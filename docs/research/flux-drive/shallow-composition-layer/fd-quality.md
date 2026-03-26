# Quality Review: Shallow Composition Layer Plan

**Plan file:** `docs/plans/2026-03-05-shallow-composition-layer.md`
**Bead:** iv-3kpfu
**Reviewer:** Flux-drive Quality & Style
**Date:** 2026-03-05

---

## Summary

The plan is well-scoped and philosophically coherent. The YAML design is reasonable for shallow metadata. Three issues warrant attention before implementation: the Go subcommand naming collides with an existing command, the YAML schema has a consistency gap in sequencing hint directionality, and the test plan skips session-start hook integration coverage that the rest of the test suite provides for comparable hooks.

---

## Findings

### P1 — Go subcommand name `tool-compose` collides with the existing `compose` family

**Location:** Task 2 (cmd naming) and main.go switch

The plan introduces `clavain-cli tool-compose domains`, `tool-compose group`, `tool-compose hints` as three new top-level commands in the flat switch in `main.go`. The existing `compose` command (`cmdCompose`) handles agent dispatch plan generation and is unrelated to plugin tool composition. Both share the word "compose," which will create reader confusion in help text and in the codebase.

The existing naming pattern for related subcommand groups uses hyphen-prefixed families: `sprint-create`, `sprint-claim`, `sprint-budget-remaining`, etc. A new group should follow the same pattern. `tool-domains`, `tool-group`, `tool-hints` or a `tool-surface-*` prefix would be unambiguous. Alternatively, since these commands query composition metadata (not "composing" anything), `tool-composition-domains`, `tool-composition-group`, `tool-composition-hints` maintains the noun-first convention used elsewhere.

The plan's verification steps reference `clavain-cli tool-compose domains` — if the name changes, update all verification lines to match.

**Fix:** Choose a non-colliding prefix before adding cases to `main.go`. Update `printHelp()` under a new group header (e.g., "Tool Composition:") to match the existing help table style.

---

### P1 — Sequencing hints schema: `before`/`after` direction is inverted relative to the hint text

**Location:** Task 1, `sequencing_hints` section of the YAML schema

The plan defines sequencing hints as:
```yaml
- before: interflux
  after: clavain
  hint: "flux-drive review runs on plan files before sprint execution"
```

Read literally: "interflux runs before clavain." But the hint text says "flux-drive review runs on plan files before sprint execution" — which is clavain (the executor). That is consistent.

However, the third hint:
```yaml
- before: interphase
  after: clavain
  hint: "enforce-gate checks phase prerequisites before advancing"
```

"enforce-gate" is a clavain command, not an interphase command. The `before` field says interphase should run before clavain, but enforce-gate is invoked by clavain on clavain's behalf. This is either a wrong assignment or the schema is modeling the wrong relationship.

More broadly, the schema uses bare plugin names (`before: interstat`, `after: clavain`) without specifying which tool within the plugin is ordered. If the composition layer is meant to help agents sequence tool calls, a bare plugin name is too coarse — an agent seeing "interstat before clavain" doesn't know whether this means `interstat.set-bead-context` should precede `clavain-cli sprint-create` or something else. The Task 1 description says "Per-plugin-pair ordering hints for the moderate-depth cases" but does not define a tool-within-plugin field, creating a precision gap.

The plan is explicitly "shallow metadata," so this may be acceptable today. But the schema should document whether `before`/`after` refer to plugins or tools, and the enforce-gate hint should name the correct owning plugin.

**Fix (minimum):** Correct the enforce-gate hint's `before` plugin to `clavain` (since enforce-gate is a clavain command, the constraint is that clavain's enforce-gate must run before clavain's executor — or document that `interphase` is intentional and explain why). Add a YAML comment clarifying the granularity contract: "plugin-level hints; tool-level sequencing not in scope for v1."

---

### P1 — Go reader: plan says "cache parsed data in memory" but Go processes are short-lived

**Location:** Task 2, implementation note

The plan says "Cache parsed data in memory (file doesn't change during a session)." In the existing codebase, all `clavain-cli` invocations are short-lived processes called from shell scripts — each invocation is a fresh process with no shared state. In-process caching has zero effect here. The plan may intend a file-level cache (e.g., write a parsed JSON sidecar to `.clavain/scratch/`), or it may simply have cargo-culted the caching pattern from a context where it made sense.

This is not a correctness bug — it just means the stated design goal ("cache parsed data") won't be achieved. If the round-trip cost of parsing the YAML is negligible (it is for a <100-line file), drop the caching language. If caching is genuinely wanted, specify the mechanism (sidecar file, shared memory, or daemon).

**Fix:** Remove the caching language from the plan or replace it with a concrete mechanism. For a <100-line YAML file, no caching is needed — just parse on every invocation.

---

### P2 — YAML schema: `domains` uses a map, `curation_groups` uses a map, but `sequencing_hints` uses a list — inconsistent shape

**Location:** Task 1, YAML schema design

`domains` and `curation_groups` are keyed maps (`coordination:`, `sprint-core:`) which is idiomatic and allows O(1) lookup by name. `sequencing_hints` is an unnamed list of `{before, after, hint}` objects. This is a reasonable choice for a list of pairs, but it means the Go reader needs a different deserialization path for each section. A consistent rule helps maintainers: either use lists throughout or maps throughout.

An alternative for hints that maintains map consistency:
```yaml
sequencing_hints:
  interpath->interlock:
    hint: "Resolve file paths before reserving them"
  interflux->clavain:
    hint: "flux-drive review before sprint execution"
```

