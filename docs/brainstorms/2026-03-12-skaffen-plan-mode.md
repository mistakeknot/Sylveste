# Brainstorm: Skaffen Plan Mode

**Bead:** Sylveste-6i0.21
**Date:** 2026-03-12
**Trigger:** Does plan mode make sense given Clavain's `/sprint` workflow already covers planning?

## Research Summary

Three parallel research threads investigated:
1. How 5 competitors implement plan mode (CC, Codex, Gemini, OpenCode, Amp)
2. What Clavain's sprint workflow already covers vs. what plan mode would add
3. Skaffen's architecture feasibility for plan mode integration

## Key Finding: Plan Mode ≠ Planning Workflow

The core confusion is conflating two different things:

| Concept | What It Does | When It Runs |
|---------|-------------|--------------|
| **Plan mode** (interactive) | Read-only codebase exploration with no side effects | Before or instead of building — user toggles it |
| **Planning workflow** (sprint) | Document creation: brainstorm → PRD → implementation plan | Step 1-3 of `/sprint` — produces artifacts |

Clavain's `/sprint` covers the planning *workflow* (creating plans). Plan mode covers the *exploration* phase — safe read-only poking around before you even know what you want to build.

**They're complementary, not competing.**

## Competitor Landscape

Three distinct architectural patterns exist:

### Pattern 1: Permission Layer (Claude Code, Gemini)
- Hard tool-level blocking: write tools unavailable in plan mode
- Toggle via `/plan`, `Shift+Tab`, or CLI flag
- Safety-first: no way to accidentally modify files
- **Claude Code:** Part of 5-mode permission system (default → acceptEdits → plan → dontAsk → bypass)
- **Gemini:** Also routes to different model (Flash-Lite router → Pro for planning, Flash for building)

### Pattern 2: Approval Gate (Codex)
- Agent researches and presents step-by-step plan
- User must explicitly approve before any modifications
- Not truly read-only — more like "propose then execute"
- Default-on since v0.96 (users opt out, not in)

### Pattern 3: Model Routing (Amp)
- No actual plan mode — just 6 agent modes that control model/thinking budget
- "Deep mode" = GPT-5.3 + extended thinking, but no tool restrictions
- Planning is instruction-based, not enforced

### Pattern 4: Agent Role (OpenCode)
- Plan agent is a separate subagent type, not a mode toggle
- Requires approval for destructive ops but isn't binary read-only

**Verdict:** Patterns 1 and 2 are most aligned with Skaffen's phase-gated architecture.

## Skaffen Architecture: Already 80% There

Skaffen's OODARC system already supports plan mode:

**What exists:**
- `PhasePlan` constant declared in `internal/tool/tool.go`
- Tool gates defined: `PhasePlan: {"read", "glob", "grep", "ls"}` (read-only)
- `ToolApprover` callback can intercept every tool call at runtime
- `explore` subagent pre-configured as read-only
- Phase FSM structure supports adding phases

**What's missing:**
- Phase FSM doesn't include plan phase (skips from brainstorm → build)
- No CLI flag (`--plan-mode` or `--phase plan`)
- No TUI toggle (no Shift+Tab equivalent)
- No status bar indicator
- Router has no plan-phase model defaults

**Implementation effort:** ~5.5 hours total (Phase 1: 2 hours for core, Phase 2: 3.5 hours for TUI polish).

## The Real Question: What User Problem Does This Solve?

### Scenarios where plan mode adds value:

1. **Unfamiliar codebase exploration** — "I want to understand this repo before I start changing things." Sprint workflow assumes you already know what to build.

2. **Impact analysis** — "What would break if I changed X?" Read-only exploration with grep, read, glob to trace dependencies before committing to a plan.

3. **Teaching/pair programming** — "Walk me through how this works." Agent explains code without risk of accidental modification.

4. **Safe multi-step research** — "Analyze the test coverage across these 5 packages." Long-running read-only tasks where a stray tool call shouldn't modify files.

5. **Audit/review** — "Review this PR's changes and explain what they do." Pure analysis, no action.

### Scenarios where sprint workflow is sufficient:

