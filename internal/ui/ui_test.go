package ui

import (
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/Dicklesworthstone/system_resource_protection_script/internal/config"
	"github.com/Dicklesworthstone/system_resource_protection_script/internal/model"
)

func newTestModel(sample model.Sample) *Model {
	return &Model{
		cfg:           config.Default(),
		latest:        sample,
		ctxCancel:     func() {},
		width:         180,
		height:        45,
		sortKey:       "cpu",
		perCoreHist:   map[int][]float64{0: {12, 34, 56}, 1: {20, 40, 60}},
		cumulativeCPU: map[string]float64{"rustc": 420.5},
		throttleCount: map[string]int{"rustc": 3},
		showIOPanels:  true,
		showGPU:       true,
		showBatt:      true,
		showTemps:     true,
		mouseEnabled:  true,
		selectedProc:  -1,
	}
}

func sampleFixture() model.Sample {
	return model.Sample{
		Timestamp: time.Date(2026, 11, 20, 12, 0, 0, 0, time.UTC),
		Interval:  time.Second,
		CPU: model.CPU{
			Total:   42.5,
			PerCore: []float64{40.0, 45.0},
			Load1:   1.25,
			Load5:   1.10,
			Load15:  0.95,
		},
		Memory: model.Memory{
			UsedBytes:  4 << 30,
			TotalBytes: 16 << 30,
			SwapUsed:   512 << 20,
			SwapTotal:  4 << 30,
			Cached:     2 << 30,
			Buffers:    256 << 20,
		},
		IO: model.IO{
			DiskReadMBs:  12.5,
			DiskWriteMBs: 8.3,
			NetRxMbps:    15.0,
			NetTxMbps:    3.2,
			PerDevice:    []model.IODevice{{Name: "nvme0n1", ReadMBs: 12.5, WriteMBs: 8.3}},
		},
		Top: []model.Process{
			{PID: 101, Nice: 19, CPU: 80.5, Memory: 12.3, Command: "rustc --edition=2024", FDCount: 120, ReadKBs: 500, WriteKBs: 1200, FDDiff: 15},
			{PID: 202, Nice: 0, CPU: 15.2, Memory: 25.0, Command: "node server.js", FDCount: 640, ReadKBs: 10, WriteKBs: 20, FDDiff: 0},
		},
		Throttled: []model.Process{
			{PID: 101, Nice: 19, CPU: 80.5, Memory: 12.3, Command: "rustc --edition=2024", FDCount: 120},
		},
		Cgroups: []model.Cgroup{{Name: "user.slice", CPU: 95.7}},
		Inotify: model.Inotify{MaxUserWatches: 524288, MaxUserInstances: 1024, NrWatches: 4096},
		Temps:   []model.Temp{{Zone: "thermal_zone0", Temp: 55.0}},
	}
}

func TestViewRendersAllTabsAndOverlays(t *testing.T) {
	m := newTestModel(sampleFixture())
	m.recordHistory(m.latest)
	m.updateStats(m.latest)
	m.updateAlerts(m.latest)

	// Tab 0: Dashboard (wide and narrow widths)
	for _, w := range []int{180, 120, 80} {
		m.width = w
		view := m.View()
		if !strings.Contains(view, "TOP PROCESSES") {
			t.Fatalf("width %d: dashboard missing TOP PROCESSES", w)
		}
		if !strings.Contains(view, "rustc") {
			t.Fatalf("width %d: dashboard missing sample process", w)
		}
	}

	// Tab 1: Analysis
	m.width = 160
	m.activeTab = 1
	if view := m.View(); !strings.Contains(view, "HALL OF SHAME") || !strings.Contains(view, "FREQUENT FLYERS") {
		t.Fatalf("analysis tab missing expected cards")
	}

	// Tab 2: System info
	m.activeTab = 2
	if view := m.View(); !strings.Contains(view, "TEMPERATURES") || !strings.Contains(view, "INOTIFY WATCHES") || !strings.Contains(view, "CGROUP CPU USAGE") {
		t.Fatalf("system tab missing expected panels")
	}

	// Help overlay
	m.showHelp = true
	if view := m.View(); !strings.Contains(view, "SYSMONI - SYSTEM RESOURCE MONITOR") {
		t.Fatalf("help overlay missing header")
	}
	m.showHelp = false

	// Process detail modal
	m.detailPID = 101
	m.showProcDetail = true
	if view := m.View(); !strings.Contains(view, "PROCESS DETAILS") || !strings.Contains(view, "101") {
		t.Fatalf("process detail modal missing expected details")
	}
}

func TestUnavailableCollectorsSuppressAlertsAndRenderMessage(t *testing.T) {
	s := sampleFixture()
	s.Memory = model.Memory{}
	s.Unavailable = []string{"memory", "swap", "load"}

	m := newTestModel(s)
	m.updateAlerts(s)
	if m.criticalMem || m.criticalSwap {
		t.Fatalf("unavailable memory/swap should not raise critical alerts: mem=%v swap=%v", m.criticalMem, m.criticalSwap)
	}
	view := m.View()
	if !strings.Contains(view, "memory: unavailable") {
		t.Fatalf("expected unavailable memory text in dashboard view")
	}
	if !strings.Contains(view, "unavailable (collector failed)") {
		t.Fatalf("expected unavailable load text in dashboard view")
	}
}

func TestUpdateNavigationSortAndFilter(t *testing.T) {
	m := newTestModel(sampleFixture())

	// Sort cycle: cpu -> mem -> io -> fd -> cpu
	for _, want := range []string{"mem", "io", "fd", "cpu"} {
		_, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'s'}})
		if m.sortKey != want {
			t.Fatalf("sortKey = %q, want %q", m.sortKey, want)
		}
	}

	// Filter input mode with Unicode and ASCII characters
	_, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'/'}})
	if !m.inputMode {
		t.Fatal("expected inputMode after /")
	}
	_, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("node")})
	_, _ = m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if m.inputMode || m.filter != "node" {
		t.Fatalf("after filter enter: inputMode=%v filter=%q", m.inputMode, m.filter)
	}
	filtered := m.sortAndFilter(m.latest.Top)
	if len(filtered) != 1 || filtered[0].PID != 202 {
		t.Fatalf("filtered = %+v, want only PID 202", filtered)
	}

	// Esc clears filter before quitting
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	if cmd != nil || m.filter != "" {
		t.Fatalf("esc should clear filter without quitting: filter=%q cmd=%v", m.filter, cmd)
	}

	// Tab switching
	_, _ = m.Update(tea.KeyMsg{Type: tea.KeyTab})
	if m.activeTab != 1 {
		t.Fatalf("activeTab = %d, want 1", m.activeTab)
	}

	// Quit cancels context and returns tea.Quit
	canceled := false
	m.ctxCancel = func() { canceled = true }
	_, cmd = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'q'}})
	if !canceled || cmd == nil {
		t.Fatalf("q should cancel context and return quit cmd: canceled=%v cmd=%v", canceled, cmd)
	}
}

func BenchmarkDashboardView(b *testing.B) {
	m := newTestModel(sampleFixture())
	m.recordHistory(m.latest)
	m.updateStats(m.latest)
	m.updateAlerts(m.latest)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = m.View()
	}
}
