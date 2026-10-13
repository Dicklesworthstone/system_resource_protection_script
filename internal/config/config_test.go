package config

import (
	"errors"
	"flag"
	"testing"
	"time"
)

func TestFromFlagsHelpReturnsErrHelp(t *testing.T) {
	for _, args := range [][]string{{"--help"}, {"-h"}} {
		if _, err := FromFlags(args); !errors.Is(err, flag.ErrHelp) {
			t.Fatalf("FromFlags(%q) err = %v, want flag.ErrHelp", args, err)
		}
	}
}

func TestFromFlagsUnknownFlagIsAnError(t *testing.T) {
	_, err := FromFlags([]string{"--json", "--definitely-invalid"})
	if err == nil || errors.Is(err, flag.ErrHelp) {
		t.Fatalf("err = %v, want a parse error", err)
	}
	var ie *IntervalError
	if errors.As(err, &ie) {
		t.Fatalf("err = %v, want a flag parse error, not an IntervalError", err)
	}
}

func TestFromFlagsRejectsNonpositiveInterval(t *testing.T) {
	t.Setenv("SRPS_SYSMONI_INTERVAL", "")
	for _, args := range [][]string{{"--interval=0"}, {"--interval=-1s"}, {"--json", "--interval", "0s"}} {
		_, err := FromFlags(args)
		var ie *IntervalError
		if !errors.As(err, &ie) {
			t.Fatalf("FromFlags(%q) err = %v, want *IntervalError", args, err)
		}
	}
}

func TestFromFlagsRejectsNonpositiveEnvInterval(t *testing.T) {
	for _, v := range []string{"0", "0s", "-5"} {
		t.Setenv("SRPS_SYSMONI_INTERVAL", v)
		_, err := FromFlags([]string{"--json"})
		var ie *IntervalError
		if !errors.As(err, &ie) {
			t.Fatalf("SRPS_SYSMONI_INTERVAL=%q err = %v, want *IntervalError", v, err)
		}
	}
}

func TestFromFlagsValidInputs(t *testing.T) {
	t.Setenv("SRPS_SYSMONI_INTERVAL", "")
	cfg, err := FromFlags([]string{"--json", "--interval=10ms"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !cfg.JSON || cfg.Interval != 10*time.Millisecond {
		t.Fatalf("cfg = %+v, want JSON and 10ms", cfg)
	}

	// A bare number in the environment means seconds, as before.
	t.Setenv("SRPS_SYSMONI_INTERVAL", "2")
	cfg, err = FromFlags(nil)
	if err != nil || cfg.Interval != 2*time.Second {
		t.Fatalf("env 2: cfg.Interval = %v err = %v, want 2s", cfg.Interval, err)
	}

	// The default stays valid.
	t.Setenv("SRPS_SYSMONI_INTERVAL", "")
	if cfg, err = FromFlags(nil); err != nil || cfg.Interval != time.Second {
		t.Fatalf("default: cfg.Interval = %v err = %v, want 1s", cfg.Interval, err)
	}
}
