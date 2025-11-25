package ui

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/Dicklesworthstone/system_resource_protection_script/internal/config"
	"github.com/Dicklesworthstone/system_resource_protection_script/internal/model"
	"github.com/Dicklesworthstone/system_resource_protection_script/internal/sampler"
)

const (
	historyPoints  = 60
	primaryColor   = "#00D7FF" // Cyan
	secondaryColor = "#FF005F" // Pink/Red
	successColor   = "#00FF87" // Green
	warningColor   = "#FFD700" // Gold
	borderColor    = "#444444" // Dark Grey
	labelColor     = "#888888" // Light Grey
)

// Styles
var (
	// Text Styles
	titleStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FFFFFF")).
			Background(lipgloss.Color(primaryColor)).
			Padding(0, 1).
			Bold(true)

	subtleStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(labelColor))

	labelStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(primaryColor)).Bold(true)

	headerStyle = lipgloss.NewStyle().
			Border(lipgloss.NormalBorder(), false, false, true, false).
			BorderForeground(lipgloss.Color(borderColor)).
			MarginBottom(1)

	// Container Styles
	cardStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color(borderColor)).
			Padding(0, 1).
			MarginRight(1).
			MarginBottom(0)

	// Metrics Styles
	gaugeLabelStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(primaryColor)).Bold(true)
	valStyle        = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF")).Bold(true)

	// Table Styles
	tableHeaderStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(primaryColor)).Bold(true)
	rowStyle         = lipgloss.NewStyle().Foreground(lipgloss.Color("#EEEEEE"))
	dimStyle         = lipgloss.NewStyle().Foreground(lipgloss.Color("#666666"))
)

// Model renders live samples from the sampler.
type Model struct {
	cfg       config.Config
	latest    model.Sample
	stream    <-chan model.Sample
	ctxCancel context.CancelFunc
	width     int
	height    int

	sortKey   string
	filter    string
	inputMode bool
	inputBuf  []rune

	// History for sparklines
	cpuHist       []float64
	memHist       []float64
	netRxHist     []float64
	netTxHist     []float64
	diskReadHist  []float64
	diskWriteHist []float64

	perCoreHist map[int][]float64

	// Statistics (Session)
	cumulativeCPU map[string]float64
	throttleCount map[string]int
	activeTab     int // 0=Dashboard, 1=Analysis
	showHelp      bool
	paused        bool
	showIOPanels  bool
	showGPU       bool
	showBatt      bool
	statusMsg     string

	jsonFile string
}

func New(cfg config.Config) *Model {
	ctx, cancel := context.WithCancel(context.Background())
	s := sampler.New(cfg.Interval)
	return &Model{
		cfg:           cfg,
		stream:        s.Stream(ctx),
		ctxCancel:     cancel,
		width:         120,
		height:        40,
		sortKey:       "cpu",
		filter:        "",
		perCoreHist:   make(map[int][]float64),
		cumulativeCPU: make(map[string]float64),
		throttleCount: make(map[string]int),
		showIOPanels:  true,
		showGPU:       cfg.EnableGPU,
		showBatt:      cfg.EnableBatt,
		jsonFile:      os.Getenv("SRPS_SYSMON_JSON_FILE"),
	}
}

// Messages
type tickMsg struct{}

func tickCmd() tea.Cmd { return tea.Tick(time.Second/5, func(time.Time) tea.Msg { return tickMsg{} }) }

func (m *Model) Init() tea.Cmd { return tickCmd() }

