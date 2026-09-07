---
artifact_type: research
bead: sylveste-ynh7
depends_on: sylveste-8lsf
baseline_ref: docs/research/2026-04-21-preamble-baseline.json
post_ref: /tmp/post.json (ephemeral)
date: 2026-04-21
---

# sylveste-ynh7 Results — Preamble Token-Efficiency Pass

## Summary

Target-metric savings hit the bead's acceptance floor.

- **skill_listing + deferred_tools + mcp_instructions**: **−8,684 bytes / ≈ −2,285 tokens per session**
- Bead acceptance: `tool-schema token count reduced by >= 2000 tokens per session` → **PASS**
- **TIER: ACCEPTABLE** — bead closes as complete.

Total preamble grew (+5,239 bytes) due to out-of-scope SessionStart hook bloat, a new `command_permissions` harness attachment, and a measurement artifact from the route command used to resume this session. See §Caveats.

## Baseline session (pre-change)

Source: `docs/research/2026-04-21-preamble-baseline.json`
Session: `a910fc63-b3c0-4031-81ff-20fa71dbbc56`

| attachment type              | bytes  |
|------------------------------|--------|
| skill_listing                | 39,436 |
| deferred_tools_delta         | 17,184 |
| hook_success/SessionStart    | 14,109 |
| mcp_instructions_delta       |  2,411 |
| async_hook_response          |  2,064 |
| hook_additional_context      |  1,518 |
| (other / user-prompt body)   |  6,537 |
| **total**                    | **83,259** |

## Post-change session

Source: `/tmp/post.json`
Session: `73c86818-b7a9-4221-a416-b2fead6e5462`

| attachment type              | bytes  |
|------------------------------|--------|
| skill_listing                | 34,879 |
| hook_success/SessionStart    | 16,566 |
| deferred_tools_delta         | 13,752 |
| async_hook_response          |  4,869 |
| mcp_instructions_delta       |  1,716 |
| hook_additional_context      |  1,518 |
| command_permissions (new)    |    407 |
| (other / user-prompt body)   | 14,791 |
| **total**                    | **88,498** |

## Delta (post − pre)

| metric                         |      pre |     post |   Δ bytes | Δ tokens (÷3.8) |
|--------------------------------|---------:|---------:|----------:|----------------:|
| skill_listing_bytes            |   39,436 |   34,879 |    −4,557 |          −1,199 |
| deferred_tools_delta_bytes     |   17,184 |   13,752 |    −3,432 |            −903 |
| mcp_instructions_bytes         |    2,411 |    1,716 |      −695 |            −183 |
| **target-metric subtotal**     | **59,031** | **50,347** | **−8,684** | **−2,285** |
| sessionstart_bytes             |   14,109 |   16,566 |    +2,457 |            +647 |
| async_hook_response (est.)     |    2,064 |    4,869 |    +2,805 |            +738 |
| command_permissions (new)      |        0 |      407 |      +407 |            +107 |
| user-prompt body (measurement noise) | 6,537 | 14,791 | +8,254 |          +2,172 |
| **total_preamble_bytes**       | **83,259** | **88,498** | **+5,239** | **+1,379** |

## Tier verdict

Using the metric aligned with bead acceptance (target-metric subtotal, not total_preamble_bytes):

- `saved_tokens = 2,285`
- **TIER: ACCEPTABLE** — ≥ 2,000 token floor hit.

Note: the plan's Step 4 tier block computes tier over `total_preamble_bytes`, which misreports in this run. The bead description's acceptance language ("tool-schema token count reduced by >= 2000 tokens") refers to target metrics; I scored against that. The plan also had a branch-ordering bug in its tier ladder (`>=500` before `>=1200`), noted in the prior handoff.

## What shipped this bead

### Plugins disabled (deferred-tool reduction)

Per `scripts/perf/apply-plugin-disables.sh`, low-use MCP plugins moved to on-demand fetch:
- intermap, intercache (subset), interlens (subset)

Recovered via `ToolSearch` when genuinely needed.

### Sylveste skills trimmed (skill_listing reduction)

Across 9 Sylveste-owned plugins, skill descriptions were run through `/clavain:distill` and trimmed to the 40-char floor where safe, preserving ≥ 60 % trigger-vocab survival (enforced by `scripts/perf/extract-trigger-vocab.py`):

| plugin       | version bump | notes |
|--------------|--------------|-------|
| intermonk    | 0.1.1 → 0.1.2 | clean |
| interhelm    | 0.2.0 → 0.2.2 | upstream unset + external stash |
| intersearch  | 0.2.1 → 0.2.2 | stale-lock clear + uv.lock stash |
| interscribe  | 0.1.1 → 0.1.2 | clean |
| interlab     | 0.4.7 → 0.4.8 | clean |
| intercraft   | 0.1.2 → 0.1.3 | clean |
| interfluence | 0.2.10 → 0.2.11 | plugin-local stale lock cleared |
| interdoc     | 5.2.1 → 5.2.2 | stale-lock clear |
| intertest    | 0.1.2 → 0.1.3 | clean |

All 9 cached at `~/.claude/plugins/cache/interagency-marketplace/<plugin>/<version>/` and spot-verified (see post-txky handoff).

## Caveats: where the +5,239 total-preamble regression comes from

This is **not** from bead work; each piece traced:

1. **SessionStart hooks (+2,457 bytes / +647 tok)** — own-fleet hook output grew. Five hooks now chain (interkasten, intermem, intertrack, intership, beads). Already close to intermem's 120-line budget. File as follow-up.
2. **async_hook_response (+2,805 bytes)** — increased asynchronous hook chatter. Co-rooted with #1.
3. **command_permissions (+407 bytes)** — new attachment type emitted by the harness; not under Sylveste control.
4. **user-prompt body (+8,254 bytes)** — measurement artifact. The baseline session started from a direct `/clear` with no slash-command preamble. This session started `/clear` → `/resume` (failed, bead id contained a space) → `/clavain:route sylveste-ynh7 Task 6` — and the route skill body (~14 KB of markdown) gets inlined into the user-prompt portion before the first assistant message, inflating `total_preamble_bytes`. Rerunning measurement from a cold `/clear` without a preceding slash-command would eliminate this. Not a regression the bead caused.

Items #1–#2 are real and deserve a follow-up bead; items #3–#4 are noise.

## Stopping rule

Not triggered. Target-metric tier is ACCEPTABLE on the first pass, so no retries required.

## Follow-ups

- **New bead (suggested):** "SessionStart hook-output budget + async_hook_response audit." SessionStart is now ≈ 647 tokens per session and growing; compounds across every fresh session. Owner: same area as sylveste-8lsf.
- **Plan cleanup:** the branch-order bug in Task 6 Step 4 tier ladder (noted in post-txky handoff) remains unfixed in the plan doc. Low priority — plan is archival after bead close, but worth correcting if the plan is reused as a template.
- **Measurement hygiene:** `measure-preamble.sh` could exclude user-prompt body from `total_preamble_bytes` or emit it as a separate field, to make apples-to-apples totals robust to different session-start routings.

## Files

- Pre: `docs/research/2026-04-21-preamble-baseline.json`
- Post: `/tmp/post.json` (ephemeral — regenerate via `scripts/perf/measure-preamble.sh --session-id=<sid>`)
- Script: `scripts/perf/measure-preamble.sh`
- Plan: `docs/plans/2026-04-21-sylveste-ynh7-skill-listing-compact.md`
- Findings origin: `docs/research/2026-04-21-sylveste-cost-breakdown.md` (to be updated in Task 7)
