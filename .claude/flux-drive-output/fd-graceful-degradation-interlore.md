---
agent: fd-graceful-degradation
mode: review
target: docs/prds/2026-03-21-interlore.md
timestamp: 2026-03-21
---

# Graceful Degradation Review: interlore PRD

## P0 — Findings that will cause silent wrong results or broken workflows

### P0-1: Alignment/Conflict lines barely exist — primary extraction signal is nearly absent

The PRD (F3) and brainstorm both cite "Alignment/Conflict lines from brainstorm frontmatter" as a primary extraction pattern. In practice, only 3 of 167 brainstorms contain an `Alignment:` line. Zero contain a structured `Conflict:` line. The brainstorm calls this "interdoc's existing format" but interdoc never enforced it — it is aspirational, not actual.

**Impact:** If interlore relies on Alignment/Conflict lines as a primary signal, it will extract almost nothing from the largest artifact corpus (brainstorms). The "established (3+ artifacts)" classification threshold becomes unreachable for most patterns. Users run `/interlore:scan`, get zero proposals, conclude the tool is broken.

**Fix required:** The PRD must specify what interlore actually extracts from the 164 brainstorms that lack Alignment/Conflict lines. Options: section headers ("Why This Approach", "Key Decisions"), inline bold-prefixed rationale ("**Problem:**", "**Solution:**"), or recurring keywords in decision sections. The brainstorm acknowledges "recurring keywords, section headers" as v1 structural patterns but the PRD acceptance criteria only mention "Alignment/Conflict lines and recurring tradeoff resolutions" — the fallback extraction is unspecified.

### P0-2: No minimum corpus threshold or below-threshold behavior defined

The PRD says "missing artifact dirs silently skipped" (F3 AC) but does not define what happens when all dirs exist but contain insufficient artifacts. Scenarios:

- A subproject has 1 brainstorm and 0 PRDs. interlore scans, finds nothing classifiable above "nascent," writes an empty proposals file.
- A new project has no `docs/` at all (fresh `interverse/` plugin). All globs return empty.

The PRD should define: (a) a minimum artifact count below which scan outputs a "not enough data" message instead of an empty proposals file, and (b) whether `/interlore:status` distinguishes "scanned and found nothing" from "not enough data to scan meaningfully."

**Suggested threshold:** At least 5 decision artifacts across at least 2 scanned directories before producing proposals. Below that, status should report "insufficient corpus" not "no patterns detected."

### P0-3: Sprint Stop hook failure propagation is unspecified

F5 says: "Sprint Stop hook runs `interlore scan --quiet` after sprint completion." The PRD says "Hook is optional — interlore works fully without it." But it does not specify:

1. Whether the hook must exit 0 on failure (the Clavain hook contract requires "exit 0 always" — see `auto-stop-actions.sh` line 18).
2. What happens if `interlore scan --quiet` hangs (no timeout specified; the existing Stop hooks use 5s timeout in hooks.json).
3. Whether interlore scan failures should block the Stop hook's other tiers (compound, dispatch, drift check).

The existing `auto-stop-actions.sh` is a tiered decision system. Adding interlore as a new tier (or integrating into the existing drift tier) requires specifying its priority relative to compound/dispatch/drift and its failure isolation.

**Fix required:** F5 ACs must include: "interlore hook exits 0 on all error paths," "hook timeout <= 5s," and "interlore scan failure does not prevent compound/dispatch/drift tiers from executing."

## P1 — Findings that cause degraded but recoverable behavior

### P1-1: `.claude/flux-drive-output/` absent for most subprojects

The PRD scans `.claude/flux-drive-output/fd-*.md` as one of 5 artifact sources. This directory exists at the monorepo root (67 files) and in `os/Skaffen/` (6 files), but is absent from all 53 Interverse plugins and most other subprojects. The PRD says "missing artifact dirs silently skipped" which handles the absent case.

