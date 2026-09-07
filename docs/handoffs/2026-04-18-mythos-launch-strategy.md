---
date: 2026-04-18
session: a210ece1
topic: mythos-launch-strategy
beads: [sylveste-3rod, sylveste-nzhl, sylveste-myyw, sylveste-oyrf]
---

## Session Handoff — 2026-04-18 Mythos Launch Strategy

### Directive

> Your job is to pick one of the three focus epics and decompose it into child beads. Start with `bd show sylveste-nzhl` (Ockham Wave 2) unless a different epic is more energizing. Verify the epic structure with `bd show sylveste-3rod` — the meta-epic's dependency graph should show 3 blocking epics.

- **Meta-epic (P0):** `sylveste-3rod` — Sylveste Mythos launch readiness; 3 focus epics block it
- **Focus epics (all P0, open):**
  - `sylveste-nzhl` — Ockham Wave 2 (Tier 2 CONSTRAIN + authority ratchet)
  - `sylveste-myyw` — Autonomy A:L3 (3 calibration loops fire without human invocation)
  - `sylveste-oyrf` — Longitudinal data + Mythos launch artifacts
- **Existing autonomy contributors** (referenced in myyw description, not formally linked): `sylveste-8n9n`, `sylveste-2aqs`, `sylveste-xcn4`
- **Ockham Tier 3 sibling:** `sylveste-t8rn` (deferred — not in Wave 2)
- **Next-session first move candidate:** Ockham Wave 2 first because Tier 2 CONSTRAIN is the biggest unknown and benefits from early spike work. Autonomy A:L3 is more "wire up what's mostly there."

### Dead Ends

- `bd dep add sylveste-myyw sylveste-8n9n` (and the 2aqs, xcn4 variants) — **failed** with "epics can only block other epics, not tasks." Cannot formally parent existing feature-beads under a new epic via dep graph. Workaround: referenced by name in epic description; formal `.N` children will be created directly under the epic when child decomposition happens next session.
- Synthesis's original 6-week launch plan — **abandoned as too-aggressive framing**. Optimized within the wrong question. Launching now would use point-estimate receipt ($2.93/785 sessions) rather than trajectory; would expose rough edges in M0-M1 subsystems; would pause active internal work. User pivoted to Path B: 3 months heads-down, launch triggers on next Claude Opus release (codename "Mythos" per user).
- "Name 3-5 practitioners for private pre-launch outreach" (Hokulea finding from synthesis) — **replaced** with "0 named practitioners + 4 artifact bearings." Solo dev without pre-existing frontier-lab relationships shouldn't manufacture a ring.

### Context

- **Strategic pivot saved to memory:** `~/.claude/projects/-home-mk-projects-Sylveste/memory/project_launch_deferred.md` captures launch deferral + locked hero + cancel list + Mythos-alignment positioning claim. Future sessions load this automatically.
- **Hero locked:** *"Sylveste orchestrates agents by human/machine comparative advantage."* Support: *"Agents run what's algorithmic; humans stay in the loop for judgment, taste, and preference. Every human correction updates the split."* Three-sentence block; $2.93 receipt is the third sentence.
- **Domain locked:** `sylvst.com` (already user's, Cloudflare-managed per `reference_cloudflare.md`). NOT sylveste.ai or sylveste.dev. Meadowsyn.com held dark until Meadowsyn ships.
- **Positioning claim for Mythos:** "Sylveste is the same on every model; what changes is how quickly the flywheel calibrates." Launch fires on Mythos drop with the before/after delta as headline, not the 3-month static baseline. Preprint gets a Mythos-transition section.
- **4 artifact bearings (no people):** preprint (zenith-star, arXiv/Zenodo DOI), viewing-line at sylvst.com/live (swell, GitHub Actions cron), reproducible cost-query.sh against published CSV (verification), blog post extending Yegge's Squirrel Selection Model (positioning — crosses into Yegge audience through intellectual lineage, no DM).
- **Cancel list (apply anytime during 3 months):** hide Garden Salon + Meadowsyn from all public surfaces; cut 64-plugin enumeration from README; cut 3-layer × 6-pillar architecture table from first-contact; tier PHILOSOPHY.md into operational (2-3 claims with receipts) + roadmap; cut "wired or it doesn't exist" public claim until receipt exists; full Clavain README realign to match comparative-advantage frame (no current external users = zero churn cost).
- **Flux-review artifacts (source of truth for decisions above):**
  - `/home/mk/projects/Sylveste/docs/flux-review/sylveste-ecosystem-external-visibility/2026-04-16-synthesis.md` (36KB, cross-track synthesis)
  - `/home/mk/projects/Sylveste/docs/flux-review/sylveste-ecosystem-external-visibility/2026-04-16-target-brief.md` (12KB, strategic brief)
  - 16 per-agent findings in `docs/research/flux-drive/sylveste-ecosystem-external-visibility-*` and `docs/research/flux-drive/2026-04-16-target-brief-*`
- **User preference saved:** When batching 2+ sequential decisions, use `AskUserQuestion` with recommendation first, not prose lists. See `feedback_askuserquestion_for_lists.md`.
- **bd convention reminder:** `bd dep add A B` means A depends on B = B blocks A. Epic→task blocking forbidden; task→epic blocking allowed. Epic children use `.N` suffix created at bead-creation time, not via dep graph.
