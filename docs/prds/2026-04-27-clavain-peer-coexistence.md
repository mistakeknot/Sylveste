---
artifact_type: prd
bead: sylveste-4ct0
stage: design
brainstorm: docs/brainstorms/2026-04-27-clavain-peer-coexistence-brainstorm.md
review_synthesis: docs/research/flux-drive/2026-04-27-clavain-peer-coexistence-brainstorm/SYNTHESIS.md
---

# PRD: Clavain Peer-Coexistence (A scope)

## Problem

Coworkers and external users arrive with `superpowers`, `compound-engineering`, or `gsd` already installed. Today `/clavain:setup` silently runs `claude plugin disable` against those plugins because `agent-rig.json` lists them under `plugins.conflicts` with the reason "Clavain is the successor to superpowers." This silently breaks the user's existing tooling.

## Solution

Reclassify peer rigs as `peers` (informational) rather than `conflicts` (auto-disabled), make the install script detect-and-ask before any mutation, ship vocabulary-mapping bridge skills as documentation, add a read-only `/clavain:peers` viewer, and instrument which `using-*` skill wins per session so future scope decisions (B′/C′) are evidence-driven rather than speculative.

## CUJ — Coworker installs Clavain alongside superpowers

1. Coworker has `superpowers@superpowers-marketplace` installed and active.
2. Coworker runs `claude plugin install clavain@interagency-marketplace` then `/clavain:setup`.
3. `/clavain:setup` detects `superpowers` is installed and active.
4. Setup displays: "Detected peer rig: superpowers. Clavain shares vocabulary with this rig but does not replace it. See `/clavain:peers` for the methodology mapping. Both rigs will remain active." No mutation.
5. Setup completes. `claude plugin list` still shows `superpowers` enabled.
6. Coworker types `/superpowers:write-plan` — works exactly as before. Coworker types `/clavain:write-plan` — works as before. No conflict, no surprise.
7. Coworker runs `/clavain:peers` later — sees the bridge documentation and vocabulary mapping.

## Features

### F1: Reclassify `agent-rig.json` peers vs hard-conflicts

**What:** Split the existing `plugins.conflicts` array into two categories: `plugins.hard_conflicts` (true duplicates that should remain auto-disabled — `code-review@official`, `pr-review-toolkit@official`, `code-simplifier@official`, `commit-commands@official`, `feature-dev@official`, `claude-md-management@official`, `frontend-design@official`, `hookify@official`) and `plugins.peers` (alt rigs — `superpowers@superpowers-marketplace`, `compound-engineering@every-marketplace`, `gsd-plugin@<marketplace>`). Update reason text to reflect peer status (drop "successor" framing).

**Acceptance criteria:**
- [ ] `os/Clavain/agent-rig.json` has `plugins.hard_conflicts` and `plugins.peers` arrays. The legacy `plugins.conflicts` array is removed (no compatibility shim — peers are listed once).
- [ ] All entries previously under `conflicts` appear under exactly one of the two new arrays.
- [ ] Each `peers` entry has `source`, `reason` (descriptive, not "successor"), and `bridge_skill` (path or name reference).
- [ ] `os/Clavain/scripts/modpack-install.sh` `process_category()` handles `hard_conflicts` and `peers` distinctly (see F2).
- [ ] **`os/Clavain/scripts/verify-config.sh`** (line 48) reads both `plugins.hard_conflicts` and `plugins.peers`. Peers are expected-present, not expected-disabled — the verifier must not report a false PASS by reading an empty `conflicts` list.
- [ ] **`os/Clavain/commands/doctor.md`** Section 4 ("Conflicting Plugins") splits its hardcoded Python list into a `hard_conflicts` block (continues to WARN if installed) and a `peers` block (informational only — no WARN if peer is installed and active).
- [ ] **`os/Clavain/commands/setup.md`** Step 3 manual fallback block (the `<!-- agent-rig:begin:disable-conflicts -->` region) removes `claude plugin disable superpowers@superpowers-marketplace` and `claude plugin disable compound-engineering@every-marketplace`. The fallback path must not bypass F2's detect-and-ask logic for peers.
- [ ] `interverse/clavain/.claude-plugin/plugin.json` (if it mirrors the rig) is consistent with the new layout, OR the manifest only references `agent-rig.json` (verify which). External consumers (`rigsync.go`, `check-rig-drift.sh`) only read `required`/`recommended`/`optional` and are unaffected by this rename — verified during PRD review.

### F2: `/clavain:setup` detect-and-ask for peers

