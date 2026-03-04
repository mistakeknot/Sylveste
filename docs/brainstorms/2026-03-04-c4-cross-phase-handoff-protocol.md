# C4: Cross-Phase Handoff Protocol — Brainstorm

**Bead:** iv-1vny
**Date:** 2026-03-04
**Context:** C3 Composer shipped. C1 agency specs, C2 fleet registry, A3 event-driven advancement all closed. C4 is the sole remaining blocker for C5 (self-building loop). The goal: make handoffs between macro-stages structured and machine-validatable.

---

## Problem Statement

Clavain's sprint pipeline has five macro-stages: Discover → Design → Build → Ship → Reflect. Each produces artifacts that the next stage consumes. Today, these handoffs are *implicit*:

1. **Existence-only gates** — The gate system checks `artifact_exists` (file present at path) but not artifact *content*. A brainstorm doc that's just a title line passes the gate.
2. **No content contracts** — Nothing declares "a brainstorm must contain a Problem Statement, a Research section, and at least one Proposed Approach." The consuming stage discovers missing content at runtime, wastes tokens, or silently produces lower-quality output.
3. **No cross-stage type linking** — The per-stage YAML files independently declare `artifacts.required` and `artifacts.produces`, but there's no formal assertion that `design.required[brainstorm]` is the *same type* as `discover.produces[brainstorm]`. A rename in one breaks the chain silently.
4. **No structured artifact metadata** — Artifacts are registered with `ic run artifact add --type=brainstorm --path=file.md`. There's no machine-readable frontmatter or structured header that a validator can parse without understanding markdown.

### Why This Matters for C5

The self-building loop requires Clavain to orchestrate its own sprints *without human intervention at phase boundaries*. If handoffs can't be validated programmatically, the loop either:
- Fails silently (bad artifact passes, downstream stage produces garbage)
- Requires human checkpoint (defeats the purpose of self-building)

---

## Current State Analysis

### What Already Works

| Component | Status | What It Does |
|-----------|--------|-------------|
| Per-stage YAML (`config/agency/*.yaml`) | ✅ Shipped | Declares `artifacts.required[]` and `artifacts.produces[]` per stage with type + phase |
| Agency spec (`config/agency-spec.yaml`) | ✅ Shipped | Declares artifacts with type, path_pattern, required flag per stage |
| Gate system (`enforce-gate` in Go) | ✅ Shipped | Checks `artifact_exists`, `phase_completed`, `verdict_clean`, `command` |
| Artifact registration (`set-artifact`/`get-artifact`) | ✅ Shipped | Records type→path in Intercore via `ic run artifact add` |
| Checkpoint system | ✅ Shipped | Records completed steps + plan path for resume |
| Composer (C3) | ✅ Shipped | Reads agency spec + fleet registry, produces dispatch plan JSON |

### What's Missing

| Gap | Impact |
|-----|--------|
| **Content contracts** — required sections/fields per artifact type | Downstream stages get garbage input, waste tokens |
| **Cross-stage linkage** — formal assertion that produce type = consume type | Rename breaks chain silently |
| **Artifact frontmatter** — structured header in artifacts | Validator can't parse without markdown understanding |
| **Validate-handoff command** — CLI entry point for handoff validation | No way to check before advancing |
| **Handoff metadata in gate evidence** — which fields passed/failed | No diagnostic info when gate blocks |

---

## Design Options

### Option A: Frontmatter Schema — YAML headers in markdown artifacts

Each artifact gets a YAML frontmatter block declaring its type, required fields present, and metadata:

```yaml
---
artifact_type: brainstorm
bead: iv-1vny
stage: discover
produced_at: 2026-03-04T10:00:00Z
sections:
  - problem_statement
  - research
  - proposed_approaches
  - tradeoffs
---
# C4: Cross-Phase Handoff Protocol — Brainstorm
...
```

The handoff contract declares what sections each type must contain:

```yaml
# In config/handoff-contracts.yaml
contracts:
  brainstorm:
    required_sections:
      - problem_statement
      - research  # or alternatives_considered
      - proposed_approaches
    optional_sections:
      - tradeoffs
      - open_questions
    min_word_count: 200
    frontmatter_required: true
```

