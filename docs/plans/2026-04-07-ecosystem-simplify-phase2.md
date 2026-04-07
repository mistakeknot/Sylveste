---
artifact_type: plan
bead: sylveste-jrua
prd: docs/prds/2026-04-07-ecosystem-simplify.md
stage: plan
review: flux-drive 2026-04-07 (3 agents — architecture, correctness, quality)
---

# Plan: Ecosystem-Wide Simplification — Phase 2 (Revised)

## Overview

Execute remaining simplification items via 7 parallel agents, repo-grouped to avoid conflicts. Each agent verifies builds/tests before committing. Revised after flux-drive review that caught: phantom paths, repo conflicts, incomplete inventories, and over-scoped agents.

## Execution: Single Parallel Batch (7 agents)

All 7 features execute simultaneously. No sequencing needed — each targets different git repos.

**Rollback:** If any agent's changes break builds, `git revert HEAD` in that repo. Each agent commits atomically per repo — partial states are not pushed.

---

### Agent 1: F1 — Shared Test Infra Rollout
**Bead:** sylveste-nhs9
**Repos:** interverse/_shared + intersearch, interpub, interknow, interwatch, interlab, intercept
**Note:** interflux moved to Agent 4 (which already touches that repo). intercept and interlab need file creation, not replacement.

**Steps:**
1. Read `interverse/_shared/tests/structural/` — actual files are `conftest_base.py`, `test_base.py`, `helpers.py`, `__init__.py`
2. For each of the 6 plugins with existing structural tests (intersearch, interpub, interknow, interwatch, interlab):
   a. Read current `tests/structural/` files
   b. Replace with thin wrappers importing from `_shared` (same pattern as interkasten/interspect/interstat)
   c. Keep plugin-specific test overrides (e.g., `test_scripts_count`, `test_plugin_name`)
   d. For interlab: create conftest.py and helpers.py from scratch (only test_structure.py exists)
   e. Run `python3 -m pytest tests/structural/ -v`
3. For intercept (no tests/ directory at all):
   a. Create `tests/structural/` directory
   b. Create thin wrappers from `_shared` pattern
   c. Run pytest to verify
4. Commit and push each plugin individually

**Verification:** All 6 plugins pass `pytest tests/structural/ -v`

---

### Agent 2: F2 — Intercore CLI Flag Conversion + run.go Split
**Bead:** sylveste-6cn3
**Repo:** core/intercore

**Steps:**
1. Read `internal/cli/flags.go` to understand the shared API
2. **Inventory first:** Read ALL `cmd/ic/*.go` files, list every file that still uses raw `args[]` parsing instead of `cli.ParseFlags`. The actual count is ~19 unconverted files (not 9). Convert all of them.
3. Split `cmd/ic/run.go` (~2050 LOC):
   - **Read the full function list first** before creating target files
   - Inventory all `cmdRun*` functions (including cmdRunStatus, cmdRunTokens, cmdRunBudget, cmdRunCancel, cmdRunAgentList, etc.)
   - Split by domain into 4-5 files, ensuring every function is placed
   - Keep `run.go` as the entry point with `cmdRun()` dispatch and shared utilities
   - Verify no orphaned functions: `go build ./...` must pass
4. **Skip** store base extraction — most stores have extra fields beyond `db *sql.DB` (eventRecorder, onEvent, logger, redactCfg). The savings are too small relative to the import graph disruption.
5. Verify: `go build ./...` and `go test ./...`
6. Commit and push

**Verification:** All existing tests pass, `go vet ./...` clean

---

### Agent 3: F3 — Intermute HTTP Handler Dedup
**Bead:** sylveste-wehj
**Repo:** core/intermute

**Steps:**
1. Read ALL handler files in `internal/http/`: `handlers_domain.go`, `handlers_messages.go`, `handlers_agents.go`, `handlers_reservations.go`, `handlers_threads.go`, `handlers_window_identity.go`
2. Note: `handlers_domain.go` uses `*DomainService` as receiver (embeds `*Service`), others use `*Service` directly
3. Extract helper that works for both receiver types:
   ```go
   type methodHandlers struct {
       get, post, put, delete http.HandlerFunc
   }
   func dispatchByMethod(w http.ResponseWriter, r *http.Request, h methodHandlers)
   ```
   Use a package-level function (not method) so both `*Service` and `*DomainService` can call it
4. Refactor each handler to use `dispatchByMethod`
5. Verify: `go build ./...` and `go test ./...`
6. Commit and push

**Verification:** All existing tests pass

---

### Agent 4: F4 — Interflux Test Conversion + Agent Definition Dedup + Session Context
**Bead:** sylveste-lio3
**Repos:** interverse/interflux, interverse/_shared, interverse/interstat

**Steps:**
1. **Interflux test conversion** (moved from Agent 1 to avoid repo conflict):
   a. Read `interverse/interflux/tests/structural/` — this is the source repo for Agent 4
   b. Replace with thin wrappers importing from `_shared`
   c. Run `python3 -m pytest tests/structural/ -v`

2. **Session context lib:**
   a. Create `interverse/_shared/hooks/lib-context.sh` with session/bead context functions
   b. Read interstat `hooks/session-start.sh` to understand current pattern
   c. Refactor interstat to source `lib-context.sh` (copy the lib into interstat's hooks/ directory — don't cross-repo source from monorepo path)
   d. For interflux: the existing `interbase-stub.sh` abstraction is sufficient — add context functions there instead of a separate source
   e. Test: `bash -n` on all modified scripts

