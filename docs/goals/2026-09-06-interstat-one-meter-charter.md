# interstat one meter: the estate path prices what happened

Approved by mk on 2026-09-06 (plan `quizzical-discovering-dragonfly.md`) after a review of what landed between the Astra review of the meter goal and 2026-09-06. The condition file beside this charter carries the goal-shaped rendering and the amendment recorded at mint.

## Why

Two meters now live in interstat. The strict one (`claude_attribution.py`, `task_attribution.py`, sibling session 01a0742a, 2026-09-06) is manifest-driven, evidence-preserving, and reads the explicit cache-write TTL; nothing on the estate path uses it. The estate meter (SessionEnd → `analyze.py` → `agent_runs` → `cost-query.sh`; `profile.py`) still folds a transcript into one row with one model, matches rows by session plus agent name so same-named subagent files overwrite each other, prices every cache write at the 5m rate, and windows by the row's last timestamp. Sylveste-balk and Sylveste-4yb3 describe those defects and are untouched since 2026-09-03. The Astra canary (Sylveste-kbh5) reports absolute main-integrator cost per completed task; its Claude-side baseline runs through the defective path. The four routing goals' measured sections in `commands/model-routing.md` were taken with the old meter.

## Scope

In:
- `scripts/claude_usage.py` (new): one lenient per-request extractor for Claude transcripts. Yields one record per assistant response (deduped by `message.id`, falling back to `uuid`), with model, timestamp, normalized usage, `cache_creation_1h_tokens` and `cache_creation_5m_tokens` from the explicit split (None when absent), `pricing_unknowns`, sidechain flag, and the source path. Tolerates missing `apiBlockIndex` and `requestId`. Reuses `claude_attribution.TTL_FIELDS` and `VERIFIED_STANDARD_CONTEXT` by import.
- `scripts/cost.py`: `calc_cost` prices a 1h write at 2x input when `cache_creation_1h_tokens` is on the row; rows without the split price at the 5m rate and are reported as lower bounds. Reports move their by-model, by-lane, and by-day aggregation to the breakdown table.
- `scripts/analyze.py`: consumes `claude_usage`; schema v7 adds `agent_runs.source_path`, `agent_runs.pricing_unknowns`, and `agent_run_usage(run_id, model, day, requests, input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens, cache_creation_1h_tokens, api_equivalent_cost_usd)`. Upsert keys on `source_path`; a transcript with no row claims the oldest unparsed hook row for its session and subagent type, else inserts. `agent_runs` totals stay the whole-file totals so `total_tokens` per run and the interband budget path do not move. `--backfill` re-ingests every transcript that has a row without `source_path` and prints a coverage receipt (rows before, rows after, transcripts without a row, rows without a transcript).
- `scripts/profile.py`: consumes `claude_usage` for Claude files; Codex handling unchanged.
- `scripts/cost-query.sh`: `by-phase-model`, `cost-usd`, and `shadow-by-model` read the breakdown table.
- `scripts/init-db.sh`: v7 migration.
- `tests/fixtures/one-meter/` and `tests/test_one_meter.py`: the frozen fixtures and expectations; the agreement test against `parse_claude`/`request_cost`; the idempotence test; the pre-fix failure recorded with the commit it failed on.
- `docs/research/2026-09-06-one-meter-historical-manifest.md`: session ids, windows, exclusions, resumed/duplicate instances for goals 1b53da77, c60de386, c4cda02c, ff7fd1a1; before/after/delta from the corrected meter.
- Clavain `commands/model-routing.md`: the three measured sections corrected, old numbers kept and labelled superseded.
- interstat published from zklw, refreshed here, content-diffed; the live database backfilled with the receipt journaled; sessions still running the old plugin listed with their rows re-ingested or named.

Out: the sibling's two modules and their semantics; manifests and canary enrollment; Sylveste-koeo; Pattern F hardening beyond a compile step before spawn; calibration and quarantine policy; Sylveste-yibw.15, Sylveste-at90, Sylveste-55bc; effort tuning; share gates; A:L3.

## Gates

