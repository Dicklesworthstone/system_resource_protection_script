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
	criticalColor  = "#FF0000" // Red for critical alerts
	coolColor      = "#00BFFF" // Deep sky blue for cool temps
	warmColor      = "#FFA500" // Orange for warm temps
	hotColor       = "#FF4500" // OrangeRed for hot temps
	accentColor    = "#9D4EDD" // Purple accent
	bgDimColor     = "#1a1a1a" // Subtle background
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

	// Enhanced card styles - focusedCardStyle available for future panel focus feature
	focusedCardStyle = lipgloss.NewStyle().
				Border(lipgloss.DoubleBorder()).
				BorderForeground(lipgloss.Color(primaryColor)).
				Padding(0, 1).
				MarginRight(1).
				MarginBottom(0)

	alertCardStyle = lipgloss.NewStyle().
			Border(lipgloss.ThickBorder()).
			BorderForeground(lipgloss.Color(criticalColor)).
			Padding(0, 1).
			MarginRight(1).
			MarginBottom(0)

	// Metrics Styles
	gaugeLabelStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(primaryColor)).Bold(true)
	valStyle        = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF")).Bold(true)

	// Alert/critical styles
	criticalStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(criticalColor)).
			Bold(true)

	// Pulsing style for attention-grabbing alerts (used with tickCount animation)
	pulseStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FFFFFF")).
			Background(lipgloss.Color(criticalColor)).
			Bold(true).
			Padding(0, 1)

	// Table header style for consistent table headers
	tableHeaderStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color(primaryColor)).
				Bold(true).
				Underline(true)

	// Badge style for counts and status indicators
	badgeStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FFFFFF")).
			Background(lipgloss.Color(accentColor)).
			Padding(0, 1).
			Bold(true)

	// Mini gauge base style (used as container for inline gauges)
	miniGaugeStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color(labelColor))

	// Table Styles
	rowStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#EEEEEE"))
	dimStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#666666"))
)

// Model renders live samples from the sampler.
type Model struct {
	cfg       config.Config
	latest    model.Sample
	stream    <-chan model.Sample
	ctxCancel context.CancelFunc
	width     int
	height    int
	topOffset int

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
	activeTab     int // 0=Dashboard, 1=Analysis, 2=System Info
	showHelp      bool
	paused        bool
	showIOPanels  bool
	showGPU       bool
	showBatt      bool
	showTemps     bool
	showInotify   bool
	showCgroups   bool
	statusMsg     string

	// Mouse support
	mouseEnabled bool
	selectedProc int // index of selected process (-1 = none)
	focusedPanel int // 0=procs, 1=io, 2=fd, 3=throttled

	// Process detail modal
	showProcDetail bool
	detailPID      int

	// Alert tracking
	alertCount   int
	criticalCPU  bool
	criticalMem  bool
	criticalSwap bool
	criticalTemp bool

	// Animation state
	tickCount int

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
		showTemps:     true,
		showInotify:   false,
		showCgroups:   false,
		mouseEnabled:  true,
		selectedProc:  -1,
		focusedPanel:  0,
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
		m.clampTopOffset()
	case tea.MouseMsg:
		if m.mouseEnabled {
			switch msg.Action {
			case tea.MouseActionPress:
				// Handle click on process list area (rough hit testing)
				if msg.Y >= 15 && msg.Y < m.height-2 {
					// Clicked in process area - calculate which process
					clickedRow := msg.Y - 16
					if clickedRow >= 0 {
						newSel := m.topOffset + clickedRow
						procs := m.sortAndFilter(m.latest.Top)
						if newSel < len(procs) {
							m.selectedProc = newSel
							m.statusMsg = fmt.Sprintf("Selected: %s (PID %d)", truncate(procs[newSel].Command, 20), procs[newSel].PID)
						}
					}
				}
			case tea.MouseActionMotion:
				// Could add hover effects here
			}
			// Scroll wheel
			if msg.Button == tea.MouseButtonWheelUp {
				m.bumpTopOffset(-3)
			} else if msg.Button == tea.MouseButtonWheelDown {
				m.bumpTopOffset(3)
			}
		}
	case tea.KeyMsg:
		// Close modal first if open
		if m.showProcDetail {
			if msg.String() == "esc" || msg.String() == "enter" || msg.String() == "q" {
				m.showProcDetail = false
				return m, nil
			}
			return m, nil
		}
		if m.inputMode {
			switch msg.Type {
			case tea.KeyEnter:
				m.filter = strings.TrimSpace(string(m.inputBuf))
				m.inputMode = false
				m.inputBuf = nil
				m.topOffset = 0
				m.selectedProc = -1 // Reset selection when filter changes
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
		case "q", "ctrl+c":
			m.ctxCancel()
			return m, tea.Quit
		case "esc":
			if m.filter != "" {
				m.filter = ""
				m.topOffset = 0
				m.statusMsg = "Filter cleared"
			} else if m.selectedProc >= 0 {
				m.selectedProc = -1
				m.statusMsg = "Selection cleared"
			} else {
				m.ctxCancel()
				return m, tea.Quit
			}
		case "tab":
			m.activeTab = (m.activeTab + 1) % 3 // Now 3 tabs
		case "h", "?":
			m.showHelp = !m.showHelp
		case "s":
			if m.sortKey == "cpu" {
				m.sortKey = "mem"
			} else if m.sortKey == "mem" {
				m.sortKey = "io"
			} else if m.sortKey == "io" {
				m.sortKey = "fd"
			} else {
				m.sortKey = "cpu"
			}
			m.topOffset = 0
			m.statusMsg = fmt.Sprintf("Sort: %s", strings.ToUpper(m.sortKey))
		case "g":
			m.showGPU = !m.showGPU
			m.statusMsg = fmt.Sprintf("GPU panels %s", onOff(m.showGPU))
		case "b":
			m.showBatt = !m.showBatt
			m.statusMsg = fmt.Sprintf("Battery panel %s", onOff(m.showBatt))
		case "i":
			m.showIOPanels = !m.showIOPanels
			m.statusMsg = fmt.Sprintf("IO/FD panels %s", onOff(m.showIOPanels))
		case "t":
			m.showTemps = !m.showTemps
			m.statusMsg = fmt.Sprintf("Temps panel %s", onOff(m.showTemps))
		case "n":
			m.showInotify = !m.showInotify
			m.statusMsg = fmt.Sprintf("Inotify panel %s", onOff(m.showInotify))
		case "c":
			m.showCgroups = !m.showCgroups
			m.statusMsg = fmt.Sprintf("Cgroups panel %s", onOff(m.showCgroups))
		case "m":
			m.mouseEnabled = !m.mouseEnabled
			m.statusMsg = fmt.Sprintf("Mouse %s", onOff(m.mouseEnabled))
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
			m.topOffset = 0
		case "o":
			if m.jsonFile != "" {
				m.jsonFile = ""
				m.statusMsg = "JSON output disabled"
			} else if f := os.Getenv("SRPS_SYSMON_JSON_FILE"); f != "" {
				m.jsonFile = f
				m.statusMsg = fmt.Sprintf("JSON output: %s", f)
			}
		case "enter":
			// Show process detail modal for selected process
			if m.selectedProc >= 0 {
				procs := m.sortAndFilter(m.latest.Top)
				if m.selectedProc < len(procs) {
					m.detailPID = procs[m.selectedProc].PID
					m.showProcDetail = true
				}
			} else if len(m.latest.Top) > 0 {
				// Show detail for top process
				m.detailPID = m.latest.Top[0].PID
				m.showProcDetail = true
			}
		case "down", "j":
			if m.selectedProc >= 0 {
				procs := m.sortAndFilter(m.latest.Top)
				if m.selectedProc < len(procs)-1 {
					m.selectedProc++
					// Auto-scroll if needed
					visible := m.visibleTopCapacity()
					if m.selectedProc >= m.topOffset+visible {
						m.bumpTopOffset(1)
					}
				}
			} else {
				m.bumpTopOffset(1)
			}
		case "up", "k":
			if m.selectedProc >= 0 {
				if m.selectedProc > 0 {
					m.selectedProc--
					// Auto-scroll if needed
					if m.selectedProc < m.topOffset {
						m.bumpTopOffset(-1)
					}
				}
			} else {
				m.bumpTopOffset(-1)
			}
		case "pgdown", "J":
			m.bumpTopOffset(m.visibleTopPage())
		case "pgup", "K":
			m.bumpTopOffset(-m.visibleTopPage())
		case "end":
			m.jumpTopEnd()
		case "home":
			m.topOffset = 0
		case "1":
			m.activeTab = 0
		case "2":
			m.activeTab = 1
		case "3":
			m.activeTab = 2
		}
	case tickMsg:
		m.tickCount++
		if m.paused {
			return m, tickCmd()
		}
		select {
		case samp, ok := <-m.stream:
			if ok {
				m.latest = samp
				m.recordHistory(samp)
				m.updateStats(samp)
				m.updateAlerts(samp)
				m.maybeWriteJSON(samp)
				m.clampTopOffset()
			}
		default:
		}
		return m, tickCmd()
	}
	return m, nil
}