**Pros:**
- Self-describing artifacts — validator reads frontmatter, checks sections exist
- Backward-compatible — existing artifacts just lack frontmatter (soft fail)
- Human-readable — YAML frontmatter is a well-known convention (Hugo, Jekyll, Obsidian)
- Composable — project overrides can extend contracts

**Cons:**
- Requires all skill templates to emit frontmatter (migration cost)
- Section names must be standardized (h2 headers → section IDs)
- Fragile to creative formatting (what if someone uses different heading levels?)

### Option B: Sidecar Manifest — JSON manifest alongside each artifact

Each artifact gets a companion `.manifest.json`:

```
docs/brainstorms/2026-03-04-c4.md
docs/brainstorms/2026-03-04-c4.manifest.json
```

```json
{
  "artifact_type": "brainstorm",
  "bead": "iv-1vny",
  "stage": "discover",
  "produced_at": "2026-03-04T10:00:00Z",
  "sections": ["problem_statement", "research", "proposed_approaches"],
  "word_count": 1542,
  "checksum": "sha256:abc123..."
}
```

**Pros:**
- Clean separation — artifact content untouched
- Machine-parseable without markdown understanding
- Can include checksums for integrity
- Easy to extend (add quality scores, token counts, etc.)

**Cons:**
- Two files per artifact (clutter, sync issues)
- Easy to forget the manifest (artifact created without companion)
- Must be explicitly generated (extra step in skill templates)
- Less discoverable than frontmatter

### Option C: Kernel-Native Contracts — all validation in Intercore

Move contract definitions into Intercore's gate system. Each artifact registration includes structured metadata, and Intercore validates on `run advance`:

```bash
ic run artifact add <run_id> \
  --type=brainstorm \
  --path=docs/brainstorms/2026-03-04-c4.md \
  --metadata='{"sections":["problem_statement","research","proposed_approaches"],"word_count":1542}'
```

Gate definition extended:

```yaml
gates:
  entry:
    - check: artifact_contract
      type: brainstorm
      require_sections: [problem_statement, research, proposed_approaches]
      min_word_count: 200
```

**Pros:**
- Single source of truth — kernel enforces contracts
- No filesystem artifacts to keep in sync
- Integrates naturally with existing gate system
- Metadata already stored in ic (run artifact list returns it)

**Cons:**
- Requires Intercore changes (new gate type, metadata field on artifacts)
- Tighter coupling between Clavain and Intercore versions
- Metadata must be computed at registration time (skill must know the contract)
- Less visible — metadata hidden in ic state, not in the artifact file

### Option D: Hybrid — Frontmatter + Kernel Validation

Combine A and C: artifacts carry frontmatter (self-describing), but validation is enforced by the kernel via a new `artifact_contract` gate type. clavain-cli reads frontmatter, computes metadata, and passes it to `ic run artifact add --metadata=...`. The kernel validates contracts on `run advance`.

```
Artifact file:
  YAML frontmatter → declares sections, type, metadata

Registration:
  clavain-cli set-artifact → reads frontmatter → passes to ic

Validation:
  clavain-cli validate-handoff → checks contracts locally
  ic gate check → validates on advance (redundant safety net)
```

**Pros:**
- Self-describing artifacts (human + machine readable)
- Kernel as backstop (catches drift between frontmatter and reality)
- Local validation before advance (fast feedback)
- Graceful degradation (works without ic, works without frontmatter in shadow mode)

**Cons:**
- Two validation paths (potential inconsistency)
- More moving parts
- Requires both Clavain and Intercore changes

---

## Recommendation: Option A (Frontmatter Schema) with Kernel Opt-In Later

**Start with frontmatter + local validation only.** This is the minimum viable handoff protocol:

1. **Define contracts** in `config/handoff-contracts.yaml` — required sections, optional sections, min quality thresholds per artifact type
2. **Add frontmatter** to skill templates (brainstorm, strategy, write-plan, reflect) — emitted automatically
3. **Build `validate-handoff` command** in clavain-cli (Go) — reads frontmatter, checks against contract, outputs pass/fail with evidence
4. **Wire into gate system** as a new gate type (`artifact_contract`) in existing Go code — calls `validate-handoff` internally
5. **Shadow mode first** — validate and warn, don't block. Graduate to enforce after a few sprints of data.

This avoids Intercore changes (keeping C4 scoped to Clavain), uses existing infrastructure (gates, artifacts, agency spec), and produces self-describing artifacts that humans can inspect.

