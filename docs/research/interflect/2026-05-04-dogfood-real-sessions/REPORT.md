# Interflect v0 dogfood — real recent sessions

Bead: `sylveste-swkx` — Dogfood Interflect v0 on real recent sessions
Date: 2026-05-04
Scope: proposal-only dogfood against recent Hermes session-search summaries. No memory, canon, skill, Beads-follow-up, or routing mutation was auto-applied.

## Source set

Used 9 real source sessions from `session_search` summaries, with 15 bounded lesson candidates.

| Session | Handle class |
|---|---|
| `20260408_073431_99def2b6` | `session_search:20260408_073431_99def2b6` |
| `20260418_111909_5169e51b` | `session_search:20260418_111909_5169e51b` |
| `20260421_070330_6e2c31ce` | `session_search:20260421_070330_6e2c31ce` |
| `20260423_051132_f7316241` | `session_search:20260423_051132_f7316241` |
| `20260424_042407_512e2247` | `session_search:20260424_042407_512e2247` |
| `20260424_042427_feab7f2e` | `session_search:20260424_042427_feab7f2e` |
| `20260426_193852_803283ff` | `session_search:20260426_193852_803283ff` |
| `20260426_213100_61c67252` | `session_search:20260426_213100_61c67252` |
| `20260503_070215_236908cc` | `session_search:20260503_070215_236908cc` |

## Run artifacts

- Candidate input: `real-session-candidates.jsonl`
- Interflect v0 proposal queue: `proposals.jsonl`
- Rendered v0 cards: `review-cards.md`
- Human review outcomes: `review-outcomes.jsonl`
- Proposed deterministic fixture additions for taxonomy misses: `taxonomy-fixture-additions.jsonl`

CLI used:

```bash
PYTHONPATH=/home/mk/projects/interflect/src python3 -m interflect.cli analyze \
  --input-jsonl docs/research/interflect/2026-05-04-dogfood-real-sessions/real-session-candidates.jsonl \
  --store docs/research/interflect/2026-05-04-dogfood-real-sessions/proposals.jsonl \
  --cards > docs/research/interflect/2026-05-04-dogfood-real-sessions/review-cards.md
```

## Summary

- Candidates evaluated: **15**
- Decision counts: **accepted**=7, **reclassified**=7, **rejected**=1
- v0 target distribution: `beads_followup`=1, `memory`=2, `repo_doctrine`=2, `routing_signal`=6, `runtime_only`=3, `skill_patch`=1
- reviewed/final target distribution: `beads_followup`=1, `memory`=2, `repo_doctrine`=5, `routing_signal`=2, `runtime_only`=1, `skill_patch`=4

Interpretation: v0 is useful as a transparent first-pass queue, but current lexical priority is too eager to route anything mentioning `agent`, `routing`, `Claude Code`, or `Codex` into `routing_signal`, and too eager to classify any `identity` language as `memory` before checking project-boundary rules.

## Proposal review table

