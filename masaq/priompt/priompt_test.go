package priompt_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/priompt"
)

// --- Task 3: Core Render tests ---

func TestRenderEmptyElements(t *testing.T) {
	r := priompt.Render(nil, 1000)
	if r.Prompt != "" {
		t.Fatalf("expected empty prompt, got %q", r.Prompt)
	}
	if len(r.Included) != 0 || len(r.Excluded) != 0 {
		t.Fatal("expected no included or excluded")
	}
}

func TestRenderBudgetZero(t *testing.T) {
	elems := []priompt.Element{
		{Name: "a", Content: "hello", Priority: 10},
		{Name: "b", Content: "world", Priority: 5},
	}
	r := priompt.Render(elems, 0)
	if r.Prompt != "" {
		t.Fatalf("expected empty prompt, got %q", r.Prompt)
	}
	if len(r.Excluded) != 2 {
		t.Fatalf("expected 2 excluded, got %d", len(r.Excluded))
	}
}

func TestRenderBudgetNegative(t *testing.T) {
	elems := []priompt.Element{
		{Name: "a", Content: "hello", Priority: 10},
	}
	r := priompt.Render(elems, -5)
	if r.Prompt != "" {
		t.Fatal("expected empty prompt for negative budget")
	}
	if len(r.Excluded) != 1 {
		t.Fatal("expected 1 excluded")
	}
}

func TestRenderBudgetZeroEmptyContentSkipped(t *testing.T) {
	elems := []priompt.Element{
		{Name: "real", Content: "hello", Priority: 10},
		{Name: "empty", Content: "", Priority: 20},
	}
	r := priompt.Render(elems, 0)
	// Empty content should be silently skipped — not in Excluded.
	if len(r.Excluded) != 1 {
		t.Fatalf("expected 1 excluded (empty skipped), got %d: %v", len(r.Excluded), r.Excluded)
	}
	if r.Excluded[0] != "real" {
		t.Fatalf("expected 'real' excluded, got %q", r.Excluded[0])
	}
}

func TestRenderSingleElement(t *testing.T) {
	elems := []priompt.Element{
		{Name: "a", Content: "hello world"},
	}
	r := priompt.Render(elems, 10000)
	if r.Prompt != "hello world" {
		t.Fatalf("expected exact content, got %q", r.Prompt)
	}
	if len(r.Included) != 1 || r.Included[0] != "a" {
		t.Fatal("expected 'a' included")
	}
}

func TestRenderSingleElementExactBudget(t *testing.T) {
	// Single element at exact budget boundary. Separator cost must be 0 for first element.
	content := "abcd" // 4 chars = 1 token with ratio 4
	elems := []priompt.Element{
		{Name: "a", Content: content},
	}
	r := priompt.Render(elems, 1) // budget = 1 token
	if r.Prompt != content {
		t.Fatalf("single element at exact budget should be included, got prompt=%q, excluded=%v", r.Prompt, r.Excluded)
	}
}

func TestRenderThreeElementsBudgetFitsTwo(t *testing.T) {
	// Each element ~1 token (4 chars). Separator "\n\n" = 1 token.
	// Two elements + 1 separator = 3 tokens.
	elems := []priompt.Element{
		{Name: "high", Content: "aaaa", Priority: 30},
		{Name: "mid", Content: "bbbb", Priority: 20},
		{Name: "low", Content: "cccc", Priority: 10},
	}
	r := priompt.Render(elems, 3) // fits 2 elements + 1 sep
	if len(r.Included) != 2 {
		t.Fatalf("expected 2 included, got %d: %v", len(r.Included), r.Included)
	}
	if r.Included[0] != "high" || r.Included[1] != "mid" {
		t.Fatalf("expected high,mid included, got %v", r.Included)
	}
	if len(r.Excluded) != 1 || r.Excluded[0] != "low" {
		t.Fatalf("expected low excluded, got %v", r.Excluded)
	}
}

func TestRenderSeparatorCount(t *testing.T) {
	// 3 elements → 2 separators. With short separator ";" (1 token).
	// Each element 4 chars = 1 token. Total: 3 + 2 = 5 tokens.
	elems := []priompt.Element{
		{Name: "a", Content: "aaaa", Priority: 30},
		{Name: "b", Content: "bbbb", Priority: 20},
		{Name: "c", Content: "cccc", Priority: 10},
	}
	// Budget 5 should fit all 3 elements with ";" separator.
	r := priompt.Render(elems, 5, priompt.WithSeparator(";"))
	if len(r.Included) != 3 {
		t.Fatalf("expected 3 included with budget 5, got %d", len(r.Included))
	}
	// Budget 4 should fit only 2 (2 elements + 1 sep = 3, 3rd element + sep = 2 more = 5 > 4)
	r2 := priompt.Render(elems, 4, priompt.WithSeparator(";"))
	if len(r2.Included) != 2 {
		t.Fatalf("expected 2 included with budget 4, got %d", len(r2.Included))
	}
}

