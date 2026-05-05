# Interflect full-loop dogfood — fresh sessions

Bead: `sylveste-e1ef` — Dogfood Interflect full extract→review→apply-draft loop on fresh sessions
Date: 2026-05-05
Scope: fresh `session_search`-style summaries after the 2026-05-04 Interflect hardening pass. This run exercises extract → analyze → review → apply-draft and preserves v0 proposal-only behavior.

## Source set

Used 6 fresh/recent session-search summaries:

| Session | Handle | Topic |
|---|---|---|
| `20260505_071335_83cbbddd` | `session_search:20260505_071335_83cbbddd` | Sweep broader server |
| `20260505_071313_36a2d74c` | `session_search:20260505_071313_36a2d74c` | Leave queued without repository changes |
| `20260505_070336_a71a8bcf` | `session_search:20260505_070336_a71a8bcf` | Review child creation for Hermes upgrade aftercare |
| `cron_9d343ae835e2_20260505_070240` | `session_search:cron_9d343ae835e2_20260505_070240` | Scheduled Check audit rules |
| `20260504_080014_d05f2f80` | `session_search:20260504_080014_d05f2f80` | Closed Hermes coordination bead with review blockers |
| `20260504_081842_26dc9c35` | `session_search:20260504_081842_26dc9c35` | Nousromancer product lane thesis |

## Artifacts

- Source export: `fresh-session-export.jsonl` (sha256 `a2f6493f27681fe3`)
- Extracted candidates: `extracted-candidates.jsonl` (sha256 `4c79f728a21f3e9d`)
- Proposal queue: `proposals.jsonl` (sha256 `98a98367ec1a9ff7`)
- Review cards: `review-cards.md`
- Human review outcomes: `review-outcomes.jsonl`
- Apply smoke results: `apply-results.jsonl`
- Safe apply drafts: `apply-drafts/`

## Commands exercised

```bash
PYTHONPATH=/home/mk/projects/interflect/src python3 -m interflect.cli extract \
  --session-jsonl docs/research/interflect/2026-05-05-full-loop-dogfood/fresh-session-export.jsonl \
  --output-jsonl docs/research/interflect/2026-05-05-full-loop-dogfood/extracted-candidates.jsonl

PYTHONPATH=/home/mk/projects/interflect/src python3 -m interflect.cli analyze \
  --input-jsonl docs/research/interflect/2026-05-05-full-loop-dogfood/extracted-candidates.jsonl \
  --store docs/research/interflect/2026-05-05-full-loop-dogfood/proposals.jsonl \
  --cards > docs/research/interflect/2026-05-05-full-loop-dogfood/review-cards.md

PYTHONPATH=/home/mk/projects/interflect/src python3 -m interflect.cli review --store ... --proposal-id ... --decision ... --final-target ...
PYTHONPATH=/home/mk/projects/interflect/src python3 -m interflect.cli apply --store ... --proposal-id ... --artifact-dir ...
```

## Summary

- Source sessions: **6**
- Extracted candidates/proposals: **10 / 10**
- v0 target distribution: `{'runtime_only': 7, 'skill_patch': 1, 'beads_followup': 1, 'repo_doctrine': 1}`
- Review decisions: `{'reclassified': 6, 'accepted': 3, 'rejected': 1}`
- Final target distribution: `{'skill_patch': 6, 'runtime_only': 1, 'beads_followup': 1, 'repo_doctrine': 2}`
- Apply drafts emitted: **9**
- Expected apply refusals: **1**

## Review table

| # | Source session | v0 target | Decision / final target | Claim | Rationale |
|---:|---|---|---|---|---|
| 1 | `20260505_071335_83cbbddd` | `runtime_only` | **reclassified** → `skill_patch` | Athenwork guidance says assistants should not scrape unseen Discord server history; use visible thread context plus Beads/repo/CASS evidence. | Reusable Discord/Athenwork operating procedure; not merely runtime residue. |
| 2 | `20260505_071313_36a2d74c` | `runtime_only` | **reclassified** → `skill_patch` | Treat Leave queued as no repository changes: no bead opened, no patch prompt generated, no file inspection, no tests, and no commits. | Button/queue behavior is a reusable workflow rule for future sessions. |
| 3 | `20260505_070336_a71a8bcf` | `skill_patch` | **accepted** → `skill_patch` | Treat Beads creation success separately from auto-export git add warnings; verify the mutation with bd show and push Dolt state. | Matches existing Beads operational pitfall taxonomy. |
| 4 | `cron_9d343ae835e2_20260505_070240` | `runtime_only` | **reclassified** → `skill_patch` | Scheduled Check should be a bounded read-only health and pickup audit, not permission to claim beads, implement patches, commit files, or restart services. | Cron/check and deployment handling are reusable operational procedures. |
| 5 | `cron_9d343ae835e2_20260505_070240` | `runtime_only` | **reclassified** → `skill_patch` | Tracked skill edits or relevant untracked skill reference files are material scheduled-check state and should be reported. | Cron/check and deployment handling are reusable operational procedures. |
| 6 | `cron_9d343ae835e2_20260505_070240` | `runtime_only` | **reclassified** → `skill_patch` | Do not run hermes update for the customized Amtiskaw deployment just because hermes version says an update is available. | Cron/check and deployment handling are reusable operational procedures. |
| 7 | `cron_9d343ae835e2_20260505_070240` | `runtime_only` | **rejected** → `runtime_only` | Port 34143 was observed during the current runtime check. | Port/PID observations are runtime residue and should not be promoted. |
| 8 | `20260504_080014_d05f2f80` | `beads_followup` | **accepted** → `beads_followup` | Closed implementation beads with untracked review artifacts can still justify creating a follow-up bead instead of treating the lane as fully final. | Concrete follow-up task capture is the intended promotion target. |
| 9 | `20260504_081842_26dc9c35` | `repo_doctrine` | **accepted** → `repo_doctrine` | Nousromancer product doctrine should frame the first wedge as interruption recovery rather than dashboard styling. | Product/source-of-truth boundary belongs in project doctrine. |
| 10 | `20260504_081842_26dc9c35` | `runtime_only` | **reclassified** → `repo_doctrine` | Nousromancer should orient, stage, expose evidence, and prepare actions; it should not become a governance layer or durable source of truth. | Product/source-of-truth boundary belongs in project doctrine. |

