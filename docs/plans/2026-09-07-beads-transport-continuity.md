---
artifact_type: plan
bead: sylveste-bkrh
stage: implementation
---
# Restore reliable Beads transport

**Goal:** Ordinary Git commits and pulls carry Beads changes between this Mac and zklw, with durable failure evidence and no silent loss.

**Architecture:** Each host retains its own Dolt database. Git-tracked `.beads/issues.jsonl` and the existing explicit deletion ledger carry changes. Native `bd import` owns transactional stale-update protection. This work repairs that transport; it does not federate Dolt or replace the tracker.

**Alignment:** Durable, observable transport gives portfolio decisions trustworthy evidence.
**Conflict/Risk:** Concurrent database writers and divergent histories require explicit coverage, guarded replacement, and preservation of ambiguity.

## Execution contract

The user updated model routing on September 7: use Sonnet 5 for bounded implementation and Opus 5 for harder implementation; use Opus 5 or GPT-5.6 Sol for independent review, escalating consequential unresolved plan/QA questions to Fable 5.1. The original Fable-only execution requirement is superseded by that explicit instruction. Preserve Claude Code in tmux for Claude execution, pin full model IDs per session, verify native effective identity, and record transitions. Do not change global model defaults or silently substitute models. Use fresh bounded handoffs when retained history adds unnecessary context; preserve prior evidence.

The manifest describes sequencing, not permission for additional implementation fan-out. One source owner at a time; permission mode remains acceptEdits. The integrator retains all review, commit, push, installation, and acceptance gates. The user may further specify whether Fable always performs plan/QA review; until then, use the authorized Opus/Sol first pass and retain Fable escalation for consequential uncertainty.

Executor owns the transport checker/helpers, corresponding hooks and tests, and `ops/beads-two-machine-sync.md`. Integrator owns this plan/manifest, production tracker operations, Git staging/commits/push, hook installation, independent review disposition, and live host acceptance. Executor must not run production imports/exports/deletions, install hooks on live hosts, or commit/push. Disposable fixture databases are authorized. Communicate progress in `/Users/sma/projects/beads-transport-2026-09-07/executor-report.md`; do not create a second task tracker.

Worktree: `/Users/sma/projects/Sylveste-beads-transport`, main, starting at `f9563fd2`. Its native Beads context shares the existing Mac project `07e89680-8485-4489-a63a-9105595860b2` and database `Sylveste`; do not copy metadata or initialize a replacement database. The canonical dirty checkout and other worktrees remain untouched. Independent review runs in a fresh session before landing.

## Prior evidence

- Current transport design: `ops/beads-two-machine-sync.md` and `.beads/PRIME.md`.
- Checker only compares IDs and global max(updated_at), so older-task edits and equal-time conflicts can be missed.
- Export writes directly to the transport file after an insufficient no-loss check.
- Import fallback is unbounded; helper failures and hook diagnostics are hidden; deletions run even after failed imports.
- Hooks exist on Mac and zklw but were absent in the isolated roadmap publishing clone. A native worktree demonstrably shares the existing database without copied configuration.
- Baseline: nine checker tests and the existing export/import shell suites pass. Native import guard and integration coverage must run; skipped native tests are not acceptance evidence.
- Native Mac backup succeeded before implementation. Refresh backups before reconciliation. Keep full snapshots private to their host; model-facing evidence contains IDs, hashes, and necessary reviewed differences.

## Must-haves

- Native Beads records created/updated on either host arrive through ordinary Git commit/push/pull, without manual JSONL shuttling.
- No malformed, missing, ambiguous, or failed coverage is reported as complete.
- One-sided changes apply; conflicting edits retain both versions and report their IDs. Never choose a host or newest timestamp to break ambiguity. Absence is not deletion.
- Existing signed `.beads/push.sh` enforcement, unrelated hooks/index entries, native history, and current project bindings survive.
- Runtime hooks invoke the verified helpers and emit durable evidence of success or incomplete synchronization.

## Task 1: Record comparison and guarded export

Modify `scripts/check_beads_jsonl_dolt_sync.py`, `scripts/beads-auto-export.sh`, and their existing tests; add one shared helper if it avoids duplicated reconciliation logic.

