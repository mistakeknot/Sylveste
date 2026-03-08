# Shallow Composition Layer Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** iv-3kpfu
**Goal:** Build a tool-routing composition layer that presents plugins as coherent tool surfaces to agents, using interchart's domain overlay pattern (pattern rules + forced curation groups).

**Architecture:** A YAML metadata file (`os/clavain/config/tool-composition.yaml`) defines domain groups, co-occurrence hints, and sequencing rules. A single Go command (`clavain-cli tool-surface`) parses this file and outputs pre-formatted context. The SessionStart hook injects this context at a defined priority slot in the shedding cascade.

**What this is NOT:** This is not a runtime tool router or a replacement for Tool Search. It is metadata that enriches the agent's context so Tool Search results are more coherent. Think database views over the existing plugin substrate.

**Tech Stack:** YAML (metadata), Go (clavain-cli reader), Bash (hook integration)

## Prior Learnings

- Interchart's `OVERLAP_DOMAIN_RULES` (8 pattern-based domains) + `FORCED_OVERLAP_GROUPS` (4 curated groups) is the proven pattern
- Dialectic R3: composition depth is a continuous metric — none/shallow/moderate/deep, with different actions at each level
- Dialectic R2: developer packaging and agent tool surfaces are independent concerns (tables vs views)
- Tool selection instrumentation (iv-rttr5) deployed but has 0 events — can't build data-driven co-occurrence yet
- Failure gap decomposes into: discovery (tags fix), sequencing (hints fix), scale (model improvements fix)
- Existing `config/routing.yaml` handles model selection; this new file handles tool composition
- `compose.go` already exists for agent dispatch planning (F3) — tool-surface is a distinct concern
- SessionStart hook has a 10,000 char cap with priority-based shedding (lines 318-334)
- clavain-cli processes are short-lived — no in-memory caching benefit
- Config resolution uses `configDirs()` from compose.go: CLAVAIN_CONFIG_DIR > CLAVAIN_DIR/config > CLAVAIN_SOURCE_DIR/config > CLAUDE_PLUGIN_ROOT/config
- tool-composition.yaml is Go-only (no bash parser) — unlike routing.yaml which has two implementations

## Review Findings Addressed

From fd-architecture and fd-quality reviews (2026-03-05):
- P0: Renamed `tool-compose` → `tool-surface` to avoid collision with existing compose subsystem
- P1: Changed `before`/`after` → `first`/`then` in sequencing hints for unambiguous direction
- P1: Collapsed three subcommands into single `tool-surface` command (one consumer: the hook)
- P1: Use `configDirs()` for config resolution, not `CLAVAIN_ROOT`
- P1: Assigned composition context priority slot in shedding cascade (after sprint, before discovery)
- P1: Removed "cache parsed data in memory" — short-lived Go processes
- P1: Fixed enforce-gate hint ownership (clavain, not interphase)
- P2: Removed interflux from research domain (interpeer is the research tool)
- P2: Added discovery curation group
- P2: Follow test_compose.bats patterns (not test_routing.bats)
- P2: Added 120-char hint length lint in tests (R3 consolidation ratchet)

---

### Task 1: Create tool-composition.yaml with domain groups and sequencing hints

**Files:**
- Create: `os/clavain/config/tool-composition.yaml`

**What to do:**
Create the composition metadata file with three sections:

