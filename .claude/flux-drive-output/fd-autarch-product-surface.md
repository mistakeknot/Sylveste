# fd-autarch-product-surface: Chris Barber 50 Ideas → Autarch Feature Mapping

**Role:** fd-autarch-product-surface
**Date:** 2026-03-12
**Source:** `docs/research/2026-03-12-agent-ui-explorations-chrisbarber.md`

**Alignment:** The strongest ideas in Barber's list reinforce Demarch's OODARC flywheel — real-time evidence surfaces (1, 7, 9, 11), closed-loop preference learning (20, 38, 43), and proactive routing (25, 44, 48) all map directly to the Observe→Orient→Compound cycle Autarch is designed to run.
**Conflict/Risk:** Gamification ideas (32–35, 49–50) sit in explicit tension with PHILOSOPHY.md's "receipts, not narratives" stance — entertainment theater that doesn't produce evidence is accidental complexity.

---

## 1. Per-Tool Feature Table

### Bigend — 17 ideas

Bigend is the mission control surface (multi-project, multi-agent). It owns dashboards, task dispatch, agent state, and the observation layer. Most dashboard/visualization ideas land here.

| # | Idea | Concrete Feature |
|---|------|-----------------|
| 1 | Waveform tok/s | Token rate sparkline per-agent in the agent card; rolling 60s waveform in TUI and web |
| 2 | Terminal frame colors | Agent card border color keyed to state: `idle`=dim, `running`=blue, `blocked`=amber, `error`=red (Tokyo Night palette) |
| 7 | Rearview mirror | Persistent "Recent Actions" panel in Bigend sidebar: last N completed tasks across all projects, condensed one-liners |
| 9 | Smart progress bars | ETA-weighted progress bar per active run using Coldwine phase data + historical interstat actuals (closes the OODARC loop on estimates) |
| 10 | Central task dispatch | This is Bigend's core purpose; the feature is a unified inbox/dispatch panel — type task → route to project → agent picks it up |
| 11 | ETA forecasts | Per-run ETA column in agent list; sources from `calibrate-phase-costs` actuals; shows confidence interval when history is thin |
| 12 | Spatial agent overview | TUI: grid layout of agent tiles with position = project/sprint; Web: card grid with drag-reorder; replaces current list view |
| 13 | Task queue | Pending queue panel alongside active runs; supports drag-reorder priority; persists to Coldwine `.state.db` |
| 14 | Breadcrumb trail | Per-agent "path" strip showing: phase → last file touched → last tool used; updates via Intermute signal stream |
| 15 | Lens switching | Tab bar in agent detail view: `Convo | Edits | Files | Cost | Timeline | Decisions`; each lens is a different read of the same run data |
| 19 | Agent dashboard | The dashboard itself — already partially exists, formalize as a first-class view with configurable widget grid |
| 24 | Notification queue | Notification panel: agent needs approval, blocked on gate, cost spike detected; accessible via `?` key or bell icon |
| 30 | Arrow key detail toggle | `→`/`←` keys cycle verbosity level in any list (compact / normal / verbose); universal across all Bigend list views |
| 36 | Agent location map | Project × agent matrix — shows which agent is in which project file tree; clickable to jump to tmux session |
| 37 | Passive toggles | Status-bar toggle row at bottom of Bigend TUI: `[auto-approve] [cost-alerts] [breadcrumbs] [lens:files]` — F-key or click |
| 49 | Company leaderboard | Internal usage leaderboard: tokens/tasks/PRs per developer per week; opt-in; reads from interstat |
| 16 | Mobile tap UI | Out of scope for TUI/CLI; web layer only; deferred — Bigend web could expose a mobile-optimized approval endpoint |

**Note on 16:** Flagged as web-layer-only deferred, not a CLI feature.

---

### Coldwine — 10 ideas

Coldwine owns task orchestration, sprints, Epics/Runs, and the execution lifecycle. Ideas about task routing, parallel execution, and permission control land here.

