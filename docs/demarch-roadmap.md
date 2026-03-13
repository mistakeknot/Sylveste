# Demarch Roadmap

**Modules:** `find apps os core interverse sdk -maxdepth 2 -name .git -printf '%h\n' 2>/dev/null | wc -l` | **Beads:** `bd stats` | **Last updated:** 2026-03-13
**Structure:** [`CLAUDE.md`](../CLAUDE.md)
**Machine output:** [`docs/roadmap.json`](roadmap.json) — auto-generated superset of roadmap-placed items only (fewer than `bd stats` totals, which track all beads).

---

## Now — Frontier Priorities

**P0: Intercom cutover** (iv-awny7, epic, 6 open subtasks). The only P0 epic. Rust/Postgres control-plane migration is partially complete; Node/SQLite remain authoritative for group state, task mutation, and command handling.

**P1: Infrastructure + bugs.**
- **iv-ho3** StrongDM Factory Substrate — validation-first infra for Clavain. In progress. Blocks iv-296 → iv-g36hy → iv-3ov (the measurement chain).
- **iv-v5ayb** go.mod replace directive breaks interlock/intermap in plugin cache. Quick fix: publish interbase/go as Go module.
- **iv-28vf9** Compaction recovery protocol for SessionStart hook.
- **iv-83du3** Intercom message delivery reliability (outbox + LISTEN/NOTIFY + UDS).
- **iv-6376** Kernel E9: Autarch Phase 2 — Pollard + Gurgeh migration.

**P1: Measurement hardening chain.** The path to making the north-star metric canonical:
- iv-ho3 (in progress) → iv-296 (CXDB integration) → iv-g36hy (sprint execution recording) → iv-3ov (evidence pipeline wiring)

**P2: Adaptive routing (the flywheel).**
- **iv-5ztam** Interspect adaptive routing epic — evidence-driven agent selection. 10+ subtasks including counterfactual shadow evaluation, rate limiter, meta-learning loop.
- **iv-jgdct** Apply complexity-aware routing across all subagents.

**Recently completed (since last update):**
- Track C (C1-C5) — ALL SHIPPED. Agency specs, fleet registry, composer, cross-phase handoff, self-building loop.
- iv-wie5i / iv-zsio — Discovery OS integration / discovery pipeline (consolidated, closed)
- iv-w7bh — Intermap: Project-Level Code Mapping (shipped)
- iv-t712t — First-stranger experience (README, install, setup)
- iv-r6mf — Interspect routing overrides F1-F5
- iv-b46xi — North star baseline ($1.17/landable change)

---

## Next — Strategic Themes (P2)

4 themes defining the medium-term direction. Full item inventory: [backlog.md](backlog.md).

1. **Adaptive Routing (Track B3)** — Evidence-driven agent selection, canary monitoring, counterfactual shadow evaluation. The learning loop that makes the system cheaper and better over time.

2. **Measurement Hardening** — Make the north-star metric canonical. The measurement chain unblocks the evidence pipeline that adaptive routing needs.

3. **Multi-Runtime Dispatch** — Multi-agent coordination patterns, Hermes pattern adoption. Multiple runtimes (Clavain + Skaffen) working together reliably.

4. **Developer Experience & Tooling** — Intermap code mapping, interlock coordination, Autarch TUI migration, plugin ecosystem maturity.

---

## Later — Horizon (P3)

Longer-term directions, not yet scoped into specific items. Full inventory: [backlog.md](backlog.md).

- **Kernel library bindings** — Native client bindings for intercore (blocked by intent router)
- **Continuous dispatch** — Daemon mode for always-on agent orchestration
- **Workspace isolation** — Git worktree per task for parallel safe execution
- **Runtime budget enforcement** — Real-time token budget checks mid-execution
- **Intercom maturity** — Dual-persistence retirement, memory layers, self-review loops
- **Evaluation infrastructure** — Model-capability sensitivity benchmarks, verifier context patterns

---

## Ecosystem Snapshot

