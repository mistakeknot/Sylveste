---
artifact_type: brainstorm
bead: sylveste-4ct0
stage: discover
resolution: down-scoped-to-A
review: docs/research/flux-drive/2026-04-27-clavain-peer-coexistence-brainstorm/SYNTHESIS.md
---

# Clavain Peer-Coexistence — Brainstorm

> **Resolution (2026-04-27):** Initial scope was C′ (full rig manager, ~1.5–2 weeks). Brainstorm review (1 P0, 7 P1) found strong cross-track convergence (3/3 reviewers) that the multi-rig assumption is unevidenced and six of eight C′ pieces are not load-bearing for the actual coworker problem. **Down-scoped to A (~1–2 days).** Follow-up beads filed for B′ and C′ gated on observed multi-rig telemetry. The mod-manager analogy and patterns are preserved as design references for when evidence justifies expansion.

## Down-Scoped Plan (A)

1. Reclassify `os/Clavain/agent-rig.json` — split `conflicts` into `hard-conflicts` (true duplicates: `code-review@official`, etc.) and `peers` (alt rigs: `superpowers@superpowers-marketplace`, `compound-engineering@every-marketplace`, `gsd@<marketplace>`). Reason field stays for documentation.
2. Modify `os/Clavain/scripts/modpack-install.sh` `process_category()` so the `peers` category never auto-disables. Default to detect-and-report; mutation requires `--apply` flag (or interactive confirmation in `/clavain:setup`).
3. Add bridge skills as pure documentation (no runtime behavior): `os/Clavain/skills/interop-with-superpowers/SKILL.md` and `os/Clavain/skills/interop-with-gsd/SKILL.md`. Map vocabulary across rigs (`/clavain:write-plan` ≈ `/gsd:plan` ≈ `/superpowers:write-plan`).
4. Add `os/Clavain/commands/peers.md` (`/clavain:peers`) — read-only viewer. Lists detected peer rigs, recommended interop reading, current resolution. No mutation.
5. Soften the `AGENTS.md` Beads integration block (lever 6 from initial proposal) from absolute prohibition to project-scoped canonicalization. **Punted to follow-up** unless trivial during implementation.
6. Add ~50 lines of telemetry: log which `using-*` skill won the routing decision per session (to `~/.clavain/peer-telemetry.jsonl` or via interspect). This is the gate for any future B′/C′ work — without it, per-skill priority defaults are designed in the dark.

The four pieces (1–4) directly fix the three named failure modes (auto-disable / competing using-* / vocab mismatch). Telemetry (6) closes the evidence gap that blocked C′. AGENTS.md softening (5) is bonus if cheap.

## Original Brainstorm (preserved for reference)


## What We're Building

A reframe of Clavain from "**successor to superpowers / compound-engineering**" into "**rig manager for the user's Claude Code stack**." A coworker who already uses superpowers, GSD, or any other agent-rig should be able to install Clavain and have *all* their rigs functional, with explicit (not silent) resolution of overlaps and a profile-based way to declare which rig leads in any given session.

Concretely, by end of this work:
- `os/Clavain/agent-rig.json` distinguishes `hard-conflicts` (true duplicates like `code-review@official`) from `peers` (alt rigs: superpowers, GSD, compound-engineering, future entrants).
- `/clavain:setup` defaults to detect-and-report; `--apply` is required to mutate. Peer rigs are never auto-disabled — `claude plugin disable` only runs against hard-conflicts and only on explicit confirmation.
- A `peers.yaml` registry (community-maintained, refreshed via `upstream-sync`) lists detection rules, recommended bridge skill, and known sharp edges per peer rig.
- Profiles (`companion` / `primary` / `off`) replace a single `CLAVAIN_COMPANION_MODE` env var. Saveable, listable, switchable: `clavain rig profile use companion`.
- Per-skill priority resolution via `~/.clavain/peer-priorities.yaml` — per-skill, not per-plugin. Mod-manager pattern (Vortex).
- `agent-rig.lock.json` lockfile — pins the exact set of plugins + versions + active profile + peer-priorities for reproducible team onboarding.
- `clavain rig` CLI surface: `profile`, `install <lockfile>`, `export`, `peers`. Read-only inspection (`/clavain:peers`) plus state mutation through explicit subcommands.
- Bridge skills (`interop-with-superpowers`, `interop-with-gsd`) document vocab mapping (e.g., `/gsd:plan` ≈ `/clavain:write-plan`).
- `using-clavain` SKILL.md becomes peer-aware: when a peer's `using-*` skill is loaded, demote "Proactive skill invocation is required" to advisory.

