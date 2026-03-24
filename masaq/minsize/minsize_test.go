package minsize_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/minsize"
)

func TestShouldBlock_TooNarrow(t *testing.T) {
	m := minsize.New(80, 24)
	m.SetSize(60, 24)
	if !m.ShouldBlock() {
		t.Fatal("should block when width < min")
	}
}

func TestShouldBlock_TooShort(t *testing.T) {
	m := minsize.New(80, 24)
	m.SetSize(80, 10)
	if !m.ShouldBlock() {
		t.Fatal("should block when height < min")
	}
}

func TestShouldBlock_OK(t *testing.T) {
	m := minsize.New(80, 24)
	m.SetSize(120, 40)
	if m.ShouldBlock() {
		t.Fatal("should not block when terminal meets requirements")
	}
}

func TestShouldBlock_Exact(t *testing.T) {
	m := minsize.New(80, 24)
	m.SetSize(80, 24)
	if m.ShouldBlock() {
		t.Fatal("should not block when terminal exactly matches minimum")
	}
}

func TestShouldBlock_ZeroSize(t *testing.T) {
	m := minsize.New(80, 24)
	// Width and Height default to 0.
	if !m.ShouldBlock() {
		t.Fatal("should block when terminal size is zero")
	}
}

func TestView_NotBlocking(t *testing.T) {
	m := minsize.New(80, 24)
	m.SetSize(100, 30)
	if v := m.View(); v != "" {
		t.Fatalf("View should be empty when not blocking, got %q", v)
	}
}

func TestView_ShowsWarning(t *testing.T) {
	m := minsize.New(80, 24)
	m.SetSize(40, 10)
	v := m.View()
	if v == "" {
		t.Fatal("View should show warning when blocking")
	}
	if !strings.Contains(v, "Terminal too small") {
		t.Fatalf("should contain 'Terminal too small', got %q", v)
	}
	if !strings.Contains(v, "80") || !strings.Contains(v, "24") {
		t.Fatal("should show required dimensions")
	}
	if !strings.Contains(v, "40") || !strings.Contains(v, "10") {
		t.Fatal("should show current dimensions")
	}
}