func (m *Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case tea.KeyMsg:
		if m.inputMode {
			switch msg.Type {
			case tea.KeyEnter:
				m.filter = strings.TrimSpace(string(m.inputBuf))
				m.inputMode = false
				m.inputBuf = nil
				return m, nil
			case tea.KeyEsc:
				m.inputMode = false
				m.inputBuf = nil
				return m, nil
			case tea.KeyBackspace:
				if len(m.inputBuf) > 0 {
					m.inputBuf = m.inputBuf[:len(m.inputBuf)-1]
				}
				return m, nil
			default:
				if msg.Runes != nil {
					m.inputBuf = append(m.inputBuf, msg.Runes...)
				}
				return m, nil
			}
		}
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			m.ctxCancel()
			return m, tea.Quit
		case "tab":
			m.activeTab = (m.activeTab + 1) % 2
		case "h", "?":
			m.showHelp = !m.showHelp
		case "s":
			if m.sortKey == "cpu" {
				m.sortKey = "mem"
			} else {
				m.sortKey = "cpu"
			}
		case "g":
			m.showGPU = !m.showGPU
			m.statusMsg = fmt.Sprintf("GPU panels %s", onOff(m.showGPU))
		case "b":
			m.showBatt = !m.showBatt
			m.statusMsg = fmt.Sprintf("Battery panel %s", onOff(m.showBatt))
		case "i":
			m.showIOPanels = !m.showIOPanels
			m.statusMsg = fmt.Sprintf("IO/FD panels %s", onOff(m.showIOPanels))
		case "f":
			m.paused = !m.paused
			m.statusMsg = fmt.Sprintf("Updates %s", onOff(!m.paused))
		case "I":
			if len(m.latest.Top) > 0 {
				p := m.latest.Top[0]
				m.statusMsg = fmt.Sprintf("ionice tip: sudo ionice -c3 -p %d  (# %s)", p.PID, truncate(p.Command, 16))
			} else {
				m.statusMsg = "ionice tip: sudo ionice -c3 -p <pid>"
			}
		case "/":
			m.inputMode = true
			m.inputBuf = nil
		case "o":
			if m.jsonFile != "" {
				m.jsonFile = ""
			} else if f := os.Getenv("SRPS_SYSMON_JSON_FILE"); f != "" {
				m.jsonFile = f
			}
		}
	case tickMsg:
		if m.paused {
			return m, tickCmd()
		}
		select {
		case samp, ok := <-m.stream:
			if ok {
				m.latest = samp
				m.recordHistory(samp)
				m.updateStats(samp)
				m.maybeWriteJSON(samp)
			}
		default:
		}
		return m, tickCmd()
	}
	return m, nil
}

func (m *Model) updateStats(s model.Sample) {
	// Accumulate CPU integral (CPU% * interval_seconds)
	// Approximate interval as 1s or use s.Interval if precise
	factor := s.Interval.Seconds()

	for _, p := range s.Top {
		m.cumulativeCPU[p.Command] += p.CPU * factor
	}
	for _, p := range s.Throttled {
		m.throttleCount[p.Command]++
	}
}

func (m *Model) recordHistory(s model.Sample) {
	appendHist := func(hist []float64, val float64) []float64 {
		hist = append(hist, val)
		if len(hist) > historyPoints {
			hist = hist[len(hist)-historyPoints:]
		}
		return hist
	}

	m.cpuHist = appendHist(m.cpuHist, s.CPU.Total)

	memPct := pct(s.Memory.UsedBytes, s.Memory.TotalBytes)
	m.memHist = appendHist(m.memHist, memPct)

	m.netRxHist = appendHist(m.netRxHist, s.IO.NetRxMbps)
	m.netTxHist = appendHist(m.netTxHist, s.IO.NetTxMbps)
	m.diskReadHist = appendHist(m.diskReadHist, s.IO.DiskReadMBs)
	m.diskWriteHist = appendHist(m.diskWriteHist, s.IO.DiskWriteMBs)

	for i, v := range s.CPU.PerCore {
		buf := m.perCoreHist[i]
		buf = append(buf, v)
		if len(buf) > historyPoints {
			buf = buf[len(buf)-historyPoints:]
		}
		m.perCoreHist[i] = buf
	}
}

