---
artifact_type: flux-drive-finding
reviewer: fd-user-product
bead: sylveste-4ct0
source_brainstorm: docs/brainstorms/2026-04-27-clavain-peer-coexistence-brainstorm.md
date: 2026-04-27
severity_counts:
  P0: 1
  P1: 2
  P2: 1
  P3: 0
verdict: revise-scope
---

# User & Product Review — Clavain Peer-Coexistence

## Primary User / Job

The trigger user is a developer who already has superpowers or GSD installed and attempts to add Clavain. Their job: run `/clavain:setup` and leave with both rigs functional. A secondary user is the Sylveste maintainer wanting reproducible team onboarding.

---

## Severity Summary

| Severity | Count |
|----------|-------|
| P0 | 1 |
| P1 | 2 |
| P2 | 1 |
| P3 | 0 |

---

## Finding 1 — P0: Problem Evidence Is Anticipatory, Not Validated

**The trigger problem is real; the generalization claim is not.**

The brainstorm states: "the coworker situation generalizes (and it likely will)" as justification for C′ scope over B′. No evidence is cited — no GitHub issues, no Discord reports, no adoption data. The only concrete evidence is a single coworker scenario. The roadmap-v1.md frames Sylveste as currently in the v0.6–0.7 range, explicitly pre-external-user. The project memory confirms launch is deferred three months.

The immediate problem — `/clavain:setup` silently calling `claude plugin disable superpowers@superpowers-marketplace` — is a one-line fix in `agent-rig.json` and `commands/setup.md` Step 3. Currently `agent-rig.json` classifies superpowers under `"conflicts"` with reason `"Clavain is the successor to superpowers"`. Changing that classification to a new `"peers"` bucket and removing superpowers from the auto-disable list in `commands/setup.md` lines 104–108 eliminates the coworker breakage entirely.

C′ is being justified by a future that hasn't arrived. The brainstorm's own Open Question 2 acknowledges "without telemetry, per-skill priorities are designed in the dark." Designing a mod-manager for a user base of one confirmed coworker and an imagined multi-rig future is anticipatory product design dressed as problem-solving.

**Minimum fix for the coworker:** reclassify `superpowers` and `compound-engineering` from `conflicts` to `peers` in `agent-rig.json`, gate the auto-disable on explicit confirmation, update Step 3 of `commands/setup.md`. Estimated: half a day, no new surface area.

---

## Finding 2 — P1: Scope Creep — Six of Eight C′ Pieces Do Not Fix the Coworker

Mapping each C′ deliverable to the stated failure modes (A, B, C from Key Decision 3):

| C′ piece | Fixes failure A (auto-disable) | Fixes failure B (using-* conflict) | Fixes failure C (vocab mismatch) | Verdict |
|---|---|---|---|---|
| peers classification in agent-rig.json | YES | no | no | core fix |
| /clavain:setup --apply gate | YES | no | no | core fix |
| peers.yaml registry | no | no | partial | nice-to-have |
| profiles (companion/primary/off) | no | no | no | ride-along |
| per-skill priority resolution | no | partial | no | ride-along |
| agent-rig.lock.json | no | no | no | ride-along |
| clavain rig CLI surface | no | no | no | ride-along |
| bridge skills | no | no | YES | core fix |
| using-clavain peer-aware softening | no | YES | no | core fix |

