package sampler

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/Dicklesworthstone/system_resource_protection_script/internal/model"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/load"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
	"github.com/shirou/gopsutil/v3/process"
)

// Sampler periodically emits Samples built from procfs and best-effort GPU/Batt reads.
type Sampler struct {
	Interval time.Duration

	prevTotal  float64
	prevIdle   float64
	prevCore   []cpu.TimesStat
	prevDisk   map[string]disk.IOCountersStat
	prevNet    []net.IOCountersStat
	prevProcIO map[int]procIO

	// Cgroup cache
	cgroupCache map[int]string
	cacheTick   int

	// GPU async
	gpuData []model.GPU
	gpuMu   sync.RWMutex
}

func New(interval time.Duration) *Sampler {
	return &Sampler{
		Interval:    interval,
		prevDisk:    make(map[string]disk.IOCountersStat),
		prevProcIO:  make(map[int]procIO),
		cgroupCache: make(map[int]string),
	}
}

type procIO struct {
	read  uint64
	write uint64
}

// Stream returns a channel that will receive snapshots until ctx is done.
func (s *Sampler) Stream(ctx context.Context) <-chan model.Sample {
	ch := make(chan model.Sample)
	go s.gpuLoop(ctx)
	go func() {
		ticker := time.NewTicker(s.Interval)
		defer ticker.Stop()
		defer close(ch)
		for {
			select {
			case t := <-ticker.C:
				ch <- s.sample(t)
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch
}

func (s *Sampler) sample(now time.Time) model.Sample {
	memStat, _ := mem.VirtualMemory()
	swapStat, _ := mem.SwapMemory()

	cpuPct, corePct := s.cpuPercents()
	loadAvg, _ := load.Avg()

	ioStat := s.ioNet()

	// Clear cgroup cache occasionally (every ~60 ticks) to handle PID reuse
	s.cacheTick++
	if s.cacheTick > 60 {
		s.cgroupCache = make(map[int]string)
		s.cacheTick = 0
	}
	top, throttled, cgroups := s.topProcs()

	s.gpuMu.RLock()
	gpus := s.gpuData
	s.gpuMu.RUnlock()

	batt := s.battery()
	inotify := s.inotify()
	temps := s.temps()

	return model.Sample{
		Timestamp: now,
		Interval:  s.Interval,
		CPU: model.CPU{
			Total:   cpuPct,
			PerCore: corePct,
			Load1:   loadAvg.Load1,
			Load5:   loadAvg.Load5,
			Load15:  loadAvg.Load15,
		},
		Memory: model.Memory{
			UsedBytes:  memStat.Used,
			TotalBytes: memStat.Total,
			SwapUsed:   swapStat.Used,
			SwapTotal:  swapStat.Total,
		},
		IO:        ioStat,
		GPUs:      gpus,
		Battery:   batt,
		Top:       top,
		Throttled: throttled,
		Cgroups:   cgroups,
		Inotify:   inotify,
		Temps:     temps,
	}
}

// CPU percentages from times delta.
func (s *Sampler) cpuPercents() (total float64, perCore []float64) {
	times, _ := cpu.Times(false)
	if len(times) == 0 {
		return 0, nil
	}
	cur := times[0]
	curTotal := cur.Total()
	curIdle := cur.Idle + cur.Iowait
	if s.prevTotal > 0 {
		dt := curTotal - s.prevTotal
		di := curIdle - s.prevIdle
		if dt > 0 {
			total = 100 * (1 - di/dt)
		}
	}
	s.prevTotal, s.prevIdle = curTotal, curIdle

	coreTimes, _ := cpu.Times(true)
	perCore = make([]float64, len(coreTimes))
	for i, c := range coreTimes {
		if i >= len(s.prevCore) {
			perCore[i] = 0
			continue
		}
		prev := s.prevCore[i]
		dt := c.Total() - prev.Total()
		di := (c.Idle + c.Iowait) - (prev.Idle + prev.Iowait)
		if dt > 0 {
			perCore[i] = 100 * (1 - di/dt)
		}
	}
	s.prevCore = coreTimes
	return
}

func (s *Sampler) ioNet() model.IO {
	// Disk
	diskCounters, _ := disk.IOCounters()
	var rdBytesDelta, wrBytesDelta uint64
	for name, st := range diskCounters {
		if strings.HasPrefix(name, "loop") {
			continue
		}
		prev, ok := s.prevDisk[name]
		if ok {
			if st.ReadBytes > prev.ReadBytes {
				rdBytesDelta += st.ReadBytes - prev.ReadBytes
			}
			if st.WriteBytes > prev.WriteBytes {
				wrBytesDelta += st.WriteBytes - prev.WriteBytes
			}
		}
		s.prevDisk[name] = st
	}
	dur := s.Interval.Seconds()
	ioStat := model.IO{
		DiskReadMBs:  float64(rdBytesDelta) / (1024 * 1024) / dur,
		DiskWriteMBs: float64(wrBytesDelta) / (1024 * 1024) / dur,
	}

	// Net
	netCounters, _ := net.IOCounters(false)
	if len(netCounters) > 0 && len(s.prevNet) > 0 {
		rx := netCounters[0].BytesRecv - s.prevNet[0].BytesRecv
		tx := netCounters[0].BytesSent - s.prevNet[0].BytesSent
		ioStat.NetRxMbps = float64(rx*8) / 1e6 / dur
		ioStat.NetTxMbps = float64(tx*8) / 1e6 / dur
	}
	if len(netCounters) > 0 {
		s.prevNet = netCounters
	}
	return ioStat
}

func (s *Sampler) topProcs() (top []model.Process, throttled []model.Process, cgs []model.Cgroup) {
	procs, _ := process.Processes()
	type cgAgg struct{ cpu float64 }
	cgMap := make(map[string]*cgAgg)
	newProcIO := make(map[int]procIO)
	dt := s.Interval.Seconds()

	for _, p := range procs {
		// Skip kernel threads without name
		name, _ := p.Name()
		if name == "" {
			continue
		}
		cpuPct, _ := p.CPUPercent()
		memPct, _ := p.MemoryPercent()
		nice, _ := p.Nice()
		cmd, _ := p.Cmdline()
		if cmd == "" {
			cmd = name
		}
		fdCount, _ := p.NumFDs()

		var rRate, wRate float64
		if ioCounters, err := p.IOCounters(); err == nil && ioCounters != nil {
			prev := s.prevProcIO[int(p.Pid)]
			if prev.read > 0 && ioCounters.ReadBytes >= prev.read && dt > 0 {
				rRate = float64(ioCounters.ReadBytes-prev.read) / 1024.0 / dt
			}
			if prev.write > 0 && ioCounters.WriteBytes >= prev.write && dt > 0 {
				wRate = float64(ioCounters.WriteBytes-prev.write) / 1024.0 / dt
			}
			newProcIO[int(p.Pid)] = procIO{read: ioCounters.ReadBytes, write: ioCounters.WriteBytes}
		}

		entry := model.Process{
			PID:      int(p.Pid),
			Nice:     int(nice),
			CPU:      cpuPct,
			Memory:   float64(memPct),
			Command:  truncate(cmd, 60),
			FDCount:  int(fdCount),
			ReadKBs:  rRate,
			WriteKBs: wRate,
		}
		top = append(top, entry)
		if nice > 0 {
			throttled = append(throttled, entry)
		}
		// cgroup aggregate (best-effort)
		// Best-effort cgroup aggregation: parse /proc/<pid>/cgroup last path component.
		if cgPath, err := s.readProcCgroup(int(p.Pid)); err == nil {
			if _, ok := cgMap[cgPath]; !ok {
				cgMap[cgPath] = &cgAgg{}
			}
			cgMap[cgPath].cpu += cpuPct
		}
	}

	sort.Slice(top, func(i, j int) bool { return top[i].CPU > top[j].CPU })
	if len(top) > 64 {
		top = top[:64]
	}
	sort.Slice(throttled, func(i, j int) bool { return throttled[i].CPU > throttled[j].CPU })
	if len(throttled) > 32 {
		throttled = throttled[:32]
	}

	for name, agg := range cgMap {
		cgs = append(cgs, model.Cgroup{Name: name, CPU: agg.cpu})
	}
	sort.Slice(cgs, func(i, j int) bool { return cgs[i].CPU > cgs[j].CPU })
	if len(cgs) > 16 {
		cgs = cgs[:16]
	}

	s.prevProcIO = newProcIO
	return
}

func (s *Sampler) gpuLoop(ctx context.Context) {
	// Initial fetch
	s.updateGPU()

	// Poll GPU slower than main loop to reduce overhead/stutter
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.updateGPU()
		}
	}
}

func (s *Sampler) updateGPU() {
	data := s.queryGPU()
	s.gpuMu.Lock()
	s.gpuData = data
	s.gpuMu.Unlock()
}

func (s *Sampler) queryGPU() []model.GPU {
	out, _ := runCmd(400*time.Millisecond, "nvidia-smi",
		"--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu",
		"--format=csv,noheader,nounits")
	if out == "" {
		return nil
	}
	var gpus []model.GPU
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		parts := strings.Split(sc.Text(), ",")
		if len(parts) < 5 {
			continue
		}
		name := strings.TrimSpace(parts[0])
		util := parseFloat(parts[1])
		memUsed := parseFloat(parts[2])
		memTotal := parseFloat(parts[3])
		temp := parseFloat(parts[4])
		gpus = append(gpus, model.GPU{
			Name:       name,
			Util:       util,
			MemUsedMB:  memUsed,
			MemTotalMB: memTotal,
			TempC:      temp,
		})
	}
	return gpus
}

