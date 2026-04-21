---
title: Sylveste per-session cost breakdown
date: 2026-04-21
bead: sylveste-8lsf
epic: sylveste-1tbk
children_unblocked: sylveste-49kl, sylveste-ynh7
status: measurement-pass-complete
---

# Sylveste per-session cost breakdown

Measurement-only pass for the Sylveste perf + token-efficiency refactor epic (sylveste-1tbk). No code changes. Corpus is the last 100 agent-run sessions landing in `~/.claude/interstat/metrics.db` (window: 2026-04-11 → 2026-04-21, 56 nonzero sessions).

## Tooling state (what worked, what didn't)

| Instrument | Status | Notes |
|---|---|---|
| `cass analytics tokens --json --since=30d` | partial | Returns buckets but `api_coverage_pct=0` on most days — cache split unreliable through cass for this window |
| `cass analytics tools --json` | broken | Returns empty `tools` array despite 103K events in backing table |
| `cass analytics models --json` | works | Confirms claude traffic dominates; does not filter `--since` correctly |
| `interstat` CLI | missing | Package exists at `interverse/interstat/` but no shim on PATH; called Python against the sqlite db directly |
| `bash interverse/interstat/scripts/cost-query.sh baseline` | blocked | Needs `sqlite3` CLI which is not installed on this host — **baseline re-derivation deferred** (see Gaps) |
| Direct sqlite via Python on `metrics.db` | works | Source for every number in this doc |
| Session jsonl at `~/.claude/projects/-home-mk-projects-Sylveste/*.jsonl` | works | Used to factor on-wire preamble content |

## Baseline (stale, carried forward)

- **$2.93 / landable change** (2026-03-18, 785 sessions) — from `feedback_long_term_quality_default.md` / MEMORY.md.
- Fresh re-derivation requires `sqlite3` CLI + `ic landed summary`; neither runs cleanly on zklw as of today. Captured as Gap #1 below.
- This pass establishes a **parallel API-equivalent baseline** from `agent_runs` token data that the follow-on beads can move.

## Headline numbers (last 100 sessions, n=56 nonzero)

```
input (non-cached):      134,204  (0.01%)
output:                8,071,535  (0.51%)
cache_creation:       62,725,241  (3.99%)
cache_read:        1,500,091,488  (95.49%)
GRAND:             1,571,022,468
```

- **Cache hit rate: 96.0%** (`cr / (cr + cc)`) — the stable-prefix cache is already working.
- **Mean cache_read per session: 26.8M tokens.** With a ~60K-token preamble, that is consistent with **~450 assistant turns per session amortized**, i.e., the cached prefix is being re-read on every turn of every session and the turn count is the multiplier, not the hit rate.

### Per-session cost (API-equivalent, using actual model mix)

| Statistic | $ / session |
|---|---|
| mean | $40.09 |
| median | $0.033 |
| p90 | $158.68 |

### Cost concentration by model (same window)

| model | runs | cache_read | $ API-equiv |
|---|---:|---:|---:|
| `claude-opus-4-7` | 29 | 1,457,212,065 | **$3,851.81** |
| `claude-sonnet-4-6` | 15 | 22,093,748 | $16.56 |
| `claude-haiku-4-5-20251001` | 41 | 19,969,190 | $6.37 |
| `<synthetic>` | 38 | 816,485 | $0.00 |
| `unknown` | 107 | 0 | $0.00 |

> **99.4% of API-equivalent spend in this window comes from 29 Opus runs.** Haiku and Sonnet combined are under 0.6% of the dollars despite being 56× the runs. Every optimization should be scored against its impact on the long Opus session — that is where the money lives.

Subscription leverage: the $3,874 figure is API-list-equivalent, not out-of-pocket on Claude Max. Use it as a **relative** signal to compare optimizations; do not quote it as actual spend.

## Preamble factoring (directly measured from this session's jsonl)

The on-wire preamble sent on every turn was captured from `a910fc63-b3c0-4031-81ff-20fa71dbbc56.jsonl`, messages 0–20 (pre-first-assistant-reply):

