---
artifact_type: plan
bead: Demarch-bncp
stage: design
requirements:
  - F1: Doc hierarchy restructure
  - F2: interlore plugin scaffold
  - F3: interlore:scan pattern detection engine
  - F4: interlore:review interactive proposal review
---
# interlore Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-bncp
**Goal:** Create MISSION.md, restructure doc hierarchy, and build interlore plugin with scan + review capabilities.

**Architecture:** interlore is a standalone Interverse plugin at `interverse/interlore/`. It has one skill (`observe`) that powers the scan engine, and three commands (`scan`, `review`, `status`). State lives in `.interlore/` at project root. Artifact discovery reuses interpath's source catalog patterns. Signal extraction is content-based (tradeoff language), with Alignment/Conflict lines as enrichment.

**Tech Stack:** Claude Code plugin (markdown skills/commands), YAML for proposals schema, pytest for structural tests, bash for bump script.

**Prior Learnings:**
- `docs/solutions/patterns/cross-document-philosophy-alignment-20260227.md` — document drift is a known problem; static counts rot, terminology diverges. interlore addresses this systematically.
- CASS session: interdeep scaffold (2025-02-28) provides exact directory structure, plugin.json, and test patterns to replicate.

---

## Must-Haves

**Truths** (observable behaviors):
- User can run `/interlore:scan` and get a `.interlore/proposals.yaml` file with detected patterns
- User can run `/interlore:review` and accept/reject/defer proposals interactively
- User can run `/interlore:status` and see scan summary with proposal counts
- MISSION.md exists at project root and doc-structure canon reflects the new hierarchy
- Plugin loads without error in Claude Code (`claude --plugin-dir interverse/interlore`)

**Artifacts** (files with specific exports):
- `MISSION.md` at project root
- `docs/canon/doc-structure.md` with updated hierarchy
- `interverse/interlore/.claude-plugin/plugin.json` with valid schema
- `interverse/interlore/skills/observe/SKILL.md` with scan logic
- `interverse/interlore/commands/{scan,review,status}.md`
- `.interlore/proposals.yaml` (created by scan)

**Key Links:**
- scan command invokes observe skill → skill reads artifacts via interpath catalog patterns → writes `.interlore/proposals.yaml`
- review command reads `.interlore/proposals.yaml` → presents proposals → updates yaml + optionally writes to PHILOSOPHY.md
- status command reads `.interlore/proposals.yaml` → displays summary

---

### Task 1: Create MISSION.md and update doc hierarchy [F1]

**Bead:** Demarch-wdiw
**Files:**
- Create: `MISSION.md`
- Modify: `docs/canon/doc-structure.md`
- Modify: `docs/canon/plugin-standard.md`
- Modify: `PHILOSOPHY.md` (trim mission-level "why")

**Step 1: Create MISSION.md**
```markdown
# Demarch Mission

Build the infrastructure that lets AI agents do real software engineering work autonomously, safely, and at scale. Prove that the bottleneck is plumbing, not intelligence — and that compounding evidence is the path to earned trust.
```

**Step 2: Trim PHILOSOPHY.md opening**
The current opening says: "The design bets, tradeoffs, and convictions that inform everything else." and "CLAUDE.md says *how to work here*. AGENTS.md says *what to build and how*. This document says *why these tradeoffs and not others*."

Replace with: "The design bets, tradeoffs, and principles that guide how we build. See MISSION.md for why this project exists."

Keep the three principles and core bet in PHILOSOPHY.md — they are philosophy, not mission.

**Step 3: Update docs/canon/doc-structure.md**
Replace the `docs/canon/` section (lines 76-87) with the new hierarchy:

```markdown
## Document Hierarchy

Three root documents, each with a distinct purpose:

```
MISSION.md                  — why the project exists (rarely changes)
  ├→ docs/demarch-vision.md — where it's going (existing vision doc, v3.4)
  └→ PHILOSOPHY.md          — how we build (design bets, principles)
       └→ derived: PRDs, Roadmap, CUJs, AGENTS.md conventions
