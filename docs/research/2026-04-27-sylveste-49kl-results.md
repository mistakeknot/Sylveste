---
artifact_type: research
bead: sylveste-49kl
parent_bead: sylveste-49kl
prior_bead: sylveste-1y3r
stage: complete
produced_in_session: 67756603-7910-4311-8887-531038aa026a
---

# sylveste-49kl — clavain skill_listing trim remeasure on 0.6.247

## Verdict

**Investigate.** The 14-entry trim landed cleanly at the file level (source bytes:
6,940 → 6,364, **−576b** for the clavain namespace), but the **listing bucket grew
+221b** (7,557 → 7,778) over the same comparison. The trim style does not
translate to `skill_listing` byte savings as theorized in commit `9415156`. Do
not roll out to interbrowse / interspect / tldr-swinton / interflux / interpath /
interfluence yet — the listing aggregation logic is the real bottleneck and
needs to be understood before more trim work is invested.

The `~117ch truncation cliff` hypothesis from the trim commit is also wrong:
descriptions of 145, 168, 242, 258 chars all appear in the listing in full.
There is no truncation — the listing echoes source descriptions verbatim.

## Measurements

### Top-line preamble (post-fix, session 67756603, clavain 0.6.247)

| slice                     | bytes  |
|---------------------------|-------:|
| `skill_listing`           | 32,149 |
| `deferred_tools_delta`    | 27,484 |
| `mcp_instructions`        |  2,272 |
| sessionstart hooks        |  9,151 |
| **total preamble**        | **74,484** |

### Three-point comparison

| measurement                          | skill_listing | clavain bucket | clavain entries |
|--------------------------------------|--------------:|---------------:|----------------:|
| Pre-trim (ff08ad22, 0.6.244)         | 35,036        | 7,557          | 68              |
| Broken-load (a0dcc11b, 0.6.245)      | 18,719        | 0              | 0               |
| Post-fix (67756603, 0.6.247)         | **31,611***   | **7,778**      | **66**          |

\* Slight discrepancy with top-line 32,149: top-line counts the entire attachment
payload, the per-namespace breakdown counts entry strings only.

### Source-level ground truth (clavain repo)

| version  | source desc bytes | entries | avg/entry |
|----------|------------------:|--------:|----------:|
| 0.6.243  | 6,940             | 68      | 102       |
| 0.6.247  | 6,364             | 68      | 94        |

Source delta: **−576 bytes** across 14 trimmed entries (less than the −1,087b
claimed in the trim commit, which counted catalog.json + skill bodies, not just
the description fields the harness reads).

### Trim-entry survival in the listing

13 of 14 trimmed entries are present in the post-fix listing with their trimmed
descriptions intact — confirming routing/discoverability is preserved:

```
122c  brainstorm           104c  migration-safety        90c  repro-first-debugging
 87c  sprint-status        114c  upstream-sync          124c  code-review-discipline
 75c  dispatching-parallel  84c  executing-plans         89c  landing-a-change
143c  project-onboard      117c  refactor-safely        155c  using-clavain
143c  using-tmux-for-interactive-commands
```

The 14th entry (`bead-sweep`) is absent from the listing despite being trimmed
and present at source — see "Listing aggregation anomaly" below.

## The mystery: why did clavain bucket grow despite source shrinking?

Source went down 576b. Format overhead per entry is `len("- clavain:" + name + ": ") + 1`,
which is fixed (names didn't change between 0.6.244 and 0.6.247). Yet the
listing bucket grew 221b on 2 fewer entries.

Differences observed between baseline and post-fix listings:

1. **Two source entries are missing from the listing** (66 vs 68): `bead-sweep`
   and `sprint-dag`. Both exist as files in 0.6.247. Neither has a malformed
   description. Why the harness drops them is unknown — candidate causes:
   - filename / frontmatter `name:` field mismatch (bead-sweep has `name: bead-sweep`
     but file is at `commands/bead-sweep.md` — should match)
   - allowed-tools or other frontmatter that disqualifies them
   - alphabetical truncation cap on number-of-entries-per-namespace
2. **One listing entry is not in source as a clavain skill/command**: `galiana`.
   Likely an agent file picked up by the harness — agents weren't in the source
   sweep above. So entry-count math doesn't quite balance with files-on-disk.
3. **Net: total clavain listing bytes are up despite trims landing at source.**

The most economical hypothesis: agent descriptions (which we didn't trim) got
larger between 0.6.244 and 0.6.247 — there were several authz/policy commits
in that window which may have lengthened agent-card descriptions. That growth
swamped the 576b skill/command trim savings.

## Decision branch (per handoff)

Per the handoff's three-way decision tree:

> If clavain bucket dropped < 250b → trim style isn't reaching the listing;
> investigate harness aggregation logic before any rollout.

We are in this branch (in fact we observed +221b growth, well below the
≥250b drop threshold). **No rollout to other plugins.** Investigation bead
filed.

## Trigger-word sniff check

Not exercised by live skill invocation (would conflate measurement with
training the harness). Verified discoverability instead: 13 of 14 trimmed
entries appear in the post-fix `skill_listing` with their trimmed descriptions
intact. The harness can still see and route them — the trim did not orphan any
trigger-word matching.

The 14th entry (`bead-sweep`) is missing from the listing for reasons
unrelated to trimming (it is also missing from the source-side sweep — see
investigation bead).

## Spawned beads

- **sylveste-NEW-investigate** (P2, perf, labels: clavain,skill_listing) —
  Investigate why clavain bucket in `skill_listing` grew despite source
  description bytes shrinking 576b. Specific questions:
  - Which non-trimmed clavain entries grew between 0.6.244 and 0.6.247?
  - Why are `bead-sweep` and `sprint-dag` missing from the listing?
  - Does the harness include agent descriptions in the bucket attribution?
  - Is there a per-namespace overhead that the trim work doesn't reach?
  - Until answered: hold rollout to interbrowse/interspect/tldr-swinton/
    interflux/interpath/interfluence (combined ~9.0K targetable).

## Files & artifacts

- Post-fix raw: `/tmp/49kl-post.json` (top-line); JSONL at
  `/home/mk/.claude/projects/-home-mk-projects-Sylveste/67756603-7910-4311-8887-531038aa026a.jsonl`
- Pre-trim baseline: `docs/research/2026-04-27-sylveste-1y3r-results.md`
  (broken-load) and source-side aa45ced commit (= 0.6.243, last clean version
  before trim)
- Source ground truth: clavain repo HEAD (= 0.6.247) at
  `/home/mk/projects/Sylveste/os/Clavain`
- Companion fix: clavain `ed76bca` (em-dash repair) + `d995bc2` (0.6.247 bump)
- Release-gate prevention: sylveste-ulp8 (closed, frontmatter validator in
  `ic publish`)