| Slice | Bytes | Est tokens | Notes |
|---|---:|---:|---|
| **Skill listing** (attachment type `skill_listing`) | 39,436 | ~10,400 | 130+ skills, each with a full triggering description. Single biggest slice. |
| **Deferred tools delta** (220+ MCP + builtin names) | 17,184 | ~4,500 | Names only, no schemas — but volume is enough to matter |
| **SessionStart hook output** (beads + intermem + intership + session-id) | 8,515 | ~2,200 | Beads workflow context is the dominant sub-slice here |
| **Handoff user prompt** | 4,163 | ~1,100 | Task-specific, not optimizable |
| **Other system-reminders + file-history-snapshots** | 6,598 | ~1,700 | CLAUDE.md, MEMORY.md index, env, misc attachments |
| **MCP instructions delta** (`context7`, `qmd`) | 2,411 | ~600 | Two servers; grows linearly with enabled MCP count |
| **Subtotal (transcript-visible)** | **83,259** | **~21,900** | |
| Claude Code harness system prompt + active tool schemas (Bash, Read, Edit, Grep, Glob, Write, Agent, Skill, ScheduleWakeup, ToolSearch) | — | ~25–35K | Not in jsonl; estimated from tool-spec volume. Agent tool alone is ~15K due to inline subagent descriptions. |
| **Estimated total cached prefix** | | **~50–60K tokens** | |

Assistant-turn amortization check: 26.8M cache_read / 60K prefix ≈ 450 turns per session on average. This matches the cass analytics picture (2026-02-26 sample: 73K api_tokens/assistant_msg ≈ one full prefix + accumulated context per turn).

## Subagent fan-out

`tool_selection_events` last 30 days (full history, not just 100-session window):

| Tool | Calls |
|---|---:|
| Bash | 12,272 |
| Read | 8,226 |
| Edit | 2,612 |
| Grep | 2,134 |
| Glob | 1,201 |
| Write | 1,097 |
| **Agent** (subagent fan-out) | **591** |
| WebSearch | 425 |
| TaskUpdate | 403 |
| ToolSearch | 263 |
| Skill | 203 |
| TaskCreate | 203 |
| AskUserQuestion | 184 |
| MCP tools (all 220+ combined) | <500 |

**Subagent fan-out is not a top driver.** 591 `Agent` calls in 30 days is modest; each is an isolated context so they do not amplify the main-session prefix. Do not chase subagent compaction until the prefix and turn-count levers are addressed.

**MCP tools are barely used.** Under 500 total calls in 30 days across all 220+ registered MCP tools. The deferred-tools mechanism is doing its job (schemas live behind `ToolSearch`, not in the preamble) — the ~4.5K tokens of deferred-tool *names* remain as a lower-priority target.

## Repeated file reads / Grep/Read cycles

Cross-joining `agent_runs` and `tool_selection_events` on recent sessions returned zero rows — the two tables' session_ids for the last 100 agent-runs sessions have no overlap in the 30-day window. Likely an interstat ingest lag for tool events. **Repeated-read audit deferred** (Gap #2).

## Top 10 most expensive sessions (API-equivalent)

```
0fea947b  2026-04-17  opus+sonnet   cr=227,286,250  cc=9,300,625   $565.93
b8c3c8ae  2026-04-19  sonnet+haiku  cr=191,468,956  cc=4,475,271   $412.40
6dc4a9ed  2026-04-20  opus+haiku    cr=154,745,788  cc=7,149,684   $404.78
454cef90  2026-04-16  haiku+synth   cr=118,789,076  cc=3,709,191   $311.35
8de2734d  2026-04-20  opus          cr=118,329,621  cc=2,085,203   $250.51
a210ece1  2026-04-15  haiku+opus    cr= 62,401,618  cc=5,319,515   $241.29
398801ab  2026-04-19  haiku+opus    cr= 46,104,287  cc=5,876,378   $224.65
f50ae35d  2026-04-19  opus          cr= 75,514,613  cc=2,780,920   $201.90
31bf39f9  2026-04-21  opus          cr= 62,516,902  cc=2,823,905   $163.79
ce632633  2026-04-18  opus          cr= 64,382,069  cc=2,027,529   $158.68
```

