# Brief: interstat one meter (goal 7be37994)

Contract: brief

## Objective

Make `tests/test_one_meter.py` pass in the interstat checkout at `/Users/sma/projects/Sylveste/interverse/interstat` without changing any test, while the rest of the suite stays green: give the estate path one lenient Claude-usage extractor, TTL-aware pricing, transcript-keyed rows with a per-(transcript, model, day) breakdown, a `--backfill` receipt, and reports that read the breakdown while still counting legacy rows.

## Scope

Files you may create or edit: `scripts/claude_usage.py` (new), `scripts/analyze.py`, `scripts/profile.py`, `scripts/cost.py`, `scripts/cost-query.sh`, `scripts/init-db.sh`, and a schema note in `CLAUDE.md`. Files you must not edit: `scripts/claude_attribution.py`, `scripts/task_attribution.py`, `scripts/codex_history.py`, anything under `tests/`. The acceptance is frozen at commit 2d04ca0; if a test looks wrong, stop and say so in the packet instead of changing it.

Design to follow (the tests pin the observable behaviour; read them first):

1. `scripts/claude_usage.py`: `iter_requests(path, *, content=None)` yields one dict per assistant response in file order, deduplicated by `message.id` (fallback: the entry `uuid`). Skip entries that are not type `assistant`, lack a usage dict, or carry `isApiErrorMessage`. Keys: `source_path` (str(path)), `session_id` (entry `sessionId`), `response_id`, `model` (`message.model` or `"unknown"`), `timestamp` (the first line seen for that response), `day` (`timestamp[:10]`), `is_sidechain` (bool of entry `isSidechain`), `agent_id`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens` (ints, lenient coercion, missing means 0), `context_tokens` (input + cache_read + cache_creation), `cache_creation_1h_tokens` and `cache_creation_5m_tokens` (ints read from `usage.cache_creation` through `claude_attribution.TTL_FIELDS` when both are ints and sum to `cache_creation_input_tokens`; otherwise both None), `pricing_unknowns` (a list: `cache_write_ttl_unreported` when the split is None and cache_creation_tokens > 0; `nonstandard_service_pricing` when `usage.speed` or `usage.service_tier` is set and not `standard`; `server_tool_charges_unpriced` when any `usage.server_tool_use` count is nonzero). Import `TTL_FIELDS` from `claude_attribution`; never copy it. Read the file in binary and json-decode only lines containing `b'"usage"'` so large transcripts stay fast.
2. `scripts/cost.py`: `calc_cost(row, pricing)` adds `(row.get("cache_creation_1h_tokens") or 0) * (2 * pricing["input"] - pricing["cache_create"]) * input_multiplier`; nothing else in the formula changes. On a record with no pricing unknowns this equals `claude_attribution.request_cost` (the agreement test).
3. Schema v7, idempotent, in both `scripts/init-db.sh` and `analyze.connect_db`: `ALTER TABLE agent_runs ADD COLUMN source_path TEXT`; `ALTER TABLE agent_runs ADD COLUMN pricing_unknowns TEXT`; `CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_runs_source_path ON agent_runs(source_path) WHERE source_path IS NOT NULL`; `CREATE TABLE IF NOT EXISTS agent_run_usage (run_id INTEGER NOT NULL, model TEXT NOT NULL, day TEXT NOT NULL, requests INTEGER NOT NULL, input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL, cache_read_tokens INTEGER NOT NULL, cache_creation_tokens INTEGER NOT NULL, cache_creation_1h_tokens INTEGER, api_equivalent_cost_usd REAL, PRIMARY KEY (run_id, model, day))`; `CREATE INDEX IF NOT EXISTS idx_aru_model_day ON agent_run_usage(model, day)`; `PRAGMA user_version = 7`.
4. `scripts/analyze.py`: `parse_jsonl` builds the run from `claude_usage.iter_requests`: whole-file totals as today (`total_tokens` = input + output), `model` = the model with the most output tokens ignoring `<synthetic>` unless it is the only one (ties go to the later-seen model), `api_equivalent_cost_usd` = the sum of per-request `calc_cost` (None if any request's model is unpriced), `timestamp` = the last yielded request's timestamp (fallbacks as today), `pricing_unknowns` = a JSON array of the sorted union across requests, `source_path`, and `usage_breakdown` = one entry per (model, day) with `requests`, the token sums, `cache_creation_1h_tokens` (sum of the known values, None when no request in the bucket has the split), and `api_equivalent_cost_usd` (sum, None if any request unpriced). A file with no requests is skipped. `upsert_agent_run` matches in this order: (a) `source_path = run.source_path`; (b) the oldest row (`ORDER BY id ASC`) with `session_id = run.session_id AND source_path IS NULL AND parsed_at IS NULL AND (subagent_type = run.agent_name OR agent_name = run.agent_name)`; (c) the oldest row with `session_id = run.session_id AND source_path IS NULL AND agent_name = run.agent_name`; else INSERT. On a match UPDATE timestamp, agent_name, the token columns, model, api_equivalent_cost_usd, pricing_unknowns, source_path, parsed_at, and never subagent_type, description, wall_clock_ms, result_length, bead_id, phase, invocation_id. Then `DELETE FROM agent_run_usage WHERE run_id = ?` and insert the breakdown rows. Add `--backfill`: implies `--force`, ingests every discovered transcript (still honouring `--session`), and prints exactly one JSON object on stdout as the last line with keys `rows_before`, `rows_after`, `transcripts_seen` (parsed candidates), `transcripts_stored` (runs written), `rows_without_source_path` (agent_runs rows with NULL source_path after the run), `rows_ttl_unreported` (rows whose pricing_unknowns contains `cache_write_ttl_unreported`). Ordinary runs print nothing on stdout; logging stays on stderr. Keep `--dry-run` working and keep the `source=` field in its output.
5. `scripts/profile.py`: `collect()` reads Claude files through `claude_usage.iter_requests` (keep the sub_file/isSidechain lane rule, the window filter on the record timestamp, and the session filter on `record["session_id"]`); pass `cache_creation_1h_tokens` into the record priced by `calc_cost` so 1h writes cost 2x; count `ttl_unreported_msgs` per (lane, model). `summarize(rows, completed_tasks)` adds `pricing_lower_bound`: True when any row has `ttl_unreported_msgs > 0`. `main()` carries `ttl_unreported_msgs` into rows and prints one lower-bound line in text mode. Codex handling is unchanged.
6. `cost.run_report` and `cost-query.sh` (`by-phase-model`, and `cost-usd` through `usd_cost_query`): aggregate from `agent_run_usage u JOIN agent_runs r ON r.id = u.run_id` for runs that have breakdown rows, UNION ALL the existing `agent_runs` aggregation restricted to `r.id NOT IN (SELECT run_id FROM agent_run_usage)`, so legacy rows still count. For breakdown rows: cost = SUM(u.api_equivalent_cost_usd) (NULL if any is NULL), runs = COUNT(DISTINCT u.run_id), tokens = input + output, the day window filters on `u.day` instead of `r.timestamp`, and lane, bead, phase, and session come from `r`. `cost.run_report` JSON adds `cost_estimate_lower_bound` (bool) and `ttl_unreported_rows` (count of agent_runs rows in the window whose pricing_unknowns contains `cache_write_ttl_unreported`); text mode prints one line about it. `by-phase-model` keeps its tokens > 0 filter. When `agent_run_usage` does not exist (an old database), fall back to today's queries.

## Constraints

No new dependencies; Python 3.10+. Keep the lenient handling of malformed lines (skip, never raise). Do not change any existing CLI except by adding `--backfill`. The 177 existing tests stay green. One commit on the current branch when everything passes; never push.

## Authority

You may create and edit the files listed in Scope, run the suite and the scripts against temporary databases, and make exactly one git commit with `git commit -F /private/tmp/claude-501/-Users-sma-projects/aa2bb078-ee16-4c32-9f97-01ef7dbdec61/scratchpad/msg-one-meter.txt -- <the paths you changed>`. You may not push, publish, touch `~/.claude/interstat/metrics.db`, or edit anything outside the interstat checkout.

## Acceptance Criteria

1. `uv run --with pytest --with pyyaml pytest -q tests/test_one_meter.py` reports 10 passed.
2. `uv run --with pytest --with pyyaml pytest -q` reports 187 passed.
3. `python3 -m py_compile` of the four Python scripts exits 0 and `bash -n` of the two shell scripts exits 0.
4. `git diff --stat 2d04ca0 -- scripts/claude_attribution.py scripts/task_attribution.py scripts/codex_history.py tests/` prints nothing.
5. The dry run over the fixtures prints 3 lines carrying `source=`.

## Verification

```bash
cd /Users/sma/projects/Sylveste/interverse/interstat
python3 -m py_compile scripts/claude_usage.py scripts/analyze.py scripts/profile.py scripts/cost.py
bash -n scripts/cost-query.sh
bash -n scripts/init-db.sh
uv run --with pytest --with pyyaml pytest -q tests/test_one_meter.py
uv run --with pytest --with pyyaml pytest -q
git diff --stat 2d04ca0 -- scripts/claude_attribution.py scripts/task_attribution.py scripts/codex_history.py tests/
python3 scripts/analyze.py --dry-run --force --conversations-dir tests/fixtures/one-meter/projects --db /tmp/one-meter-dryrun.db | grep -c 'source='
```

Expected: exit 0 on every line; the two pytest runs report 10 passed and 187 passed; the git diff prints nothing; the last command prints 3.

## Deliverables

A bounded packet: the commit hash; the files changed; each Verification command with its outcome; failures, if any, with the failing test name and why you believe the brief rather than the test is wrong; unresolved questions. Nothing else.
