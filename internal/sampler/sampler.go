package sampler

import (
	"context"
	"time"

	"github.com/Dicklesworthstone/system_resource_protection_script/internal/model"
)

// Sampler periodically emits Samples; this stub just emits zeros.
type Sampler struct {
	Interval time.Duration
}

func New(interval time.Duration) *Sampler {
	return &Sampler{Interval: interval}
}

// Stream returns a channel that will receive snapshots until ctx is done.
func (s *Sampler) Stream(ctx context.Context) <-chan model.Sample {
	ch := make(chan model.Sample)
	go func() {
		ticker := time.NewTicker(s.Interval)
		defer ticker.Stop()
		defer close(ch)
		for {
			select {
			case t := <-ticker.C:
				ch <- model.Sample{Timestamp: t, Interval: s.Interval}
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch
}