Preserve existing checker flags and JSON fields, adding explicit coverage/conflict results. Compare canonical native-export records by ID, including semantic content rather than only timestamps. Validate input shapes and duplicates; preserve supported non-issue records. Distinguish missing tooling/database, invalid input, drift, and complete equality. Existing advisory callers may remain advisory, but export/publish decisions require complete evidence.

Use a private temporary native export, bounded subprocesses, and validation before changing the transport file. Serialize transport operations for the same Beads identity across worktrees. Check the expected transport bytes again before atomic replacement. Preserve file permissions and unrelated staged changes; retain a separate path-specific export commit and reentrancy/sequence guards.

Use the last verified transport baseline to classify one-sided changes. If a baseline cannot establish provenance, differences remain conflicts. Preserve both conflicting versions in private evidence; public reports contain IDs/hashes. New database work must never overwrite incoming transport-only work or newer/conflicting content. A database write after the captured snapshot remains pending for the next pass, never described as included.

Preserve-and-flag is per record: safe unrelated changes may travel while conflicted IDs retain their current transport versions. Such a pass reports partial/incomplete coverage, never complete synchronization. Do not block every safe update on resolving all historical conflicts.

<verify>
- run: python3 -m pytest tests/test_beads_jsonl_dolt_sync.py -q
  expect: exit 0
- run: bash tests/test_beads_auto_export.sh
  expect: exit 0
</verify>

## Task 2: Bounded, recoverable import

Modify `scripts/beads-import-merged.sh`, `.beads/hooks/post-merge`, and `tests/test_beads_import_merged.sh`. Reuse native per-record import guards; do not replace them with direct SQL writes.

Import only verified changed rows; missing/invalid before-commit information must yield an explicit recoverable result, not an unbounded full import. Detect Git diff/parsing errors. Bound execution on Mac and Linux, including process cleanup. Persist pending batch plus exact before/after commit identities after failure. Retry explicitly and idempotently; verify post-import results before clearing pending state. The helper returns failure; the hook reports that Git completed but Beads sync is incomplete. Do not apply the deletion ledger after an incomplete import. A subsequent unchanged Git pull must not silently strand the pending batch.

Cover the existing deletion helper entrypoints too: failed lookups are not absence; invalid timestamps cannot authorize deletion; refused/failed deletes cannot report complete. Deletion confirmation must not interpret an unreadable sync verdict as approval for a bare export. Extend their existing tests without performing live deletions.

<verify>
- run: bash tests/test_beads_import_merged.sh
  expect: exit 0
- run: BEADS_NATIVE_REQUIRED=1 python3 -m pytest tests/test_bd_import_guard.py -q
  expect: exit 0
- run: bash tests/test_beads_deletion_propagation.sh
  expect: exit 0
</verify>

## Task 3: Hook setup/check and operational documentation

Add an idempotent setup/check command for this existing transport and integration tests. Resolve Git worktree paths correctly, verify actual Beads project/database identity, and preserve foreign hook sections. Isolate worktree hook configuration and prove other worktrees' effective hook paths remain unchanged. Do not silently initialize fresh clone databases. Missing/inactive/mismatched hooks must be visible. Native `bd hooks` support may be composed, but it alone does not install Sylveste's post-commit transport.

Update `ops/beads-two-machine-sync.md` with actual topology, setup/check commands, recovery of pending imports, conflict evidence, and canary procedure. Fix directly relevant stale instructions in `.beads/PRIME.md` if needed; do not widen into unrelated documentation cleanup.

Tests exercise actual Git commit and pull hooks in disposable repositories, including no-change behavior, worktree discovery, failure output, retry, and foreign hooks. Also run `bash tests/test_beads_metadata_isolation.sh` and all changed-file checks required by the repository.

## Task 4: Independent review, publish, and installed verification

Integrator refreshes origin and records its exact SHA and changed paths. Fast-forward the source worktree before the final freeze, only after confirming no overlap with the owned changes and protecting the native tracker from old hooks as described below. If there is overlap, preserve both versions, integrate deliberately, and repeat affected checks. Freeze the integrated source and test evidence; an independent Opus 5 or GPT-5.6 Sol session reviews source and acceptance coverage, with Fable 5.1 escalation for consequential unresolved plan/QA questions under the updated user routing. Earlier Fable findings remain required dispositions; changing reviewers does not clear them. Verify each finding and repair Important/Critical issues before landing. Later upstream movement requires another overlap/integration assessment, a renewed freeze, and review of any integration delta.