## Apply smoke

| Proposal | Target / probe | Mutation applied | Artifact / result |
|---|---|---:|---|
| `51a4e6345ecf4866b90cb414` | `skill_patch` | False | `docs/research/interflect/2026-05-05-full-loop-dogfood/apply-drafts/51a4e6345ecf4866b90cb414-skill_patch-athenwork-guidance-says-assistants-should-not-sc.md` |
| `6093067ce21056c15676a121` | `skill_patch` | False | `docs/research/interflect/2026-05-05-full-loop-dogfood/apply-drafts/6093067ce21056c15676a121-skill_patch-treat-leave-queued-as-no-repository-changes-no-b.md` |
| `b629017c4552dd5c563c01c5` | `skill_patch` | False | `docs/research/interflect/2026-05-05-full-loop-dogfood/apply-drafts/b629017c4552dd5c563c01c5-skill_patch-treat-beads-creation-success-separately-from-aut.md` |
| `cea1efa9589b4cae4c61eba8` | `skill_patch` | False | `docs/research/interflect/2026-05-05-full-loop-dogfood/apply-drafts/cea1efa9589b4cae4c61eba8-skill_patch-scheduled-check-should-be-a-bounded-read-only-he.md` |
| `3aec3825d72ae858d5659924` | `skill_patch` | False | `docs/research/interflect/2026-05-05-full-loop-dogfood/apply-drafts/3aec3825d72ae858d5659924-skill_patch-tracked-skill-edits-or-relevant-untracked-skill.md` |
| `4db01acce63144ee51a33511` | `skill_patch` | False | `docs/research/interflect/2026-05-05-full-loop-dogfood/apply-drafts/4db01acce63144ee51a33511-skill_patch-do-not-run-hermes-update-for-the-customized-amti.md` |
| `1675c51effc7143af788ffa6` | `beads_followup` | False | `docs/research/interflect/2026-05-05-full-loop-dogfood/apply-drafts/1675c51effc7143af788ffa6-beads_followup-closed-implementation-beads-with-untracked-revie.md` |
| `9c69166d0d5fd0ad62f10290` | `repo_doctrine` | False | `docs/research/interflect/2026-05-05-full-loop-dogfood/apply-drafts/9c69166d0d5fd0ad62f10290-repo_doctrine-nousromancer-product-doctrine-should-frame-the-f.md` |
| `654ef2ed08eef4d770879818` | `repo_doctrine` | False | `docs/research/interflect/2026-05-05-full-loop-dogfood/apply-drafts/654ef2ed08eef4d770879818-repo_doctrine-nousromancer-should-orient-stage-expose-evidence.md` |
| `c79298a327dff68a71ba677c` | refusal probe | rc=1 | proposal review_decision must be accepted or reclassified before apply |

All successful apply paths emitted draft artifacts or explicit-approval stubs only; `mutation_applied` remained `false`. The rejected runtime-only proposal refused apply with a non-zero exit and no draft artifact.

## Findings

1. **Extractor works for concise session-search exports, but depends on summary wording.** The fresh source export generated the candidate set from bounded records. This is enough for manual dogfood, but source quality still depends on upstream summaries containing explicit `should`/`use`/`boundary`/`follow-up` wording.
2. **Taxonomy is still conservative but under-detects operational procedures.** Several Athenwork/cron/button rules defaulted to `runtime_only` and were reclassified to `skill_patch`. That is a useful safe default, but it means review UX must make reclassification cheap.
3. **The review state and apply draft seam now works end-to-end.** Reviewed proposals produced patch artifacts, Beads follow-up drafts, or explicit-approval stubs. No memory, repo, Beads, skill, or routing mutation occurred automatically.
4. **Rejected/runtime-only protection works.** The refusal probe returned non-zero and no artifact for the port/runtime observation.

## Recommendation

Session-end/scheduled hooks are **not justified as automatic appliers** yet. They are justified only as **candidate-export producers** or **queued review reminders**. The next useful Interflect slice is tracked as `sylveste-l0zc.2` and should:

- export session_search/CASS summaries with raw handles and snippets,
- preview candidate count and likely target distribution,
- keep review/apply draft emission manual and explicit,
- add fixtures for operational-procedure wording (`Leave queued`, scheduled `Check`, Discord visibility boundary, customized Hermes update warnings).

## Alignment

Interflect remains proposal-first: extraction, cards, review state, and dry-run apply artifacts exist before any durable mutation.

## Conflict/Risk

The source export is derived from session-search summaries, not raw transcripts. It is adequate for dogfood, but future adapters should preserve stronger source spans and avoid over-relying on assistant-compressed summaries.
