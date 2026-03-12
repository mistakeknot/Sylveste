package tabbar_test

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mistakeknot/Masaq/tabbar"
)

func makeTabs() []tabbar.Tab {
	return []tabbar.Tab{
		{Label: "Convo", Key: "c"},
		{Label: "Edits", Key: "e"},
		{Label: "Files", Key: "f"},
	}
}

func TestNewEmpty(t *testing.T) {
	m := tabbar.New(nil)
	if got := m.View(); got != "" {
		t.Errorf("View() with no tabs = %q, want empty", got)
	}
}

func TestActiveDefault(t *testing.T) {
	m := tabbar.New(makeTabs())
	if got := m.Active(); got != 0 {
		t.Errorf("Active() default = %d, want 0", got)
	}
}

func TestSetActive(t *testing.T) {
	m := tabbar.New(makeTabs())
	m.SetActive(2)
	if got := m.Active(); got != 2 {
		t.Errorf("Active() after SetActive(2) = %d, want 2", got)
	}
}

func TestSetActiveClampHigh(t *testing.T) {
	m := tabbar.New(makeTabs())
	m.SetActive(99)
	if got := m.Active(); got != 2 {
		t.Errorf("Active() after SetActive(99) = %d, want 2", got)
	}
}

func TestSetActiveClampLow(t *testing.T) {
	m := tabbar.New(makeTabs())
	m.SetActive(-1)
	if got := m.Active(); got != 0 {
		t.Errorf("Active() after SetActive(-1) = %d, want 0", got)
	}
}

func TestSetActiveEmptyTabs(t *testing.T) {
	m := tabbar.New(nil)
	m.SetActive(0) // should not panic
}

func TestViewContainsBrackets(t *testing.T) {
	m := tabbar.New(makeTabs())
	view := stripANSI(m.View())
	if !strings.Contains(view, "[") || !strings.Contains(view, "]") {
		t.Errorf("View() should contain brackets: %q", view)
	}
}

func TestViewContainsLabels(t *testing.T) {
	m := tabbar.New(makeTabs())
	view := stripANSI(m.View())
	for _, tab := range makeTabs() {
		if !strings.Contains(view, tab.Label) {
			t.Errorf("View() should contain label %q: %q", tab.Label, view)
		}
	}
}

func TestViewContainsNumbers(t *testing.T) {
	m := tabbar.New(makeTabs())
	view := stripANSI(m.View())
	if !strings.Contains(view, "1 Convo") {
		t.Errorf("View() should prefix with number: %q", view)
	}
}

func TestNumberKeySwitch(t *testing.T) {
	m := tabbar.New(makeTabs())
	var cmd tea.Cmd
	m, cmd = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'2'}})
	if m.Active() != 1 {
		t.Errorf("Active() after pressing 2 = %d, want 1", m.Active())
	}
	if cmd == nil {
		t.Error("Should emit command on tab change")
	}
	// Execute the command to get the message.
	msg := cmd()
	if changed, ok := msg.(tabbar.ChangedMsg); !ok || changed.Index != 1 {
		t.Errorf("Expected ChangedMsg{Index: 1}, got %v", msg)
	}
}

func TestNumberKeyOutOfRange(t *testing.T) {
	m := tabbar.New(makeTabs())
	m, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'9'}})
	if m.Active() != 0 {
		t.Errorf("Active() after pressing 9 = %d, want 0 (unchanged)", m.Active())
	}
	if cmd != nil {
		t.Error("Should not emit command for out-of-range key")
	}
}

func TestNumberKeySameTab(t *testing.T) {
	m := tabbar.New(makeTabs())
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'1'}})
	if cmd != nil {
		t.Error("Should not emit command when pressing current tab's number")
	}
}

func TestCustomKeySwitch(t *testing.T) {
	m := tabbar.New(makeTabs())
	m, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'f'}})
	if m.Active() != 2 {
		t.Errorf("Active() after pressing 'f' = %d, want 2", m.Active())
	}
	if cmd == nil {
		t.Error("Should emit command on custom key switch")
	}
}

func TestRightArrow(t *testing.T) {
	m := tabbar.New(makeTabs())
	m, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRight})
	if m.Active() != 1 {
		t.Errorf("Active() after right arrow = %d, want 1", m.Active())
	}
	if cmd == nil {
		t.Error("Should emit command on arrow key")
	}
}

func TestLeftArrowWraps(t *testing.T) {
	m := tabbar.New(makeTabs())
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyLeft})
	if m.Active() != 2 {
		t.Errorf("Active() after left arrow from 0 = %d, want 2 (wrap)", m.Active())
	}
}

func TestRightArrowWraps(t *testing.T) {
	m := tabbar.New(makeTabs())
	m.SetActive(2)
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRight})
	if m.Active() != 0 {
		t.Errorf("Active() after right arrow from last = %d, want 0 (wrap)", m.Active())
	}
}

func TestInitReturnsNil(t *testing.T) {
	m := tabbar.New(makeTabs())
	if cmd := m.Init(); cmd != nil {
		t.Error("Init() should return nil")
	}
}

func TestWindowSizeMsg(t *testing.T) {
	m := tabbar.New(makeTabs())
	m, _ = m.Update(tea.WindowSizeMsg{Width: 20, Height: 24})
	// Should not panic; width is stored internally for truncation.
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