func TestRenderCustomSeparator(t *testing.T) {
	elems := []priompt.Element{
		{Name: "a", Content: "hello", Priority: 10},
		{Name: "b", Content: "world", Priority: 5},
	}
	r := priompt.Render(elems, 10000, priompt.WithSeparator("---"))
	if !strings.Contains(r.Prompt, "---") {
		t.Fatal("expected custom separator in prompt")
	}
	if strings.Contains(r.Prompt, "\n\n") {
		t.Fatal("should not contain default separator")
	}
}

func TestRenderEmptyContentSkipped(t *testing.T) {
	elems := []priompt.Element{
		{Name: "real", Content: "hello", Priority: 10},
		{Name: "empty", Content: "", Priority: 20},
	}
	r := priompt.Render(elems, 10000)
	if len(r.Included) != 1 || r.Included[0] != "real" {
		t.Fatalf("expected only 'real' included, got %v", r.Included)
	}
	// Empty content should not appear in Included or Excluded.
	for _, name := range r.Excluded {
		if name == "empty" {
			t.Fatal("empty-content element should not appear in Excluded")
		}
	}
}

func TestRenderDeterministic(t *testing.T) {
	elems := []priompt.Element{
		{Name: "a", Content: "alpha", Priority: 10},
		{Name: "b", Content: "bravo", Priority: 20},
		{Name: "c", Content: "charlie", Priority: 10},
	}
	first := priompt.Render(elems, 100)
	for i := 0; i < 100; i++ {
		r := priompt.Render(elems, 100)
		if r.Prompt != first.Prompt {
			t.Fatalf("iteration %d: prompt differs", i)
		}
	}
}

func TestRenderEqualPrioritySortedByName(t *testing.T) {
	elems := []priompt.Element{
		{Name: "charlie", Content: "c", Priority: 10},
		{Name: "alpha", Content: "a", Priority: 10},
		{Name: "bravo", Content: "b", Priority: 10},
	}
	r := priompt.Render(elems, 10000)
	// Should be sorted by name: alpha, bravo, charlie.
	if r.Included[0] != "alpha" || r.Included[1] != "bravo" || r.Included[2] != "charlie" {
		t.Fatalf("expected alphabetical order, got %v", r.Included)
	}
}

func TestRenderAllExceedBudget(t *testing.T) {
	// Each element is much larger than the budget.
	elems := []priompt.Element{
		{Name: "big", Content: strings.Repeat("x", 1000), Priority: 10},
		{Name: "bigger", Content: strings.Repeat("y", 2000), Priority: 20},
	}
	r := priompt.Render(elems, 1)
	if r.Prompt != "" {
		t.Fatal("expected empty prompt when all elements exceed budget")
	}
	if len(r.Excluded) != 2 {
		t.Fatalf("expected 2 excluded, got %d", len(r.Excluded))
	}
}

// --- Task 4: Tokenizer tests ---

func TestCharHeuristicBasic(t *testing.T) {
	h := priompt.CharHeuristic{Ratio: 4}
	// "hello" = 5 chars / 4 = 1 (max(1, 1))
	if got := h.Count("hello"); got != 1 {
		t.Fatalf("expected 1, got %d", got)
	}
}

func TestCharHeuristicEmpty(t *testing.T) {
	h := priompt.CharHeuristic{Ratio: 4}
	if got := h.Count(""); got != 0 {
		t.Fatalf("expected 0 for empty, got %d", got)
	}
}

func TestCharHeuristicZeroRatio(t *testing.T) {
	h := priompt.CharHeuristic{Ratio: 0}
	// Should fall back to ratio 4, not panic.
	got := h.Count("hello")
	if got != 1 {
		t.Fatalf("expected 1 with fallback ratio, got %d", got)
	}
}

func TestCharHeuristicRatioOne(t *testing.T) {
	h := priompt.CharHeuristic{Ratio: 1}
	if got := h.Count("hello"); got != 5 {
		t.Fatalf("expected 5 with ratio 1, got %d", got)
	}
}