| # | Source session | v0 target | Decision / final target | Claim | Rationale |
|---:|---|---|---|---|---|
| 1 | `20260503_070215_236908cc` | `memory` | **reclassified** → `repo_doctrine` | Interflect is the active project identity, not Interspect. | Interflect/Interspect boundary is project doctrine/spec material; current memory hit came from overbroad "identity" rule. |
| 2 | `20260503_070215_236908cc` | `routing_signal` | **reclassified** → `repo_doctrine` | Interflect proposals must be reviewable before memory, canon, skill, Beads, or routing mutation. | Review-before-mutation is an Interflect doctrine guardrail; routing was triggered only because the claim mentioned routing. |
| 3 | `20260503_070215_236908cc` | `beads_followup` | **accepted** → `beads_followup` | Create a Beads follow-up for an Interflect session-source adapter if manual lesson extraction remains costly. | Concrete future implementation work belongs in Beads. |
| 4 | `20260408_073431_99def2b6` | `routing_signal` | **reclassified** → `repo_doctrine` | Ockham project doctrine should preserve policy/governance boundaries and avoid becoming a scheduler or monolithic orchestrator. | Ockham policy-vs-orchestrator boundary is repo/project doctrine, not merely routing. |
| 5 | `20260408_073431_99def2b6` | `routing_signal` | **accepted** → `routing_signal` | Route paid, public, or high-autonomy execution through explicit human approval gates before dispatch. | Approval gates affect dispatch/routing of costly or high-autonomy execution. |
| 6 | `20260408_073431_99def2b6` | `routing_signal` | **accepted** → `routing_signal` | Routing should consider Codex alongside Claude Code for design synthesis and implementation review instead of defaulting to Claude-only. | Claude/Codex body selection is a routing signal. |
| 7 | `20260426_213100_61c67252` | `repo_doctrine` | **accepted** → `repo_doctrine` | SCP repo doctrine should preserve the high-end domain-practice transformation boundary and avoid software-only or generic AI-workshop positioning. | SCP positioning boundary belongs in repo doctrine, not memory or runtime state. |
| 8 | `20260418_111909_5169e51b` | `memory` | **accepted** → `memory` | mk prefers the assistant to proceed without asking when the next step is obvious. | Stable collaboration preference about when to proceed belongs in compact user memory. |
| 9 | `20260418_111909_5169e51b` | `repo_doctrine` | **accepted** → `repo_doctrine` | Athenverse project doctrine should keep Athen* names for Hermes-specific adapters and preserve Interverse as canonical. | Athenverse naming/boundary doctrine belongs in project docs/canon. |
| 10 | `20260423_051132_f7316241` | `routing_signal` | **reclassified** → `skill_patch` | Use the Claude Code plus Oracle prereview procedure before opening or updating upstream PRs. | PR prereview is a reusable workflow procedure; Claude/Oracle terms caused over-routing. |
| 11 | `20260423_051132_f7316241` | `runtime_only` | **reclassified** → `skill_patch` | Patch Oracle review skills to avoid bare local-path references; embed prompt contents or use a wrapper that passes files correctly. | Oracle prompt/file handling is a reusable skill/runbook pitfall; classifier missed plural "skills" and "patch" phrasing. |
| 12 | `20260426_193852_803283ff` | `routing_signal` | **reclassified** → `memory` | General Systems Ventures is the broad umbrella; Sylveste is part of GSV; Interverse is the agent/Claude Code plugin layer. | GSV/Sylveste/Interverse scope is a stable ecosystem identity fact; "agent" caused false routing. |
| 13 | `20260424_042407_512e2247` | `skill_patch` | **accepted** → `skill_patch` | Treat Beads mutation success separately from auto-export or git-add warnings. | Beads warning interpretation is a reusable operational pitfall already suited to skill patching. |
| 14 | `20260421_070330_6e2c31ce` | `runtime_only` | **reclassified** → `skill_patch` | Patch review-planning skills to distinguish strong GO for bounded scope from broad safety clearance and conditional GO with declared blind spots. | Reviewer-verdict taxonomy is a reusable review-planning procedure; classifier missed "patch ... skills". |
| 15 | `20260424_042427_feab7f2e` | `runtime_only` | **rejected** → `runtime_only` | Port 3308 PID drift was observed during that specific t7x runtime check. | This is useful session context but should not be promoted as durable canon; keep only in the t7x artifact trail if needed. |

## Taxonomy misses and implementation notes

1. **Boundary-before-memory ordering.** `Interflect ... not Interspect` was classified as `memory` because `identity` matched before the Interflect/Interspect boundary rule. Put explicit project-boundary rules before broad memory terms.
2. **Routing terms are overbroad.** `agent`, `routing`, `Claude Code`, and `Codex` hijacked project doctrine, skill patch, and memory cases. Routing should require the claim to affect future body/model/tool selection, not merely mention an agent or model name.
3. **Skill-patch vocabulary is too narrow.** Add terms/patterns for `patch ... skill(s)`, `review skill`, `wrapper`, `Oracle review`, `prereview`, `workflow procedure`, and `taxonomy`.
4. **Project-doctrine vocabulary needs more named project boundaries.** Ockham policy-vs-orchestrator, SCP positioning, Athenverse/Interverse, and Interflect/Interspect should be covered by explicit boundary fixtures.
5. **Runtime-only behavior worked for true runtime state.** The t7x `port 3308 PID drift` item was correctly safe to reject as durable promotion.

The seven reclassified rows in `taxonomy-fixture-additions.jsonl` are the concrete regression fixture set for the next implementation slice.

## Recommendation for next Interflect bead

**Recommended next lane: review UX + taxonomy hardening before safe appliers.**

Reason: manual extraction is tolerable for this dogfood pass, but review produced six target corrections. A session-source adapter would increase candidate volume before the classifier/review loop can reliably capture corrections. Safe appliers are premature until review outcomes are stored as first-class training/eval data.

Concrete next bead candidate:

> Harden Interflect v0 taxonomy from real-session dogfood: add the six fixture rows, reorder boundary rules before broad memory/routing rules, add skill-patch vocabulary for review/prereview/wrapper/taxonomy cases, and persist review outcomes in the proposal queue or a sidecar review file.

## Alignment

Interflect remains proposal-first: it compounds lessons only after source handles, review cards, and explicit decisions exist.

## Conflict/Risk

Session-search summaries are source handles, not raw transcript exports. They are enough for bounded dogfood, but a future session-source adapter should preserve stronger transcript/CASS handles and snippets.
