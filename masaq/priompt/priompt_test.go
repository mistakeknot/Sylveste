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

// --- ContentFunc (dynamic rendering) tests ---

func TestContentFuncOverridesStatic(t *testing.T) {
	elems := []priompt.Element{
		{
			Name:     "dynamic",
			Content:  "static fallback",
			Priority: 10,
			Render: func(ctx priompt.RenderContext) string {
				return "dynamic content"
			},
		},
	}
	r := priompt.Render(elems, 10000)
	if r.Prompt != "dynamic content" {
		t.Fatalf("expected dynamic content, got %q", r.Prompt)
	}
}

func TestContentFuncReceivesPhase(t *testing.T) {
	elems := []priompt.Element{
		{
			Name:     "phase-aware",
			Priority: 10,
			Render: func(ctx priompt.RenderContext) string {
				return "phase=" + ctx.Phase
			},
		},
	}
	r := priompt.Render(elems, 10000, priompt.WithPhase("build"))
	if r.Prompt != "phase=build" {
		t.Fatalf("expected phase=build, got %q", r.Prompt)
	}
}

func TestContentFuncReceivesModel(t *testing.T) {
	elems := []priompt.Element{
		{
			Name:     "model-aware",
			Priority: 10,
			Render: func(ctx priompt.RenderContext) string {
				return "model=" + ctx.Model
			},
		},
	}
	r := priompt.Render(elems, 10000, priompt.WithModel("opus"))
	if r.Prompt != "model=opus" {
		t.Fatalf("expected model=opus, got %q", r.Prompt)
	}
}

func TestContentFuncReceivesTurnCount(t *testing.T) {
	var gotTurn int
	elems := []priompt.Element{
		{
			Name:     "turn-aware",
			Priority: 10,
			Render: func(ctx priompt.RenderContext) string {
				gotTurn = ctx.TurnCount
				return "ok"
			},
		},
	}
	priompt.Render(elems, 10000, priompt.WithTurnCount(42))
	if gotTurn != 42 {
		t.Fatalf("expected turn count 42, got %d", gotTurn)
	}
}

func TestContentFuncEmptyExcludes(t *testing.T) {
	elems := []priompt.Element{
		{
			Name:     "conditional",
			Priority: 10,
			Render: func(ctx priompt.RenderContext) string {
				if ctx.Phase == "build" {
					return "build instructions"
				}
				return "" // excluded in other phases
			},
		},
		{Name: "always", Content: "hello", Priority: 5},
	}
	// In review phase, conditional returns empty → excluded
	r := priompt.Render(elems, 10000, priompt.WithPhase("review"))
	if len(r.Included) != 1 || r.Included[0] != "always" {
		t.Fatalf("conditional should be excluded in review, got %v", r.Included)
	}
	// In build phase, conditional returns content → included
	r2 := priompt.Render(elems, 10000, priompt.WithPhase("build"))
	if len(r2.Included) != 2 {
		t.Fatalf("conditional should be included in build, got %v", r2.Included)
	}
}

func TestContentFuncNilFallsBackToContent(t *testing.T) {
	elems := []priompt.Element{
		{Name: "static", Content: "hello", Priority: 10, Render: nil},
	}
	r := priompt.Render(elems, 10000)
	if r.Prompt != "hello" {
		t.Fatalf("nil Render should use static Content, got %q", r.Prompt)
	}
}

func TestContentFuncBudgetInContext(t *testing.T) {
	var gotBudget int
	elems := []priompt.Element{
		{
			Name:     "budget-aware",
			Priority: 10,
			Render: func(ctx priompt.RenderContext) string {
				gotBudget = ctx.Budget
				return "ok"
			},
		},
	}
	priompt.Render(elems, 5000)
	if gotBudget != 5000 {
		t.Fatalf("expected budget 5000, got %d", gotBudget)
	}
}

// --- Packing efficiency observability tests ---

func TestPackingEfficiencyGenerousBudget(t *testing.T) {
	elems := []priompt.Element{
		{Name: "a", Content: strings.Repeat("x", 40), Priority: 10}, // 10 tokens
		{Name: "b", Content: strings.Repeat("y", 40), Priority: 5},  // 10 tokens
	}
	r := priompt.Render(elems, 10000) // way more than needed
	if r.PackingEfficiency >= 1.0 {
		t.Fatalf("generous budget should have efficiency < 1.0, got %f", r.PackingEfficiency)
	}
	if r.PackingEfficiency <= 0 {
		t.Fatalf("efficiency should be positive, got %f", r.PackingEfficiency)
	}
	if r.WastedTokens <= 0 {
		t.Fatalf("should have wasted tokens with generous budget, got %d", r.WastedTokens)
	}
}

