package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"github.com/Dicklesworthstone/system_resource_protection_script/internal/config"
	"github.com/Dicklesworthstone/system_resource_protection_script/internal/sampler"
	"github.com/Dicklesworthstone/system_resource_protection_script/internal/ui"
)

func main() {
	cfg := config.FromFlags(os.Args[1:])

	// JSON/NDJSON modes
	if cfg.JSON || cfg.JSONStream || !isTTY() {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		s := sampler.New(cfg.Interval)
		out := json.NewEncoder(os.Stdout)
		for samp := range s.Stream(ctx) {
			_ = out.Encode(samp)
			if !cfg.JSONStream {
				return
			}
		}
		return
	}

	if err := ui.RunTUI(cfg); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// isTTY is a tiny check to avoid pulling in extra deps; good enough for now.
func isTTY() bool {
	fi, err := os.Stdout.Stat()
	if err != nil {
		return false
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}
