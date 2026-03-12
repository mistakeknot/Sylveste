package question_test

import (
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mistakeknot/Masaq/question"
)

func TestNewQuestion(t *testing.T) {
	q := question.New("Which approach?", []question.Option{
		{Label: "Option A", Description: "First approach"},
		{Label: "Option B", Description: "Second approach"},
	})
	if q.Question() != "Which approach?" {
		t.Fatalf("got %q", q.Question())
	}
	if len(q.Options()) != 2 {
		t.Fatalf("got %d options", len(q.Options()))
	}
}

func TestNavigation(t *testing.T) {
	q := question.New("Pick:", []question.Option{
		{Label: "A"}, {Label: "B"}, {Label: "C"},
	})
	if q.Cursor() != 0 {
		t.Fatalf("initial cursor=%d, want 0", q.Cursor())
	}
	q, _ = q.Update(tea.KeyMsg{Type: tea.KeyDown})
	if q.Cursor() != 1 {
		t.Fatalf("after down cursor=%d, want 1", q.Cursor())
	}
}

func TestSelectSendsMsg(t *testing.T) {
	q := question.New("Pick:", []question.Option{
		{Label: "A"}, {Label: "B"},
	})
	_, cmd := q.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil {
		t.Fatal("enter should produce a command")
	}
	msg := cmd()
	selected, ok := msg.(question.SelectedMsg)
	if !ok {
		t.Fatalf("expected SelectedMsg, got %T", msg)
	}
	if selected.Index != 0 || selected.Label != "A" {
		t.Fatalf("got index=%d label=%q", selected.Index, selected.Label)
	}
}

func TestWrapAround(t *testing.T) {
	q := question.New("Pick:", []question.Option{
		{Label: "A"}, {Label: "B"},
	})
	// Wrap down
	q, _ = q.Update(tea.KeyMsg{Type: tea.KeyDown})
	q, _ = q.Update(tea.KeyMsg{Type: tea.KeyDown})
	if q.Cursor() != 0 {
		t.Fatalf("cursor should wrap to 0, got %d", q.Cursor())
	}
	// Wrap up
	q, _ = q.Update(tea.KeyMsg{Type: tea.KeyUp})
	if q.Cursor() != 1 {
		t.Fatalf("cursor should wrap to 1, got %d", q.Cursor())
	}
}