// updateAlerts checks for critical conditions and updates alert state
func (m *Model) updateAlerts(s model.Sample) {
	m.alertCount = 0
	m.criticalCPU = s.CPU.Total > 90
	m.criticalMem = pct(s.Memory.UsedBytes, s.Memory.TotalBytes) > 90
	m.criticalSwap = pct(s.Memory.SwapUsed, s.Memory.SwapTotal) > 80
	m.criticalTemp = false

	for _, t := range s.Temps {
		if t.Temp > 85 {
			m.criticalTemp = true
			break
		}
	}

	if m.criticalCPU {
		m.alertCount++
	}
	if m.criticalMem {
		m.alertCount++
	}
	if m.criticalSwap {
		m.alertCount++
	}
	if m.criticalTemp {
		m.alertCount++
	}
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

	// Show process detail modal overlay if active
	if m.showProcDetail {
		return m.renderProcDetailModal(s)
	}

	if m.showHelp {
		return m.renderHelp()
	}

	// --- Header with Tabs and Alert Badge ---
	filterTxt := ""
	if m.filter != "" || m.inputMode {
		filterTxt = fmt.Sprintf(" /: %s", displayFilter(m))
	}

	// Tab Styles with glow effect for active
	activeTabStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#FFFFFF")).
		Background(lipgloss.Color(secondaryColor)).
		Padding(0, 1).
		Bold(true)
	inactiveTabStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#888888")).
		Background(lipgloss.Color("#333333")).
		Padding(0, 1)

	tabs := []string{" 1:Dashboard ", " 2:Analysis ", " 3:System "}
	var tabRenders []string
	for i, t := range tabs {
		if i == m.activeTab {
			tabRenders = append(tabRenders, activeTabStyle.Render(t))
		} else {
			tabRenders = append(tabRenders, inactiveTabStyle.Render(t))
		}
	}
	tabBar := lipgloss.JoinHorizontal(lipgloss.Bottom, tabRenders...)

	// Status indicators with icons
	sortIcon := "▼"
	switch m.sortKey {
	case "mem":
		sortIcon = "▼M"
	case "io":
		sortIcon = "▼I"
	case "fd":
		sortIcon = "▼F"
	default:
		sortIcon = "▼C"
	}
	pauseIcon := ""
	if m.paused {
		pauseIcon = " ⏸"
	}

	// Alert badge using pulseStyle with animation
	alertBadge := ""
	if m.alertCount > 0 {
		// Use pulseStyle for critical alerts with blink animation
		alertStyleLocal := pulseStyle
		if m.tickCount%4 < 2 {
			alertStyleLocal = alertStyleLocal.Background(lipgloss.Color("#660000"))
		}
		alertBadge = alertStyleLocal.Render(fmt.Sprintf("⚠ %d", m.alertCount))
	}

	info := subtleStyle.Render(fmt.Sprintf("%s%s%s%s", sortIcon, strings.ToUpper(m.sortKey), pauseIcon, filterTxt))
	timestamp := subtleStyle.Render(s.Timestamp.Format("15:04:05"))

	// Build header with proper spacing
	leftPart := tabBar
	rightPart := lipgloss.JoinHorizontal(lipgloss.Center, alertBadge, " ", info, " ", timestamp)

	gap := m.width - lipgloss.Width(leftPart) - lipgloss.Width(rightPart) - 2
	if gap < 1 {
		gap = 1
	}

	header := lipgloss.JoinHorizontal(lipgloss.Bottom,
		leftPart,
		strings.Repeat(" ", gap),
		rightPart)

	header = headerStyle.Width(m.width).Render(header)

	// Content based on tab
	var content string
	switch m.activeTab {
	case 0:
		content = m.renderDashboard(s)
	case 1:
		content = m.renderAnalysis(s)
	case 2:
		content = m.renderSystemInfo(s)
	}

	// Enhanced footer with keyboard hints and status
	footerLeft := subtleStyle.Render("tab/1-3:view  s:sort  /:filter  ?:help")
	toggles := fmt.Sprintf("g:%s i:%s t:%s b:%s",
		onOffIcon(m.showGPU), onOffIcon(m.showIOPanels), onOffIcon(m.showTemps), onOffIcon(m.showBatt))
	footerMid := subtleStyle.Render(toggles)
	footerRight := ""
	if m.statusMsg != "" {
		footerRight = lipgloss.NewStyle().Foreground(lipgloss.Color(primaryColor)).Render(m.statusMsg)
	}

	footerGap := m.width - lipgloss.Width(footerLeft) - lipgloss.Width(footerMid) - lipgloss.Width(footerRight) - 4
	if footerGap < 1 {
		footerGap = 1
	}

	footer := lipgloss.JoinHorizontal(lipgloss.Bottom,
		footerLeft,
		strings.Repeat(" ", footerGap/2),
		footerMid,
		strings.Repeat(" ", footerGap-footerGap/2),
		footerRight)

	return lipgloss.JoinVertical(lipgloss.Left, header, content, footer)
}

// onOffIcon returns a visual indicator for on/off state
func onOffIcon(v bool) string {
	if v {
		return "●"
	}
	return "○"
}

