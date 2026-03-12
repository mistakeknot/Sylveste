package sparkline_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/sparkline"
)

func TestNewZeroWidth(t *testing.T) {
	m := sparkline.New(0)
	if got := m.View(); got != "" {
		t.Errorf("View() on width=0 = %q, want empty", got)
	}
}

func TestNewNegativeWidth(t *testing.T) {
	m := sparkline.New(-1)
	if got := m.View(); got != "" {
		t.Errorf("View() on width=-1 = %q, want empty", got)
	}
}

func TestPushAndLast(t *testing.T) {
	m := sparkline.New(5)
	m.Push(1.0)
	m.Push(2.0)
	m.Push(3.0)
	if got := m.Last(); got != 3.0 {
		t.Errorf("Last() = %v, want 3.0", got)
	}
}

func TestLastEmpty(t *testing.T) {
	m := sparkline.New(5)
	if got := m.Last(); got != 0 {
		t.Errorf("Last() on empty = %v, want 0", got)
	}
}

func TestAvg(t *testing.T) {
	m := sparkline.New(5)
	m.Push(2.0)
	m.Push(4.0)
	m.Push(6.0)
	if got := m.Avg(); got != 4.0 {
		t.Errorf("Avg() = %v, want 4.0", got)
	}
}

func TestAvgEmpty(t *testing.T) {
	m := sparkline.New(5)
	if got := m.Avg(); got != 0 {
		t.Errorf("Avg() on empty = %v, want 0", got)
	}
}

func TestRingBufferOverflow(t *testing.T) {
	m := sparkline.New(3)
	m.Push(1.0)
	m.Push(2.0)
	m.Push(3.0)
	m.Push(4.0) // overwrites 1.0
	if got := m.Avg(); got != 3.0 {
		t.Errorf("Avg() after overflow = %v, want 3.0 (2+3+4)/3", got)
	}
}

func TestViewRendersBlocks(t *testing.T) {
	m := sparkline.New(4)
	m.Push(0.0)
	m.Push(0.33)
	m.Push(0.66)
	m.Push(1.0)

	view := m.View()
	// Should contain block characters, not spaces
	if strings.TrimSpace(stripANSI(view)) == "" {
		t.Error("View() should contain block characters")
	}
}

func TestViewEmptySlotsAreSpaces(t *testing.T) {
	m := sparkline.New(5)
	m.Push(1.0)
	// 4 empty slots should be spaces, 1 filled
	view := stripANSI(m.View())
	if len([]rune(view)) != 5 {
		t.Errorf("View() rune count = %d, want 5", len([]rune(view)))
	}
	// First 4 should be spaces
	runes := []rune(view)
	for i := 0; i < 4; i++ {
		if runes[i] != ' ' {
			t.Errorf("rune[%d] = %q, want space", i, runes[i])
		}
	}
}

func TestViewWidthOne(t *testing.T) {
	m := sparkline.New(1)
	m.Push(0.5)
	view := stripANSI(m.View())
	if len([]rune(view)) != 1 {
		t.Errorf("View() width=1 rune count = %d, want 1", len([]rune(view)))
	}
}

func TestSetBoundsManual(t *testing.T) {
	m := sparkline.New(3)
	m.SetBounds(0, 100)
	m.Push(0)
	m.Push(50)
	m.Push(100)
	view := stripANSI(m.View())
	runes := []rune(view)
	if len(runes) != 3 {
		t.Fatalf("rune count = %d, want 3", len(runes))
	}
	// First block should be lowest, last should be highest
	if runes[0] >= runes[2] {
		t.Errorf("expected ascending blocks: %q", view)
	}
}

func TestSetBoundsRevert(t *testing.T) {
	m := sparkline.New(3)
	m.SetBounds(0, 100)
	m.SetBounds(0, 0) // revert to auto
	m.Push(5)
	m.Push(10)
	m.Push(15)
	// Should not panic and should render
	view := m.View()
	if view == "" {
		t.Error("View() after reverting bounds should not be empty")
	}
}

func TestAllSameValues(t *testing.T) {
	m := sparkline.New(3)
	m.Push(5.0)
	m.Push(5.0)
	m.Push(5.0)
	// Should render mid-height blocks, not panic
	view := stripANSI(m.View())
	if len([]rune(view)) != 3 {
		t.Errorf("rune count = %d, want 3", len([]rune(view)))
	}
}

func TestPushOnZeroWidth(t *testing.T) {
	m := sparkline.New(0)
	m.Push(1.0) // should not panic
	if got := m.Last(); got != 0 {
		t.Errorf("Last() on width=0 after push = %v, want 0", got)
	}
}

// stripANSI removes ANSI escape sequences for test assertions on content.
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