func (m *Model) View() string {
	if m.width == 0 {
		return "Loading..."
	}
	s := m.latest
	if m.showHelp {
		return m.renderHelp()
	}

	// --- Header with Tabs ---
	filterTxt := ""
	if m.filter != "" || m.inputMode {
		filterTxt = fmt.Sprintf(" Filter: %s", displayFilter(m))
	}

	// Tab Styles
	activeTabStyle := titleStyle.Copy().Background(lipgloss.Color(secondaryColor))
	inactiveTabStyle := titleStyle.Copy().Background(lipgloss.Color("#444444")).Foreground(lipgloss.Color("#888888"))

	dashTab := inactiveTabStyle.Render(" 1: Dashboard ")
	if m.activeTab == 0 {
		dashTab = activeTabStyle.Render(" 1: Dashboard ")
	}

	histTab := inactiveTabStyle.Render(" 2: Analysis ")
	if m.activeTab == 1 {
		histTab = activeTabStyle.Render(" 2: Analysis ")
	}

	pausedTxt := ""
	if m.paused {
		pausedTxt = " | PAUSED"
	}
	info := subtleStyle.Render(fmt.Sprintf("Sort:%s%s %s", strings.ToUpper(m.sortKey), pausedTxt, filterTxt))
	headerRight := subtleStyle.Render(s.Timestamp.Format("15:04:05"))

	tabs := lipgloss.JoinHorizontal(lipgloss.Bottom, dashTab, " ", histTab)

	// Calculate padding
	gap := m.width - lipgloss.Width(tabs) - lipgloss.Width(info) - lipgloss.Width(headerRight) - 3
	if gap < 1 {
		gap = 1
	}

	header := lipgloss.JoinHorizontal(lipgloss.Bottom,
		tabs,
		strings.Repeat(" ", gap),
		info,
		" ",
		headerRight)

	header = headerStyle.Width(m.width).Render(header)

	// Content based on tab
	var content string
	if m.activeTab == 0 {
		content = m.renderDashboard(s)
	} else {
		content = m.renderAnalysis(s)
	}

	footer := subtleStyle.Render(fmt.Sprintf("tab dashboards | s sort | / filter | g gpu:%s i io:%s b batt:%s f pause:%s | ? help | %s",
		onOff(m.showGPU), onOff(m.showIOPanels), onOff(m.showBatt), onOff(!m.paused), m.statusMsg))

	return lipgloss.JoinVertical(lipgloss.Left, header, content, footer)
}

