// Package statusbar provides a single-row status strip with named slots for
// persistent display at the top or bottom of a terminal screen.
package statusbar

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/Masaq/theme"
)

// Slot is a single label-value pair in the status bar.
type Slot struct {
	Label string
	Value string
	Color lipgloss.Color // optional override; zero value means use theme default
}

// Model is a slot-based status bar.
type Model struct {
	width int
	slots []Slot
}

// New creates a status bar with the given display width.
func New(width int) Model {
	if width < 0 {
		width = 0
	}
	return Model{width: width}
}

// SetSlots replaces all slots.
func (m *Model) SetSlots(slots []Slot) {
	m.slots = slots
}

// SetSlot updates the value of the slot with the given label, or appends a new
// slot if no match is found.
func (m *Model) SetSlot(label, value string) {
	for i := range m.slots {
		if m.slots[i].Label == label {
			m.slots[i].Value = value
			return
		}
	}
	m.slots = append(m.slots, Slot{Label: label, Value: value})
}

// Height returns the height of the status bar (always 1).
func (m Model) Height() int { return 1 }

// View renders the status bar as a single-line string.
func (m Model) View() string {
	if m.width == 0 || len(m.slots) == 0 {
		return ""
	}

	sem := theme.Current().Semantic()
	sepStyle := lipgloss.NewStyle().Foreground(sem.Border.Color())
	labelStyle := lipgloss.NewStyle().Foreground(sem.FgDim.Color())
	valueStyle := lipgloss.NewStyle().Foreground(sem.Fg.Color())

	sep := sepStyle.Render("  │  ")
	sepLen := 5 // "  │  " is 5 display columns

	// Build segments and measure.
	type segment struct {
		rendered string
		dispLen  int
	}
	var segs []segment
	for _, s := range m.slots {
		var rendered string
		var dispLen int
		if s.Label != "" {
			lbl := labelStyle.Render(s.Label + ": ")
			lblLen := len(s.Label) + 2 // "label: "
			var val string
			if s.Color != "" {
				val = lipgloss.NewStyle().Foreground(s.Color).Render(s.Value)
			} else {
				val = valueStyle.Render(s.Value)
			}
			valLen := len(s.Value)
			rendered = lbl + val
			dispLen = lblLen + valLen
		} else {
			if s.Color != "" {
				rendered = lipgloss.NewStyle().Foreground(s.Color).Render(s.Value)
			} else {
				rendered = valueStyle.Render(s.Value)
			}
			dispLen = len(s.Value)
		}
		segs = append(segs, segment{rendered: rendered, dispLen: dispLen})
	}

	// Truncate from the right until it fits (1 char left padding).
	padLen := 1
	for len(segs) > 0 {
		total := padLen
		for i, s := range segs {
			total += s.dispLen
			if i > 0 {
				total += sepLen
			}
		}
		if total <= m.width {
			break
		}
		segs = segs[:len(segs)-1]
	}

	if len(segs) == 0 {
		return ""
	}

	var sb strings.Builder
	sb.WriteString(" ") // left padding
	for i, s := range segs {
		if i > 0 {
			sb.WriteString(sep)
		}
		sb.WriteString(s.rendered)
	}
	return sb.String()
}
