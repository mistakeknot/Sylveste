package breadcrumb_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/breadcrumb"
)

func TestNewZeroWidth(t *testing.T) {
	m := breadcrumb.New(0)
	if got := m.View(); got != "" {
		t.Errorf("View() on width=0 = %q, want empty", got)
	}
}

func TestNewNegativeWidth(t *testing.T) {
	m := breadcrumb.New(-1)
	if got := m.View(); got != "" {
		t.Errorf("View() on width=-1 = %q, want empty", got)
	}
}

func TestEmptySteps(t *testing.T) {
	m := breadcrumb.New(40)
	if got := m.View(); got != "" {
		t.Errorf("View() with no steps = %q, want empty", got)
	}
}

func TestSingleDoneStep(t *testing.T) {
	m := breadcrumb.New(40)
	m.SetSteps([]breadcrumb.Step{
		{Label: "init", Status: breadcrumb.Done},
	})
	view := stripANSI(m.View())
	if !strings.Contains(view, "✓") {
		t.Errorf("Done step should have ✓: %q", view)
	}
	if !strings.Contains(view, "init") {
		t.Errorf("Should contain label: %q", view)
	}
}

func TestSingleActiveStep(t *testing.T) {
	m := breadcrumb.New(40)
	m.SetSteps([]breadcrumb.Step{
		{Label: "build", Status: breadcrumb.Active},
	})
	view := stripANSI(m.View())
	if !strings.Contains(view, "●") {
		t.Errorf("Active step should have ●: %q", view)
	}
}

func TestSinglePendingStep(t *testing.T) {
	m := breadcrumb.New(40)
	m.SetSteps([]breadcrumb.Step{
		{Label: "ship", Status: breadcrumb.Pending},
	})
	view := stripANSI(m.View())
	if !strings.Contains(view, "○") {
		t.Errorf("Pending step should have ○: %q", view)
	}
}

func TestMultipleSteps(t *testing.T) {
	m := breadcrumb.New(80)
	m.SetSteps([]breadcrumb.Step{
		{Label: "init", Status: breadcrumb.Done},
		{Label: "build", Status: breadcrumb.Active},
		{Label: "ship", Status: breadcrumb.Pending},
	})
	view := stripANSI(m.View())
	if !strings.Contains(view, "→") {
		t.Errorf("Steps should be separated by →: %q", view)
	}
}

func TestPushTransitionsActive(t *testing.T) {
	m := breadcrumb.New(80)
	m.Push("init")
	m.Push("build")
	view := stripANSI(m.View())
	// "init" should now be Done (✓), "build" should be Active (●)
	if !strings.Contains(view, "✓") {
		t.Errorf("Previous step should be ✓ after Push: %q", view)
	}
	if !strings.Contains(view, "●") {
		t.Errorf("New step should be ● after Push: %q", view)
	}
}

func TestComplete(t *testing.T) {
	m := breadcrumb.New(80)
	m.Push("init")
	m.Complete()
	view := stripANSI(m.View())
	if strings.Contains(view, "●") {
		t.Errorf("After Complete, no step should be Active: %q", view)
	}
	if !strings.Contains(view, "✓") {
		t.Errorf("After Complete, step should be Done: %q", view)
	}
}

func TestLeftTruncation(t *testing.T) {
	m := breadcrumb.New(25)
	m.SetSteps([]breadcrumb.Step{
		{Label: "first-long-step", Status: breadcrumb.Done},
		{Label: "second-long-step", Status: breadcrumb.Done},
		{Label: "current", Status: breadcrumb.Active},
	})
	view := stripANSI(m.View())
	// Should have ellipsis for truncated left steps
	if !strings.Contains(view, "…") {
		t.Errorf("Truncated view should contain …: %q", view)
	}
	// Most recent step should always be visible
	if !strings.Contains(view, "current") {
		t.Errorf("Most recent step should be visible: %q", view)
	}
}

func TestWidthOne(t *testing.T) {
	m := breadcrumb.New(1)
	m.Push("test")
	// Should not panic
	_ = m.View()
}

func TestSetStepsCopiesSlice(t *testing.T) {
	m := breadcrumb.New(80)
	steps := []breadcrumb.Step{
		{Label: "a", Status: breadcrumb.Active},
	}
	m.SetSteps(steps)
	steps[0].Label = "mutated"
	view := stripANSI(m.View())
	if strings.Contains(view, "mutated") {
		t.Error("SetSteps should copy the slice, not reference it")
	}
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
