---
artifact_type: plan
bead: iv-mtf12
stage: design
---
# Data-Driven Plugin Boundary Decisions — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** iv-mtf12
**Goal:** Expand tool-composition.yaml with evidence-based sequencing and disambiguation hints, informed by a manual audit of all Clavain pipelines, plus a consolidation checklist.

**Architecture:** Four sequential tasks: (1) audit documented pipelines to find gaps, (2) extend the Go parser and YAML schema with disambiguation hints, (3) add new sequencing + disambiguation hints from audit findings, (4) document consolidation criteria. Tasks 1 and 2 are independent. Task 3 depends on both. Task 4 is independent.

**Tech Stack:** YAML (metadata), Go (clavain-cli), Bash (BATS tests)

## Prior Learnings

- `docs/research/accuracy-gap-measurement-results.md` — sequencing hints dominate (+70%), discovery marginal (+20%), scale non-issue (0%). Unhinted pairs fail at same rate as no composition.
- `docs/solutions/patterns/search-surfaces.md` — decision tree for tool selection by use case. Model for disambiguation hints.
- `docs/solutions/2026-03-04-c5-self-building-loop.md` — "wiring > building" principle: composition metadata should expose minimal bridge interface, not deep domain knowledge.

---

### Task 1: Audit multi-tool pipelines and produce gap analysis

**Files:**
- Create: `docs/research/pipeline-audit-results.md`

**Step 1: Create the audit results document**

Analyze the 18 multi-tool pipelines identified in commands and skills. For each pipeline, map whether it has a corresponding sequencing or disambiguation hint in `tool-composition.yaml`. Produce a table:

```markdown
# Pipeline Audit Results

**Bead:** iv-zdrpo
**Date:** 2026-03-05
**Source:** Manual audit of 45 commands + 16 skills in os/clavain/

## Covered Pipelines (have hints)

| Pipeline | Hint | Source |
|----------|------|--------|
| interpath → interlock | "Resolve file paths before reserving them for editing" | sequencing_hints[0] |
| interflux → clavain | "flux-drive review runs on plan files before sprint execution" | sequencing_hints[1] |
| clavain → clavain | "enforce-gate checks phase prerequisites before sprint-advance" | sequencing_hints[2] |
| interstat → clavain | "set-bead-context registers token attribution before sprint work" | sequencing_hints[3] |

## Uncovered Pipelines (need hints)

| Pipeline | Type | Evidence | Recommended Hint |
|----------|------|----------|-----------------|
| interflux → intersynth | sequencing | quality-gates.md Phase 4→5: agents run, then synthesis | "Run review agents before synthesizing verdicts" |
| intersynth → interspect | sequencing | quality-gates.md Phase 5→5a: synthesis feeds evidence | "Synthesize verdicts before recording evidence" |
| interflux:learnings-researcher → clavain:work | sequencing | work.md Step 1b: search learnings before executing | "Search institutional learnings before starting execution" |
| interflux → clavain:resolve | sequencing | sprint.md Step 7→8: review findings feed resolve | "Quality gate findings feed into resolve step" |
| interspect → clavain:reflect | sequencing | reflect.md Step 7: evidence feeds routing calibration | "Record evidence before calibrating agent routing" |

## Within-Domain Disambiguation Gaps

| Plugins | Domain | Confusion Evidence | Recommended Hint |
|---------|--------|-------------------|-----------------|
| interpath, interdoc | docs | Benchmark Task 10: model confused "generate docs" | "interpath generates artifacts (roadmaps, changelogs); interdoc manages AGENTS.md" |
| interwatch, intercheck | quality/docs | Benchmark Task 2: "check docs" confused with intercheck | "interwatch detects documentation drift; intercheck runs code quality verification" |
| intersearch, tldr-swinton | discovery | Both do code search; intersearch for cached embeddings, tldr-swinton for live analysis | "intersearch queries cached embeddings; tldr-swinton extracts live file structure" |
| interlock, intermux | coordination | Both coordinate agents; interlock for file reservation, intermux for session monitoring | "interlock reserves files for editing; intermux monitors active agent sessions" |
```

Review the actual commands and skills to validate and extend the uncovered pipelines table. Focus on the most impactful gaps (pipelines that agents encounter frequently in sprint workflows).

**Step 2: Commit**

```bash
git add docs/research/pipeline-audit-results.md
git commit -m "research: audit multi-tool pipelines for composition gaps"
```

**Verification:** Document exists with both covered and uncovered pipeline tables populated.

---

