package config

import (
	"flag"
	"fmt"
	"os"
	"time"
)

// Config carries runtime options for sysmoni.
type Config struct {
	Interval   time.Duration
	Sort       string
	Filter     string
	JSON       bool
	JSONStream bool
	EnableGPU  bool
	EnableBatt bool
}

func Default() Config {
	return Config{
		Interval:   time.Second,
		Sort:       "cpu",
		Filter:     "",
		JSON:       false,
		JSONStream: false,
		EnableGPU:  true,
		EnableBatt: true,
	}
}

// IntervalError reports a nonpositive sampling interval, which would otherwise
// panic in time.NewTicker.
type IntervalError struct {
	Interval time.Duration
}

func (e *IntervalError) Error() string {
	return fmt.Sprintf("sysmoni: interval must be positive, got %s (from --interval or SRPS_SYSMONI_INTERVAL)", e.Interval)
}

// FromFlags parses flags and environment overrides.
//
// It returns flag.ErrHelp after printing usage for -h/--help, the parse error
// (already printed with usage) for an unknown or malformed flag, and an error
// for a nonpositive interval from either the flag or SRPS_SYSMONI_INTERVAL.
// Callers must not start sampling when err != nil (#6).
func FromFlags(args []string) (Config, error) {
	cfg := Default()
	fs := flag.NewFlagSet("sysmoni", flag.ContinueOnError)
	fs.DurationVar(&cfg.Interval, "interval", cfg.Interval, "refresh interval")
	fs.StringVar(&cfg.Sort, "sort", cfg.Sort, "sort column: cpu|mem")
	fs.StringVar(&cfg.Filter, "filter", cfg.Filter, "regex filter for process names")
	fs.BoolVar(&cfg.JSON, "json", cfg.JSON, "output one-shot JSON and exit")
	fs.BoolVar(&cfg.JSONStream, "json-stream", cfg.JSONStream, "stream NDJSON until interrupted")
	fs.BoolVar(&cfg.EnableGPU, "gpu", cfg.EnableGPU, "enable GPU sampling")
	fs.BoolVar(&cfg.EnableBatt, "battery", cfg.EnableBatt, "enable battery sampling")
	if err := fs.Parse(args); err != nil {
		return cfg, err
	}

	if v := os.Getenv("SRPS_SYSMONI_INTERVAL"); v != "" {
		if parsed, err := time.ParseDuration(v); err == nil {
			cfg.Interval = parsed
		} else if parsed, err2 := time.ParseDuration(v + "s"); err2 == nil {
			cfg.Interval = parsed
		}
	}
	if cfg.Interval <= 0 {
		return cfg, &IntervalError{Interval: cfg.Interval}
	}
	if v := os.Getenv("SRPS_SYSMONI_GPU"); v == "0" {
		cfg.EnableGPU = false
	}
	if v := os.Getenv("SRPS_SYSMONI_BATT"); v == "0" {
		cfg.EnableBatt = false
	}
	return cfg, nil
}
