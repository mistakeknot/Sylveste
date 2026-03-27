# fd-theme-clustering — Agent UI Concept Analysis
**Analyst:** fd-theme-clustering (product analyst, HCI + agent interface design background)
**Date:** 2026-03-12
**Source:** Chris Barber's 50 agent UI concept explorations

---

## 1. Named Cluster Taxonomy

### Cluster A — Temporal Situational Awareness
*Ideas that give the user a real-time read on what's happening and how it's going.*

| # | Idea |
|---|------|
| 1 | Waveform showing tok/s usage over time |
| 7 | Rearview mirror — condensed recent high-level actions |
| 8 | Compass showing whether you're on track or drifting |
| 9 | Smart progress bars forecasting estimated progress to goal |
| 11 | ETA forecasts for coding agents |
| 14 | Breadcrumb trail showing agent progress at a glance |
| 36 | See where agents are and what they're working on |

**One-line description:** Widgets that surface agent momentum, drift, and trajectory at a glance without requiring the user to interrogate logs.

---

### Cluster B — Multi-Agent Spatial Command
*Ideas about orchestrating and overviewing multiple agents simultaneously.*

| # | Idea |
|---|------|
| 10 | Central task dispatch hub — send tasks, see/respond to agent requests without switching |
| 12 | Spatial overview of all agents |
| 13 | Sending tasks as adding to a queue |
| 19 | Dashboard of your agents |
| 24 | Notification queue for agents |
| 47 | A/B testing alternatives, one agent per approach, split pane view |
| 48 | Speculative queue — pre-builds most likely next requests |

**One-line description:** Command-and-control surfaces for managing a fleet of concurrent agents: dispatch, observe, prioritize, and A/B test in one place.

---

### Cluster C — Lens / View Switching
*Ideas about giving the user multiple interpretive frames over the same agent activity.*

| # | Idea |
|---|------|
| 15 | Switch "lens" for viewing agents (convo, edits, files, cost, timeline, learnings, decisions) |
| 30 | Toggle detail levels with arrow keys |
| 37 | Passive features toggleable at the bottom |
| 46 | Alternative UI for user interview questions — see prior and recent questions |

**One-line description:** First-class view-mode switching so users can pivot between what happened, what it cost, what changed, and what was decided without losing context.

---

### Cluster D — Speculative & Exploratory Execution
*Ideas about agents generating and surfacing alternatives before the user asks.*

| # | Idea |
|---|------|
| 17 | Parallel exploration mode — try multiple approaches, pick favorite |
| 22 | Explore multiple paths, help you pick |
| 42 | Agents explore alternatives, give side-by-side comparison |
| 44 | Agents proactively explore alternatives for likely next work |
| 45 | Agents proactively explore based on current work, surface discoveries |
| 48 | Speculative queue — pre-builds most likely next requests |

**One-line description:** Modes that turn the agent from a responder into an active explorer — pre-executing branches, surfacing comparisons, and reducing cold-start cost for common paths.

*Note: #48 appears in both B and D — it is a dispatch artifact (B) that is populated speculatively (D). Counted once in each.*

---

### Cluster E — Adaptive Personalization & Taste Calibration
*Ideas about the agent learning user preferences and adapting autonomously.*

| # | Idea |
|---|------|
| 20 | Agents learn your taste/preferences by domain, auto-pick high-confidence choices |
| 21 | Agents track their progress learning skills in your repo |
| 23 | Auto-generate shortcuts based on usage |
| 28 | Auto-generate shortcuts and help you learn them |
| 38 | Agent detects patterns, turns them into recipes |
| 39 | Time-aware suggestions |
| 43 | Agents identify where they don't know your prefs, proactively calibrate |

**One-line description:** Agents that build a persistent, introspectable model of the user's habits, blind spots, and preferences — and expose that model for inspection and correction.

---

### Cluster F — Gamification & Affect
*Ideas that borrow game mechanics to make agent work feel rewarding, punishing, or playful.*

| # | Idea |
|---|------|
| 4 | Desktop peripheral (video game controller) mapped to agent actions with status screen |
| 5 | Terminal agents with controls like video games |
| 32 | Coding agent as video game — failed deploy = pwned |
| 33 | Agents teach/test/quiz you about what they're doing and why |
| 34 | Victory celebrations in coding agents |
| 35 | Critical hits in coding agents |

