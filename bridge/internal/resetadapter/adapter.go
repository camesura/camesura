// Package resetadapter isolates how a Yaw Reset is actually performed.
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

type ResetAdapter interface {
	Name() string
	YawReset(ctx context.Context) error
}

// Mock logs the reset instead of talking to SlimeVR.
type Mock struct {
	Logger *slog.Logger
	Delay  time.Duration
}

func (m *Mock) Name() string { return "mock" }

func (m *Mock) YawReset(ctx context.Context) error {
	if m.Delay > 0 {
		select {
		case <-time.After(m.Delay):
		case <-ctx.Done():
			return ErrTimeout
		}
	}
	if m.Logger != nil {
		m.Logger.Info("mock yaw reset finished")
	}
	return nil
}
