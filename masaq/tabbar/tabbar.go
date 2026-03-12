// Package tabbar provides a horizontal tab selector with number-key hotkeys.
// It implements the Bubble Tea Model interface and emits ChangedMsg when the
// active tab changes.
package tabbar

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/Masaq/theme"
)

// Tab defines a single tab with a display label and an optional keyboard shortcut.
type Tab struct {
	Label string
	Key   string // single char shortcut (e.g., "1", "c")
}

// ChangedMsg is emitted when the active tab changes.
type ChangedMsg struct {
	Index int
}

// Model is a horizontal tab bar implementing tea.Model.
type Model struct {
	tabs   []Tab
	active int
	width  int
}

// New creates a tab bar from the given tabs.
func New(tabs []Tab) Model {
	t := make([]Tab, len(tabs))
	copy(t, tabs)
	return Model{tabs: t}
}

// Init returns no initial command.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles keyboard input for tab switching.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		key := msg.String()

		// Number keys 1-9 for direct selection.
		if len(key) == 1 && key[0] >= '1' && key[0] <= '9' {
			idx := int(key[0]-'1')
			if idx < len(m.tabs) && idx != m.active {
				m.active = idx
				return m, func() tea.Msg { return ChangedMsg{Index: m.active} }
			}
			return m, nil
		}

		// Check tab Key shortcuts.
		for i, t := range m.tabs {
			if t.Key != "" && t.Key == key && i != m.active {
				m.active = i
				return m, func() tea.Msg { return ChangedMsg{Index: m.active} }
			}
		}

		// Arrow keys for cycling.
		switch key {
		case "left", "shift+tab":
			if len(m.tabs) > 0 {
				m.active = (m.active - 1 + len(m.tabs)) % len(m.tabs)
				return m, func() tea.Msg { return ChangedMsg{Index: m.active} }
			}
		case "right", "tab":
			if len(m.tabs) > 0 {
				m.active = (m.active + 1) % len(m.tabs)
				return m, func() tea.Msg { return ChangedMsg{Index: m.active} }
			}
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
	}
	return m, nil
}

// View renders the tab bar as a single-line string.
func (m Model) View() string {
	if len(m.tabs) == 0 {
		return ""
	}

	sem := theme.Current().Semantic()
	activeStyle := lipgloss.NewStyle().
		Foreground(sem.Primary.Color()).
		Bold(true).
		Underline(true)
	inactiveStyle := lipgloss.NewStyle().
		Foreground(sem.FgDim.Color())

	var sb strings.Builder
	for i, t := range m.tabs {
		if i > 0 {
			sb.WriteRune(' ')
		}

		// Build label with optional number prefix.
		label := t.Label
		if i < 9 {
			label = string(rune('1'+i)) + " " + label
		}

		if i == m.active {
			sb.WriteString("[")
			sb.WriteString(activeStyle.Render(label))
			sb.WriteString("]")
		} else {
			sb.WriteString("[")
			sb.WriteString(inactiveStyle.Render(label))
			sb.WriteString("]")
		}
	}

	// Truncation: if we have a width and the rendered text exceeds it,
	// truncate from the right. We do a simple rune-based truncation on
	// the plain text length.
	result := sb.String()
	if m.width > 0 {
		plainLen := len(stripANSI(result))
		if plainLen > m.width && m.width > 3 {
			// Re-render with fewer tabs until it fits.
			for maxTabs := len(m.tabs) - 1; maxTabs >= 1; maxTabs-- {
				trimmed := m.renderTabs(maxTabs, activeStyle, inactiveStyle)
				if len(stripANSI(trimmed)) <= m.width {
					return trimmed
				}
			}
		}
	}
	return result
}

// renderTabs renders up to n tabs.
func (m Model) renderTabs(n int, activeStyle, inactiveStyle lipgloss.Style) string {
	var sb strings.Builder
	for i := 0; i < n && i < len(m.tabs); i++ {
		if i > 0 {
			sb.WriteRune(' ')
		}
		label := m.tabs[i].Label
		if i < 9 {
			label = string(rune('1'+i)) + " " + label
		}
		if i == m.active {
			sb.WriteString("[")
			sb.WriteString(activeStyle.Render(label))
			sb.WriteString("]")
		} else {
			sb.WriteString("[")
			sb.WriteString(inactiveStyle.Render(label))
			sb.WriteString("]")
		}
	}
	return sb.String()
}

// Active returns the index of the currently active tab.
func (m Model) Active() int {
	return m.active
}

// SetActive sets the active tab by index. Out-of-range values are clamped.
func (m *Model) SetActive(index int) {
	if len(m.tabs) == 0 {
		return
	}
	if index < 0 {
		index = 0
	}
	if index >= len(m.tabs) {
		index = len(m.tabs) - 1
	}
	m.active = index
}

// stripANSI removes ANSI escape sequences for width measurement.
func stripANSI(s string) string {
	var out strings.Builder
	inEsc := false
	for _, r := range s {
		if r == '\033' {
			inEsc = true
			continue
		}
		if inEsc {
			if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') {
				inEsc = false
			}
			continue
		}
		out.WriteRune(r)
	}
	return out.String()
}
