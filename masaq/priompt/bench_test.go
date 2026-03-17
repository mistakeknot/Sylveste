package priompt_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/priompt"
)

// makeElements generates n elements with realistic characteristics:
// ~30% stable, mixed priorities, some with phase boosts, varied content sizes.
func makeElements(n int) []priompt.Element {
	elems := make([]priompt.Element, n)
	phases := []string{"brainstorm", "plan", "execute", "review", "ship"}
	for i := range elems {
		stable := i%3 == 0
		priority := 10 + (i*7)%90 // spread across 10-99
		// Content sizes: mix of small (100 chars), medium (500), large (2000)
		var contentSize int
		switch i % 3 {
		case 0:
			contentSize = 100
		case 1:
			contentSize = 500
		case 2:
			contentSize = 2000
		}
		content := strings.Repeat("x", contentSize)

		var boost map[string]int
		if i%4 == 0 {
			boost = map[string]int{phases[i%len(phases)]: 20 + i%30}
		}

		elems[i] = priompt.Element{
			Name:       fmt.Sprintf("elem-%03d", i),
			Content:    content,
			Priority:   priority,
			PhaseBoost: boost,
			Stable:     stable,
		}
	}
	return elems
}

// makeElementsWithDynamic generates elements where ~20% use ContentFunc.
func makeElementsWithDynamic(n int) []priompt.Element {
	elems := makeElements(n)
	for i := range elems {
		if i%5 == 0 {
			size := len(elems[i].Content)
			elems[i].Render = func(ctx priompt.RenderContext) string {
				if ctx.TurnCount > 10 {
					return strings.Repeat("y", size/2)
				}
				return strings.Repeat("y", size)
			}
			elems[i].Content = "" // ContentFunc takes precedence
		}
	}
	return elems
}

func BenchmarkRender20(b *testing.B) {
	elems := makeElements(20)
	budget := 5000
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		priompt.Render(elems, budget, priompt.WithPhase("execute"))
	}
}

func BenchmarkRender50(b *testing.B) {
	elems := makeElements(50)
	budget := 10000
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		priompt.Render(elems, budget, priompt.WithPhase("execute"))
	}
}

func BenchmarkRender100(b *testing.B) {
	elems := makeElements(100)
	budget := 20000
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		priompt.Render(elems, budget, priompt.WithPhase("execute"))
	}
}

func BenchmarkRender100TightBudget(b *testing.B) {
	elems := makeElements(100)
	budget := 2000 // forces many exclusions
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		priompt.Render(elems, budget, priompt.WithPhase("execute"))
	}
}

func BenchmarkRenderDynamic50(b *testing.B) {
	elems := makeElementsWithDynamic(50)
	budget := 10000
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		priompt.Render(elems, budget, priompt.WithPhase("plan"), priompt.WithTurnCount(5))
	}
}

func BenchmarkPackingEfficiency(b *testing.B) {
	elems := makeElements(100)
	budget := 2000 // tight budget to maximize exclusion pressure
	b.ReportAllocs()
	b.ResetTimer()
	var lastResult priompt.RenderResult
	for i := 0; i < b.N; i++ {
		lastResult = priompt.Render(elems, budget, priompt.WithPhase("execute"))
	}
	b.ReportMetric(lastResult.PackingEfficiency, "packing_eff")
	b.ReportMetric(float64(lastResult.WastedTokens), "wasted_tokens")
	b.ReportMetric(float64(lastResult.ExcludedPrioritySum), "excluded_pri_sum")
	b.ReportMetric(float64(len(lastResult.Included)), "included_count")
}

func BenchmarkCharHeuristic(b *testing.B) {
	h := priompt.CharHeuristic{Ratio: 4}
	text := strings.Repeat("The quick brown fox jumps. ", 100) // ~2600 chars
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		h.Count(text)
	}
}
