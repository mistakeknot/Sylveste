---
artifact_type: plan
bead: none
stage: design
---
# CUJs as First-Class Artifacts — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** none
**Goal:** Add CUJ (Critical User Journey) as a new first-class artifact type in Demarch, with generation via interpath, drift detection via interwatch, and auto-discovery.

**Architecture:** CUJs are prose-first markdown files in `docs/cujs/` with typed success signals (measurable/observable/qualitative). interpath gets a new `cuj` phase for generation. interwatch gets a new `cuj` signal template and discovery rules. The existing artifact lifecycle (generate → register → detect drift → refresh) extends naturally to CUJs.

**Tech Stack:** Markdown (artifact format), YAML (watchables config, signal templates), Python (interwatch-scan.py), Bash (lib-watch.sh), Claude Code skills/commands (interpath)

---

### Task 1: Create the CUJ Phase File for interpath

**Files:**
- Create: `interverse/interpath/skills/artifact-gen/phases/cuj.md`

**Step 1: Write the CUJ synthesis phase**

This file tells the artifact-gen skill how to generate a CUJ. It follows the same pattern as `phases/prd.md` and `phases/vision.md` — it defines the output structure and writing guidelines.

```markdown
# CUJ Synthesis

Using the discovered sources, generate or refresh a Critical User Journey document.

## Output Structure

### Header

The CUJ frontmatter uses additional fields beyond the standard artifact header:

```yaml
---
artifact_type: cuj
journey: <journey-slug>
actor: <who>
criticality: <p0-p4>
bead: <bead-id or none>
---
```

Followed by the markdown header:

```markdown
# [Journey Name]