func (m *Model) renderDashboard(s model.Sample) string {
	// --- Row 1: Vitals (CPU, MEM, SWAP, LOAD) ---
	// CPU Section with gradient gauge
	cpuGauge := renderGauge("CPU", s.CPU.Total) // Use convenient wrapper
	cpuGraph := renderSparklinePct(m.cpuHist, 20, primaryColor)
	// Add pulsing critical badge when CPU is over 90%
	cpuAlert := ""
	if m.criticalCPU && m.tickCount%4 < 2 {
		cpuAlert = " " + pulseStyle.Render("CRITICAL")
	}
	cpuBlock := lipgloss.JoinHorizontal(lipgloss.Bottom, cpuGauge, "  ", cpuGraph, cpuAlert)
	// Use alert border if critical
	cpuCardStyle := cardStyle
	if m.criticalCPU {
		cpuCardStyle = alertCardStyle
	}
	cpuCard := cpuCardStyle.Render(cpuBlock)

	// Memory Section with gradient gauge
	memVal := pct(s.Memory.UsedBytes, s.Memory.TotalBytes)
	memGauge := renderGaugeEnhanced("MEM", memVal, "#BD93F9", true) // Use gradient
	memGraph := renderSparklinePct(m.memHist, 20, "#BD93F9")
	// Add pulsing critical badge when MEM is over 90%
	memAlert := ""
	if m.criticalMem && m.tickCount%4 < 2 {
		memAlert = " " + pulseStyle.Render("LOW MEM")
	}
	memDetails := subtleStyle.Render(fmt.Sprintf("%.1f/%.1f GB | cache %.1f GB | buf %.1f GB", bytesToGiB(s.Memory.UsedBytes), bytesToGiB(s.Memory.TotalBytes), bytesToGiB(s.Memory.Cached), bytesToGiB(s.Memory.Buffers)))
	memBlock := lipgloss.JoinVertical(lipgloss.Left,
		lipgloss.JoinHorizontal(lipgloss.Bottom, memGauge, "  ", memGraph, memAlert),
		memDetails)
	memCardStyle := cardStyle
	if m.criticalMem {
		memCardStyle = alertCardStyle
	}
	memCard := memCardStyle.Render(memBlock)

	// Swap & Load with gradient gauge
	swapVal := pct(s.Memory.SwapUsed, s.Memory.SwapTotal)
	swapGauge := renderGaugeEnhanced("SWAP", swapVal, warningColor, true) // Use gradient
	// Add pulsing for critical swap
	swapAlert := ""
	if m.criticalSwap && m.tickCount%4 < 2 {
		swapAlert = " " + pulseStyle.Render("SWAPPING")
	}
	// Load averages with color-coded values
	loadColor := successColor
	if s.CPU.Load1 > float64(len(s.CPU.PerCore)) {
		loadColor = criticalColor
	} else if s.CPU.Load1 > float64(len(s.CPU.PerCore))*0.8 {
		loadColor = warningColor
	}
	loadValStyle := lipgloss.NewStyle().Foreground(lipgloss.Color(loadColor)).Bold(true)
	// Use miniGaugeStyle as container for load info
	loadMiniGauge := miniGaugeStyle.Render("LOAD: ") + loadValStyle.Render(fmt.Sprintf("%.2f", s.CPU.Load1)) +
		subtleStyle.Render(fmt.Sprintf(" (%.0f cores) 5m %.2f 15m %.2f", float64(len(s.CPU.PerCore)), s.CPU.Load5, s.CPU.Load15))
	miscBlock := lipgloss.JoinVertical(lipgloss.Left,
		lipgloss.JoinHorizontal(lipgloss.Bottom, swapGauge, swapAlert),
		loadMiniGauge)
	miscCardStyle := cardStyle
	if m.criticalSwap {
		miscCardStyle = alertCardStyle
	}
	miscCard := miscCardStyle.Render(miscBlock)

	row1 := lipgloss.JoinHorizontal(lipgloss.Top, cpuCard, memCard, miscCard)

	// --- Row 2: Throughput & Hardware (NET, DISK, GPU, BATT) ---

	// Network - use enhanced sparklines with stats on wider terminals
	var netRxSpark, netTxSpark string
	if m.width >= 160 {
		netRxSpark = renderSparklineWithStats(m.netRxHist, 30, successColor)
		netTxSpark = renderSparklineWithStats(m.netTxHist, 30, "#0077FF")
	} else {
		netRxSpark = renderSparklineAuto(m.netRxHist, 15, successColor)
		netTxSpark = renderSparklineAuto(m.netTxHist, 15, "#0077FF")
	}
	netBlock := lipgloss.JoinVertical(lipgloss.Left,
		fmt.Sprintf("%s RX %5.1f Mb/s %s", valStyle.Foreground(lipgloss.Color(successColor)).Render("↓"), s.IO.NetRxMbps, netRxSpark),
		fmt.Sprintf("%s TX %5.1f Mb/s %s", valStyle.Foreground(lipgloss.Color("#0077FF")).Render("↑"), s.IO.NetTxMbps, netTxSpark),
	)
	netCard := cardStyle.Render(lipgloss.JoinVertical(lipgloss.Left, titleStyle.Render("NETWORK"), netBlock))

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
	diskCard := cardStyle.Render(lipgloss.JoinVertical(lipgloss.Left, titleStyle.Render("DISK I/O"), diskBlock))

	// GPU & Battery & Temperature Summary
	var extraLines []string
	if m.showGPU && len(s.GPUs) > 0 {
		for _, g := range s.GPUs {
			// Color-coded temperature
			tempStyle := lipgloss.NewStyle().Foreground(lipgloss.Color(coolColor))
			if g.TempC >= 85 {
				tempStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(criticalColor)).Bold(true)
			} else if g.TempC >= 70 {
				tempStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(hotColor))
			} else if g.TempC >= 50 {
				tempStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(warmColor))
			}
			extraLines = append(extraLines,
				fmt.Sprintf("🎮 %s", truncate(g.Name, 12)),
				fmt.Sprintf("   %s %s  %s",
					renderMiniGauge(g.Util, 8),
					lipgloss.NewStyle().Bold(true).Render(fmt.Sprintf("%3.0f%%", g.Util)),
					tempStyle.Render(fmt.Sprintf("%2.0f°C", g.TempC))),
				fmt.Sprintf("   VRAM: %3.0f/%3.0f MB", g.MemUsedMB, g.MemTotalMB))
		}
	}
	if m.showBatt && s.Battery.Percent > 0 {
		// Battery with icon based on level
		battIcon := "🔋"
		battStyle := lipgloss.NewStyle().Foreground(lipgloss.Color(successColor))
		if s.Battery.Percent <= 20 {
			battIcon = "🪫"
			battStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(criticalColor)).Bold(true)
		} else if s.Battery.Percent <= 40 {
			battStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(warningColor))
		}
		if s.Battery.State == "Charging" {
			battIcon = "⚡"
		}
		extraLines = append(extraLines,
			fmt.Sprintf("%s %s %s",
				battIcon,
				battStyle.Render(fmt.Sprintf("%.0f%%", s.Battery.Percent)),
				subtleStyle.Render(s.Battery.State)))
	}
	// Show temperature summary if available
	if m.showTemps && len(s.Temps) > 0 {
		maxTemp := s.Temps[0]
		for _, t := range s.Temps {
			if t.Temp > maxTemp.Temp {
				maxTemp = t
			}
		}
		tempStyle := lipgloss.NewStyle().Foreground(lipgloss.Color(coolColor))
		if maxTemp.Temp >= 85 {
			tempStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(criticalColor)).Bold(true)
		} else if maxTemp.Temp >= 70 {
			tempStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(hotColor))
		} else if maxTemp.Temp >= 50 {
			tempStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(warmColor))
		}
		extraLines = append(extraLines,
			fmt.Sprintf("🌡️ Max: %s (%s)",
				tempStyle.Render(fmt.Sprintf("%.0f°C", maxTemp.Temp)),
				truncate(maxTemp.Zone, 10)))
	}
	extraContent := ""
	if len(extraLines) == 0 {
		msg := "No GPU/Batt/Temp data"
		if !m.showGPU && !m.showBatt && !m.showTemps {
			msg = "All hidden (g/b/t to toggle)"
		} else if !m.showGPU || !m.showBatt || !m.showTemps {
			msg = "Some panels hidden (g/b/t)"
		}
		extraContent = subtleStyle.Render(msg)
	} else {
		extraContent = strings.Join(extraLines, "\n")
	}
	extraCardStyle := cardStyle
	if m.criticalTemp {
		extraCardStyle = alertCardStyle
	}
	extraCard := extraCardStyle.Render(lipgloss.JoinVertical(lipgloss.Left, titleStyle.Render("HARDWARE"), extraContent))

	row2 := lipgloss.JoinHorizontal(lipgloss.Top, netCard, diskCard, extraCard)

	// --- Row 3: Main Content (Procs left, PerCore right) ---

	// Process List (Left Column)
	// Calculate available height conservatively to ensure everything fits on one screen
	// header=3, row1=6, row2=9, footer=1, padding=3 -> ~22 lines used by other elements
	// Cap the process area height to prevent overflow
	availHeight := m.height - 22
	if availHeight > 20 {
		availHeight = 20 // Cap to prevent excessive vertical growth
	}
	if availHeight < 6 {
		availHeight = 6
	}

	row3 := func() string {
		// Use most of the horizontal space with many columns to minimize vertical height
		// This keeps everything visible on one screen with scrolling for additional processes
		filteredProcs := m.sortAndFilter(s.Top)
		totalProcs := len(filteredProcs)

		// Scroll indicator with badge for count
		scrollInfo := ""
		procCountBadge := ""
		if totalProcs > 0 {
			visible := m.visibleTopCapacity()
			endIdx := minInt(m.topOffset+visible, totalProcs)
			procCountBadge = " " + badgeStyle.Render(fmt.Sprintf("%d", totalProcs))
			scrollInfo = fmt.Sprintf(" [%d-%d of %d", m.topOffset+1, endIdx, totalProcs)
			if totalProcs > visible {
				scrollInfo += ", j/k/PgUp/PgDn"
			}
			scrollInfo += "]"
		}
		procLabel := titleStyle.Render("TOP PROCESSES") + procCountBadge + subtleStyle.Render(scrollInfo)

		// Wide screens: have a right panel with IO/FD leaders, throttled, and cores
		if m.width >= 160 {
			rightWidth := minInt(44, m.width/4) // Wider right panel for IO/FD data
			if rightWidth < 36 {
				rightWidth = 36
			}
			procAreaWidth := m.width - rightWidth - 3

			// Calculate columns based on process area width
			cols := 1
			if procAreaWidth >= 80 {
				cols = 2
			}
			if procAreaWidth >= 120 {
				cols = 3
			}
			if procAreaWidth >= 160 {
				cols = 4
			}

			procTable := renderProcessColumns(filteredProcs, cols, availHeight, procAreaWidth-4, m.topOffset, primaryColor)
			// Use focused style when a process is selected
			procCardStyle := cardStyle
			if m.selectedProc >= 0 {
				procCardStyle = focusedCardStyle
			}
			procCard := procCardStyle.Width(procAreaWidth).Height(availHeight).
				Render(lipgloss.JoinVertical(lipgloss.Left, procLabel, procTable))

			// Right panel with IO/FD leaders, throttled processes, and CPU cores
			var rightColContent string
			if m.showIOPanels {
				// Allocate space for IO TOP, FD TOP, THROTTLED, and CORES
				ioHeight := maxInt(4, availHeight/4)
				fdHeight := maxInt(3, availHeight/5)
				thHeight := maxInt(3, availHeight/5)

				ioTable := renderIOTable(m.topIO(s.Top), ioHeight, rightWidth-4)
				fdTable := renderFDTable(m.topFD(s.Top), fdHeight, rightWidth-4)
				throttledTable := renderProcessTableCompact(m.sortAndFilter(s.Throttled), thHeight, secondaryColor)
				coreBlock := renderCoreGridCompact(m.perCoreHist, rightWidth-4)

				// Use titleStyle for section headers and badgeStyle for throttled count
				throttledCount := len(m.sortAndFilter(s.Throttled))
				throttledBadge := ""
				if throttledCount > 0 {
					throttledBadge = " " + badgeStyle.Background(lipgloss.Color(secondaryColor)).Render(fmt.Sprintf("%d", throttledCount))
				}

				rightColContent = lipgloss.JoinVertical(lipgloss.Left,
					titleStyle.Background(lipgloss.Color(warningColor)).Render("⚡ IO TOP"),
					ioTable,
					titleStyle.Background(lipgloss.Color(warningColor)).Render("📂 FD TOP"),
					fdTable,
					titleStyle.Background(lipgloss.Color(secondaryColor)).Render("🔻 THROTTLED")+throttledBadge,
					throttledTable,
					titleStyle.Render("CPU CORES"),
					coreBlock,
				)
			} else {
				// Without IO panels, show more throttled and cores
				thHeight := maxInt(6, availHeight/3)
				throttledProcs := m.sortAndFilter(s.Throttled)
				throttledTable := renderProcessTableCompact(throttledProcs, thHeight, secondaryColor)
				coreBlock := renderCoreGrid(m.perCoreHist, rightWidth-4)

				// Badge for throttled count
				throttledBadge := ""
				if len(throttledProcs) > 0 {
					throttledBadge = " " + badgeStyle.Background(lipgloss.Color(secondaryColor)).Render(fmt.Sprintf("%d", len(throttledProcs)))
				}

				rightColContent = lipgloss.JoinVertical(lipgloss.Left,
					titleStyle.Background(lipgloss.Color(secondaryColor)).Render("🔻 THROTTLED")+throttledBadge,
					throttledTable,
					titleStyle.Render("CPU CORES"),
					coreBlock,
					subtleStyle.Render("(press i to show IO/FD panels)"),
				)
			}

			rightCard := cardStyle.Width(rightWidth).Height(availHeight).Render(rightColContent)
			return lipgloss.JoinHorizontal(lipgloss.Top, procCard, rightCard)
		}

		// Narrow screens: no right panel, full width for processes
		procAreaWidth := m.width - 2
		cols := 1
		if m.width >= 100 {
			cols = 2
		}
		if m.width >= 140 {
			cols = 3
		}

		procTable := renderProcessColumns(filteredProcs, cols, availHeight, procAreaWidth-4, m.topOffset, primaryColor)
		// Use focused style when a process is selected
		procCardStyle := cardStyle
		if m.selectedProc >= 0 {
			procCardStyle = focusedCardStyle
		}
		procCard := procCardStyle.Width(procAreaWidth).Height(availHeight).
			Render(lipgloss.JoinVertical(lipgloss.Left, procLabel, procTable))

		return procCard
	}()

	return lipgloss.JoinVertical(lipgloss.Left, row1, row2, row3)
}

