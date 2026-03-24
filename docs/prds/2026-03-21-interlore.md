---
artifact_type: prd
bead: Demarch-bncp
stage: design
---

# PRD: interlore — Philosophy Observer Plugin + Doc Hierarchy

## Problem

PHILOSOPHY.md is static — no feedback loop from decisions back to principles. interdoc claims a "philosophy alignment protocol" but doesn't actually load the file. The doc hierarchy lacks a root (MISSION.md) that vision and philosophy derive from. Design principles emerge implicitly from repeated decisions but are never codified until someone notices.

## Solution

Close the loop with two pieces delivered in this epic: (1) a doc hierarchy with MISSION.md as root, and (2) an interlore plugin that detects latent design patterns and philosophy drift from decision artifacts. interlore proposes — humans approve. Integration wiring (interdoc fix, interwatch signal, sprint hook) ships as separate beads in their respective plugin owners.

## Features

### F1: Doc Hierarchy Restructure

**What:** Add MISSION.md at project root as the foundational document. Establish the hierarchy: MISSION → {VISION, PHILOSOPHY} as siblings. Update doc-structure canon. Migrate cross-references.

**Semantic boundaries:**
- MISSION.md: why the project exists (rarely changes). Extracted from PHILOSOPHY.md's opening — the three principles and core bet stay in PHILOSOPHY.md, but the "why" sentence moves to MISSION.
- VISION.md: where the project is going. The existing `docs/demarch-vision.md` (v3.4) is the canonical vision doc — F1 references it in the hierarchy, does not create a duplicate.
- PHILOSOPHY.md: how we build (design bets, tradeoffs, principles). Unchanged except removing the mission-level "why" sentence that moves to MISSION.md.
- Conflict resolution: MISSION.md takes precedence when VISION and PHILOSOPHY conflict.

**Migration strategy:**
- Update `docs/canon/plugin-standard.md` AGENTS.md Standard Header boilerplate to reference the full hierarchy (MISSION + PHILOSOPHY)
- Existing plugin AGENTS.md files cascade on next `interdoc` regeneration — no bulk manual update
- 47 structural test suites that assert `PHILOSOPHY.md` in required files: no change needed (PHILOSOPHY.md stays at root; MISSION.md is additive)
- doc-structure.md removes "auto-loaded by interdoc" rationale, replaces with hierarchy position rationale

**Acceptance criteria:**
- [ ] MISSION.md exists at project root with one-paragraph mission statement
- [ ] docs/canon/doc-structure.md updated to show MISSION → {VISION, PHILOSOPHY} hierarchy with semantic boundary definitions
- [ ] doc-structure.md no longer claims "auto-loaded by interdoc" for PHILOSOPHY.md placement
- [ ] docs/canon/plugin-standard.md AGENTS.md boilerplate updated to reference MISSION.md alongside PHILOSOPHY.md
- [ ] PHILOSOPHY.md opening section trimmed: mission-level "why" extracted to MISSION.md, principles and core bet remain
- [ ] Existing `docs/demarch-vision.md` acknowledged as canonical vision doc in hierarchy (no duplicate created)
- [ ] interdoc AGENTS.md relative path to PHILOSOPHY.md still resolves correctly

### F2: interlore Plugin Scaffold

**What:** Create the interlore plugin with standard Interverse structure per `docs/canon/plugin-standard.md`.

**Acceptance criteria:**
- [ ] `interverse/interlore/.claude-plugin/plugin.json` with correct schema: `name: "interlore"`, `author: { "name": "mistakeknot" }`, skills as `["./skills/observe"]`, commands as `["./commands/scan.md", "./commands/review.md", "./commands/status.md"]`
- [ ] 6 required root files: README.md, CLAUDE.md (30-60 lines, hard cap 80), AGENTS.md, PHILOSOPHY.md, LICENSE (MIT, copyright MK), .gitignore
- [ ] Skill in per-subdirectory layout: `skills/observe/SKILL.md` with YAML frontmatter (name, description)
- [ ] Commands in `commands/` directory: `scan.md`, `review.md`, `status.md` with YAML frontmatter
- [ ] `tests/structural/` with full suite: `pyproject.toml` (requires-python >= 3.12), `conftest.py`, `helpers.py`, `test_structure.py`, `test_skills.py`
- [ ] `scripts/bump-version.sh` delegating to `ic publish` or `interbump.sh`
- [ ] No hooks declared in `plugin.json` (hooks auto-load from `hooks/hooks.json` if present)
- [ ] State directory: `.interlore/` (not `.clavain/interlore/` — interlore is a standalone plugin, not kernel-native)
- [ ] Plugin loads without error in Claude Code
- [ ] `uv run pytest tests/structural/` passes