**One-line description:** Emotional and physical engagement patterns from gaming applied to agent interaction — feedback loops, consequence, celebration, and physical controllers.

---

### Cluster G — Memory, Knowledge & Context Management
*Ideas about surfacing, editing, and reviewing what agents remember and how context is managed.*

| # | Idea |
|---|------|
| 27 | SRS/Anki memory review — agents review their memories with you |
| 29 | Edit compaction rules (e.g., keep recent messages verbatim) |
| 31 | Rolling context window with progressive compaction |
| 40 | /treasures shows discoveries |
| 41 | Claude Code / Codex wrapped (annual summary) |

**One-line description:** Tools for users to inspect, curate, and deliberately shape what agents retain — from session compaction rules to spaced-repetition review of agent memories.

---

### Cluster H — Presence, Social & Ecosystem Signals
*Ideas about visibility across users, teams, and organizations.*

| # | Idea |
|---|------|
| 49 | Agent usage leaderboards within a company |
| 50 | Agent usage leaderboards across companies |
| 18 | Energy-aware decision routing (easy decisions when low energy, hard when high) |
| 16 | Mobile UI optimized for tap approvals and voice input |
| 25 | Stream of suggested next work items |
| 26 | Click and drag boundaries to adjust permission levels |

**One-line description:** Social proof, cross-context reachability, and organizational signal layers — from leaderboards to mobile-first approval flows to human-centric routing.

*Note: #18, 16, 25, 26 are partial fits — they are grouped here because they have no better cluster and share an "ambient / peripheral interaction" quality.*

---

### Remainder: Codebase Intelligence
*Ideas about spatial/frequency mapping of where agents and humans work in the codebase.*

| # | Idea |
|---|------|
| 3 | See at a glance how familiar you are with different slash commands |
| 6 | Visualize how often you visit different parts of the codebase |
| 2 | Terminal frames with color to indicate health/state |

**One-line description:** Heatmap-style spatial awareness of codebase regions, command familiarity, and terminal health states.

*These three form a thin 9th cluster (Codebase Cartography). Kept separate because they are more about user-code navigation than agent-user interaction. See Outliers section.*

---

## 2. Density Ranking — Themes Barber Returned To Most

