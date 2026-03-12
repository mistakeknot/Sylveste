package statusbar_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/statusbar"
)

func TestNewZeroWidth(t *testing.T) {
	m := statusbar.New(0)
	if got := m.View(); got != "" {
		t.Errorf("View() on width=0 = %q, want empty", got)
	}
}

func TestNewNegativeWidth(t *testing.T) {
	m := statusbar.New(-1)
	if got := m.View(); got != "" {
		t.Errorf("View() on width=-1 = %q, want empty", got)
	}
}

func TestEmptySlots(t *testing.T) {
	m := statusbar.New(40)
	if got := m.View(); got != "" {
		t.Errorf("View() with no slots = %q, want empty", got)
	}
}

func TestSingleSlot(t *testing.T) {
	m := statusbar.New(40)
	m.SetSlots([]statusbar.Slot{
		{Label: "status", Value: "running"},
	})
	view := stripANSI(m.View())
	if !strings.Contains(view, "status:") {
		t.Errorf("View() should contain label: %q", view)
	}
	if !strings.Contains(view, "running") {
		t.Errorf("View() should contain value: %q", view)
	}
}

func TestMultipleSlots(t *testing.T) {
	m := statusbar.New(60)
	m.SetSlots([]statusbar.Slot{
		{Label: "status", Value: "running"},
		{Label: "time", Value: "2m"},
	})
	view := stripANSI(m.View())
	if !strings.Contains(view, "│") {
		t.Errorf("View() should contain separator: %q", view)
	}
	if !strings.Contains(view, "time:") {
		t.Errorf("View() should contain second slot: %q", view)
	}
}

func TestSetSlotUpdate(t *testing.T) {
	m := statusbar.New(40)
	m.SetSlots([]statusbar.Slot{
		{Label: "status", Value: "running"},
	})
	m.SetSlot("status", "done")
	view := stripANSI(m.View())
	if !strings.Contains(view, "done") {
		t.Errorf("SetSlot should update value: %q", view)
	}
	if strings.Contains(view, "running") {
		t.Errorf("SetSlot should have replaced 'running': %q", view)
	}
}

func TestSetSlotAppend(t *testing.T) {
	m := statusbar.New(60)
	m.SetSlots([]statusbar.Slot{
		{Label: "a", Value: "1"},
	})
	m.SetSlot("b", "2")
	view := stripANSI(m.View())
	if !strings.Contains(view, "b:") {
		t.Errorf("SetSlot should append new slot: %q", view)
	}
}

func TestTruncation(t *testing.T) {
	m := statusbar.New(15)
	m.SetSlots([]statusbar.Slot{
		{Label: "a", Value: "short"},
		{Label: "b", Value: "this-is-long"},
		{Label: "c", Value: "overflow"},
	})
	view := stripANSI(m.View())
	// Should drop rightmost slots to fit
	if strings.Contains(view, "overflow") {
		t.Errorf("View() should have truncated 'overflow': %q", view)
	}
}

func TestHeightAlwaysOne(t *testing.T) {
	m := statusbar.New(40)
	if got := m.Height(); got != 1 {
		t.Errorf("Height() = %d, want 1", got)
	}
}

func TestSlotWithoutLabel(t *testing.T) {
	m := statusbar.New(40)
	m.SetSlots([]statusbar.Slot{
		{Value: "just-value"},
	})
	view := stripANSI(m.View())
	if !strings.Contains(view, "just-value") {
		t.Errorf("View() should contain value without label: %q", view)
	}
}

func TestWidthOne(t *testing.T) {
	m := statusbar.New(1)
	m.SetSlots([]statusbar.Slot{
		{Label: "x", Value: "y"},
	})
	// Should not panic; may truncate to empty
	_ = m.View()
}

// stripANSI removes ANSI escape sequences for test assertions.
func stripANSI(s string) string {
	var out strings.Builder
	inEsc := false
	for _, r := range s {
		if r == '\033' {
			inEsc = true
			continue
		}
		if inEsc {
			if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') {
				inEsc = false
			}
			continue
		}
		out.WriteRune(r)
	}
	return out.String()
}
