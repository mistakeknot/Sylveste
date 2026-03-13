---
artifact_type: cuj
journey: interspect-agent-learning
actor: regular user (developer tuning agent performance)
criticality: p2
bead: Demarch-2c7
---

# Interspect Agent Learning and Calibration

## Why This Journey Matters

Multi-agent systems produce varying quality. One review agent consistently catches real bugs. Another produces 80% false positives. A dispatch agent works great for Go code but struggles with Rust. Without measurement, these differences are invisible — the developer treats all agents equally and wonders why quality is inconsistent.

Interspect is the profiler and learning system for Demarch's agent fleet. It tracks which agents produce findings that are acted upon, which get dismissed, which dispatches succeed, and which fail. Over time, this evidence feeds into routing decisions: better agents get more work, worse agents get downweighted or excluded from triage.

This journey covers how the developer observes, understands, and tunes agent performance — the meta-level of "how well are my tools working?"

## The Journey

The developer notices that flux-drive reviews have been noisy lately — too many nitpick findings, not enough actionable ones. They run `/interspect:interspect-status` to see the fleet overview: session counts, evidence records, and per-agent summary stats.

For deeper analysis, `/interspect:interspect-evidence fd-quality` shows the detailed evidence for a specific agent: how many reviews, what percentage of findings were acted upon vs dismissed, false positive rate, common finding categories. The developer sees: "fd-quality: 45 reviews, 30% act-upon rate, 70% dismiss rate. Top dismissed: 'consider adding docstrings' (18 times)."

That's the signal. The developer records a correction: `/interspect:interspect-correction fd-quality "docstring suggestions are noise — we don't add docstrings to code we didn't change per CLAUDE.md"`. Interspect records this as negative evidence weighted against docstring-type findings from fd-quality.

For routing optimization, `/interspect:interspect-propose` analyzes evidence patterns and suggests routing overrides: "fd-safety has 95% act-upon rate for auth-related changes. Propose: always include fd-safety when files matching 'auth/*' change." The developer approves with `/interspect:interspect-approve`.

Conversely, if an agent is consistently poor: `/interspect:interspect-override fd-game-design "not relevant — this isn't a game project"` excludes it from triage for this project. If the developer changes their mind: `/interspect:interspect-unblock fd-game-design`.

Calibration runs periodically: `/interspect:calibrate` computes agent scores and delegation stats from accumulated evidence. The output shows pass rates, defect escape rates, and cost efficiency per agent. This data feeds into Mycroft's dispatch decisions (which agent to assign a bead to) and flux-drive's triage scoring (which review agents to include).

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Agent performance data accumulates automatically | measurable | Evidence records grow with each review/dispatch |
| High-performing agents get higher triage scores | measurable | Act-upon rate correlates with triage priority |
| Corrections reduce specific false positive patterns | measurable | Correction for "docstring" findings reduces their frequency |
| Routing overrides take effect immediately | measurable | Approved override visible in next flux-drive run |
| Calibration produces actionable agent rankings | measurable | Score output distinguishes top from bottom performers |
| Developer can diagnose "why is review noisy?" from Interspect alone | qualitative | Status + evidence + correction flow answers the question |

## Known Friction Points

- **Evidence collection is passive** — Interspect only knows about findings that go through flux-drive or quality gates. Direct agent interactions (manual subagent calls) aren't tracked.
- **Correction is manual** — the developer must notice and report false positive patterns. No automatic false-positive detection.
- **Cold start for new agents** — a newly generated project agent has no evidence. It takes 5-10 reviews before Interspect has meaningful data.
- **Cross-project learning doesn't exist** — an agent's performance in one project doesn't inform its treatment in another. Each project starts fresh.
- **Score computation is batch** — `/calibrate` must be run manually. Scores don't update in real-time after each review.