| Rank | Cluster | Idea Count | Signal |
|------|---------|-----------|--------|
| 1 | D — Speculative & Exploratory Execution | 6 (7 with shared #48) | Barber is clearly preoccupied with agents that act ahead of the user — this is the dominant creative bet |
| 2 | E — Adaptive Personalization & Taste | 7 | Near-equal weight — the "agent that knows you" arc is a parallel obsession |
| 3 | A — Temporal Situational Awareness | 7 | Also 7 items, but more varied in modality — less tightly coupled as a design space |
| 4 | B — Multi-Agent Spatial Command | 7 (8 with shared #48) | Fleet orchestration features appear across many different entry points |
| 5 | F — Gamification & Affect | 6 | Strong subcategory — physical peripherals + game feedback loops, unusual in terminal contexts |
| 6 | G — Memory, Knowledge & Context | 5 | Compact but high-signal; SRS + compaction rules are unusually specific |
| 7 | C — Lens / View Switching | 4 | Foundational UX primitive, low idea count but high architectural weight |
| 8 | H — Presence, Social & Ecosystem | 6 | Scatter cluster — leaderboards are outliers; the rest are cross-context interaction |

**Barber's dominant preoccupation:** Agents that anticipate, explore ahead, and calibrate autonomously (clusters D + E together = 13 distinct ideas). This is both the most differentiated and hardest-to-implement cluster group.

---

## 3. Cross-Reference to Sylveste Layers

| Cluster | Primary Layer | Secondary Layer | Notes |
|---------|--------------|-----------------|-------|
| A — Temporal Situational Awareness | **Masaq** | Skaffen (data source) | Waveform, progress bars, ETA, breadcrumbs — all pure rendering components. Skaffen emits events; Masaq renders them. |
| B — Multi-Agent Spatial Command | **Autarch** (Bigend/Pollard tools) | Skaffen (per-agent runtime), Masaq (layout) | Fleet dispatch requires Autarch's orchestration layer. Individual agent status is Skaffen-side. |
| C — Lens / View Switching | **Masaq** | Skaffen (evidence events feed lenses) | View switching is a Masaq primitive; data for each lens comes from Skaffen's evidence JSONL stream. |
| D — Speculative & Exploratory | **Skaffen** + **Autarch** | Masaq (comparison UI) | Parallel branch execution is Skaffen's OODARC engine. Fleet coordination of branches is Autarch. Comparison display is Masaq. Full-stack feature. |
| E — Adaptive Personalization | **Skaffen** | Masaq (calibration UI) | Taste modeling, SRS of prefs, pattern-to-recipe — all Skaffen session/memory layer. Calibration dialogs could be Masaq components. |
| F — Gamification & Affect | **Masaq** | Skaffen (event triggers) | Celebration, critical hits, health color coding — rendering-only. Skaffen emits events (build pass, deploy fail); Masaq animates them. |
| G — Memory & Context | **Skaffen** | Masaq (compaction UI) | Compaction rules, rolling context, memory review — Skaffen's session package owns this. Masaq could surface `/treasures` and the SRS review UI. |
| H — Presence & Social | **Autarch** / cross-cutting | Masaq (leaderboard display), Intercore (event routing) | Leaderboards need cross-project telemetry — Autarch + Intercore. Mobile UI is entirely out-of-scope for terminal-first. |

---

## 4. "Quick Win" Cluster — Masaq-Only, Shippable Together

**Cluster: Masaq Signal Pack** (A + C + F rendering subset)

These ideas require no new Skaffen behavior — they consume events already emitted and render them:

| # | Idea | Masaq Component Shape |
|---|------|-----------------------|
| 1 | Waveform tok/s | `waveform` widget: sparkline over token usage events |
| 2 | Terminal frames with color | `frame-state` wrapper: border color from agent health enum |
| 7 | Rearview mirror | `rearview` widget: last N high-level action summaries |
| 9 | Smart progress bars | Extension of existing `viewport` — add ETA annotation |
| 11 | ETA forecasts | `eta` widget: linear regression on step completion timestamps |
| 14 | Breadcrumb trail | `breadcrumb` widget: phase trail from evidence JSONL |
| 15 | Lens switching | `lens-bar` component: tab strip + keybind-driven view swap |
| 30 | Toggle detail levels | Arrow key handler + verbosity enum in existing viewport |
| 34 | Victory celebrations | `confetti` or brief lipgloss animation on build-pass event |
| 35 | Critical hits | `hit-flash` overlay on tool success with high impact score |
| 37 | Passive toggles at bottom | `status-bar` extension: toggle row for optional passive widgets |
| 40 | /treasures | `discoveries` pane: filtered evidence view for `type=discovery` events |

**Shipping rationale:** All twelve components depend only on Skaffen's existing evidence event stream (already JSONL-written by `internal/evidence/`). No new Skaffen APIs needed. These can ship as a Masaq minor release and get pulled into Skaffen's TUI via the existing local replace directive.

**Recommended first three:** #2 (frame-state), #30 (detail toggle), #15 (lens-bar) — they compose as a foundation for everything else in this pack.

---

## 5. "Strategic Cluster" — Most Differentiating vs GUI Competitors

**Cluster D — Speculative & Exploratory Execution** is the strategic bet.

**Why this wins in a terminal-first OS:**

GUI competitors (Cursor, Devin, GitHub Copilot Workspace) all operate on a request-response model. The user asks; the agent responds. Parallelism is either hidden (background indexing) or manual (multiple tabs).

Clusters D + E together define a qualitatively different posture: **the agent as co-pilot that explores ahead of the user's request**. This is executable in Skaffen's OODARC engine today because:

1. The `agentloop` is already phase-agnostic and can be instantiated multiple times per session
2. The `brainstorm` phase is already separated from `build` — speculative runs can be brainstorm-only with no side effects
3. Autarch's Gurgeh and Pollard tools are positioned for multi-strategy work

**Specific differentiators:**

| # | Idea | Why it's a moat |
|---|------|----------------|
| 17 | Parallel exploration mode | GUI tools do this one-at-a-time; terminal-first can show diff panes natively |
| 44 | Proactive exploration of likely next work | Turns idle compute into pre-fetched answers; no GUI competitor does this |
| 45 | Surface discoveries from current work | Makes the agent a researcher, not a responder |
| 43 | Proactive preference calibration | Agents that ask the right questions before they need to guess |
| 48 | Speculative queue | Pre-builds likely requests; radical latency reduction |

**Implementation path:** Start with #17 (parallel exploration mode) as a Skaffen `--parallel N` flag that spawns N brainstorm-phase agentloops concurrently. Then surface the comparison via a Masaq `split-pane` component. This is a single sprint worth of Skaffen work plus one Masaq component.

---

## 6. Outliers — Ideas That Don't Fit Cleanly

| # | Idea | Why it's an outlier |
|---|------|-------------------|
| 3 | Familiarity with slash commands | This is about the human's command mastery, not agent behavior. Closer to a CLI help system feature than an agent UI concept. |
| 4 | Video game controller peripheral | Hardware/HID integration with no plausible terminal path. Interesting as a concept for a dedicated Autarch desktop app; not applicable to TUI. |
| 16 | Mobile UI for tap approvals / voice | Mobile-first UX is orthogonal to terminal-first design. Could be an Autarch companion app (Pollard tool?), but it's a separate surface entirely. |
| 18 | Energy-aware decision routing | Human energy state detection is unimplemented science (requires biometric input). The routing outcome is interesting; the sensing mechanism has no obvious implementation path. |
| 32 | Coding agent as video game | The "failed deploy = pwned" framing is too gamified to be a shipping feature without major tonal risk. It could inform micro-interactions (F cluster) without literally being realized. |
| 49/50 | Leaderboards within/across companies | These are B2B social features that require cross-tenant telemetry infrastructure. Out of scope for Sylveste's current architecture and potentially privacy-hostile. |

---

## 7. Effort vs Terminal-Fit Grid

```
HIGH TERMINAL FIT
        |
        |  C (Lens/View)     A (Temporal
        |  [low effort,      Awareness)
        |   high fit]        [low-med effort,
        |                    high fit]
        |
        |  G (Memory/        D (Speculative
        |  Context)          Execution)
        |  [med effort,      [high effort,
        |   high fit]        high fit — STRATEGIC]
        |
  LOW   |                                HIGH
  EFFORT|________________________________ EFFORT
        |
        |  E (Personalization B (Multi-Agent
        |  & Taste)           Command)
        |  [high effort,      [high effort,
        |   med fit —         med-high fit]
        |   requires session
        |   memory work]     F (Gamification)
        |                    [med effort,
        |                    med fit — terminal
        |                    animations viable;
        |                    controllers not]
        |
        |  H (Social/         [Outliers: 4,16,18,
        |  Ecosystem)         49,50 — low terminal
        |  [high effort,      fit regardless of
        |   low fit]          effort]
        |
LOW TERMINAL FIT
```

### Grid Summary Table

| Cluster | Effort | Terminal Fit | Verdict |
|---------|--------|--------------|---------|
| C — Lens/View Switching | Low | Very High | Ship first |
| A — Temporal Situational Awareness | Low-Med | Very High | Ship as Masaq pack |
| G — Memory & Context | Med | High | Skaffen sprint |
| F — Gamification (TUI subset) | Med | Med-High | Ship micro-interactions only |
| B — Multi-Agent Command | High | High | Autarch roadmap |
| D — Speculative Execution | High | High | Strategic investment |
| E — Adaptive Personalization | High | Med | Requires session memory infrastructure first |
| H — Social / Ecosystem | High | Low | Backlog / separate product |
| Outliers (4, 16, 18, 32, 49, 50) | Various | Low | Discard or shelve |

---

## Summary: Three-Layer Implementation Map

### Ship Now (Masaq, 1-2 sprints)
Clusters A + C + F-TUI-subset as the **Masaq Signal Pack** (12 components listed in section 4). Foundational rendering layer that makes Skaffen feel alive without touching Skaffen logic.

### Next Quarter (Skaffen, 2-3 sprints)
Cluster G (memory/context management — compaction rules, rolling window, `/treasures`) plus the first foothold of Cluster D (parallel brainstorm execution via `--parallel N`).

### Strategic Investment (Autarch + Skaffen, roadmap)
Clusters B + D together form the **speculative fleet** vision: a terminal-first multi-agent workspace where agents explore ahead, surface alternatives in split panes, and pre-build likely next work. This is the moat against GUI competitors.

### Deprioritize
Clusters E and H require cross-cutting infrastructure (persistent taste modeling, cross-tenant telemetry) that doesn't pay off until the fleet vision is delivering value. Build E after D demonstrates adoption; deprioritize H indefinitely.
