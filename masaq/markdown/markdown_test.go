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
