# SPEAR Prompt Algebra Assessment

**Assessed:** 2026-03-16
**Source:** arxiv.org/abs/2508.05012 (CIDR 2026)
**Authors:** Cetintemel et al. (Brown University)
**Skaffen context:** D9 (system prompt architecture), priompt priority rendering

---

## What It Is

SPEAR ("Structured Prompt Engineering with Algebraic Refinement") makes prompts
first-class citizens in LLM pipelines. Instead of treating prompts as opaque
strings, SPEAR defines a closed prompt algebra over a triple (P, C, M):

- **P** (Prompt Store): key-value store of named, versioned prompt fragments with
  refinement history (ref_log)
- **C** (Context): dynamic map of runtime data — tool results, extracted fields,
  intermediate outputs
- **M** (Metadata): control signals — confidence scores, latency, retry counts

Six operators manipulate this triple:

| Operator | Purpose |
|----------|---------|
| `RET[source]` | Retrieve data from external sources into context |
| `GEN[label]` | Invoke LLM with current prompt+context, store result |
| `REF[action, f]` | Apply transformation to construct/refine prompt entries |
| `CHECK[cond, f]` | Conditionally apply refinements based on metadata |
| `MERGE[P1, P2]` | Reconcile prompts from divergent execution branches |
| `DELEGATE[agent, payload]` | Offload subtasks to external agents |

The algebra is closed — each operator consumes and produces (P, C, M), enabling
arbitrary chaining. This gives you fusion optimization (merging adjacent
operators), prefix caching (stable prompt prefixes), and provenance tracking
(ref_log records every mutation to every prompt fragment).

### Three Refinement Modes

- **Manual:** developer writes REF operations directly
- **Assisted:** developer states intent, LLM generates the refinement function
- **Automatic:** system monitors M (confidence, latency) and triggers refinements
  based on learned patterns

### Evaluation Results

On Sentiment140 (1K samples):
- Static prompt: 0.70 F1 (baseline)
- Auto refinement: 0.81 F1 (+15.7%), 1.32x speedup, 80.6% cache hits
- Manual refinement: 0.75 F1 (+7.1%), 1.33x speedup, 96.8% cache hits

---

## Skaffen's Current System

Skaffen uses `masaq/priompt` — a ~225-line Go package that does priority-based
prompt composition within a token budget. The model:

```go
type Element struct {
    Name       string
    Content    string         // raw prompt text
    Priority   int            // higher = more important (0-100)
    PhaseBoost map[string]int // phase tag -> priority adjustment
    Stable     bool           // render first for cache prefix stability
}
```

At each turn, `Render(elements, budget, WithPhase(phase))`:
1. Splits elements into stable/dynamic partitions
2. Sorts each by effective priority (base + phase boost)
3. Greedy-packs stable first, then dynamic, until budget exhausted
4. Returns prompt string + included/excluded lists + token counts

Elements are static — constructed once at session creation, never mutated during
the session. The system has no runtime refinement, no provenance tracking, and
no conditional composition.

The agentloop calls `session.SystemPrompt(hints)` every turn, which re-renders
with the current budget (context window minus message tokens minus output
reserve). Phase changes shift effective priorities via PhaseBoost, but no
element content changes at runtime.

---

## Applicability Analysis

### Where SPEAR Concepts Map to Skaffen

**1. Named prompt store (P) — already have this, weaker form.**
Skaffen's `[]priompt.Element` is a flat list of named fragments. SPEAR's P is a
key-value store with versioning and ref_log. The naming overlap is superficial —
Skaffen elements are static strings; SPEAR fragments are mutable, tracked data.

**2. Phase-aware composition — already solved differently.**
SPEAR's `CHECK[M["phase"] == "build"]` is equivalent to Skaffen's PhaseBoost
mechanism, just expressed as conditional operators vs. priority arithmetic.
Skaffen's approach is simpler and works fine for the ~10-20 system prompt
sections that exist. Priority arithmetic is O(n) in the section count;
CHECK/REF chains add operator overhead for the same result.

**3. Automatic refinement — genuinely interesting, not applicable yet.**
SPEAR's auto-refinement monitors confidence scores and mutates prompts at
runtime. Skaffen doesn't have a prompt quality feedback loop today. The D9
brainstorm mentions a stage-3 calibration path ("collect which elements the
model actually uses, calibrate priorities from usage data"), but that's element
*priority* calibration, not content mutation. Auto-refinement of prompt
*content* requires:
- A quality signal per turn (confidence, outcome)
- A mutation policy (when to refine, how much to change)
- A rollback mechanism (if refinement hurts)

Skaffen's `mutations` package and `SignalStore` interface are the embryo of
this, but they operate on task-level quality signals, not prompt-level ones.

**4. MERGE operator — irrelevant.**
SPEAR's MERGE reconciles prompts from divergent execution branches (e.g.,
parallel pipeline stages). Skaffen is a single-threaded agent loop. No
divergent prompt branches exist.

