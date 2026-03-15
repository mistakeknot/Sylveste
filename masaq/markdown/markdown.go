package markdown

import (
	"strings"

	"github.com/charmbracelet/glamour"
)

// Renderer handles streaming and one-shot markdown rendering via Glamour.
type Renderer struct {
	width    int
	renderer *glamour.TermRenderer
	buf      strings.Builder

	// Streaming delta state: tracks how much rendered output has already
	// been emitted so we can return only the new portion.
	lastRendered string
}

// New creates a Renderer with the given terminal width.
func New(width int) *Renderer {
	r, _ := glamour.NewTermRenderer(
		glamour.WithAutoStyle(),
		glamour.WithWordWrap(width),
	)
	return &Renderer{
		width:    width,
		renderer: r,
	}
}

// Render does a one-shot render of complete markdown.
func (r *Renderer) Render(md string) string {
	if md == "" {
		return ""
	}
	out, err := r.renderer.Render(md)
	if err != nil {
		return md // fallback to raw
	}
	return strings.TrimRight(out, "\n")
}

// Append adds streaming text to the buffer.
func (r *Renderer) Append(text string) {
	r.buf.WriteString(text)
}

// View renders the accumulated buffer.
func (r *Renderer) View() string {
	content := r.buf.String()
	if content == "" {
		return ""
	}
	return r.Render(content)
}

// Reset clears the streaming buffer.
func (r *Renderer) Reset() {
	r.buf.Reset()
}

// StreamDelta renders the full accumulated buffer and returns only the portion
// that is new since the last call to StreamDelta. This allows callers to append
// streaming text chunks and get correctly rendered incremental output — Glamour
// always sees the full context so block-level structures (code fences, styled
// blocks) render correctly even when they arrive across multiple chunks.
//
// When Glamour re-renders earlier content (e.g. closing a code fence changes
// the styling of the opening line), the prefix match fails. In this case we
// emit only the tail of the new rendering that extends beyond the old length.
// This avoids full viewport replacement while keeping output roughly correct.
func (r *Renderer) StreamDelta() string {
	content := r.buf.String()
	if content == "" {
		return ""
	}

	full := r.Render(content)
	if full == r.lastRendered {
		return "" // no change
	}

	var delta string
	if strings.HasPrefix(full, r.lastRendered) {
		// Common case: rendered output grew at the end.
		delta = full[len(r.lastRendered):]
	} else if len(full) > len(r.lastRendered) {
		// Glamour re-rendered earlier content. Emit the tail that extends
		// beyond the previous length — not perfect but avoids duplication.
		delta = full[len(r.lastRendered):]
	} else {
		// Output shrank or fully changed — emit nothing and wait for more.
		// The next append will likely extend past the old length.
		r.lastRendered = full
		return ""
	}

	r.lastRendered = full
	return delta
}

// ResetStream clears both the buffer and the streaming delta state.
func (r *Renderer) ResetStream() {
	r.buf.Reset()
	r.lastRendered = ""
}

// Content returns the raw accumulated text.
func (r *Renderer) Content() string {
	return r.buf.String()
}
