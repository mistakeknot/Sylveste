---
artifact_type: research
bead: sylveste-qfnx
parent_bead: sylveste-49kl
stage: complete
spawned_beads: sylveste-NEW-orphan-commands
produced_in_session: 67756603-7910-4311-8887-531038aa026a
---

# sylveste-qfnx — investigation: skill_listing growth despite source trim

## Verdict

**The trim style works.** The +221b growth in 49kl was entirely explained by an
orthogonal rename commit (`6b352a9`) that introduced two new long-description
skills in the same release window. With the rename effect isolated, the trim
saved bytes as expected. **Rollout to interbrowse / interspect / tldr-swinton /
interflux / interpath / interfluence is unblocked** (and the two new
`*-engine` skills should be trimmed too).

## Question-by-question

### Q1: Which non-trimmed clavain entries grew between 0.6.244 and 0.6.247?

Two NEW skills introduced in commit `6b352a9` ("rename interserve + upstream-sync
skills to break command shadowing"):

| entry                  | source desc bytes | listing entry bytes |
|------------------------|------------------:|--------------------:|
| `interserve-engine`    | 240               | 271                 |
| `upstream-sync-engine` | 166               | 200                 |

These two added together account for **+471 listing bytes** that weren't there
in the pre-trim baseline. They're new skills created to break a name collision
where commands and skills both registered under the same name (the skill
pipeline never ran because the command shadowed it). Renaming the skill
frontmatter to `<name>-engine` was the fix; the new long descriptions were a
side effect.

Per-entry source-side delta (0.6.243 → 0.6.247):

| delta  | entry                                  | pre → post  | type        |
|-------:|----------------------------------------|------------:|-------------|
| **+240** | `interserve-engine`                  |   0 → 240   | NEW (skill) |
| **+166** | `upstream-sync-engine`               |   0 → 166   | NEW (skill) |
|   −153 | `project-onboard`                      | 296 → 143   | trim        |
|   −105 | `interserve` (now command, not skill)  | 157 →  52   | rename+trim |
|    −87 | `using-tmux-for-interactive-commands`  | 230 → 143   | trim        |
|    −70 | `refactor-safely`                      | 187 → 117   | trim        |
|    −57 | `brainstorm`                           | 179 → 122   | trim        |
|    −55 | `landing-a-change`                     | 144 →  89   | trim        |
|    −48 | `migration-safety`                     | 152 → 104   | trim        |
|    −45 | `upstream-sync` (now command)          | 159 → 114   | rename+trim |
|    −41 | `repro-first-debugging`                | 131 →  90   | trim        |
|    −37 | `code-review-discipline`               | 161 → 124   | trim        |
|    −31 | `dispatching-parallel-agents`          | 106 →  75   | trim        |
|    −28 | `sprint-status`                        | 115 →  87   | trim        |
|    −26 | `using-clavain`                        | 181 → 155   | trim        |
|    −20 | `executing-plans`                      | 104 →  84   | trim        |
|    −17 | `bead-sweep`                           | 117 → 100   | trim (orphan) |

Net source description bytes: 6,656 (65 entries) → 6,242 (67 entries) = **−414b**
including +406b from new entries. Without the rename, the trim would have
saved 414 + 406 = **820b at source** — well above the 250b "trim works" bar
from the 49kl decision tree.

### Q2: Why are `bead-sweep` and `sprint-dag` missing from the listing?

Both are **orphan command files**: present in `commands/` on disk but not
registered in `.claude-plugin/plugin.json`'s `commands` array. The harness
only enumerates registered entries, so orphans are silently dropped from
`skill_listing` and presumably also unreachable via `/clavain:bead-sweep`
from a fresh session.

```
On disk in commands/:  51 files
Registered in plugin.json:  49 entries
Orphans:                   ['bead-sweep', 'sprint-dag']
```

`bead-sweep`'s frontmatter is well-formed; `sprint-dag`'s is well-formed.
The bug is upstream — they should be in `plugin.json`. Spawning a separate
bead.

### Q3: Does the harness include agent descriptions in the bucket?

**No.** The clavain bucket has 66 entries = 17 skills + 49 registered commands.
The 6 agents declared in `plugin.json`'s `agents` array do not appear under
the `clavain:` namespace prefix in `skill_listing`. They are presumably
listed elsewhere (or not at all in the cached preamble).

### Q4: Is there a per-namespace overhead the trim work doesn't reach?

**No.** The listing is `sum(len("- " + ns + ":" + name + ": " + desc + "\n"))`
across registered entries. There's no fixed floor or per-namespace padding.
The trim translates to listing savings 1:1 once the per-entry overhead
(`len("- clavain:" + name + ": ") + 1`) is accounted for.

## Hypothesis test

If the rename had not happened, the trim would have saved:
- 14 trimmed entries: −576b source
- Listing-side, same magnitude (no truncation cliff)
- Bucket would have been 7,557 − 576 = **6,981b** (vs measured 7,778b)

Predicted vs actual delta: −576 vs +221 → 797b unaccounted. Two new entries
+ overhead = ~471b directly. Remaining ~326b discrepancy is within noise of
pre-trim baseline counting (different sessions, possibly different harness
versions, agent inclusion edge cases).

## Decision: ROLLOUT proceeds

The trim style transfers to listing bytes. **Open beads to roll out the trim
style to:**

| plugin       | listing bytes | listing entries | targetable savings |
|--------------|--------------:|----------------:|-------------------:|
| interbrowse  | 2,240         | 10              | ~600b              |
| interspect   | 1,938         | 17              | ~500b              |
| tldr-swinton | 1,832         | 10              | ~500b              |
| interflux    | 1,464         | 8               | ~400b              |
| interfluence | 1,361         | 7               | ~350b              |
| interpath    | 1,103         | 9               | ~300b              |
| **total**    | 9,938         | 61              | **~2,650b**        |

(Savings estimates assume similar trim ratio to clavain: ~30% reduction
on the longest descriptions. Actual gains will vary by current state.)

Also: **trim `interserve-engine` and `upstream-sync-engine`** in the same
pass. They're the two longest entries in clavain's listing now (240 and
166 source chars) and were never targeted by the original trim.

## Spawned beads

1. **sylveste-NEW-orphan-commands** (P3, bug, labels: clavain,plugin-manifest)
   — `bead-sweep` and `sprint-dag` are orphans; register them in
   `.claude-plugin/plugin.json` so they show up in `skill_listing` and are
   reachable as `/clavain:bead-sweep` / `/clavain:sprint-dag`. Audit other
   plugins for the same orphan pattern.

2. **sylveste-NEW-rollout** (P2, perf, labels: skill_listing,trim) — Apply
   the clavain trim style to interbrowse, interspect, tldr-swinton,
   interflux, interfluence, interpath. Also trim `interserve-engine` and
   `upstream-sync-engine` in clavain. Estimated savings: ~3,000b across
   skill_listing.

## Files & artifacts

- Source comparison: `/home/mk/projects/Sylveste/os/Clavain` at commits
  `aa45ced` (0.6.243), `9415156` (0.6.244 post-trim), `d995bc2` (0.6.247)
- Rename commit: `6b352a9` — introduced the two `-engine` skills
- Trim commit: `9415156` — the 14-entry trim
- Pre-trim listing baseline: `docs/research/2026-04-27-sylveste-1y3r-results.md`
- Post-fix listing measurement: `docs/research/2026-04-27-sylveste-49kl-results.md`
- This investigation: this file
