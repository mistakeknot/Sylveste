# Model Routing Calibration Review

Reviewer focus: Whether Skaffen's per-turn model routing (Opus/Sonnet/Haiku by complexity tier) is correctly calibrated for SWE-bench task structure.

## Finding 1: Complexity Classifier Uses Only Token Count (Critical)

**File:** `os/Skaffen/internal/router/complexity.go:27-39`

The `Classify` method uses raw input token count as the sole proxy for reasoning difficulty:

```go
func (cc *ComplexityClassifier) Classify(inputTokens int) int {
    switch {
    case inputTokens < 300:  return 1
    case inputTokens < 800:  return 2
    case inputTokens < 2000: return 3
    case inputTokens < 4000: return 4
    default:                 return 5
    }
}
```

Token count is a poor proxy for reasoning difficulty. On SWE-bench Lite, the issue description for a hard multi-file refactor might be 200 tokens (C1 = "trivial"), while a verbose but straightforward logging change might be 5000 tokens (C5 = "complex"). The correlation between input length and required reasoning depth is near-zero for SWE-bench tasks. In enforce mode, this would demote a hard 200-token problem to Haiku while keeping a verbose easy problem on Opus.

**Recommendation:** Replace token-count heuristic with features that actually correlate with coding difficulty:
- Number of files touched in the conversation so far (multi-file > single-file)
- Tool call density in recent turns (high tool use = complex exploration)
- Error rate in recent tool results (retries signal difficulty)
- Phase context (Orient/Reflect naturally need more reasoning than Act)
- If staying heuristic-based, at minimum use conversation-accumulated tokens (not single-turn input) and weight output tokens higher (output-heavy turns indicate complex reasoning)

**Severity:** Critical for SWE-bench. If complexity enforcement is ever enabled, it will misroute the majority of tasks.

---

## Finding 2: All Phase Defaults Are Opus (Correct for SWE-bench, Wasteful for Production)

**File:** `os/Skaffen/internal/router/router.go:20-27`

```go
var phaseDefaults = map[tool.Phase]string{
    tool.PhaseObserve:  ModelOpus,
    tool.PhaseOrient:   ModelOpus,
    tool.PhaseDecide:   ModelOpus,
    tool.PhaseAct:      ModelOpus,
    tool.PhaseReflect:  ModelOpus,
    tool.PhaseCompound: ModelOpus,
}
```

Every OODARC phase defaults to Opus. This is correct for SWE-bench where pass rate is the only metric, but it means the routing infrastructure is effectively a no-op: the complexity classifier, phase defaults, and budget tracker all exist but produce the same result (Opus) unless explicitly overridden.

**Assessment:** For the SWE-bench pilot, this is the right default. The 1/10 pass rate problem is not caused by model selection -- it's caused by task understanding, patch quality, or test validation. Introducing Sonnet/Haiku routing before achieving >40% with all-Opus would add confounding variables.

**Recommendation:** Keep all-Opus for SWE-bench until pass rate exceeds 40%. Then introduce per-phase differentiation:
- Orient/Reflect: Opus (reasoning-heavy)
- Decide: Sonnet (structured decision, lower creativity needed)
- Act: Opus for edits, Sonnet for reads (within-phase granularity, see Finding 5)
- Compound: Sonnet (summarization, not novel reasoning)

---

## Finding 3: Complexity Shadow Mode Means Routing Is a No-Op (By Design, But Invisible)

**File:** `os/Skaffen/internal/router/complexity.go:59-63`

```go
if cc.mode == "shadow" {
    override.Applied = false
    return model, reason, override
}
```

Default complexity mode is `"shadow"` (`complexity.go:19`), meaning the classifier logs what it *would* change but never applies overrides. Combined with all-Opus phase defaults, the entire routing pipeline is a pass-through: every turn gets Opus regardless of complexity tier.

The shadow data *is* being recorded via `buildDecisionRecord` and sent to Intercore (`router.go:124-126`), which is valuable for future calibration. However, there is no mechanism to analyze this shadow data or trigger an alert when the classifier's recommendations diverge significantly from actual routing.

**Recommendation:**
1. Add a shadow mode analysis tool that reads Intercore routing decisions and reports: "In the last N sessions, complexity would have demoted X% of turns from Opus to Haiku" -- this tells you whether the classifier is even plausible before enabling enforce mode.
2. Add a `"shadow-warn"` mode that logs a warning to stderr when the classifier disagrees with the actual model, so operators notice the gap during development.