## Why This Approach (mod-manager analogy)

The Skyrim/Stellaris modding ecosystem spent 15+ years on the same structural problem: two systems want to overwrite the same surface, and the user wants both. Patterns that map directly:

| Mod-manager pattern | Source | Clavain mapping |
|---|---|---|
| Virtual file system / non-destructive layering | Mod Organizer 2 | Stop mutating `~/.claude/settings.json`; resolve at runtime |
| Profiles / Playsets | MO2, Paradox Mod Launcher | `companion` / `primary` / `off` profiles, switchable |
| Masterlist (community metadata) | LOOT | `peers.yaml` registry, refreshed via `upstream-sync` |
| Conflict viewer | MO2, Paradox | `/clavain:peers` read-only inspection |
| Per-file resolution | Vortex | Per-skill priority resolution |
| Lockfile / reproducible install | Wabbajack | `agent-rig.lock.json` |
| Compatibility patches | xEdit, Irony Mod Manager | Bridge skills |
| Detection-not-prescription | LOOT | Recommended config informational; enforcement opt-in |

The deeper shift: **Clavain becomes a rig manager for Claude Code, not a rig that competes with peers.** This aligns with Sylveste's existing principle ("adopt mature tools, don't rebuild") applied recursively — don't rebuild superpowers; manage it alongside Clavain.

The current `/clavain:setup` auto-disable is the equivalent of a mod manager *deleting* mods it considers superseded. No serious mod manager does this. The whole industry settled on overlay-without-mutation 10+ years ago.

## Key Decisions

1. **C′ selected** — full rig-manager scope, ~1.5–2 weeks. Higher payoff than B′ (rig-manager-lite) and aligns with the likely-generalized future where every Claude Code user has multiple rigs (superpowers, GSD, agent-os, claude-md-management, etc.).
2. **Skills are namespaced per-plugin in Claude Code.** The original 6-lever proposal included renaming Clavain's vendored superpowers skills under a `clavain-` prefix. This is **dropped** — Claude Code's plugin model already namespaces skills (`clavain:executing-plans`, `intertest:systematic-debugging`). No skill-name collision exists at runtime.
3. **The real failure modes** are: (A) `/clavain:setup` silently disabling peer plugins, (B) competing `using-*` SKILL.md headers both demanding "Proactive skill invocation," (C) methodology vocab mismatch (`/clavain:write-plan` vs `/gsd:plan` vs `/superpowers:write-plan`).
4. **Profiles, not env vars.** A `CLAVAIN_COMPANION_MODE=1` flag is one-shot; profiles are saveable, listable, shareable, and naturally extend to future modes (`review-only`, `brainstorm-only`, `minimal`).
5. **Per-skill priority, not per-plugin.** When superpowers and Clavain both ship `dispatching-parallel-agents`, the user should be able to say "let superpowers' version win for that skill, but Clavain's `using-clavain` wins for routing." Per-plugin priority is too coarse.
6. **Lockfile dovetails with existing `agent-rig.json` schema.** No new format — just a sibling file with the resolved set + versions + profile + priorities.
7. **Detection-not-prescription throughout.** `agent-rig.json` already has `recommended` vs `required` semantics; this work adds `peers` (informational, never auto-acted-on) and `hard-conflicts` (action gated behind explicit confirmation).

## Failure Modes Surfaced (from mod-manager experience)