func (m *Model) renderAnalysis(s model.Sample) string {
	availHeight := m.height - 4 // approximate header/padding

	// Hall of Shame (Left) - processes that have consumed the most CPU time
	shameHeight := availHeight
	shameRows := m.getHallOfShame(shameHeight - 4)
	shameTable := renderSimpleTable([]string{"COMMAND", "CPU-SEC"}, shameRows, 25, primaryColor)
	shameBadge := ""
	if len(shameRows) > 0 {
		shameBadge = " " + badgeStyle.Render(fmt.Sprintf("%d", len(shameRows)))
	}
	shameCard := cardStyle.Width(40).Height(shameHeight).Render(lipgloss.JoinVertical(lipgloss.Left,
		titleStyle.Render("🏆 HALL OF SHAME")+shameBadge,
		shameTable))

	// Frequent Flyers (Right) - processes that have been throttled most often
	freqRows := m.getFrequentFlyers(shameHeight - 4)
	freqTable := renderSimpleTable([]string{"COMMAND", "THROTTLED"}, freqRows, 25, secondaryColor)
	freqBadge := ""
	if len(freqRows) > 0 {
		freqBadge = " " + badgeStyle.Background(lipgloss.Color(secondaryColor)).Render(fmt.Sprintf("%d", len(freqRows)))
	}
	freqCard := cardStyle.Width(40).Height(shameHeight).Render(lipgloss.JoinVertical(lipgloss.Left,
		titleStyle.Background(lipgloss.Color(secondaryColor)).Render("✈️ FREQUENT FLYERS")+freqBadge,
		freqTable))

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
	// Build a visually appealing help screen using global styles
	helpTitleStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color(primaryColor)).
		Bold(true)
	keyStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color(warningColor)).
		Bold(true)
	descStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("#CCCCCC"))
	sectionStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color(accentColor)).
		Bold(true).
		MarginTop(1)

	var b strings.Builder

	// Use titleStyle for main header
	borderTop := "╔═══════════════════════════════════════════════════════════╗"
	borderBottom := "╚═══════════════════════════════════════════════════════════╝"
	title := titleStyle.Render("SYSMON - SYSTEM RESOURCE MONITOR")
	innerWidth := lipgloss.Width(borderTop) - 2 // subtract side borders
	padding := innerWidth - lipgloss.Width(title)
	if padding < 0 {
		padding = 0
	}
	padLeft := 1 // keep a small left margin inside the box
	if padLeft > padding {
		padLeft = padding
	}
	padRight := padding - padLeft

	left := helpTitleStyle.Render("║" + strings.Repeat(" ", padLeft))
	right := helpTitleStyle.Render(strings.Repeat(" ", padRight) + "║")

	b.WriteString(helpTitleStyle.Render(borderTop) + "\n")
	b.WriteString(left + title + right + "\n")
	b.WriteString(helpTitleStyle.Render(borderBottom) + "\n\n")

	b.WriteString(sectionStyle.Render("⌨️  NAVIGATION") + "\n")
	b.WriteString(keyStyle.Render("  q/Ctrl+C") + descStyle.Render("      Quit application") + "\n")
	b.WriteString(keyStyle.Render("  Tab/1-3") + descStyle.Render("       Switch tabs (Dashboard/Analysis/System)") + "\n")
	b.WriteString(keyStyle.Render("  j/k ↑/↓") + descStyle.Render("       Scroll process list / move selection") + "\n")
	b.WriteString(keyStyle.Render("  PgUp/PgDn") + descStyle.Render("     Page through process list") + "\n")
	b.WriteString(keyStyle.Render("  Home/End") + descStyle.Render("      Jump to start/end of list") + "\n")
	b.WriteString(keyStyle.Render("  Enter") + descStyle.Render("         Show process details modal") + "\n")
	b.WriteString(keyStyle.Render("  Esc") + descStyle.Render("           Clear selection/filter, close modal") + "\n")

	b.WriteString(sectionStyle.Render("🔍 FILTERING & SORTING") + "\n")
	b.WriteString(keyStyle.Render("  /") + descStyle.Render("             Start filter input (Enter=apply, Esc=cancel)") + "\n")
	b.WriteString(keyStyle.Render("  s") + descStyle.Render("             Cycle sort: CPU → MEM → IO → FD") + "\n")

	b.WriteString(sectionStyle.Render("🎛️  PANEL TOGGLES") + "\n")
	b.WriteString(keyStyle.Render("  g") + descStyle.Render("             Toggle GPU panel") + "\n")
	b.WriteString(keyStyle.Render("  b") + descStyle.Render("             Toggle Battery panel") + "\n")
	b.WriteString(keyStyle.Render("  i") + descStyle.Render("             Toggle IO/FD panels") + "\n")
	b.WriteString(keyStyle.Render("  t") + descStyle.Render("             Toggle Temperature panel") + "\n")
	b.WriteString(keyStyle.Render("  n") + descStyle.Render("             Toggle Inotify panel") + "\n")
	b.WriteString(keyStyle.Render("  c") + descStyle.Render("             Toggle Cgroups panel") + "\n")

	b.WriteString(sectionStyle.Render("⚙️  OTHER CONTROLS") + "\n")
	b.WriteString(keyStyle.Render("  f") + descStyle.Render("             Freeze/unfreeze updates") + "\n")
	b.WriteString(keyStyle.Render("  m") + descStyle.Render("             Toggle mouse support") + "\n")
	b.WriteString(keyStyle.Render("  I") + descStyle.Render("             Show ionice tip for top process") + "\n")
	b.WriteString(keyStyle.Render("  o") + descStyle.Render("             Toggle JSON output (SRPS_SYSMON_JSON_FILE)") + "\n")
	b.WriteString(keyStyle.Render("  ?/h") + descStyle.Render("           Toggle this help") + "\n")

	b.WriteString(sectionStyle.Render("🖱️  MOUSE SUPPORT") + "\n")
	b.WriteString(descStyle.Render("  Click on processes to select, scroll wheel to navigate") + "\n")

	b.WriteString(sectionStyle.Render("📊 VISUAL INDICATORS") + "\n")
	b.WriteString(descStyle.Render("  Gauges use gradient colors: ") +
		lipgloss.NewStyle().Foreground(lipgloss.Color(successColor)).Render("green") +
		descStyle.Render(" → ") +
		lipgloss.NewStyle().Foreground(lipgloss.Color(warningColor)).Render("yellow") +
		descStyle.Render(" → ") +
		lipgloss.NewStyle().Foreground(lipgloss.Color(criticalColor)).Render("red") + "\n")
	b.WriteString(descStyle.Render("  Alert badge blinks when CPU/MEM/Swap/Temp is critical") + "\n")
	b.WriteString(descStyle.Render("  Process rows highlight: ") +
		lipgloss.NewStyle().Foreground(lipgloss.Color(warningColor)).Render("gold=FD growth") +
		descStyle.Render(", ") +
		lipgloss.NewStyle().Foreground(lipgloss.Color(secondaryColor)).Render("pink=throttled") + "\n")

	b.WriteString(sectionStyle.Render("💡 TIPS") + "\n")
	b.WriteString(descStyle.Render("  Throttle IO: sudo ionice -c3 -p <pid>") + "\n")
	b.WriteString(descStyle.Render("  Lower priority: sudo renice +10 -p <pid>") + "\n")
	b.WriteString(descStyle.Render("  Limit new commands: limited <cmd> (systemd-run)") + "\n")

	b.WriteString("\n" + subtleStyle.Render("Press ? or h to close this help"))

	return cardStyle.Width(m.width - 4).Render(b.String())
}

