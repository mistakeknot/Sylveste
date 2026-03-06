---
artifact_type: brainstorm
bead: iv-t712t.3
stage: discover
---

# First-Stranger Setup Failure Taxonomy

**Bead:** iv-t712t.3
**Parent:** iv-t712t (P0: First-stranger experience)
**Date:** 2026-03-06

## Problem Statement

No external user has ever successfully set up Demarch. The installation infrastructure exists (install.sh, modpack-install.sh, setup.md, doctor.md) but has never been validated by a stranger. The system's fail-safe design — every library degrades gracefully, session-start never blocks — means a 60% broken setup produces zero visible errors. A stranger has no way to know what's missing.

## Research: Failure Taxonomy

### Tier 1: Blocking Failures (Setup Cannot Proceed)

These stop installation dead. User sees an error and knows they're stuck.

| # | Failure | Trigger | Error Message | Fix |
|---|---------|---------|---------------|-----|
| B1 | **jq missing** | `install.sh` | "jq not found" (fatal) | Install jq |
| B2 | **Go missing or < 1.22** | `install.sh` | "go not found" or version check (fatal) | Install/update Go |
| B3 | **Marketplace add fails** | Network down, auth issue | "Marketplace add failed: <err>" (fatal) | Check network, retry |
| B4 | **Clavain plugin install fails** | Marketplace cache corrupt | "Clavain install failed: <err>" (fatal) | Clear cache, retry |

**Assessment:** These are the *good* failures — clear message, known fix. Only 4 exist.

### Tier 2: Silent Failures (Setup Appears to Succeed)

These are the dangerous ones. Install completes, user thinks everything works, but features are broken with no indication.

| # | Failure | What Breaks | User Sees | Stranger Impact |
|---|---------|-------------|-----------|-----------------|
| S1 | **~/.local/bin not on PATH** | `ic` unavailable after build | Nothing (warning at install end, easily missed) | Kernel features silently disabled; sprints, gates, dispatch all fail |
| S2 | **Python 3 + PyYAML missing** | Spec loader falls back to hardcoded defaults | Nothing (stderr warning only) | Agency spec, budget allocation, gates all use wrong values |
| S3 | **yq v4 missing** | Fleet registry queries fail | Nothing (lib-fleet returns empty) | Agent cost estimation, fleet queries return nothing |
| S4 | **Node.js missing** | JS-based plugins fail to build MCP | JSON error to stderr, MCP doesn't start | Intermap, intermux, interserve tools unavailable |
| S5 | **Slow internet** | Plugin install takes 10-30 min | No progress indicator | User thinks installer hung, kills it, partial install |
| S6 | **Dolt server crashed/hung** | `bd` commands hang forever | No output, no error, just hangs | User is completely stuck, no diagnostic |
| S7 | **agency-spec.yaml malformed** | All spec queries return empty | No error (spec_load returns "failed" silently) | Stage budgets, gates, agent roster all wrong |
| S8 | **Companion plugin has syntax error** | Hook sourcing silently skips it | No error (sourced with `2>/dev/null || true`) | Features degrade — no indication which or why |
| S9 | **ic database not initialized** | `ic health` returns non-zero | One-time stderr warning, then nothing | State management, dispatch, cost tracking all fail |
| S10 | **Multiple marketplace conflicts** | Wrong plugin version loaded | No error until features misbehave | Subtle bugs, wrong skill versions |

**Assessment:** 10 silent failures, each invisible to a stranger. The root cause: Demarch's fail-safe design treats every dependency as optional. This is correct for resilience but catastrophic for setup validation.

### Tier 3: Confusion Failures (User Doesn't Know What to Do Next)

| # | Failure | Symptom | What's Missing |
|---|---------|---------|----------------|
| C1 | **No system requirements listed** | User clones repo without Go, Python, yq | README needs prerequisites section |
| C2 | **Subproject repos are confusing** | User doesn't understand why `os/clavain/` has its own git | No architectural onboarding |
| C3 | **Plugin count overwhelming** | 40 plugins to install, no explanation of which matter | No "essential vs nice-to-have" guide |
| C4 | **ic build fails with cryptic Go error** | `go build` fails, error mentions modules | No Go troubleshooting guide |
| C5 | **Post-install: what now?** | Install completes, user opens Claude Code, nothing happens | No first-run guide injection |
| C6 | **Disk space exhausted** | Monorepo + plugins + node_modules = 5-10GB | No size warning |