func TestPackingEfficiencyTightBudget(t *testing.T) {
	// 3 elements: 1 token each. 2 separators at 1 token each. Total needed: 5.
	elems := []priompt.Element{
		{Name: "a", Content: "aaaa", Priority: 30}, // 1 token
		{Name: "b", Content: "bbbb", Priority: 20}, // 1 token
		{Name: "c", Content: "cccc", Priority: 10}, // 1 token
	}
	r := priompt.Render(elems, 5, priompt.WithSeparator(";"))
	// All fit exactly: 3 tokens + 2 seps = 5
	if r.PackingEfficiency != 1.0 {
		t.Fatalf("expected efficiency 1.0 for exact fit, got %f", r.PackingEfficiency)
	}
	if r.WastedTokens != 0 {
		t.Fatalf("expected 0 wasted tokens for exact fit, got %d", r.WastedTokens)
	}
}

func TestPackingEfficiencyZeroBudget(t *testing.T) {
	elems := []priompt.Element{
		{Name: "a", Content: "hello", Priority: 10},
	}
	r := priompt.Render(elems, 0)
	if r.PackingEfficiency != 0 {
		t.Fatalf("zero budget should have 0 efficiency, got %f", r.PackingEfficiency)
	}
}

func TestExcludedPrioritySum(t *testing.T) {
	elems := []priompt.Element{
		{Name: "big", Content: strings.Repeat("x", 1000), Priority: 50},  // 250 tokens
		{Name: "also-big", Content: strings.Repeat("y", 1000), Priority: 30}, // 250 tokens
	}
	r := priompt.Render(elems, 1) // nothing fits
	if r.ExcludedPrioritySum != 80 {
		t.Fatalf("expected excluded priority sum 80, got %d", r.ExcludedPrioritySum)
	}
}

func TestExcludedPrioritySumWithPhaseBoost(t *testing.T) {
	elems := []priompt.Element{
		{Name: "fits", Content: "aaaa", Priority: 10},                                       // 1 token, fits
		{Name: "excluded", Content: strings.Repeat("x", 1000), Priority: 20, PhaseBoost: map[string]int{"plan": 15}}, // 250 tokens, excluded
	}
	r := priompt.Render(elems, 5, priompt.WithPhase("plan"))
	// excluded effective priority: 20 + 15 = 35
	if r.ExcludedPrioritySum != 35 {
		t.Fatalf("expected excluded priority sum 35 (with boost), got %d", r.ExcludedPrioritySum)
	}
}

func TestWastedTokensPlusTotalEqualsBudget(t *testing.T) {
	elems := makeElements(20)
	budget := 500
	r := priompt.Render(elems, budget, priompt.WithPhase("execute"))
	if r.TotalTokens+r.WastedTokens != budget {
		t.Fatalf("TotalTokens(%d) + WastedTokens(%d) should equal budget(%d)",
			r.TotalTokens, r.WastedTokens, budget)
	}
}

func TestFillPassRecoversSmallElement(t *testing.T) {
	// Greedy pass: high(1) fits, big(250) doesn't fit, small(1) would fit but comes after big.
	// Fill pass should recover small since it's tried smallest-first.
	elems := []priompt.Element{
		{Name: "high", Content: "aaaa", Priority: 30},                         // 1 token
		{Name: "big", Content: strings.Repeat("x", 1000), Priority: 20},       // 250 tokens — won't fit
		{Name: "small", Content: "bbbb", Priority: 10},                         // 1 token — fits after fill
	}
	r := priompt.Render(elems, 4, priompt.WithSeparator(";"))
	// Budget 4: high(1) + sep(1) + small(1) + sep(1) = 4. big excluded.
	if len(r.Included) != 2 {
		t.Fatalf("fill pass should recover small element, got %d included: %v (excluded: %v)",
			len(r.Included), r.Included, r.Excluded)
	}
	found := false
	for _, name := range r.Included {
		if name == "small" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected small in included after fill pass, got %v", r.Included)
	}
	if len(r.Excluded) != 1 || r.Excluded[0] != "big" {
		t.Fatalf("expected only big excluded, got %v", r.Excluded)
	}
}