### Why Not Start with Kernel-Native (Option C)?

- Intercore changes increase scope and coupling
- C4 should be deliverable in one session
- Can add kernel validation later as a safety net (Option D) without breaking anything

---

## Detailed Design: Handoff Contracts

### Contract Schema

```yaml
# config/handoff-contracts.yaml
version: "1.0"

# Contracts keyed by artifact type (matches artifacts.produces[].type in agency YAML)
contracts:
  brainstorm:
    description: "Problem exploration with research and proposed approaches"
    produced_by: discover
    consumed_by: [design]
    frontmatter:
      required_fields: [artifact_type, bead, stage]
    content:
      required_sections:
        - id: problem_statement
          heading_pattern: "Problem|Problem Statement"
          min_words: 50
        - id: research
          heading_pattern: "Research|Analysis|Current State"
        - id: approaches
          heading_pattern: "Approach|Proposed|Options|Design"
      optional_sections:
        - id: tradeoffs
          heading_pattern: "Tradeoff|Trade-off|Comparison"
        - id: open_questions
          heading_pattern: "Open Question|TBD|Unresolved"
      min_total_words: 200

  prd:
    description: "Product requirements with features and acceptance criteria"
    produced_by: design
    consumed_by: [design, build]
    frontmatter:
      required_fields: [artifact_type, bead, stage]
    content:
      required_sections:
        - id: summary
          heading_pattern: "Summary|Overview|Goal"
        - id: features
          heading_pattern: "Feature|Requirement|Scope"
        - id: acceptance_criteria
          heading_pattern: "Acceptance|Criteria|Done.*When|Definition.*Done"
      optional_sections:
        - id: non_goals
          heading_pattern: "Non.?Goal|Out.*Scope|Excluded"
      min_total_words: 300

  plan:
    description: "Implementation plan with tasks and file targets"
    produced_by: design
    consumed_by: [build]
    frontmatter:
      required_fields: [artifact_type, bead, stage]
    content:
      required_sections:
        - id: tasks
          heading_pattern: "Task\\s+\\d|Step\\s+\\d|Phase\\s+\\d"
          min_count: 1  # At least one task heading
      optional_sections:
        - id: prior_learnings
          heading_pattern: "Prior.*Learn|Learnings|Context"
      # Plans must reference at least one file path
      content_patterns:
        - pattern: "[A-Za-z_/]+\\.[a-z]{1,4}"
          description: "Must reference at least one file path"

  verdict:
    description: "Review verdict from quality gates"
    produced_by: build
    consumed_by: [ship]
    # Verdicts are structured text, not markdown
    content:
      required_patterns:
        - pattern: "^TYPE:\\s+(verdict|implementation)"
          description: "Must start with TYPE header"
        - pattern: "^STATUS:\\s+(CLEAN|NEEDS_ATTENTION|BLOCKED|ERROR|COMPLETE|PARTIAL|FAILED)"
          description: "Must have STATUS line"
      optional_patterns:
        - pattern: "^MODEL:"
        - pattern: "^TOKENS_SPENT:"

  reflection:
    description: "Sprint learnings and retrospective"
    produced_by: reflect
    consumed_by: []  # Terminal — consumed by memory, not a stage
    frontmatter:
      required_fields: [artifact_type, bead]
    content:
      required_sections:
        - id: learnings
          heading_pattern: "Learning|Key.*Insight|What.*Learn"
      optional_sections:
        - id: what_went_well
          heading_pattern: "Went.*Well|Success|Win"
        - id: improvements
          heading_pattern: "Improve|Next.*Time|Could.*Better"
      min_total_words: 100
```

### Cross-Stage Linkage

The `produced_by` / `consumed_by` fields create a directed graph:

```
discover.produces[brainstorm] ──→ design.requires[brainstorm]
design.produces[prd]          ──→ design.requires[prd] (self-consume for plan stage)
design.produces[plan]         ──→ build.requires[plan]
build.produces[verdict]       ──→ ship.requires[verdict]
reflect.produces[reflection]  ──→ (terminal)
```

The `validate-handoff` command can check:
1. Every `consumed_by` stage has a matching `artifacts.required` entry
2. Every `produced_by` stage has a matching `artifacts.produces` entry
3. No orphaned contracts (type defined but never produced or consumed)

