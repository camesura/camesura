// Package protocol defines the Mobile -> Bridge UDP/JSON messages.
package protocol

import "fmt"

const (
	Version         = 1
	DefaultPort     = 39500
	MaxDatagramSize = 4 * 1024

	TypeResetRequest = "reset_request"
	TypeResetResult  = "reset_result"
	TypePing         = "ping"
	TypePong         = "pong"

	ResetYaw  = "yaw"
	ResetFull = "full"

	PoseAPose  = "a_pose"
	PoseManual = "manual"

	MinStableMS = 2000

	StatusOK    = "ok"
	StatusError = "error"

	CodeResetFinished      = "reset_finished"
	CodeInvalidRequest     = "invalid_request"
	CodeUnsupportedVersion = "unsupported_version"
	CodeCooldown           = "cooldown"
	CodeSlimeVRUnavailable = "slimevr_unavailable"
	CodeSlimeVRTimeout     = "slimevr_timeout"
	CodeAdapterError       = "adapter_error"
	CodeBridgeReady        = "bridge_ready"
)

// Request is a message sent from the mobile app.
// ping uses only Version, Type and RequestID.
type Request struct {
	Version    int      `json:"version"`
	Type       string   `json:"type"`
	RequestID  string   `json:"request_id"`
	DeviceID   string   `json:"device_id"`
	Reset      string   `json:"reset"`
	Pose       string   `json:"pose"`
	StableMS   int64    `json:"stable_ms"`
	Confidence *float64 `json:"confidence"`
}

// Result is a reset_result or pong sent back to the mobile app.
type Result struct {
	Version   int    `json:"version"`
	Type      string `json:"type"`
	RequestID string `json:"request_id"`
	Status    string `json:"status"`
	Code      string `json:"code"`
	Adapter   string `json:"adapter"`
	Message   string `json:"message"`
}

// ValidationError carries the reset_result code for a rejected request.
type ValidationError struct {
	Code    string
	Message string
}

func (e *ValidationError) Error() string { return e.Code + ": " + e.Message }

// ValidateResetRequest checks a reset_request. It returns nil when valid.
func ValidateResetRequest(r Request) *ValidationError {
	invalid := func(format string, args ...any) *ValidationError {
		return &ValidationError{Code: CodeInvalidRequest, Message: fmt.Sprintf(format, args...)}
	}
	switch {
	case r.Version != Version:
		return &ValidationError{
			Code:    CodeUnsupportedVersion,
			Message: fmt.Sprintf("unsupported version %d", r.Version),
		}
	case r.Type != TypeResetRequest:
		return invalid("unexpected type %q", r.Type)
	case r.RequestID == "":
		return invalid("request_id is empty")
	case r.DeviceID == "":
		return invalid("device_id is empty")
	case r.Reset != ResetYaw && r.Reset != ResetFull:
		return invalid("unsupported reset %q", r.Reset)
	case r.Pose != PoseAPose && r.Pose != PoseManual:
		return invalid("unsupported pose %q", r.Pose)
	case r.StableMS < MinStableMS:
		return invalid("stable_ms must be >= %d", MinStableMS)
	case r.Confidence == nil || *r.Confidence < 0 || *r.Confidence > 1:
		return invalid("confidence must be within 0.0..1.0")
	}
	return nil
}
