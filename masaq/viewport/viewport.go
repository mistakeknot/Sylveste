// Package viewport provides a flicker-free scrollable viewport as a Bubble Tea
// sub-model. It handles ANSI-aware line truncation (never slicing styled strings
// by rune) and supports auto-scroll on content append.
package viewport

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

// Model is a scrollable viewport that can be embedded in a Bubble Tea program.
// Mutating methods use pointer receivers so the caller can modify the model
// directly before rendering. Update returns a Model by value per Bubble Tea
// convention.
type Model struct {
	lines      []string
	width      int
	height     int
	offset     int  // first visible line index
	autoScroll bool // scroll to bottom on new content
}

// New creates a viewport with the given dimensions. AutoScroll is enabled by
// default, so new content appended via AppendContent will keep the view pinned
// to the bottom.
func New(width, height int) Model {
	return Model{
		width:      width,
		height:     height,
		autoScroll: true,
	}
}

// AppendContent appends text to the viewport. The text is split by newlines and
// each resulting segment becomes a line. If the last existing line was produced
// by a previous write that did not end with a newline, the first segment of the
// new text is merged onto that line (partial-line continuation). When autoScroll
// is enabled, the viewport scrolls to the bottom after appending.
func (m *Model) AppendContent(text string) {
	if text == "" {
		return
	}

	parts := strings.Split(text, "\n")

	// Merge partial line: if we have existing lines and the new text starts
	// without an explicit newline prefix, join onto the last line.
	if len(m.lines) > 0 && len(parts) > 0 {
		m.lines[len(m.lines)-1] += parts[0]
		parts = parts[1:]
	}

	m.lines = append(m.lines, parts...)

	if m.autoScroll {
		m.scrollToEnd()
	}
}

// SetContent replaces all viewport content with text.
func (m *Model) SetContent(text string) {
	if text == "" {
		m.lines = nil
	} else {
		m.lines = strings.Split(text, "\n")
	}

	if m.autoScroll {
		m.scrollToEnd()
	}
}

// SetSize updates the viewport dimensions.
func (m *Model) SetSize(w, h int) {
	m.width = w
	m.height = h
	m.clampOffset()
}

// Width returns the viewport width in columns.
func (m Model) Width() int { return m.width }

// Height returns the viewport height in rows.
func (m Model) Height() int { return m.height }

// TotalLines returns the number of content lines.
func (m Model) TotalLines() int { return len(m.lines) }

// AtBottom returns true when the viewport is scrolled to the very bottom (or
// content fits entirely on screen).
func (m Model) AtBottom() bool {
	return m.offset >= m.maxOffset()
}

// ScrollUp moves the viewport up by n lines and disables autoScroll.
func (m *Model) ScrollUp(n int) {
	m.offset -= n
	if m.offset < 0 {
		m.offset = 0
	}
	m.autoScroll = false
}

// ScrollDown moves the viewport down by n lines. If the resulting position is
// at the bottom, autoScroll is re-enabled.
func (m *Model) ScrollDown(n int) {
	m.offset += n
	max := m.maxOffset()
	if m.offset > max {
		m.offset = max
	}
	if m.AtBottom() {
		m.autoScroll = true
	}
}

// ScrollToBottom scrolls to the end of the content and re-enables autoScroll.
func (m *Model) ScrollToBottom() {
	m.scrollToEnd()
	m.autoScroll = true
}

// Init satisfies tea.Model. Returns nil.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles key messages for viewport scrolling. It returns a new Model by
// value per Bubble Tea convention.
func (m Model) Update(msg tea.Msg) (Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.Type {
		case tea.KeyUp:
			m.ScrollUp(1)
		case tea.KeyDown:
			m.ScrollDown(1)
		case tea.KeyPgUp:
			half := m.height / 2
			if half < 1 {
				half = 1
			}
			m.ScrollUp(half)
		case tea.KeyPgDown:
			half := m.height / 2
			if half < 1 {
				half = 1
			}
			m.ScrollDown(half)
		case tea.KeyHome:
			m.offset = 0
			m.autoScroll = false
		case tea.KeyEnd:
			m.ScrollToBottom()
		}
	}
	return m, nil
}

// View renders the visible portion of the viewport content. Lines are truncated
// to the viewport width using ANSI-aware truncation (preserving escape codes).
func (m Model) View() string {
	if m.height <= 0 || len(m.lines) == 0 {
		return ""
	}

	end := m.offset + m.height
	if end > len(m.lines) {
		end = len(m.lines)
	}

	start := m.offset
	if start < 0 {
		start = 0
	}
	if start > end {
		start = end
	}

	visible := m.lines[start:end]
	if m.width <= 0 {
		return strings.Join(visible, "\n")
	}

	var b strings.Builder
	for i, line := range visible {
		if i > 0 {
			b.WriteByte('\n')
		}
		b.WriteString(ansi.Truncate(line, m.width, ""))
	}
	return b.String()
}

// maxOffset returns the highest valid offset (first line of the last screenful).
func (m Model) maxOffset() int {
	n := len(m.lines) - m.height
	if n < 0 {
		return 0
	}
	return n
}

// scrollToEnd moves the offset so the last line is visible.
func (m *Model) scrollToEnd() {
	m.offset = m.maxOffset()
}

// clampOffset keeps offset within [0, maxOffset].
func (m *Model) clampOffset() {
	max := m.maxOffset()
	if m.offset > max {
		m.offset = max
	}
	if m.offset < 0 {
		m.offset = 0
	}
}
