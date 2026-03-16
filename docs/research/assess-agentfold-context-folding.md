# AgentFold (Learned Context Folding) Assessment

**Assessed:** 2026-03-16
**Source:** arxiv.org/abs/2510.24699 (AgentFold), arxiv.org/abs/2510.11967 (FoldAgent)
**Venue:** ICLR 2026 Poster
**Referenced from:** docs/brainstorms/2026-03-10-skaffen-sovereign-agent-brainstorm.md (D10, research bead #3)

---

## What It Is

AgentFold is a context management paradigm for long-horizon LLM agents. Instead of
treating the conversation history as a passive, ever-growing log, AgentFold trains the
model to actively "fold" its context at each step -- producing multi-scale summaries
that replace raw history. Two fold granularities:

- **Granular condensation** (k=t-1): Fold only the latest interaction into a fine-grained
  summary. Used for incremental progress within a subtask.
- **Deep consolidation** (k<t-1): Fuse multiple prior summary blocks into a single
  coarse summary. Used when a subtask completes and details can be abstracted away.

Each step the model produces a structured quadruplet: (thinking, folding_directive,
explanation, action). The folding directive is a JSON object `{"range": [k, t-1],
"summary": "..."}` that retracts summary blocks in the given range and replaces them
with the new summary.

**Key result:** AgentFold-30B-A3B (Qwen3 MoE, 3B active params) achieves 36.2% on
BrowseComp, beating DeepSeek-V3.1-671B (30.0%) and matching proprietary agents like
o4-mini. Context stays ~7k tokens after 100 turns vs. linear/exponential growth in
ReAct agents.

### Related Work in the Folding Family

| Paper | Training | Key difference |
|-------|----------|----------------|
| **AgentFold** (2510.24699) | SFT on Qwen3-30B-A3B | Proactive multi-scale folding via structured output |
| **FoldAgent** (2510.11967) | RL (FoldGRPO) on Qwen3-8B | Branch-and-fold subtask decomposition, RL rewards |
| **FoldAct** (2512.22733) | RL with separated losses | Training efficiency (5x speedup), gradient signal fixes |
| **U-Fold** (2601.18285) | SFT + intent-aware | User-centric, dynamic intent tracking |

All four require model training. None is a prompting-only technique.

---

## How It Works (Technical Detail)

### Context Structure

At step t, the agent's context contains:
1. **Multi-Scale State Summaries** (S_{t-1}): A list of folded blocks, each covering
   a step range with a summary string. This is the compressed history.
2. **Latest Interaction**: Full raw record of step t-1 (observation + action).

The model sees summaries + the last raw step, then decides how to fold before acting.

### Training Pipeline

1. **Fold-Generator**: A data collection pipeline using a strong LLM to generate
   trajectories that demonstrate interleaved action and context curation.
   Produces (context, response) pairs where responses include folding directives.
2. **Rejection Sampling**: Discard any step that fails structured format validation
   or contains too many environment errors. This filters for high-quality trajectories.
3. **Supervised Fine-Tuning**: Train on validated trajectories using standard SFT
   on Qwen3-30B-A3B-Instruct. No RL, no continual pre-training.

### Critical Limitation (for Skaffen)

The paper explicitly states:

> "We find that even the most advanced LLMs cannot reliably produce AgentFold's
> accurate, structured, multi-part responses through prompt engineering alone."

This is the core finding: the folding behavior must be distilled into model weights.
Prompting alone produces unreliable fold directives -- the model either folds too
aggressively (losing critical details) or too conservatively (defeating the purpose).

---

## Skaffen Applicability

### Current Skaffen Context Management

Skaffen's `session.go` implements a two-tier approach:

1. **Truncation** (`truncate()`): When messages exceed `maxTurns * 2`, keep the first
   message (context anchor) + the last N messages. Simple sliding window.
2. **Compaction** (`Compact(summary, keepRecent)`): Replace all messages except the
   last `keepRecent` with a single summary message. The summary is generated externally
   (by the LLM or a compaction prompt).
3. **Priority rendering** (`PriomptSession`): Priompt-style budget-aware prompt
   assembly. Sections have priorities; low-priority sections are excluded when the
   token budget is tight.

The brainstorm (D8) describes the target: hybrid compaction with structured summaries
at phase boundaries and reactive compaction mid-phase. D10 envisions git-context tools
(commit/retrieve/anchor/fold) that the agent calls explicitly.

### What AgentFold Would Require

To adopt AgentFold's learned folding, Skaffen would need to:

1. **Fine-tune a model** (e.g., Qwen3-30B-A3B) on coding-agent folding trajectories.
   This means generating training data via Fold-Generator adapted for code tasks,
   running rejection sampling, and SFT training.
2. **Host the fine-tuned model** or serve it via an inference provider that supports
   custom models (not standard Claude/GPT APIs).
3. **Modify the agent loop** to parse the structured quadruplet output format
   (thinking + fold directive + explanation + action) on every turn.

**This is a non-starter.** Skaffen's architecture is built around API-based providers
(Anthropic, OpenAI, Gemini). Fine-tuning a custom model for context folding contradicts
the design principle of using best-available frontier models via standard APIs.

### What IS Portable

Despite the core technique requiring training, several ideas from AgentFold transfer
as design patterns for Skaffen's existing compaction system:

1. **Multi-scale summary structure.** Instead of a single flat summary, maintain
   a list of summary blocks at different granularities -- recent steps get fine-grained
   summaries, older steps get coarse ones. Skaffen's `Compact()` currently produces
   one monolithic summary. Replacing this with a tiered structure is straightforward.

2. **Explicit fold-range tracking.** AgentFold tracks which step ranges each summary
   covers. Skaffen could track which turn ranges each compaction summary covers,
   enabling selective re-expansion if the agent needs to revisit a specific phase.

3. **Phase-boundary deep consolidation.** AgentFold's deep consolidation maps
   directly to Skaffen's existing D8 design (structured summaries at phase boundaries).
   The insight is that OODARC phase transitions are natural fold points -- Orient
   findings fold into a compact hypothesis, Act tool results fold into a diff summary.

4. **Context budget as first-class metric.** AgentFold's ~7k token steady state is
   a concrete target. Skaffen could measure and enforce a context budget ceiling,
   triggering compaction proactively rather than reactively.

5. **Compaction prompt engineering.** While AgentFold's folding is learned, the
   Fold-Generator's trajectory format provides a template for Skaffen's compaction
   prompts. Structure the compaction request to produce granular vs. deep summaries
   based on recency, rather than asking for a single "summarize everything" output.

---

## Verdict: inspire-only

AgentFold's core contribution -- learned multi-scale folding via SFT -- requires
fine-tuning a custom model. This is incompatible with Skaffen's API-provider
architecture. The paper explicitly confirms that prompting alone cannot replicate
the technique reliably.

However, the conceptual framework is valuable:

- **Multi-scale summary blocks** (not monolithic compaction) -- portable as a data
  structure change in `session.go`
- **Phase-aligned consolidation** -- already planned in D8, reinforced by AgentFold
- **Context budget targeting** (~7k steady state) -- a measurable goal for Skaffen
- **Structured compaction prompts** (granular vs. deep) -- achievable via prompt
  engineering on Claude/GPT, even if less reliable than trained models

### Comparison to Other D10 Research Beads

| Technique | Skaffen fit | Why |
|-----------|-------------|-----|
| AgentFold (this) | inspire-only | Requires SFT on custom model |
| SimpleMem (entropy-aware) | port-partially | Entropy scoring works as a preprocessing step on any model |
| RLMs (code-managed context) | inspire-only | Requires model that writes/executes context management code |
| MAGMA (multi-graph retrieval) | port-partially | Graph construction is model-agnostic; retrieval works with any LLM |

---

## Practical Recommendations

1. **Upgrade `Compact()` to multi-scale.** Replace the single summary with a list
   of `SummaryBlock{Range [2]int; Granularity string; Text string}`. Recent blocks
   are "granular" (per-turn detail), older blocks are "deep" (phase-level abstract).
   Estimated effort: ~50 lines in `session.go`.

2. **Add structured compaction prompts.** When triggering compaction, use two prompt
   templates: one for granular (preserve tool names, file paths, error messages) and
   one for deep (preserve only goals, decisions, and artifacts). Select based on
   recency of the messages being compacted.

3. **Enforce a context budget ceiling.** Target 8k tokens of history context
   (excluding system prompt and latest turn). Trigger proactive compaction at 80%
   of budget. Measure actual token usage per turn in the evidence pipeline.

4. **Wire phase transitions as fold points.** When OODARC transitions (e.g.,
   Orient -> Decide), automatically trigger deep consolidation of the completed
   phase. This is already designed in D8 but not yet implemented in the Go code.

5. **Revisit if Skaffen adds a local model backend.** If Skaffen ever supports
   local inference (e.g., via Ollama or vLLM), AgentFold-style SFT on a small MoE
   model becomes viable for the folding component specifically, while keeping
   frontier models for the main reasoning. This would be a "folding co-processor"
   pattern.

---

## Sources

- [AgentFold paper (arxiv.org/abs/2510.24699)](https://arxiv.org/abs/2510.24699)
- [AgentFold HTML (arxiv.org/html/2510.24699v1)](https://arxiv.org/html/2510.24699v1)
- [FoldAgent paper (arxiv.org/abs/2510.11967)](https://arxiv.org/abs/2510.11967)
- [FoldAgent GitHub (github.com/sunnweiwei/FoldAgent)](https://github.com/sunnweiwei/FoldAgent)
- [FoldAct paper (arxiv.org/abs/2512.22733)](https://arxiv.org/abs/2512.22733)
- [U-Fold paper (arxiv.org/abs/2601.18285)](https://arxiv.org/abs/2601.18285)
- [AgentFold OpenReview (ICLR 2026 Poster)](https://openreview.net/forum?id=IuZoTgsUws)
- [FoldAgent OpenReview](https://openreview.net/forum?id=JaLXQnA2wi)