However, if interlore is later scoped to subprojects (Open Question #2), the flux-drive source will be empty for nearly all of them, silently reducing corpus quality. The PRD should acknowledge this in the cross-project expansion section and note that subproject scans will be dominated by brainstorms/PRDs alone.

### P1-2: No handling specified for PHILOSOPHY.md absence

F3 diffs extracted patterns "against current PHILOSOPHY.md sections." If PHILOSOPHY.md does not exist (e.g., a subproject that hasn't created one yet, or a fresh project adopting interlore), the diff operation has no baseline.

**Expected behavior should be specified:** If PHILOSOPHY.md is absent, all detected patterns should be classified as EMERGING (no drift possible), and scan should emit a warning: "No PHILOSOPHY.md found — all patterns classified as emerging."

### P1-3: proposals.md accumulation without bounds

The PRD specifies that proposals accumulate in `.clavain/interlore/proposals.md` and rejected proposals are "excluded from future scans." But there is no specified mechanism for:

- Purging old accepted/rejected proposals from the staging file
- Maximum proposal count before scan stops adding new ones
- What happens when the same pattern is re-detected after rejection (the reject reason might not survive pattern re-extraction from new artifacts)

Over time, the proposals file will grow unbounded. Deferred proposals re-trigger every scan. Rejected proposals need a persistent exclusion list that survives across scans, but the PRD only says "marks proposal as rejected with reason" without specifying where the exclusion state lives or how it is matched.

### P1-4: `docs/prd/*.md` vs `docs/prds/*.md` — dual-path ambiguity

F3 scans both `docs/prds/*.md` (116 files) and `docs/prd/*.md` (5 files). This is correct for the current repo state, but creates a deduplication risk: if a file is moved from `docs/prd/` to `docs/prds/`, interlore would count the same decision patterns from the old location (if cached in proposals) and the new location. The PRD should specify that pattern evidence is keyed by content hash or canonical path, not by discovery path.

## P2 — Findings that cause confusion or suboptimal output

### P2-1: No dry-run or preview mode specified

The PRD has no `--dry-run`, `--preview`, or `--check` flag for `/interlore:scan`. Users cannot see what interlore would detect without writing to the proposals staging file. This matters because:

- First-time users want to evaluate output quality before committing to the workflow.
- After changing PHILOSOPHY.md, users want to verify the diff logic works correctly.
- Testing pattern extraction rules during development requires a non-destructive mode.

**Suggested:** Add `interlore scan --preview` that prints detected patterns and proposed classifications to stdout without writing to proposals.md.

### P2-2: Malformed artifact handling unspecified

The PRD globs `docs/brainstorms/*.md`, `docs/prds/*.md`, etc. These directories may contain:

- Files with invalid YAML frontmatter (unclosed quotes, tabs in YAML, missing `---` delimiter)
- Binary files accidentally matching `*.md` (rare but possible via misnamed attachments)
- Empty files (created by interrupted writes)
- Files with frontmatter only and no body content

The PRD should specify: (a) malformed files are skipped with a warning in scan output, (b) binary detection (check first 512 bytes for null bytes), and (c) minimum file size or content threshold to consider a file scannable.

### P2-3: interwatch signal type not in existing taxonomy

F5 specifies adding `interlore_patterns_pending` as a signal type in interwatch's `watchables.yaml`. The current watchables.yaml uses 17 signal types, none of which follow the `<plugin>_<metric>` naming pattern. All existing types are generic (`bead_closed`, `file_created`, `version_bump`, `commits_since_update`). The proposed signal name breaks the naming convention.

**Suggested:** Use a generic signal type like `external_metric` or `plugin_metric` with configuration pointing to interlore, or align with the existing naming pattern (e.g., `patterns_pending` without the plugin prefix, with the checker field pointing to interlore's state).

## P3 — Minor gaps, future-proofing

### P3-1: `--quiet` flag behavior undefined

F5 references `interlore scan --quiet` for the hook integration but the scan command in F3 does not define a `--quiet` flag or its behavior. Presumably it suppresses stdout output and only writes to the proposals file, but this should be explicit in the AC.

### P3-2: Classification thresholds are time-dependent but clock source unspecified

F3 classifies patterns as "established (3+ artifacts, 2+ weeks)." The "2+ weeks" criterion requires comparing artifact dates. The PRD does not specify whether this uses git commit dates, file modification times, or YAML frontmatter dates. Each has different failure modes: frontmatter dates may be absent or malformed, git dates require a git repo, mtime is unreliable after clones.

### P3-3: `.clavain/interlore/` directory creation

The PRD writes proposals to `.clavain/interlore/proposals.md` but does not specify whether scan creates this directory on first run, or whether it expects it to exist. Should be explicit: scan creates the directory tree if absent.

### P3-4: Concurrent scan safety

If two sessions run `/interlore:scan` simultaneously (e.g., sprint hook + manual invocation), they could race on writing proposals.md. The PRD should note whether this is a concern and whether file-level locking or last-writer-wins is acceptable.
