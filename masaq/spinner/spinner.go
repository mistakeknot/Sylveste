// Package spinner provides animated spinner models for Bubble Tea applications.
// Spinners cycle through a sequence of frames at a configurable interval,
// rendering with theme-aware brand colors.
package spinner

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/Masaq/theme"
)

// Frames defines a set of animation frames.
type Frames []string

// Common frame sets.
var (
	Dots    = Frames{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
	Line    = Frames{"|", "/", "—", "\\"}
	Ellipsis = Frames{"   ", ".  ", ".. ", "..."}
	Pulse   = Frames{"○", "◎", "●", "◎"}
)

// DefaultInterval is the time between frame advances.
const DefaultInterval = 80 * time.Millisecond

// TickMsg advances the spinner by one frame. The ID field ensures that
// only the spinner that started the tick sequence consumes the message.
type TickMsg struct {
	ID int
}

// Model is an animated spinner.
type Model struct {
	Frames   Frames
	Interval time.Duration
	Label    string // optional text after the spinner character

	id    int
	frame int
}

var nextID int

// New creates a spinner with the default dot frames.
func New() Model {
	nextID++
	return Model{
		Frames:   Dots,
		Interval: DefaultInterval,
		id:       nextID,
	}
}

// Tick returns a command that sends a TickMsg after the configured interval.
func (m Model) Tick() tea.Cmd {
	id := m.id
	interval := m.Interval
	return tea.Tick(interval, func(time.Time) tea.Msg {
		return TickMsg{ID: id}
	})
}

// Update advances the frame if the tick belongs to this spinner.
// Returns the updated model and the next tick command.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	if tick, ok := msg.(TickMsg); ok && tick.ID == m.id {
		m.frame = (m.frame + 1) % len(m.Frames)
		return m, m.Tick()
	}
	return m, nil
}

// View renders the current frame with the theme's Primary color.
// Returns empty string for a zero-value spinner (no frames).
func (m Model) View() string {
	if len(m.Frames) == 0 {
		return ""
	}
	c := theme.Current().Semantic()
	style := lipgloss.NewStyle().Foreground(c.Primary.Color())

	frame := m.Frames[m.frame%len(m.Frames)]
	if m.Label != "" {
		return style.Render(frame) + " " + style.Render(m.Label)
	}
	return style.Render(frame)
}