**5. DELEGATE operator — already have this.**
Skaffen's MCP plugin system and tool dispatch already delegate subtasks.
DELEGATE adds nothing.

**6. Prefix caching — already solved.**
Skaffen's `Stable` flag and stable-first rendering was designed specifically for
Anthropic's prompt cache. SPEAR's ref_log-based approach to identifying cache
boundaries is more general but solves a problem Skaffen already handles with a
boolean flag.

**7. Prompt views — potentially useful, not urgent.**
SPEAR's "views" are reusable, parameterized prompt templates (like database
views). Skaffen could benefit from parameterized elements — e.g., a
`sprint-context` element that takes `{sprint_id, budget_remaining, phase}` as
parameters and renders differently. But this is template interpolation, which
Go's `text/template` or `fmt.Sprintf` already handles. No algebra needed.

**8. Provenance tracking (ref_log) — nice for debugging, not essential.**
Knowing "this prompt fragment was created by CREATE, then modified by
ASSISTED(add_detail), then AUTO(add_hint)" would help debug prompt drift. But
Skaffen's elements are static — there's no drift to debug yet. When/if runtime
prompt mutation is added, provenance should come with it, but not before.

### Where SPEAR Doesn't Fit

**Scale mismatch.** SPEAR is designed for LLM *pipelines* — multi-stage
workflows where prompts flow through RET -> GEN -> CHECK -> REF chains across
many LLM calls in a single request. Skaffen is a *loop* — one LLM call per
turn, tools in between. The pipeline algebra adds complexity without the
multi-stage pipeline to justify it.

**Abstraction cost.** The (P, C, M) triple and six operators are a formal
framework for reasoning about prompt manipulation. Skaffen has 226 lines of
prompt rendering code that does everything it needs. Adding algebraic operators
would increase surface area 3-5x for capabilities that aren't currently needed.

**Runtime mutation risk.** SPEAR's auto-refinement mutates prompts during
execution. For a coding agent, prompt stability matters — the agent needs
consistent instructions across a multi-turn editing session. Mutating the system
prompt between turns could cause behavioral inconsistency. The brainstorm's
stage-3 calibration approach (adjust priorities offline, not content at runtime)
is safer for this use case.

**Go vs. academic fit.** SPEAR's formal algebra maps naturally to Haskell-style
type composition or Rust traits. Go's type system doesn't reward algebraic
composition — you'd end up with interface proliferation and adapter boilerplate
that obscures rather than clarifies.

---

## What's Worth Stealing

Despite the verdict below, two SPEAR ideas are worth absorbing into Skaffen's
existing architecture without adopting the framework:

**1. Element content as a function, not a string.**

Currently: `Element.Content string` is set at session creation.
Better: `Element.ContentFunc func(ctx RenderContext) string` that receives
phase, budget hints, and runtime state. This enables parameterized elements
without the full algebra:

```go
type Element struct {
    Name        string
    Content     string                        // static content (used if ContentFunc nil)
    ContentFunc func(ctx RenderContext) string // dynamic content (takes precedence)
    Priority    int
    PhaseBoost  map[string]int
    Stable      bool
}

type RenderContext struct {
    Phase       string
    Budget      int
    Model       string
    TurnNumber  int
    // extensible via context.Context if needed
}
```

This is ~20 lines of change to `masaq/priompt/priompt.go`. No algebra, no
operators, but it unlocks the core value of SPEAR's dynamic fragments: prompt
content that adapts to runtime state.

**2. Excluded-element feedback for priority calibration.**

Skaffen already tracks `ExcludedElements` and `ExcludedStable` in evidence. The
next step (D9 stage 3) is closing the loop: if an element is consistently
excluded AND the agent's outcome quality doesn't suffer, lower its priority. If
an element is excluded AND quality drops, raise it. This is SPEAR's
auto-refinement applied to *priorities* rather than *content* — safer for a
coding agent and achievable within the existing architecture.

---

## Verdict: inspire-only

**Why not adopt/port:** SPEAR solves a pipeline composition problem that
Skaffen doesn't have. Skaffen's prompt rendering is a single-stage knapsack
packer, not a multi-stage pipeline. The ~226-line priompt package is adequate
for the current element count (~10-20 sections), and the complexity cost of a
full algebra would not pay off.

**Why not skip entirely:** The dynamic content idea (ContentFunc) and priority
calibration feedback loop are directly useful and can be implemented within the
existing priompt architecture without any algebraic framework. These are the
practical gems inside the academic wrapper.

**Concrete next steps:**
1. Add `ContentFunc` to `priompt.Element` (~20 lines, backward compatible)
2. Build priority calibration into the reflect/compound phases using existing
   evidence data (ExcludedElements + outcome quality signals)
3. Revisit if Skaffen adds multi-stage prompt pipelines (e.g., RAG retrieval ->
   prompt construction -> refinement), at which point SPEAR's operator model
   would become relevant

The current priority-based system works. Make it dynamic where needed; don't
algebraicize it.
