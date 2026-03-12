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

// Element is a prompt section with priority metadata.
type Element struct {
	Name       string         // identifier for debugging/metrics
	Content    string         // the actual prompt text
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
	tokenizer Tokenizer
	separator string
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

// WithSeparator sets the string inserted between adjacent included elements.
// Default is "\n\n".
func WithSeparator(sep string) Option {
	return func(c *renderConfig) {
		c.separator = sep
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

	// Filter out empty content elements.
	var filtered []Element
	for _, e := range elements {
		if e.Content != "" {
			filtered = append(filtered, e)
		}
	}

	if len(filtered) == 0 {
		return RenderResult{}
	}

	// Compute effective priorities.
	type scored struct {
		elem     Element
		effPri   int
	}
	var stable, dynamic []scored
	for _, e := range filtered {
		eff := e.Priority
		if cfg.phase != "" {
			eff += e.PhaseBoost[cfg.phase]
		}
		s := scored{elem: e, effPri: eff}
		if e.Stable {
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
			return ss[i].elem.Name < ss[j].elem.Name
		})
	}
	sortScored(stable)
	sortScored(dynamic)

	// Handle budget <= 0: everything excluded.
	if budget <= 0 {
		var result RenderResult
		for _, s := range stable {
			result.ExcludedStable = append(result.ExcludedStable, s.elem.Name)
		}
		for _, s := range dynamic {
			result.Excluded = append(result.Excluded, s.elem.Name)
		}
		return result
	}

	// Greedy pack: stable first, then dynamic.
	remaining := budget
	var included []string
	var includedContents []string
	var stableContents []string
	var excluded []string
	var excludedStable []string
	anyStableExcluded := false

	sepCost := 0
	if cfg.separator != "" {
		sepCost = cfg.tokenizer.Count(cfg.separator)
		if sepCost < 1 {
			sepCost = 1
		}
	}

	pack := func(items []scored, isStable bool) {
		for _, s := range items {
			tokenCost := cfg.tokenizer.Count(s.elem.Content)
			thisSepCost := 0
			if len(included) > 0 {
				thisSepCost = sepCost
			}

			if tokenCost+thisSepCost <= remaining {
				remaining -= tokenCost + thisSepCost
				included = append(included, s.elem.Name)
				includedContents = append(includedContents, s.elem.Content)
				if isStable {
					stableContents = append(stableContents, s.elem.Content)
				}
			} else {
				if isStable {
					excludedStable = append(excludedStable, s.elem.Name)
					anyStableExcluded = true
				} else {
					excluded = append(excluded, s.elem.Name)
				}
			}
		}
	}

	pack(stable, true)
	pack(dynamic, false)

	// Build prompt.
	prompt := strings.Join(includedContents, cfg.separator)

	// Compute StableTokens.
	stableTokens := 0
	if !anyStableExcluded && len(stableContents) > 0 {
		stableTokens = cfg.tokenizer.Count(strings.Join(stableContents, cfg.separator))
	}

	return RenderResult{
		Prompt:         prompt,
		Included:       included,
		Excluded:       excluded,
		ExcludedStable: excludedStable,
		TotalTokens:    cfg.tokenizer.Count(prompt),
		StableTokens:   stableTokens,
	}
}
