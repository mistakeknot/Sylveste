// Package meter provides a bounded horizontal progress gauge with an optional
// forecast overlay. It renders in a single terminal row using block and shade
// characters, colored via the active theme.
package meter

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/Masaq/theme"
)

// Model is a bounded progress gauge.
type Model struct {
	width    int
	current  float64
	max      float64
	forecast float64 // negative means unset
	label    string
}

// New creates a meter with the given display width (including label area).
// Width is clamped to a minimum of 0.
func New(width int) Model {
	if width < 0 {
		width = 0
	}
	return Model{
		width:    width,
		max:      100,
		forecast: -1,
	}
}

// SetValue sets the current value and maximum.
func (m *Model) SetValue(current, max float64) {
	m.current = current
	m.max = max
}

// SetForecast sets the predicted completion point. Pass a negative value to
// clear the forecast.
func (m *Model) SetForecast(forecast float64) {
	m.forecast = forecast
}

// SetLabel sets the optional right-side label.
func (m *Model) SetLabel(label string) {
	m.label = label
}

// Percent returns the current progress as a percentage (0–100).
func (m Model) Percent() float64 {
	if m.max <= 0 {
		return 0
	}
	p := (m.current / m.max) * 100
	if p < 0 {
		return 0
	}
	if p > 100 {
		return 100
	}
	return p
}

// View renders the meter as a single-line string.
func (m Model) View() string {
	if m.width == 0 {
		return ""
	}

	sem := theme.Current().Semantic()
	pct := m.Percent()

	// Build the suffix: " 42% label"
	suffix := fmt.Sprintf(" %d%%", int(pct))
	if m.label != "" {
		suffix += " " + m.label
	}

	// Bar width is total width minus brackets minus suffix.
	barWidth := m.width - 2 - len(suffix) // 2 for [ and ]
	if barWidth < 1 {
		// Too narrow for a bar; just show the percentage.
		s := fmt.Sprintf("%d%%", int(pct))
		if len(s) > m.width {
			return s[:m.width]
		}
		return s
	}

	filledCount := int(float64(barWidth) * pct / 100)
	if filledCount > barWidth {
		filledCount = barWidth
	}

	// Forecast position (-1 means no forecast).
	forecastPos := -1
	if m.forecast >= 0 && m.max > 0 {
		fp := m.forecast / m.max
		if fp > 1 {
			fp = 1
		}
		if fp < 0 {
			fp = 0
		}
		forecastPos = int(fp * float64(barWidth))
		if forecastPos >= barWidth {
			forecastPos = barWidth - 1
		}
	}

	primaryStyle := lipgloss.NewStyle().Foreground(sem.Primary.Color())
	mutedStyle := lipgloss.NewStyle().Foreground(sem.Muted.Color())
	infoStyle := lipgloss.NewStyle().Foreground(sem.Info.Color())
	borderStyle := lipgloss.NewStyle().Foreground(sem.Border.Color())

	var bar strings.Builder
	bar.Grow(m.width * 4)

	bar.WriteString(borderStyle.Render("["))

	for i := 0; i < barWidth; i++ {
		if forecastPos >= 0 && i == forecastPos && i >= filledCount {
			bar.WriteString(infoStyle.Render("│"))
		} else if i < filledCount {
			bar.WriteString(primaryStyle.Render("█"))
		} else {
			bar.WriteString(mutedStyle.Render("░"))
		}
	}

	bar.WriteString(borderStyle.Render("]"))
	bar.WriteString(suffix)

	return bar.String()
}
