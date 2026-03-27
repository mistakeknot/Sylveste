---
artifact_type: brainstorm
bead: Sylveste-bncp
stage: discover
---

# interlore: Philosophy Observer Plugin + Doc Hierarchy Restructure

## What We're Building

Three connected pieces:

1. **Doc hierarchy restructure.** Add MISSION.md as the root document. VISION.md and PHILOSOPHY.md become siblings derived from it. All other artifacts (PRDs, roadmap, CUJs, AGENTS.md conventions) derive from one or both. Update doc-structure canon to reflect this.

2. **interlore plugin.** New Interverse plugin that scans decision artifacts (brainstorms, PRDs, flux-drive outputs, code reviews) to detect two things:
   - **Emerging patterns** — recurring decision tradeoffs not yet captured in PHILOSOPHY.md (e.g., "4 PRDs chose integration over building")
   - **Philosophy drift** — decisions that contradict stated philosophy (e.g., a PRD chose monolith over composition)

3. **interdoc fix.** Make interdoc's "philosophy alignment protocol" actually load PHILOSOPHY.md instead of being inert prose in AGENTS.md.

## Why This Approach

**Problem:** PHILOSOPHY.md is static. interdoc claims to enforce alignment but doesn't actually load the file. There's no feedback loop from decisions back to philosophy — it's open-loop. The doc hierarchy also lacks a root (MISSION.md) that vision and philosophy derive from.

**Solution:** Close the loop. interlore observes what the project actually does and proposes updates to what it says it believes. The mission doc anchors everything.

**Unix decomposition (cybernetic unix principle):**
- interlore: detect patterns, propose philosophy updates
- interdoc: check doc generation against philosophy (existing protocol, made real)
- interpath: generate vision/roadmap/PRD from mission + vision
- interwatch: detect when any doc drifts from reality

Each does one thing. interlore doesn't generate docs, interdoc doesn't detect patterns.

## Key Decisions

### Doc hierarchy
- MISSION.md at project root — one paragraph, changes almost never
- VISION.md and PHILOSOPHY.md are siblings (both derived from mission, neither derives from the other)
- Philosophy = how we build (design bets, principles). Vision = where we're going.
- All derived artifacts (PRDs, roadmap, CUJs) derive from vision and/or philosophy

### interlore output model: hybrid staging + review
- Proposals accumulate in `.interlore/proposals.yaml` (structured YAML with evidence links)
- `/interlore:review` walks through proposals interactively (accept/reject/defer)
- Propose, never auto-apply — philosophy changes need human review
- State dir is `.interlore/` (standalone plugin, not kernel-native — `.clavain/` is kernel-owned)

### interlore triggers: on-demand (v1) + integration wiring (separate beads)
- `/interlore:scan` for ad-hoc scanning (primary, ships with interlore)
- Sprint Stop hook, interwatch signal, interdoc fix ship as separate beads in their respective plugin owners
- interlore works fully standalone without any integration wiring

### interlore scope: discover + drift
- EMERGING proposals: novel patterns not yet in PHILOSOPHY.md (threshold: 3+ unique decisions by bead ID)
- DRIFT flags: decisions that contradict stated philosophy
- CONFORMING patterns: match existing philosophy — logged but not proposed (avoids re-discovery noise)
- Both EMERGING and DRIFT surfaced as proposals for review, not auto-applied

### Signal extraction model (revised after flux-drive review)
- **Primary: content-based extraction** — scan for tradeoff language ("chose X over Y", "prefer", "default to")
- **Enrichment: Alignment/Conflict lines** — high-quality when present, but <2% of existing artifacts have them
- **Deduplication: bead ID context** — brainstorm → PRD → plan from same bead = 1 decision, not 3
- Classification by unique decision count (bead IDs), not artifact count

### What interlore scans
- Artifact discovery follows interpath source catalog (documentation reuse, not runtime coupling)
- `docs/brainstorms/*.md`, `docs/prds/*.md`, `docs/prd/*.md`, `.claude/flux-drive-output/fd-*.md`, `docs/plans/*.md`

## Open Questions (post flux-drive review)

1. **Pattern storage format.** Resolved: structured YAML (`.interlore/proposals.yaml`). Git-trackable, schema-defined, readable by downstream consumers.
2. **MISSION.md exact wording.** Draft: "Build the infrastructure that lets AI agents do real software engineering work autonomously, safely, and at scale. Prove that the bottleneck is plumbing, not intelligence — and that compounding evidence is the path to earned trust."
3. **Cross-project interlore.** Should interlore work per-project or across the monorepo? PHILOSOPHY.md exists at both root and subproject level.
4. **interdoc integration depth.** Should interdoc call interlore during generation, or just read the staging file? Calling interlore couples them; reading the file keeps them independent.

**Alignment:** Directly supports PHILOSOPHY.md principle "Every action produces evidence" — interlore makes decision patterns into observable evidence, closing the reflect→compound loop for philosophy itself.

**Conflict/Risk:** None with current philosophy. The tool embodies the flywheel: more decisions → more evidence → better philosophy → better decisions.