This makes the pair canonical and eliminates the `before`/`after` directionality confusion identified in P1 above.

If the list form is kept, add a YAML comment explaining why (e.g., "list used because a plugin may appear as both before and after in different pairs").

---

### P2 — Task 4 BATS tests: missing session-start integration test

**Location:** Task 4, test plan

The plan specifies six unit-level tests for the `tool-compose` command. These are correct and necessary. However, the hook integration path (Task 3) has no test coverage in the plan. The existing test suite in `session_start.bats` tests that `session-start.sh` produces valid JSON and a non-empty `additionalContext` — but it does not verify that specific content is present.

The risk from Task 3 is: if the `clavain-cli tool-compose domains` call in the hook fails silently (which the plan explicitly allows via the `command -v` guard), the session-start output will be valid but the composition context will be absent with no indication. There is no test that verifies the composition block appears when `clavain-cli` is available.

The session_start.bats pattern (stub external commands, run hook in subshell, assert JSON shape) supports exactly this kind of test. A test that stubs `clavain-cli` to output a known JSON response and asserts the composition section appears in `additionalContext` would close this gap.

**Fix:** Add a test to `session_start.bats` (not a new file) that stubs `clavain-cli` and verifies the composition section is injected. This aligns with how the existing inflight-agents and drift-injection tests work.

---

### P2 — `interflux` appears in two semantically incompatible domains

**Location:** Task 1, `domains` section

`interflux` is listed under both `quality` ("Code review and quality gates") and `research` ("Cross-AI review, web search, document analysis"). These are valid uses of interflux, but an agent querying `tool-compose domains --plugin=interflux` will get two contradictory domain assignments. The plan says "plugins can belong to multiple domains," so this is by design — but the descriptions are different enough that an agent could be confused about which capability to use interflux for.

The `research` domain description says "web search, document analysis" — this is interpeer's territory, not interflux's. Interflux is oracle-backed multi-agent review, not web search. Consider whether interflux belongs in `research` at all, or whether the research domain should be named more precisely to match the actual tool capabilities.

**Fix:** Verify interflux's primary capability against its plugin manifest before adding it to `research`. If interpeer is the web search tool, move interpeer into `research` and remove or relabel interflux's entry there.

---

### P3 — `curation_groups` is missing a "research" group

**Location:** Task 1, `curation_groups`

The plan defines three curation groups: `sprint-core`, `coordination-stack`, `doc-lifecycle`. The `research` domain has no corresponding curation group, and the `discovery` domain (intersearch, tldr-swinton, intermap, interject) likewise has no group. For an agent doing code investigation work, knowing that "intersearch + tldr-swinton + intermap are a coherent discovery stack" is as useful as knowing "interlock + intermux + interpath are a coordination stack."

This is not a blocking issue for v1 — the plan explicitly says this is shallow metadata. But the omission is notable and the "Future Work" section does not mention it, which means it may fall through. Adding a discovery group would complete the primary query patterns that agents encounter.

---

### P3 — Verification step for Task 3 is weak

**Location:** Task 3, Verification section

"Start a new Claude Code session and check that the injected context appears in the session start output." This is a manual verification step. The existing verification strategy for session-start content (e.g., companion detection, drift injection) uses BATS tests, not manual inspection. The P2 finding above addresses this structurally. The verification line in the plan should reference the BATS test rather than a manual session start.

---

### P3 — `version: 1` in tool-composition.yaml but no schema file

**Location:** Task 1, YAML preamble

The existing `config/` directory has schema files (`agency-spec.schema.json`, `fleet-registry.schema.json`, `routing-overrides.schema.json`) for each YAML config. `tool-composition.yaml` introduces a `version: 1` field, which implies future schema evolution, but no schema file is planned. This is fine for v1 but the pattern suggests a `tool-composition.schema.json` should be added when the format stabilizes. Note this omission in a TODO comment in the file rather than leaving it unacknowledged.

---

## Non-Issues

- The approach of keeping the YAML < 100 lines with three named sections mirrors interchart's pattern well. The structure is proportionate to the stated "shallow" intent.
- Using `command -v clavain-cli` as the guard in session-start.sh is the correct project convention (per MEMORY.md: use `command -v`, not `which`).
- Outputting JSON from Go subcommands and plain text as a separate mode is consistent with how `compose` and `sprint-compose` work.
- The empty-results-not-errors contract for missing config files matches `loadInterspectCalibration()` and `loadRoutingOverrides()` behavior in `compose.go`.
- Placing new commands in `cmd/clavain-cli/` as a separate `.go` file matches the per-concern file layout (compose.go, budget.go, sprint.go, etc.).
- The Go `_test.go` file pattern with `testdata/` fixtures matches `compose_test.go` exactly — this is the right model for Task 4's Go-level tests if any are added.

---

## Priority Summary

| ID | Priority | Area | Issue |
|----|----------|------|-------|
| F1 | P1 | Go naming | `tool-compose` subcommand collides with existing `compose` command family |
| F2 | P1 | YAML schema | `before`/`after` direction unclear; enforce-gate hint names wrong owning plugin |
| F3 | P1 | Go design | "In-memory cache" has no effect in a short-lived CLI process |
| F4 | P2 | YAML schema | Mixed map/list shapes across top-level sections |
| F5 | P2 | Tests | No session-start integration test for composition injection |
| F6 | P2 | YAML content | `interflux` in `research` domain conflicts with its actual capability |
| F7 | P3 | YAML content | No curation group for discovery domain |
| F8 | P3 | Verification | Task 3 verification is manual; should reference BATS |
| F9 | P3 | Schema | No schema file planned despite `version:` field |