---

## Finding 4: Budget Demotion Is a Binary Cliff with No Phase Awareness (Critical)

**File:** `os/Skaffen/internal/router/budget.go:65-91`

```go
func (bt *BudgetTracker) MaybeDegrade(model, reason string) (string, string) {
    // ...
    default: // "graceful"
        if pct >= 1.0 {
            return ModelHaiku, "budget-exceeded"
        }
        if pct >= bt.degradeAt {
            return ModelHaiku, "budget-degrade"
        }
        return model, reason
}
```

When budget hits 80% (default `degradeAt`), the system jumps directly from Opus to Haiku with no intermediate Sonnet step. For SWE-bench, this is a trajectory-killer: if the agent has spent 80% of budget in Orient/Act building understanding and a partial patch, the sudden drop to Haiku in mid-repair means:

1. **Context comprehension loss:** Haiku cannot follow the reasoning chain built by Opus across prior turns.
2. **No graceful degradation path:** There's no Opus -> Sonnet -> Haiku cascade. The fallback chain exists (`router.go:16`) but is never used by the budget tracker.
3. **Phase-blind:** Budget demotion doesn't know whether it's interrupting a critical Reflect phase (where Opus matters most for self-correction) or a simple file read in Act (where Haiku would be fine).

**Recommendation:**
1. Implement stepped degradation: 80% -> Sonnet, 95% -> Haiku, 100% -> hard-stop or Haiku.
2. Add phase-aware budget policy: never demote during Reflect phase (self-correction is the highest-leverage use of remaining budget). Allow demotion in Act phase for tool-execution turns that are primarily reading.
3. For SWE-bench specifically, use `"advisory"` mode (never demote) or set budget high enough to never trigger -- demotion mid-task is worse than running over budget.

---

## Finding 5: No Within-Phase Routing Granularity (Moderate)

**File:** `os/Skaffen/internal/agentloop/loop.go:115`

```go
model, modelReason := l.router.SelectModel(config.Hints)
```

Model selection happens once per turn, using only the phase as context. Within a single OODARC phase (especially Act, which can run for dozens of turns), the agent alternates between very different cognitive tasks:

- **Reading files** (grep, read tool): Low reasoning, could use Sonnet
- **Forming hypotheses** (text output analyzing what was read): High reasoning, needs Opus
- **Writing patches** (edit tool): High reasoning + precision, needs Opus
- **Running tests** (bash tool): Low reasoning, could use Sonnet

The `SelectionHints` struct already has `Urgency` and `TaskType` fields (`types.go:13-16`) but they're never populated by the agent layer -- the `routerAdapter` in `agent.go:276-278` discards the hints entirely:

```go
func (ra *routerAdapter) SelectModel(_ agentloop.SelectionHints) (string, string) {
    return ra.inner.SelectModel(ra.phase())
}
```

**Recommendation:**
1. In the agentloop, set `TaskType` based on the previous turn's stop reason: if the last turn was `tool_use` with read-only tools, set `TaskType = "analysis"`; if edit/write, set `TaskType = "code"`.
2. In the router, use `TaskType` to optionally demote read-heavy turns to Sonnet when not in all-Opus mode.
3. For SWE-bench: defer this optimization until after the all-Opus baseline is established. Within-phase routing adds complexity for marginal cost savings.

---

## Finding 6: SetInputTokens Is Never Called from Production Code (Critical Bug)

**File:** `os/Skaffen/internal/router/router.go:152-155` (definition)

```go
func (r *DefaultRouter) SetInputTokens(n int) {
    r.inputTokens = n
}
```

Grep confirms `SetInputTokens` is called only from test files (`router_test.go`, `integration_test.go`). It is never called from `agentloop/loop.go`, `agent/agent.go`, or `cmd/skaffen/main.go`. This means:

- `r.inputTokens` is always `0` in production
- `Classify(0)` always returns tier 1 (C1, the "trivial" tier)
- In shadow mode, every turn logs `complexity_tier: 1` regardless of actual input size
- In enforce mode, every turn would be demoted to Haiku (since C1 <= 2 triggers demotion)
- **The shadow data being recorded to Intercore is garbage** -- it always shows C1

