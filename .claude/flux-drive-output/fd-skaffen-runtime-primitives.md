# Skaffen Runtime Primitives: Mapping 50 Agent UI Concepts

**Author:** fd-skaffen-runtime-primitives
**Date:** 2026-03-12
**Source:** Chris Barber's 50 agent UI concepts → Skaffen OODARC sovereign agent runtime

---

## Runtime Inventory (as of analysis)

Before mapping, the current state of each major package:

| Package | Key State Exposed Today |
|---------|------------------------|
| `agentloop` | `Evidence` per turn (timestamps, tokens_in/out, tool_calls[], phase, duration_ms, model, budget_pct, stop_reason), `StreamEvent` (text, tool_start, tool_complete, turn_complete, phase_change) |
| `agent` | `phaseFSM` (brainstorm→plan→build→review→ship, linear), `RunResult` (response, usage, turns, phase) |
| `router` | `BudgetTracker` (spent, max, pct, mode), `ComplexityClassifier` (tier, override), `SelectModel` (model, reason string per turn) |
| `session` | JSONL turns (phase, messages[], usage, tool_calls count, timestamp), `PriomptSession` (prompt_tokens, stable_tokens, excluded_elements[]) |
| `trust` | Three-tier eval (session override → learned glob override → built-in rules), `Allow/Prompt/Block`, `ScopeSession/ScopeProject/ScopeGlobal`, `Learn()` |
| `evidence` | JSONL writer + intercore bridge (`ic events record`), emits per-turn `Evidence` struct |
| `tui` | Single-threaded Bubble Tea app, `statusModel` (phase | model | $cost | ctx% | turns), `StreamCallback` wiring, tool approval overlay, settings overlay |

**What is NOT tracked today:** tok/s rate (only total tokens per turn), file visit frequency, per-tool invocation counts, cross-session patterns, wall-clock timestamp per tool call (only per turn), speculative branches, agent spatial position.

---

## 1. Mapping Table