```

| Document | Changes | Who updates |
|----------|---------|-------------|
| MISSION.md | Almost never | Human only |
| VISION.md | Quarterly | Human, interpath drafts |
| PHILOSOPHY.md | When latent patterns detected | Human, interlore proposes |

Conflict resolution: MISSION.md takes precedence when VISION and PHILOSOPHY conflict.

## docs/canon/

Foundational docs that define project standards:

```
docs/canon/
├── doc-structure.md      # This file
├── plugin-standard.md    # Structural quality bar for Interverse plugins
└── naming.md             # Naming conventions (currently at docs/guides/naming-conventions.md)
```

Root keeps: MISSION.md, CLAUDE.md, AGENTS.md (auto-loaded). PHILOSOPHY.md stays at project root (hierarchy position — sibling of VISION, derived from MISSION).
```

**Step 4: Update docs/canon/plugin-standard.md**
Add a note in the AGENTS.md Standard Header section that monorepo projects should reference MISSION.md in their root-level AGENTS.md. Do NOT add MISSION.md to the per-plugin boilerplate template — plugins don't have their own MISSION.md and the relative path would break for standalone clones. The change is additive documentation, not a structural requirement change.

**Step 5: Verify PHILOSOPHY.md trimming**
After Step 2, confirm PHILOSOPHY.md no longer contains the mission-level "why" text that was moved to MISSION.md. The opening should say "how we build", not "why these tradeoffs".

**Step 6: Commit**
```bash
git add MISSION.md PHILOSOPHY.md docs/canon/doc-structure.md docs/canon/plugin-standard.md
git commit -m "feat: add MISSION.md, restructure doc hierarchy (MISSION → VISION + PHILOSOPHY)"
```

<verify>
- run: `test -f MISSION.md && echo "exists"`
  expect: contains "exists"
- run: `grep -c "Document Hierarchy" docs/canon/doc-structure.md`
  expect: contains "1"
- run: `grep "how we build" PHILOSOPHY.md`
  expect: exit 0
- run: `grep -c "MISSION" docs/canon/doc-structure.md`
  expect: exit 0
</verify>

---

### Task 2: Scaffold interlore plugin [F2]

**Bead:** Demarch-28rf
**Depends:** none (parallel with Task 1)
**Files:**
- Create: `interverse/interlore/` (full plugin structure)

**Step 1: Create directory structure**
```bash
mkdir -p interverse/interlore/.claude-plugin
mkdir -p interverse/interlore/skills/observe
mkdir -p interverse/interlore/commands
mkdir -p interverse/interlore/scripts
mkdir -p interverse/interlore/tests/structural
mkdir -p interverse/interlore/docs
```

**Step 2: Create `.claude-plugin/plugin.json`**
```json
{
  "name": "interlore",
  "version": "0.1.0",
  "description": "Philosophy observer — detects latent design patterns and philosophy drift from decision artifacts, proposes PHILOSOPHY.md updates.",
  "author": { "name": "mistakeknot" },
  "license": "MIT",
  "keywords": ["philosophy", "patterns", "alignment", "drift-detection"],
  "skills": [
    "./skills/observe"
  ],
  "commands": [
    "./commands/scan.md",
    "./commands/review.md",
    "./commands/status.md"
  ]
}
```

**Step 3: Create 6 required root files**

`README.md`:
```markdown
# interlore

Philosophy observer for the Demarch ecosystem. Detects latent design patterns across brainstorms, PRDs, and flux-drive outputs. Proposes PHILOSOPHY.md updates with evidence links.

## Installation

```bash
claude plugin add interlore@interagency-marketplace
claude plugin update interlore@interagency-marketplace
```

## Usage

- `/interlore:scan` — Scan artifacts for design patterns, write proposals
- `/interlore:review` — Walk through proposals, accept/reject/defer
- `/interlore:status` — Show scan summary and proposal counts

## Architecture

```
interlore/
├── .claude-plugin/plugin.json
├── skills/observe/SKILL.md     # Scan engine
├── commands/                   # scan, review, status
├── tests/structural/           # pytest structural suite
└── scripts/bump-version.sh
```
```