1. Ownership: balk and 4yb3 claimed, a note on Sylveste-yibw naming this goal and its files, before the first edit. The two sibling modules are imported, never edited.
2. Acceptance frozen before spawn: fixtures, expectations, manifest, pricing assumptions, verification commands committed first.
3. Every executor plan compiles its assembled post-edit Python before spawn; gauge-lint alone is not sufficient.
4. Executors and validators resolve through the contracts on disk at mint (routine-execution → gpt-5.6-sol, validation on a different model); any fixed-model trial is declared as an override.
5. Every attempt, refusal, retry, and verdict in the register with `--db` explicit and read back. Absolutes per attempt; no share-based claim; no predetermined pass count.

## Amendment recorded at mint (2026-09-06, before any edit)

The OUTCOME's first clause named `claude_attribution.parse_claude` as the extractor for the estate path. Measured before minting: `parse_claude` marks every request without `apiBlockIndex` invalid, and a survey of all 4,062 transcripts under `~/.claude/projects` found that field in 0 of 270,000 assistant messages before September 2026 and in 41,886 of 52,864 in September (it appeared with a Claude Code release around 2026-09-05). On a 59 MB transcript from 2026-09-04 the strict parser returned 0 requests and 7,035 `invalid_usage` issues. The explicit 1h/5m cache-write split, by contrast, is present in 100% of assistant messages in every month surveyed.

So "one usage extraction" is delivered as: one shared lenient extractor for the estate path (`scripts/claude_usage.py`, consumed by both `analyze.py` and `profile.py`, which today scan transcripts separately and disagree on dedupe and sidechain handling), one TTL pricing rule in `cost.py`, and a checked-in agreement test that, on a fixture the strict parser accepts, the lenient extractor's per-request tokens equal `parse_claude`'s and `cost.py`'s price equals `request_cost`. The sibling's files stay untouched. "Mark a missing split as a pricing gap rather than pricing it silently" is read as: price the write at the 5m rate as a lower bound and carry `cache_write_ttl_unreported` on the row, never a silent full price. The rest of the goal is unchanged.

## Interpretations recorded at mint

- "one usage extraction": see the amendment in the condition file. The estate extractor is lenient by necessity; agreement with the strict parser is pinned by test on inputs both accept.
- "pricing gap": a row whose writes lack the TTL split is priced at the 5m rate and carries `cache_write_ttl_unreported`; reports show the count of such rows and label the total a lower bound when any exist.
- "run counts unchanged": one row per transcript stays the unit; the backfill adds rows for transcripts that never reached one and the receipt says how many.
- "keyed by source_path": absolute path of the transcript file as written by Claude Code; a moved corpus is a new corpus.
- "before/after/delta": the same manifest windows priced by the installed 0.3.5 parser and by the corrected one, side by side, per goal.
- Preflight done before mint: the stray untracked `.beads` store at the interstat root held 0 issues and was removed; the `uv.lock` drift is a version bump to 0.3.5 and is committed with the first change; the suite is green under `uv run --with pytest --with pyyaml pytest`.

## Completion condition

See the condition file. Or stop after 12 turns.

## Close (2026-09-06)

DONE WHEN met: balk and 4yb3 closed against interstat fb398b6 and 3a315df (0.3.6 published from zklw, refreshed here, content-diffed); fixtures and the historical manifest in the interstat repo with before/after/delta; the three measured sections in `commands/model-routing.md` corrected with the old tables labelled superseded (one conclusion changed: pilot G was 53% of cost, not 47%); the live database backfilled with a coverage receipt (11,962 → 13,883 rows, 3,850 runs with breakdowns) and one SessionEnd ingestion reconciled against `profile.py` exactly; old-writer sessions counted (16) with the re-ingest path named. GATE held; the amendment recorded at mint governed the mechanism. Executor strike 1; validator strike 1 on criteria but its seat could not execute (Sylveste-soj7), so the executed replay is the orchestrator's. Five second-channel defects fixed on the main thread under rule 4 with tests; three residuals in Sylveste-y8xx. Turn budget overrun: about 22 tool-bearing turns against 12.

## Successor obligations

Sylveste-soj7 (the validation seat must run the Verification block or refuse to emit a verdict); a linter `--apply` mode so exact contracts are applied and replayed by tool; Sylveste-y8xx residuals (mixed-database window semantics, silent malformed-line drops, JSON rounding, the PostToolUse init-db re-run, hook rows with no transcript); a second `analyze.py --backfill` once the 16 pre-refresh sessions have ended; Clavain republish carrying f48fd65 whenever the measured-delivery lane's work is released.