func (m *Model) renderDashboard(s model.Sample) string {
	// --- Row 1: Vitals (CPU, MEM, SWAP, LOAD) ---
	// CPU Section
	cpuGauge := renderGauge("CPU", s.CPU.Total, primaryColor)
	cpuGraph := renderSparklinePct(m.cpuHist, 20, primaryColor)
	cpuBlock := lipgloss.JoinHorizontal(lipgloss.Bottom, cpuGauge, "  ", cpuGraph)
	cpuCard := cardStyle.Render(cpuBlock)

	// Memory Section
	memVal := pct(s.Memory.UsedBytes, s.Memory.TotalBytes)
	memGauge := renderGauge("MEM", memVal, "#BD93F9") // Purple
	memGraph := renderSparklinePct(m.memHist, 20, "#BD93F9")
	memDetails := subtleStyle.Render(fmt.Sprintf("%.1f/%.1f GB | cache %.1f GB | buf %.1f GB", bytesToGiB(s.Memory.UsedBytes), bytesToGiB(s.Memory.TotalBytes), bytesToGiB(s.Memory.Cached), bytesToGiB(s.Memory.Buffers)))
	memBlock := lipgloss.JoinVertical(lipgloss.Left,
		lipgloss.JoinHorizontal(lipgloss.Bottom, memGauge, "  ", memGraph),
		memDetails)
	memCard := cardStyle.Render(memBlock)

	// Swap & Load
	swapVal := pct(s.Memory.SwapUsed, s.Memory.SwapTotal)
	swapGauge := renderGauge("SWAP", swapVal, warningColor)
	loadStr := fmt.Sprintf("LOAD: %.2f (%.0f cores) 5m %.2f 15m %.2f", s.CPU.Load1, float64(len(s.CPU.PerCore)), s.CPU.Load5, s.CPU.Load15)
	miscBlock := lipgloss.JoinVertical(lipgloss.Left, swapGauge, "\n", valStyle.Render(loadStr))
	miscCard := cardStyle.Render(miscBlock)

	row1 := lipgloss.JoinHorizontal(lipgloss.Top, cpuCard, memCard, miscCard)

	// --- Row 2: Throughput & Hardware (NET, DISK, GPU, BATT) ---

	// Network
	netRxSpark := renderSparklineAuto(m.netRxHist, 15, successColor)
	netTxSpark := renderSparklineAuto(m.netTxHist, 15, "#0077FF") // Blue
	netBlock := lipgloss.JoinVertical(lipgloss.Left,
		fmt.Sprintf("%s RX %5.1f Mb/s %s", valStyle.Foreground(lipgloss.Color(successColor)).Render("↓"), s.IO.NetRxMbps, netRxSpark),
		fmt.Sprintf("%s TX %5.1f Mb/s %s", valStyle.Foreground(lipgloss.Color("#0077FF")).Render("↑"), s.IO.NetTxMbps, netTxSpark),
	)
	netCard := cardStyle.Render(lipgloss.JoinVertical(lipgloss.Left, labelStyle.Render("NETWORK"), netBlock))

	// Disk
	diskRSpark := renderSparklineAuto(m.diskReadHist, 15, warningColor)
	diskWSpark := renderSparklineAuto(m.diskWriteHist, 15, secondaryColor)
	topDevs := topDevices(s.IO.PerDevice, 3)
	devLines := ""
	for _, d := range topDevs {
		devLines += fmt.Sprintf("%-6s R%5.1f W%5.1f MB/s\n", d.Name, d.ReadMBs, d.WriteMBs)
	}
	if devLines == "" {
		devLines = subtleStyle.Render("no device stats")
	}
	diskBlock := lipgloss.JoinVertical(lipgloss.Left,
		fmt.Sprintf("Total R %5.1f MB/s %s", s.IO.DiskReadMBs, diskRSpark),
		fmt.Sprintf("Total W %5.1f MB/s %s", s.IO.DiskWriteMBs, diskWSpark),
		subtleStyle.Render("Top devices:"),
		devLines,
	)
	diskCard := cardStyle.Render(lipgloss.JoinVertical(lipgloss.Left, labelStyle.Render("DISK I/O"), diskBlock))

	// GPU & Battery
	extraContent := ""
	if m.showGPU && len(s.GPUs) > 0 {
		for _, g := range s.GPUs {
			extraContent += fmt.Sprintf("GPU: %s\nUse: %3.0f%% | %2.0f°C\nMem: %3.0f/%3.0f MB\n",
				truncate(g.Name, 10), g.Util, g.TempC, g.MemUsedMB, g.MemTotalMB)
		}
	}
	if m.showBatt && s.Battery.Percent > 0 {
		if extraContent != "" {
			extraContent += "\n"
		}
		extraContent += fmt.Sprintf("BATT: %.0f%% (%s)", s.Battery.Percent, s.Battery.State)
	}
	if extraContent == "" {
		msg := "No GPU/Batt"
		if !m.showGPU || !m.showBatt {
			msg = "GPU/Batt hidden (g/b to toggle)"
		}
		extraContent = subtleStyle.Render(msg)
	}
	extraCard := cardStyle.Render(lipgloss.JoinVertical(lipgloss.Left, labelStyle.Render("HARDWARE"), extraContent))

	row2 := lipgloss.JoinHorizontal(lipgloss.Top, netCard, diskCard, extraCard)

	// --- Row 3: Main Content (Procs left, PerCore right) ---

	// Process List (Left Column)
	// Calculate available height for table (approximate)
	// header=2, row1=5, row2=5, padding=2 -> ~14 lines used
	availHeight := m.height - 14
	if availHeight < 6 {
		availHeight = 6
	}

	row3 := func() string {
		// Wide screens: fill horizontal space with multi-column top list
		if m.width >= 110 {
			cols := 2
			if m.width > 170 {
				cols = 3
			}
			procAreaWidth := (m.width * 2) / 3
			if procAreaWidth < 70 {
				procAreaWidth = 70
			}

			procTable := renderProcessColumns(m.sortAndFilter(s.Top), cols, availHeight, procAreaWidth-4, primaryColor)
			procCard := cardStyle.Width(procAreaWidth).Height(availHeight).
				Render(lipgloss.JoinVertical(lipgloss.Left, labelStyle.Render("TOP PROCESSES"), procTable))

			rightWidth := m.width - procAreaWidth - 1
			if rightWidth < 32 {
				rightWidth = 32
			}
			if procAreaWidth+rightWidth+1 > m.width {
				rightWidth = maxInt(24, m.width-procAreaWidth-1)
			}

			thHeight := maxInt(5, availHeight/3)
			ioHeight := maxInt(5, availHeight/3)
			fdHeight := maxInt(4, availHeight/4)
			coreWidth := minInt(32, rightWidth-6)

			throttledTable := renderProcessTable(m.sortAndFilter(s.Throttled), thHeight, secondaryColor)
			ioLeaders := ""
			fdLeaders := ""
			if m.showIOPanels {
				ioLeaders = renderProcessTable(m.topIO(s.Top), ioHeight, warningColor)
				fdLeaders = renderProcessTable(m.topFD(s.Top), fdHeight, warningColor)
			}
			coreBlock := renderCoreGrid(m.perCoreHist, coreWidth)

			rightColContent := lipgloss.JoinVertical(lipgloss.Left,
				labelStyle.Foreground(lipgloss.Color(secondaryColor)).Render("THROTTLED (Nice > 0)"),
				throttledTable,
				func() string {
					if m.showIOPanels {
						return lipgloss.JoinVertical(lipgloss.Left,
							labelStyle.Render("IO TOP (R/W kB/s, FDs)"), ioLeaders,
							labelStyle.Render("FD TOP"), fdLeaders,
							labelStyle.Render("CPU CORES"), coreBlock)
					}
					return lipgloss.JoinVertical(lipgloss.Left,
						labelStyle.Render("CPU CORES"), coreBlock,
						subtleStyle.Render("(IO panels hidden; press i to toggle)"))
				}(),
			)

			rightCard := cardStyle.Width(rightWidth).Height(availHeight).Render(rightColContent)
			return lipgloss.JoinHorizontal(lipgloss.Top, procCard, rightCard)
		}

		// Narrow screens: fall back to single column
		procTable := renderProcessTable(m.sortAndFilter(s.Top), availHeight, primaryColor)
		procCard := cardStyle.Width(55).Height(availHeight).Render(lipgloss.JoinVertical(lipgloss.Left, labelStyle.Render("TOP PROCESSES"), procTable))

		throttledTable := renderProcessTable(m.sortAndFilter(s.Throttled), 5, secondaryColor)
		coreBlock := renderCoreGrid(m.perCoreHist, 25)
		var ioLeaders, fdLeaders string
		if m.showIOPanels {
			ioLeaders = renderProcessTable(m.topIO(s.Top), 6, warningColor)
			fdLeaders = renderProcessTable(m.topFD(s.Top), 6, warningColor)
		}

		rightColContent := lipgloss.JoinVertical(lipgloss.Left,
			labelStyle.Foreground(lipgloss.Color(secondaryColor)).Render("THROTTLED (Nice > 0)"),
			throttledTable,
			func() string {
				if m.showIOPanels {
					return lipgloss.JoinVertical(lipgloss.Left,
						labelStyle.Render("IO TOP (R/W kB/s, FDs)"), ioLeaders,
						labelStyle.Render("FD TOP"), fdLeaders,
						labelStyle.Render("CPU CORES"), coreBlock)
				}
				return lipgloss.JoinVertical(lipgloss.Left,
					labelStyle.Render("CPU CORES"), coreBlock,
					subtleStyle.Render("(IO panels hidden; press i to toggle)"))
			}(),
		)

		rightCard := cardStyle.Render(rightColContent)
		return lipgloss.JoinHorizontal(lipgloss.Top, procCard, rightCard)
	}()

	return lipgloss.JoinVertical(lipgloss.Left, row1, row2, row3)
}

