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

func TestScrollPercent(t *testing.T) {
	vp := viewport.New(40, 2)
	// No content — at bottom.
	if pct := vp.ScrollPercent(); pct != 1.0 {
		t.Fatalf("empty viewport scroll%% = %v, want 1.0", pct)
	}
	// Add 10 lines, auto-scrolled to bottom.
	for i := 0; i < 10; i++ {
		vp.AppendContent("line\n")
	}
	if pct := vp.ScrollPercent(); pct != 1.0 {
		t.Fatalf("at bottom scroll%% = %v, want 1.0", pct)
	}
	// Scroll to top.
	vp.ScrollUp(100)
	if pct := vp.ScrollPercent(); pct != 0.0 {
		t.Fatalf("at top scroll%% = %v, want 0.0", pct)
	}
}

func TestLinesBelow(t *testing.T) {
	vp := viewport.New(40, 3)
	vp.SetContent("a\nb\nc\nd\ne")
	// 5 lines, height 3, auto-scrolled to bottom → 0 below.
	if below := vp.LinesBelow(); below != 0 {
		t.Fatalf("at bottom LinesBelow = %d, want 0", below)
	}
	// Scroll up to top.
	vp.ScrollUp(100)
	if below := vp.LinesBelow(); below != 2 {
		t.Fatalf("at top LinesBelow = %d, want 2", below)
	}
}

func TestScrollTo(t *testing.T) {
	vp := viewport.New(40, 3)
	// 10 lines of content.
	for i := 0; i < 10; i++ {
		vp.AppendContent("line\n")
	}
	// Auto-scrolled to bottom.
	if !vp.AtBottom() {
		t.Fatal("expected at bottom after append")
	}
	// Scroll to line 2 (0-indexed).
	vp.ScrollTo(2)
	if vp.AtBottom() {
		t.Fatal("should not be at bottom after ScrollTo(2)")
	}
	// Lines below: 11 total (10 "line" + 1 trailing ""), offset 2, height 3 → 6 below.
	if below := vp.LinesBelow(); below != 6 {
		t.Fatalf("LinesBelow after ScrollTo(2) = %d, want 6", below)
	}
	// Clamping: ScrollTo beyond max offset should clamp.
	vp.ScrollTo(100)
	if !vp.AtBottom() {
		t.Fatal("ScrollTo(100) should clamp to bottom")
	}
	// Negative should clamp to 0.
	vp.ScrollTo(-5)
	if pct := vp.ScrollPercent(); pct != 0.0 {
		t.Fatalf("ScrollTo(-5) should be at top, got %v", pct)
	}
}

func TestScrollIndicator(t *testing.T) {
	vp := viewport.New(40, 2)
	// No content below → empty.
	if ind := vp.ScrollIndicator(40); ind != "" {
		t.Fatalf("at bottom indicator should be empty, got %q", ind)
	}
	// Add content and scroll up.
	for i := 0; i < 10; i++ {
		vp.AppendContent("line\n")
	}
	vp.ScrollUp(5)
	ind := vp.ScrollIndicator(40)
	if ind == "" {
		t.Fatal("indicator should be non-empty when content is below fold")
	}
	if !strings.Contains(ind, "more lines") {
		t.Fatalf("indicator should contain 'more lines', got %q", ind)
	}
	if !strings.Contains(ind, "↓") {
		t.Fatalf("indicator should contain ↓, got %q", ind)
	}
}
