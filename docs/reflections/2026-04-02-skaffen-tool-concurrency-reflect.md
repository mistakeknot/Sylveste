---
artifact_type: reflection
bead: sylveste-18a.1
stage: done
---

# Reflect: Per-Invocation Tool Concurrency Classification

## What Worked

- **Brainstorm review caught the biggest design mistake early.** The initial Approach A (extend core Tool interface) was rejected by 3 independent review agents in favor of Approach B (optional interface). This saved significant rework — the optional interface pattern required zero changes to MCP tools and matched the established PhasedTool precedent.

- **Three-phase execution model (serial gate → parallel execute → serial collect)** emerged from the correctness review as a P0 fix and proved to be the cleanest architecture. Approval stays on the main goroutine (non-reentrant TUI constraint), execution fans out, collection restores ordering. This is exactly what Claude Code does in production.

- **Channel-based result collection** over direct slice writes eliminated race detector concerns entirely. The `indexedResult` channel pattern is cleaner than pre-allocated slots and makes the ordering guarantee explicit.

- **Single-send `executeOne` pattern** eliminated the dual-send deadlock risk caught by quality gates. Named return + deferred recover means exactly one write to the channel per goroutine, regardless of panic path.

## What We'd Do Differently

- **Start with the optional interface pattern.** The user chose Approach A in brainstorming; the review cycle corrected it. If we'd applied the PhasedTool precedent test ("does this codebase already use optional interfaces?") during brainstorming, we'd have skipped one review round.

- **Audit `find` earlier.** Both correctness and quality agents flagged `find -delete` and `find -exec ... +` as false-safe escapes. The metachar guard only catches shell operators, not tool-specific write flags. `find` was removed from safeCommands — but this class of tool-specific write modes (vs shell-level composition) should be a first-class check in BashCommandSafe.

- **Don't emit StreamToolStart from execution phase.** We added it, then had to remove it because `collectWithCallbacks` already emits it during streaming. The dual-emission was caught by existing tests, but the round-trip cost a few minutes. Reading the stream callback flow before implementing would have avoided it.

## Key Lessons

1. **Optional interfaces are Go's extension mechanism.** When you find yourself adding a method to a core interface that most implementors will stub with a constant, use an optional interface instead. The duck-type assertion in `agentloop` (anonymous local interface) keeps the layering clean.

2. **Semaphore acquisition belongs inside the goroutine, not on the launching goroutine.** Acquiring on the main goroutine couples the launch loop to goroutine completion order. Inside the goroutine, the semaphore is purely a concurrency limiter with no ordering side effects.

3. **Per-invocation classification is strictly more useful than per-type.** `bash` is sometimes safe and sometimes not. The Claude Code pattern of checking `isConcurrencySafe(input)` — not `isConcurrencySafe()` — is the right granularity. The cost is parsing the input in the classifier, but that's a trivial price for correctness.

4. **MCP tools must never self-declare concurrency safety.** The toolBridge MCP guard (checking for `ServerName()` method) is a trust boundary. Untrusted plugins cannot opt into parallel execution — only built-in tools with known behavior can.

5. **Review agents converge on real issues.** Three independent agents finding the same P0 (interface package placement) is strong signal. Cross-agent convergence is the highest-confidence indicator in multi-agent review.