### Task 2: Add disambiguation_hints to Go parser and YAML schema

**Files:**
- Edit: `os/clavain/config/tool-composition.yaml` (add empty disambiguation_hints section)
- Edit: `os/clavain/cmd/clavain-cli/tool_surface.go` (add DisambiguationHint type + parsing + rendering)
- Edit: `os/clavain/tests/shell/test_tool_surface.bats` (add disambiguation tests)

**Step 1: Add DisambiguationHint type to tool_surface.go**

Add the new type after `SequencingHint`:

```go
type DisambiguationHint struct {
	Plugins []string `yaml:"plugins" json:"plugins"`
	Domain  string   `yaml:"domain" json:"domain"`
	Hint    string   `yaml:"hint" json:"hint"`
}
```

Add the field to `ToolComposition`:

```go
type ToolComposition struct {
	Version              int                        `yaml:"version" json:"version"`
	Domains              map[string]Domain          `yaml:"domains" json:"domains"`
	CurationGroups       map[string]CurationGroup   `yaml:"curation_groups" json:"curation_groups"`
	SequencingHints      []SequencingHint           `yaml:"sequencing_hints" json:"sequencing_hints"`
	DisambiguationHints  []DisambiguationHint       `yaml:"disambiguation_hints" json:"disambiguation_hints"`
}
```

**Step 2: Update formatToolSurface to render disambiguation hints**

Add after the sequencing hints block in `formatToolSurface()`:

```go
	// Disambiguation hints
	if len(comp.DisambiguationHints) > 0 {
		b.WriteString("\n### Disambiguation\n")
		for _, h := range comp.DisambiguationHints {
			b.WriteString(fmt.Sprintf("- %s: %s\n",
				strings.Join(h.Plugins, " vs "), h.Hint))
		}
	}
```

**Step 3: Add empty disambiguation_hints section to tool-composition.yaml**

Add after `sequencing_hints` at the bottom of the file:

```yaml
disambiguation_hints: []
```

This keeps the file valid while Task 3 populates it with actual hints.

**Step 4: Add BATS tests for disambiguation hints**

Add to `test_tool_surface.bats`:

```bash
@test "tool-surface --json includes disambiguation_hints key" {
    run "$CLI" tool-surface --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.disambiguation_hints'
}

@test "disambiguation hints are all <= 120 characters" {
    run "$CLI" tool-surface --json
    [ "$status" -eq 0 ]
    long_hints=$(echo "$output" | jq '[.disambiguation_hints[] | select(.hint | length > 120)] | length')
    [ "$long_hints" -eq 0 ]
}

@test "disambiguation hints have required fields" {
    run "$CLI" tool-surface --json
    [ "$status" -eq 0 ]
    missing=$(echo "$output" | jq '[.disambiguation_hints[] | select(.plugins | length == 0 or .hint == "")] | length')
    [ "$missing" -eq 0 ]
}
```

**Step 5: Build and test**

```bash
cd os/clavain && bash scripts/build-clavain-cli.sh && bats tests/shell/test_tool_surface.bats
```

Expected: All tests pass, including new disambiguation tests (trivially, since the list is empty).

**Step 6: Commit**

```bash
git add os/clavain/cmd/clavain-cli/tool_surface.go os/clavain/config/tool-composition.yaml os/clavain/tests/shell/test_tool_surface.bats
git commit -m "feat: add disambiguation_hints to tool-composition schema and Go parser"
```

**Verification:** `clavain-cli tool-surface --json | jq '.disambiguation_hints'` returns `[]`. BATS tests pass.

---

### Task 3: Populate sequencing and disambiguation hints from audit

**Files:**
- Edit: `os/clavain/config/tool-composition.yaml` (add new hints)
- Edit: `os/clavain/tests/shell/test_tool_surface.bats` (update line count test if needed)

**Depends on:** Task 1 (audit results), Task 2 (disambiguation schema)

**Step 1: Add new sequencing hints**

Based on the audit from Task 1, add the highest-impact uncovered pipelines to `sequencing_hints`. Add these after the existing 4 hints:

```yaml
  - first: interflux
    then: intersynth
    hint: "Run review agents before synthesizing verdicts"
  - first: intersynth
    then: interspect
    hint: "Synthesize verdicts before recording evidence"
  - first: interspect
    then: clavain
    hint: "Record evidence before calibrating agent routing"
```

Keep each hint <= 120 characters. Only add hints for pipelines that agents actually encounter in sprint workflows (not hypothetical combinations).

**Step 2: Add disambiguation hints**