1. **`domains`** — Domain groupings (mirrors interchart's `OVERLAP_DOMAIN_RULES`). Each domain has a name, description, and list of plugin IDs. Plugins can belong to multiple domains.

2. **`curation_groups`** — Forced groupings for plugins that co-occur in workflows (mirrors `FORCED_OVERLAP_GROUPS`). Each group has a name, member plugin IDs, and a one-line context sentence. Intentionally omits boost/weight — this is context injection, not graph scoring (unlike interchart's groups which affect visual layout).

3. **`sequencing_hints`** — Per-plugin-pair ordering hints using `first`/`then` fields for unambiguous execution direction. Keep each hint <= 120 characters (the R3 consolidation signal: if a hint grows beyond one sentence, the boundary may need consolidation).

Keep the file small (< 100 lines). This is shallow metadata, not comprehensive documentation.

```yaml
# Tool composition layer — shallow metadata for agent tool routing
# Mirrors interchart's domain overlay pattern applied to tool selection
# See: dialectics/2026-03-02-plugin-modularity/r3_sublation.md
#
# Go-only parser (clavain-cli tool-surface). No bash-side parser exists.
# curation_groups omit boost/weight intentionally — context injection, not graph scoring.
# TODO: Add tool-composition.schema.json when format stabilizes.

version: 1

domains:
  coordination:
    description: "Multi-agent coordination, file locking, message passing"
    plugins: [interlock, intermux, intercom]
  analytics:
    description: "Token tracking, cost analysis, benchmarking"
    plugins: [interstat, tool-time, interbench]
  quality:
    description: "Code review, quality gates, verification"
    plugins: [interflux, intercheck]
  docs:
    description: "Documentation lifecycle, drift detection, artifact generation"
    plugins: [interwatch, interdoc, interpath, interkasten]
  discovery:
    description: "Code search, semantic retrieval, context extraction"
    plugins: [intersearch, tldr-swinton, intermap, interject]
  phase-control:
    description: "Sprint lifecycle, phase gates, bead tracking"
    plugins: [interphase, clavain]
  design:
    description: "Visual design, UI components, theming"
    plugins: [interform, interchart]
  research:
    description: "Cross-AI peer review, external web search"
    plugins: [interpeer]

curation_groups:
  sprint-core:
    plugins: [clavain, interphase, interflux, interstat]
    context: "Sprint lifecycle — clavain orchestrates, interphase gates, interflux reviews, interstat measures"
  coordination-stack:
    plugins: [interlock, intermux, interpath]
    context: "Multi-agent file coordination — resolve paths, reserve files, monitor agents"
  doc-lifecycle:
    plugins: [interwatch, interdoc, interpath, interkasten]
    context: "Document maintenance — detect drift, generate artifacts, manage AGENTS.md, sync Notion"
  discovery-stack:
    plugins: [intersearch, tldr-swinton, intermap, interject]
    context: "Code investigation — semantic search, file extraction, codebase mapping, inbox triage"

sequencing_hints:
  - first: interpath
    then: interlock
    hint: "Resolve file paths before reserving them for editing"
  - first: interflux
    then: clavain
    hint: "flux-drive review runs on plan files before sprint execution"
  - first: clavain
    then: clavain
    hint: "enforce-gate checks phase prerequisites before sprint-advance"
  - first: interstat
    then: clavain
    hint: "set-bead-context registers token attribution before sprint work"
```

**Verification:** `python3 -c "import yaml; yaml.safe_load(open('os/clavain/config/tool-composition.yaml'))"` succeeds. File is < 100 lines.

---

### Task 2: Add `tool-surface` Go command to clavain-cli

**Files:**
- Create: `os/clavain/cmd/clavain-cli/tool_surface.go`
- Edit: `os/clavain/cmd/clavain-cli/main.go` (add case to switch)

**What to do:**
Add a single `tool-surface` command: `clavain-cli tool-surface [--json]`

Default output (plain text, for hook injection):
```
## Tool Composition
Coordination: interlock, intermux, intercom — multi-agent coordination
Quality: interflux, intercheck — code review and quality gates
[... other domains ...]

### Workflow Groups
- sprint-core: clavain + interphase + interflux + interstat — Sprint lifecycle
- coordination-stack: interlock + intermux + interpath — File coordination
[...]

### Sequencing
- interpath before interlock (resolve paths before reserving)
- interflux before clavain (review plan first)
[...]
```

With `--json` flag: output the parsed YAML as JSON (for future programmatic consumers).

Implementation:
- Load `tool-composition.yaml` via `configDirs()` (same resolution as `findFleetRegistryPath()`)
- Parse into typed structs: `ToolComposition`, `Domain`, `CurationGroup`, `SequencingHint`
- No caching — just parse on every invocation (< 100 line file, negligible cost)
- Return empty output (not error) if the file is missing

Add to `main.go` under a new "Tool Composition:" section in help:
```go
case "tool-surface":
    err = cmdToolSurface(args)
```

**Verification:** `clavain-cli tool-surface` outputs formatted text. `clavain-cli tool-surface --json` outputs valid JSON.

---

### Task 3: Inject composition context into SessionStart hook

**Files:**
- Edit: `os/clavain/hooks/session-start.sh`

**What to do:**
Add composition context as a new section in the shedding cascade, at priority **after sprint_context, before discovery_context** (composition hints are more useful than raw work discovery but less urgent than active sprint state).

1. After the sprint scan block (line ~217), add:
```bash
# Tool composition context (iv-3kpfu) — shallow metadata for tool routing
composition_context=""
if command -v clavain-cli &>/dev/null; then
    _comp_output=$(clavain-cli tool-surface 2>/dev/null) || _comp_output=""
    if [[ -n "$_comp_output" ]]; then
        composition_context="\\n\\n$(escape_for_json "$_comp_output")"
    fi
fi
```

2. Insert `${composition_context}` into the `_full_context` assembly (line ~313), between `${sprint_context}` and `${discovery_context}`.

3. Add composition_context to the shedding cascade between sprint and discovery:
```bash
if [[ ${#_full_context} -gt $ADDITIONAL_CONTEXT_CAP ]]; then
    composition_context=""
    # ... rebuild _full_context
fi
```

**Verification:** BATS test (Task 4) verifies composition block appears in additionalContext when clavain-cli is available. Manual: start new session and check output.

---

### Task 4: Add tests

**Files:**
- Create: `os/clavain/tests/shell/test_tool_surface.bats`
- Edit: `os/clavain/tests/shell/session_start.bats` (add composition injection test)

**What to do:**

**test_tool_surface.bats** — follow `test_compose.bats` patterns (compiled Go binary, `CLAVAIN_CONFIG_DIR` env var, `jq` assertions):

1. `tool-surface` with valid config returns formatted text containing domain names
2. `tool-surface --json` returns valid JSON with domains, curation_groups, sequencing_hints keys
3. Missing config file returns empty output (exit 0, no stderr)
4. Each sequencing hint is <= 120 characters (R3 consolidation ratchet)
5. Config file is < 100 lines

**session_start.bats** — add one test:
6. Stub `clavain-cli` to output known composition text, run session-start hook, assert `additionalContext` contains "## Tool Composition"

**Verification:** `bats os/clavain/tests/shell/test_tool_surface.bats` passes.

---

## Verification Checklist

- [ ] `tool-composition.yaml` is valid YAML and < 100 lines
- [ ] `clavain-cli tool-surface` returns formatted text with domains and hints
- [ ] `clavain-cli tool-surface --json` returns valid JSON
- [ ] SessionStart hook injects composition context at correct priority slot
- [ ] BATS tests pass (tool_surface + session_start integration)
- [ ] No changes to existing routing.yaml, lib-routing.sh, or compose.go
- [ ] All sequencing hints <= 120 characters

## Future Work (not in scope)

- **Co-occurrence signals from telemetry:** When tool_selection_events has data, build a pipeline that reads co-occurrence patterns and auto-generates curation groups
- **Dynamic composition at query time:** Tool Search could use composition metadata to return coherent tool surfaces instead of individual tools
- **Doc-depth monitoring:** BATS test catches hint > 120 chars. Future: periodic scan for overall file growth and doc-depth creep per plugin pair
- **Per-phase filtering:** `tool-surface --phase=executing` could filter to phase-relevant domains (e.g., skip research domain during execution)
- **Individual query subcommands:** `tool-surface domains`, `tool-surface hints --plugin=X` — add only when a second consumer appears