| # | Idea | Concrete Feature |
|---|------|-----------------|
| 5 | Game-style controls | Sprint control keybindings: `p` pause, `r` resume, `k` kill, `f` fast-forward (skip to next gate) — already partial, formalize |
| 8 | Compass (on/off track) | Per-sprint "drift score": compare current file-edit distribution vs PRD scope in Gurgeh spec; surface as `⬤ on track` / `⚠ drifting` indicator |
| 17 | Parallel exploration | Coldwine Epics: launch N child runs with different approach branches; new `--explore N` flag; each run gets isolated workspace |
| 22 | Multi-path pick | After parallel exploration (17), Coldwine presents diff summary per branch; user picks winner; losing branches archived as evidence (C2) |
| 26 | Drag permission levels | Configurable trust level per sprint: `[read-only | propose | apply | auto-apply]` — stored in `.coldwine/config.toml` per project |
| 29 | Edit compaction rules | User-editable compaction policy: which message types to summarize vs keep verbatim; stored as TOML per project/sprint |
| 31 | Rolling context window | Context compaction that ages oldest unreferenced segments first; configurable decay rate; hooks into Intermute context events |
| 42 | Side-by-side alternatives | Split-pane view of two Coldwine run outputs; keybind `s` in run detail view; useful after parallel exploration |
| 47 | A/B split pane | Formalized A/B mode: two runs, same task, different models; Coldwine tracks outcome divergence; feeds model routing calibration |
| 48 | Speculative queue | Pre-warm queue: Coldwine reads "likely next tasks" signal from Pollard/Bigend and pre-stages agent context; delivers to user as "ready" |

---

### Gurgeh — 6 ideas

Gurgeh owns PRD generation, spec validation, and structured brainstorming. Ideas about structured question flows, interview UI, and alternatives review land here.

| # | Idea | Concrete Feature |
|---|------|-----------------|
| 6 | Codebase visit frequency | Heatmap of file access frequency shown in PRD context panel — which files are most referenced, helping Gurgeh focus spec scope |
| 21 | Agent skill tracking | Per-spec "agent knowledge coverage" panel: which repo areas the agent has visited; gaps shown as unvisited zones in Gurgeh file tree |
| 33 | Agent teaches/quizzes | "Rationale mode" in Gurgeh spec review: agent explains each spec decision, user can confirm/reject; each rejection improves the PRD |
| 40 | /treasures discoveries | `/discoveries` slash command in Gurgeh: surfaces interesting patterns found during spec research (undocumented APIs, surprising constraints, etc.) |
| 43 | Proactive pref calibration | During PRD intake, Gurgeh detects ambiguous preference points and asks targeted calibration questions before generating (not after) |
| 46 | Interview question UI | Structured question panel in Gurgeh: shows all clarifying questions the agent wants to ask, grouped by section, with prior Q&A visible |

---

### Pollard — 9 ideas

Pollard owns research intelligence, competitive monitoring, and landscape analysis. Ideas about pattern detection, proactive discovery, and external signal scanning land here.

| # | Idea | Concrete Feature |
|---|------|-----------------|
| 18 | Energy-aware routing | Pollard reads session timing patterns (time of day, session length) to classify "high-engagement" vs "low-engagement" windows; feeds routing hints to Bigend |
| 20 | Preference learning | Pollard builds a per-developer taste model: which research findings they acted on, which they dismissed; weights future report prominence accordingly |
| 25 | Next work suggestions | Pollard generates a daily "next work" signal: highest-priority unstarted tasks given current codebase state, competitive landscape, and sprint velocity |
| 38 | Pattern → recipes | Pollard's pattern hunter: detects recurring task sequences in interstat/session data and converts them into reusable task templates (stored as C4 curated knowledge) |
| 39 | Time-aware suggestions | Pollard surfaces suggestions based on time context: Monday morning = sprint planning prompts; Friday afternoon = wrap-up/cleanup tasks |
| 44 | Proactive alternatives | Pollard pre-explores alternative technical approaches for likely upcoming tasks; stored speculatively, surfaced when task begins |
| 45 | Proactive exploration | Pollard's "ambient scout" mode: runs background hunters on areas adjacent to current sprint work; surfaces discoveries as interject messages |
| 27 | SRS memory review | Pollard (via interkasten or standalone): periodic review prompt surfacing stale agent memories or pattern-recipe entries that need validation |
| 41 | Wrapped summary | `pollard report --wrapped` command: generates a Spotify-Wrapped-style annual/monthly summary of agent usage, productivity patterns, code areas touched |

