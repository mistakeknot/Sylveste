// Package question provides a Bubble Tea sub-model for structured multi-choice
// questions. It renders a prompt with selectable options and emits a SelectedMsg
// when the user confirms their choice.
package question

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/masaq/theme"
)

// Option is a single selectable choice.
type Option struct {
	Label       string
	Description string
}

// SelectedMsg is emitted when the user confirms a selection.
type SelectedMsg struct {
	Index int
	Label string
}

// Model holds the state for a multi-choice question widget.
type Model struct {
	question string
	options  []Option
	cursor   int
}

// New creates a question model with the given prompt and options.
func New(question string, options []Option) Model {
	return Model{
		question: question,
		options:  options,
	}
}

// Question returns the prompt text.
func (m Model) Question() string {
	return m.question
}

// Options returns a copy of the option list.
func (m Model) Options() []Option {
	out := make([]Option, len(m.options))
	copy(out, m.options)
	return out
}

// Cursor returns the current cursor position.
func (m Model) Cursor() int {
	return m.cursor
}

// Init implements tea.Model. No initial command is needed.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles key messages to navigate and select options.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		n := len(m.options)
		if n == 0 {
			return m, nil
		}

		switch msg.Type {
		case tea.KeyDown:
			m.cursor = (m.cursor + 1) % n
		case tea.KeyUp:
			m.cursor = (m.cursor - 1 + n) % n
		case tea.KeyEnter:
			selected := m.options[m.cursor]
			return m, func() tea.Msg {
				return SelectedMsg{Index: m.cursor, Label: selected.Label}
			}
		case tea.KeyRunes:
			if len(msg.Runes) == 1 {
				r := msg.Runes[0]
				if r >= '1' && r <= '9' {
					idx := int(r - '1')
					if idx < n {
						m.cursor = idx
						selected := m.options[idx]
						return m, func() tea.Msg {
							return SelectedMsg{Index: idx, Label: selected.Label}
						}
					}
				}
			}
		}
	}
	return m, nil
}

// View renders the question and its options.
func (m Model) View() string {
	c := theme.Current().Semantic()

	questionStyle := lipgloss.NewStyle().
		Foreground(c.Primary.Color()).
		Bold(true)

	cursorStyle := lipgloss.NewStyle().
		Foreground(c.Success.Color())

	labelSelectedStyle := lipgloss.NewStyle().
		Foreground(c.Success.Color()).
		Bold(true)

	descStyle := lipgloss.NewStyle().
		Foreground(c.Muted.Color())

	var b strings.Builder
	b.WriteString(questionStyle.Render(m.question))
	b.WriteByte('\n')

	for i, opt := range m.options {
		indicator := "  "
		if i == m.cursor {
			indicator = cursorStyle.Render("\u25b8 ")
		}

		label := opt.Label
		if i == m.cursor {
			label = labelSelectedStyle.Render(label)
		}

		line := fmt.Sprintf("%s%s", indicator, label)
		if opt.Description != "" {
			line += " " + descStyle.Render(opt.Description)
		}

		b.WriteString(line)
		if i < len(m.options)-1 {
			b.WriteByte('\n')
		}
	}

	return b.String()
}