func (s *Sampler) battery() model.Battery {
	battPaths, _ := filepath.Glob("/sys/class/power_supply/BAT*/capacity")
	for _, capPath := range battPaths {
		base := filepath.Dir(capPath)
		capBytes, err := os.ReadFile(capPath)
		if err != nil {
			continue
		}
		pct := parseFloat(string(capBytes))
		stateBytes, _ := os.ReadFile(filepath.Join(base, "status"))
		state := strings.TrimSpace(string(stateBytes))
		return model.Battery{Percent: pct, State: state}
	}
	return model.Battery{}
}

func (s *Sampler) inotify() model.Inotify {
	readUint := func(path string) uint64 {
		b, err := os.ReadFile(path)
		if err != nil {
			return 0
		}
		v, _ := strconv.ParseUint(strings.TrimSpace(string(b)), 10, 64)
		return v
	}
	return model.Inotify{
		MaxUserWatches:   readUint("/proc/sys/fs/inotify/max_user_watches"),
		MaxUserInstances: readUint("/proc/sys/fs/inotify/max_user_instances"),
		NrWatches:        readUint("/proc/sys/fs/inotify/nr_watches"),
	}
}

func (s *Sampler) temps() []model.Temp {
	var temps []model.Temp
	paths, _ := filepath.Glob("/sys/class/thermal/thermal_zone*/temp")
	for _, p := range paths {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		val := parseFloat(string(b)) / 1000
		zone := filepath.Base(filepath.Dir(p))
		temps = append(temps, model.Temp{Zone: zone, Temp: val})
	}
	return temps
}

// Helpers
func parseFloat(s string) float64 {
	s = strings.TrimSpace(s)
	s = strings.TrimSuffix(s, "%")
	f, _ := strconv.ParseFloat(s, 64)
	return f
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max-1] + "…"
}

func runCmd(timeout time.Duration, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return "", ctx.Err()
	}
	return string(out), err
}

// readProcCgroup returns the last path component of the first cgroup entry.
func (s *Sampler) readProcCgroup(pid int) (string, error) {
	if v, ok := s.cgroupCache[pid]; ok {
		return v, nil
	}
	path := fmt.Sprintf("/proc/%d/cgroup", pid)
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		parts := strings.Split(line, ":")
		if len(parts) != 3 {
			continue
		}
		p := parts[2]
		segs := strings.Split(p, "/")
		for i := len(segs) - 1; i >= 0; i-- {
			if segs[i] != "" {
				s.cgroupCache[pid] = segs[i]
				return segs[i], nil
			}
		}
	}
	return "", fmt.Errorf("no cgroup")
}