## Diagnostic Gap Analysis

### What Exists

| Diagnostic | What It Checks | Coverage |
|---|---|---|
| `bd doctor --json` | Beads health, sync state | Good for beads |
| `ic health` | Kernel database state | Good for ic |
| `install.sh` prereqs | jq, go, git, claude, bd | Good but incomplete |
| `lib-fleet.sh` yq check | yq presence and version | Per-library only |
| `lib-spec.sh` python check | Python 3 + PyYAML | Per-library only |

### What's Missing

| Missing Diagnostic | Impact |
|---|---|
| **Unified health check** (`/clavain:doctor` runs but doesn't check Python, yq, Node, PATH) | No single command tells a stranger "your setup is healthy" |
| **PATH validation** | ic built but not found at runtime |
| **Config file validation on startup** | Malformed YAML silently ignored |
| **Plugin load-time error reporting** | Broken plugins silently skipped |
| **First-run detection** | No "you're new here, check these things" |
| **Dependency aggregation** | Missing deps reported individually, never together |
| **Network/disk prereq check** | Large downloads with no warning |

## Proposed Telemetry & Diagnostics

### 1. Enhanced Doctor Command

Add these checks to the existing doctor.md spec:

```
NEW CHECKS:
- Python 3 presence + PyYAML importable
- yq v4 presence + version check
- Node.js 20+ presence (if JS plugins installed)
- ~/.local/bin on PATH (if ic was built there)
- agency-spec.yaml parseable (quick YAML load test)
- routing.yaml parseable
- fleet-registry.yaml parseable
- Dolt server responsive (timeout 5s, not hang forever)
- Plugin hook syntax check (bash -n on each *.sh)
- Plugin version freshness (installed vs marketplace)
```

### 2. First-Run Detection

On session-start, if `.clavain/setup-verified` doesn't exist:
- Run quick health check (subset of doctor)
- If any critical failure: inject warning into context
- If all pass: create `.clavain/setup-verified` (skip on future sessions)

### 3. Install Telemetry

Add timing + status to install.sh output:

```
[1/7] Checking prerequisites...           ✓ (2s)
[2/7] Updating marketplace...             ✓ (15s)
[3/7] Installing Clavain plugin...        ✓ (3s)
[4/7] Installing companion plugins...     ✓ (45s)  [26/26 required, 14 optional]
[5/7] Building ic kernel...               ✓ (12s)
[6/7] Initializing beads...               ✓ (5s)
[7/7] Running health check...             ✓ (3s)

Setup complete in 1m 25s.
```

### 4. Silent Failure Surfacing

For each Tier 2 silent failure, add a diagnostic that runs once per session:

| Silent Failure | Proposed Surface |
|---|---|
| S1: PATH | `session-start.sh`: check `command -v ic` after noting ic was built |
| S2: Python | `session-start.sh`: quick PyYAML import test |
| S3: yq | Only check when fleet/spec features first needed |
| S4: Node.js | Check on MCP server launch failure |
| S5: Slow install | Add progress bar + ETA to modpack-install.sh |
| S6: Dolt hung | `bd stats` with 5s timeout; on timeout, suggest `bash .beads/recover.sh` |
| S7: Bad YAML | Validate on load, surface to doctor |
| S8: Hook syntax | `bash -n` check on session-start (fast, <100ms) |
| S9: ic not init | Already checked; make message clearer |
| S10: Plugin conflicts | Already in doctor; run automatically on first session |

## Key Decisions

1. **Silent degradation is correct for production resilience** — but needs a parallel validation layer for setup
2. **Doctor is the right place** for comprehensive checks — extend it, don't create a new tool
3. **First-run detection** should be lightweight (~200ms) and write a marker file
4. **Progress indicators** are essential for any operation >5 seconds
5. **PATH validation** is the single highest-impact fix (affects every ic-dependent feature)

## Open Questions

1. Should install.sh check for Python/yq/Node.js or just warn post-install?
2. Should first-run detection auto-run doctor or just suggest it?
3. How much install telemetry is too much? (Current: none. Target: timing per step?)
4. Should we add a `--minimal` install mode that skips optional plugins?
5. Pre-built `ic` binaries — worth the CI complexity for better stranger UX?