All ten are multi-hour or multi-run Opus-touched sessions. The pattern is "long Opus stretch with accumulated context," not "many subagents fan out."

## Top 3 optimization targets

Each target below names a slice, an estimated saving, and a metric the follow-on bead should move.

### Target #1 — Compact the skill listing

- **Current**: 39,436 bytes / ~10,400 tokens, eagerly attached every session as `skill_listing`. Contains 130+ skills with full description paragraphs, most never invoked in any single session.
- **Proposal**: ship only a skill *index* (name + one-sentence purpose) and force full descriptions to arrive through `Skill` tool metadata or on first reference. Rough model: 130 entries × ~20 tokens ≈ 2.6K tokens for the index.
- **Expected saving**: ~7,800 tokens off the cached prefix → ~13% prefix reduction.
- **$ impact**: on a typical Opus-heavy session (26.8M cache_read), a 13% prefix cut drops cache_read by ~3.5M tokens ≈ **~$5.25 API-equivalent per expensive Opus session** at $1.50/Mtok.
- **Linked metric for sylveste-ynh7**: `skill_listing` attachment bytes per session (measure from jsonl). Target: **≤ 10 KB** (from 39 KB).

### Target #2 — Shrink the hidden system prompt, starting with the `Agent` tool spec

- **Current**: the `Agent` tool description inlines every subagent's trigger description. Crude count from the current session prompt suggests ~15K tokens — 25% of the full prefix — yet `Agent` saw only 591 calls in 30 days (1.5% of tool volume).
- **Proposal**: move subagent descriptions behind a lookup (same pattern as ToolSearch). Primary `Agent` schema keeps only general guidance + a compact `subagent_type` enum; descriptions fetched on first use.
- **Expected saving**: ~10K tokens off the cached prefix → another ~17% prefix reduction stacked on Target #1.
- **$ impact**: ~$6.75 per expensive Opus session at current cache_read levels. Combined with Target #1: ~**$12 / expensive session, ~30% prefix reduction, ~4% cost-per-landable-change reduction**.
- **Linked metric for sylveste-49kl**: estimated cached prefix tokens per session (computable as `(cache_read + cache_creation) / assistant_turn_count` once turn count is joined in). Target: **≤ 35K tokens** (from ~50–60K).

### Target #3 — Kill the unused SessionStart noise

- **Current**: 8.5 KB / ~2,200 tokens from four SessionStart hooks — beads workflow context (the bulk), intermem budget warning, intership spinner verbs, session id. The intership line ("253 spinner verbs loaded") is pure noise; the intermem warning is a one-line ask that expands into guidance every session. The beads block is useful but repeats across every session unchanged.
- **Proposal**: collapse the beads block to a 10-line "ran out of room — see AGENTS.md §beads" pointer; drop the intership verb announcement entirely; make intermem:tidy nudges conditional on the user opting in rather than top-of-session.
- **Expected saving**: ~1,500 tokens / session.
- **$ impact**: ~$1 per expensive Opus session, but — crucially — hits **every** session including the cheap Haiku runs, so the *aggregate* saving across the 56-session window is proportionally larger than Target #1 or #2.
- **Linked metric for sylveste-ynh7**: SessionStart hook output bytes. Target: **≤ 3 KB** (from 8.5 KB).

### Combined projection

| Lever | Prefix tokens saved | Prefix % cut | $ saved / expensive Opus session |
|---|---:|---:|---:|
| Target #1 (skill listing) | ~7,800 | ~13% | ~$5.25 |
| Target #2 (Agent schema + subagent descriptions) | ~10,000 | ~17% | ~$6.75 |
| Target #3 (SessionStart noise) | ~1,500 | ~2.5% | ~$1.00 |
| **Combined** | **~19,300** | **~32%** | **~$13 / expensive session** |