`CLAUDE.md` (under 60 lines):
```markdown
# interlore

> See `AGENTS.md` for full development guide.

## Overview

Philosophy observer — 1 skill, 3 commands, 0 agents, 0 hooks, 0 MCP servers. Standalone Interverse plugin. Detects design patterns from decision artifacts and proposes PHILOSOPHY.md updates.

## Quick Commands

```bash
claude --plugin-dir /path/to/interlore
ls skills/*/SKILL.md | wc -l          # Should be 1
ls commands/*.md | wc -l              # Should be 3
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"
```

## Design Decisions (Do Not Re-Ask)

- Namespace: `interlore:` (standalone, not Clavain companion)
- State directory: `.interlore/` at project root (not `.clavain/` — standalone plugin)
- Signal extraction: content-based primary, Alignment/Conflict lines as enrichment
- Proposals format: structured YAML (`.interlore/proposals.yaml`)
- Propose only, never auto-apply PHILOSOPHY.md changes
- Artifact discovery: follows interpath source catalog patterns (no independent crawling)
- Deduplication: by bead ID, not artifact count
```

`AGENTS.md`:
```markdown
# AGENTS.md — interlore

Philosophy observer plugin. Scans decision artifacts (brainstorms, PRDs, flux-drive outputs, plans) to detect recurring design patterns and philosophy drift. Proposes PHILOSOPHY.md updates with evidence links.

**Plugin Type:** Claude Code skill plugin
**Plugin Namespace:** `interlore`
**Current Version:** 0.1.0

## Canonical References
1. [`MISSION.md`](../../MISSION.md) — project mission.
2. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — design bets and principles (what interlore observes and proposes updates to).

## Philosophy Alignment Protocol
Review [`PHILOSOPHY.md`](../../PHILOSOPHY.md) during intake, brainstorming, planning, execution, review, and handoff.

For brainstorming/planning outputs, add:
- **Alignment:** one sentence on how the proposal supports Demarch's philosophy.
- **Conflict/Risk:** one sentence on any tension with philosophy (or 'none').

## Architecture

interlore has three layers:
1. **Artifact discovery** — glob patterns from interpath source catalog
2. **Pattern extraction** — content-based tradeoff detection + Alignment/Conflict enrichment
3. **Proposal management** — structured YAML staging with accept/reject/defer lifecycle

State: `.interlore/proposals.yaml` at project root.
```

`PHILOSOPHY.md`:
```markdown
# interlore Philosophy

## Purpose
Make implicit design decisions explicit. Close the feedback loop between what a project does and what it says it believes.

## North Star
Every decision is evidence. Philosophy should emerge from practice, not be imposed top-down.

## Working Priorities
1. Signal quality over coverage — one correct detection beats ten noisy ones
2. Propose, never apply — humans own philosophy
3. Evidence transparency — every proposal shows its evidence chain

## Decision Filters
- Does this detection reliably distinguish signal from noise?
- Would a human reviewing this proposal have enough context to decide?
- Does this respect the boundary between interlore (detect) and interdoc (generate)?
```

`LICENSE`: Standard MIT, copyright MK.

`.gitignore`:
```
node_modules/
__pycache__/
*.pyc
.venv/
.pytest_cache/
.claude/
.beads/
*.log
*.egg-info/
dist/
build/
.ruff_cache/
```

**Step 4: Create `scripts/bump-version.sh`** (executable)
```bash
#!/usr/bin/env bash
set -euo pipefail
if command -v ic &>/dev/null; then
    exec ic publish "${1:---patch}"
else
    echo "ic not available — use interbump.sh" >&2
    exit 1
fi
```

**Step 5: Create test suite**

`tests/pyproject.toml` (note: at tests/ level, not tests/structural/):
```toml
[project]
name = "interlore-tests"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["pytest>=8.0", "pyyaml>=6.0"]
```

`tests/structural/conftest.py`:
```python
import pathlib
import pytest

@pytest.fixture
def plugin_root():
    return pathlib.Path(__file__).parent.parent.parent

@pytest.fixture
def plugin_json(plugin_root):
    import json
    manifest = plugin_root / ".claude-plugin" / "plugin.json"
    return json.loads(manifest.read_text())
```

`tests/structural/helpers.py`:
```python
import pathlib

def skill_dirs(plugin_root: pathlib.Path) -> list[pathlib.Path]:
    skills = plugin_root / "skills"
    return [d for d in skills.iterdir() if d.is_dir() and (d / "SKILL.md").exists()]

def command_files(plugin_root: pathlib.Path) -> list[pathlib.Path]:
    commands = plugin_root / "commands"
    if not commands.exists():
        return []
    return sorted(commands.glob("*.md"))
```

`tests/structural/test_structure.py`:
```python
import json
import pathlib

def test_required_files(plugin_root):
    required = ["CLAUDE.md", "AGENTS.md", "README.md", "PHILOSOPHY.md", "LICENSE", ".gitignore"]
    for f in required:
        assert (plugin_root / f).exists(), f"Missing required file: {f}"

def test_plugin_json_valid(plugin_root):
    manifest = plugin_root / ".claude-plugin" / "plugin.json"
    assert manifest.exists()
    data = json.loads(manifest.read_text())
    assert data["name"] == "interlore"
    assert "version" in data
    assert "author" in data

def test_skills_layout(plugin_root, plugin_json):
    for skill_ref in plugin_json.get("skills", []):
        skill_path = plugin_root / skill_ref.lstrip("./")
        assert skill_path.is_dir(), f"Skill must be a directory: {skill_ref}"
        assert (skill_path / "SKILL.md").exists(), f"Missing SKILL.md in {skill_ref}"

def test_commands_exist(plugin_root, plugin_json):
    for cmd_ref in plugin_json.get("commands", []):
        cmd_path = plugin_root / cmd_ref.lstrip("./")
        assert cmd_path.exists(), f"Missing command: {cmd_ref}"

def test_bump_script(plugin_root):
    bump = plugin_root / "scripts" / "bump-version.sh"
    assert bump.exists()
```

`tests/structural/test_skills.py`:
```python
from helpers import skill_dirs

def test_observe_skill_exists(plugin_root):
    observe = plugin_root / "skills" / "observe" / "SKILL.md"
    assert observe.exists()
    content = observe.read_text()
    assert "name:" in content or "description:" in content
```

**Step 6: Create stub command files**

`commands/scan.md`:
```markdown
---
name: scan
description: Scan decision artifacts for design patterns and philosophy drift, write proposals to .interlore/proposals.yaml
---
Use the skill `interlore:observe` with the instruction: "Scan for design patterns."
```

`commands/review.md`:
```markdown
---
name: review
description: Walk through pending proposals — accept, reject, or defer each with evidence display
---
Use the skill `interlore:observe` with the instruction: "Review pending proposals interactively."
```

`commands/status.md`:
```markdown
---
name: status
description: Show scan summary — last scan date, proposal counts by type and classification
---
Use the skill `interlore:observe` with the instruction: "Show interlore status summary."
```

**Step 7: Create stub skill**

`skills/observe/SKILL.md` (stub — full content in Task 3):
```markdown
---
name: observe
description: Scan decision artifacts for latent design patterns and philosophy drift. Write structured proposals to .interlore/proposals.yaml.
---
You are the interlore observer. Follow the instruction provided by the invoking command.

## Stub
This skill will be fully implemented in Task 3.
```

**Step 8: Init git repo and commit**
```bash
cd interverse/interlore && git init && git add -A && git commit -m "feat: scaffold interlore plugin"
```

**Step 9: Run structural tests**
```bash
cd interverse/interlore && uv run pytest tests/structural/ -v
```

<verify>
- run: `cd interverse/interlore && python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"`
  expect: exit 0
- run: `cd interverse/interlore && uv run pytest tests/structural/ -v`
  expect: exit 0
- run: `ls interverse/interlore/skills/observe/SKILL.md`
  expect: exit 0
</verify>

---

### Task 3: Implement interlore:scan (observe skill) [F3]

**Bead:** Demarch-7a8c
**Depends:** Task 2
**Files:**
- Modify: `interverse/interlore/skills/observe/SKILL.md`
- Create: `interverse/interlore/skills/observe/references/proposals-schema.md`
- Create: `interverse/interlore/skills/observe/references/source-patterns.md`

**Step 1: Create proposals schema reference**

`skills/observe/references/proposals-schema.md`:
````markdown
# Proposals Schema

Version 1 of `.interlore/proposals.yaml`.

```yaml
version: 1
last_scan: "2026-03-21T17:00:00Z"
scan_stats:
  artifacts_scanned: 12
  patterns_detected: 5
  proposals_generated: 2
  conforming_patterns: 3
proposals:
  - id: "p-001"
    type: "emerging"           # emerging | drift
    classification: "established"  # established | emerging
    tradeoff_axis: "integration vs reimplementation"
    chosen_pole: "integration"
    evidence:
      - path: "docs/brainstorms/2026-03-08-cass-brainstorm.md"
        bead: "Demarch-abc1"
        excerpt: "Chose to integrate CASS rather than build session search"
    unique_decisions: 4
    time_span:
      earliest: "2026-02-28"
      latest: "2026-03-15"
    philosophy_match: "Composition Over Capability"
    proposed_text: "When a mature external tool exists, default to integration over reimplementation."
    proposed_section: "Composition Over Capability"
    status: "pending"          # pending | accepted | rejected
    rejection_reason: null
    decided_at: null
    first_seen: "2026-03-21T17:00:00Z"
rejected_patterns:
  - tradeoff_axis: "integration vs reimplementation"
    rejected_at: "2026-03-20"
    reason: "Too specific to one domain"
```

## Status transitions
- `pending` → `accepted` (applies to PHILOSOPHY.md)
- `pending` → `rejected` (adds to rejected_patterns)
- Defer action: keeps status as `pending` for next review cycle (no separate status)

## Evidence merge rules
- On rescan: union-merge evidence by path (never overwrite)
- `first_seen` preserves when a proposal was first detected
- `unique_decisions` and `time_span` are recomputed from merged evidence
- If classification upgrades (emerging → established), update classification field

## Classification rules
- **established**: 3+ unique decisions (by bead ID), 2+ weeks time span
- **emerging**: 2 unique decisions
- **nascent**: 1 decision (logged in scan stats, not proposed)

## Proposal types
- **emerging**: pattern not matched by any PHILOSOPHY.md section
- **drift**: decision contradicts a stated PHILOSOPHY.md principle
- **conforming**: matches existing philosophy (logged in stats, not proposed)
````

**Step 2: Create source patterns reference**

`skills/observe/references/source-patterns.md`:
```markdown
# Source Patterns

Artifact discovery follows interpath's source catalog. interlore scans these globs:

| Source | Glob | Extract |
|--------|------|---------|
| Brainstorms | `docs/brainstorms/*.md` | Full text, Alignment/Conflict lines, frontmatter bead ID |
| PRDs | `docs/prds/*.md`, `docs/prd/*.md` | Full text, frontmatter bead ID |
| Plans | `docs/plans/*.md` | Full text, frontmatter bead ID |
| Flux-drive | `.claude/flux-drive-output/fd-*.md` | Full text (no frontmatter) |

## Content-based signal extraction (primary)

Two-pass strategy: frontmatter read (30 lines) + Grep for decision markers + context windows.

Decision marker patterns (ordered by frequency in Demarch corpus):
1. `**Decision:**` — most common (~120+ instances)
2. `## Key Decisions` / `## Design Decisions` — section headers
3. "chose X over Y", "preferred X to Y", "decided against Y" — tradeoff language
4. "default to X", "always X unless", "never Y" — policy language
5. "tradeoff: X vs Y", "X over Y because" — explicit tradeoff declarations

## Alignment/Conflict line extraction (enrichment)

When present in artifacts:
- `**Alignment:**` — confirms a philosophy principle
- `**Conflict/Risk:**` — may indicate drift

These exist in <2% of artifacts. Never rely on them alone.

## Bead ID deduplication

Extract bead ID from YAML frontmatter (`bead:` field). Artifacts sharing a bead count as one decision. Artifacts without bead IDs count as independent decisions.
```

**Step 3: Write the full observe skill**

`skills/observe/SKILL.md`:
````markdown
---
name: observe
description: Scan decision artifacts for latent design patterns and philosophy drift. Write structured proposals to .interlore/proposals.yaml.
---

You are the interlore observer. You detect latent design patterns and philosophy drift by scanning decision artifacts.

## Routing

Parse the invoking instruction to determine mode:
- Contains "scan" or "pattern" → **Scan mode**
- Contains "review" → **Review mode** (see Review section)
- Contains "status" → **Status mode** (see Status section)

---

## Scan Mode

### Phase 1: Discover artifacts

Use Glob to find artifacts matching the patterns in `references/source-patterns.md`:
```
docs/brainstorms/*.md
docs/prds/*.md
docs/prd/*.md
docs/plans/*.md
.claude/flux-drive-output/fd-*.md
```

If no artifacts found across all globs, output: "No decision artifacts found. Nothing to scan." and stop.

If fewer than 3 artifacts total, output: "Found N artifacts — below minimum threshold (3) for meaningful pattern detection." and stop.

### Phase 2: Read PHILOSOPHY.md baseline

Read the project root `PHILOSOPHY.md`. Extract section headers and key principles as the baseline for diffing.

If PHILOSOPHY.md not found, output: "Warning: no PHILOSOPHY.md found — cannot detect drift, only emerging patterns." Continue with emerging-only detection.

### Phase 3: Extract patterns from artifacts

Two-pass strategy per artifact:
**Pass 1 (frontmatter):** Read first 30 lines — extract bead ID from YAML frontmatter, Alignment/Conflict lines if present.
**Pass 2 (decisions):** Use Grep to find decision markers in the full file, then Read context windows (10 lines) around each match.

Decision marker patterns (search with Grep):
- `**Decision:**` — most common format in brainstorms (~120+ instances across corpus)
- `## Key Decisions` / `## Design Decisions` — section headers
- `chose .* over`, `preferred .* to`, `decided against` — tradeoff language
- `default to`, `always .* unless`, `never .*` — policy language
- `**Alignment:**` / `**Conflict/Risk:**` — interdoc enrichment lines

For each detected decision, record: (tradeoff_axis, chosen_pole, artifact_path, bead_id, excerpt)

### Phase 4: Cluster and classify

Group extracted tradeoffs by tradeoff_axis (fuzzy match on axis description). For each cluster:
1. Count unique bead IDs (artifacts without bead = independent)
2. Calculate time span from artifact dates (frontmatter or filename YYYY-MM-DD prefix)
3. Classify: established (3+ unique decisions, 2+ weeks), emerging (2), nascent (1)
4. Match against PHILOSOPHY.md sections:
   - Match found + decisions align → **conforming** (log, don't propose)
   - Match found + decisions contradict → **drift** (propose)
   - No match → **emerging** (propose if established or emerging classification)

### Phase 5: Check rejected patterns

Read existing `.interlore/proposals.yaml` if present. Skip any tradeoff_axis that appears in `rejected_patterns`.

### Phase 6: Write proposals

Ensure `.interlore/` directory exists. Write `.interlore/proposals.yaml` following the schema in `references/proposals-schema.md`.

Preserve existing proposals with status != "pending" (accepted/rejected history). For pending proposals with matching tradeoff_axis: union-merge evidence by path (never drop evidence from prior scans), recompute unique_decisions and time_span from merged evidence, upgrade classification if threshold now met. Set `first_seen` only on initial creation.

Generate proposal IDs as `p-NNN` (incrementing from highest existing ID).

For each emerging proposal, draft `proposed_text` — a 1-2 sentence principle statement and `proposed_section` — which PHILOSOPHY.md section it belongs in (or "New Section" if novel).

Output scan summary:
```
Scan complete:
  Artifacts scanned: N
  Patterns detected: N (N established, N emerging, N nascent)
  Conforming: N (match existing philosophy)
  New proposals: N (N emerging, N drift)
  Skipped: N (previously rejected)
  Wrote: .interlore/proposals.yaml
```

---

## Review Mode

Read `.interlore/proposals.yaml`. If missing or no pending proposals: "No pending proposals. Run /interlore:scan first."

For each proposal with `status: "pending"`, present:

```
Proposal [id]: [type] — [tradeoff_axis]
Classification: [classification] ([unique_decisions] decisions, [time_span])
Chosen pole: [chosen_pole]

Evidence:
  1. [path] (bead: [bead]) — "[excerpt]"
  2. ...

Philosophy match: [philosophy_match or "none — novel pattern"]

Proposed addition to PHILOSOPHY.md §[proposed_section]:
> [proposed_text]
```

Use AskUserQuestion with options: Accept, Reject, Defer.

- **Accept**: Read PHILOSOPHY.md, find the proposed_section, append proposed_text. Update proposal status to "accepted", set decided_at. Write both files.
- **Reject**: AskUserQuestion for rejection reason. Update proposal status to "rejected", set rejection_reason and decided_at. Add tradeoff_axis to rejected_patterns.
- **Defer**: Keep status as "pending", move to next proposal. No status change written — deferred proposals are simply re-presented next review.

Update `.interlore/proposals.yaml` after EACH decision (not batched — survives interrupted sessions). Use Write tool to overwrite the full file with updated state.

After all proposals reviewed, output summary: "Reviewed N proposals: N accepted, N rejected, N deferred."

---

## Status Mode

Read `.interlore/proposals.yaml`. If missing: "No interlore state found. Run /interlore:scan first."

Output:
```
interlore status:
  Last scan: [last_scan]
  Artifacts scanned: [scan_stats.artifacts_scanned]

  Proposals:
    Pending:  N (N emerging, N drift)
    Accepted: N
    Rejected: N

  Classification breakdown:
    Established: N
    Emerging: N

  Rejected patterns: N
```
````

**Step 4: Commit**
```bash
cd interverse/interlore && git add -A && git commit -m "feat: implement interlore:scan observe skill with proposals schema"
```

<verify>
- run: `test -f interverse/interlore/skills/observe/SKILL.md && wc -l < interverse/interlore/skills/observe/SKILL.md`
  expect: exit 0
- run: `test -f interverse/interlore/skills/observe/references/proposals-schema.md`
  expect: exit 0
- run: `cd interverse/interlore && uv run pytest tests/structural/ -v`
  expect: exit 0
</verify>

---

### Task 4: Implement interlore:review and interlore:status commands [F4]

**Bead:** Demarch-2jwp
**Depends:** Task 3
**Files:**
- Modify: `interverse/interlore/commands/review.md`
- Modify: `interverse/interlore/commands/status.md`
- Modify: `interverse/interlore/commands/scan.md`

**Step 1: Finalize command files**

The commands route to the observe skill which already handles all three modes. Update the command descriptions to be more precise:

`commands/scan.md`:
```markdown
---
name: scan
description: Scan decision artifacts for design patterns and philosophy drift. Writes proposals to .interlore/proposals.yaml with evidence links and classification.
---
Use the skill `interlore:observe` with the instruction: "Run a full scan for design patterns and philosophy drift."
```

`commands/review.md`:
```markdown
---
name: review
description: Walk through pending proposals interactively — accept (applies to PHILOSOPHY.md), reject (with reason, prevents re-proposal), or defer each.
---
Use the skill `interlore:observe` with the instruction: "Review pending proposals interactively. For each proposal, present evidence and ask to accept, reject, or defer."

If `--dry-run` is in the arguments, add: "Dry-run mode — show what would be proposed without writing."
```

`commands/status.md`:
```markdown
---
name: status
description: Show interlore scan summary — last scan date, proposal counts by type and classification, rejected patterns count.
---
Use the skill `interlore:observe` with the instruction: "Show interlore status summary."
```

**Step 2: Commit**
```bash
cd interverse/interlore && git add -A && git commit -m "feat: finalize scan, review, status commands"
```

<verify>
- run: `cd interverse/interlore && uv run pytest tests/structural/ -v`
  expect: exit 0
- run: `grep -c "description:" interverse/interlore/commands/scan.md`
  expect: contains "1"
</verify>

---

### Task 5: Integration test — end-to-end scan on real artifacts [F3, F4]

**Bead:** Demarch-7a8c
**Depends:** Task 3, Task 4
**Files:**
- No new files — validation only

**Step 1: Verify plugin loads**
```bash
cd /home/mk/projects/Demarch && claude --plugin-dir interverse/interlore --print "list your interlore commands" 2>&1 | head -20
```
Expected: Shows interlore:scan, interlore:review, interlore:status.

If plugin loading fails, debug by checking plugin.json schema, skill paths, and command paths.

**Step 2: Manual scan test**
Run `/interlore:scan` against the Demarch monorepo's real artifacts. Verify:
- `.interlore/proposals.yaml` is created
- Schema matches `references/proposals-schema.md`
- At least one pattern detected (the "integration over reimplementation" pattern should appear given CASS, interwatch, etc.)

**Step 3: Manual status test**
Run `/interlore:status`. Verify output matches expected format.

**Step 4: Commit .interlore/ to .gitignore if needed**
```bash
echo ".interlore/" >> .gitignore  # project root — scan output is ephemeral
git add .gitignore && git commit -m "chore: add .interlore/ to root gitignore"
```

<verify>
- run: `test -f interverse/interlore/.claude-plugin/plugin.json`
  expect: exit 0
- run: `python3 -c "import json; d=json.load(open('interverse/interlore/.claude-plugin/plugin.json')); assert len(d['skills'])==1; assert len(d['commands'])==3; print('OK')`
  expect: contains "OK"
</verify>

---

## Execution Notes

- Tasks 1 and 2 are independent (doc hierarchy vs plugin scaffold) — can run in parallel
- Tasks 3 and 4 depend on Task 2 (need scaffold)
- Task 5 depends on everything (integration test)
- Total: 5 tasks, ~4 commits
