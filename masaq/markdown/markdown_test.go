package markdown_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/markdown"
)

func TestRenderComplete(t *testing.T) {
	m := markdown.New(80)
	result := m.Render("# Hello\n\nThis is **bold**.")
	if !strings.Contains(result, "Hello") {
		t.Fatal("rendered markdown should contain heading text")
	}
}

func TestStreamingAppend(t *testing.T) {
	m := markdown.New(80)
	m.Append("# He")
	m.Append("llo\n\nBody text.")
	result := m.View()
	if !strings.Contains(result, "Hello") {
		t.Fatal("streaming view should render accumulated content")
	}
}

func TestEmptyReturnsEmpty(t *testing.T) {
	m := markdown.New(80)
	result := m.Render("")
	if result != "" {
		t.Fatalf("empty input should return empty, got %q", result)
	}
}

func TestReset(t *testing.T) {
	m := markdown.New(80)
	m.Append("some text")
	m.Reset()
	if m.Content() != "" {
		t.Fatal("Reset should clear the buffer")
	}
}

func TestContent(t *testing.T) {
	m := markdown.New(80)
	m.Append("chunk1")
	m.Append("chunk2")
	if m.Content() != "chunk1chunk2" {
		t.Fatalf("Content() = %q, want chunk1chunk2", m.Content())
	}
}

func TestStreamDelta_IncrementalOutput(t *testing.T) {
	m := markdown.New(80)
	// Use separate lines so Glamour treats them as distinct blocks
	// that won't reflow when more text arrives.
	m.Append("First line.\n\n")
	d1 := m.StreamDelta()
	if d1 == "" {
		t.Fatal("first delta should be non-empty")
	}
	m.Append("Second line.\n\n")
	d2 := m.StreamDelta()
	if d2 == "" {
		t.Fatal("second delta should be non-empty")
	}
	// When lines are on separate paragraphs, Glamour renders them independently.
	// d2 should either be a clean delta or a RERENDER (both are valid).
	// The key invariant is that it's non-empty.
}

func TestStreamDelta_NoDuplicateOnSameContent(t *testing.T) {
	m := markdown.New(80)
	m.Append("test")
	_ = m.StreamDelta()
	// Calling again without new content should return empty
	d := m.StreamDelta()
	if d != "" {
		t.Fatalf("delta without new content should be empty, got %q", d)
	}
}

func TestStreamDelta_CodeFenceClose(t *testing.T) {
	m := markdown.New(80)
	// Simulate a code fence arriving in chunks
	m.Append("Before\n\n```\ncode line 1\n")
	_ = m.StreamDelta()
	m.Append("code line 2\n```\n\nAfter\n\n")
	d := m.StreamDelta()
	// Closing a code fence may cause Glamour to re-render the block.
	// StreamDelta handles this by emitting the tail of the new output.
	// The delta should be non-empty (contains at least "After").
	if d == "" {
		t.Fatal("closing a code fence should produce a delta")
	}
}

func TestResetStream_ClearsState(t *testing.T) {
	m := markdown.New(80)
	m.Append("text")
	_ = m.StreamDelta()
	m.ResetStream()
	if m.Content() != "" {
		t.Fatal("ResetStream should clear buffer")
	}
	// After reset, new content should produce fresh delta
	m.Append("new text")
	d := m.StreamDelta()
	if d == "" {
		t.Fatal("delta after reset should be non-empty")
	}
}