func (m *Model) renderAnalysis(s model.Sample) string {
	availHeight := m.height - 4 // approximate header/padding

	// Hall of Shame (Left)
	shameHeight := availHeight
	shameRows := m.getHallOfShame(shameHeight - 4)
	shameTable := renderSimpleTable([]string{"COMMAND", "CPU-SEC"}, shameRows, 25, primaryColor)
	shameCard := cardStyle.Width(40).Height(shameHeight).Render(lipgloss.JoinVertical(lipgloss.Left, labelStyle.Render("HALL OF SHAME"), shameTable))

	// Frequent Flyers (Right)
	freqRows := m.getFrequentFlyers(shameHeight - 4)
	freqTable := renderSimpleTable([]string{"COMMAND", "THROTTLED"}, freqRows, 25, secondaryColor)
	freqCard := cardStyle.Width(40).Height(shameHeight).Render(lipgloss.JoinVertical(lipgloss.Left, labelStyle.Render("FREQUENTLY THROTTLED"), freqTable))

	return lipgloss.JoinHorizontal(lipgloss.Top, shameCard, freqCard)
}

// Helpers for Analysis data
func (m *Model) getHallOfShame(limit int) []string {
	if limit < 1 {
		limit = 1
	}
	type kv struct {
		k string
		v float64
	}
	var ss []kv
	for k, v := range m.cumulativeCPU {
		ss = append(ss, kv{k, v})
	}
	sort.Slice(ss, func(i, j int) bool { return ss[i].v > ss[j].v })

	var rows []string
	for i := 0; i < limit && i < len(ss); i++ {
		// Divide by 100 to get "Core-Seconds"
		val := ss[i].v / 100.0
		rows = append(rows, fmt.Sprintf("%-18s %6.1f", truncate(ss[i].k, 18), val))
	}
	return rows
}

