---
artifact_type: cuj
journey: skaffen-sovereign-session
actor: regular user (developer using Skaffen for autonomous tasks)
criticality: p1
bead: Demarch-2c7
---

# Skaffen Sovereign Agent Session

## Why This Journey Matters

Skaffen is the sovereign agent runtime — the thing that actually thinks, decides, and acts. Every other Demarch component (Clavain, Mycroft, the plugins) exists to orchestrate, review, or support what happens inside a Skaffen session. If a Skaffen session is slow, opaque, or untrustworthy, the entire platform fails regardless of how good the coordination is.

The OODARC loop (Observe-Orient-Decide-Act-Reflect-Compound) is Skaffen's core innovation. Unlike simple prompt-response agents, Skaffen separates thinking into phases: observing the environment, orienting on the problem, deciding on an approach, acting (writing code, running commands), reflecting on the outcome, and compounding learnings for future sessions. Each phase can use a different model (cheap for observe, expensive for decide), different tools (restricted during orient, full access during act), and different trust levels.

This matters because the developer needs to trust what Skaffen does autonomously while maintaining the ability to intervene, redirect, or veto at any point. The TUI is the window into the agent's mind — it must surface the right level of detail: enough to understand, not so much that it overwhelms.

## The Journey

The developer launches Skaffen in TUI mode: `go run ./cmd/skaffen`. The TUI presents a chat interface with a status bar showing the current phase, model, and token count. The developer types a task: "Refactor the selector to support priority boosts."

Skaffen enters the Observe phase — scanning relevant files, reading the codebase context. The TUI shows what Skaffen is reading (file names, not full contents). It moves to Orient — analyzing the problem, identifying patterns in the existing code. The developer can see the orient output: "Found RankBeads in selector.go, currently sorts by priority/age/complexity. Boost would modify effective priority before sort."

In the Decide phase, Skaffen proposes an approach. The TUI highlights the decision: "Will add PriorityBoost config type, modify RankBeads to accept variadic boosts, clamp to [0,4]." The developer can approve, modify, or veto. For trusted tasks (simple complexity, within established patterns), the smart trust evaluator may auto-approve.

The Act phase is where code gets written. Skaffen uses its registered tools — file read, file write, bash execution — with phase gating (destructive tools only available in Act). The TUI shows tool invocations and results in real-time. The developer watches code appear, tests run, and diffs accumulate.

After acting, Skaffen Reflects: did the tests pass? Does the diff match the intent? Were there surprises? Reflection output goes to the session log. Finally, Compound: what was learned that should persist across sessions? This feeds back into Skaffen's memory and Demarch's compound docs.

For headless operation (CI, automation, Mycroft dispatch), the developer uses print mode: `echo "fix the flaky test in selector_test.go" | go run ./cmd/skaffen --mode print`. Same OODARC loop, just stdout instead of TUI.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Phase transitions visible in TUI status bar | observable | Status bar updates on each phase change |
| Observe phase completes without reading unnecessary files | measurable | File reads are scoped to the task's module |
| Decide phase produces a reviewable plan before acting | observable | Decision output visible in TUI before Act begins |
| Tool invocations are phase-gated | measurable | Destructive tools blocked outside Act phase |
| Smart trust auto-approves simple, safe tool calls | measurable | Trust evaluator approval rate > 80% for simple patterns |
| Print mode produces equivalent results to TUI mode | measurable | Same tool calls, same output for identical prompts |
| Session persists and is resumable | measurable | JSONL session file written, reloadable on restart |
| Cost scales with task complexity | observable | Simple tasks cost meaningfully less than complex ones |

## Known Friction Points

- **Model routing latency** — switching between cheap and expensive models mid-session adds API cold-start time. Router should pre-warm when possible.
- **Trust calibration is per-installation** — a new Skaffen instance starts with no trust history. Bootstrapping trust requires human-in-the-loop for the first N sessions.
- **MCP tool loading** — loading all Interverse plugin tools at startup is slow if many plugins are installed. Should be lazy-loaded per phase.
- **TUI model display lag** — the router selects different models per phase (configurable), but the TUI status bar doesn't auto-update the displayed model name on phase transitions. The backend routes correctly; the display is stale until the next turn.
- **Compound phase auto-writes** — Skaffen automatically identifies learnings and writes compound docs to docs/solutions/ without user intervention. The mechanism for deciding *what* is worth compounding needs calibration.
- **No streaming diff view** — code changes appear as full file writes, not incremental diffs. Hard to follow for large changes.