---

### Out of Scope — 8 ideas

| # | Idea | Reason |
|---|------|--------|
| 3 | Slash command familiarity | Cosmetic usage frequency overlay on command picker — low signal, not worth the UX complexity; Autarch's commands are already discoverable via `/help` |
| 4 | Desktop peripheral controller | Hardware peripheral (game controller with screen) — pure hardware R&D, outside software scope |
| 16 | Mobile tap UI | Deferred; requires separate mobile-native surface; web approval endpoint is the correct approach if priority increases |
| 23 | Auto shortcuts | System-generated keyboard shortcuts based on usage — conflicts with Autarch's explicit keybinding philosophy; too many surprise bindings break muscle memory |
| 28 | Auto shortcuts + learning | Same as 23, with gamified teaching — doubly out of scope |
| 32 | Coding as game | "Failed deploy = pwned" gamification — entertainment theater, produces no evidence, conflicts with PHILOSOPHY.md's receipt-first stance |
| 34 | Victory celebrations | Cosmetic celebrations on task success — see gamification section below |
| 35 | Critical hits | Random bonus events — see gamification section below |
| 50 | Cross-company leaderboard | Requires anonymized cross-org telemetry and centralized collection — privacy and trust model not established; deferred |

---

## 2. Slash Command Candidates

Ideas that map cleanly to new slash commands in the existing CLI (addable to the `/` picker immediately):

