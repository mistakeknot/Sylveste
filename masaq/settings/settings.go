// Package settings provides a Bubble Tea sub-model for interactive settings
// display and editing. It renders a navigable list of settings with current
// values and supports boolean toggle and enum cycling.
package settings

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/Masaq/theme"
)

// EntryType classifies a setting for UI interaction.
type EntryType int

const (
	TypeBool EntryType = iota // Toggle on/off
	TypeEnum                  // Cycle through Options slice
)

// Entry describes a single setting for display and editing.
type Entry struct {
	Key         string
	Description string
	Type        EntryType
	Value       string   // current value as string ("on"/"off" for bool)
	Options     []string // for TypeEnum: allowed values in cycle order
}

// ChangedMsg is emitted when a setting value changes.
type ChangedMsg struct {
	Key      string
	OldValue string
	NewValue string
}

// DismissedMsg is emitted when the user presses Esc.
type DismissedMsg struct{}

// Model holds the state for an interactive settings overlay.
type Model struct {
	title   string
	entries []Entry
	cursor  int
	width   int
}

// New creates a settings model with the given title and entries.
func New(title string, entries []Entry) Model {
	return Model{
		title:   title,
		entries: entries,
		width:   80,
	}
}

// SetWidth sets the rendering width and returns the updated model.
func (m Model) SetWidth(w int) Model {
	m.width = w
	return m
}

// Cursor returns the current cursor position.
func (m Model) Cursor() int {
	return m.cursor
}

// Entries returns a copy of the entry list.
func (m Model) Entries() []Entry {
	out := make([]Entry, len(m.entries))
	copy(out, m.entries)
	return out
}

// UpdateEntry replaces the entry at index i. Used by the host to sync
// values after handling ChangedMsg.
func (m Model) UpdateEntry(i int, e Entry) Model {
	if i >= 0 && i < len(m.entries) {
		m.entries[i] = e
	}
	return m
}

// Init implements tea.Model. No initial command is needed.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles key messages for navigation and editing.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		n := len(m.entries)
		if n == 0 {
			return m, nil
		}

		switch msg.Type {
		case tea.KeyDown:
			m.cursor = (m.cursor + 1) % n
		case tea.KeyUp:
			m.cursor = (m.cursor - 1 + n) % n
		case tea.KeyEsc:
			return m, func() tea.Msg { return DismissedMsg{} }
		case tea.KeyEnter, tea.KeySpace:
			return m.toggleCurrent()
		case tea.KeyRunes:
			if len(msg.Runes) == 1 {
				r := msg.Runes[0]
				if r >= '1' && r <= '9' {
					idx := int(r - '1')
					if idx < n {
						m.cursor = idx
					}
				}
			}
		}
	}
	return m, nil
}

// toggleCurrent toggles the current entry and emits a ChangedMsg.
func (m Model) toggleCurrent() (Model, tea.Cmd) {
	e := &m.entries[m.cursor]
	old := e.Value

	switch e.Type {
	case TypeBool:
		if e.Value == "on" {
			e.Value = "off"
		} else {
			e.Value = "on"
		}
	case TypeEnum:
		if len(e.Options) > 0 {
			idx := indexOf(e.Options, e.Value)
			e.Value = e.Options[(idx+1)%len(e.Options)]
		}
	}

	if e.Value == old {
		return m, nil
	}

	changed := ChangedMsg{
		Key:      e.Key,
		OldValue: old,
		NewValue: e.Value,
	}
	return m, func() tea.Msg { return changed }
}

// View renders the settings list.
func (m Model) View() string {
	c := theme.Current().Semantic()

	titleStyle := lipgloss.NewStyle().
		Foreground(c.Primary.Color()).
		Bold(true)

	cursorStyle := lipgloss.NewStyle().
		Foreground(c.Success.Color())

	keySelectedStyle := lipgloss.NewStyle().
		Foreground(c.Primary.Color()).
		Bold(true)

	keyNormalStyle := lipgloss.NewStyle().
		Foreground(c.FgDim.Color())

	valOnStyle := lipgloss.NewStyle().
		Foreground(c.Success.Color())

	valOffStyle := lipgloss.NewStyle().
		Foreground(c.Muted.Color())

	descStyle := lipgloss.NewStyle().
		Foreground(c.Muted.Color())

	hintStyle := lipgloss.NewStyle().
		Foreground(c.FgDim.Color())

	var b strings.Builder
	b.WriteString(titleStyle.Render(m.title))
	b.WriteByte('\n')

	// Compute max key length for dot-padding
	maxKey := 0
	for _, e := range m.entries {
		if len(e.Key) > maxKey {
			maxKey = len(e.Key)
		}
	}

	for i, e := range m.entries {
		// Cursor indicator
		if i == m.cursor {
			b.WriteString(cursorStyle.Render("▸ "))
		} else {
			b.WriteString("  ")
		}

		// Key name
		if i == m.cursor {
			b.WriteString(keySelectedStyle.Render(e.Key))
		} else {
			b.WriteString(keyNormalStyle.Render(e.Key))
		}

		// Dot padding
		dots := maxKey - len(e.Key) + 2
		if dots < 2 {
			dots = 2
		}
		b.WriteString(descStyle.Render(" " + strings.Repeat(".", dots) + " "))

		// Value
		val := e.Value
		switch {
		case e.Type == TypeBool && val == "on":
			b.WriteString(valOnStyle.Render(val))
		case e.Type == TypeBool && val == "off":
			b.WriteString(valOffStyle.Render(val))
		default:
			b.WriteString(val)
		}

		b.WriteByte('\n')
	}

	// Footer hint
	b.WriteByte('\n')
	b.WriteString(hintStyle.Render("  ↑↓ navigate  Enter toggle  Esc close"))
	b.WriteByte('\n')

	return b.String()
}

// indexOf returns the index of s in slice, or 0 if not found.
func indexOf(slice []string, s string) int {
	for i, v := range slice {
		if strings.EqualFold(v, s) {
			return i
		}
	}
	return 0
}
