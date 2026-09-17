package protocol

import "testing"

func validRequest() Request {
	confidence := 0.91
	return Request{
		Version:    Version,
		Type:       TypeResetRequest,
		RequestID:  "req-1",
		DeviceID:   "device-1",
		Reset:      ResetYaw,
		Pose:       PoseAPose,
		StableMS:   2180,
		Confidence: &confidence,
	}
}

func TestValidateResetRequest(t *testing.T) {
	outOfRange := 1.5
	tests := []struct {
		name   string
		modify func(*Request)
		code   string
	}{
		{"valid a_pose", func(*Request) {}, ""},
		{"valid manual", func(r *Request) { r.Pose = PoseManual }, ""},
		{"version", func(r *Request) { r.Version = 2 }, CodeUnsupportedVersion},
		{"type", func(r *Request) { r.Type = "hello" }, CodeInvalidRequest},
		{"device_id", func(r *Request) { r.DeviceID = "" }, CodeInvalidRequest},
		{"reset", func(r *Request) { r.Reset = "full" }, CodeInvalidRequest},
		{"pose", func(r *Request) { r.Pose = "t_pose" }, CodeInvalidRequest},
		{"stable_ms", func(r *Request) { r.StableMS = 1999 }, CodeInvalidRequest},
		{"missing confidence", func(r *Request) { r.Confidence = nil }, CodeInvalidRequest},
		{"confidence range", func(r *Request) { r.Confidence = &outOfRange }, CodeInvalidRequest},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := validRequest()
			tt.modify(&req)
			err := ValidateResetRequest(req)
			switch {
			case tt.code == "" && err != nil:
				t.Fatalf("unexpected error: %v", err)
			case tt.code != "" && (err == nil || err.Code != tt.code):
				t.Fatalf("got %v, want code %s", err, tt.code)
			}
		})
	}
}
