// Package minsize provides a terminal minimum-size guard for Bubble Tea
// applications. When the terminal is smaller than the configured minimum,
// View renders a centered warning instead of the main UI.
package minsize

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/Masaq/theme"
)

// Model checks terminal dimensions against minimum requirements.
type Model struct {
	MinWidth  int
	MinHeight int

	// Current terminal size, updated by the consumer on tea.WindowSizeMsg.
	Width  int
	Height int
}

// New creates a minimum-size guard with the given thresholds.
func New(minWidth, minHeight int) Model {
	return Model{
		MinWidth:  minWidth,
		MinHeight: minHeight,
	}
}

// SetSize updates the current terminal dimensions.
func (m *Model) SetSize(w, h int) {
	m.Width = w
	m.Height = h
}

// ShouldBlock returns true when the terminal is too small for the application.
func (m Model) ShouldBlock() bool {
	return m.Width < m.MinWidth || m.Height < m.MinHeight
}

// View renders a centered warning message when the terminal is too small.
// Returns empty string when the terminal meets minimum requirements.
func (m Model) View() string {
	if !m.ShouldBlock() {
		return ""
	}

	sem := theme.Current().Semantic()
	warnStyle := lipgloss.NewStyle().Foreground(sem.Warning.Color())
	dimStyle := lipgloss.NewStyle().Foreground(sem.FgDim.Color())

	title := warnStyle.Render("Terminal too small")
	detail := dimStyle.Render(fmt.Sprintf("Need %d×%d, have %d×%d",
		m.MinWidth, m.MinHeight, m.Width, m.Height))

	// Center vertically and horizontally.
	lines := []string{title, detail}
	maxLen := maxDisplayLen(m.MinWidth, m.MinHeight, m.Width, m.Height)

	var sb strings.Builder
	topPad := (m.Height - len(lines)) / 2
	if topPad < 0 {
		topPad = 0
	}
	for i := 0; i < topPad; i++ {
		sb.WriteByte('\n')
	}
	for i, line := range lines {
		leftPad := (m.Width - maxLen) / 2
		if leftPad < 0 {
			leftPad = 0
		}
		if i > 0 {
			sb.WriteByte('\n')
		}
		sb.WriteString(strings.Repeat(" ", leftPad))
		sb.WriteString(line)
	}
	return sb.String()
}

// maxDisplayLen returns the display width of the longer line in the warning.
func maxDisplayLen(minW, minH, curW, curH int) int {
	title := len("Terminal too small")
	detail := len(fmt.Sprintf("Need %d×%d, have %d×%d", minW, minH, curW, curH))
	if title > detail {
		return title
	}
	return detail
}
