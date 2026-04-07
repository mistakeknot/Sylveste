---
artifact_type: prd
bead: sylveste-jrua
stage: design
---

# PRD: Ecosystem-Wide Simplification Pass (Phase 2)

## Problem

A 6-agent flux-review scan identified 24 cross-boundary simplification targets across all Sylveste pillars and plugins. Phase 1 resolved 6 P0/P1 items (~1,100 LOC). 18 items remain spanning incremental completions, new shared infrastructure, god function decomposition, and config cleanup.

## Solution

Execute 18 remaining items via repo-grouped parallel delegation (~6 agents). Each agent handles all items in its repo cluster, verifies builds/tests, and commits directly. Pure structural refactoring — no behavioral changes.

## Features

### F1: Shared Test Infra Rollout
**What:** Convert 7+ remaining plugins to the shared structural test package at `interverse/_shared/tests/structural/`.
**Acceptance criteria:**
- [ ] interflux, intersearch, interpub, interknow, interwatch, intercept, interlab all use shared helpers.py, conftest.py, test_structure.py
- [ ] All converted plugins pass `pytest tests/structural/ -v`
- [ ] Each plugin's test files are <20 lines (thin wrappers)

### F2: Intercore CLI Completion + run.go Split
**What:** Convert remaining 9 command files to shared flag parser, split run.go into domain-focused files, extract store boilerplate.
**Acceptance criteria:**
- [ ] All 12 cmd/ic/*.go files use `internal/cli.ParseFlags`
- [ ] run.go split into run_create.go, run_lifecycle.go, run_config.go, run_replay.go (each <600 LOC)
- [ ] Base store type in internal/store/ eliminates repeated `type Store struct { db *sql.DB }` pattern
- [ ] `go build ./...` and `go test ./...` pass

### F3: Intermute HTTP Handler Dedup
**What:** Extract method switch helper to replace repeated GET/POST/PUT/DELETE dispatch in 4+ handler files.
**Acceptance criteria:**
- [ ] `methodSwitch` or equivalent helper replaces manual method dispatch in handlers_domain.go, handlers_messages.go, handlers_agents.go, handlers_reservations.go
- [ ] `go build ./...` and `go test ./...` pass
- [ ] ~80 LOC reduction

### F4: Agent Definition Dedup + Session Context Lib
**What:** Extract generic boilerplate from 12 interflux review agents. Create shared session context library for plugin hooks.
**Acceptance criteria:**
- [ ] "First Step (MANDATORY)" and "What NOT to Flag" sections reduced or generated from skill docs
- [ ] `interverse/_shared/hooks/lib-context.sh` provides `_context_read_session_id`, `_context_write_session_id`, `_context_set_bead_id`, `_context_read_bead_id`
- [ ] At least 2 plugins (interflux, interstat) source the shared lib instead of reimplementing

### F5: Apps Layer Consolidation
**What:** Extract shared Clerk middleware factory, API response helpers, decompose chatpanel.go and container-runner.ts, consolidate content schemas.
**Acceptance criteria:**
- [ ] Clerk middleware factory in `sdk/interbase/typescript/astro/` used by both interblog and intersite
- [ ] API response helpers (`errorResponse`, `successResponse`, `parseJsonBody`) in interblog `src/lib/api-utils.ts`
- [ ] chatpanel.go decomposed: no single file >600 LOC in Autarch TUI
- [ ] container-runner.ts decomposed: volume builder, container executor, output parser extracted
- [ ] Content schemas share base builder if patterns align, or documented as intentionally divergent

### F6: Root Infrastructure Cleanup
**What:** Extract shared logging helpers from install/uninstall scripts, clean up stale flux-gen specs.
**Acceptance criteria:**
- [ ] `lib/installer-common.sh` contains color setup + logging functions shared by install.sh and uninstall.sh
- [ ] 10 stale/stub flux-gen spec files archived or deleted
- [ ] ~100 LOC reduction in install script pair

## Non-goals

- Changing public APIs or external behavior
- Adding new features or capabilities
- Modifying test coverage (beyond removing duplicates)
- Touching documentation beyond what's directly affected by code moves

## Dependencies

- F1 depends on `interverse/_shared/tests/structural/` (created in Phase 1)
- F2 depends on `internal/cli/flags.go` (created in Phase 1)
- F5 Clerk middleware depends on `sdk/interbase/` having a typescript/astro/ directory
- All other features are independent

## Open Questions

- F5 content schemas: share via sdk/interbase or keep app-local? Decision deferred to agent based on actual pattern similarity.
- F4 agent boilerplate: how much to extract without reducing agent-specific clarity? Mitigation: only extract fully generic text.