func (m *Model) getFrequentFlyers(limit int) []string {
	if limit < 1 {
		limit = 1
	}
	type kv struct {
		k string
		v int
	}
	var ss []kv
	for k, v := range m.throttleCount {
		ss = append(ss, kv{k, v})
	}
	sort.Slice(ss, func(i, j int) bool { return ss[i].v > ss[j].v })

	var rows []string
	for i := 0; i < limit && i < len(ss); i++ {
		rows = append(rows, fmt.Sprintf("%-18s %6d", truncate(ss[i].k, 18), ss[i].v))
	}
	return rows
}

func (m *Model) topIO(procs []model.Process) []model.Process {
	sorted := append([]model.Process{}, procs...)
	sort.Slice(sorted, func(i, j int) bool {
		return (sorted[i].ReadKBs + sorted[i].WriteKBs) > (sorted[j].ReadKBs + sorted[j].WriteKBs)
	})
	if len(sorted) > 8 {
		sorted = sorted[:8]
	}
	return sorted
}

func (m *Model) topFD(procs []model.Process) []model.Process {
	sorted := append([]model.Process{}, procs...)
	sort.Slice(sorted, func(i, j int) bool {
		return sorted[i].FDCount > sorted[j].FDCount
	})
	if len(sorted) > 8 {
		sorted = sorted[:8]
	}
	return sorted
}

func (m *Model) renderHelp() string {
	helpText := []string{
		"KEYS",
		"  q / Ctrl+C     Quit",
		"  tab            Toggle Dashboard / Analysis",
		"  s              Toggle sort CPU/MEM",
		"  /              Filter by substring (enter to apply, esc to cancel)",
		"  h or ?         Toggle this help",
		"  g / b / i      Toggle GPU / Battery / IO panels",
		"  f              Freeze/unfreeze updates",
		"  I              Show ionice tip for the top process",
		"  o              Toggle JSON file output (when SRPS_SYSMON_JSON_FILE set)",
		"",
		"DASHBOARD PANELS",
		"  CPU/MEM/Swap gauges, IO/NET sparklines, GPU/Batt status",
		"  Top Processes now show Rk/s, Wk/s, FDs",
		"  IO TOP and FD TOP highlight disk hogs and FD explosions",
		"",
		"TIPS",
		"  Drop IO priority manually: sudo ionice -c3 -p <pid>",
		"  Throttle CPU-heavy commands: limited <cmd> (uses systemd-run if available)",
	}
	return cardStyle.Width(m.width - 4).Render(strings.Join(helpText, "\n"))
}

func renderSimpleTable(headers []string, rows []string, width int, color string) string {
	var b strings.Builder
	style := lipgloss.NewStyle().Foreground(lipgloss.Color(color))

	// Header
	headStr := strings.Join(headers, " ")
	b.WriteString(style.Bold(true).Render(headStr) + "\n")

	for i, r := range rows {
		rowStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#EEEEEE"))
		if i%2 != 0 {
			rowStyle = rowStyle.Foreground(lipgloss.Color("#AAAAAA"))
		}
		b.WriteString(rowStyle.Render(r) + "\n")
	}
	return b.String()
}

// --- Render Helpers ---

func renderGauge(label string, pct float64, color string) string {
	width := 20
	filled := int((pct / 100) * float64(width))
	if filled > width {
		filled = width
	}
	if filled < 0 {
		filled = 0
	}

	bar := strings.Repeat("█", filled) + strings.Repeat("░", width-filled)

	// Apply color gradient logic or solid color
	style := lipgloss.NewStyle().Foreground(lipgloss.Color(color))
	if pct > 90 {
		style = style.Foreground(lipgloss.Color(secondaryColor)) // Alert color
	}

	return lipgloss.JoinVertical(lipgloss.Left,
		gaugeLabelStyle.Render(label),
		style.Render(bar)+fmt.Sprintf(" %.0f%%", pct),
	)
}