Against the stale $2.93/landable-change baseline, a 32% prefix cut weighted by the 95% cache_read share suggests **~9–13% cost-per-landable-change reduction — target $2.55–$2.66** once the follow-on beads land. This is a projection, not a promise — the follow-on beads must re-measure on identical corpus to claim savings.

## Bead framing notes for the follow-ons

- **sylveste-49kl "Prompt cache hit-rate audit: stabilize the session preamble"** — title is mis-framed. The cache hit rate is already **96%** and the preamble is already stable turn-to-turn; there is no instability problem. The real lever is **prefix size**. Suggested rewrite: "Shrink the cached session prefix from ~55K → ≤35K tokens." Keep sylveste-49kl for Targets #2 + #3 (harness-level shrink).
- **sylveste-ynh7 "Deferred-tool + skill-compact discipline audit"** — title lands. Assign Target #1 (skill listing compact) here, plus a sweep of the deferred-tools delta (~4.5K tokens of names alone) to see if install-profile filtering can trim the name list for sessions that do not need every MCP.

## Gaps / follow-ups worth beading

1. **Re-derive $/landable-change baseline.** Requires `sqlite3` CLI and `ic landed summary` to run cleanly. The stale $2.93 figure is now 34 days old across two interstat pricing updates (costs.yaml v0.2.27) and two model-mix shifts. File a small bead: "install sqlite3 on zklw + re-run `cost-query.sh baseline` and update MEMORY.md."
2. **Repeated-read audit.** `agent_runs` ↔ `tool_selection_events` join returns zero overlap for the last 100 sessions — interstat ingest is dropping tool events or binding them to a different session_id shape. File a small bead: "diagnose interstat tool_selection_events session_id join gap."
3. **`cass analytics tools`** returns an empty array against a populated backing table. Likely schema drift after the 0.2.0 bump. File upstream with cass.
4. **MEMORY.md budget**: the intermem hook already flags "129 / 120 lines." Left to /intermem:tidy; not a top-3 target at ~3K tokens.
5. **/compact discipline**: accumulated context (not prefix) is the other half of the cache_read multiplier. Once Targets #1–#3 land, the next lever is probably "compact after N turns" — but measure first before building.

## Sources

- `~/.claude/interstat/metrics.db` (agent_runs, tool_selection_events)
- `~/.claude/projects/-home-mk-projects-Sylveste/*.jsonl` (session transcripts)
- `core/intercore/config/costs.yaml` (pricing, via published rates at time of writing)
- `interverse/interstat/scripts/cost-query.sh` (blocked — see Gap #1)
- MEMORY.md topic files: [2026-03-08] CASS is the session intelligence backend; [2026-03-18] cost baseline.

---

## Post-implementation update (sylveste-ynh7) — 2026-04-21

Skill-listing compact + deferred-tool trim pass landed.

- Target-metric savings: **−8,684 bytes / −2,285 tokens per session**
  - `skill_listing`: 39,436 → 34,879 (−1,199 tok)
  - `deferred_tools_delta`: 17,184 → 13,752 (−903 tok)
  - `mcp_instructions_delta`: 2,411 → 1,716 (−183 tok)
- Bead acceptance floor (≥ 2,000 tokens) met. TIER: ACCEPTABLE.
- Total preamble grew (+5,239 bytes) on out-of-scope attachments:
  SessionStart hooks (+647 tok), async_hook_response (+738 tok), a new
  `command_permissions` harness attachment (+107 tok), and a
  measurement artifact from the `/clavain:route` skill body inlined
  into the user-prompt portion. SessionStart + async-hook bloat
  deserves its own bead.
- Full results: [docs/research/2026-04-21-sylveste-ynh7-results.md](./2026-04-21-sylveste-ynh7-results.md)

Gap #1 (cost-query.sh dependency on missing `subagent_type` column)
unaffected by this pass.
