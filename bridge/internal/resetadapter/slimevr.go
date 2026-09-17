package resetadapter

import (
	"context"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"sync"
	"time"

	flatbuffers "github.com/google/flatbuffers/go"
	"github.com/gorilla/websocket"

	"github.com/camesura/camesura/bridge/internal/solarxr/solarxr_protocol"
	"github.com/camesura/camesura/bridge/internal/solarxr/solarxr_protocol/datatypes"
	"github.com/camesura/camesura/bridge/internal/solarxr/solarxr_protocol/rpc"
)

// DefaultSlimeVRURL is the SlimeVR Server WebSocket endpoint. It is loopback-only:
// the Bridge never exposes SlimeVR's port 21110 beyond this machine.
const DefaultSlimeVRURL = "ws://127.0.0.1:21110"

// SlimeVR sends a ResetRequest over the SolarXR Protocol WebSocket/FlatBuffers
// API (see docs/camesura-spec.md §8) and waits for the matching ResetResponse.
//
// The connection is dialed lazily and kept alive across calls; it redials once
// after any read/write/dial failure.
type SlimeVR struct {
	URL    string
	Logger *slog.Logger

	mu       sync.Mutex
	conn     *websocket.Conn
	waiters  map[uint32]waiter
	statuses map[uint32]rpc.ResetStatus
}

func NewSlimeVR(url string, logger *slog.Logger) *SlimeVR {
	if url == "" {
		url = DefaultSlimeVRURL
	}
	if logger == nil {
		logger = slog.Default()
	}
	return &SlimeVR{
		URL:      url,
		Logger:   logger,
		waiters:  map[uint32]waiter{},
		statuses: map[uint32]rpc.ResetStatus{},
	}
}

func (s *SlimeVR) Name() string { return "slimevr" }

func (s *SlimeVR) Reset(ctx context.Context, kind Kind) error {
	resetType, err := solarXRResetType(kind)
	if err != nil {
		return err
	}
	conn, err := s.connection(ctx)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrUnavailable, err)
	}

	txID := rand.Uint32()
	done := make(chan struct{})
	s.mu.Lock()
	s.waiters[txID] = waiter{done: done, resetType: resetType}
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(s.waiters, txID)
		delete(s.statuses, txID)
		s.mu.Unlock()
	}()

	if err := s.sendResetRequest(conn, txID, resetType); err != nil {
		s.dropConnection(conn)
		return fmt.Errorf("%w: %v", ErrUnavailable, err)
	}

	select {
	case <-done:
		s.mu.Lock()
		status := s.statuses[txID]
		s.mu.Unlock()
		if status != rpc.ResetStatusFINISHED {
			return fmt.Errorf("%w: unexpected reset status %v", ErrUnavailable, status)
		}
		return nil
	case <-ctx.Done():
		return ErrTimeout
	}
}

// connection returns the current WebSocket connection, dialing one and
// starting its read loop if needed.
func (s *SlimeVR) connection(ctx context.Context) (*websocket.Conn, error) {
	s.mu.Lock()
	if s.conn != nil {
		conn := s.conn
		s.mu.Unlock()
		return conn, nil
	}
	s.mu.Unlock()

	dialer := websocket.Dialer{HandshakeTimeout: 5 * time.Second}
	conn, resp, err := dialer.DialContext(ctx, s.URL, nil)
	if err != nil {
		return nil, err
	}
	if resp != nil && resp.Body != nil {
		_ = resp.Body.Close()
	}
	if resp != nil && resp.StatusCode != http.StatusSwitchingProtocols {
		_ = conn.Close()
		return nil, fmt.Errorf("unexpected handshake status %d", resp.StatusCode)
	}

	s.mu.Lock()
	s.conn = conn
	s.mu.Unlock()

	go s.readLoop(conn)
	return conn, nil
}

func (s *SlimeVR) dropConnection(conn *websocket.Conn) {
	s.mu.Lock()
	if s.conn == conn {
		s.conn = nil
	}
	s.mu.Unlock()
	_ = conn.Close()
}