func renderSparklineAuto(values []float64, width int, color string) string {
	if len(values) == 0 {
		return strings.Repeat(" ", width)
	}
	// Take last N values
	if len(values) > width {
		values = values[len(values)-width:]
	}

	// Find max for auto-scaling
	max := 0.0
	for _, v := range values {
		if v > max {
			max = v
		}
	}
	if max == 0 {
		max = 1 // Avoid divide by zero, render flat line
	}

	chars := []rune(" ▂▃▄▅▆▇█")
	var b strings.Builder
	style := lipgloss.NewStyle().Foreground(lipgloss.Color(color))

	for _, v := range values {
		// Normalize 0-1 based on max
		ratio := v / max
		idx := int(ratio * float64(len(chars)-1))
		if idx < 0 {
			idx = 0
		}
		if idx >= len(chars) {
			idx = len(chars) - 1
		}
		b.WriteRune(chars[idx])
	}

	// Pad left if not enough data
	padding := width - len(values)
	if padding > 0 {
		return strings.Repeat(" ", padding) + style.Render(b.String())
	}
	return style.Render(b.String())
}

func topDevices(devs []model.IODevice, n int) []model.IODevice {
	sorted := append([]model.IODevice{}, devs...)
	sort.Slice(sorted, func(i, j int) bool {
		return (sorted[i].ReadMBs + sorted[i].WriteMBs) > (sorted[j].ReadMBs + sorted[j].WriteMBs)
	})
	if len(sorted) > n {
		sorted = sorted[:n]
	}
	return sorted
}

func renderSparklinePct(values []float64, width int, color string) string {
	if len(values) == 0 {
		return strings.Repeat(" ", width)
	}
	// Take last N values
	if len(values) > width {
		values = values[len(values)-width:]
	}

	chars := []rune(" ▂▃▄▅▆▇█")
	var b strings.Builder
	style := lipgloss.NewStyle().Foreground(lipgloss.Color(color))

	for _, v := range values {
		// Normalize 0-100 fixed scale
		idx := int((v / 100.0) * float64(len(chars)-1))
		if idx < 0 {
			idx = 0
		}
		if idx >= len(chars) {
			idx = len(chars) - 1
		}
		b.WriteRune(chars[idx])
	}

	// Pad left if not enough data
	padding := width - len(values)
	if padding > 0 {
		return strings.Repeat(" ", padding) + style.Render(b.String())
	}
	return style.Render(b.String())
}

func renderProcessTable(procs []model.Process, height int, highlightColor string) string {
	var b strings.Builder

	// Header
	fmt.Fprintf(&b, "%-18s %6s %4s %6s %6s %6s %6s %5s\n", "COMMAND", "PID", "NI", "CPU%", "MEM%", "Rk/s", "Wk/s", "FDs")

	count := 0
	for _, p := range procs {
		if count >= height-1 {
			break
		} // -1 for header

		cmd := truncate(p.Command, 18)
		line := fmt.Sprintf("%-18s %6d %4d %6.1f %6.1f %6.1f %6.1f %5d", cmd, p.PID, p.Nice, p.CPU, p.Memory, p.ReadKBs, p.WriteKBs, p.FDCount)

		style := rowStyle
		if p.FDDiff > 100 {
			style = style.Foreground(lipgloss.Color(warningColor)).Bold(true)
		} else if p.Nice > 0 {
			style = style.Foreground(lipgloss.Color(secondaryColor))
		} else if count == 0 {
			style = style.Foreground(lipgloss.Color(highlightColor)).Bold(true)
		} else if count%2 == 0 {
			style = dimStyle
		}

		b.WriteString(style.Render(line) + "\n")
		count++
	}
	return b.String()
}

