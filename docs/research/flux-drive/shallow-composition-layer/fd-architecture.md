# Architecture Review: Shallow Composition Layer
# flux-drive — fd-architecture

**Plan:** `/home/mk/projects/Sylveste/docs/plans/2026-03-05-shallow-composition-layer.md`
**Bead:** iv-3kpfu
**Reviewer:** Flux-drive Architecture Agent
**Date:** 2026-03-05

---

## Summary Assessment

The plan is grounded in the right dialectic conclusions (R2/R3 sublations) and the interchart reference implementation is a sound analogy. Three structural issues require attention before implementation begins. The biggest risk is not what the plan adds — it is the name collision with the existing `cmdCompose` / `compose.go` subsystem, which this plan's terminology would silently shadow. Everything else is either well-scoped or clearly labeled as future work.

---

## 1. Boundaries and Coupling

### P0 — Naming collision: "tool-compose" subcommand conflicts with the existing `compose` command family

The plan proposes adding `clavain-cli tool-compose` subcommands (domains, group, hints) to a new `cmd/tool-compose.go` file. The existing `compose.go` already owns the `compose` and `sprint-compose` commands and defines a rich set of types: `ComposePlan`, `composePlan()`, `composeSprint()`, `cmdCompose()`, `cmdSprintCompose()`. These resolve _agent dispatch plans_ from agency specs and fleet registries.

The new `tool-compose` command is conceptually unrelated — it reads _plugin metadata_ for routing hints. But the shared verb "compose" creates a collision at every level:

- The command name `tool-compose` in `main.go` sits adjacent to `compose` and `sprint-compose`; readers will not know which compose means what without reading both files.
- A new `cmd/tool-compose.go` file alongside `compose.go` guarantees persistent confusion about which file to edit for which concern.
- Any `CompositionConfig` or similar struct defined in the new file will share the `package main` namespace with the existing `ComposePlan`, `AgencySpec`, `FleetRegistry` types. The new file will need careful naming to avoid symbol-level shadowing.

The fix is to use a name that reflects what this subsystem actually does: it reads _plugin taxonomy metadata_. Candidates fitting existing conventions: `clavain-cli plugin-domains`, `clavain-cli tool-surface`, or `clavain-cli routing-hints`. Any of these avoids collision without requiring changes to the existing compose subsystem.

The plan's own description uses precise language — "metadata that enriches the agent's context", "database views over the existing plugin substrate" — which is exactly right. The command name should match that precision.

### P1 — Session-start hook already has a token budget ceiling with priority-based shedding; this plan's injection has no defined priority slot

`session-start.sh` implements explicit priority-based shedding across five sections: `inflight_context`, `discovery_context`, `sprint_context`, `upstream_warning`, and `setup_hint`. The cap is 10,000 characters. The shedding order is hardcoded as a cascade of if-blocks (lines 318-334).

The plan proposes appending composition context after existing context and claims this will cost fewer than 500 tokens. That claim may hold initially, but the hook does not shed in byte-level increments — it drops whole sections. The new section must be assigned an explicit priority (shedding position) in that cascade, otherwise:

1. It is either unshed (appended outside the cascade, always injected regardless of cap), or
2. It displaces an existing section at an unintended priority level.

The plan's Task 3 says "append to existing context" but does not specify where in the shedding cascade. The smallest viable fix: add the composition injection before the `_full_context` assembly on line 313, assign it a priority slot in the cascade (probably after `discovery_context`, before `sprint_context`, since composition hints are lower-urgency than sprint state), and document that slot.

### P1 — The sequencing_hints schema direction is ambiguous and will produce contradictory reads

The plan's YAML schema expresses hints as:

```yaml
sequencing_hints:
  - before: interpath
    after: interlock
    hint: "Resolve file paths before reserving them"
```

This models a directed relationship, but the field names are ambiguous. Reading "before: interpath, after: interlock" suggests "interpath comes before interlock in execution order" — which matches the hint text. But a reader could interpret the fields as "this hint applies before interpath runs" and "this hint applies after interlock runs," which is the opposite ordering.

The interchart reference uses a different model: it infers edges from plugin-to-plugin co-occurrence signals and domain membership, not explicit before/after fields. Sequencing hints in the existing codebase (routing.yaml, lib-routing.sh) use resolution-chain priority, not explicit directed pairs.

A cleaner schema uses a single field that makes direction unambiguous:

```yaml
sequencing_hints:
  - first: interpath
    then: interlock
    hint: "Resolve file paths before reserving them"
```

Or follow the existing pattern in routing.yaml comment style:

```yaml
sequencing_hints:
  - pair: [interpath, interlock]
    order: first-then
    hint: "Resolve file paths before reserving them"
```

Either alternative is unambiguous. The current `before`/`after` schema will require an explanatory comment in every consumer (hook and Go reader) to clarify which direction the fields encode.

### P2 — tool-composition.yaml adds a third config-resolution code path not aligned with the existing two