**What:** `modpack-install.sh` adds a new `process_peers()` function (sibling to the existing `process_category()`). It is **report-only** — it never calls `disable_plugin`. The existing `process_category("conflicts")` is renamed to `process_category("hard_conflicts")`; behavior is otherwise unchanged. This preserves the existing dry-run-by-default-when-flag-is-present contract: no flag = live mutation for hard_conflicts; `--dry-run` = no mutation anywhere; `peers` = always report-only regardless of flag. **No new flags introduced.**

**Acceptance criteria:**
- [ ] `modpack-install.sh --dry-run` against a system with `superpowers` installed reports it under `peers_detected` (never under `disabled` or `would_disable`).
- [ ] `modpack-install.sh` (no flags) does not call `claude plugin disable` for any entry in `plugins.peers` — for any reason.
- [ ] `hard_conflicts` continue to auto-disable on no-flag invocation (preserves the existing `/clavain:setup` Step 2 `$INSTALL_SCRIPT --quiet` contract that expects conflicts disabled on that call).
- [ ] JSON output adds two keys: `peers_detected: [...]` (peers present in cache, regardless of disabled state) and `peers_active: [...]` (peers installed and currently enabled). Existing keys (`installed`, `already_present`, `failed`, `disabled`, `already_disabled`, `optional_available`) are unchanged — additive schema only.
- [ ] **All six edit sites in `modpack-install.sh` are touched (avoid partial edits):** (1) rename `conflicts` case in `process_category()` to `hard_conflicts`; (2) add `peers` case routing to `process_peers()`; (3) update `all` main block to call both new category names; (4) update `--category=` validation allowlist; (5) add `peers_detected=()` and `peers_active=()` accumulator arrays; (6) update both JSON output blocks (dry-run and live).
- [ ] `/clavain:setup` reads the detection report and presents a post-detection summary. If peers detected, output names them and points to `/clavain:peers`. **`setup.md` Step 7 conflict count is updated to reflect `hard_conflicts` only** (previously implied a total that included peers).
- [ ] **Failure-loud requirement (from fd-systems P1):** if a peer detection rule produces an ambiguous match (e.g., plugin name found but version mismatch), log a `peer_detection_warning` to stderr — never silently skip.

### F3: Bridge skills — `interop-with-superpowers` + `interop-with-gsd`

**What:** Two new SKILL.md files in `os/Clavain/skills/`. Pure documentation, no runtime behavior. Each maps Clavain commands/skills to the peer rig's equivalent (e.g., `/clavain:write-plan` ≈ `/superpowers:write-plan` ≈ `/gsd:plan`), notes vocabulary differences, and points to the peer rig's docs for canonical reference.

**Acceptance criteria:**
- [ ] `os/Clavain/skills/interop-with-superpowers/SKILL.md` exists with valid frontmatter (`name`, `description`).
- [ ] `os/Clavain/skills/interop-with-gsd/SKILL.md` exists with valid frontmatter.
- [ ] Each contains a 2-column table mapping at least 5 vocabulary pairs (Clavain ↔ peer).
- [ ] Each notes the upstream repo URL and a one-paragraph "when to reach for the peer rig instead" guidance.
- [ ] Each description begins with "If [peer] is not installed, this skill is informational only." so users without that peer can deprioritize it.
- [ ] Skills are listed in `os/Clavain/CLAUDE.md` or the plugin's `plugin.json` `skills` array as appropriate.
- [ ] Description fields use the standard "Use when..." trigger pattern so the model auto-loads them when peer commands are mentioned.

### F4: `/clavain:peers` read-only viewer command

**What:** New slash command `os/Clavain/commands/peers.md`. Reads `agent-rig.json`'s `peers` array, runs the same detection logic as `modpack-install.sh`, and prints a structured report: which peers are detected, which are active, recommended bridge skill, and current resolution. Read-only — never mutates.

**Acceptance criteria:**
- [ ] `os/Clavain/commands/peers.md` exists with valid command frontmatter.
- [ ] Invoking `/clavain:peers` produces output listing each peer with status (`installed-active`, `installed-disabled`, `not-installed`).
- [ ] Output references the bridge skill path for each detected peer.
- [ ] No file or settings mutation occurs (verify via `git status` and `~/.claude/settings.json` mtime).
- [ ] Read-only is asserted in the command body's prose (mirrors the `doctor.md` pattern — "Read-only diagnostic. Never makes changes."). No new frontmatter convention introduced.
- [ ] **Claude Code only.** On Codex CLI, the equivalent surface is `bash modpack-install.sh --dry-run --quiet | jq` — F4 does NOT attempt cross-runtime parity. Codex parity for peer status is a separate follow-up bead if/when needed.

### F5: AGENTS.md beads-softening (bonus, P3)