func renderSimpleTable(headers []string, rows []string, width int, color string) string {
	var b strings.Builder

	// Header using tableHeaderStyle
	headStr := strings.Join(headers, " ")
	b.WriteString(tableHeaderStyle.Foreground(lipgloss.Color(color)).Render(headStr) + "\n")

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

// renderGauge is a convenience wrapper for renderGaugeEnhanced with defaults
// Use this for simple gauges where gradient coloring is desired
func renderGauge(label string, pct float64) string {
	return renderGaugeEnhanced(label, pct, primaryColor, true)
}

// interpolateColor creates a gradient color based on percentage (0-100)
// green -> yellow -> orange -> red
func interpolateColor(pct float64) string {
	if pct < 50 {
		// Green to Yellow: increase red, keep green high
		r := int(pct * 5.1) // 0 -> 255
		return fmt.Sprintf("#%02X%02X00", r, 255)
	} else if pct < 75 {
		// Yellow to Orange: keep red high, decrease green
		g := int(255 - (pct-50)*5.1) // 255 -> 127
		return fmt.Sprintf("#FF%02X00", g)
	} else {
		// Orange to Red: decrease green further
		g := int(127 - (pct-75)*5.1) // 127 -> 0
		if g < 0 {
			g = 0
		}
		return fmt.Sprintf("#FF%02X00", g)
	}
}

func renderGaugeEnhanced(label string, pct float64, baseColor string, useGradient bool) string {
	width := 20
	filled := int((pct / 100) * float64(width))
	if filled > width {
		filled = width
	}
	if filled < 0 {
		filled = 0
	}

	var bar strings.Builder
	if useGradient {
		// Build bar with gradient colors per character
		for i := 0; i < filled; i++ {
			charPct := float64(i+1) / float64(width) * 100
			c := interpolateColor(charPct)
			bar.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color(c)).Render("█"))
		}
		// Empty part
		emptyStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#333333"))
		bar.WriteString(emptyStyle.Render(strings.Repeat("░", width-filled)))
	} else {
		// Simple solid color with alert threshold
		style := lipgloss.NewStyle().Foreground(lipgloss.Color(baseColor))
		if pct > 90 {
			style = style.Foreground(lipgloss.Color(criticalColor))
		} else if pct > 75 {
			style = style.Foreground(lipgloss.Color(warningColor))
		}
		bar.WriteString(style.Render(strings.Repeat("█", filled)))
		bar.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("#333333")).Render(strings.Repeat("░", width-filled)))
	}

	// Value display with color based on severity
	valColor := "#FFFFFF"
	if pct > 90 {
		valColor = criticalColor
	} else if pct > 75 {
		valColor = warningColor
	}
	valStr := lipgloss.NewStyle().Foreground(lipgloss.Color(valColor)).Bold(true).Render(fmt.Sprintf(" %.0f%%", pct))

	return lipgloss.JoinVertical(lipgloss.Left,
		gaugeLabelStyle.Render(label),
		bar.String()+valStr,
	)
}

