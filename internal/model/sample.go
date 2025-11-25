package model

import "time"

// CPU aggregates instantaneous CPU usage.
type CPU struct {
	Total   float64   // percent 0-100
	PerCore []float64 // per-core percent
	Load1   float64
	Load5   float64
	Load15  float64
}

// Memory captures RAM and swap usage in bytes for precision.
type Memory struct {
	UsedBytes  uint64
	TotalBytes uint64
	SwapUsed   uint64
	SwapTotal  uint64
}

// IO holds disk and network throughput numbers.
type IO struct {
	DiskReadMBs  float64
	DiskWriteMBs float64
	NetRxMbps    float64
	NetTxMbps    float64
}

// GPU holds a single device snapshot.
type GPU struct {
	Name       string
	Util       float64 // percent
	MemUsedMB  float64
	MemTotalMB float64
	TempC      float64
}

// Battery shows power state; absent if Percent == 0 and State is empty.
type Battery struct {
	Percent          float64
	State            string
	SecondsRemaining int64
}

// Process is a lightweight top entry.
type Process struct {
	PID      int
	Nice     int
	CPU      float64
	Memory   float64
	Command  string
	FDCount  int
	ReadKBs  float64
	WriteKBs float64
}

// Cgroup summarizes CPU usage by unit/name.
type Cgroup struct {
	Name string
	CPU  float64
}

// Inotify collects watch stats.
type Inotify struct {
	MaxUserWatches   uint64
	MaxUserInstances uint64
	NrWatches        uint64
}

// Temp is a thermal sensor reading.
type Temp struct {
	Zone string
	Temp float64
}

// Sample is the full snapshot exchanged between sampler, UI, and JSON exporter.
type Sample struct {
	Timestamp time.Time
	Interval  time.Duration
	CPU       CPU
	Memory    Memory
	IO        IO
	GPUs      []GPU
	Battery   Battery
	Top       []Process
	Throttled []Process
	Cgroups   []Cgroup
	Inotify   Inotify
	Temps     []Temp
}

// Zero returns an empty sample for initialization.
func Zero() Sample { return Sample{Timestamp: time.Now()} }
