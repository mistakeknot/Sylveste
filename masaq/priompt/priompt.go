// Package priompt provides priority-based prompt composition within a token
// budget. Elements are sorted by effective priority (with optional phase boosts)
// and greedily packed until the budget is exhausted. Cache-aware ordering
// ensures stable elements form a consistent prefix for Anthropic prompt cache
// hits.
//
// Elements are expected to be system-prompt-level sections (~10-20), not
// per-message content. Element names must be unique within a Render call.
package priompt

import (
	"sort"
	"strings"
)

// RenderContext provides dynamic rendering context to ContentFunc.
type RenderContext struct {
	Phase     string
	Model     string
	TurnCount int
	Budget    int
}

// ContentFunc generates element content dynamically per render cycle.
// When set on an Element, it is called instead of using the static Content field.
// If it returns an empty string, the element is excluded from the render.
type ContentFunc func(ctx RenderContext) string

// Element is a prompt section with priority metadata.
type Element struct {
	Name       string         // identifier for debugging/metrics
	Content    string         // the actual prompt text (used when Render is nil)
	Render     ContentFunc    // optional dynamic content generator (takes precedence over Content)
	Priority   int            // higher = more important (0-100 suggested range)
	PhaseBoost map[string]int // phase tag → priority adjustment
	Stable     bool           // render first for cache prefix stability
}

// Tokenizer estimates token count for a string.
// Count must return a non-negative integer. Count("") must return 0.
type Tokenizer interface {
	Count(s string) int
}

// CharHeuristic estimates tokens using a character-to-token ratio.
// A Ratio of 4 means roughly 4 characters per token (~85% accuracy).
// If Ratio is <= 0, the default ratio of 4 is used.
type CharHeuristic struct {
	Ratio int
}

// Count returns the estimated token count for s.
func (h CharHeuristic) Count(s string) int {
	if len(s) == 0 {
		return 0
	}
	r := h.Ratio
	if r <= 0 {
		r = 4
	}
	n := len(s) / r
	if n < 1 {
		n = 1
	}
	return n
}

// Option configures a Render call.
type Option func(*renderConfig)

type renderConfig struct {
	phase     string
	model     string
	turnCount int
	tokenizer Tokenizer
	separator string
	stableCap float64 // max fraction of budget for stable elements (0 = no cap, 1.0 = no cap)
}

// WithPhase activates phase boosts for the given tag.
// An empty string or omitting this option means phase boosts are inert.
func WithPhase(tag string) Option {
	return func(c *renderConfig) {
		c.phase = tag
	}
}

// WithTokenizer overrides the default CharHeuristic{Ratio: 4} tokenizer.
func WithTokenizer(t Tokenizer) Option {
	return func(c *renderConfig) {
		c.tokenizer = t
	}
}

// WithModel sets the model name for RenderContext.
func WithModel(model string) Option {
	return func(c *renderConfig) {
		c.model = model
	}
}

// WithTurnCount sets the turn count for RenderContext.
func WithTurnCount(n int) Option {
	return func(c *renderConfig) {
		c.turnCount = n
	}
}

// WithSeparator sets the string inserted between adjacent included elements.
// Default is "\n\n".
func WithSeparator(sep string) Option {
	return func(c *renderConfig) {
		c.separator = sep
	}
}

// WithStableCap limits stable elements to at most pct fraction of the budget.
// Stable elements that exceed this cap are demoted to the dynamic queue.
// A value of 0 or 1.0 means no cap (default behavior).
func WithStableCap(pct float64) Option {
	return func(c *renderConfig) {
		c.stableCap = pct
	}
}