Populate the `disambiguation_hints` section with within-domain confusion cases from the audit:

```yaml
disambiguation_hints:
  - plugins: [interpath, interdoc]
    domain: docs
    hint: "interpath generates artifacts (roadmaps, changelogs); interdoc manages AGENTS.md"
  - plugins: [interwatch, intercheck]
    domain: docs
    hint: "interwatch detects doc drift; intercheck runs code quality verification"
  - plugins: [intersearch, tldr-swinton]
    domain: discovery
    hint: "intersearch queries cached embeddings; tldr-swinton extracts live file structure"
  - plugins: [interlock, intermux]
    domain: coordination
    hint: "interlock reserves files for editing; intermux monitors active agent sessions"
```

**Step 3: Update line count test**

The existing BATS test asserts `tool-composition.yaml` is < 100 lines. With the new hints, the file will grow. Update the test threshold:

```bash
@test "tool-composition.yaml is < 150 lines" {
    config_file="${CLAVAIN_CONFIG_DIR}/tool-composition.yaml"
    [ -f "$config_file" ]
    line_count=$(wc -l < "$config_file")
    [ "$line_count" -lt 150 ]
}
```

**Step 4: Verify tool-surface output**

```bash
clavain-cli tool-surface
```

Expected output now includes:
- `### Sequencing` with 7 hints (4 existing + 3 new)
- `### Disambiguation` with 4 hints

```bash
clavain-cli tool-surface --json | jq '.sequencing_hints | length'  # → 7
clavain-cli tool-surface --json | jq '.disambiguation_hints | length'  # → 4
```

**Step 5: Run full test suite**

```bash
cd os/clavain && bats tests/shell/test_tool_surface.bats
```

Expected: All tests pass. No hint exceeds 120 characters.

**Step 6: Commit**

```bash
git add os/clavain/config/tool-composition.yaml os/clavain/tests/shell/test_tool_surface.bats
git commit -m "feat: expand composition hints from pipeline audit — 7 sequencing, 4 disambiguation"
```

**Verification:** `clavain-cli tool-surface` shows both new sections. All BATS tests pass.

---

### Task 4: Document consolidation checklist

**Files:**
- Edit: `os/clavain/config/tool-composition.yaml` (add consolidation criteria as comments)
- Edit: `docs/research/pipeline-audit-results.md` (add consolidation assessment)

**Step 1: Add consolidation criteria to tool-composition.yaml header**

Add after the existing header comments (before `version: 1`):

```yaml
# Consolidation Criteria (evaluate when adding hints):
# 1. Hint exceeds 120-char limit → boundary may need facade or merge
# 2. >3 hints between same plugin pair → too much coordination surface
# 3. Persistent failure rate despite hints (check interstat data)
# 4. Tool descriptions need cross-references to explain interaction
# As of 2026-03-05: no plugin pair meets these criteria.
```

**Step 2: Add consolidation section to audit results**

Append to `docs/research/pipeline-audit-results.md`:

```markdown
## Consolidation Assessment

**Date:** 2026-03-05
**Verdict:** No consolidation needed

### Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| Any hint > 120 chars | No | All hints within limit |
| >3 hints between same pair | No | Max is 2 (interflux→clavain has sequencing + quality-gates pattern) |
| Persistent failure despite hints | Unknown | No telemetry data yet (iv-qi80j) |
| Cross-reference needed in tool descriptions | No | Tool descriptions are self-contained |

### Next Review
Re-evaluate after 2 weeks of interstat telemetry data (iv-qi80j). If any pair shows >20% failure rate WITH hints, apply consolidation criteria.
```

**Step 3: Commit**

```bash
git add os/clavain/config/tool-composition.yaml docs/research/pipeline-audit-results.md
git commit -m "docs: add consolidation checklist — no merges needed as of 2026-03-05"
```

**Verification:** Consolidation criteria visible in YAML header comments. Assessment table in audit results.

---

## Verification Checklist

- [ ] Pipeline audit document exists with covered/uncovered tables
- [ ] `disambiguation_hints` parsed by Go and rendered in `tool-surface` output
- [ ] Sequencing hints expanded from 4 to ~7
- [ ] Disambiguation hints added (~4 within-domain confusion cases)
- [ ] All hints <= 120 characters (BATS enforced)
- [ ] `tool-composition.yaml` < 150 lines
- [ ] Consolidation criteria documented in YAML header and audit results
- [ ] All BATS tests pass
- [ ] No changes to existing routing.yaml, lib-routing.sh, or compose.go
