// Package breadcrumb provides a horizontal step trail with left-truncation.
// Steps are displayed as ✓ done → ● active → ○ pending, colored via the
// active theme.
package breadcrumb

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/Masaq/theme"
)

// Status represents the state of a breadcrumb step.
type Status int

const (
	// Pending means the step has not started.
	Pending Status = iota
	// Active means the step is currently in progress.
	Active
	// Done means the step has completed.
	Done
)

// Step is a single entry in the breadcrumb trail.
type Step struct {
	Label  string
	Status Status
}

// Model is a horizontal breadcrumb trail.
type Model struct {
	width int
	steps []Step
}

// New creates a breadcrumb with the given display width.
func New(width int) Model {
	if width < 0 {
		width = 0
	}
	return Model{width: width}
}

// SetSteps replaces all steps.
func (m *Model) SetSteps(steps []Step) {
	m.steps = make([]Step, len(steps))
	copy(m.steps, steps)
}

// Push adds a new step as Active, transitioning the previous Active step to Done.
func (m *Model) Push(label string) {
	for i := range m.steps {
		if m.steps[i].Status == Active {
			m.steps[i].Status = Done
		}
	}
	m.steps = append(m.steps, Step{Label: label, Status: Active})
}

// Complete marks the current Active step as Done.
func (m *Model) Complete() {
	for i := range m.steps {
		if m.steps[i].Status == Active {
			m.steps[i].Status = Done
			return
		}
	}
}

// View renders the breadcrumb as a single-line string with left-truncation.
func (m Model) View() string {
	if m.width == 0 || len(m.steps) == 0 {
		return ""
	}

	sem := theme.Current().Semantic()
	doneStyle := lipgloss.NewStyle().Foreground(sem.Success.Color())
	activeStyle := lipgloss.NewStyle().Foreground(sem.Active.Color()).Bold(true)
	pendingStyle := lipgloss.NewStyle().Foreground(sem.Muted.Color())
	sepStyle := lipgloss.NewStyle().Foreground(sem.FgDim.Color())

	sep := sepStyle.Render(" → ")
	sepLen := 4 // " → " is 4 display columns (→ is single-width)

	type rendered struct {
		text    string
		dispLen int
	}

	// Render all steps.
	items := make([]rendered, len(m.steps))
	for i, s := range m.steps {
		var prefix, label string
		var prefixLen int
		switch s.Status {
		case Done:
			prefix = doneStyle.Render("✓ ")
			label = doneStyle.Render(s.Label)
			prefixLen = 2
		case Active:
			prefix = activeStyle.Render("● ")
			label = activeStyle.Render(s.Label)
			prefixLen = 2
		default:
			prefix = pendingStyle.Render("○ ")
			label = pendingStyle.Render(s.Label)
			prefixLen = 2
		}
		items[i] = rendered{
			text:    prefix + label,
			dispLen: prefixLen + len(s.Label),
		}
	}

	// Calculate total width.
	totalLen := 0
	for i, it := range items {
		totalLen += it.dispLen
		if i > 0 {
			totalLen += sepLen
		}
	}

	// Left-truncation: drop leftmost items and prepend "…" if over width.
	startIdx := 0
	ellipsis := "… "
	ellipsisLen := 2

	if totalLen > m.width {
		for startIdx < len(items)-1 {
			// Remove leftmost item.
			removed := items[startIdx].dispLen
			if startIdx > 0 {
				removed += sepLen
			} else if startIdx+1 < len(items) {
				removed += sepLen // remove the sep after it
			}
			totalLen -= removed
			startIdx++
			// Account for ellipsis prefix.
			if totalLen+ellipsisLen <= m.width {
				break
			}
		}
	}

	var sb strings.Builder
	if startIdx > 0 {
		sb.WriteString(sepStyle.Render(ellipsis))
	}
	first := true
	for i := startIdx; i < len(items); i++ {
		if !first {
			sb.WriteString(sep)
		}
		sb.WriteString(items[i].text)
		first = false
	}
	return sb.String()
}