- **Silent breakage.** When MO2's VFS fails, Skyrim *appears* to work but uses fallback files — devastating debugging experience. Mitigation: every peer-aware fallback in Clavain MUST log the resolution decision; never silently demote.
- **Profile drift.** Users with 5 profiles forget which is active. Mitigation: status command and statusline always show active profile.
- **Masterlist staleness.** LOOT masterlist gets out of date. Mitigation: `peers.yaml` carries a `last-updated` timestamp; `/clavain:doctor` warns if stale >30 days.
- **Lockfile rot.** Wabbajack modlists break when upstream mods are removed. Mitigation: lockfile carries checksums; `clavain rig install <lockfile>` fails loud on missing/changed plugins with a "rehydrate" hint.
- **Two-Clavains support burden.** Companion mode could create two distinct Clavain experiences (autonomous vs quiet) that need separate testing and docs. Mitigation: profiles are the same code path with different config; bridge skills + `/clavain:peers` are added surface, not forked surface.

## Open Questions

1. **AGENTS.md beads softening (lever 6 from initial proposal).** The current `AGENTS.md` block says "do NOT use TodoWrite, TaskCreate, or markdown TODO lists" — an absolute prohibition that breaks GSD's spec-driven workflow when coworker opens Sylveste itself. Soften to project-scoped ("in this project, beads is canonical")? **Punted to follow-up bead** unless the user adds it back to scope. It's structurally separate (project-vs-user-tooling, not peer-coexistence).
2. **What does the coworker actually reach for?** Without telemetry, per-skill priorities are designed in the dark. Risk for C′. Mitigation: ship `peers.yaml` with sane defaults, expose priority overrides as user-config (`~/.clavain/peer-priorities.yaml`), and instrument which `using-*` skill won the routing decision per session for later calibration.
3. **GSD detection.** GSD ships as `jnuyens/gsd-plugin` (Claude Code packaging) and as `gsd-build/get-shit-done` (raw upstream). Detection rule needs to handle both. Confirm with first install probe.
4. **Compound-engineering still in scope?** Currently listed alongside superpowers as a "successor" claim. Same reframe applies — peer, not predecessor — but compound's public adoption seems lower than superpowers/GSD. Lower priority, but cheap to include in the same `peers.yaml` entry.
5. **Bridge skill scope.** What exactly do bridge skills DO? They could be (a) pure documentation that lives in `skills/interop-with-*/SKILL.md` and informs the model, or (b) active routing helpers that intercept natural-language requests and offer choices. Recommend (a) for V1; (b) is the cross-rig router from the rejected Approach C, deferred.
6. **Profile granularity.** Should profiles cover only "Clavain proactivity vs deference" (3 modes), or also bundle peer-priorities, enabled bridges, and which skills load (more like MO2 profiles)? Lean toward the bigger version — profiles as full rig snapshots — to maximize the lockfile/onboarding payoff.

## Alignment

Supports Clavain's purpose ("orchestration brain: disciplined workflow routing, robust review gates, dependable inter-module handoffs") by extending orchestration outward to *other* rigs the user has chosen. Reduces ambiguity for future sessions (explicit resolution beats silent disable). Reversibility built in (profiles toggle; lockfile snapshots; per-skill priorities are config-file, not code).

## Conflict / Risk

The C′ scope is meaningfully larger than originally proposed (1.5–2 weeks vs ~3 days). Risks:
- Per-skill priority design ahead of telemetry — mitigated by sane defaults + user override file.
- Profile system is new state; bugs here affect all sessions — mitigated by `off` profile being a no-op fallback.
- Lockfile schema becomes a contract — needs versioning from day one.
- Surface area expansion (3 new commands, 1 new SKILL, 2 bridge skills, 1 registry, 1 lockfile, 1 priority config) — large enough to warrant its own milestone in the v1 roadmap.

The bigger bet: positioning Clavain as a rig manager rather than a rig is a meaningful identity shift. If the bet doesn't pay off (i.e. users don't actually multi-rig), the lockfile and profiles are still useful for Sylveste-internal team onboarding. The bet is hedged.
