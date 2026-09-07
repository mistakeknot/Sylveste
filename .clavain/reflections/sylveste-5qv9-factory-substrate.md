---
bead: sylveste-5qv9
predecessor: iv-ho3
title: Factory Substrate — validation-first infrastructure for Clavain
sprint_date: 2026-04-10
artifact_type: reflection
---

# Reflection: Factory Substrate (sylveste-5qv9)

## What happened

This sprint resurrected iv-ho3, a factory substrate epic that was lost in the 2026-03-05 beads DB reinit. The original work (brainstorm, PRD, plan, plan review, and full implementation across 6 features) was completed in early March 2026 sessions but the tracking bead disappeared.

**This session's work:**
1. Archaeological recovery — found iv-ho3 in git history and old JSONL backups
2. Created successor bead sylveste-5qv9 and linked existing artifacts
3. Triaged 117 orphaned plans/PRDs: 82 shipped, 22 need new beads, 13 obsolete
4. Batch-created 22 replacement beads (3 P1, 11 P2, 8 P3)
5. Built CXDB server from vendored Rust source (67s compile)
6. Fixed cxdbStoreBlob bug (returned "" instead of BLAKE3 hash)
7. Added integration test exercising full CXDB round-trip
8. Verified all 6 feature areas: CXDB lifecycle, scenario bank, satisfaction scoring, evidence pipeline, policy enforcement, factory status dashboard

## What we learned

**Ghost infrastructure is the dominant pattern.** The CXDB integration had 3515 lines of Go code, all tests passing, all commands registered — but the binary had never been built or installed. The code was 100% complete for local-only unit tests but 0% verified against a live server. The single bug found (cxdbStoreBlob returning "") would have been caught by any integration test.

**Beads DB data loss is systemic, not episodic.** We found TWO data loss events: the 2026-03-05 `iv-` prefix reinit and a later `Sylveste-*` uppercase loss. 82 shipped items lost their tracking records. The tracker under-represents project progress by ~80 closed beads. The root cause is likely Dolt crash/reinit cycles that don't fully restore from JSONL backup.

**BEADS_DIR auto-detection fails from subdirectories.** `bd` and `clavain-cli` both fail to find `.beads/` when the working directory is in a subproject (e.g., `os/Clavain/cmd/clavain-cli/`). This means any session that `cd`s into a Go module for builds will silently lose bead connectivity unless BEADS_DIR is exported.

## What to do differently

- **Integration tests should be written with the initial implementation**, not deferred. The cxdbStoreBlob bug survived for 5+ weeks because all tests were unit tests.
- **BEADS_DIR should be set in session-start hooks** to prevent auto-detection failures when working in subdirectories.
- **Periodic orphan scans** should be automated — the gap between "what's tracked" and "what's built" grows silently.

## Remaining work

The factory substrate code is verified end-to-end but the CXDB binary is only built locally. For production:
- Run the GitHub Actions workflow to produce cross-platform binaries
- Add `clavain setup` download integration (F1 Step 1.4)
- Register type bundles on startup (the types.json path resolution needs CLAUDE_PLUGIN_ROOT or CLAVAIN_SOURCE_DIR)
- Wire the `ic state` context ID caching so CXDB contexts persist across sessions
