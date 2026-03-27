---
artifact_type: cuj
journey: skaffen-sovereign-session
actor: regular user (developer using Skaffen for autonomous tasks)
criticality: p1
bead: Sylveste-2c7
---

# Skaffen Sovereign Agent Session

## Why This Journey Matters

Skaffen is the sovereign agent runtime — the thing that actually thinks, decides, and acts. Every other Sylveste component (Clavain, Mycroft, the plugins) exists to orchestrate, review, or support what happens inside a Skaffen session. If a Skaffen session is slow, opaque, or untrustworthy, the entire platform fails regardless of how good the coordination is.

The OODARC loop (Observe-Orient-Decide-Act-Reflect-Compound) is Skaffen's core innovation. Unlike simple prompt-response agents, Skaffen separates thinking into phases: observing the environment, orienting on the problem, deciding on an approach, acting (writing code, running commands), reflecting on the outcome, and compounding learnings for future sessions. Each phase can use a different model (cheap for Observe, expensive for Decide), different tools (restricted during Orient, full access during Act), and different trust levels (strict defaults at L0-L1, softened gates at L2+ — see Tool Trust CUJ).

This matters because the developer needs to trust what Skaffen does autonomously while maintaining the ability to intervene, redirect, or veto at any point. The TUI is the window into the agent's mind — it must surface the right level of detail: enough to understand, not so much that it overwhelms.

## The Journey

The developer launches Skaffen in TUI mode: `skaffen` (or `go run ./cmd/skaffen` during development). The TUI presents a chat interface with a status bar showing the current phase, model, and cost. The developer types a task: "Refactor the selector to support priority boosts."

Skaffen enters the Observe phase — a dedicated phase that uses targeted tool calls (read, glob, grep) to explore the codebase guided by the task description. The TUI shows what Skaffen is reading (file names, not full contents). It moves to Orient — analyzing the problem, identifying patterns in the existing code. The developer can see the orient output: "Found RankBeads in selector.go, currently sorts by priority/age/complexity. Boost would modify effective priority before sort."

In the Decide phase, Skaffen proposes an approach. The TUI highlights the decision: "Will add PriorityBoost config type, modify RankBeads to accept variadic boosts, clamp to [0,4]." The developer can approve, modify, or veto. For trusted tasks (simple complexity, within established patterns), the smart trust evaluator may auto-approve.

The Act phase is where code gets written. Skaffen uses its registered tools — file read, file write, bash execution — with phase gating (write tools restricted outside Act at default trust level L0-L1; softened at L2+ per Tool Trust CUJ). The TUI shows tool invocations and results in real-time. The developer watches code appear, tests run, and diffs accumulate.

After acting, Skaffen Reflects: did the tests pass? Does the diff match the intent? Were there surprises? Reflection output goes to the session log. Finally, Compound: Skaffen automatically identifies learnings worth persisting and writes compound docs to docs/solutions/. The mechanism for deciding *what* is worth compounding is calibrated over time — early sessions may over- or under-compound.

For headless operation (CI, automation, Mycroft dispatch), the developer uses print mode: `echo "fix the flaky test in selector_test.go" | skaffen --mode print`. Same OODARC loop, just stdout instead of TUI.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Phase transitions visible in TUI status bar | observable | Status bar updates on each phase change, including model name |
| Observe phase uses targeted exploration | measurable | File reads are scoped to the task's relevant modules via tool calls |
| Decide phase produces a reviewable plan before acting | observable | Decision output visible in TUI before Act begins |
| Tool invocations are phase-gated | measurable | Write tools restricted outside Act at default trust level; softened at higher trust levels (see Tool Trust CUJ) |
| Smart trust auto-approves simple, safe tool calls | measurable | Trust evaluator approval rate > 80% for simple patterns after 5 sessions |
| Print mode produces equivalent results to TUI mode | observable | Same OODARC phases and tool calls for identical prompts (output may vary due to LLM non-determinism) |
| Session persists and is resumable | measurable | JSONL session file written, reloadable on restart |
| Cost scales with task complexity | observable | Skaffen records cost per session; simple tasks cost meaningfully less than complex ones (tracked via interstat) |

## Known Friction Points

- **Model routing latency** — switching between cheap and expensive models mid-session adds API cold-start time. Router should pre-warm when possible.
- **Trust calibration is per-installation** — a new Skaffen instance starts with no trust history. Built-in rules provide a safe baseline (read=Allow, write=Prompt, destructive=Block), but learned patterns take several sessions to accumulate. Dispatched agents inherit the developer's global trust rules (read-only) for faster cold-start.
- **MCP tool loading** — loading all Interverse plugin tools at startup is slow if many plugins are installed. Should be lazy-loaded per phase.
- **TUI model display lag** — the router selects different models per phase (configurable), but the TUI status bar doesn't auto-update the displayed model name on phase transitions. The backend routes correctly; the display is stale until the next turn.
- **Compound calibration period** — Skaffen automatically writes compound docs, but the mechanism for deciding what's worth persisting needs calibration. Early sessions may over-compound (noisy) or under-compound (missing learnings).
- **No streaming diff view** — code changes appear as full file writes, not incremental diffs. Hard to follow for large changes.