func TestCharHeuristicShortSeparator(t *testing.T) {
	h := priompt.CharHeuristic{Ratio: 4}
	// "\n\n" = 2 chars / 4 = 0, but max(1, 0) = 1
	if got := h.Count("\n\n"); got != 1 {
		t.Fatalf("expected 1 for short separator, got %d", got)
	}
}

func TestWithTokenizerOverride(t *testing.T) {
	fixed := fixedTokenizer(10)
	elems := []priompt.Element{
		{Name: "a", Content: "short", Priority: 10},
	}
	// Fixed tokenizer says everything is 10 tokens. Budget 9 should exclude.
	r := priompt.Render(elems, 9, priompt.WithTokenizer(fixed))
	if len(r.Excluded) != 1 {
		t.Fatal("expected element excluded with fixed tokenizer")
	}
	// Budget 10 should include.
	r2 := priompt.Render(elems, 10, priompt.WithTokenizer(fixed))
	if len(r2.Included) != 1 {
		t.Fatal("expected element included with budget matching fixed tokenizer")
	}
}

// fixedTokenizer always returns a fixed count.
type fixedTokenizer int

func (f fixedTokenizer) Count(s string) int {
	if len(s) == 0 {
		return 0
	}
	return int(f)
}

// --- Task 5: Cache-aware ordering tests ---

func TestStableBeforeDynamic(t *testing.T) {
	elems := []priompt.Element{
		{Name: "dynamic-high", Content: "dyn", Priority: 100, Stable: false},
		{Name: "stable-low", Content: "stb", Priority: 1, Stable: true},
	}
	r := priompt.Render(elems, 10000)
	if r.Included[0] != "stable-low" {
		t.Fatalf("stable should render first, got %v", r.Included)
	}
}

func TestStablePartitionSortedByPriority(t *testing.T) {
	elems := []priompt.Element{
		{Name: "s-low", Content: "aaa", Priority: 10, Stable: true},
		{Name: "s-high", Content: "bbb", Priority: 50, Stable: true},
	}
	r := priompt.Render(elems, 10000)
	if r.Included[0] != "s-high" || r.Included[1] != "s-low" {
		t.Fatalf("stable should be sorted by priority, got %v", r.Included)
	}
}

func TestStableTokensCorrect(t *testing.T) {
	elems := []priompt.Element{
		{Name: "s1", Content: strings.Repeat("a", 40), Priority: 10, Stable: true},  // 10 tokens
		{Name: "s2", Content: strings.Repeat("b", 40), Priority: 5, Stable: true},   // 10 tokens
		{Name: "d1", Content: strings.Repeat("c", 20), Priority: 3, Stable: false},  // 5 tokens
	}
	r := priompt.Render(elems, 10000)
	// Stable prefix: s1 + "\n\n" + s2 = 40 + 2 + 40 = 82 chars.
	// Count("aaa...a\n\naaa...a") with ratio 4.
	h := priompt.CharHeuristic{Ratio: 4}
	expected := h.Count(strings.Repeat("a", 40) + "\n\n" + strings.Repeat("b", 40))
	if r.StableTokens != expected {
		t.Fatalf("StableTokens: expected %d, got %d", expected, r.StableTokens)
	}
}

func TestStableExcludedZerosStableTokens(t *testing.T) {
	// Make stable element too large for budget.
	elems := []priompt.Element{
		{Name: "big-stable", Content: strings.Repeat("x", 1000), Priority: 10, Stable: true},
		{Name: "small-dynamic", Content: "hi", Priority: 5, Stable: false},
	}
	r := priompt.Render(elems, 5) // too small for stable
	if r.StableTokens != 0 {
		t.Fatalf("StableTokens should be 0 when stable is excluded, got %d", r.StableTokens)
	}
	if len(r.ExcludedStable) != 1 || r.ExcludedStable[0] != "big-stable" {
		t.Fatalf("expected big-stable in ExcludedStable, got %v", r.ExcludedStable)
	}
}

func TestExcludedStableSeparateFromExcluded(t *testing.T) {
	elems := []priompt.Element{
		{Name: "stable", Content: strings.Repeat("x", 1000), Priority: 10, Stable: true},
		{Name: "dynamic", Content: strings.Repeat("y", 1000), Priority: 5, Stable: false},
	}
	r := priompt.Render(elems, 1) // nothing fits
	if len(r.ExcludedStable) != 1 || r.ExcludedStable[0] != "stable" {
		t.Fatalf("expected stable in ExcludedStable, got %v", r.ExcludedStable)
	}
	if len(r.Excluded) != 1 || r.Excluded[0] != "dynamic" {
		t.Fatalf("expected dynamic in Excluded, got %v", r.Excluded)
	}
}