### F3: interlore:scan — Pattern Detection Engine

**What:** Core skill that scans decision artifacts, detects recurring design patterns and philosophy drift, and writes structured proposals to a staging file.

**Signal extraction model (three tiers):**
1. **Content-based extraction (primary):** Scan artifact text for recurring tradeoff language — decision keywords ("chose X over Y", "prefer", "default to", "rejected"), tradeoff pairs, rationale patterns. This is the primary signal source since it works on all artifacts.
2. **Alignment/Conflict lines (enrichment):** When present, these structured lines from interdoc's protocol provide high-quality signal. But <2% of existing artifacts have them — never rely on these alone.
3. **Frontmatter and bead context:** Extract bead IDs from frontmatter to deduplicate citation chains. A brainstorm → PRD → plan from the same bead = one decision, not three.

**Pattern definition:** A structured tuple:
- `tradeoff_axis`: what tradeoff was being made (e.g., "integration vs reimplementation")
- `chosen_pole`: which side was chosen (e.g., "integration")
- `evidence`: list of (artifact_path, bead_id, relevant_excerpt) tuples
- `unique_decisions`: count of unique bead IDs (not artifact count)
- `time_span`: earliest to latest evidence date
- `philosophy_match`: which PHILOSOPHY.md section this relates to (or "none" if novel)

**Classification (by unique decisions, not artifact count):**
- established: 3+ unique decisions, 2+ weeks span
- emerging: 2 unique decisions
- nascent: 1 decision (logged but not proposed)

**Proposal types:**
- EMERGING: pattern not yet in PHILOSOPHY.md (`philosophy_match == "none"`)
- DRIFT: decision contradicts a stated PHILOSOPHY.md principle
- Note: patterns that conform to existing philosophy are logged as "conforming" but not proposed (avoids re-discovery noise)

**Artifact discovery:** Reference interpath's `references/source-catalog.md` as authoritative artifact directory list. Override only where interlore's needs differ. No independent crawling logic — if interpath's catalog changes, interlore follows.

**Acceptance criteria:**
- [ ] Scans artifacts discovered via interpath source catalog patterns: `docs/brainstorms/*.md`, `docs/prds/*.md`, `docs/prd/*.md`, `.claude/flux-drive-output/fd-*.md`, `docs/plans/*.md`
- [ ] Content-based extraction is primary signal (works on all artifacts); Alignment/Conflict lines are enrichment only
- [ ] Deduplicates by bead ID — artifacts sharing a bead count as one decision
- [ ] Classifies by unique decision count: established (3+), emerging (2), nascent (1)
- [ ] Distinguishes EMERGING (novel pattern) from DRIFT (contradicts philosophy) from conforming (matches existing — not proposed)
- [ ] Writes proposals to `.interlore/proposals.yaml` in structured schema (see below)
- [ ] `/interlore:status` shows: last scan date, proposal count by type and classification, pre-threshold candidate count, conforming pattern count
- [ ] Graceful degradation: missing artifact dirs silently skipped; absent PHILOSOPHY.md produces "no baseline for diff" warning (not error); empty corpus produces "no patterns detected" (not error); malformed artifacts (bad YAML, binary files) skipped with warning
- [ ] Minimum corpus: 3+ artifacts required for any proposals; below threshold outputs informational message only

**Proposals schema (`.interlore/proposals.yaml`):**
```yaml
version: 1
last_scan: "2026-03-21T17:00:00Z"
proposals:
  - id: "p-001"
    type: "emerging"  # emerging | drift
    classification: "established"  # established | emerging
    tradeoff_axis: "integration vs reimplementation"
    chosen_pole: "integration"
    evidence:
      - path: "docs/brainstorms/2026-03-08-cass-brainstorm.md"
        bead: "Demarch-abc1"
        excerpt: "Chose to integrate CASS rather than build session search"
      - path: "docs/prds/2026-03-05-data-driven-plugin-boundaries.md"
        bead: "Demarch-def2"
        excerpt: "Adopt existing boundary detection over custom implementation"
    unique_decisions: 4
    time_span: { earliest: "2026-02-28", latest: "2026-03-15" }
    philosophy_match: "Composition Over Capability"
    proposed_text: "When a mature external tool exists, default to integration over reimplementation."
    proposed_section: "Composition Over Capability"
    status: "pending"  # pending | accepted | rejected | deferred
    rejection_reason: null
    decided_at: null
rejected_patterns:
  - tradeoff_axis: "..."
    rejected_at: "2026-03-20"
    reason: "Too specific to one domain"
```

