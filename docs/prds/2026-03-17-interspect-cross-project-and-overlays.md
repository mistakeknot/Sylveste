---
artifact_type: prd
bead: iv-5ztam
stage: design
---
# PRD: Interspect Cross-Project Aggregation & Prompt Tuning Overlays

## Problem

1. **Cross-project blindness:** If fd-game-design is consistently wrong across 5 projects, each project independently accumulates evidence and proposes overrides. The global pattern is obvious but invisible per-project.

2. **Binary routing:** The only routing action is "exclude agent entirely." Sometimes an agent is useful but needs domain-specific prompt tuning — e.g., fd-performance is great for Go but gives irrelevant advice for Python projects.

## Solution

1. Add cross-project evidence aggregation: query all project interspect databases, surface patterns that repeat globally, and propose cross-project overrides.

2. Complete the prompt tuning overlay system: generate overlay prompts from correction patterns, inject into agent system prompts via Clavain, and canary-monitor the tuning.

## Features

### F1: Cross-Project Evidence Aggregation
**What:** Query all `.clavain/interspect/interspect.db` databases across projects, merge patterns, and surface cross-project insights.

**Acceptance criteria:**
- [ ] `_interspect_discover_project_dbs()` finds all interspect.db files under `~/projects/`
- [ ] `_interspect_cross_project_report()` aggregates patterns across all discovered DBs
- [ ] Report shows per-agent stats with project count (e.g., "fd-game-design: excluded in 4/7 projects")
- [ ] `/interspect:effectiveness --global` flag triggers cross-project view
- [ ] Cross-project proposals shown in `/interspect:propose` when agent is excluded in >50% of projects
- [ ] No writes to other project databases — read-only aggregation

### F2: Prompt Tuning Overlay Creation (iv-t1m4)
**What:** Generate and manage prompt tuning overlays from correction evidence patterns.

**Acceptance criteria:**
- [ ] `/interspect:tune <agent>` generates an overlay from the agent's correction patterns
- [ ] Overlay stored at `.clavain/interspect/overlays/<agent>/tuning.md` with YAML frontmatter
- [ ] Overlay format: frontmatter (status, created, evidence_count) + markdown body (guidance)
- [ ] Generation uses correction patterns: "In this project, fd-performance corrections mostly relate to [X]. Adjust recommendations to [Y]."
- [ ] Overlay canary: same 20-use/14-day window as routing overrides
- [ ] `/interspect:revert <agent> --overlay` disables the overlay
- [ ] Overlay content injected into agent context via `additionalContext` in SessionStart hook

### F3: Overlay Injection in SessionStart
**What:** Read active overlays and inject them into agent context at session start.

**Acceptance criteria:**
- [ ] SessionStart hook reads `.clavain/interspect/overlays/*/tuning.md`
- [ ] Only active overlays (status: active in frontmatter) are injected
- [ ] Overlay body appended to `additionalContext` output
- [ ] Token budget: max 500 tokens per overlay, max 2000 total
- [ ] Graceful degradation: if overlay read fails, session continues without it

## Non-goals

- Cross-project write operations (modifying other projects' DBs or routing overrides)
- Automated overlay generation without user confirmation
- LLM-based overlay content generation (template-based for v1)
- Overlay A/B testing (canary is binary pass/fail, not comparison)

## Dependencies

- F1: Access to `~/projects/*/` directory structure
- F2: Existing overlay infrastructure in lib-interspect.sh (directories, canary schema)
- F3: SessionStart hook already supports `additionalContext` output
- F2 depends on F1 (cross-project data informs overlay recommendations)