The agentloop *does* compute `estimateMessageTokens(messages)` at line 121, but this value is used only for prompt budget computation, never fed back to the router.

**Recommendation:** In `agentloop/loop.go`, after computing `msgTokens` (line 121), call `l.router.SetInputTokens(msgTokens)` before `l.router.SelectModel()`. This requires either:
- Adding `SetInputTokens(n int)` to the `agentloop.Router` interface, or
- Using a type assertion to `*router.DefaultRouter` (less clean but avoids interface change), or
- Passing token count through `SelectionHints` (cleanest -- add a `TokenCount int` field)

The `SelectionHints` approach is recommended since the hints struct already exists for this purpose:

```go
type SelectionHints struct {
    Phase      string
    Urgency    string
    TaskType   string
    TokenCount int  // <-- add this
}
```

---

## Finding 7: Context Window Values Are Identical Across All Models (Minor)

**File:** `os/Skaffen/internal/router/router.go:190-194`

```go
var defaultContextWindows = map[string]int{
    ModelOpus:   200000,
    ModelSonnet: 200000,
    ModelHaiku:  200000,
}
```

All three models are listed with 200K context windows. While this is currently accurate for Claude 4 family models, it means:
- There is no context window mismatch risk on model demotion (a non-issue today)
- The fallback of `200000` for unknown models (`router.go:208`) is also safe

However, if future models have different context sizes, budget demotion could fail silently: the agent builds a 180K-token conversation on Opus, gets demoted to a model with a smaller window, and the provider silently truncates or errors.

**Recommendation:** When `MaybeDegrade` selects a different model, validate that the new model's context window can accommodate the current conversation size. If not, skip that degradation step or emit a warning. This is a minor defensive measure -- not needed for SWE-bench today.

---

## Finding 8: routerAdapter Discards SelectionHints (Design Gap)

**File:** `os/Skaffen/internal/agent/agent.go:276-278`

```go
func (ra *routerAdapter) SelectModel(_ agentloop.SelectionHints) (string, string) {
    return ra.inner.SelectModel(ra.phase())
}
```

The adapter bridges the agentloop's `SelectionHints`-based router to the agent layer's `tool.Phase`-based router. But it discards `Urgency`, `TaskType`, and any future hint fields. This means the `DefaultRouter.SelectModel(phase)` method can never receive within-phase context, even if the agentloop starts populating hints.

The `DefaultRouter.SelectModel` method signature takes `tool.Phase`, not `SelectionHints`. To use hints, either:
- The agent.Router interface needs to change to accept hints (breaking change)
- The adapter needs to smuggle hints through a side channel (the `DefaultRouter.inputTokens` pattern is already a side channel)

**Recommendation:** Evolve the agent.Router interface to accept a richer context struct that includes both phase and hints. This is a prerequisite for Findings 5 and 6. For now, the side-channel pattern (`SetInputTokens` before `SelectModel`) works for token count.

---

## Summary: SWE-bench Impact Assessment

| Finding | Severity | SWE-bench Impact | Action |
|---------|----------|-----------------|--------|
| F1: Token-count complexity | Critical | Misroutes if enabled | Don't enable enforce mode with current classifier |
| F2: All-Opus defaults | Correct | Right choice for benchmarking | Keep until >40% pass rate |
| F3: Shadow mode no-op | By design | No impact | Add shadow analysis tooling |
| F4: Budget cliff demotion | Critical | Kills trajectories if budget set | Use advisory mode or no budget for SWE-bench |
| F5: No within-phase routing | Moderate | No impact (all Opus) | Defer to post-baseline |
| F6: SetInputTokens never called | Critical bug | Shadow data is garbage | Wire msgTokens to router before SelectModel |
| F7: Identical context windows | Minor | No risk today | Add defensive check |
| F8: Hints discarded by adapter | Design gap | Blocks future routing | Evolve interface |

**Bottom line for 1/10 pass rate:** Model routing is not the cause. The all-Opus default is correct. The routing infrastructure is dormant and contains bugs (F6) that would manifest if activated, but the right play for SWE-bench is to keep routing simple and focus on task understanding, patch generation quality, and test validation. Fix F6 now so shadow data starts being useful; defer everything else until pass rate exceeds 40%.