// renderMiniGauge renders a compact inline gauge
func renderMiniGauge(pct float64, width int) string {
	filled := int((pct / 100) * float64(width))
	if filled > width {
		filled = width
	}
	if filled < 0 {
		filled = 0
	}

	var bar strings.Builder
	for i := 0; i < filled; i++ {
		charPct := float64(i+1) / float64(width) * 100
		c := interpolateColor(charPct)
		bar.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color(c)).Render("▰"))
	}
	bar.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("#333333")).Render(strings.Repeat("▱", width-filled)))
	return bar.String()
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

// renderProcessColumns splits the process table into multiple narrow columns to avoid tall lists.
func renderProcessColumns(procs []model.Process, columns, height, totalWidth int, offset int, highlightColor string) string {
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
	if offset < 0 {
		offset = 0
	}
	if offset > len(procs) {
		offset = len(procs)
	}
	procs = procs[offset:]
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
	header := fmt.Sprintf("%-*s %5s %3s %5s %5s %5s %5s %4s", cmdWidth, "CMD", "PID", "NI", "CPU", "MEM", "Rk", "Wk", "FD")
	b.WriteString(tableHeaderStyle.Render(header) + "\n")

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

// renderProcessTableCompact renders a minimal process table for the right panel
func renderProcessTableCompact(procs []model.Process, height int, highlightColor string) string {
	var b strings.Builder
	// Compact header using tableHeaderStyle
	header := fmt.Sprintf("%-12s %5s %3s %5s", "CMD", "PID", "NI", "CPU%")
	b.WriteString(tableHeaderStyle.Render(header) + "\n")

	count := 0
	for _, p := range procs {
		if count >= height-1 {
			break
		}
		cmd := truncate(p.Command, 12)
		line := fmt.Sprintf("%-12s %5d %3d %5.1f", cmd, p.PID, p.Nice, p.CPU)

		style := rowStyle
		if p.Nice > 0 {
			style = style.Foreground(lipgloss.Color(highlightColor))
		} else if count%2 == 0 {
			style = dimStyle
		}
		b.WriteString(style.Render(line) + "\n")
		count++
	}
	return b.String()
}

// renderIOTable renders a table showing top IO consumers with read/write rates
func renderIOTable(procs []model.Process, height int, width int) string {
	var b strings.Builder
	cmdWidth := maxInt(8, width-24)

	for i, p := range procs {
		if i >= height {
			break
		}
		cmd := truncate(p.Command, cmdWidth)
		totalIO := p.ReadKBs + p.WriteKBs

		// Color based on IO intensity
		style := rowStyle
		if totalIO > 10000 { // > 10 MB/s
			style = lipgloss.NewStyle().Foreground(lipgloss.Color(secondaryColor)).Bold(true)
		} else if totalIO > 1000 { // > 1 MB/s
			style = lipgloss.NewStyle().Foreground(lipgloss.Color(warningColor))
		} else if i%2 == 0 {
			style = dimStyle
		}

		// Format: CMD R:xxxx W:xxxx
		line := fmt.Sprintf("%-*s R:%5.0f W:%5.0f", cmdWidth, cmd, p.ReadKBs, p.WriteKBs)
		b.WriteString(style.Render(line) + "\n")
	}
	return b.String()
}

// renderFDTable renders a table showing top FD consumers
func renderFDTable(procs []model.Process, height int, width int) string {
	var b strings.Builder
	cmdWidth := maxInt(8, width-16)

	for i, p := range procs {
		if i >= height {
			break
		}
		cmd := truncate(p.Command, cmdWidth)

		// Color based on FD count and growth
		style := rowStyle
		if p.FDDiff > 100 {
			style = lipgloss.NewStyle().Foreground(lipgloss.Color(secondaryColor)).Bold(true)
		} else if p.FDCount > 500 {
			style = lipgloss.NewStyle().Foreground(lipgloss.Color(warningColor))
		} else if p.FDCount > 100 {
			style = lipgloss.NewStyle().Foreground(lipgloss.Color(successColor))
		} else if i%2 == 0 {
			style = dimStyle
		}

		// Show FD count and diff if significant
		fdStr := fmt.Sprintf("%5d", p.FDCount)
		if p.FDDiff > 10 {
			fdStr = fmt.Sprintf("%5d +%d", p.FDCount, p.FDDiff)
		}

		line := fmt.Sprintf("%-*s %s", cmdWidth, cmd, fdStr)
		b.WriteString(style.Render(line) + "\n")
	}
	return b.String()
}

// renderCoreGridCompact renders a more compact CPU core grid for smaller spaces
func renderCoreGridCompact(hist map[int][]float64, width int) string {
	var keys []int
	for k := range hist {
		keys = append(keys, k)
	}
	sort.Ints(keys)

	// For many cores, show 4 per line with tiny sparklines
	coresPerLine := 4
	sparkWidth := 6

	var lines []string
	for i := 0; i < len(keys); i += coresPerLine {
		var lineParts []string
		for j := 0; j < coresPerLine && i+j < len(keys); j++ {
			c := keys[i+j]
			sp := renderSparklinePct(hist[c], sparkWidth, primaryColor)
			lineParts = append(lineParts, fmt.Sprintf("%2d%s", c, sp))
		}
		lines = append(lines, strings.Join(lineParts, " "))
	}

	// Limit to 4 lines max
	if len(lines) > 4 {
		lines = lines[:4]
	}

	return strings.Join(lines, "\n")
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

// renderSparklineWithStats renders a sparkline with min/max/avg annotations
func renderSparklineWithStats(values []float64, width int, color string) string {
	if len(values) == 0 {
		return strings.Repeat(" ", width)
	}

	// Calculate stats
	min, max, sum := values[0], values[0], 0.0
	for _, v := range values {
		if v < min {
			min = v
		}
		if v > max {
			max = v
		}
		sum += v
	}
	avg := sum / float64(len(values))

	// Take last N values for sparkline
	sparkWidth := width - 16 // Leave room for stats
	if sparkWidth < 5 {
		sparkWidth = 5
	}
	displayVals := values
	if len(displayVals) > sparkWidth {
		displayVals = displayVals[len(displayVals)-sparkWidth:]
	}

	chars := []rune(" ▂▃▄▅▆▇█")
	var b strings.Builder
	style := lipgloss.NewStyle().Foreground(lipgloss.Color(color))

	// Find the peak position for marker
	peakIdx := 0
	for i, v := range displayVals {
		if v == max {
			peakIdx = i
		}
		idx := 0
		if max > 0 {
			idx = int((v / max) * float64(len(chars)-1))
		}
		if idx < 0 {
			idx = 0
		}
		if idx >= len(chars) {
			idx = len(chars) - 1
		}
		// Highlight peak
		if i == peakIdx && max > 0 {
			b.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color(warningColor)).Render(string(chars[idx])))
		} else {
			b.WriteRune(chars[idx])
		}
	}

	// Add stats suffix
	statsStyle := subtleStyle
	stats := fmt.Sprintf(" ↑%.0f ↓%.0f ~%.0f", max, min, avg)
	return style.Render(b.String()) + statsStyle.Render(stats)
}