3. **Agent definition dedup:**
   a. Read all 12 interflux review agents in `agents/review/fd-*.md`
   b. The "First Step (MANDATORY)" text has domain-specific variations (correctness: "write down invariants first"; safety: "determine the real threat model") — **keep these**. Only extract the fully generic paragraph that's identical across all 12.
   c. "What NOT to Flag" — only 9 of 12 agents have this section. Keep the agent-specific exclusion lists. Extract only the closing instruction "Only flag the above if deeply entangled..." to skill docs.
   d. Run `python3 interverse/interflux/scripts/validate-roster.sh` to verify agent integrity
   e. Verify YAML frontmatter parses: `python3 -c "import yaml; [yaml.safe_load(open(f).read().split('---')[1]) for f in glob.glob('agents/review/fd-*.md')]"`

4. Commit and push interflux, _shared, interstat separately

**Verification:** pytest pass, `bash -n` pass, `validate-roster.sh` pass, frontmatter parseable

---

### Agent 5a: F5a — Apps TypeScript Consolidation
**Bead:** sylveste-jo5m
**Repos:** apps/interblog, apps/intersite

**Steps:**
1. **Clerk middleware:** Create `apps/interblog/src/lib/auth-middleware.ts` with `createAuthMiddleware(config)` factory. Both apps have different auth patterns (interblog: email allowlist; intersite: env-configured admin routes) — the factory must accept a config object that handles both variants. Update interblog middleware.ts to use the factory. Document the pattern for intersite (intersite can adopt when ready — don't force it).

2. **API response helpers:** Create `apps/interblog/src/lib/api-utils.ts` with `errorResponse()`, `successResponse()`, `parseJsonBody()`. Refactor `texturaize/submit.ts` and `drafts/save.ts` to use helpers.

3. **Content schemas:** Compare `apps/interblog/src/content.config.ts` with `apps/intersite/src/content.config.ts`. If patterns diverge significantly (they likely do — different approval gates), document as intentionally divergent rather than forcing shared schema.

4. Commit and push interblog and intersite separately

**Verification:** Both apps build successfully

---

### Agent 5b: F5b — Go/TS App Decomposition
**Bead:** sylveste-jo5m (same bead, different agent)
**Repos:** apps/Autarch, apps/Intercom

**Steps:**
1. **Decompose chatpanel.go (921 LOC):**
   a. Read `apps/Autarch/pkg/tui/chatpanel.go`
   b. Extract rendering logic, state management, and input handling into separate files
   c. Target: no single file >600 LOC
   d. Verify: `cd apps/Autarch && go build ./...`

2. **Decompose container-runner.ts (744 LOC):**
   a. Read `apps/Intercom/src/container-runner.ts`
   b. Extract `volume-builder.ts`, `container-executor.ts`, `output-parser.ts`
   c. Keep `container-runner.ts` as orchestrator (~300 LOC)

3. Commit and push each app repo individually

**Verification:** Autarch Go build passes, Intercom TypeScript compiles

---

### Agent 6: F6 — Root Infrastructure Cleanup
**Bead:** sylveste-fomo
**Repo:** root monorepo

**Steps:**
1. **Install/uninstall script dedup:**
   a. Read `install.sh` and `uninstall.sh`
   b. `mkdir -p lib/`
   c. Create `lib/installer-common.sh` with shared color setup and logging functions
   d. Refactor both scripts to source `lib/installer-common.sh`
   e. Verify: `bash -n install.sh && bash -n uninstall.sh`

2. **Stale flux-gen specs:**
   a. Read each file in `.claude/flux-gen-specs/` individually
   b. Only delete files that are genuinely empty/stub (≤8 lines with no meaningful agent specs)
   c. Verify per-file before deleting — do not batch-delete based on line count alone
   d. The actual stub count may be lower than 10 — delete only what's truly empty

3. Commit and push

**Verification:** `bash -n` on install scripts

---

## Changes from Initial Plan (Post-Review)

| Issue | Fix |
|-------|-----|
| Agents 1+4 both touch interflux | Moved interflux test conversion to Agent 4 |
| sdk/interbase/typescript/ doesn't exist | Clerk middleware → interblog-local, not sdk/interbase |
| Agent 5 over-scoped (5 repos) | Split into Agent 5a (TS apps) + Agent 5b (Go/TS decomposition) |
| Agent 2 command file count wrong | "Inventory first" — read ALL files, don't trust plan count |
| run.go function inventory incomplete | "Read full function list before creating files" |
| Store base extraction risky | Dropped — most stores have extra fields |
| Session context cross-repo sourcing fragile | Copy lib into each plugin's hooks/, don't cross-repo source |
| Agent definition domain-specific text | "Keep domain-specific variations" explicit instruction |
| intercept has no tests | Explicit "create from scratch" framing |
| No rollback strategy | Added: `git revert HEAD` per repo |
| Flux-gen spec deletion scope | "Verify per-file" — don't batch-delete |

## Risk Mitigation

- Each agent targets different git repos — no merge conflicts
- All agents verify builds/tests before committing
- Pure refactoring — no behavioral changes
- Rollback: `git revert HEAD` per repo if changes break
- If any agent fails, others continue independently

## Success Metrics

- All 7 agents complete with passing builds/tests
- ~700 additional LOC removed (revised down from ~800 after dropping store extraction)
- Shared test infra covers 10+ plugins total
- All intercore command files use shared flag parser
