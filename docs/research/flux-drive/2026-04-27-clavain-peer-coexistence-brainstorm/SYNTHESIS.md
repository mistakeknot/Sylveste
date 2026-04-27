---
artifact_type: review-synthesis
method: flux-drive
target: docs/brainstorms/2026-04-27-clavain-peer-coexistence-brainstorm.md
bead: sylveste-4ct0
date: 2026-04-27
agents:
  - fd-decisions
  - fd-user-product
  - fd-systems
---

# Brainstorm Review — Synthesis

**Verdict: NEEDS_ATTENTION (1 P0, 7 P1).**

Three independent agent perspectives converge strongly on a single core finding: **C′ scope is built on an unevidenced "users actually multi-rig" assumption**, while the actual coworker problem is a 1–2 day fix. The brainstorm is well-structured and self-aware about the evidence gap, but the choice to commit ~1.5–2 weeks before that gap is closed is the highest-severity decision quality issue.

## Severity Counts

| Agent | P0 | P1 | P2 | P3 |
|---|---|---|---|---|
| fd-user-product | **1** | 2 | 1 | 0 |
| fd-decisions | 0 | 3 | 3 | 0 |
| fd-systems | 0 | 2 | 2 | 2 |
| **Total** | **1** | **7** | **6** | **2** |

## Cross-Track Convergence (highest confidence)

### Convergent finding 1 (3/3): Multi-rig assumption is unevidenced

- **fd-user-product (P0):** "The trigger breakage is real and confirmed. The generalization is not... no GitHub issues, no Discord complaints, no install data. The project is pre-launch."
- **fd-decisions (P1):** "How many Sylveste users run Clavain + superpowers/GSD simultaneously? How often do conflicts occur? This is answerable in 1 hour via telemetry but is deferred post-ship."
- **fd-systems (P1):** "Per-skill priorities are designed in a vacuum with no telemetry to learn which peer skill wins in practice."

The brainstorm itself flags this in Open Question 2 ("designed in the dark") but proceeds anyway. Treated as P0 because it inverts the standard product-development sequence: build infrastructure for a use case before confirming the use case exists.

### Convergent finding 2 (3/3): Six of eight C′ pieces are not load-bearing for the named failure modes

- **fd-user-product (P1):** "Against the three named failure modes (auto-disable / competing using-\* / vocab mismatch), only four deliverables are load-bearing: the peer reclassification, the `--apply` gate, bridge skills as documentation, and the using-clavain softening. Profiles, lockfile, per-skill priorities, `peers.yaml`, and the `clavain rig` CLI are ride-alongs built for a multi-rig future."
- **fd-decisions (P1):** Implicit in "Mod-Manager Analogy Anchors Design; Simpler Solutions Unexplored."
- **fd-systems** indirectly via "feedback-loop absence" — the unloaded pieces are exactly the ones lacking telemetry to justify them.

### Convergent finding 3 (2/3): Mod-manager analogy may import unnecessary complexity

- **fd-decisions (P1):** "Game modding is fundamentally different: users *deliberately* install multiple mods... Clavain peer-rig conflicts are *accidental* (user installs superpowers for one reason, Clavain for another). The analogy imports complexity that may not be necessary."
- **fd-user-product (P1):** "Ride-alongs built for a multi-rig future that has no confirmed users."

### Convergent finding 4 (2/3): Identity confusion creates maintenance debt

- **fd-decisions (P2):** "Clavain's dual identity (neutral manager + opinionated rig) unresolved. When peer rigs conflict, does Clavain lead (asymmetric coordinator) or are all rigs equal (symmetric)?"
- **fd-user-product (P2):** "Clavain's PHILOSOPHY.md purpose statement does not include managing other rigs. If multi-rig usage does not materialize, this is 1.5–2 weeks of infrastructure debt with no users."

## Domain-Expert Single-Track Findings

### fd-systems P1: Schelling-point brittleness
"The entire peer detection depends on a shared convention (skill names, plugin metadata). One plugin author's rename cascades into silent misdetection. Failure is invisible: users think their rig is detected when it isn't." Mitigation: detection failures must be loud; add `/clavain:verify-peers` diagnostic; version detection schemas.

### fd-user-product P1: Discoverability is inverted
"The `using-clavain` SKILL.md is auto-injected at every session start — that is the only surface the coworker will see unprompted. The new `/clavain:peers`, `clavain rig profile use companion`, and `~/.clavain/peer-priorities.yaml` are all CLI-only." The detection report at `/clavain:setup` is the only discoverable entry point and is not specified in the brainstorm.

### fd-systems P2: Pace-layer mismatch
"Plugin authors evolve daily; `peers.yaml` updates weekly. By design, the registry lags by 1–2 weeks." Suggested fix: embed detection rules in peer plugins (metadata) instead of relying on a centralized registry.

### fd-decisions P2: Lockfile versioning strategy not designed
"The brainstorm notes 'lockfile schema becomes a contract — needs versioning from day one,' but no versioning scheme is documented."

### fd-decisions P2: Profile granularity lacks decision criteria
"The choice between 3-mode profiles and full rig snapshots is deferred to design time without explicit criteria."

## Synthesis Assessment

**Quality of the brainstorm:** Honest, well-structured, self-aware about uncertainty. The risk is not bad thinking — it's premature commitment.

**Highest-leverage improvement:** Down-scope to **A** or **B′-minimum** (1–2 days). Ship the auto-disable fix and the bridge skills as documentation. Add ~50 lines of lightweight logging to capture which skill won per session. Defer profiles, lockfile, per-skill priorities, `peers.yaml`, and the `clavain rig` CLI to a follow-up bead gated on observed multi-rig usage.

**Surprising finding (cross-track):** All three reviewers — from completely different lenses (decision quality, user/product, systems thinking) — independently arrived at the same recommendation: **collect evidence first, then expand**. This is the highest-confidence signal possible from a 3-agent review.

**Sylveste philosophy filter:**
- *Reduces ambiguity?* B′-minimum passes (small surface, observable). C′ adds ambiguity (many new state surfaces with unproven defaults).
- *Reliability without inflating cognitive load?* B′ passes. C′ inflates (3 new commands, lockfile schema contract, peers.yaml staleness, profile drift).
- *Reversibility?* B′ trivially reversible. C′'s "reversibility built in" claim is weakened by hidden state accumulation in profiles and lockfile commitments.

## Recommended Action

**Tier 2 gate: pause, present findings, allow user to choose between three responses:**

1. **Down-scope to A** — accept the convergent recommendation; ship the 1–2 day fix; file a follow-up bead for B′/C′ gated on telemetry.
2. **Down-scope to B′-minimum** — A + bridge skills + peer-aware using-clavain (~3 days); defer profiles/lockfile/per-skill-priorities/peers.yaml/rig-CLI.
3. **Override and proceed with C′** — accept the unevidenced bet; document the rationale; expect the maintenance debt finding to materialize if multi-rig usage does not.