func TestFillPassImprovesTightBudgetEfficiency(t *testing.T) {
	// Create a scenario where greedy leaves waste but fill pass can recover.
	// Mix of large and small elements with a tight budget.
	elems := []priompt.Element{
		{Name: "s1", Content: strings.Repeat("a", 100), Priority: 90, Stable: true},   // 25 tokens
		{Name: "big", Content: strings.Repeat("b", 800), Priority: 80},                 // 200 tokens — won't fit
		{Name: "med", Content: strings.Repeat("c", 200), Priority: 70},                 // 50 tokens
		{Name: "tiny1", Content: "aaaa", Priority: 60},                                  // 1 token
		{Name: "tiny2", Content: "bbbb", Priority: 50},                                  // 1 token
	}
	r := priompt.Render(elems, 80) // tight: s1(25)+sep(1)+med(50)=76, leaving 4 tokens
	// Fill pass should pick up tiny1 and tiny2 from the remaining 4 tokens
	if r.PackingEfficiency < 0.9 {
		t.Fatalf("fill pass should achieve >0.9 efficiency, got %f", r.PackingEfficiency)
	}
}

func TestStableCapDemotesOverflow(t *testing.T) {
	// Without cap: big-stable consumes 250 of 300 tokens, only 1 dynamic fits.
	// With cap 0.5: stable budget = 150, big-stable (250) demoted to dynamic queue.
	// Dynamic queue gets big-stable (250, pri 10) + small-dyn (1, pri 80) + med-dyn (50, pri 60).
	// Priority order: small-dyn(80), med-dyn(60), big-stable(10).
	// Packs: small-dyn(1) + sep(1) + med-dyn(50) + sep(1) = 53. Remaining: 247.
	// big-stable(250) + sep(1) = 251 > 247, excluded.
	elems := []priompt.Element{
		{Name: "big-stable", Content: strings.Repeat("x", 1000), Priority: 10, Stable: true}, // 250 tokens
		{Name: "small-dyn", Content: "aaaa", Priority: 80},                                     // 1 token
		{Name: "med-dyn", Content: strings.Repeat("y", 200), Priority: 60},                    // 50 tokens
	}

	// Without cap: big-stable fits first (250), then small-dyn(1+1=2). Total: 252. med-dyn excluded.
	rNoCap := priompt.Render(elems, 300)
	if len(rNoCap.Included) != 2 {
		t.Fatalf("no cap: expected 2 included, got %d: %v", len(rNoCap.Included), rNoCap.Included)
	}

	// With cap 0.5: stable budget = 150. big-stable (250) won't fit → demoted.
	rCapped := priompt.Render(elems, 300, priompt.WithStableCap(0.5))
	// Should include small-dyn + med-dyn (higher priority than big-stable when competing as dynamic).
	if len(rCapped.Included) < 2 {
		t.Fatalf("capped: expected ≥2 included, got %d: %v", len(rCapped.Included), rCapped.Included)
	}
	// med-dyn should now be included (was excluded without cap)
	found := false
	for _, name := range rCapped.Included {
		if name == "med-dyn" {
			found = true
		}
	}
	if !found {
		t.Fatalf("capped: expected med-dyn included, got %v", rCapped.Included)
	}
}

func TestStableCapDefaultNoCap(t *testing.T) {
	// Default (no WithStableCap) should behave identically to previous behavior.
	elems := []priompt.Element{
		{Name: "stable", Content: strings.Repeat("x", 100), Priority: 10, Stable: true},
		{Name: "dynamic", Content: "aaaa", Priority: 80},
	}
	r1 := priompt.Render(elems, 1000)
	r2 := priompt.Render(elems, 1000, priompt.WithStableCap(0))  // explicit 0 = no cap
	r3 := priompt.Render(elems, 1000, priompt.WithStableCap(1.0)) // 1.0 = no cap

	if r1.Prompt != r2.Prompt || r1.Prompt != r3.Prompt {
		t.Fatalf("default, 0, and 1.0 should produce same prompt")
	}
}

func TestRunningTokensConservative(t *testing.T) {
	// Running accumulation may slightly overestimate vs recounting the joined string,
	// because Count(A)+Count(sep)+Count(B) >= Count(A+sep+B) with integer division.
	// This is conservative (won't over-pack the budget).
	elems := makeElements(50)
	budget := 10000
	h := priompt.CharHeuristic{Ratio: 4}
	r := priompt.Render(elems, budget, priompt.WithPhase("execute"))
	recount := h.Count(r.Prompt)
	if r.TotalTokens < recount {
		t.Fatalf("running TotalTokens(%d) should be >= recount(%d)", r.TotalTokens, recount)
	}
	// Difference should be small (< 5% of budget).
	diff := r.TotalTokens - recount
	maxDiff := budget / 20
	if diff > maxDiff {
		t.Fatalf("running vs recount difference too large: %d (max %d)", diff, maxDiff)
	}
}
