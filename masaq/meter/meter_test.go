package meter_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/meter"
)

func TestNewZeroWidth(t *testing.T) {
	m := meter.New(0)
	if got := m.View(); got != "" {
		t.Errorf("View() on width=0 = %q, want empty", got)
	}
}

func TestNewNegativeWidth(t *testing.T) {
	m := meter.New(-1)
	if got := m.View(); got != "" {
		t.Errorf("View() on width=-1 = %q, want empty", got)
	}
}

func TestPercentZero(t *testing.T) {
	m := meter.New(30)
	m.SetValue(0, 100)
	if got := m.Percent(); got != 0 {
		t.Errorf("Percent() = %v, want 0", got)
	}
}

func TestPercentFull(t *testing.T) {
	m := meter.New(30)
	m.SetValue(100, 100)
	if got := m.Percent(); got != 100 {
		t.Errorf("Percent() = %v, want 100", got)
	}
}

func TestPercentHalf(t *testing.T) {
	m := meter.New(30)
	m.SetValue(50, 100)
	if got := m.Percent(); got != 50 {
		t.Errorf("Percent() = %v, want 50", got)
	}
}

func TestPercentOverflow(t *testing.T) {
	m := meter.New(30)
	m.SetValue(200, 100)
	if got := m.Percent(); got != 100 {
		t.Errorf("Percent() overflow = %v, want 100", got)
	}
}

func TestPercentZeroMax(t *testing.T) {
	m := meter.New(30)
	m.SetValue(50, 0)
	if got := m.Percent(); got != 0 {
		t.Errorf("Percent() zero max = %v, want 0", got)
	}
}

func TestViewContainsBrackets(t *testing.T) {
	m := meter.New(30)
	m.SetValue(50, 100)
	view := stripANSI(m.View())
	if !strings.HasPrefix(view, "[") {
		t.Errorf("View() should start with [: %q", view)
	}
	if !strings.Contains(view, "]") {
		t.Errorf("View() should contain ]: %q", view)
	}
}

func TestViewContainsPercent(t *testing.T) {
	m := meter.New(30)
	m.SetValue(42, 100)
	view := stripANSI(m.View())
	if !strings.Contains(view, "42%") {
		t.Errorf("View() should contain 42%%: %q", view)
	}
}

func TestViewWithLabel(t *testing.T) {
	m := meter.New(40)
	m.SetValue(50, 100)
	m.SetLabel("build")
	view := stripANSI(m.View())
	if !strings.Contains(view, "build") {
		t.Errorf("View() should contain label: %q", view)
	}
}

func TestViewNarrowWidth(t *testing.T) {
	m := meter.New(3)
	m.SetValue(50, 100)
	// Too narrow for brackets + bar; should still render without panic
	view := m.View()
	if view == "" {
		t.Error("View() on narrow width should not be empty")
	}
}

func TestViewWidthOne(t *testing.T) {
	m := meter.New(1)
	m.SetValue(50, 100)
	view := m.View()
	if view == "" {
		t.Error("View() on width=1 should not be empty")
	}
}

func TestForecastRender(t *testing.T) {
	m := meter.New(30)
	m.SetValue(30, 100)
	m.SetForecast(70)
	view := stripANSI(m.View())
	if !strings.Contains(view, "│") {
		t.Errorf("View() with forecast should contain │: %q", view)
	}
}

func TestForecastBeyondMax(t *testing.T) {
	m := meter.New(30)
	m.SetValue(50, 100)
	m.SetForecast(200) // > max, should clamp
	// Should not panic
	view := m.View()
	if view == "" {
		t.Error("View() with forecast > max should not be empty")
	}
}

func TestForecastNegativeClears(t *testing.T) {
	m := meter.New(30)
	m.SetValue(50, 100)
	m.SetForecast(70)
	m.SetForecast(-1) // clear
	view := stripANSI(m.View())
	if strings.Contains(view, "│") {
		t.Errorf("View() after clearing forecast should not contain │: %q", view)
	}
}

func TestForecastBehindCurrent(t *testing.T) {
	m := meter.New(30)
	m.SetValue(80, 100)
	m.SetForecast(30) // behind current
	// Forecast marker falls in filled area, so it won't show as │
	// but should not panic
	view := m.View()
	if view == "" {
		t.Error("View() with forecast < current should not be empty")
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