| # | Idea | Package(s) | New vs Existing | Classification |
|---|------|-----------|-----------------|----------------|
| 1 | Waveform tok/s over time | `agentloop`, `tui` | **New:** add `DurationMs` per-token streaming timing; ring buffer in TUI | Evidence extension + UI |
| 2 | Terminal color for health/state | `tui` | **Existing:** `phaseColor()` + cost thresholds already do this; extend to tool error rates | Mostly UI |
| 3 | Familiarity view for slash commands | `tui` | **New:** usage counter store in `tui/` or `session/` metadata | Pure UI |
| 4 | Desktop peripheral controller | `tui` | **New:** external IPC channel (named pipe or Unix socket) from `cmd/skaffen/` | New IPC layer |
| 5 | Video game terminal controls | `tui` | **Existing:** extends existing keyboard dispatch in `app.go`; gamepad = input abstraction | Mostly UI |
| 6 | Codebase visit frequency | `agentloop`, `evidence` | **New:** `ToolCallDetail` event with file path extraction from bash/read/edit params | New evidence type |
| 7 | Rearview mirror (condensed recent actions) | `tui`, `evidence` | **Existing:** `evidence/` JSONL already has all turns; need sliding window view in TUI | UI over existing data |
| 8 | Compass (on track vs drifting) | `agent`, `evidence` | **New:** phase-progress score: expected_tools_per_phase vs actual, emit as `CompasState` evidence | New evidence type + FSM metric |
| 9 | Smart progress bars with forecasting | `router`, `evidence`, `tui` | **Existing:** `BudgetTracker.Percentage` + turn count; add ETA regression from past evidence | Router + UI |
| 10 | Central task dispatch hub | `agent`, `agentloop` | **New:** multi-agent orchestrator above `Agent`; task queue feeding multiple `Loop` instances | New orchestration layer |
| 11 | ETA forecasts | `router`, `evidence` | **Existing:** `DurationMs` + token counts exist; need rolling average + extrapolation | Evidence query + UI |
| 12 | Spatial overview of agents | `agent` | **New:** `AgentRegistry` with position/status; requires multi-agent runtime | New multi-agent layer |
| 13 | Task queue interface | `agent` | **New:** `TaskQueue` struct above `agentloop`; single agent processes queue serially or new parallel mode | New runtime struct |
| 14 | Breadcrumb trail for progress | `evidence`, `tui` | **Existing:** `Evidence.Phase` + `Evidence.TurnNumber` + `ToolCalls[]` provide full breadcrumbs | UI over existing data |
| 15 | Lens switching (convo/edits/files/cost/timeline/learnings/decisions) | `tui`, `evidence` | **New:** `LensMode` enum in TUI; most lenses read from `evidence/` JSONL; decisions lens needs new `Decision` evidence type | New evidence type + UI |
| 16 | Mobile UI for tap approvals and voice | `trust`, `tui` | **New:** approval channel abstraction (today: chan bool hardcoded to TUI); need HTTP/WebSocket bridge | Trust interface extension |
| 17 | Parallel exploration mode | `agent`, `agentloop` | **New:** `ParallelRunner` spawning N `Loop` instances concurrently with shared read-only session snapshot | Phase-FSM + new runtime |
| 18 | Energy-aware decision routing | `router` | **New:** `EnergyHint` in `SelectionHints.Urgency`; router degrades model on battery/load signal | Router extension |
| 19 | Agent dashboard | `tui`, `evidence` | **Existing:** all metrics available; dashboard = new TUI pane aggregating `Evidence` JSONL | UI over existing data |
| 20 | Preference learning, auto-pick high-confidence | `trust` | **Existing:** `trust.Learn()` + `ScopeProject/ScopeGlobal` already persist preferences; need confidence counter on `Override.Count` | Trust extension |
| 21 | Agent skill learning progress tracking | `evidence`, `session` | **New:** per-tool success/fail rate from `Evidence.ToolCalls[]` + `Evidence.Outcome`; emit `SkillMetric` events | New evidence type |
| 22 | Multi-path exploration with selection | `agent`, `agentloop` | **New:** `BranchRunner` (like #17) + branch scoring + selection mechanism; FSM forks at decision point | Phase-FSM fork + new runtime |
| 23 | Auto-generated shortcuts from usage | `tui`, `evidence` | **New:** slash-command frequency counter in persistent TUI state; auto-register aliases | Pure UI |
| 24 | Notification queue | `tui`, `agentloop` | **Existing:** `StreamCallback` events are already queued; need priority/filter layer on top | UI over existing stream |
| 25 | Next work suggestions stream | `evidence`, `session` | **New:** post-session analysis emitting `Suggestion` events; queries CASS/intersearch | New evidence type (post-session) |
| 26 | Drag-adjustable permission levels | `trust`, `tui` | **Existing:** `trust.Learn()` + scope exist; add slider/range UI over existing trust tiers | Trust UI |
| 27 | SRS/Anki memory review for agents | `session` | **New:** `MemoryCard` records in session JSONL; spaced-repetition scheduler in `session/` | New session record type |
| 28 | Auto-shortcuts with learning aids | `tui` | **New:** shortcut registry with `mnemonic` + `usage_count` persisted to `~/.skaffen/shortcuts.json` | Pure UI |
| 29 | Editable compaction rules | `session` | **Existing:** `PriomptSession` sections are already priority-ordered elements; expose section weights as config | Session config |
| 30 | Arrow key detail level toggling | `tui` | **Existing:** verbose/compact toggle already exists (`/verbose`, `/compact`); extend to keybinding | Pure UI |
| 31 | Rolling context window with progressive compaction | `session`, `agentloop` | **Existing:** `JSONLSession.truncate()` + `PriomptSession.ExcludedElements()` already do this; surface it | UI over existing data |
| 32 | Coding as video game (failed deploy = pwned) | `evidence`, `tui` | **Existing:** `Evidence.Outcome` + tool error flag; gamification layer reads these | UI over existing data |
| 33 | Agents teach/quiz you while working | `session`, `evidence` | **New:** `QuizEvent` evidence type; quiz generator reads session JSONL for teachable moments | New evidence type |
| 34 | Victory celebrations | `tui`, `evidence` | **Existing:** `StreamPhaseChange` to `ship` + `Evidence.Outcome == "success"` trigger; animation only | Pure UI |
| 35 | Critical hits | `tui`, `evidence` | **Existing:** detect from `Evidence.DurationMs` (fast turn) + large `TokensOut`; probabilistic overlay | UI over existing data |
| 36 | See where agents are working | `evidence`, `tui` | **New:** extract file paths from `ToolCalls[]` params; emit `FileActivity` event per tool call | New evidence type |
| 37 | Passive feature toggles | `tui`, `session` | **Existing:** `settings` struct in TUI + `ApplySetting()`; extend to session-level feature flags | UI + session config |
| 38 | Pattern detection → recipes | `evidence` | **New:** `PatternDetector` post-processor over evidence JSONL; emits `RecipeDiscovery` events to intercore | New evidence post-processor |
| 39 | Time-aware suggestions | `router`, `evidence` | **New:** `TimeHint` in `SelectionHints`; router adjusts model/task based on time-of-day/deadline proximity | Router extension |
| 40 | /treasures discoveries | `evidence`, `tui` | **New:** `Discovery` evidence event emitted when agent surfaces novel insight; `/treasures` command reads JSONL | New evidence type + slash cmd |
| 41 | Wrapped (annual summary) | `evidence` | **Existing:** all evidence JSONL is time-stamped; need aggregation query tool (like CASS analytics) | Evidence query tooling |
| 42 | Side-by-side alternatives comparison | `agent`, `tui` | **New:** dual-pane TUI + `BranchRunner` (shared with #17/#22); requires multi-column TUI layout | Phase-FSM fork + UI |
| 43 | Proactive preference calibration | `trust` | **Existing:** `trust.Learn()` exists; need proactive surfacing of low-confidence patterns to user | Trust extension |
| 44 | Proactive alternatives for next work | `evidence`, `session` | **New:** `NextWorkSuggester` analyzes session JSONL + beads state; emits suggestions pre-session | New session lifecycle hook |
| 45 | Proactive exploration surfacing discoveries | `evidence` | **New:** background `ExplorationScanner` that emits `Discovery` events during idle time | New evidence type + async |
| 46 | Alternative interview question UI | `tui` | **New:** structured Q&A overlay mode in TUI; branching question tree for prompt building | Pure UI |
| 47 | A/B testing with split pane | `agent`, `agentloop`, `tui` | **New:** `ABTestRunner` (variant of #17/#22) + split-pane TUI + metric comparison | Phase-FSM fork + UI |
| 48 | Speculative pre-build queue | `agent`, `agentloop` | **New:** `SpeculativeQueue` running low-priority `Loop` instances ahead of user request | New async runtime |
| 49 | Company leaderboards | `evidence` | **New:** evidence export + aggregation service; individual Skaffen has no multi-user primitives | External service |
| 50 | Cross-company leaderboards | `evidence` | **New:** same as #49 but federated; requires telemetry consent + aggregation pipeline | External service |

---

## 2. Ideas Supportable With Current Evidence/Session APIs (15 identified)

These ideas require no new runtime data — only consuming what `Evidence` and `StreamCallback` already emit.

**#7 — Rearview mirror:** `Evidence.ToolCalls[]`, `Evidence.Phase`, `Evidence.TurnNumber`, `Evidence.DurationMs` are per-turn. A sliding window of the last N turns drawn from the JSONL file gives a complete condensed action log. Implementation: new TUI pane reading `~/.skaffen/evidence/<session>.jsonl`.

**#9 — Smart progress bars with forecasting:** `BudgetTracker.Percentage` is live on every `StreamTurnComplete`. `Evidence.DurationMs` per turn gives a velocity signal. ETA = `(1.0 - budget_pct) / avg_pct_per_ms`. All inputs exist today.

**#11 — ETA forecasts:** Same as #9. `Evidence.TokensIn`, `Evidence.TokensOut`, `Evidence.DurationMs` are the three inputs. Rolling 5-turn average gives a stable estimate.

**#14 — Breadcrumb trail:** `Evidence.Phase` + `Evidence.TurnNumber` + `Evidence.ToolCalls[]` fully reconstruct the path. TUI just needs to render them as a horizontal trail.

**#19 — Agent dashboard:** All metrics are in `Evidence` JSONL. The dashboard is a new Bubble Tea pane (or side panel) aggregating: total turns, total cost, phase distribution, tool call frequency histogram, budget burn rate.

**#24 — Notification queue:** `StreamCallback` delivers `StreamText`, `StreamToolStart`, `StreamToolComplete`, `StreamTurnComplete`, `StreamPhaseChange` already. A priority filter on top (e.g., only surface `StreamPhaseChange` and tool errors as notifications) requires no runtime changes.

**#30 — Arrow key detail level toggling:** `/verbose` and `/compact` already exist as commands. Binding them to a key in `keys.Map` is a three-line TUI change. The compact/verbose state is in `m.settings.Verbose`.

**#31 — Rolling context window with progressive compaction:** `PriomptSession.ExcludedElements()` and `ExcludedStableElements()` expose exactly what was dropped from the prompt. `JSONLSession.truncate()` implements windowing. Surfacing these in the TUI is pure rendering.

**#32 — Coding as video game:** `Evidence.Outcome` (`"success"` vs `"tool_use"`) and `IsError` on `StreamToolComplete` events are the health signals. Deploy failure = tool error on a git/bash call. All data exists.

**#34 — Victory celebrations:** `StreamPhaseChange` to phase `"ship"` + `agentDoneMsg` with no error = victory condition. Animation is pure TUI.

**#35 — Critical hits:** `Evidence.DurationMs < threshold` on a turn that produced `Evidence.TokensOut > threshold` = "critical hit" (fast, large response). Probabilistic roll using these two existing fields.

**#37 — Passive feature toggles:** `settings` struct + `ApplySetting()` in `tui/settings.go` already handles toggle persistence within a session. Extending to session-level feature flags requires adding fields to `settings` and wiring them to `session/` metadata record.

**#2 — Terminal color for health/state:** `phaseColor()` in `tui/phase.go` and cost-threshold coloring in `tui/status.go` already exist. Extending to tool error rate (count errors from `StreamToolComplete.IsError`) adds one counter to `appModel`.

**#41 — Wrapped (annual summary):** All `Evidence` JSONL files are timestamped with RFC3339. An offline query tool (go binary or CASS-style analytics) aggregating `~/.skaffen/evidence/*.jsonl` over a date range requires no runtime changes.

**#20 — Preference learning, auto-pick high-confidence:** `trust.Learn()` and `trust.Override{Count}` exist. The `Count` field on `Override` is not incremented today, but the infrastructure is there. Incrementing it on each glob match and auto-promoting high-count overrides to `ScopeProject` needs ~20 lines in `trust.go`.

---

## 3. Ideas Requiring New Evidence/Event Types

These ideas need new fields or new event varieties in `agentloop.Evidence` or new JSONL record types.

**#1 — Waveform tok/s:** Need sub-turn timing. Today `DurationMs` covers the whole turn. Need: `StreamText` events timestamped, or a new `Evidence.TokenTimings []int64` field (ms offsets for each output token chunk). Alternatively add `TokensOutPerSecond float64` computed at turn end from `OutputTokens / DurationMs`.

**#6 — Codebase visit frequency:** Extract file paths from tool params at execution time. Need a new `FileActivity` evidence record: `{type: "file_visit", path: string, tool: string, session_id: string, timestamp: string}`. The extraction hook belongs in `agentloop.executeToolsWithCallbacks()` — parse `bash`/`read`/`edit`/`glob` params for paths and emit before/after tool execution.

**#8 — Compass (on track vs drifting):** Need a per-phase expectation model. Proposed: `CompassState` evidence event emitted at phase boundaries — `{phase: string, expected_tools: []string, actual_tools: []string, coherence_score: float64}`. The coherence score compares actual tool mix against a configurable phase profile. New config file: `~/.skaffen/phase-profiles.json`.

**#15 — Lens switching (decisions lens):** The `decisions` lens needs agent-emitted decision events: `{type: "decision", description: string, options_considered: []string, chosen: string, rationale: string, turn: int}`. The agent would need to detect and structured-emit these from its reasoning text. Other lenses (cost, timeline, files) can be served from existing `Evidence` fields.

**#21 — Agent skill learning progress:** Need per-tool success/fail aggregates. Proposed: `SkillMetric` record emitted per session end — `{tool: string, calls: int, successes: int, errors: int, avg_duration_ms: float64}`. Computed from the session's evidence JSONL by a post-processor in `evidence/`. Requires new post-session hook.

**#25 — Next work suggestions stream:** Post-session `Suggestion` events: `{type: "suggestion", basis: string, action: string, priority: int, session_id: string}`. Emitted by a `NextWorkSuggester` that runs after `agentDoneMsg` and queries CASS context for the working directory.

**#27 — SRS/Anki memory review:** New JSONL record type in `session/`: `{type: "memory_card", front: string, back: string, due: string, ease: float64, reps: int, session_id: string}`. The agent would emit these via a new `remember` tool or by parsing its own output for `[REMEMBER: ...]` markers.

**#33 — Agents teach/quiz you:** New `QuizEvent` evidence type: `{type: "quiz", question: string, answer: string, topic: string, turn: int, session_id: string}`. Generated by a post-processor analyzing session JSONL for teachable patterns.

**#36 — See where agents are working:** Same `FileActivity` event as #6 but needs real-time delivery to TUI via `StreamCallback`. Requires a new `StreamFileActivity` event type in `agentloop.StreamEventType`.

**#38 — Pattern detection → recipes:** New post-session `RecipeDiscovery` event: `{type: "recipe", trigger_pattern: string, tool_sequence: []string, success_count: int, avg_tokens: int}`. A `PatternDetector` goroutine scans evidence JSONL after session end.

**#40 — /treasures discoveries:** New `Discovery` evidence event: `{type: "discovery", content: string, category: string, session_id: string, turn: int}`. The agent emits these when it surfaces a novel insight (could be triggered by a keyword or structured marker in model output). New `/treasures` slash command in `tui/commands.go` reads from evidence JSONL.

**#45 — Proactive exploration surfacing discoveries:** Same `Discovery` type as #40 but emitted asynchronously by a background `ExplorationScanner` goroutine that runs during idle time between user prompts.

---

## 4. Ideas Requiring Phase-FSM Changes or Cross-Phase Signals

The current `phaseFSM` is a strict linear sequence: `brainstorm→plan→build→review→ship`. It has no branching, no parallelism, and no backtracking. The following ideas require structural changes.

### #17 — Parallel Exploration Mode

**Current state:** `agent.Run()` creates one `agentloop.Loop` and runs it to completion. Single goroutine.

**Required changes:**
- New `ParallelRunner` type in `agent/` (or a new `agent/parallel/` package): spawns N `Loop` instances, each with an independent copy of the current session messages (snapshot) and a shared read-only tool registry.
- Each branch gets its own `sessionID` suffixed with `-branch-N` for evidence isolation.
- Branches share a `context.CancelFunc` — canceling one branch does not cancel others.
- The phase FSM cannot be shared across branches; each branch needs its own `phaseFSM` copy.
- New `StreamEventType`: `StreamBranchStart`, `StreamBranchComplete` — carry `BranchID string`.
- New `Evidence.BranchID string` field for attribution.
- `TUI` needs to know which branch produced which output; branch selection collapses to single FSM state.

**FSM change:** The FSM does not advance until a branch is selected. Introduction of a synthetic `exploring` super-state or a `phaseFSM.Fork()` method that returns N child FSMs all in the same phase.

### #22 — Multi-Path Exploration with Selection

Same as #17 but adds **branch scoring**. Requires:
- New `BranchScore` struct: `{branch_id: string, tool_calls: int, tokens: int, complexity: int, coherence_score: float64}`.
- A `BranchScorer` interface injected into `ParallelRunner`.
- After all branches complete, `ParallelRunner` ranks them and emits `StreamBranchRanked` with the recommended branch.
- The selected branch's session messages are merged back into the primary session.
- Session merge requires a new `Session.Merge(other Session) error` method — the primary session appends the selected branch's turns.

### #42 — Side-by-Side Alternatives Comparison

Same runtime requirement as #17/#22. Additional TUI requirement:
- Split-pane layout in `tui/app.go` — two `viewport.Model` instances side-by-side.
- Branch A runs in left pane, Branch B in right pane, each receiving their branch's `StreamCallback`.
- The phase FSM advances only after user selects a branch via key binding.
- `appModel` needs `leftBranchID string`, `rightBranchID string`, `activeBranchID string` state.

### #47 — A/B Testing with Split Pane

Combines #42 (split pane TUI) with controlled variation: Branch A uses model X, Branch B uses model Y. Requires:
- `ParallelRunner` accepts per-branch `RouterConfig` overrides.
- Each branch's `routerAdapter` gets a `SetModelOverride()` call with the A/B model.
- New evidence field: `ABTestID string`, `ABVariant string` — for post-hoc analysis.
- Metric comparison panel in TUI: shows cost, duration, token count side-by-side for both branches.

### #48 — Speculative Pre-Build Queue

Most structurally novel. Requires:
- A `SpeculativeRunner` that maintains a background `Loop` running at `SelectionHints.Urgency = "background"` with a low-priority model (haiku or sonnet).
- The speculative run starts from a predicted next task (inferred from conversation context or next-work suggestions from #25/#44).
- When the user submits a task that matches the speculative prediction (similarity check), the speculative run's partial result is promoted to the foreground.
- Requires: `Loop.Suspend()` / `Loop.Resume()` — pause the speculative goroutine, inspect its current messages, promote if matching.
- New `Agent.StartSpeculative(ctx, task string)` method returning a `SpeculativeHandle`.
- New `Evidence.Speculative bool` field — speculative runs are tagged so evidence analytics can filter them.
- The phase FSM for a speculative run starts at `build` (skips brainstorm/plan) and cannot advance past `review` without promotion.
- **Risk:** If speculative prediction is wrong, the background run is discarded; the evidence JSONL accumulates orphaned events — need a `SpeculativeAborted` event type for cleanup accounting.

### #10 — Central Task Dispatch Hub

Not strictly a FSM change, but requires a new orchestration layer above `Agent`:
- `TaskDispatcher` type: maintains a `TaskQueue` (priority queue of tasks), assigns tasks to available `Agent` instances.
- Each `Agent` instance runs in its own goroutine, signaling completion via channel.
- Requires `Agent` to be reentrant (currently it is, since state is in `phaseFSM` and `session` which are per-instance).
- New `AgentStatus` type: `{agent_id: string, phase: string, task: string, turns: int, budget_pct: float64}`.

---

## 5. Ideas Requiring Trust/Approval Model Evolution

Current trust model: `Allow/Prompt/Block`, three scopes (`Session/Project/Global`), glob pattern matching, learned overrides per tool-name pattern.

**#16 — Mobile UI for tap approvals:**
- Today: `ToolApprover func(toolName string, input json.RawMessage) (allow bool)` blocks a goroutine on a `chan bool`.
- Mobile approval requires the approval request to escape the local process: HTTP/WebSocket endpoint that serializes the `toolApprovalRequestMsg` and waits for a remote response.
- Required: `trust.ApprovalTransport` interface with `LocalTUI` and `RemoteHTTP` implementations. The `ToolApprover` becomes a factory that picks the transport.
- Security: approval token per session, HTTPS only, short timeout before auto-deny.
- This is a significant trust boundary change — remote approval means the approval decision travels over a network.

**#26 — Drag-adjustable permission levels:**
- Current: binary per-tool overrides. The drag slider concept implies a risk spectrum.
- Required: `trust.RiskLevel int` (0=safe, 1=low, 2=medium, 3=high, 4=dangerous) on each built-in rule and learned override.
- Slider sets a `maxAutoApproveRisk int` threshold; tools at or below threshold are auto-allowed.
- New `trust.Config.MaxAutoApproveRisk int` field.
- The `evaluateBuiltIn()` function returns `Allow` if `toolRisk <= config.maxAutoApproveRisk`, `Prompt` above threshold, `Block` for rules explicitly blocked.

**#43 — Proactive preference calibration:**
- Current: `Override.Count` field exists on the struct but is never incremented.
- Required: increment `Count` on every glob match hit in `Evaluate()`.
- Add `Override.Confidence float64` = `Count / (Count + doubt_factor)` — surfaced when confidence drops below a threshold.
- New TUI notification: "You've approved `bash:go test*` 47 times — want to auto-allow it globally?"
- Requires `trust.Evaluator.LowConfidenceOverrides() []Override` method.

**#20 — Preference learning, auto-pick high-confidence:**
- Extends the `Count` tracking from #43.
- `ScopeProject` overrides with `Count > N` are promoted to `ScopeGlobal` automatically.
- New `trust.Config.AutoPromoteThreshold int` field.
- The `Learn()` method checks existing overrides before appending — if a session-scope override already exists with high count, promotes it up.

---

## 6. Ideas Requiring Session/Context Management Changes

**#29 — Editable compaction rules:**
- `PriomptSession` receives `[]priompt.Element` at construction; section weights/priorities are baked in.
- Required: expose `PriomptSession.SetSectionPriority(name string, priority int)` — re-orders the `sections` slice.
- New config file: `~/.skaffen/compaction.json` maps section names to priority overrides.
- The `/settings` command would include a `compact.sections` key to list and adjust.

**#27 — SRS/Anki memory review:**
- New JSONL record type alongside `turnRecord` in `session/session.go`: `memoryCardRecord {type: "memory_card", ...}`.
- `JSONLSession.Load()` would need to separate `turn` and `memory_card` records.
- A new `JSONLSession.MemoryCards() []MemoryCard` accessor.
- The review scheduler would call `MemoryCards()`, filter by `due <= now`, and inject them into the system prompt as a `priompt.Element` with high priority.

**#31 — Rolling context window (surface to user):**
- `PriomptSession.ExcludedElements()` already returns what was dropped.
- Required: push `ExcludedElements` into `StreamCallback` as a new `StreamContextCompaction` event so the TUI can show "3 earlier context sections dropped" in real-time.
- Alternatively: include excluded element names in `Evidence` (already done in `Evidence.ExcludedElements[]`) and render from evidence JSONL.

**#44 — Proactive alternatives for next work:**
- New session lifecycle phase: `post-session`. After `agentDoneMsg`, a `PostSessionHook` runs asynchronously.
- `PostSessionHook` reads the current session JSONL, calls CASS `cass context <workdir>` to find related past sessions, and emits `Suggestion` evidence events.
- Required: `session.PostSessionHook func(sessionID, workDir string)` — a callback wired in `cmd/skaffen/main.go` after the run completes.
- TUI shows suggestions on next startup via a new `~/.skaffen/suggestions.json` file.

**#48 — Speculative pre-build (session aspect):**
- The speculative branch needs a `session.Snapshot() *JSONLSession` method that deep-copies the current message history.
- The snapshot is frozen at the point of fork; the speculative run appends to its own copy.
- On promotion, `session.Merge(speculative *JSONLSession) error` appends the speculative turns to the primary session, then truncates to `maxTurns`.
- On abort, the speculative session file is deleted (or marked with a `SpeculativeAborted` header record).

**#15 — Decisions lens:**
- New `decision` record type in `session/session.go` alongside `turnRecord`.
- The agent emits decision records by detecting structured output (e.g., `<decision>...</decision>` XML markers in model output, stripped before display).
- A parser in `session/` extracts these and writes them as `decisionRecord` entries.
- The decisions lens in TUI reads `decisionRecord` entries from the session JSONL.

---

## 7. Pure UI Decorations (No Runtime Changes)

These ideas are entirely cosmetic — they can be implemented in `tui/` or as external TUI panels reading existing `Evidence` JSONL, with zero changes to `agentloop/`, `agent/`, `session/`, `router/`, `trust/`, or `evidence/`.

| # | Idea | Notes |
|---|------|-------|
| 3 | Familiarity view for slash commands | Persist a usage counter to `~/.skaffen/cmd_usage.json`; read in TUI at startup |
| 5 | Video game terminal controls | Keyboard dispatch extension in `app.go`; gamepad via OS input layer |
| 23 | Auto-generated shortcuts from usage | Frequency counter for slash commands; alias registration in `tui/` |
| 28 | Auto-shortcuts with learning aids | Same as #23 with mnemonic hints in completion UI |
| 30 | Arrow key detail level toggling | Bind `[` / `]` keys to existing verbose/compact toggle |
| 34 | Victory celebrations | Ship phase animation; reads `StreamPhaseChange` and `agentDoneMsg` |
| 35 | Critical hits | Probabilistic overlay on turns with low `DurationMs` + high `TokensOut` |
| 46 | Alternative interview question UI | Branching Q&A overlay in TUI; builds prompt string; no agent changes |

**Near-pure UI (one minor evidence extension each):**

| # | Idea | Minimal Runtime Touch |
|---|------|----------------------|
| 2 | Terminal color for health | Add `ErrorCount` counter to `appModel` from `StreamToolComplete.IsError` |
| 19 | Agent dashboard | New TUI pane; zero evidence changes |
| 24 | Notification queue | Priority filter on existing `StreamCallback`; no runtime changes |
| 32 | Coding as video game | Reads `Evidence.Outcome` + tool errors; no new events |
| 37 | Passive feature toggles | Extend `settings` struct; no session/evidence changes |
| 49 | Company leaderboards | External service; Skaffen only exports `evidence/` JSONL |
| 50 | Cross-company leaderboards | External federated service |

---

## Summary: Effort Classification

| Tier | Count | Ideas |
|------|-------|-------|
| Pure UI (no runtime) | 8 | #3, #5, #23, #28, #30, #34, #35, #46 |
| UI over existing APIs | 11 | #2, #7, #9, #11, #14, #19, #24, #31, #32, #37, #41 |
| New evidence/event types | 12 | #1, #6, #8, #15, #21, #25, #27, #33, #36, #38, #40, #45 |
| Trust model evolution | 4 | #16, #20, #26, #43 |
| Session/context changes | 5 | #27, #29, #31, #44, #48 (partial overlap with evidence) |
| Phase-FSM / parallel runtime | 6 | #10, #17, #22, #42, #47, #48 |
| External service (no Skaffen changes) | 2 | #49, #50 |
| Router extensions | 2 | #18, #39 |
| IPC/peripheral layer | 1 | #4 |

**Highest leverage, lowest cost:** Ideas #7, #9, #11, #14, #24, #31, #34, #35 — all read existing `Evidence` or `StreamCallback` data and require only TUI rendering work.

**Highest architectural impact:** Ideas #17, #22, #42, #47, #48 — all require a `ParallelRunner`/`BranchRunner` abstraction that fundamentally changes the single-goroutine assumption in `agentloop.Loop`. These should be designed together as a single `agent/parallel/` package.

**Most self-contained new feature:** #40 (`/treasures`) — new `Discovery` evidence type + new slash command in `tui/commands.go`. Clean vertical slice with no cross-cutting impact.

**Watch for:** `agentloop` must not import `agent` or `tool` (existing constraint). Any parallel/branching runtime must respect this. `ParallelRunner` belongs in `agent/` or a new `agent/parallel/` package, not in `agentloop/`.
