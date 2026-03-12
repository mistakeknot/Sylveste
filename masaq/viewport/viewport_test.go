package viewport_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/viewport"
)

func TestNewViewport(t *testing.T) {
	vp := viewport.New(80, 24)
	if vp.Width() != 80 || vp.Height() != 24 {
		t.Fatalf("got %dx%d, want 80x24", vp.Width(), vp.Height())
	}
}

func TestAppendAndView(t *testing.T) {
	vp := viewport.New(40, 5)
	vp.AppendContent("line 1\nline 2\nline 3\n")
	view := vp.View()
	if !strings.Contains(view, "line 1") {
		t.Fatal("view should contain appended content")
	}
}

func TestAutoScrollOnAppend(t *testing.T) {
	vp := viewport.New(40, 2)
	for i := 0; i < 10; i++ {
		vp.AppendContent("line\n")
	}
	view := vp.View()
	lines := strings.Split(strings.TrimRight(view, "\n"), "\n")
	if len(lines) > 2 {
		t.Fatalf("viewport should clip to height, got %d lines", len(lines))
	}
}

func TestSetContent(t *testing.T) {
	vp := viewport.New(40, 5)
	vp.AppendContent("old content\n")
	vp.SetContent("new content\n")
	view := vp.View()
	if strings.Contains(view, "old") {
		t.Fatal("SetContent should replace all content")
	}
	if !strings.Contains(view, "new") {
		t.Fatal("SetContent should set new content")
	}
}

func TestManualScroll(t *testing.T) {
	vp := viewport.New(40, 2)
	for i := 0; i < 10; i++ {
		vp.AppendContent("line\n")
	}
	vp.ScrollUp(5)
	if vp.AtBottom() {
		t.Fatal("should not be at bottom after scrolling up")
	}
	vp.ScrollToBottom()
	if !vp.AtBottom() {
		t.Fatal("should be at bottom after ScrollToBottom")
	}
}

func TestSetSize(t *testing.T) {
	vp := viewport.New(80, 24)
	vp.SetSize(40, 12)
	if vp.Width() != 40 || vp.Height() != 12 {
		t.Fatalf("after resize got %dx%d, want 40x12", vp.Width(), vp.Height())
	}
}