| Slash Command | Tool | What It Does |
|---------------|------|-------------|
| `/discoveries` | Gurgeh | Shows findings surfaced during spec research — APIs, constraints, surprises (#40) |
| `/next` | Pollard | Displays Pollard's next-work suggestions ranked by priority (#25, #39) |
| `/lens <mode>` | Bigend | Switches agent view lens: `convo`, `edits`, `files`, `cost`, `timeline`, `decisions` (#15) |
| `/explore N` | Coldwine | Launches N parallel runs with divergent approaches (#17) |
| `/wrapped` | Pollard | Generates wrapped summary report for current month/year (#41) |
| `/compass` | Coldwine | Shows drift score: how far current sprint has deviated from spec scope (#8) |
| `/queue` | Bigend | Opens the notification/task queue panel (#24, #13) |

That's 7 slash command candidates, all implementable within the existing `/` fuzzy picker architecture.

---

## 3. Dashboard Ideas: TUI vs Web

| # | Idea | TUI | Web | Notes |
|---|------|-----|-----|-------|
| 1 | Tok/s waveform | Sparkline (braille chars) | SVG chart | Braille sparkline is idiomatic TUI; web gets full SVG |
| 2 | Frame colors | Border color on agent card | Card border via Tailwind | Both surfaces already support color; trivial |
| 7 | Rearview mirror | Sidebar panel | Sticky sidebar widget | TUI: toggle with `Ctrl+B`; Web: persistent right column |
| 9 | Smart progress bars | `[=====>    ] 67% ETA 4m` | Animated progress bar | TUI is simpler and sufficient; web adds animation |
| 11 | ETA forecasts | Column in agent list | Card footer | Same data, different layout |
| 12 | Spatial overview | Grid tiles (needs 120+ cols) | Card grid with drag | Web is the better surface for spatial layout; TUI grid is fallback |
| 14 | Breadcrumb trail | Status line per agent | Inline path component | TUI can fit 3-4 crumbs per line; web shows full trail |
| 15 | Lens switching | Tab row in detail pane | Tab bar in modal | Both work; TUI uses number keys 1-6 |
| 19 | Agent dashboard | Primary TUI view | Primary web view | Both — this IS Bigend's main surface |
| 24 | Notification queue | `?` key overlay panel | Bell icon drawer | TUI overlay is idiomatic; web gets persistent drawer |
| 36 | Agent location map | ASCII project×agent table | Interactive file tree heatmap | Web significantly better for spatial map; TUI is text table fallback |
| 37 | Passive toggles | Status bar toggle strip | Toggle switches in settings bar | TUI: bottom-of-screen F-key strip; Web: sticky bottom bar |
| 41 | Wrapped summary | Paginated TUI report | Full HTML report | Both, but web shines for data-rich annual summary |
| 42 | Side-by-side diff | Split pane (`|` divider) | Side-by-side columns | TUI split pane already exists in Coldwine; web adds diff highlighting |
| 49 | Leaderboard | Table view | Sortable table with charts | Web much better; TUI is a fallback text table |

**Key finding:** 12 of these dashboard ideas are fully viable in TUI. 3 (spatial map, leaderboard, wrapped summary) strongly prefer web for layout reasons. None exclusively requires web — but the web layer unlocks richer visualization for spatial and chart-heavy ideas.

---

## 4. Agent Preference Learning and Proactive Suggestion as Autarch Features

These warrant dedicated treatment because they form a system, not isolated features.

### Preference Learning (ideas 20, 38, 43)

The underlying mechanism is a **C3 Learned Preferences** store (per PHILOSOPHY.md memory taxonomy) that each tool writes to and reads from:

**Data sources:**
- Which Gurgeh PRD decisions the user accepted vs rejected (43)
- Which Pollard research findings they acted on vs dismissed (20)
- Which Coldwine parallel exploration branches they selected (17, 22)
- Which compaction rules they customized (29)

**Where it lives:** Plugin-local per PHILOSOPHY.md C3 decision — `~/.config/autarch/preferences.db` (SQLite). Not kernel state. Each tool reads its own slice.

**What it produces:**
- Gurgeh: front-loads calibration questions on topics where preferences are uncertain (43)
- Pollard: re-weights report sections by inferred interest (20)
- Coldwine: pre-selects default branch strategy for parallel exploration (22)
- Bigend: auto-configures lens on agent detail view to the user's most-used lens

**Closed-loop requirement (PHILOSOPHY.md):** Every preference prediction must record the actual outcome. `preferences.db` schema needs: `prediction`, `actual`, `timestamp`. Calibrate periodically via `autarch prefs calibrate`.

### Proactive Suggestion (ideas 25, 44, 45, 48)

These form a **Proactive Agent Layer** that runs alongside the user's active session:

| Idea | Mechanism | Output Surface |
|------|-----------|---------------|
| 25 (next work) | Pollard reads sprint state + velocity → ranks unstarted tasks | `/next` command + Bigend sidebar widget |
| 44 (proactive alternatives) | Pollard pre-explores likely upcoming tasks in background | Delivered as interject messages when task starts |
| 45 (ambient scout) | Pollard runs adjacent-area hunters during idle periods | `/discoveries` command + Pollard report |
| 48 (speculative queue) | Coldwine pre-stages agent context for top `/next` items | "Ready" indicator on queued tasks in Bigend |

**Implementation note:** Ideas 44 and 48 share a pre-warming mechanism — Pollard identifies likely next tasks (44), Coldwine pre-stages context for them (48). These should be designed together as a single `pre-warm` pipeline. The hook point is session idle detection (already exists in Interspect's canary monitoring).

---

## 5. Cross-Tool Coordination Requirements

Some ideas require signal flow across tools. These are not implementable within a single tool.

| Idea | Signal | From | To | Channel |
|------|--------|------|----|---------|
| 8 (compass) | Spec scope | Gurgeh | Coldwine | Intermute: `SpecUpdated` event → drift scorer reads current spec |
| 9 (smart progress) | Historical phase actuals | interstat | Bigend progress bar | `calibrate-phase-costs` output file; Bigend reads at render time |
| 11 (ETA) | Phase completion times | Coldwine runs | Bigend display | Intermute: `PhaseCompleted` event with duration; Bigend aggregates |
| 14 (breadcrumbs) | Tool call events | Coldwine/agent | Bigend | Intermute: `ToolUsed` event stream; Bigend subscribes |
| 18 (energy routing) | Session timing | Pollard | Bigend dispatch | Pollard writes `energy_level` to C3 prefs; Bigend reads before routing |
| 25 (next work) | Sprint state + velocity | Coldwine | Pollard | Coldwine writes `sprint_summary` event; Pollard subscribes |
| 44 (proactive alternatives) | Likely next tasks | Pollard | Coldwine pre-warm | Pollard writes speculative task list; Coldwine reads and pre-stages |
| 48 (speculative queue) | Pre-warmed contexts | Coldwine | Bigend queue display | Coldwine writes `context_ready` state; Bigend shows "ready" badge |

**Intermute is the right bus for all of these** — REST + WebSocket is already the designated cross-tool coordination channel. No new infrastructure needed; these are new event types on the existing bus.

**New Intermute event types needed:**
- `SpecScopeUpdated` (Gurgeh → Coldwine)
- `ToolUsed` (agent → Bigend, for breadcrumbs)
- `EnergyLevelUpdated` (Pollard → Bigend)
- `SpeculativeTasksReady` (Pollard → Coldwine)
- `ContextPreWarmed` (Coldwine → Bigend)

---

## 6. Gamification / Cosmetic Ideas: Scope Decision

**Ideas in question:** 32 (coding as game), 33 (agent teaches/quizzes), 34 (victory celebrations), 35 (critical hits), 41 (wrapped summary), 49 (company leaderboard)

### Hard exclude

- **32 (coding as game / "failed deploy = pwned"):** Pure theater. Reframes real outcomes as game events without producing evidence. Conflicts directly with "receipts, not narratives" in PHILOSOPHY.md. Out of scope.
- **35 (critical hits):** Random bonus events. Adds noise to a system that runs on signal quality. Out of scope.

### Include as evidence-producing features (not cosmetics)

- **34 (victory celebrations):** Exclude the theatrical animation. Include a genuine "sprint closed" summary: what was accomplished, cost, duration, model performance. This is a receipt that earns authority — it's just also pleasant to receive. The summary IS the celebration.
- **33 (agent teaches/quizzes):** Reframe as "rationale mode" in Gurgeh. Agent explains each PRD decision; user confirms/challenges. Every challenge is a preference signal written to C3. This is functional, not cosmetic — it closes the learning loop.
- **41 (wrapped summary):** Include. `pollard report --wrapped` is an evidence artifact — it's the calibration view of the entire learning flywheel over a period. The Spotify framing is cosmetic; the data content is a receipt.
- **49 (company leaderboard):** Include as an opt-in interstat-derived metric table. Signal value: identifies over-indexed developers, under-utilized capacity, and cost distribution. Leaderboard framing is cosmetic; the underlying analytics are actionable.

### Conditional include

- **28 (auto shortcuts + learning):** The "auto-generate" part is out of scope (conflicts with explicit keybinding philosophy). The "teach users shortcuts they haven't discovered" part — a `/shortcuts` command that shows personalized underused shortcuts — is worth doing as a discoverability feature, not a gamification feature.

### Summary table

| # | Decision | Reason |
|---|----------|--------|
| 32 | **Exclude** | No evidence produced; pure theater |
| 33 | **Include** (as rationale mode) | Closes preference learning loop |
| 34 | **Include** (as sprint receipt) | Receipt, not celebration |
| 35 | **Exclude** | Random noise in a signal-quality system |
| 41 | **Include** (as evidence artifact) | Calibration view of the learning flywheel |
| 49 | **Include** (opt-in, analytics framing) | Actionable capacity and cost data |
| 50 | **Defer** | Requires cross-org privacy model |

---

## 7. Priority Ranking: Top 10 Features by Impact/Effort

For sequencing purposes, ordered by highest signal value per implementation cost:

| Rank | # | Feature | Tool | Why |
|------|---|---------|------|-----|
| 1 | 15 | Lens switching | Bigend | Immediate productivity win; same data, multiple read angles; low effort |
| 2 | 13 | Task queue | Coldwine/Bigend | Core to the dispatch model; high daily utility |
| 3 | 11 | ETA forecasts | Bigend | Closes OODARC loop on estimates; data already in interstat |
| 4 | 24 | Notification queue | Bigend | Unblocks agents faster; reduces manual polling |
| 5 | 25 | Next work suggestions | Pollard | Highest-leverage proactive feature; feeds the daily workflow |
| 6 | 8 | Compass (drift score) | Coldwine | Prevents spec drift silently; high quality signal |
| 7 | 14 | Breadcrumb trail | Bigend | Low effort on Intermute event stream; high observability win |
| 8 | 43 | Proactive pref calibration | Gurgeh | Systematizes what good PRD intake looks like |
| 9 | 20 | Preference learning | Pollard | Foundation for the entire proactive layer |
| 10 | 47 | A/B split pane | Coldwine | Model routing calibration data generator; pairs with interspect |

---

## Appendix: Full 50-Idea Quick-Reference

| # | Idea | Tool | Status |
|---|------|------|--------|
| 1 | Waveform tok/s | Bigend | Include |
| 2 | Frame colors | Bigend | Include |
| 3 | Slash command familiarity | — | Out of scope |
| 4 | Desktop peripheral | — | Out of scope (hardware) |
| 5 | Game-style controls | Coldwine | Include |
| 6 | Codebase visit frequency | Gurgeh | Include |
| 7 | Rearview mirror | Bigend | Include |
| 8 | Compass | Coldwine | Include |
| 9 | Smart progress bars | Bigend | Include |
| 10 | Central task dispatch | Bigend | Include (core) |
| 11 | ETA forecasts | Bigend | Include |
| 12 | Spatial agent overview | Bigend | Include |
| 13 | Task queue | Coldwine/Bigend | Include |
| 14 | Breadcrumb trail | Bigend | Include |
| 15 | Lens switching | Bigend | Include |
| 16 | Mobile tap UI | Bigend (web) | Deferred |
| 17 | Parallel exploration | Coldwine | Include |
| 18 | Energy-aware routing | Pollard | Include |
| 19 | Agent dashboard | Bigend | Include (core) |
| 20 | Preference learning | Pollard | Include |
| 21 | Agent skill tracking | Gurgeh | Include |
| 22 | Multi-path pick | Coldwine | Include |
| 23 | Auto shortcuts | — | Out of scope |
| 24 | Notification queue | Bigend | Include |
| 25 | Next work suggestions | Pollard | Include |
| 26 | Drag permission levels | Coldwine | Include |
| 27 | SRS memory review | Pollard | Include |
| 28 | Auto shortcuts + learning | — | Out of scope (auto-gen part) |
| 29 | Edit compaction rules | Coldwine | Include |
| 30 | Arrow key detail toggle | Bigend | Include |
| 31 | Rolling context window | Coldwine | Include |
| 32 | Coding as game | — | Exclude |
| 33 | Agent teaches/quizzes | Gurgeh | Include (as rationale mode) |
| 34 | Victory celebrations | Bigend/Coldwine | Include (as sprint receipt) |
| 35 | Critical hits | — | Exclude |
| 36 | Agent location map | Bigend | Include |
| 37 | Passive toggles | Bigend | Include |
| 38 | Pattern → recipes | Pollard | Include |
| 39 | Time-aware suggestions | Pollard | Include |
| 40 | /treasures discoveries | Gurgeh | Include |
| 41 | Wrapped summary | Pollard | Include (as evidence artifact) |
| 42 | Side-by-side alternatives | Coldwine | Include |
| 43 | Proactive pref calibration | Gurgeh | Include |
| 44 | Proactive alternatives | Pollard | Include |
| 45 | Proactive exploration | Pollard | Include |
| 46 | Interview question UI | Gurgeh | Include |
| 47 | A/B split pane | Coldwine | Include |
| 48 | Speculative queue | Coldwine | Include |
| 49 | Company leaderboard | Bigend | Include (opt-in, analytics) |
| 50 | Cross-company leaderboard | — | Defer (privacy model needed) |

**Totals:** Bigend: 17 | Coldwine: 10 | Gurgeh: 6 | Pollard: 9 | Out of scope: 5 | Deferred: 3