// renderProcDetailModal renders a modal with detailed process information
func (m *Model) renderProcDetailModal(s model.Sample) string {
	// Find the process by PID
	var proc *model.Process
	for i := range s.Top {
		if s.Top[i].PID == m.detailPID {
			proc = &s.Top[i]
			break
		}
	}
	if proc == nil {
		return "Process not found. Press ESC to close."
	}

	// Modal style with double border
	modalStyle := lipgloss.NewStyle().
		Border(lipgloss.DoubleBorder()).
		BorderForeground(lipgloss.Color(primaryColor)).
		Padding(1, 2).
		Width(60)

	// Content
	var content strings.Builder
	content.WriteString(lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color(primaryColor)).Render("PROCESS DETAILS"))
	content.WriteString("\n\n")

	// Process info rows
	infoStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	modalLabelStyle := lipgloss.NewStyle().Foreground(lipgloss.Color(labelColor)).Width(12)

	rows := []struct {
		label string
		value string
	}{
		{"Command", proc.Command},
		{"PID", fmt.Sprintf("%d", proc.PID)},
		{"Nice", fmt.Sprintf("%d", proc.Nice)},
		{"CPU", fmt.Sprintf("%.1f%%", proc.CPU)},
		{"Memory", fmt.Sprintf("%.1f%%", proc.Memory)},
		{"Read", fmt.Sprintf("%.1f kB/s", proc.ReadKBs)},
		{"Write", fmt.Sprintf("%.1f kB/s", proc.WriteKBs)},
		{"FD Count", fmt.Sprintf("%d", proc.FDCount)},
		{"FD Change", fmt.Sprintf("%+d", proc.FDDiff)},
	}

	for _, r := range rows {
		content.WriteString(modalLabelStyle.Render(r.label+":") + " " + infoStyle.Render(r.value) + "\n")
	}

	// Mini gauges for CPU and Memory
	content.WriteString("\n")
	content.WriteString(modalLabelStyle.Render("CPU:") + " " + renderMiniGauge(proc.CPU, 30) + "\n")
	content.WriteString(modalLabelStyle.Render("MEM:") + " " + renderMiniGauge(proc.Memory, 30) + "\n")

	// Action hints
	content.WriteString("\n")
	hintStyle := lipgloss.NewStyle().Foreground(lipgloss.Color(labelColor)).Italic(true)
	content.WriteString(hintStyle.Render("Tip: sudo ionice -c3 -p " + fmt.Sprintf("%d", proc.PID) + " to throttle IO"))
	content.WriteString("\n")
	content.WriteString(hintStyle.Render("     sudo renice +10 -p " + fmt.Sprintf("%d", proc.PID) + " to lower priority"))
	content.WriteString("\n\n")
	content.WriteString(subtleStyle.Render("Press ESC or Enter to close"))

	modal := modalStyle.Render(content.String())

	// Center the modal on screen with a dim background
	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, modal,
		lipgloss.WithWhitespaceChars("░"),
		lipgloss.WithWhitespaceForeground(lipgloss.Color("#111111")))
}

// renderSystemInfo renders the third tab with system details (temps, inotify, cgroups)
func (m *Model) renderSystemInfo(s model.Sample) string {
	availHeight := m.height - 4

	// Temperature panel
	tempsCard := m.renderTempsPanel(s.Temps, availHeight/3)

	// Inotify panel
	inotifyCard := m.renderInotifyPanel(s.Inotify, availHeight/3)

	// Cgroups panel
	cgroupsCard := m.renderCgroupsPanel(s.Cgroups, availHeight/3)

	// Layout: temps on left, inotify + cgroups on right
	leftWidth := m.width / 2
	rightWidth := m.width - leftWidth - 2

	leftCol := lipgloss.NewStyle().Width(leftWidth).Render(tempsCard)
	rightCol := lipgloss.JoinVertical(lipgloss.Left,
		lipgloss.NewStyle().Width(rightWidth).Render(inotifyCard),
		lipgloss.NewStyle().Width(rightWidth).Render(cgroupsCard))

	return lipgloss.JoinHorizontal(lipgloss.Top, leftCol, rightCol)
}

// renderTempsPanel renders temperature readings with thermal coloring
func (m *Model) renderTempsPanel(temps []model.Temp, height int) string {
	var content strings.Builder

	header := lipgloss.NewStyle().
		Foreground(lipgloss.Color(primaryColor)).
		Bold(true).
		Render("🌡️  TEMPERATURES")
	content.WriteString(header + "\n\n")

	if len(temps) == 0 {
		content.WriteString(subtleStyle.Render("No temperature sensors available\n"))
	} else {
		// Sort by temperature descending
		sortedTemps := make([]model.Temp, len(temps))
		copy(sortedTemps, temps)
		sort.Slice(sortedTemps, func(i, j int) bool {
			return sortedTemps[i].Temp > sortedTemps[j].Temp
		})

		maxShown := height - 3
		if maxShown < 1 {
			maxShown = 1
		}

		for i, t := range sortedTemps {
			if i >= maxShown {
				content.WriteString(subtleStyle.Render(fmt.Sprintf("  ... and %d more", len(sortedTemps)-maxShown)) + "\n")
				break
			}

			// Color based on temperature
			var tempStyle lipgloss.Style
			var icon string
			if t.Temp >= 85 {
				tempStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(criticalColor)).Bold(true)
				icon = "🔥"
			} else if t.Temp >= 70 {
				tempStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(hotColor))
				icon = "🟠"
			} else if t.Temp >= 50 {
				tempStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(warmColor))
				icon = "🟡"
			} else {
				tempStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(coolColor))
				icon = "🟢"
			}

			zone := truncate(t.Zone, 20)
			tempStr := tempStyle.Render(fmt.Sprintf("%5.1f°C", t.Temp))
			// Mini thermal bar
			barWidth := 15
			barPct := t.Temp / 100
			if barPct > 1 {
				barPct = 1
			}
			filled := int(barPct * float64(barWidth))
			bar := ""
			for j := 0; j < filled; j++ {
				pct := float64(j) / float64(barWidth) * 100
				bar += lipgloss.NewStyle().Foreground(lipgloss.Color(interpolateColor(pct))).Render("▰")
			}
			bar += lipgloss.NewStyle().Foreground(lipgloss.Color("#333333")).Render(strings.Repeat("▱", barWidth-filled))

			content.WriteString(fmt.Sprintf("%s %-20s %s %s\n", icon, zone, tempStr, bar))
		}
	}

	return cardStyle.Height(height).Render(content.String())
}

