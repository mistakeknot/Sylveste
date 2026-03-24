package spinner

import (
	"testing"
	"time"
)

func TestZeroValueViewEmpty(t *testing.T) {
	var s Model
	if s.View() != "" {
		t.Fatal("zero-value spinner should render empty string")
	}
}

func TestNewDefaults(t *testing.T) {
	s := New()
	if len(s.Frames) == 0 {
		t.Fatal("default frames should not be empty")
	}
	if s.Interval != DefaultInterval {
		t.Fatalf("interval = %v, want %v", s.Interval, DefaultInterval)
	}
}

func TestViewRendersFrame(t *testing.T) {
	s := New()
	v := s.View()
	if v == "" {
		t.Fatal("view should not be empty")
	}
}

func TestViewWithLabel(t *testing.T) {
	s := New()
	s.Label = "Thinking"
	v := s.View()
	if v == "" {
		t.Fatal("view with label should not be empty")
	}
}

func TestUpdateAdvancesFrame(t *testing.T) {
	s := New()
	initial := s.View()

	s, cmd := s.Update(TickMsg{ID: s.id})
	if cmd == nil {
		t.Fatal("update should return next tick command")
	}

	advanced := s.View()
	if advanced == initial {
		t.Fatal("frame should change after tick")
	}
}

func TestUpdateIgnoresWrongID(t *testing.T) {
	s := New()
	initial := s.frame

	s, cmd := s.Update(TickMsg{ID: s.id + 999})
	if cmd != nil {
		t.Fatal("update with wrong ID should return nil cmd")
	}
	if s.frame != initial {
		t.Fatal("frame should not change for wrong ID")
	}
}

func TestFrameWraps(t *testing.T) {
	s := New()
	s.Frames = Frames{"a", "b", "c"}

	for i := 0; i < 10; i++ {
		s, _ = s.Update(TickMsg{ID: s.id})
	}
	// Should not panic — frame wraps modulo len(Frames)
	_ = s.View()
}

func TestTickReturnsCmdWithInterval(t *testing.T) {
	s := New()
	s.Interval = 50 * time.Millisecond
	cmd := s.Tick()
	if cmd == nil {
		t.Fatal("Tick should return a non-nil command")
	}
}

func TestMultipleSpinnersIndependent(t *testing.T) {
	s1 := New()
	s2 := New()
	if s1.id == s2.id {
		t.Fatal("different spinners should have different IDs")
	}

	// Tick for s1 should not advance s2
	s2Initial := s2.frame
	s2, cmd := s2.Update(TickMsg{ID: s1.id})
	if cmd != nil {
		t.Fatal("s2 should not respond to s1's tick")
	}
	if s2.frame != s2Initial {
		t.Fatal("s2 frame should not change from s1's tick")
	}
}

func TestCustomFrames(t *testing.T) {
	s := New()
	s.Frames = Line
	v := s.View()
	if v == "" {
		t.Fatal("custom frames should render")
	}
}

func TestPulseFrames(t *testing.T) {
	s := New()
	s.Frames = Pulse
	// Cycle through all frames
	for i := 0; i < len(Pulse)+1; i++ {
		_ = s.View()
		s, _ = s.Update(TickMsg{ID: s.id})
	}
}

func TestEllipsisFrames(t *testing.T) {
	s := New()
	s.Frames = Ellipsis
	for i := 0; i < len(Ellipsis); i++ {
		_ = s.View()
		s, _ = s.Update(TickMsg{ID: s.id})
	}
}
