---
date: 2026-04-09
session: ece9b344
topic: Auraken discrimination curriculum
beads: [sylveste-uais, sylveste-bt82, sylveste-jkkn, sylveste-794i, sylveste-ex7j, sylveste-t021, sylveste-1t3u]
---

## Session Handoff — 2026-04-09 Auraken discrimination curriculum

### Directive
> Your job is to implement the DQ correctness judge (sylveste-794i epic). `/route sylveste-794i` to start.
- Epic sylveste-794i — open, 3 children: ex7j (F1 judge), t021 (F2 wire into agent.py), 1t3u (F3 wrong-answer friction)
- Dependency chain: ex7j → t021 → 1t3u (sequential)
- F1 spec is in `apps/Auraken/docs/specs/conversation-integration-wax-and-gold.md` section 4 "Correctness signal"
- Pattern to follow: `select_lenses()` in `apps/Auraken/src/auraken/lenses.py:268` — same Haiku subprocess call via `claude -p`
- F2 needs session metadata flag ("DQ was presented last turn") — check `apps/Auraken/src/auraken/agent.py:428-454` curriculum hook
- The curriculum hook presents DQs but never records resolutions yet — tracker stays at easy tier forever

### Dead Ends
- Plan rev 1 used wrong JSON key (`"top_pairs"` vs `"pairs"`) and wrong field name (`"frequency"` vs `"co_occurrence_count"`) for near_miss_analysis.json — caught in 4-agent plan review
- Plan rev 1 annotated `_near_miss_dq` on select_lenses() output but prompts.py never reads it — moved to agent.py post-selection
- Hard tier was structurally empty in rev 1 — all high-frequency pairs were stress-tested (routed through stress branch first). Fixed by classifying mixed RESOLVED/PARTIAL as hard

### Context
- Auraken Go migration is underway — new curriculum modules (discrimination.py, curriculum.py, lens_stacks.py) are Python, bead filed for Go port
- `DiscriminationEvent` table uses append-only pattern (like ProfileEpisode), NOT JSONB on CoreProfile — this was a P1 from plan review
- Sentence splitting in restructure_holdings.py uses regex `(?<=[a-z])\.\s+(?=[A-Z])` to avoid corrupting "vs." — naive `.split(".")` breaks 2 DQs
- conftest.py uses `importlib.util.spec_from_file_location` to import build_difficulty_ladder.py from data/calibration/ — no sys.path hack
- Difficulty ladder distribution: 15 easy / 11 medium / 4 hard (from 30 pairs)
- Tier-to-depth mapping: easy→wax, medium→shallow_gold, hard→deep_gold
- GDPR: discrimination_events covered in /deleteall (telegram.py) and retention.py (user_answer redaction)
