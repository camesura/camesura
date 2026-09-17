// Package server receives reset requests from the mobile app over UDP.
package server

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"sync"
	"time"

	"github.com/camesura/camesura/bridge/internal/protocol"
	"github.com/camesura/camesura/bridge/internal/resetadapter"
)

const (
	DefaultCooldown     = 3 * time.Second
	DefaultResultTTL    = 5 * time.Minute
	DefaultResetTimeout = 10 * time.Second
)

type Config struct {
	// Name identifies this Bridge in discovery replies (usually the host name).
	Name         string
	Adapter      resetadapter.ResetAdapter
	Logger       *slog.Logger
	Cooldown     time.Duration
	ResultTTL    time.Duration
	ResetTimeout time.Duration
	Now          func() time.Time
}

type cachedResult struct {
	result    protocol.Result
	expiresAt time.Time
}

type Server struct {
	cfg  Config
	conn net.PacketConn
	wg   sync.WaitGroup

	mu           sync.Mutex
	results      map[string]cachedResult
	inflight     map[string][]net.Addr
	lastAccepted map[string]time.Time
}

func New(conn net.PacketConn, cfg Config) *Server {
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	if cfg.Cooldown == 0 {
		cfg.Cooldown = DefaultCooldown
	}
	if cfg.ResultTTL == 0 {
		cfg.ResultTTL = DefaultResultTTL
	}
	if cfg.ResetTimeout == 0 {
		cfg.ResetTimeout = DefaultResetTimeout
	}
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	return &Server{
		cfg:          cfg,
		conn:         conn,
		results:      map[string]cachedResult{},
		inflight:     map[string][]net.Addr{},
		lastAccepted: map[string]time.Time{},
	}
}

// Serve handles datagrams until ctx is cancelled or the connection fails.
func (s *Server) Serve(ctx context.Context) error {
	stop := context.AfterFunc(ctx, func() { s.conn.Close() })
	defer stop()
	defer s.wg.Wait()

	buf := make([]byte, protocol.MaxDatagramSize+1)
	for {
		n, addr, err := s.conn.ReadFrom(buf)
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		if n > protocol.MaxDatagramSize {
			s.cfg.Logger.Warn("dropped oversized datagram", "from", addr, "bytes", n)
			continue
		}
		s.handle(ctx, buf[:n], addr)
	}
}

func (s *Server) handle(ctx context.Context, data []byte, addr net.Addr) {
	var req protocol.Request
	if err := json.Unmarshal(data, &req); err != nil || req.RequestID == "" {
		s.cfg.Logger.Warn("dropped malformed datagram", "from", addr, "error", err)
		return
	}
	if req.Version == protocol.Version {
		switch req.Type {
		case protocol.TypePing, protocol.TypeDiscover:
			replyType := protocol.TypePong
			if req.Type == protocol.TypeDiscover {
				replyType = protocol.TypeAnnounce
			}
			s.cfg.Logger.Info(req.Type, "from", addr)
			res := s.result(replyType, req.RequestID, nil, protocol.CodeBridgeReady, "Bridge is ready")
			res.Name = s.cfg.Name
			s.send(res, addr)
			return
		}
	}
	s.handleReset(ctx, req, addr)
}