func TestMixedStableDynamicTightBudget(t *testing.T) {
	elems := []priompt.Element{
		{Name: "stable", Content: "aaaa", Priority: 10, Stable: true},   // 1 token
		{Name: "dynamic", Content: "bbbb", Priority: 50, Stable: false}, // 1 token
	}
	// Budget 3: stable(1) + sep(1) + dynamic(1). Stable gets priority placement.
	r := priompt.Render(elems, 3, priompt.WithSeparator(";"))
	if len(r.Included) != 2 {
		t.Fatalf("expected both included, got %v (excluded: %v)", r.Included, r.Excluded)
	}
	if r.Included[0] != "stable" {
		t.Fatal("stable should be first")
	}
}

// --- Task 6: Phase boost tests ---

func TestPhaseBoostActivates(t *testing.T) {
	elems := []priompt.Element{
		{Name: "base-high", Content: "aaaa", Priority: 50},
		{Name: "boosted", Content: "bbbb", Priority: 10, PhaseBoost: map[string]int{"build": 100}},
	}
	r := priompt.Render(elems, 10000, priompt.WithPhase("build"))
	// With boost, "boosted" has effective priority 110 > 50.
	if r.Included[0] != "boosted" {
		t.Fatalf("boosted should be first with build phase, got %v", r.Included)
	}
}

func TestNoPhaseBoostsInert(t *testing.T) {
	elems := []priompt.Element{
		{Name: "high", Content: "aaaa", Priority: 50},
		{Name: "low", Content: "bbbb", Priority: 10, PhaseBoost: map[string]int{"build": 100}},
	}
	r := priompt.Render(elems, 10000) // no WithPhase
	if r.Included[0] != "high" {
		t.Fatalf("without phase, base priority wins, got %v", r.Included)
	}
}

func TestEmptyPhaseInert(t *testing.T) {
	elems := []priompt.Element{
		{Name: "high", Content: "aaaa", Priority: 50},
		{Name: "low", Content: "bbbb", Priority: 10, PhaseBoost: map[string]int{"build": 100}},
	}
	r := priompt.Render(elems, 10000, priompt.WithPhase(""))
	if r.Included[0] != "high" {
		t.Fatalf("empty phase should be inert, got %v", r.Included)
	}
}

func TestNilPhaseBoostMapSafe(t *testing.T) {
	elems := []priompt.Element{
		{Name: "a", Content: "aaaa", Priority: 10, PhaseBoost: nil},
	}
	// Should not panic.
	r := priompt.Render(elems, 10000, priompt.WithPhase("build"))
	if len(r.Included) != 1 {
		t.Fatal("nil PhaseBoost should be safe")
	}
}

func TestNegativeEffectivePriority(t *testing.T) {
	elems := []priompt.Element{
		{Name: "demoted", Content: "aaaa", Priority: 5, PhaseBoost: map[string]int{"review": -20}},
		{Name: "normal", Content: "bbbb", Priority: 1},
	}
	r := priompt.Render(elems, 10000, priompt.WithPhase("review"))
	// demoted: 5 + (-20) = -15. normal: 1. normal should be first.
	if r.Included[0] != "normal" {
		t.Fatalf("negative priority should sort lower, got %v", r.Included)
	}
}

func TestPositiveBoostPromotes(t *testing.T) {
	elems := []priompt.Element{
		{Name: "base-high", Content: "aaaa", Priority: 50},
		{Name: "promoted", Content: "bbbb", Priority: 10, PhaseBoost: map[string]int{"plan": 50}},
	}
	// With boost: promoted = 60, base-high = 50.
	r := priompt.Render(elems, 10000, priompt.WithPhase("plan"))
	if r.Included[0] != "promoted" {
		t.Fatalf("positive boost should promote, got %v", r.Included)
	}
}

func TestNegativeBoostDemotes(t *testing.T) {
	elems := []priompt.Element{
		{Name: "demoted", Content: "aaaa", Priority: 50, PhaseBoost: map[string]int{"ship": -40}},
		{Name: "stays", Content: "bbbb", Priority: 20},
	}
	// demoted: 50 + (-40) = 10. stays: 20. stays should be first.
	r := priompt.Render(elems, 10000, priompt.WithPhase("ship"))
	if r.Included[0] != "stays" {
		t.Fatalf("negative boost should demote, got %v", r.Included)
	}
}