Commit scoped logical units directly to main, using TZ=UTC; preserve unrelated index/worktree state. Source-only commits use the existing invocation-local `BEADS_NO_AUTO_EXPORT=1` opt-out and must not include an unreviewed transport payload. Required CI must pass for the exact published revision. Record the enforced check context, CI run and exact tag/commit SHA; a passing upstream check does not cover the repair. Do not bypass branch protection; the established non-release CI-tag workflow can obtain required checks.

Before the initial source advances on either host, record effective hook paths and hashes and check for active transport writers. During this bootstrap only, prevent the old managed transport importer/exporter and native automatic import from mutating Beads. Preserve unrelated hook behavior and quality gates; retain the exact invocation-local override or temporary hook composition and its diff as evidence. Do not persist a global hook bypass. Verify the source advance introduced only the expected committed transport bytes and no native database changes. Install/check the exact CI-passed producer hooks before beginning reconciliation; bootstrap operations earn no live transport acceptance credit.

Installation covers `/Users/sma/projects/Sylveste-beads-transport` and the zklw main checkout. The dirty canonical Mac checkout and other worktrees are excluded consumers whose source, index and hook configuration must remain intact. Record their unchanged effective hook paths, the canonical branch/dirty status and old-hook hashes. A two-checkout canary cannot establish that all Mac worktrees are repaired. Canonical post-commit exports only its own branch transport; its old post-merge can mutate the shared native database and remains unsafe outside this result. Keep canonical commits, merges, pulls and Beads writes quiescent from the pre-canary snapshot through final reconciliation, verify shared-database deltas against the expected canary changes, and investigate any other mutation before accepting evidence. A bounded route can close after these gates without upgrading an excluded consumer; do not imply that preserving that consumer makes it verified. This scope disposition is independently reviewed, not permission to broaden installation.

Mandatory native-bd receipts set `BEADS_NATIVE_REQUIRED=1` and record a positive test count with zero skips. Missing tooling or fixture initialization failure must fail that gate. Include a real helper success path and a divergent Git-history conflict case; native stale-write tests alone do not exercise the helper's JSON response handling.

Before live reconciliation refresh native backups and per-record comparisons on both hosts. Establish a common baseline from reviewed Git/native provenance and record its commit, semantic hashes, identity and coverage before invoking `--seed-baseline`; never seed automatically from a divergent current native snapshot or assume HEAD is verified. A record without established provenance remains ambiguous. Apply verified one-sided deltas through the repaired Git transport, preserving ambiguous conflicts privately. Confirm conflicts remain recorded through a subsequent no-change export. Review transport changes for inappropriate private data before publication. Keep existing Dolt remotes and signing policy.

Create a clearly labeled canary on Mac, update it, commit/push through normal commands, run the first ordinary `git pull --ff-only` on zklw, and query native Beads. Update/close on zklw, return through the same Git transport, and query Mac after its first ordinary pull. Each leg requires a durable `import: verified` verdict tied to exact before/after commit SHAs, no pending batch, the expected semantic native value, and no retry. A correct native row with an incomplete verdict does not pass. No manual export/import commands may substitute for this journey. Test pending import recovery separately without live destructive fault injection; recovery cannot qualify the clean first-pass canary. Record executable/hook/commit identities and command results.

Re-run the per-record reconciliation report and deterministic roadmap/backlog checks. Close sylveste-bkrh only when the live journey passes and unresolved conflicts are resolved; otherwise retain the explicit blocker. Signed Dolt backup push is separate evidence from cross-host transport. Remontoire reprioritization remains disabled.

## Token efficiency

One implementation session plus one fresh bounded review. Use deterministic checks for unchanged state and retries, focused file reads, bounded tmux tails, and compact handoffs. Measure native session usage without claiming complete pricing coverage or predetermined savings. No LLM polling loop and no extra model calls for a no-change transport check.