func (s *Server) handleReset(ctx context.Context, req protocol.Request, addr net.Addr) {
	now := s.cfg.Now()

	s.mu.Lock()
	s.pruneLocked(now)
	if cached, ok := s.results[req.RequestID]; ok {
		s.mu.Unlock()
		s.send(cached.result, addr)
		return
	}
	if waiters, ok := s.inflight[req.RequestID]; ok {
		s.inflight[req.RequestID] = appendAddr(waiters, addr)
		s.mu.Unlock()
		return
	}
	if verr := protocol.ValidateResetRequest(req); verr != nil {
		res := s.cacheLocked(req.RequestID, verr, verr.Code, verr.Message, now)
		s.mu.Unlock()
		s.cfg.Logger.Warn("rejected reset request", "from", addr, "code", verr.Code, "message", verr.Message)
		s.send(res, addr)
		return
	}
	if last, ok := s.lastAccepted[req.DeviceID]; ok && now.Sub(last) < s.cfg.Cooldown {
		res := s.cacheLocked(req.RequestID, errCooldown, protocol.CodeCooldown, "Reset is cooling down", now)
		s.mu.Unlock()
		s.cfg.Logger.Warn("reset request in cooldown", "from", addr, "device_id", req.DeviceID)
		s.send(res, addr)
		return
	}
	s.lastAccepted[req.DeviceID] = now
	s.inflight[req.RequestID] = []net.Addr{addr}
	s.mu.Unlock()

	s.cfg.Logger.Info("reset request accepted",
		"from", addr, "request_id", req.RequestID, "device_id", req.DeviceID,
		"reset", req.Reset, "pose", req.Pose, "stable_ms", req.StableMS)

	s.wg.Go(func() { s.runReset(ctx, req.RequestID, resetadapter.Kind(req.Reset)) })
}

var errCooldown = errors.New("cooldown")

func (s *Server) runReset(ctx context.Context, requestID string, kind resetadapter.Kind) {
	resetCtx, cancel := context.WithTimeout(ctx, s.cfg.ResetTimeout)
	defer cancel()
	err := s.cfg.Adapter.Reset(resetCtx, kind)

	code, message := protocol.CodeResetFinished, "Reset finished"
	switch {
	case err == nil:
	case errors.Is(err, resetadapter.ErrUnavailable):
		code, message = protocol.CodeSlimeVRUnavailable, err.Error()
	case errors.Is(err, resetadapter.ErrTimeout), errors.Is(err, context.DeadlineExceeded):
		code, message = protocol.CodeSlimeVRTimeout, err.Error()
	default:
		code, message = protocol.CodeAdapterError, err.Error()
	}
	if err != nil {
		s.cfg.Logger.Error("reset failed", "request_id", requestID, "kind", kind, "code", code, "error", err)
	}

	s.mu.Lock()
	res := s.cacheLocked(requestID, err, code, message, s.cfg.Now())
	waiters := s.inflight[requestID]
	delete(s.inflight, requestID)
	s.mu.Unlock()

	for _, addr := range waiters {
		s.send(res, addr)
	}
}

func (s *Server) result(typ, requestID string, err error, code, message string) protocol.Result {
	status := protocol.StatusOK
	if err != nil {
		status = protocol.StatusError
	}
	return protocol.Result{
		Version:   protocol.Version,
		Type:      typ,
		RequestID: requestID,
		Status:    status,
		Code:      code,
		Adapter:   s.cfg.Adapter.Name(),
		Message:   message,
	}
}

func (s *Server) cacheLocked(requestID string, err error, code, message string, now time.Time) protocol.Result {
	res := s.result(protocol.TypeResetResult, requestID, err, code, message)
	s.results[requestID] = cachedResult{result: res, expiresAt: now.Add(s.cfg.ResultTTL)}
	return res
}

func (s *Server) pruneLocked(now time.Time) {
	for id, c := range s.results {
		if !now.Before(c.expiresAt) {
			delete(s.results, id)
		}
	}
	for device, last := range s.lastAccepted {
		if now.Sub(last) >= s.cfg.Cooldown {
			delete(s.lastAccepted, device)
		}
	}
}

func (s *Server) send(res protocol.Result, addr net.Addr) {
	data, err := json.Marshal(res)
	if err != nil {
		s.cfg.Logger.Error("failed to encode result", "error", err)
		return
	}
	if _, err := s.conn.WriteTo(data, addr); err != nil {
		s.cfg.Logger.Warn("failed to send result", "to", addr, "error", err)
	}
}

func appendAddr(addrs []net.Addr, addr net.Addr) []net.Addr {
	for _, a := range addrs {
		if a.String() == addr.String() {
			return addrs
		}
	}
	return append(addrs, addr)
}