1. **"Build feature X"** — Sprint's brainstorm→plan→execute pipeline handles this end-to-end.

2. **"Fix this bug"** — Sprint pipeline with TDD cycle covers analysis + fix.

3. **"Refactor module Y"** — Sprint + quality gates provides structured refactoring.

## Design Options

### Option A: Minimal — CLI Flag + Phase Entry Point
Add `--plan-mode` flag that starts the agent at `PhasePlan` instead of `PhaseBuild`. Uses existing gate definitions. No TUI changes.

- **Pro:** 2 hours, zero risk, uses existing architecture
- **Con:** No way to toggle mid-session, no TUI feedback
- **Competitive parity:** Partial (matches Amp's approach)

### Option B: Toggle — TUI Mode Switch
Add Shift+Tab (or similar) toggle between Plan and Build modes. Status bar shows current mode. Tool gates switch dynamically.

- **Pro:** Matches Claude Code/Gemini UX exactly, mid-session toggle
- **Con:** 5.5 hours, needs TUI status bar work
- **Competitive parity:** Full (matches CC + Gemini)

### Option C: Hybrid — Plan Phase in OODARC FSM
Insert Plan as a formal OODARC phase between Brainstorm and Build. Agent progresses: Brainstorm → Plan (read-only analysis) → Build (execution). Plan→Build transition requires explicit user approval.

- **Pro:** Integrates naturally into existing phase system, approval gate built-in
- **Con:** Changes FSM semantics (currently linear, no backward transitions)
- **Competitive parity:** Exceeds (combines CC's read-only with Codex's approval gate)

### Option D: Defer — Not Now
Plan mode is a nice-to-have. Focus on higher-leverage features (subagents, skills, hooks).

- **Pro:** Zero effort, keeps focus on P1 items
- **Con:** Feature gap remains, 4/5 competitors have it

## Recommendation

**Option B (Toggle)** — it's the right balance of effort vs. value:

1. Skaffen's architecture is already designed for this (PhasePlan exists, gates exist)
2. The toggle pattern (Shift+Tab) is the established UX convention across competitors
3. Implementation is bounded at 5.5 hours with zero architectural risk
4. It fills a genuine gap between "I want to explore" and "I want to build"

**Not Option C** because:
- Forcing plan-before-build adds friction for users who know what they want
- OODARC phases should remain opt-in, not mandatory
- The Codex approval-gate pattern is better handled by the existing ToolApprover callback

**Not Option D** because:
- PhasePlan already exists in the codebase — wiring it up is negligible effort
- 4/5 competitors ship this; it's table stakes for a coding agent
- The user's instinct ("does this make sense?") was good — it makes sense precisely *because* it's complementary to sprint, not competing

## Open Questions

1. **Model routing:** Should plan mode use a cheaper model? (Gemini does Flash-Lite → Pro routing for plan vs build)
2. **Session continuity:** When toggling out of plan mode, does the plan-mode conversation context carry into build mode? (It should — the exploration informs the build)
3. **Evidence emission:** Should plan-mode exploration emit Interspect evidence? (Yes — read patterns inform future routing)
4. **Subagent inheritance:** When plan mode is active, should spawned subagents also be plan-mode? (Yes — explore subagent already is)

## Implementation Sketch (Option B)

### Phase 1: Core (2 hours)
1. Add `planMode bool` field + `WithPlanMode(bool)` option to `internal/agent/agent.go`
2. When enabled, use `PlanModeGates` (all phases → read-only tools)
3. Add `--plan-mode` flag to `cmd/skaffen/main.go`
4. Add plan-mode context to session system prompt

### Phase 2: TUI Integration (3.5 hours)
1. Add Shift+Tab keybinding to toggle plan mode in TUI
2. Show "Plan Mode" badge in status bar
3. When toggling off, confirm with user ("Exit plan mode and allow modifications?")
4. Persist mode in session metadata for resume

### Phase 3: Polish (future, not in scope)
1. Model routing hint for plan mode (cheaper model)
2. Plan-mode evidence emission to Interspect
3. Plan summary generation on exit ("Here's what I learned during exploration")