// renderProcessColumns splits the process table into multiple narrow columns to avoid tall lists.
func renderProcessColumns(procs []model.Process, columns, height, totalWidth int, highlightColor string) string {
	if columns < 1 {
		columns = 1
	}
	if height < 2 {
		height = 2
	}
	maxRows := height - 1 // account for header per column
	if maxRows < 1 {
		maxRows = 1
	}
	if totalWidth < columns {
		totalWidth = columns
	}
	colWidth := totalWidth / columns
	if colWidth < 32 {
		colWidth = 32
	}
	if colWidth*columns > totalWidth {
		colWidth = maxInt(16, totalWidth/columns)
	}
	cmdWidth := colWidth - 32 // leave room for metrics
	if cmdWidth < 8 {
		cmdWidth = 8
	}

	limit := minInt(len(procs), columns*maxRows)
	var cols []string
	for c := 0; c < columns; c++ {
		start := c * maxRows
		if start >= limit {
			break
		}
		end := minInt(start+maxRows, limit)
		col := renderProcessColumn(procs[start:end], maxRows, cmdWidth, highlightColor)
		cols = append(cols, lipgloss.NewStyle().Width(colWidth).Render(col))
	}
	return lipgloss.JoinHorizontal(lipgloss.Top, cols...)
}

func renderProcessColumn(procs []model.Process, maxRows int, cmdWidth int, highlightColor string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "%-*s %5s %3s %5s %5s %5s %5s %4s\n", cmdWidth, "CMD", "PID", "NI", "CPU", "MEM", "Rk", "Wk", "FD")

	for i, p := range procs {
		if i >= maxRows {
			break
		}
		cmd := truncate(p.Command, cmdWidth)
		line := fmt.Sprintf("%-*s %5d %3d %5.1f %5.1f %5.0f %5.0f %4d", cmdWidth, cmd, p.PID, p.Nice, p.CPU, p.Memory, p.ReadKBs, p.WriteKBs, p.FDCount)

		style := rowStyle
		if p.FDDiff > 100 {
			style = style.Foreground(lipgloss.Color(warningColor)).Bold(true)
		} else if p.Nice > 0 {
			style = style.Foreground(lipgloss.Color(secondaryColor))
		} else if i == 0 {
			style = style.Foreground(lipgloss.Color(highlightColor)).Bold(true)
		} else if i%2 == 0 {
			style = dimStyle
		}
		b.WriteString(style.Render(line) + "\n")
	}
	return b.String()
}

func renderCoreGrid(hist map[int][]float64, width int) string {
	// Create a simple grid. We assume we have hist points.
	// Sort keys
	var keys []int
	for k := range hist {
		keys = append(keys, k)
	}
	sort.Ints(keys)

	var lines []string
	// 2 columns of cores
	for i := 0; i < len(keys); i += 2 {
		c1 := keys[i]
		sp1 := renderSparklinePct(hist[c1], 10, primaryColor) // mini sparklines
		line := fmt.Sprintf("%2d %s", c1, sp1)

		if i+1 < len(keys) {
			c2 := keys[i+1]
			sp2 := renderSparklinePct(hist[c2], 10, primaryColor)
			line += fmt.Sprintf("   %2d %s", c2, sp2)
		}
		lines = append(lines, line)
	}

	return strings.Join(lines, "\n")
}

// --- Utility ---

func pct(used, total uint64) float64 {
	if total == 0 {
		return 0
	}
	return float64(used) * 100 / float64(total)
}

func bytesToGiB(b uint64) float64 { return float64(b) / (1024 * 1024 * 1024) }

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n-1] + "…"
	}
	return s
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func onOff(v bool) string {
	if v {
		return "on"
	}
	return "off"
}

func (m *Model) sortAndFilter(rows []model.Process) []model.Process {
	// Filter
	var filtered []model.Process
	filterLower := strings.ToLower(m.filter)
	for _, r := range rows {
		if filterLower != "" && !strings.Contains(strings.ToLower(r.Command), filterLower) {
			continue
		}
		filtered = append(filtered, r)
	}
	// Sort
	sort.Slice(filtered, func(i, j int) bool {
		if m.sortKey == "mem" {
			return filtered[i].Memory > filtered[j].Memory
		}
		return filtered[i].CPU > filtered[j].CPU
	})
	return filtered
}

func displayFilter(m *Model) string {
	if m.inputMode {
		return "/" + string(m.inputBuf)
	}
	return m.filter
}

func (m *Model) maybeWriteJSON(s model.Sample) {
	if m.jsonFile == "" {
		return
	}
	f, err := os.OpenFile(m.jsonFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	_ = json.NewEncoder(f).Encode(s)
}

// RunTUI starts the Bubble Tea program.
func RunTUI(cfg config.Config) error {
	p := tea.NewProgram(New(cfg), tea.WithAltScreen())
	_, err := p.Run()
	return err
}
