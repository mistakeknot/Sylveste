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

// Content returns the raw accumulated text.
func (r *Renderer) Content() string {
	return r.buf.String()
}