**Last updated:** [today's date]
**Status:** Living document — regenerate with `/interpath:cuj`
```

### Section 1: Why This Journey Matters

Synthesize from PRD, brainstorms, and vision doc:
- Why is this journey critical to the product?
- What breaks or degrades if this journey is poor?
- Who is the actor and what's their context?

Keep to 1-2 paragraphs.

### Section 2: The Journey

Prose narrative describing the expected end-to-end experience. This is freeform — it should read naturally for both linear flows (CLI tools) and exploratory flows (games, complex UIs).

For linear flows, describe the step-by-step sequence.
For exploratory flows, describe the intended discovery path, emotional beats, and key moments.

Authors may optionally embed step tables, mermaid diagrams, or other structured elements inline. The format does not prescribe a specific structure.

Synthesize from:
- PRD core capabilities (what the user does)
- Brainstorms (what the experience should feel like)
- Existing docs and README (current documented flows)
- Beads (what's shipped vs. planned)

### Section 3: Success Signals

A table of typed assertions that agents and tests can validate:

| Signal | Type | Assertion |
|--------|------|-----------|
| [name] | measurable/observable/qualitative | [what success looks like] |

**Signal types:**
- **measurable** — quantitative, automatable (HTTP 200, < 5min, no errors)
- **observable** — detectable with instrumentation (state change, event fired)
- **qualitative** — requires human judgment (feels intuitive, low friction)

Derive from:
- PRD success metrics
- Brainstorm acceptance criteria
- Beads with test/acceptance tags

### Section 4: Known Friction Points

Current pain points, gaps, or risks in this journey. Derive from:
- Open beads related to this flow
- Brainstorm friction discussions
- Known bugs or UX issues

## Writing Guidelines

- Be specific — reference actual commands, files, UI elements
- Describe the CURRENT journey, not the aspirational one
- Keep under 150 lines
- Link to sub-journey CUJ files where a step is complex enough to warrant its own document
- Prefer concrete success signals over vague ones ("HTTP 200 at /health" not "app works")
```

**Step 2: Verify the file was created**

Run: `ls -la interverse/interpath/skills/artifact-gen/phases/cuj.md`
Expected: File exists

**Step 3: Commit**

```bash
git add interverse/interpath/skills/artifact-gen/phases/cuj.md
git commit -m "feat(interpath): add CUJ synthesis phase for artifact-gen"
```

---

### Task 2: Register CUJ in the artifact-gen Skill Router

**Files:**
- Modify: `interverse/interpath/skills/artifact-gen/SKILL.md` (lines 13-14, 39-47)
- Modify: `interverse/interpath/skills/artifact-gen/SKILL-compact.md` (lines 3, 25-33)

**Step 1: Update SKILL.md to add `cuj` as an artifact type**

In `SKILL.md`, update the type list on line 14 from:

```
The user wants one of: **roadmap**, **prd**, **vision**, **changelog**, **status**, **monorepo-roadmap**, **propagate**
```

to:

```
The user wants one of: **roadmap**, **prd**, **vision**, **changelog**, **status**, **cuj**, **monorepo-roadmap**, **propagate**
```

Then add a new row to the routing table (after the `status` row, around line 46):

```markdown
| cuj | `artifact-gen/phases/cuj.md` |
```

**Step 2: Update SKILL-compact.md to add `cuj`**

In `SKILL-compact.md`, update line 3 from:

```
Generate product artifacts from project state. Supports: **roadmap**, **monorepo-roadmap**, **propagate**, **prd**, **vision**, **changelog**, **status**.
```

to:

```
Generate product artifacts from project state. Supports: **roadmap**, **monorepo-roadmap**, **propagate**, **prd**, **vision**, **changelog**, **status**, **cuj**.
```

Then add a new row to the type table (around line 33):

```markdown
| **cuj** | `docs/cujs/<journey-slug>.md` | Why It Matters, The Journey (prose), Success Signals (typed table), Known Friction Points |
```

**Step 3: Verify the changes**

Run: `grep -n "cuj" interverse/interpath/skills/artifact-gen/SKILL.md interverse/interpath/skills/artifact-gen/SKILL-compact.md`
Expected: Both files reference `cuj` in the type list and routing table

**Step 4: Commit**

```bash
git add interverse/interpath/skills/artifact-gen/SKILL.md interverse/interpath/skills/artifact-gen/SKILL-compact.md
git commit -m "feat(interpath): register CUJ type in artifact-gen skill router"
```

---

### Task 3: Add the interpath CUJ Command

**Files:**
- Create: `interverse/interpath/commands/cuj.md`
- Modify: `interverse/interpath/.claude-plugin/plugin.json` (add command entry)

**Step 1: Create the command file**

Follow the exact pattern from `commands/prd.md`:

```markdown
---
name: cuj
description: Generate or refresh a Critical User Journey from PRDs, brainstorms, and project state
---

# Generate CUJ

Invoke the `artifact-gen` skill with artifact type **cuj**.

The CUJ synthesizes:
- Journey motivation from PRD and vision doc
- Prose narrative from brainstorms and existing docs
- Typed success signals from PRD metrics and beads
- Known friction points from open beads and brainstorms

Output: `docs/cujs/<journey-slug>.md`

Use the Skill tool to invoke `interpath:artifact-gen` with the instruction: "Generate a CUJ artifact."
```

**Step 2: Register the command in plugin.json**

In `interverse/interpath/.claude-plugin/plugin.json`, add to the `commands` array:

```json
"./commands/cuj.md"
```

Add it after `"./commands/changelog.md"` to maintain alphabetical order.

**Step 3: Update plugin.json description to mention CUJs**

Update the `description` field from:

```
"Product artifact generator — roadmaps, PRDs, vision docs, changelogs, and status reports from beads, brainstorms, and project state. Companion plugin for Clavain."
```

to:

```
"Product artifact generator — roadmaps, PRDs, vision docs, changelogs, CUJs, and status reports from beads, brainstorms, and project state. Companion plugin for Clavain."
```

Also add `"cuj"` to the `keywords` array.

**Step 4: Verify**

Run: `python3 -c "import json; d=json.load(open('interverse/interpath/.claude-plugin/plugin.json')); print(d['commands']); print('cuj' in d['keywords'])"`
Expected: commands list includes `./commands/cuj.md`, keywords includes cuj

**Step 5: Commit**

```bash
git add interverse/interpath/commands/cuj.md interverse/interpath/.claude-plugin/plugin.json
git commit -m "feat(interpath): add /interpath:cuj command"
```

---

### Task 4: Add CUJ Source to Discovery Phase

**Files:**
- Modify: `interverse/interpath/skills/artifact-gen/phases/discover.md` (add Source 10)
- Modify: `interverse/interpath/skills/artifact-gen/references/source-catalog.md` (add CUJ row)

**Step 1: Add CUJ source to discover.md**

Add after Source 9 (Companion Plugins):

```markdown
## Source 10: CUJ Documents

- Pattern: `docs/cujs/*.md`
- Read each file's first 20 lines for journey name and actor
- Useful for cross-referencing when generating other artifacts (PRDs, roadmaps)
```

**Step 2: Add CUJ row to source-catalog.md**

Add to the Sources table:

```markdown
| CUJs | `docs/cujs/*.md` | First 20 lines: journey name, actor, criticality |
```

**Step 3: Commit**

```bash
git add interverse/interpath/skills/artifact-gen/phases/discover.md interverse/interpath/skills/artifact-gen/references/source-catalog.md
git commit -m "feat(interpath): add CUJ docs as discovery source"
```

---

### Task 5: Add CUJ Output Template

**Files:**
- Modify: `interverse/interpath/skills/artifact-gen/references/output-templates.md` (add CUJ template)

**Step 1: Add CUJ template section**

Add after the Status Report Template section (around line 97):

```markdown
## CUJ Template

1. Why This Journey Matters (motivation, stakes)
2. The Journey (prose narrative — linear or exploratory)
3. Success Signals (typed assertion table: Signal | Type | Assertion)
4. Known Friction Points (current pain points)

Signal types: measurable (automatable), observable (instrumented), qualitative (human judgment).

Target: under 150 lines
```

**Step 2: Commit**

```bash
git add interverse/interpath/skills/artifact-gen/references/output-templates.md
git commit -m "feat(interpath): add CUJ to output templates reference"
```

---

### Task 6: Add CUJ Watchable and Signal Template to interwatch

**Files:**
- Modify: `interverse/interwatch/config/watchables.yaml` (add watchable, signal template, discovery rule)

**Step 1: Add the CUJ watchable entry**

Add after the `vision` watchable entry (around line 63):

```yaml
  - name: cuj
    path: docs/cujs/
    generator: interpath:artifact-gen
    generator_args: { type: cuj }
    signals:
      - type: bead_closed
        weight: 2
        description: "Closed bead may affect journey steps or success signals"
      - type: brainstorm_created
        weight: 1
        description: "New brainstorm may redefine user flows"
      - type: file_created
        weight: 2
        description: "New files may change journey paths"
      - type: file_deleted
        weight: 3
        description: "Deleted file may break a documented journey step"
      - type: commits_since_update
        weight: 1
        description: "Accumulated changes may drift journey description"
        threshold: 15
    staleness_days: 14
```

**Step 2: Add the CUJ signal template**

Add after the `agents-md` signal template (around line 144):

```yaml
  cuj:
    generator: interpath:artifact-gen
    generator_args: { type: cuj }
    staleness_days: 14
    signals:
      - { type: bead_closed, weight: 2 }
      - { type: brainstorm_created, weight: 1 }
      - { type: file_created, weight: 2 }
      - { type: file_deleted, weight: 3 }
      - { type: commits_since_update, weight: 1, threshold: 15 }
```

**Step 3: Add the CUJ discovery rule**

Add after the vision discovery rules (around line 177):

```yaml
  - pattern: "docs/cujs/*.md"
    template: cuj
    name_format: "cuj-{stem}"
```

Here `{stem}` is the filename without extension — e.g., `docs/cujs/deploy-first-app.md` becomes watchable name `cuj-deploy-first-app`.

**Step 4: Verify YAML is valid**

Run: `python3 -c "import yaml; yaml.safe_load(open('interverse/interwatch/config/watchables.yaml')); print('Valid YAML')"`
Expected: `Valid YAML`

**Step 5: Commit**

```bash
git add interverse/interwatch/config/watchables.yaml
git commit -m "feat(interwatch): add CUJ watchable, signal template, and discovery rule"
```

---

### Task 7: Update interwatch Watchables Reference Doc

**Files:**
- Modify: `interverse/interwatch/skills/doc-watch/references/watchables.md` (add CUJ generator mapping)

**Step 1: Add CUJ to the Generator Mapping table**

The table at line 23-26 currently lists `interpath:artifact-gen` producing "Roadmap, PRD, Vision, Changelog, Status". Update it to:

```markdown
| `interpath:artifact-gen` | interpath | Roadmap, PRD, Vision, Changelog, Status, CUJ |
```

**Step 2: Commit**

```bash
git add interverse/interwatch/skills/doc-watch/references/watchables.md
git commit -m "docs(interwatch): add CUJ to generator mapping reference"
```

---

### Task 8: Handle `{stem}` Placeholder in interwatch Scanner

**Files:**
- Modify: `interverse/interwatch/scripts/interwatch-scan.py` (add `{stem}` resolution in discovery)

**Step 1: Read the discovery section of interwatch-scan.py**

Read the file to find where `{module}` placeholders are resolved in discovery rules. The `{stem}` placeholder needs to be resolved to the filename stem when matching `docs/cujs/*.md`.

**Step 2: Add `{stem}` resolution**

Find the discovery rule resolution function (likely named something like `resolve_discovery_rules` or `discover_watchables`). Where `{module}` is replaced, add handling for `{stem}`:

When a discovery rule pattern contains a glob (`*`), and the `name_format` uses `{stem}`, resolve `{stem}` to the matched filename without extension. For each file matching the glob pattern, create a separate watchable entry.

For example, if `docs/cujs/deploy-first-app.md` and `docs/cujs/onboard-agent.md` both exist, generate two watchable entries:
- `name: cuj-deploy-first-app, path: docs/cujs/deploy-first-app.md`
- `name: cuj-onboard-agent, path: docs/cujs/onboard-agent.md`

**Step 3: Write a test for the new resolution**

Run: `python3 interverse/interwatch/scripts/interwatch-scan.py --discover-only 2>&1 | head -20`
Expected: No errors. If CUJ files exist in `docs/cujs/`, they should appear in `.interwatch/watchables.yaml`.

**Step 4: Commit**

```bash
git add interverse/interwatch/scripts/interwatch-scan.py
git commit -m "feat(interwatch): support {stem} placeholder in discovery rules for per-file watchables"
```

---

### Task 9: Create docs/cujs/ Directory with README

**Files:**
- Create: `docs/cujs/README.md`

**Step 1: Create the directory and README**

```markdown
# Critical User Journeys (CUJs)

CUJ documents describe end-to-end user experiences that the product must support well. Each CUJ is a prose-first markdown file with typed success signals.

## Template

See the [brainstorm](../brainstorms/2026-03-05-cujs-as-first-class-artifacts.md) for the full design rationale.

Generate a new CUJ: `/interpath:cuj`

## Format

Each CUJ file uses this structure:

- **Frontmatter:** `artifact_type: cuj`, journey slug, actor, criticality, bead
- **Why This Journey Matters:** 1-2 paragraphs on stakes
- **The Journey:** Prose narrative (linear or exploratory)
- **Success Signals:** Table with Signal | Type | Assertion columns
- **Known Friction Points:** Current pain points

Signal types: `measurable` (automatable), `observable` (instrumented), `qualitative` (human judgment).

## Drift Detection

CUJs are monitored by interwatch for staleness via:
- Feature-change signals (bead closures, new brainstorms, file changes)
- Test-result signals (success signal failures in smoke tests)
```

**Step 2: Commit**

```bash
git add docs/cujs/README.md
git commit -m "docs: create docs/cujs/ directory with CUJ format README"
```

---

### Task 10: Verify End-to-End Integration

**Files:** None (verification only)

**Step 1: Verify interpath recognizes the CUJ type**

Run: `grep -c "cuj" interverse/interpath/skills/artifact-gen/SKILL.md interverse/interpath/skills/artifact-gen/SKILL-compact.md interverse/interpath/commands/cuj.md`
Expected: All three files match

**Step 2: Verify interwatch config is valid**

Run: `python3 -c "import yaml; d=yaml.safe_load(open('interverse/interwatch/config/watchables.yaml')); print('Watchables:', len(d['watchables'])); print('Signal templates:', list(d['signal_templates'].keys())); print('Discovery rules:', len(d['discovery_rules']))"`
Expected: watchables count increased by 1, signal_templates includes `cuj`, discovery_rules count increased by 1

**Step 3: Verify plugin.json is valid**

Run: `python3 -c "import json; d=json.load(open('interverse/interpath/.claude-plugin/plugin.json')); assert './commands/cuj.md' in d['commands']; assert 'cuj' in d['keywords']; print('OK')"`
Expected: `OK`

**Step 4: Verify discovery would find CUJs**

Run: `python3 interverse/interwatch/scripts/interwatch-scan.py --discover-only 2>&1 | tail -5`
Expected: No errors (CUJ rule is registered; it may find 0 CUJs if none exist yet, which is fine)

**Step 5: Final commit (if any fixes needed)**

Only if verification steps revealed issues that needed fixing.