The plan says: "Load `config/tool-composition.yaml` relative to `CLAVAIN_ROOT`." Existing config resolution uses two established patterns:

- `lib-routing.sh` uses `_routing_find_config()` which tries `CLAVAIN_ROUTING_CONFIG`, `script_dir/../config/`, `CLAVAIN_SOURCE_DIR`, then `CLAUDE_PLUGIN_ROOT`.
- `compose.go` uses `findFleetRegistryPath()` / `configDirs()` which tries `CLAVAIN_CONFIG_DIR`, `CLAVAIN_DIR/config`, `CLAVAIN_SOURCE_DIR/config`, then `CLAUDE_PLUGIN_ROOT/config`.

The plan references `CLAVAIN_ROOT` — an env var that does not appear in either existing pattern. Using `CLAVAIN_ROOT` rather than the established `CLAVAIN_SOURCE_DIR` / `CLAVAIN_CONFIG_DIR` / `CLAUDE_PLUGIN_ROOT` chain will require callers to set a new env var, and will make the new file invisible to the existing config-discovery infrastructure.

The smallest fix: follow `configDirs()` from `compose.go` exactly. It is already the canonical Go-side config resolution path. The new file loader should call `configDirs()` and look for `tool-composition.yaml` in the same locations.

### P3 — interflux appears in two domains with different justifications

In the plan's YAML, `interflux` is listed under both `quality` and `research` domains:

```yaml
quality:
  plugins: [interflux, intercheck]
research:
  plugins: [interpeer, interflux]
```

In interchart's `FORCED_OVERLAP_GROUPS`, `interflux` appears in `discovery-context-stack` alongside `interject`, `intersearch`, and `tldr-swinton`. The two classification schemes disagree on interflux's primary domain. This is not a bug — the R2 sublation explicitly permits multi-domain membership. But the plan does not document why interflux belongs to both domains in this taxonomy vs. the interchart taxonomy. A one-line comment in the YAML explaining "interflux spans both quality gates and research dispatch; see interchart's discovery-context-stack for visualization grouping" would prevent future maintainers from treating one as authoritative and correcting the other.

---

## 2. Pattern Analysis

### P1 — The Go reader for tool-composition.yaml duplicates parse logic that lib-routing.sh already owns in Bash

`lib-routing.sh` parses YAML into bash associative arrays using a hand-rolled state machine (lines 158-470). The Go compose subsystem reads YAML using `gopkg.in/yaml.v3` into typed structs. The plan proposes a third implementation: a new Go file in clavain-cli that parses `tool-composition.yaml`.

This is not automatically wrong — the routing YAML and tool-composition YAML have different schemas. But the codebase already has a precedent for this duplication and it has caused divergence: the `_routing_load_cache()` bash parser and the Go `ic route` path have different code paths, connected by the fast-path delegation on lines 516-523 of lib-routing.sh. The comment there reads "Fall through on failure — bash implementation is the safety net."

If `tool-composition.yaml` is parsed only in Go (clavain-cli), the hook at Task 3 calls `clavain-cli tool-compose domains` via subprocess. That is the right pattern for the hook side — it avoids duplicating YAML parsing in bash. But the plan should explicitly state that there is no bash-side parser for `tool-composition.yaml`. The routing.yaml has two implementations for backward compatibility; tool-composition.yaml should have one (Go only, via subprocess call from bash hooks). This should be documented in the file header.

### P2 — `curation_groups` in the plan does not match `FORCED_OVERLAP_GROUPS` semantics

`FORCED_OVERLAP_GROUPS` in interchart assigns a `boost` value that affects edge weight in the ecosystem graph. The plan's `curation_groups` has no equivalent weight or boost field — it only has `plugins` and `context`. The R2 sublation explicitly uses FORCED_OVERLAP_GROUPS as the existence proof for this pattern. If the curation groups don't carry the same weighting semantics, the analogy breaks: interchart's groups affect layout and visual proximity, but the plan's groups affect only the text injected into session context.

This is fine for the current scope (shallow metadata, not a dynamic query-time composer), but the plan should document that `curation_groups` intentionally omits boost/weight because this implementation is context injection, not graph scoring. Without this clarification, future iterations may add boost values expecting graph behavior that the current implementation does not provide, or may add query-time filtering expecting tool-level granularity that the plugin-level grouping does not provide.

### P2 — The plan has no mechanism to detect when a sequencing_hint has grown into a paragraph (the R3 consolidation signal)

R3's core insight is that doc depth is the coupling metric: shallow = metadata, moderate = sequencing hints, deep = consolidation signal. The plan correctly targets the "moderate" tier. But the plan has no mechanism to detect when a hint crosses from one-line into multi-paragraph territory.

The R3 sublation explicitly names this as a contradiction: "Moderate depth may creep toward deep. A one-line sequencing hint today becomes a paragraph of error handling next month. Is there a ratchet that catches this drift?" The plan's Future Work section does not address this, and the `< 100 lines` constraint on `tool-composition.yaml` is the only implicit guard.

