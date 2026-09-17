package resetadapter

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	flatbuffers "github.com/google/flatbuffers/go"
	"github.com/gorilla/websocket"

	"github.com/camesura/camesura/bridge/internal/solarxr/solarxr_protocol"
	"github.com/camesura/camesura/bridge/internal/solarxr/solarxr_protocol/datatypes"
	"github.com/camesura/camesura/bridge/internal/solarxr/solarxr_protocol/rpc"
)

// fakeSlimeVRServer answers SolarXR ResetRequest RPCs like a real SlimeVR
// Server would, without needing SlimeVR itself.
type fakeSlimeVRServer struct {
	*httptest.Server
	respond func(txID uint32, resetType rpc.ResetType) (rpc.ResetStatus, bool)
	// reply chooses the reset type echoed back; defaults to the requested one.
	reply func(txID uint32, resetType rpc.ResetType) rpc.ResetType
}

func newFakeSlimeVRServer(t *testing.T) *fakeSlimeVRServer {
	t.Helper()
	upgrader := websocket.Upgrader{}
	fake := &fakeSlimeVRServer{
		respond: func(uint32, rpc.ResetType) (rpc.ResetStatus, bool) {
			return rpc.ResetStatusFINISHED, true
		},
	}
	fake.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		for {
			msgType, data, err := conn.ReadMessage()
			if err != nil {
				return
			}
			if msgType != websocket.BinaryMessage {
				continue
			}
			bundle := solarxr_protocol.GetRootAsMessageBundle(data, 0)
			var header rpc.RpcMessageHeader
			for i := 0; i < bundle.RpcMsgsLength(); i++ {
				if !bundle.RpcMsgs(&header, i) || header.MessageType() != rpc.RpcMessageResetRequest {
					continue
				}
				var table flatbuffers.Table
				if !header.Message(&table) {
					continue
				}
				var req rpc.ResetRequest
				req.Init(table.Bytes, table.Pos)
				txID := header.TxId(nil)
				if txID == nil {
					continue
				}
				status, ok := fake.respond(txID.Id(), req.ResetType())
				if !ok {
					continue
				}
				replyType := req.ResetType()
				if fake.reply != nil {
					replyType = fake.reply(txID.Id(), replyType)
				}
				reply := buildResetResponse(txID.Id(), replyType, status)
				if err := conn.WriteMessage(websocket.BinaryMessage, reply); err != nil {
					return
				}
			}
		}
	}))
	t.Cleanup(fake.Close)
	return fake
}

func buildResetResponse(txID uint32, resetType rpc.ResetType, status rpc.ResetStatus) []byte {
	builder := flatbuffers.NewBuilder(64)

	rpc.ResetResponseStart(builder)
	rpc.ResetResponseAddResetType(builder, resetType)
	rpc.ResetResponseAddStatus(builder, status)
	resetResponse := rpc.ResetResponseEnd(builder)

	rpc.RpcMessageHeaderStart(builder)
	txIDStruct := datatypes.CreateTransactionId(builder, txID)
	rpc.RpcMessageHeaderAddTxId(builder, txIDStruct)
	rpc.RpcMessageHeaderAddMessageType(builder, rpc.RpcMessageResetResponse)
	rpc.RpcMessageHeaderAddMessage(builder, resetResponse)
	header := rpc.RpcMessageHeaderEnd(builder)

	solarxr_protocol.MessageBundleStartRpcMsgsVector(builder, 1)
	builder.PrependUOffsetT(header)
	rpcMsgsVec := builder.EndVector(1)

	solarxr_protocol.MessageBundleStart(builder)
	solarxr_protocol.MessageBundleAddRpcMsgs(builder, rpcMsgsVec)
	bundle := solarxr_protocol.MessageBundleEnd(builder)
	builder.Finish(bundle)

	return builder.FinishedBytes()
}

func wsURL(server *httptest.Server) string {
	return "ws" + strings.TrimPrefix(server.URL, "http")
}

func discardLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func TestSlimeVRResetFinishes(t *testing.T) {
	fake := newFakeSlimeVRServer(t)
	adapter := NewSlimeVR(wsURL(fake.Server), discardLogger())
	defer adapter.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if err := adapter.Reset(ctx, KindYaw); err != nil {
		t.Fatalf("Reset() = %v, want nil", err)
	}
}

func TestSlimeVRResetTimesOut(t *testing.T) {
	fake := newFakeSlimeVRServer(t)
	fake.respond = func(uint32, rpc.ResetType) (rpc.ResetStatus, bool) {
		return 0, false // never reply
	}
	adapter := NewSlimeVR(wsURL(fake.Server), discardLogger())
	defer adapter.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()

	if err := adapter.Reset(ctx, KindYaw); err != ErrTimeout {
		t.Fatalf("Reset() = %v, want ErrTimeout", err)
	}
}

func TestSlimeVRUnavailable(t *testing.T) {
	adapter := NewSlimeVR("ws://127.0.0.1:1", discardLogger())
	defer adapter.Close()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	err := adapter.Reset(ctx, KindYaw)
	if err == nil {
		t.Fatal("Reset() = nil, want an error")
	}
}

func TestSlimeVRReusesConnectionAcrossRequests(t *testing.T) {
	fake := newFakeSlimeVRServer(t)
	adapter := NewSlimeVR(wsURL(fake.Server), discardLogger())
	defer adapter.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if err := adapter.Reset(ctx, KindYaw); err != nil {
		t.Fatalf("first Reset() = %v, want nil", err)
	}
	if err := adapter.Reset(ctx, KindFull); err != nil {
		t.Fatalf("second Reset() = %v, want nil", err)
	}
}

func TestSlimeVRIgnoresResponseOfOtherResetType(t *testing.T) {
	fake := newFakeSlimeVRServer(t)
	fake.reply = func(_ uint32, requested rpc.ResetType) rpc.ResetType {
		if requested == rpc.ResetTypeFull {
			return rpc.ResetTypeYaw
		}
		return requested
	}
	adapter := NewSlimeVR(wsURL(fake.Server), discardLogger())
	defer adapter.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()

	if err := adapter.Reset(ctx, KindFull); err != ErrTimeout {
		t.Fatalf("Reset() = %v, want ErrTimeout", err)
	}
}
