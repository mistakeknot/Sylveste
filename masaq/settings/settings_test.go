package settings

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func testEntries() []Entry {
	return []Entry{
		{Key: "verbose", Description: "Verbose mode", Type: TypeBool, Value: "off"},
		{Key: "auto-scroll", Description: "Follow output", Type: TypeBool, Value: "on"},
		{Key: "theme", Description: "Color theme", Type: TypeEnum, Value: "Tokyo Night", Options: []string{"Tokyo Night", "Catppuccin", "Gruvbox"}},
		{Key: "color-mode", Description: "Color mode", Type: TypeEnum, Value: "dark", Options: []string{"dark", "light"}},
	}
}

func TestNew(t *testing.T) {
	m := New("Settings", testEntries())
	if m.Cursor() != 0 {
		t.Errorf("initial cursor = %d, want 0", m.Cursor())
	}
	if len(m.Entries()) != 4 {
		t.Errorf("entries = %d, want 4", len(m.Entries()))
	}
}

func TestNavigateDown(t *testing.T) {
	m := New("Settings", testEntries())

	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	if m.Cursor() != 1 {
		t.Errorf("after down: cursor = %d, want 1", m.Cursor())
	}

	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	if m.Cursor() != 0 {
		t.Errorf("after wrap: cursor = %d, want 0 (wrapped)", m.Cursor())
	}
}

func TestNavigateUp(t *testing.T) {
	m := New("Settings", testEntries())

	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyUp})
	if m.Cursor() != 3 {
		t.Errorf("after up from 0: cursor = %d, want 3 (wrapped)", m.Cursor())
	}
}

func TestToggleBoolOff(t *testing.T) {
	m := New("Settings", testEntries())
	// cursor at 0 = verbose (off)

	var cmd tea.Cmd
	m, cmd = m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil {
		t.Fatal("expected ChangedMsg command")
	}

	msg := cmd()
	changed, ok := msg.(ChangedMsg)
	if !ok {
		t.Fatalf("expected ChangedMsg, got %T", msg)
	}
	if changed.Key != "verbose" {
		t.Errorf("Key = %q, want verbose", changed.Key)
	}
	if changed.OldValue != "off" {
		t.Errorf("OldValue = %q, want off", changed.OldValue)
	}
	if changed.NewValue != "on" {
		t.Errorf("NewValue = %q, want on", changed.NewValue)
	}

	// Entry should be updated in model
	if m.Entries()[0].Value != "on" {
		t.Errorf("entry value = %q, want on", m.Entries()[0].Value)
	}
}

func TestToggleBoolOn(t *testing.T) {
	m := New("Settings", testEntries())
	// Move to auto-scroll (index 1, value "on")
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})

	m, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil {
		t.Fatal("expected command")
	}

	msg := cmd()
	changed := msg.(ChangedMsg)
	if changed.OldValue != "on" || changed.NewValue != "off" {
		t.Errorf("toggle on→off: got %q→%q", changed.OldValue, changed.NewValue)
	}
}

func TestToggleEnumCycle(t *testing.T) {
	m := New("Settings", testEntries())
	// Move to theme (index 2)
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})

	// Cycle: Tokyo Night → Catppuccin
	m, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	msg := cmd().(ChangedMsg)
	if msg.NewValue != "Catppuccin" {
		t.Errorf("first cycle: got %q, want Catppuccin", msg.NewValue)
	}

	// Cycle: Catppuccin → Gruvbox
	m, cmd = m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	msg = cmd().(ChangedMsg)
	if msg.NewValue != "Gruvbox" {
		t.Errorf("second cycle: got %q, want Gruvbox", msg.NewValue)
	}

	// Cycle: Gruvbox → Tokyo Night (wrap)
	m, cmd = m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	msg = cmd().(ChangedMsg)
	if msg.NewValue != "Tokyo Night" {
		t.Errorf("wrap cycle: got %q, want Tokyo Night", msg.NewValue)
	}
}

func TestSpaceToggles(t *testing.T) {
	m := New("Settings", testEntries())
	m, cmd := m.Update(tea.KeyMsg{Type: tea.KeySpace})
	if cmd == nil {
		t.Fatal("Space should toggle like Enter")
	}
	msg := cmd().(ChangedMsg)
	if msg.Key != "verbose" {
		t.Errorf("Key = %q, want verbose", msg.Key)
	}
}

func TestEscDismisses(t *testing.T) {
	m := New("Settings", testEntries())
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	if cmd == nil {
		t.Fatal("expected DismissedMsg command")
	}
	msg := cmd()
	if _, ok := msg.(DismissedMsg); !ok {
		t.Fatalf("expected DismissedMsg, got %T", msg)
	}
}

func TestNumberKeyJumps(t *testing.T) {
	m := New("Settings", testEntries())
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'3'}})
	if m.Cursor() != 2 {
		t.Errorf("after '3': cursor = %d, want 2", m.Cursor())
	}
}

func TestNumberKeyOutOfRange(t *testing.T) {
	m := New("Settings", testEntries())
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'9'}})
	if m.Cursor() != 0 {
		t.Errorf("out-of-range number key should not move cursor, got %d", m.Cursor())
	}
}

func TestViewContainsKeys(t *testing.T) {
	m := New("Settings", testEntries())
	view := m.View()
	for _, key := range []string{"verbose", "auto-scroll", "theme", "color-mode"} {
		if !strings.Contains(view, key) {
			t.Errorf("view should contain %q", key)
		}
	}
}

func TestViewContainsTitle(t *testing.T) {
	m := New("My Settings", testEntries())
	if !strings.Contains(m.View(), "My Settings") {
		t.Error("view should contain title")
	}
}

func TestViewContainsHints(t *testing.T) {
	m := New("Settings", testEntries())
	view := m.View()
	if !strings.Contains(view, "Esc") {
		t.Error("view should contain Esc hint")
	}
	if !strings.Contains(view, "navigate") {
		t.Error("view should contain navigate hint")
	}
}

func TestSetWidth(t *testing.T) {
	m := New("Settings", testEntries())
	m = m.SetWidth(120)
	// Should not panic
	_ = m.View()
}

func TestUpdateEntry(t *testing.T) {
	m := New("Settings", testEntries())
	e := m.Entries()[0]
	e.Value = "on"
	m = m.UpdateEntry(0, e)
	if m.Entries()[0].Value != "on" {
		t.Errorf("UpdateEntry didn't take effect: %q", m.Entries()[0].Value)
	}
}

func TestEmptyEntries(t *testing.T) {
	m := New("Settings", nil)
	m, cmd := m.Update(tea.KeyMsg{Type: tea.KeyDown})
	if cmd != nil {
		t.Error("empty entries: down should produce no command")
	}
	_ = m.View() // should not panic
}
