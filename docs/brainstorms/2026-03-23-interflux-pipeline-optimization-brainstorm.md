---
artifact_type: brainstorm
bead: Demarch-z5qg
stage: discover
---

# Interflux Pipeline Optimization: Scoring, Slicing, Latency, Budget

## What We're Building

Improvements to the flux-drive multi-agent review pipeline across 4 axes: triage scoring accuracy, content slicing precision, dispatch latency, and token budget accountability. Source: 5-agent review (fd-triage-scoring-fidelity, fd-content-slicing-precision, fd-dispatch-pipeline-latency, fd-agentdropout-and-expansion, fd-token-budget-accounting) producing 17 findings.

## Why This Matters

The flux-drive pipeline is the core review/research engine for all Demarch sprints. Every sprint runs it at least twice (plan review + quality gates). Inefficiencies compound across every sprint:
- **Token waste:** Bonus inflation means nearly every agent scores above threshold — the scoring system doesn't discriminate in mature projects
- **Latency:** 4-8.5 minutes of avoidable wall-clock time per review (Stage 1→2 barrier + polling)
- **Blind budgeting:** Token data is never recorded, so all cost decisions are based on hardcoded guesses
- **Safety gaps:** fd-safety patterns miss common auth paths; zero-priority-skip silently drops user-confirmed agents

## Key Findings by Axis

### Scoring (5 findings)
1. **P0: Pre-filter false negatives** — fd-correctness keyword set too narrow (misses state, validation, algorithm, schema)
2. **P1: Domain boost degenerate** — all profiles have exactly 5 bullets per agent → +1 tier never triggers, boost is binary +0/+2
3. **P1: base_score=1 waste** — tangential agents inflated to score 4 via bonuses, burn ~40K tokens with no survival-rate tracking
4. **P1: Slot ceiling inflation** — `generated_slots: +2` expands pool to 11/12 instead of making generated agents compete on score
5. **P1: Selection threshold meaningless** — score>=2 provides zero discrimination after bonus inflation in mature projects

### Slicing (4 findings)
6. **P0: Zero-priority-skip contract violation** — silently drops user-confirmed agents when slicing finds no priority sections
7. **P1: fd-safety patterns incomplete** — miss oauth/sso/webhook/token/keys directories and package manager credential files
8. **P1: Heading keywords incomplete** — fd-safety misses encryption/compliance/threat; fd-correctness misses idempotency/retry/error; fd-performance misses database/pool
9. **P1: Body sampling truncated** — only checks first 50 lines, misses conclusions and summaries

### Latency (2 findings)
10. **P1: Stage 1→2 full barrier** — 3-6 minutes of idle time; incremental/speculative Stage 2 dispatch possible
11. **P1: 30s polling interval** — 1-2.5 minutes of dead time; reduce to 5s or use inotifywait

### Budget (2 findings)
12. **P0: Token data never recorded** — interstat has NULL tokens for all 106 agent runs; entire budget system is inert
13. **P0: Namespace mismatch** — estimate-costs.sh looks up `fd-architecture` but interstat stores `interflux:fd-architecture`

### Dropout (2 findings)
14. **P1: Threshold unvalidated** — lowered 0.7→0.6 based on token savings alone, no recall-loss measurement
15. **P1: Project agents invisible** — flux-gen agents absent from adjacency map, can't be dropped or expanded

## Scoping for This Sprint

**Must-fix (P0, 4 items):** Pre-filter false negatives, zero-priority-skip, token data recording, namespace mismatch
**High-value quick wins (3 items):** Remove generated_slots, reduce polling to 5s, expand fd-safety patterns
**Deferred to iteration 2:** Stage 1→2 incremental dispatch (architectural), base_score=1 survival tracking (needs data from P0-1 fix first), dropout threshold validation (needs data)

## Open Questions

1. **Token recording mechanism:** Session JSONL parsing at SessionEnd vs agent self-reporting? JSONL parsing is more reliable but requires post-processing. Self-reporting is real-time but requires protocol changes.
2. **Selection threshold fix:** Raise to score>=3 for profiled projects, or apply threshold to base_score only? The latter is more targeted but changes the scoring semantics.
3. **Zero-priority-skip fix:** Full-document fallback (safe but expensive) or send priority-less agent a document abstract only (cheaper but may miss issues)?

## Research Sources

5 custom review agents generated via `/flux-gen` from prompt mode, each focused on a distinct optimization axis. Full findings in agent output files.
