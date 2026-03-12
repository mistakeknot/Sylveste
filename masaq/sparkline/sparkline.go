// Package sparkline provides a fixed-width time-series sparkline renderer
// using Unicode block characters (▁▂▃▄▅▆▇█). Values are stored in a ring
// buffer and auto-scaled to fit the available vertical resolution.
package sparkline

import (
	"math"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/Masaq/theme"
)

// blocks maps quantized levels 0–7 to Unicode block elements.
var blocks = [8]rune{'▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'}

// Model is a fixed-width sparkline backed by a ring buffer.
type Model struct {
	width int
	buf   []float64
	head  int
	count int

	// Manual bounds; if manualMin == manualMax auto-scaling is used.
	manualMin, manualMax float64

	// Thresholds for color zones (fraction of max, 0–1).
	// Values above WarnThreshold render in Warning, above CritThreshold in Error.
	WarnThreshold float64
	CritThreshold float64
}

// New creates a sparkline with the given display width.
// Width is clamped to a minimum of 0.
func New(width int) Model {
	if width < 0 {
		width = 0
	}
	return Model{
		width:         width,
		buf:           make([]float64, width),
		WarnThreshold: 0.75,
		CritThreshold: 0.90,
	}
}

// Push appends a sample to the ring buffer.
func (m *Model) Push(value float64) {
	if m.width == 0 {
		return
	}
	m.buf[m.head%m.width] = value
	m.head++
	if m.count < m.width {
		m.count++
	}
}

// SetBounds sets explicit min/max scaling. Pass equal values to revert to
// auto-scaling.
func (m *Model) SetBounds(min, max float64) {
	m.manualMin = min
	m.manualMax = max
}

// Last returns the most recently pushed value, or 0 if empty.
func (m Model) Last() float64 {
	if m.count == 0 {
		return 0
	}
	return m.buf[(m.head-1+m.width)%m.width]
}

// Avg returns the running average of buffered values.
func (m Model) Avg() float64 {
	if m.count == 0 {
		return 0
	}
	sum := 0.0
	for i := 0; i < m.count; i++ {
		sum += m.buf[(m.head-m.count+i+m.width)%m.width]
	}
	return sum / float64(m.count)
}

// View renders the sparkline as a single-line string.
func (m Model) View() string {
	if m.width == 0 {
		return ""
	}

	lo, hi := m.bounds()
	sem := theme.Current().Semantic()

	var sb strings.Builder
	sb.Grow(m.width * 4) // UTF-8 block chars are up to 3 bytes + possible ANSI

	for i := 0; i < m.width; i++ {
		idx := (m.head - m.width + i + m.width) % m.width
		filled := i < m.width-m.count+m.count // always true when i >= width-count

		if i >= m.width-m.count {
			// This slot has data.
			v := m.buf[idx]
			level := quantize(v, lo, hi)
			color := m.colorFor(v, lo, hi, sem)
			style := lipgloss.NewStyle().Foreground(color)
			sb.WriteString(style.Render(string(blocks[level])))
		} else {
			_ = filled
			sb.WriteRune(' ')
		}
	}
	return sb.String()
}

// bounds returns the effective min and max for scaling.
func (m Model) bounds() (float64, float64) {
	if m.manualMin != m.manualMax {
		return m.manualMin, m.manualMax
	}
	if m.count == 0 {
		return 0, 1
	}
	lo, hi := math.Inf(1), math.Inf(-1)
	for i := 0; i < m.count; i++ {
		v := m.buf[(m.head-m.count+i+m.width)%m.width]
		if v < lo {
			lo = v
		}
		if v > hi {
			hi = v
		}
	}
	if lo == hi {
		// All values identical — center at half-height.
		return lo - 1, hi + 1
	}
	return lo, hi
}

// quantize maps a value within [lo, hi] to a block level 0–7.
func quantize(v, lo, hi float64) int {
	if hi <= lo {
		return 3 // mid-level fallback
	}
	t := (v - lo) / (hi - lo)
	if t < 0 {
		t = 0
	}
	if t > 1 {
		t = 1
	}
	level := int(t * 7)
	if level > 7 {
		level = 7
	}
	return level
}

// colorFor picks a semantic color based on the value's relative position.
func (m Model) colorFor(v, lo, hi float64, sem theme.SemanticColors) lipgloss.Color {
	if hi <= lo {
		return sem.Success.Color()
	}
	t := (v - lo) / (hi - lo)
	if t >= m.CritThreshold {
		return sem.Error.Color()
	}
	if t >= m.WarnThreshold {
		return sem.Warning.Color()
	}
	return sem.Success.Color()
}