The four "core fix" pieces are: reclassify peers, gate auto-disable, bridge skills (documentation only, per Open Question 5's recommendation), and the using-clavain SKILL.md softening. The brainstorm itself recommends bridge skills as "pure documentation" for V1. That's a SKILL.md edit.

Profiles, lockfile, per-skill priorities, and the full `clavain rig` CLI are future-proofing for a multi-rig ecosystem that doesn't yet have measurable demand. The brainstorm hedges this ("if the bet doesn't pay off... lockfile and profiles are still useful for Sylveste-internal team onboarding") but that hedge is doing a lot of work for a 1.5–2 week commitment with no external users yet.

The true MVP is: reclassify peers in agent-rig.json + gate on --apply + soften using-clavain + add bridge SKILL.md documentation. One to two days, zero new state, zero new commands, zero new file formats.

---

## Finding 3 — P1: Discoverability Gap — New Surface Is CLI-Only, Trigger Mechanism Is Auto-Loading

The `using-clavain` SKILL.md is auto-injected at SessionStart via the hook in `additionalContext`. This means every user who has Clavain loaded sees the routing table on every session start. The new pieces — `/clavain:peers`, `clavain rig profile use companion`, `~/.clavain/peer-priorities.yaml` — are CLI commands and config files. Nothing in the auto-loading skill content would surface them to the coworker.

The coworker's actual discovery path: they install Clavain, `/clavain:setup` runs, something happens (previously: their rig disappears; after the fix: they see a detection report). If the detection report says "superpowers detected — run /clavain:peers for options" that is discoverable. If the only path to companion mode is knowing to type `clavain rig profile use companion` at a terminal, it will not be found.

The brainstorm does not specify what the detection report output looks like or how it directs the user to the new CLI surface. For the MVP case, the detection report at the end of `/clavain:setup` is the only discoverable entry point. This needs to be designed before the CLI surface is built, not after. Building the CLI first inverts the flow.

---

## Finding 4 — P2: Identity Shift Risk — "Rig Manager" Frames Clavain as Infrastructure, Not Agent

The reframe from "successor to superpowers" to "rig manager" is named as a "meaningful identity shift" in the Conflict/Risk section. The brainstorm is correct that it's meaningful — but it is a bet with asymmetric failure modes.

Clavain's PHILOSOPHY.md states the purpose as: "Self-improving agent rig — codifies product and engineering discipline into composable workflows from brainstorm to ship." The North Star is "orchestration brain: disciplined workflow routing, robust review gates, dependable inter-module handoffs." None of that framing is about managing other rigs. Adding a mod-manager layer is infrastructure work that recenters Clavain's identity around coordination rather than discipline.

If multi-rig usage does not materialize (the brainstorm's acknowledged risk), Clavain has shipped a lockfile schema that is now a versioned contract, a peer registry that needs maintenance, a profiles system with its own test surface, and a `clavain rig` CLI namespace — all for a positioning bet that didn't pay off. The "hedge" (lockfile useful for internal team onboarding) is not a hedge; Sylveste's own session protocol uses Dolt + beads, not lockfiles.

The identity work should be separated from the coexistence fix. Fix the coexistence problem (P0 above). If multi-rig adoption becomes observable — GitHub issues, marketplace install counts, Discord threads — revisit the rig-manager identity as a deliberate roadmap item with evidence behind it.

---

## Edge Cases Not Addressed in the Brainstorm

**User who wants Clavain to win over superpowers.** The brainstorm assumes the desire is always coexistence. A user upgrading from superpowers to Clavain who wants a clean cutover has no path in C′ — the new default is detect-and-report, not auto-disable. They would need to manually run the disable commands that previously ran automatically. The `--apply` flag restores this path only if the user knows to use it. The current setup.md Step 3 fallback block should be preserved as an opt-in "full migration" path.

**Users with 5 peer rigs.** The brainstorm mentions 5 profiles as a risk ("users forget which is active"). Per-skill priorities across 5 peers multiplies the combinatorial space. The peers.yaml maintenance burden scales with the number of rigs in the wild, not with Clavain's own development. This is an argument for deferring the community registry until there is actual community demand, not for building it preemptively.

**Codex-CLI users.** `agent-rig.json` is Claude Code's manifest format. The Codex path in `commands/setup.md` Step 0 routes to `install-codex-interverse.sh` and terminates before the conflict-disable steps. Peer detection, profiles, and the `clavain rig` CLI are underdefined for the Codex runtime. The brainstorm does not address this split. Since Sylveste is explicitly dual-runtime (see `agent-rig.json` `platforms.codex`), any new surface area added under Claude Code's manifest model needs a parallel or explicitly deferred story for Codex.

---

## Recommendation

Ship the minimum fix:
1. Reclassify `superpowers` and `compound-engineering` from `conflicts` to `peers` in `os/Clavain/agent-rig.json`.
2. Gate `claude plugin disable` for peers behind explicit `--apply` confirmation in `commands/setup.md` Step 3.
3. Add a detection report at setup completion that names peers found and suggests a follow-up action.
4. Soften the `using-clavain` SKILL.md "Proactive skill invocation is required" line to advisory when a peer's `using-*` skill is also loaded.
5. Add `interop-with-superpowers` and `interop-with-gsd` as documentation-only SKILL.md files (pure vocabulary mapping, per the brainstorm's own recommendation for V1).

Defer profiles, lockfile, per-skill priorities, `peers.yaml` community registry, and `clavain rig` CLI until there is measurable evidence of multi-rig users. Define the success signal before building: "X installs where superpowers is also installed" is observable via marketplace data once Clavain has external users.
