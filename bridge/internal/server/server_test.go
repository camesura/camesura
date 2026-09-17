package server

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/camesura/camesura/bridge/internal/protocol"
	"github.com/camesura/camesura/bridge/internal/resetadapter"
)

type countingAdapter struct {
	calls atomic.Int32
	kinds sync.Map // resetadapter.Kind -> struct{}
	delay time.Duration
	err   error
}

func (a *countingAdapter) Name() string { return "test" }

func (a *countingAdapter) Reset(_ context.Context, kind resetadapter.Kind) error {
	a.calls.Add(1)
	a.kinds.Store(kind, struct{}{})
	time.Sleep(a.delay)
	return a.err
}

type fakeClock struct {
	mu  sync.Mutex
	now time.Time
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
}

func startServer(t *testing.T, adapter resetadapter.ResetAdapter, clock *fakeClock) net.Addr {
	t.Helper()
	conn, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	srv := New(conn, Config{
		Name:    "test-bridge",
		Adapter: adapter,
		Logger:  slog.New(slog.NewTextHandler(io.Discard, nil)),
		Now:     clock.Now,
	})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		srv.Serve(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
	return conn.LocalAddr()
}

func newClient(t *testing.T) net.PacketConn {
	t.Helper()
	conn, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return conn
}

func sendJSON(t *testing.T, client net.PacketConn, to net.Addr, v any) {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := client.WriteTo(data, to); err != nil {
		t.Fatal(err)
	}
}

func receive(t *testing.T, client net.PacketConn) (protocol.Result, bool) {
	t.Helper()
	buf := make([]byte, protocol.MaxDatagramSize)
	client.SetReadDeadline(time.Now().Add(300 * time.Millisecond))
	n, _, err := client.ReadFrom(buf)
	if err != nil {
		return protocol.Result{}, false
	}
	var res protocol.Result
	if err := json.Unmarshal(buf[:n], &res); err != nil {
		t.Fatal(err)
	}
	return res, true
}

func resetRequest(id string) protocol.Request {
	confidence := 0.9
	return protocol.Request{
		Version:    protocol.Version,
		Type:       protocol.TypeResetRequest,
		RequestID:  id,
		DeviceID:   "device-1",
		Reset:      protocol.ResetYaw,
		Pose:       protocol.PoseManual,
		StableMS:   3000,
		Confidence: &confidence,
	}
}

func TestPingReturnsPong(t *testing.T) {
	addr := startServer(t, &countingAdapter{}, &fakeClock{now: time.Unix(0, 0)})
	client := newClient(t)

	sendJSON(t, client, addr, map[string]any{"version": 1, "type": "ping", "request_id": "p1"})
	res, ok := receive(t, client)
	if !ok || res.Type != protocol.TypePong || res.RequestID != "p1" || res.Adapter != "test" {
		t.Fatalf("unexpected pong: %+v (received=%v)", res, ok)
	}
}

func TestRetriedRequestRunsAdapterOnce(t *testing.T) {
	adapter := &countingAdapter{delay: 50 * time.Millisecond}
	addr := startServer(t, adapter, &fakeClock{now: time.Unix(0, 0)})
	client := newClient(t)

	for range 3 {
		sendJSON(t, client, addr, resetRequest("r1"))
	}
	res, ok := receive(t, client)
	if !ok || res.Status != protocol.StatusOK || res.Code != protocol.CodeResetFinished {
		t.Fatalf("unexpected result: %+v (received=%v)", res, ok)
	}
	if _, extra := receive(t, client); extra {
		t.Fatal("in-flight retries should share a single result")
	}

	sendJSON(t, client, addr, resetRequest("r1"))
	cached, ok := receive(t, client)
	if !ok || cached != res {
		t.Fatalf("cached result mismatch: %+v", cached)
	}
	if got := adapter.calls.Load(); got != 1 {
		t.Fatalf("adapter called %d times, want 1", got)
	}
}

func TestCooldownPerDevice(t *testing.T) {
	adapter := &countingAdapter{}
	clock := &fakeClock{now: time.Unix(0, 0)}
	addr := startServer(t, adapter, clock)
	client := newClient(t)

	sendJSON(t, client, addr, resetRequest("r1"))
	if res, _ := receive(t, client); res.Code != protocol.CodeResetFinished {
		t.Fatalf("first request: %+v", res)
	}

	clock.Advance(time.Second)
	sendJSON(t, client, addr, resetRequest("r2"))
	if res, _ := receive(t, client); res.Code != protocol.CodeCooldown || res.Status != protocol.StatusError {
		t.Fatalf("second request: %+v", res)
	}

	clock.Advance(DefaultCooldown)
	sendJSON(t, client, addr, resetRequest("r3"))
	if res, _ := receive(t, client); res.Code != protocol.CodeResetFinished {
		t.Fatalf("third request: %+v", res)
	}
	if got := adapter.calls.Load(); got != 2 {
		t.Fatalf("adapter called %d times, want 2", got)
	}
}

func TestInvalidRequests(t *testing.T) {
	adapter := &countingAdapter{}
	addr := startServer(t, adapter, &fakeClock{now: time.Unix(0, 0)})
	client := newClient(t)

	short := resetRequest("short")
	short.StableMS = 500
	sendJSON(t, client, addr, short)
	if res, _ := receive(t, client); res.Code != protocol.CodeInvalidRequest {
		t.Fatalf("short stable_ms: %+v", res)
	}

	future := resetRequest("future")
	future.Version = 2
	sendJSON(t, client, addr, future)
	if res, _ := receive(t, client); res.Code != protocol.CodeUnsupportedVersion {
		t.Fatalf("unsupported version: %+v", res)
	}

	if _, err := client.WriteTo([]byte("{broken"), addr); err != nil {
		t.Fatal(err)
	}
	if _, ok := receive(t, client); ok {
		t.Fatal("broken JSON must not be answered")
	}
	if got := adapter.calls.Load(); got != 0 {
		t.Fatalf("adapter called %d times, want 0", got)
	}
}

func TestAdapterErrorsAreMapped(t *testing.T) {
	adapter := &countingAdapter{err: resetadapter.ErrUnavailable}
	addr := startServer(t, adapter, &fakeClock{now: time.Unix(0, 0)})
	client := newClient(t)

	sendJSON(t, client, addr, resetRequest("r1"))
	res, _ := receive(t, client)
	if res.Status != protocol.StatusError || res.Code != protocol.CodeSlimeVRUnavailable {
		t.Fatalf("unexpected result: %+v", res)
	}
}

func TestFullResetIsPassedToAdapter(t *testing.T) {
	adapter := &countingAdapter{}
	addr := startServer(t, adapter, &fakeClock{now: time.Unix(0, 0)})
	client := newClient(t)

	req := resetRequest("full-1")
	req.Reset = protocol.ResetFull
	sendJSON(t, client, addr, req)
	if res, _ := receive(t, client); res.Code != protocol.CodeResetFinished {
		t.Fatalf("full reset: %+v", res)
	}
	if _, ok := adapter.kinds.Load(resetadapter.KindFull); !ok {
		t.Fatal("adapter did not receive a full reset")
	}
}

func TestDiscoverReturnsAnnounce(t *testing.T) {
	adapter := &countingAdapter{}
	addr := startServer(t, adapter, &fakeClock{now: time.Unix(0, 0)})
	client := newClient(t)

	sendJSON(t, client, addr, map[string]any{"version": 1, "type": "discover", "request_id": "d1"})
	res, ok := receive(t, client)
	if !ok || res.Type != protocol.TypeAnnounce || res.RequestID != "d1" || res.Name != "test-bridge" {
		t.Fatalf("unexpected announce: %+v (received=%v)", res, ok)
	}
	if got := adapter.calls.Load(); got != 0 {
		t.Fatalf("discover must not reset, adapter called %d times", got)
	}
}