| Module | Location | Version | Status | Roadmap | Open Beads (context) |
|--------|----------|---------|--------|---------|----------------------|
| agent-rig | core/agent-rig | 0.1.0 | early | no | n/a |
| autarch | apps/autarch | 0.1.0 | active | yes | n/a |
| clavain | os/clavain | 0.6.155 | active | yes | n/a |
| interband | core/interband | — | planned | no | n/a |
| interbench | core/interbench | — | planned | no | n/a |
| intercache | interverse/intercache | 0.2.0 | early | no | n/a |
| interchart | interverse/interchart | 0.1.8 | early | no | n/a |
| intercheck | interverse/intercheck | 0.2.0 | active | yes | 4 |
| intercom | apps/intercom | 1.1.0 | active | yes | n/a |
| intercore | core/intercore | — | active | yes | n/a |
| intercraft | interverse/intercraft | 0.1.2 | active | yes | 4 |
| interdeep | interverse/interdeep | 0.1.6 | early | no | n/a |
| interdev | interverse/interdev | 0.2.0 | active | yes | 4 |
| interdoc | interverse/interdoc | 5.1.2 | active | yes | 4 |
| interfluence | interverse/interfluence | 0.2.8 | active | yes | 4 |
| interflux | interverse/interflux | 0.2.36 | active | yes | n/a |
| interform | interverse/interform | 0.1.0 | active | yes | 4 |
| interject | interverse/interject | 0.1.9 | active | yes | 4 |
| interkasten | interverse/interkasten | 0.4.9 | early | no | n/a |
| interknow | interverse/interknow | 0.1.2 | early | no | n/a |
| interlearn | interverse/interlearn | 0.1.0 | active | yes | 8 |
| interleave | interverse/interleave | 0.1.1 | early | no | n/a |
| interlens | interverse/interlens | 2.2.4 | active | yes | 4 |
| interline | interverse/interline | 0.2.11 | active | yes | 4 |
| interlock | interverse/interlock | 0.2.7 | active | yes | n/a |
| intermap | interverse/intermap | 0.1.5 | active | yes | 7 |
| intermem | interverse/intermem | 0.2.3 | active | yes | n/a |
| intermonk | interverse/intermonk | 0.1.1 | early | no | n/a |
| intermute | core/intermute | — | active | yes | n/a |
| intermux | interverse/intermux | 0.1.2 | active | yes | 4 |
| intername | interverse/intername | 0.1.1 | early | no | n/a |
| internext | interverse/internext | 0.1.4 | active | yes | 4 |
| interpath | interverse/interpath | 0.3.0 | active | yes | 4 |
| interpeer | interverse/interpeer | 0.1.0 | early | no | n/a |
| interphase | interverse/interphase | 0.3.13 | active | yes | 4 |
| interplug | interverse/interplug | 0.1.0 | early | no | n/a |
| interpub | interverse/interpub | 0.1.7 | active | yes | 4 |
| interpulse | interverse/interpulse | 0.1.3 | early | no | n/a |
| interrank | interverse/interrank | 0.1.0 | early | no | n/a |
| interscribe | interverse/interscribe | 0.1.1 | early | no | n/a |
| intersearch | interverse/intersearch | 0.2.0 | active | yes | 4 |
| intersense | interverse/intersense | 0.1.0 | early | no | n/a |
| interserve | interverse/interserve | 0.1.5 | active | yes | 4 |
| intership | interverse/intership | 0.3.0 | early | no | n/a |
| intersight | interverse/intersight | 0.1.3 | early | no | n/a |
| interskill | interverse/interskill | 0.1.1 | early | no | n/a |
| interslack | interverse/interslack | 0.1.0 | active | yes | 4 |
| interspect | interverse/interspect | 0.1.6 | active | [vision](./interspect-vision.md) | n/a |
| interstat | interverse/interstat | 0.2.15 | active | yes | 4 |
| intersynth | interverse/intersynth | 0.1.6 | early | no | n/a |
| intertest | interverse/intertest | 0.1.2 | early | no | n/a |
| intertrace | interverse/intertrace | 0.1.2 | early | no | n/a |
| intertrack | interverse/intertrack | 0.1.0 | active | yes | n/a |
| intertree | interverse/intertree | 0.1.0 | early | no | n/a |
| intertrust | interverse/intertrust | 0.1.2 | early | no | n/a |
| interverse | root | — | active | yes | n/a |
| interwatch | interverse/interwatch | 0.2.0 | active | yes | 5 |
| marketplace | core/marketplace | — | active | yes | n/a |
| skaffen | os/skaffen | — | active | no | n/a |
| tldr-swinton | interverse/tldr-swinton | 0.7.17 | active | yes | n/a |
| tool-time | interverse/tool-time | 0.3.5 | active | yes | n/a |
| tuivision | interverse/tuivision | 0.1.6 | active | yes | 4 |

**Legend:** active = recent commits or active tracker items; early = manifest exists but roadmap maturity is limited. `n/a` means there is no module-local `.beads` database.

---

## Keeping Current

```
# Regenerate this roadmap JSON from current repo state
scripts/sync-roadmap-json.sh docs/roadmap.json

# Regenerate via interpath command flow (Claude Code)
/interpath:roadmap    (from Interverse root)

# Propagate items to subrepo roadmaps
/interpath:propagate  (from Interverse root)
```

---

**Moved to separate files:** Module highlights → [demarch-reference.md](demarch-reference.md). Research agenda, cross-module dependencies, modules without roadmaps → [backlog.md](backlog.md).