### F4: interlore:review — Interactive Proposal Review

**What:** Command that walks through pending proposals, allowing accept/reject/defer with evidence display.

**Acceptance criteria:**
- [ ] Reads `.interlore/proposals.yaml` and presents pending proposals sequentially
- [ ] For each: shows tradeoff axis, chosen pole, evidence with excerpts, proposed PHILOSOPHY.md text, classification level
- [ ] Accept: applies proposed text to PHILOSOPHY.md at specified section, updates proposal status to "accepted" with timestamp
- [ ] Reject: updates proposal status to "rejected" with reason, adds tradeoff_axis to `rejected_patterns` list (prevents re-proposal on future scans)
- [ ] Defer: keeps proposal as "pending" for next review cycle
- [ ] Updates `.interlore/proposals.yaml` after each decision (not batched at end — survives interrupted sessions)
- [ ] Empty/no pending proposals: "No pending proposals. Run /interlore:scan first."
- [ ] Dry-run mode: `--dry-run` shows what would be proposed without writing

## Deferred: Integration Wiring (separate beads)

The following integrations ship as separate beads in their respective plugin owners, not as part of the interlore epic. interlore works fully standalone via `/interlore:scan` and `/interlore:review`.

### Clavain: Sprint Stop dispatch tier
- Extend `auto-stop-actions.sh` with opt-in `interlore_scan_quiet` dispatch tier (gated on `CLAVAIN_INTERLORE_PASSIVE=true`)
- Do NOT register a competing Stop hook in interlore's hooks.json — that conflicts with Clavain's sentinel

### interdoc: Philosophy alignment protocol fix
- Make interdoc actually Read PHILOSOPHY.md during generation (currently inert prose)
- interdoc reads `.interlore/proposals.yaml` if present for alignment context (decoupled — no interlore import)

### interwatch: Philosophy drift signal
- Add PHILOSOPHY.md watchable with appropriate signal type following interwatch naming conventions
- Ship checker function following `_watch_roadmap_bead_coverage` pattern

## Non-goals

- Auto-applying philosophy changes (always propose, never commit)
- Replacing interdoc's AGENTS.md generation
- Cross-project philosophy detection (monorepo-scoped only for v1; subproject PHILOSOPHY.md expansion deferred)
- Fully autonomous pattern detection without LLM mediation (v1 is an LLM skill, not a deterministic script)

## Dependencies

- Beads tracker (for bead ID deduplication in evidence)
- interpath source catalog (for artifact discovery patterns — documentation reuse, not runtime coupling)

## Resolved Questions

1. **Pattern storage:** Structured YAML (`.interlore/proposals.yaml`). Git-trackable, schema-defined, readable by downstream consumers without importing interlore internals.
2. **interdoc integration depth:** interdoc reads the staging file. No coupling — interlore doesn't call interdoc, interdoc doesn't call interlore.
3. **State directory:** `.interlore/` (standalone plugin, not kernel-native — `.clavain/` is kernel-owned territory).
4. **Signal extraction primary source:** Content-based pattern extraction. Alignment/Conflict lines are enrichment only (<2% coverage in actual corpus).
5. **Decision counting:** By unique bead IDs, not artifact count. Prevents citation-chain inflation.

## Open Questions

1. **Calibration path.** v1 records accept/reject outcomes but doesn't auto-adjust thresholds. Design should include a calibration data model (accepted_count, rejected_count per tradeoff_axis) even if the adjustment logic is deferred to v2.
2. **Conflicting patterns.** When artifacts show evidence for both poles of a tradeoff (e.g., some chose "flat files", others chose "SQLite"), surface as a tension proposal rather than two independent proposals. Design the tension detection in v1 or defer?
3. **Cross-project scope.** v1 is project-root only. If expanded, should subproject PHILOSOPHY.md inherit from root PHILOSOPHY.md, or be fully independent?
