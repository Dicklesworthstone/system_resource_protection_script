package ui

import (
	"context"
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/Dicklesworthstone/system_resource_protection_script/internal/config"
	"github.com/Dicklesworthstone/system_resource_protection_script/internal/model"
	"github.com/Dicklesworthstone/system_resource_protection_script/internal/sampler"
)

// Model wires sampler output into a minimal Bubble Tea view.
type Model struct {
	cfg     config.Config
	latest  model.Sample
	stream  <-chan model.Sample
	ctxCancel context.CancelFunc
}

func New(cfg config.Config) *Model {
	ctx, cancel := context.WithCancel(context.Background())
	s := sampler.New(cfg.Interval)
	return &Model{cfg: cfg, stream: s.Stream(ctx), ctxCancel: cancel}
}

func (m *Model) Init() tea.Cmd { return tickCmd() }

func tickCmd() tea.Cmd { return tea.Tick(time.Second/4, func(time.Time) tea.Msg { return tickMsg{} }) }

type tickMsg struct{}
type sampleMsg model.Sample

func (m *Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			m.ctxCancel();
			return m, tea.Quit
		}
	case tickMsg:
		select {
		case samp, ok := <-m.stream:
			if ok {
				m.latest = samp
			}
		default:
		}
		return m, tickCmd()
	}
	return m, nil
}

var (
	headerStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("36"))
	labelStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
)

func (m *Model) View() string {
	ls := m.latest
	return fmt.Sprintf("%s\n%s %s\n%s %s\n",
		headerStyle.Render("SYSMon (Go stub)"),
		labelStyle.Render("Time:"), ls.Timestamp.Format(time.RFC3339),
		labelStyle.Render("Interval:"), ls.Interval.String(),
	)
}

// RunTUI starts the Bubble Tea program.
func RunTUI(cfg config.Config) error {
	prog := tea.NewProgram(New(cfg))
	_, err := prog.Run()
	return err
}