**What:** Soften the absolute prohibition in `AGENTS.md` from "Never create TODO files, markdown checklists, or pending-beads lists" to project-scoped canonicalization ("In this project, beads is canonical for work tracking. If you use external rigs (GSD, superpowers) with their own task surfaces, those rigs' tracking belongs to them — Sylveste-internal work tracking goes through beads."). Mirror the change in the `<!-- BEGIN BEADS INTEGRATION -->` block at the bottom of `AGENTS.md`.

**Acceptance criteria:**
- [ ] `AGENTS.md` "Conventions → Work tracking" paragraph rewords prohibition to project-scoped canonicalization.
- [ ] The `<!-- BEGIN BEADS INTEGRATION v:1 -->` block's "Rules" section is consistent with the new wording (no contradiction).
- [ ] No information loss: beads is still clearly the canonical Sylveste tracker.

### F6: Telemetry — log winning `using-*` skill per session (P2)

**What:** Lightweight hook that captures which `using-*` skill (or none) "won" the routing decision per session. Appended to `~/.clavain/peer-telemetry.jsonl` with one record per session: `{ts, session_id, using_skills_loaded: [...], using_skill_invoked: <name|null>, peers_detected: [...]}`. This is the gating signal for B′/C′ scope expansion. ~50 lines.

**Acceptance criteria:**
- [ ] Telemetry file path is `~/.clavain/peer-telemetry.jsonl` and is append-only.
- [ ] One JSONL record per session start (or session close — design choice; pick the simpler one).
- [ ] Records include the schema fields above.
- [ ] Hook fails silently if `~/.clavain/` is unwritable (no session disruption).
- [ ] Telemetry is opt-out via `CLAVAIN_PEER_TELEMETRY=0` env var or `~/.clavain/config.json`'s `telemetry.peers: false`.
- [ ] No PII collected (session_id is opaque hash, no file paths or content).
- [ ] One-line documentation in `os/Clavain/CLAUDE.md` noting the file path and opt-out.

## Non-goals

- **Profiles, lockfile, per-skill priority resolution, peers.yaml community registry, `clavain rig` CLI surface.** Deferred to sylveste-fj1w (B′) and sylveste-yofd (C′), gated on telemetry from this sprint.
- **Auto-detection of GSD via runtime probing.** Detection is via plugin name in `~/.claude/plugins/installed_plugins.json` only. If GSD ships outside that registry (raw upstream clone), it goes undetected — a known gap, deferred.
- **Cross-rig router that maps natural-language requests across rigs.** Rejected in brainstorm review — premature without telemetry.
- **Per-skill priority configuration.** Same — premature.
- **Codex CLI side of the install flow.** F4 should degrade cleanly on Codex but the Codex installer (`scripts/install-codex-interverse.sh`) is out of scope. File a follow-up bead if Codex parity is needed for ship.

## Dependencies

- `bd` (beads) — already required by Sylveste workflow
- `jq` — already required by `modpack-install.sh`
- Claude Code plugin system: `claude plugin list/install/disable` — used by existing `modpack-install.sh`; no new dependencies introduced

## Open Questions

1. **F3 bridge skill auto-load triggers.** What's the right `description` field wording? Should the skill auto-load any time the user mentions `superpowers` or `gsd`, or only when they explicitly invoke a peer command? Lean toward "explicit peer command mentioned" to avoid noise. To be decided in plan phase.
2. **F6 telemetry capture point.** Session start (lightweight, but doesn't know which skill ultimately won) vs session end (knows the answer, but requires a stop hook that may not fire reliably). Lean toward session start + post-routing-decision append; finalize in plan phase.
3. ~~**F2 `--apply` flag.**~~ **RESOLVED in PRD review:** drop `--apply` entirely. `hard_conflicts` keep existing auto-disable contract; `peers` are always report-only via the new `process_peers()` function. No new flag surface.
4. **GSD marketplace identifier.** `jnuyens/gsd-plugin` ships via what marketplace? Need to confirm before F1 lists it correctly. Could be `gsd-plugin@<marketplace-name>` or it might require a placeholder until first user reports.

## Risks (from brainstorm review)

- **Schelling-point brittleness (fd-systems P1).** Peer detection by plugin name is fragile — if `superpowers` renames or migrates marketplaces, detection silently fails. Mitigation: F2 acceptance criterion "failure-loud" requires `peer_detection_warning` on ambiguous match.
- **Discoverability inversion (fd-user-product P1).** `/clavain:setup` post-detection report is the only auto-discovered surface for the new peer-coexistence behavior. F2 acceptance criterion explicitly requires the setup report to mention `/clavain:peers` so users can find the inspection surface.
- **Over-decomposition risk.** Six features for a 1–2 day scope is borderline. F5 is bonus and can drop if cheap-during-implementation doesn't pan out.