A minimal ratchet: add a lint step to `bats` tests that asserts each `hint:` value is no longer than 120 characters. If a hint exceeds that length, the test fails with a message: "hint for X→Y is too long — if you need more than one sentence, consider whether consolidation is appropriate." This makes the R3 consolidation signal operationally visible without requiring architectural judgment at write time.

---

## 3. Simplicity and YAGNI

### P1 — Task 2 creates a new clavain-cli binary interface with three subcommands for metadata that could be inline YAML in the hook

The `domains`, `group`, and `hints` subcommands serve a single consumer: the SessionStart hook. The hook reads their output, formats it into a context string, and injects it. This is a subprocess-per-section call pattern (three invocations of `clavain-cli` per session start) for data that could be read directly from YAML in bash — or in a single `clavain-cli tool-compose context` call that returns the pre-formatted string.

The three-subcommand interface implies these commands will be called by multiple consumers independently. If there is currently only one consumer (the hook), the multi-command interface is speculative extensibility. The R3 sublation explicitly places this plan in the "shallow metadata" tier, which warrants a correspondingly simple interface.

Smallest viable change: collapse the three subcommands into one: `clavain-cli tool-compose context [--phase=<phase>]`, which outputs the pre-formatted `## Tool Composition` block that the hook injects verbatim. The Go code reads all three sections internally and formats the output. This removes the per-section subprocess overhead, eliminates the bash formatting logic in the hook, and keeps the interface surface minimal. Individual `domains`, `group`, `hints` subcommands can be added later if a second consumer materializes.

### P2 — BATS test specification mirrors the wrong existing test (test_compose.bats, not test_routing.bats)

The plan references `test_routing.bats` as the pattern to follow. But `test_routing.bats` tests a bash library (lib-routing.sh) using isolated temp directories and env var injection — a completely different approach from what `test_tool_compose.bats` would test, which is a compiled Go binary.

The correct reference is `test_compose.bats`, which already tests `clavain-cli` subcommands using the binary path pattern (`$CLI compose --stage=ship`), the `CLAVAIN_CONFIG_DIR` env var, and `jq` assertions on JSON output. The new `test_tool_compose.bats` should follow `test_compose.bats` exactly: same setup pattern, same binary reference, same `skip "clavain-cli-go not built"` guard.

### P3 — The `< 100 lines` constraint on tool-composition.yaml is good but not enforced

The plan states the file should be "< 100 lines" but this is prose guidance, not a test assertion. Given that this file is the primary artifact of the feature, a single `wc -l` check in the BATS suite (or the Verification Checklist) would make the constraint mechanical. This is a nit — the constraint is sound, just unenforced.

---

## Must-Fix Before Implementation

1. **P0** — Rename the command family away from `tool-compose` to avoid collision with the existing compose subsystem. Use `plugin-domains`, `tool-surface`, or `routing-hints`.

2. **P1** — Assign the composition context injection an explicit priority slot in `session-start.sh`'s shedding cascade (lines 318-334). Document the priority rationale in the hook comment.

3. **P1** — Fix the `before`/`after` schema ambiguity in `sequencing_hints`. Use `first`/`then` or `pair` + `order` to make execution direction unambiguous.

4. **P1** — Use `configDirs()` from `compose.go` as the config resolution path for `tool-composition.yaml`. Remove any reference to `CLAVAIN_ROOT` and align with the established env var chain.

5. **P1** — Collapse the three subcommands into a single `context` command. Add individual subcommands only if a second consumer appears.

## Optional Improvements

6. **P2** — Add a one-line comment in `tool-composition.yaml` explaining that `curation_groups` intentionally omits boost/weight (context injection, not graph scoring).

7. **P2** — Add a BATS assertion that each `hint:` value is <= 120 characters, making the R3 consolidation signal mechanically visible.

8. **P2** — Document in the Go file header that `tool-composition.yaml` has no bash-side parser and is intentionally Go-only (unlike `routing.yaml` which has two implementations for backward compatibility).

9. **P3** — Clarify `interflux`'s dual-domain membership in the YAML comment.

10. **P3** — Add a `wc -l` assertion in the verification checklist or BATS suite to enforce the `< 100 lines` constraint mechanically.

## What the Plan Gets Right

The plan correctly:

- Identifies this as shallow metadata enrichment, not a runtime router
- Preserves the routing.yaml / lib-routing.sh separation of concerns
- Uses interchart's pattern (domain rules + forced curation groups) at the right tier
- Guards the hook injection with `command -v clavain-cli` for graceful degradation
- Scopes telemetry-driven co-occurrence and dynamic query-time composition to Future Work
- Tests the empty-config case explicitly (Task 4, point 6)

The core architecture — YAML metadata file + Go reader + hook injection — is the right design for this tier of the R3 spectrum. The issues above are structural corrections to that design, not objections to it.