### Frontmatter Schema

```yaml
---
artifact_type: brainstorm    # Must match a contract key
bead: iv-1vny                # Links to tracking
stage: discover              # Must match contract's produced_by
produced_at: 2026-03-04T10:00:00Z  # Optional: timestamp
sprint: iv-xyz               # Optional: parent sprint bead
sections:                    # Optional: self-declared sections (validated against headings)
  - problem_statement
  - research
  - approaches
---
```

### Validation Flow

```
┌─────────────┐
│ skill emits  │ ─── artifact with frontmatter ──→ docs/brainstorms/*.md
│ brainstorm   │
└─────────────┘
       │
       ▼
┌─────────────┐
│ set-artifact │ ─── register artifact in ic ──→ ic run artifact add
│ (Go CLI)     │     (reads frontmatter, passes type + metadata)
└─────────────┘
       │
       ▼
┌─────────────┐
│ sprint-      │ ─── calls validate-handoff internally ──→
│ advance      │     checks contracts before allowing advance
└─────────────┘
       │
       ▼
┌──────────────┐
│ validate-    │
│ handoff      │
│ (Go CLI)     │
│              │
│ 1. Load      │ ─── config/handoff-contracts.yaml
│    contract  │
│              │
│ 2. Read      │ ─── parse YAML frontmatter from artifact
│    artifact  │
│              │
│ 3. Check     │ ─── match heading patterns against content
│    sections  │
│              │
│ 4. Check     │ ─── word count, content patterns
│    quality   │
│              │
│ 5. Output    │ ─── JSON result with pass/fail + evidence
│    result    │
└──────────────┘
```

### Output Format

```json
{
  "artifact_type": "brainstorm",
  "artifact_path": "docs/brainstorms/2026-03-04-c4.md",
  "contract_version": "1.0",
  "result": "pass",
  "checks": [
    {"check": "frontmatter_present", "result": "pass"},
    {"check": "frontmatter_field:artifact_type", "result": "pass"},
    {"check": "frontmatter_field:bead", "result": "pass"},
    {"check": "section:problem_statement", "result": "pass", "heading": "## Problem Statement", "line": 12},
    {"check": "section:research", "result": "pass", "heading": "## Current State Analysis", "line": 34},
    {"check": "section:approaches", "result": "pass", "heading": "## Design Options", "line": 78},
    {"check": "min_total_words", "result": "pass", "actual": 1542, "required": 200}
  ],
  "warnings": []
}
```

### Shadow Mode

Initial rollout uses `gate_mode: shadow` (already the default in agency-spec.yaml). In shadow mode:
- `validate-handoff` runs and logs results
- Gate system records pass/fail in evidence but doesn't block advance
- After N sprints of clean data, graduate to `enforce`

---

## Implementation Scope

### In Scope (This Sprint)

1. `config/handoff-contracts.yaml` — contract definitions for all 5 artifact types
2. `validate-handoff` Go command in clavain-cli — parse frontmatter, check contracts, output JSON
3. New gate type `artifact_contract` wired into `enforce-gate`
4. Update `set-artifact` to read and validate frontmatter when present
5. Update skill templates to emit frontmatter (brainstorm, strategy, write-plan, reflect)
6. Bats integration tests for valid/invalid artifacts
7. Cross-stage linkage validation (contract graph consistency)

### Out of Scope (Future)

- Kernel-native contract enforcement (Intercore changes)
- Automatic remediation (suggesting missing sections)
- Content quality scoring beyond word count
- Artifact versioning/diffing
- Contract inheritance/composition across projects

---

## Open Questions

1. **Should verdict contracts validate the structured header only, or also check the detail file at `DETAIL_PATH`?** Recommendation: header only — detail files are for human consumption.

2. **How strict should section heading matching be?** Using regex patterns allows flexibility ("Problem|Problem Statement") but could false-positive on unrelated headings. Recommendation: require h2 (`##`) level headings only, case-insensitive match.

3. **Should `validate-handoff` be callable standalone (for pre-commit hooks) or only through the gate system?** Recommendation: standalone command + gate integration. Useful for skill authors to test their templates.

4. **What happens when a project override changes a contract?** Recommendation: project-level `handoff-contracts.yaml` merges with defaults (same semantics as agency-spec override).