// renderInotifyPanel renders inotify watch statistics
func (m *Model) renderInotifyPanel(info model.Inotify, height int) string {
	var content strings.Builder

	header := lipgloss.NewStyle().
		Foreground(lipgloss.Color(primaryColor)).
		Bold(true).
		Render("👁️  INOTIFY WATCHES")
	content.WriteString(header + "\n\n")

	// Calculate usage percentage
	usagePct := 0.0
	if info.MaxUserWatches > 0 {
		usagePct = float64(info.NrWatches) / float64(info.MaxUserWatches) * 100
	}

	// Determine alert level
	var usageStyle lipgloss.Style
	if usagePct > 90 {
		usageStyle = criticalStyle
	} else if usagePct > 70 {
		usageStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(warningColor))
	} else {
		usageStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(successColor))
	}

	labelW := lipgloss.NewStyle().Foreground(lipgloss.Color(labelColor)).Width(16)
	valW := lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))

	content.WriteString(labelW.Render("Current:") + " " + usageStyle.Render(fmt.Sprintf("%d", info.NrWatches)) + "\n")
	content.WriteString(labelW.Render("Max User:") + " " + valW.Render(fmt.Sprintf("%d", info.MaxUserWatches)) + "\n")
	content.WriteString(labelW.Render("Max Instances:") + " " + valW.Render(fmt.Sprintf("%d", info.MaxUserInstances)) + "\n")
	content.WriteString("\n")
	content.WriteString(labelW.Render("Usage:") + " " + renderMiniGauge(usagePct, 20) + usageStyle.Render(fmt.Sprintf(" %.1f%%", usagePct)) + "\n")

	if usagePct > 80 {
		content.WriteString("\n")
		warnStyle := lipgloss.NewStyle().Foreground(lipgloss.Color(warningColor)).Italic(true)
		content.WriteString(warnStyle.Render("⚠ Running low on inotify watches!"))
	}

	return cardStyle.Height(height).Render(content.String())
}

// renderCgroupsPanel renders cgroup CPU usage summary
func (m *Model) renderCgroupsPanel(cgroups []model.Cgroup, height int) string {
	var content strings.Builder

	header := lipgloss.NewStyle().
		Foreground(lipgloss.Color(primaryColor)).
		Bold(true).
		Render("📦 CGROUP CPU USAGE")
	content.WriteString(header + "\n\n")

	if len(cgroups) == 0 {
		content.WriteString(subtleStyle.Render("No cgroup data available\n"))
	} else {
		// Sort by CPU descending
		sortedCgroups := make([]model.Cgroup, len(cgroups))
		copy(sortedCgroups, cgroups)
		sort.Slice(sortedCgroups, func(i, j int) bool {
			return sortedCgroups[i].CPU > sortedCgroups[j].CPU
		})

		maxShown := height - 3
		if maxShown < 1 {
			maxShown = 1
		}

		for i, cg := range sortedCgroups {
			if i >= maxShown {
				content.WriteString(subtleStyle.Render(fmt.Sprintf("  ... and %d more", len(sortedCgroups)-maxShown)) + "\n")
				break
			}

			name := truncate(cg.Name, 25)
			cpuPct := cg.CPU

			// Color based on CPU usage
			var cpuStyle lipgloss.Style
			if cpuPct > 80 {
				cpuStyle = criticalStyle
			} else if cpuPct > 50 {
				cpuStyle = lipgloss.NewStyle().Foreground(lipgloss.Color(warningColor))
			} else {
				cpuStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
			}

			bar := renderMiniGauge(cpuPct, 12)
			content.WriteString(fmt.Sprintf("%-25s %s %s\n", name, bar, cpuStyle.Render(fmt.Sprintf("%5.1f%%", cpuPct))))
		}
	}

	return cardStyle.Height(height).Render(content.String())
}

// --- Scrolling helpers for the Top table ---

func (m *Model) topLayout() (columns int, maxRows int) {
	availHeight := m.height - 22
	if availHeight > 20 {
		availHeight = 20 // Match the cap in renderDashboard
	}
	if availHeight < 6 {
		availHeight = 6
	}

	// Calculate columns based on screen width (matches renderDashboard logic)
	if m.width >= 160 {
		// Wide screens: have a right panel for IO/FD/throttled/cores
		rightWidth := minInt(44, m.width/4)
		if rightWidth < 36 {
			rightWidth = 36
		}
		procAreaWidth := m.width - rightWidth - 3
		columns = 1
		if procAreaWidth >= 80 {
			columns = 2
		}
		if procAreaWidth >= 120 {
			columns = 3
		}
		if procAreaWidth >= 160 {
			columns = 4
		}
	} else {
		// Narrow screens: no right panel, full width for processes
		columns = 1
		if m.width >= 100 {
			columns = 2
		}
		if m.width >= 140 {
			columns = 3
		}
	}

	maxRows = availHeight - 1
	if maxRows < 1 {
		maxRows = 1
	}
	return
}

func (m *Model) visibleTopCapacity() int {
	cols, rows := m.topLayout()
	return maxInt(1, cols*rows)
}

func (m *Model) maxTopOffset() int {
	total := len(m.sortAndFilter(m.latest.Top))
	capacity := m.visibleTopCapacity()
	maxOff := total - capacity
	if maxOff < 0 {
		return 0
	}
	return maxOff
}

func (m *Model) clampTopOffset() {
	maxOff := m.maxTopOffset()
	if m.topOffset > maxOff {
		m.topOffset = maxOff
	}
	if m.topOffset < 0 {
		m.topOffset = 0
	}
}

func (m *Model) bumpTopOffset(delta int) {
	m.topOffset += delta
	m.clampTopOffset()
}

func (m *Model) visibleTopPage() int {
	_, rows := m.topLayout()
	if rows < 1 {
		return 1
	}
	return rows
}

func (m *Model) jumpTopEnd() {
	m.topOffset = m.maxTopOffset()
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
	// Sort based on current sort key
	sort.Slice(filtered, func(i, j int) bool {
		switch m.sortKey {
		case "mem":
			return filtered[i].Memory > filtered[j].Memory
		case "io":
			return (filtered[i].ReadKBs + filtered[i].WriteKBs) > (filtered[j].ReadKBs + filtered[j].WriteKBs)
		case "fd":
			return filtered[i].FDCount > filtered[j].FDCount
		default: // "cpu"
			return filtered[i].CPU > filtered[j].CPU
		}
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
	p := tea.NewProgram(
		New(cfg),
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(), // Enable mouse support
	)
	_, err := p.Run()
	return err
}
