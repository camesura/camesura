// Package resetadapter isolates how a reset is actually performed.
package resetadapter

import (
	"context"
	"errors"
	"log/slog"
	"time"
)

var (
	// ErrUnavailable means the reset target (SlimeVR Server) is not reachable.
	ErrUnavailable = errors.New("reset target unavailable")
	// ErrTimeout means the reset target did not report completion in time.
	ErrTimeout = errors.New("reset target timed out")
)

// Kind is the reset requested by the mobile app.
type Kind string

const (
	KindYaw  Kind = "yaw"
	KindFull Kind = "full"
)

type ResetAdapter interface {
	Name() string
	Reset(ctx context.Context, kind Kind) error
}

// Mock logs the reset instead of talking to SlimeVR.
type Mock struct {
	Logger *slog.Logger
	Delay  time.Duration
}

func (m *Mock) Name() string { return "mock" }

func (m *Mock) Reset(ctx context.Context, kind Kind) error {
	if m.Delay > 0 {
		select {
		case <-time.After(m.Delay):
		case <-ctx.Done():
			return ErrTimeout
		}
	}
	if m.Logger != nil {
		m.Logger.Info("mock reset finished", "kind", kind)
	}
	return nil
}