func (s *SlimeVR) sendResetRequest(conn *websocket.Conn, txID uint32, resetType rpc.ResetType) error {
	builder := flatbuffers.NewBuilder(64)

	rpc.ResetRequestStart(builder)
	rpc.ResetRequestAddResetType(builder, resetType)
	rpc.ResetRequestAddDelay(builder, 0)
	resetRequest := rpc.ResetRequestEnd(builder)

	// TransactionId is a struct: it must be built right before the field that
	// references it, since flatbuffers writes structs inline at the current
	// builder position rather than as a separate offset table.
	rpc.RpcMessageHeaderStart(builder)
	txIDStruct := datatypes.CreateTransactionId(builder, txID)
	rpc.RpcMessageHeaderAddTxId(builder, txIDStruct)
	rpc.RpcMessageHeaderAddMessageType(builder, rpc.RpcMessageResetRequest)
	rpc.RpcMessageHeaderAddMessage(builder, resetRequest)
	header := rpc.RpcMessageHeaderEnd(builder)

	solarxr_protocol.MessageBundleStartRpcMsgsVector(builder, 1)
	builder.PrependUOffsetT(header)
	rpcMsgsVec := builder.EndVector(1)

	solarxr_protocol.MessageBundleStart(builder)
	solarxr_protocol.MessageBundleAddRpcMsgs(builder, rpcMsgsVec)
	bundle := solarxr_protocol.MessageBundleEnd(builder)
	builder.Finish(bundle)

	s.Logger.Info("sending SlimeVR reset", "tx_id", txID, "reset_type", resetType)
	return conn.WriteMessage(websocket.BinaryMessage, builder.FinishedBytes())
}

func (s *SlimeVR) readLoop(conn *websocket.Conn) {
	defer s.dropConnection(conn)
	for {
		msgType, data, err := conn.ReadMessage()
		if err != nil {
			s.Logger.Warn("SlimeVR connection closed", "error", err)
			return
		}
		if msgType != websocket.BinaryMessage {
			continue
		}
		s.handleBundle(data)
	}
}

func (s *SlimeVR) handleBundle(data []byte) {
	defer func() {
		// A malformed frame from the server must not crash the read loop.
		if r := recover(); r != nil {
			s.Logger.Warn("dropped malformed SolarXR frame", "error", r)
		}
	}()

	bundle := solarxr_protocol.GetRootAsMessageBundle(data, 0)
	var msgHeader rpc.RpcMessageHeader
	for i := 0; i < bundle.RpcMsgsLength(); i++ {
		if !bundle.RpcMsgs(&msgHeader, i) {
			continue
		}
		if msgHeader.MessageType() != rpc.RpcMessageResetResponse {
			continue
		}
		var table flatbuffers.Table
		if !msgHeader.Message(&table) {
			continue
		}
		var resetResponse rpc.ResetResponse
		resetResponse.Init(table.Bytes, table.Pos)
		txID := msgHeader.TxId(nil)
		if txID == nil {
			continue
		}
		s.deliver(txID.Id(), resetResponse.ResetType(), resetResponse.Status())
	}
}

// deliver completes the waiter whose tx_id and reset type both match.
func (s *SlimeVR) deliver(txID uint32, resetType rpc.ResetType, status rpc.ResetStatus) {
	s.mu.Lock()
	w, ok := s.waiters[txID]
	ok = ok && w.resetType == resetType
	if ok {
		s.statuses[txID] = status
	}
	s.mu.Unlock()
	if !ok || status != rpc.ResetStatusFINISHED {
		return
	}
	close(w.done)
}

type waiter struct {
	done      chan struct{}
	resetType rpc.ResetType
}

func solarXRResetType(kind Kind) (rpc.ResetType, error) {
	switch kind {
	case KindYaw:
		return rpc.ResetTypeYaw, nil
	case KindFull:
		return rpc.ResetTypeFull, nil
	}
	return 0, fmt.Errorf("unsupported reset kind %q", kind)
}

// Close releases the SlimeVR connection, if any.
func (s *SlimeVR) Close() error {
	s.mu.Lock()
	conn := s.conn
	s.conn = nil
	s.mu.Unlock()
	if conn == nil {
		return nil
	}
	return conn.Close()
}