// RenderResult contains the rendered prompt and metadata.
type RenderResult struct {
	Prompt        string   // concatenated prompt text
	Included      []string // names of included elements
	Excluded      []string // names of excluded dynamic elements (over budget)
	ExcludedStable []string // names of excluded stable elements (higher severity)
	TotalTokens   int      // estimated token count of rendered prompt
	StableTokens  int      // token count of stable prefix (0 if any stable element dropped)

	PackingEfficiency   float64 // TotalTokens / budget (0 if budget <= 0)
	WastedTokens        int     // budget - TotalTokens (0 if fully packed or budget <= 0)
	ExcludedPrioritySum int     // sum of effective priorities of all excluded elements
}

// scored holds an index into the resolved element slice plus effective priority.
// Using an index avoids copying the Element struct (which contains strings and maps).
type scored struct {
	idx    int // index into resolved slice
	effPri int
}

// Render assembles elements into a prompt within the token budget.
// Elements with empty Content are silently skipped.
func Render(elements []Element, budget int, opts ...Option) RenderResult {
	cfg := renderConfig{
		separator: "\n\n",
		tokenizer: CharHeuristic{Ratio: 4},
	}
	for _, o := range opts {
		o(&cfg)
	}

	// Resolve dynamic content and filter out empty elements.
	// We rewrite elements in-place into a "resolved" slice to avoid copying.
	rctx := RenderContext{
		Phase:     cfg.phase,
		Model:     cfg.model,
		TurnCount: cfg.turnCount,
		Budget:    budget,
	}

	// Pre-allocate resolved slice at input capacity.
	resolved := make([]Element, 0, len(elements))
	for i := range elements {
		e := &elements[i]
		content := e.Content
		if e.Render != nil {
			content = e.Render(rctx)
		}
		if content != "" {
			resolved = append(resolved, Element{
				Name:       e.Name,
				Content:    content,
				Priority:   e.Priority,
				PhaseBoost: e.PhaseBoost,
				Stable:     e.Stable,
			})
		}
	}

	n := len(resolved)
	if n == 0 {
		return RenderResult{}
	}

	// Partition into stable/dynamic using indices, pre-allocated.
	stable := make([]scored, 0, n)
	dynamic := make([]scored, 0, n)
	for i := range resolved {
		eff := resolved[i].Priority
		if cfg.phase != "" {
			eff += resolved[i].PhaseBoost[cfg.phase]
		}
		s := scored{idx: i, effPri: eff}
		if resolved[i].Stable {
			stable = append(stable, s)
		} else {
			dynamic = append(dynamic, s)
		}
	}

	// Sort each partition: effective priority descending, then Name ascending.
	sortScored := func(ss []scored) {
		sort.Slice(ss, func(i, j int) bool {
			if ss[i].effPri != ss[j].effPri {
				return ss[i].effPri > ss[j].effPri
			}
			return resolved[ss[i].idx].Name < resolved[ss[j].idx].Name
		})
	}
	sortScored(stable)
	sortScored(dynamic)

	// Handle budget <= 0: everything excluded.
	if budget <= 0 {
		var result RenderResult
		for _, s := range stable {
			result.ExcludedStable = append(result.ExcludedStable, resolved[s.idx].Name)
			result.ExcludedPrioritySum += s.effPri
		}
		for _, s := range dynamic {
			result.Excluded = append(result.Excluded, resolved[s.idx].Name)
			result.ExcludedPrioritySum += s.effPri
		}
		return result
	}

	// Greedy pack: stable first, then dynamic.
	remaining := budget
	runningTokens := 0
	stableRunningTokens := 0
	excludedPrioritySum := 0
	anyStableExcluded := false

	// Pre-allocate output slices.
	included := make([]string, 0, n)
	includedContents := make([]string, 0, n)

	type excludedItem struct {
		idx       int // index into resolved
		tokenCost int
		effPri    int
		isStable  bool
	}
	var excludedItems []excludedItem

	sepCost := 0
	if cfg.separator != "" {
		sepCost = cfg.tokenizer.Count(cfg.separator)
		if sepCost < 1 {
			sepCost = 1
		}
	}

	pack := func(items []scored, isStable bool) {
		for _, s := range items {
			content := resolved[s.idx].Content
			tokenCost := cfg.tokenizer.Count(content)
			thisSepCost := 0
			if len(included) > 0 {
				thisSepCost = sepCost
			}

			if tokenCost+thisSepCost <= remaining {
				remaining -= tokenCost + thisSepCost
				runningTokens += tokenCost + thisSepCost
				included = append(included, resolved[s.idx].Name)
				includedContents = append(includedContents, content)
				if isStable {
					stableRunningTokens += tokenCost + thisSepCost
				}
			} else {
				excludedItems = append(excludedItems, excludedItem{
					idx:       s.idx,
					tokenCost: tokenCost,
					effPri:    s.effPri,
					isStable:  isStable,
				})
				if isStable {
					anyStableExcluded = true
				}
			}
		}
	}

	// Apply stable cap: demote stable elements that exceed the stable budget.
	if cfg.stableCap > 0 && cfg.stableCap < 1.0 {
		stableBudget := int(float64(budget) * cfg.stableCap)
		stableSpent := 0
		kept := 0
		for i, s := range stable {
			tokenCost := cfg.tokenizer.Count(resolved[s.idx].Content)
			thisSepCost := 0
			if kept > 0 {
				thisSepCost = sepCost
			}
			if stableSpent+tokenCost+thisSepCost <= stableBudget {
				stableSpent += tokenCost + thisSepCost
				stable[kept] = stable[i]
				kept++
			} else {
				dynamic = append(dynamic, s)
			}
		}
		stable = stable[:kept]
		sortScored(dynamic)
	}

	pack(stable, true)
	pack(dynamic, false)

	// Fill pass: try excluded elements smallest-first to recover wasted budget.
	if remaining > 0 && len(excludedItems) > 0 {
		sort.Slice(excludedItems, func(i, j int) bool {
			return excludedItems[i].tokenCost < excludedItems[j].tokenCost
		})
		kept := 0
		for _, ex := range excludedItems {
			thisSepCost := 0
			if len(included) > 0 {
				thisSepCost = sepCost
			}
			if ex.tokenCost+thisSepCost <= remaining {
				remaining -= ex.tokenCost + thisSepCost
				runningTokens += ex.tokenCost + thisSepCost
				included = append(included, resolved[ex.idx].Name)
				includedContents = append(includedContents, resolved[ex.idx].Content)
			} else {
				excludedItems[kept] = ex
				kept++
			}
		}
		excludedItems = excludedItems[:kept]
	}

	// Build final excluded lists from remaining excluded items.
	var excluded []string
	var excludedStable []string
	for _, ex := range excludedItems {
		excludedPrioritySum += ex.effPri
		if ex.isStable {
			excludedStable = append(excludedStable, resolved[ex.idx].Name)
		} else {
			excluded = append(excluded, resolved[ex.idx].Name)
		}
	}

	// Build prompt.
	prompt := strings.Join(includedContents, cfg.separator)

	// Compute StableTokens from running sum (avoids re-joining and re-counting).
	stableTokens := 0
	if !anyStableExcluded && stableRunningTokens > 0 {
		stableTokens = stableRunningTokens
	}

	// Packing efficiency.
	var packingEfficiency float64
	wastedTokens := 0
	if budget > 0 {
		packingEfficiency = float64(runningTokens) / float64(budget)
		if packingEfficiency > 1.0 {
			packingEfficiency = 1.0
		}
		wastedTokens = budget - runningTokens
		if wastedTokens < 0 {
			wastedTokens = 0
		}
	}

	return RenderResult{
		Prompt:              prompt,
		Included:            included,
		Excluded:            excluded,
		ExcludedStable:      excludedStable,
		TotalTokens:         runningTokens,
		StableTokens:        stableTokens,
		PackingEfficiency:   packingEfficiency,
		WastedTokens:        wastedTokens,
		ExcludedPrioritySum: excludedPrioritySum,
	}
}
