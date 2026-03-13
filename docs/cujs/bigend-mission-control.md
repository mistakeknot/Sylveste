---
artifact_type: cuj
journey: bigend-mission-control
actor: regular user (developer managing multiple projects)
criticality: p2
bead: Demarch-2c7
---

# Bigend Multi-Project Mission Control

## Why This Journey Matters

A developer working across multiple projects (or a large monorepo with sub-projects) needs a unified view: what's the status of each project's sprint, which agents are active where, what beads need attention, what's the token spend. Without Bigend, this means hopping between terminal tabs, running `bd list` in each project, and mentally aggregating.

Bigend is the meta-dashboard — it doesn't do the work itself but shows the state of all work across all projects. It's the first thing the developer opens in the morning and the last thing they check before EOD. If it's stale, slow, or cluttered, the developer stops using it and reverts to manual tab-hopping.

## The Journey

The developer starts Bigend via the Autarch TUI (`./dev autarch tui`) or the web interface (`go run ./cmd/bigend`). The onboarding flow detects registered projects — each sub-project in the monorepo, plus any external projects with Clavain configured.

The dashboard shows a grid: one card per project. Each card displays active agents (count + status), open beads (count + top priority), sprint status (active/idle), and token spend (today/week). Cards are color-coded — green for healthy, yellow for attention needed, red for failures.

The developer clicks into a project card to see details: the full beads list, agent activity timeline, recent dispatches, and sprint progress. They can trigger actions from here — claim a bead, dispatch to an agent, pause a sprint — without switching to that project's terminal.

The Mycroft tab shows fleet-level orchestration: which projects have active Mycroft instances, what tier each is at, recent dispatch decisions. This is the "mayor's office" view — cross-project coordination.

For the TUI mode (`--inline`), Bigend preserves scrollback and works within the existing terminal session. For the web mode, it uses htmx + Tailwind for a responsive dashboard that auto-refreshes.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Dashboard loads all projects within 3 seconds | measurable | Time from start to full render ≤ 3s |
| Project status matches reality (beads, agents, sprints) | measurable | Status matches `bd list` + `intermux` output |
| Cross-project actions work (claim, dispatch, pause) | measurable | Action taken in Bigend reflected in target project |
| Web mode auto-refreshes without manual reload | observable | Dashboard updates within refresh interval |
| TUI mode works in inline and fullscreen | measurable | Both `--inline` and default modes render correctly |
| Developer's morning standup takes <2 minutes with Bigend | qualitative | Self-reported time reduction |

## Known Friction Points

- **Project discovery is filesystem-based** — Bigend scans for project directories. Remote projects or non-standard layouts may not be found.
- **Cross-project actions require shared infrastructure** — beads must be accessible from the Bigend process. Works in monorepo, harder across separate repos.
- **Web mode requires a running server** — not as instant as TUI. Bind-to-loopback default means no remote access without explicit opt-in.
- **No authentication on web interface** — local-only by design, but if someone binds to 0.0.0.0, there's no auth layer.
