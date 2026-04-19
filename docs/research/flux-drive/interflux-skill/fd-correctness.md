### Findings Index
- P0 | C1 | "phases/launch.md Step 2.3" | Retry loop can race with orphaned background Task producing duplicate `.md` files
- P1 | C2 | "phases/launch.md Step 2.1c / phases/synthesize.md Step 3.7" | Temp file lifetime race: cleanup runs after synthesis, but retries at Step 2.3 may still be reading — ordering fragile
- P1 | C3 | "phases/reaction.md Step 2.5.2b" | Fixative computation is declared sequential but depends on findings files whose writes are concurrent — no barrier enforced beyond file existence
- P1 | C4 | "phases/expansion.md Step 2.2a.5" | AgentDropout computes redundancy on Stage 1 findings before validating Findings Index shape — malformed outputs silently poison dropout scoring
- P1 | C5 | "phases/synthesize.md Step 3.4c" | SQLite `UPDATE ... ORDER BY created_at DESC LIMIT 1` with no transaction can update the wrong agent_run if multiple sessions overlap
- P2 | C6 | "phases/expansion.md Step 2.2c / tier_cap" | `tier_cap[agent]` global dict mutates during downgrade cap restoration — re-applying domain intersection check can flip decisions non-deterministically
- P2 | C7 | "phases/reaction.md Step 2.5.0" | Fail-open on `intercept not installed` is explicit; fail-open on `intercept installed but crashed` is silent — no failure-mode distinction
- P2 | C8 | "phases/launch.md Step 2.3" | Usage Policy refusal detection uses `tail -c 500` on a JSONL stream — the refusal text could legally span message boundaries and be split mid-string
- P2 | C9 | "phases/synthesize.md Step 3.4c" | `find /tmp/claude-*/` glob depends on the user's uid directory; if multiple Claude sessions run concurrently, the find can match the wrong session's tasks
- P2 | C10 | "phases/launch.md Step 2.0 / OUTPUT_DIR isolation" | `find -delete` on `.md.partial` races with slow agents when `--output-dir` is passed; even with timestamp default, Oracle's 1800s timeout can outlast a subsequent run if the user re-invokes with the same fixed path
Verdict: needs-changes

### Summary

Invariants to hold: (1) each dispatched agent produces exactly one `.md` output file, (2) peer-findings writes are append-only and atomic, (3) synthesis reads a stable view of findings, (4) token counts are recorded against the correct agent_run. Each invariant has at least one correctness gap. The dispatch-retry-synthesize pipeline has several soft races around file lifetime and concurrent completion, and the reaction round's fixative gate depends on a sequencing constraint that isn't actually enforced by any code path — it's declared as "MUST complete before Step 2.5.3 begins" in prose. Several SQL updates and temp-file cleanups assume single-session exclusivity that isn't guaranteed when users run parallel flux-drive invocations.

### Issues Found

1. C1. P0: Retry race on `.md.partial` → `.md` rename. `phases/launch.md` Step 2.3 states: "For `.md.partial` only (incomplete): retry once with `run_in_background: false`, timeout 300000ms. Pre-retry guard: skip if `.md` exists." The guard is "skip if `.md` exists" — but the original background Task can complete between the guard check and the retry launch, or (worse) the retry can finish first and the original later renames `.md.partial` to `.md`, overwriting the retry's output with the original's findings (or producing a `.md` that is stale while a second rename silently completes). Failure narrative: Stage 1 launches fd-safety in background; timeout fires at 300s; orchestrator reads `fd-safety.md.partial` still exists, no `fd-safety.md`; orchestrator retries synchronously; retry completes in 120s and writes `fd-safety.md`; meanwhile, the original background job (still running) finally finishes at 320s and renames its `.md.partial` over the retry's `.md`. Now the output file belongs to the original run (which the orchestrator concluded had timed out). Fix: kill the original Task before retrying, or move the retry's output to `.retry.md.partial` and atomically rename with a collision-detection check.

2. C2. P1: Temp file cleanup ordering is prose-declared, not enforced. `phases/synthesize.md` Step 3.7 notes "This cleanup runs after synthesis, not before — agents may still be reading temp files during retry (Step 2.3)." But Step 2.3 retry can run before synthesis's "validate all agents completed" check. If an agent fails and is retried by the synthesis subagent (or by Step 2.3's retry logic), a temp file rm can happen underneath a still-reading retry. The prose declares the constraint but no code-level guard (like a lockfile, or a `trap` in the shell script) enforces it. Fix: either delete temp files as part of each successful agent finalize (the agent removes its own file after reading), or use a lockfile at `/tmp/flux-drive-${INPUT_STEM}-${TS}.lock` that cleanup waits on.

3. C3. P1: Fixative sequencing barrier is prose. `phases/reaction.md` L67-68 says "Step 2.5.2b MUST complete before Step 2.5.3 begins — do not parallelize. Fixative context depends on the complete findings set and Gini/novelty computation." The orchestrator is instructed to honor this, but the reaction round dispatches agents with `run_in_background: true` and waits on them (Step 2.5.4). The scan that reads findings for Gini/novelty (Step 2.5.2b) runs before Step 2.5.3 (sanitization), which runs before Step 2.5.4 (dispatch). That's fine — but the finding set being scanned is the outputs from Phase 2, not Phase 2.5. The constraint is really "Phase 2 must be fully complete before Phase 2.5.2b starts". That's enforced by the Phase 2 monitor completing before Phase 2.5 begins. The prose is imprecise about which barrier matters. Fix: reword to "Phase 2 must complete before Step 2.5.2b", which is the real invariant.

4. C4. P1: AgentDropout trusts Stage 1 findings without structural validation. `phases/expansion.md` Step 2.2a.5 computes `stage1_domains = set of domains that produced P0/P1 findings in Stage 1` and `adjacent_finding_count = count of P0+P1 findings from agents adjacent to this agent`. If a Stage 1 agent produced a malformed Findings Index (missing Verdict line, or invalid SEVERITY token), the orchestrator's Findings Index parse silently treats it as "no findings". That inflates redundancy scores for agents who should expand (their neighbors appear to have "covered" nothing). Fix: require Findings Index structural validation (Step 3.1 rules) before computing dropout; agents with "error" verdict should be treated as "no coverage" — which is what happens, but malformed outputs could be treated as "clean" when they should be "unknown".

5. C5. P1: UPDATE ... ORDER BY ... LIMIT 1 race. `phases/synthesize.md` Step 3.4c issues per-agent:
   ```sql
   UPDATE agent_runs SET total_tokens=... WHERE agent_name='interflux:$agent_name'
     AND total_tokens IS NULL ORDER BY created_at DESC LIMIT 1;
   ```
   If another session is running the same agent (fd-safety is a common cross-project agent) and its `agent_runs` row has `total_tokens IS NULL`, this UPDATE can target the wrong session's row. There's no `session_id` clause. Fix: scope by session_id, which is known at synthesis time. The prior query at L220-230 already shows session_id scoping; the update at L324-325 drops it.

6. C6. P2: `tier_cap[agent]` mutation during downgrade restoration. `phases/expansion.md` Step 2.2c § Downgrade cap (L263-273): "After restoring each agent, reapply: (1) Domain intersection tier_cap check (may re-cap to haiku) (2) safety floor (non-negotiable)". But `tier_cap[agent]` was computed earlier in "Domain intersection validation" based on initial expansion candidates. When an agent is restored to its original model, reapplying `tier_cap` may re-cap it to haiku, which is below its original model. The restoration logic promises "restore to original model" but the subsequent reapply can override that. Two passes are capped at 2 to prevent oscillation — but the oscillation is still possible within the 2 passes when restoration happens mid-pool. Fix: compute `tier_cap` once on the final adjusted pool, not iteratively.

7. C7. P2: Silent fail-open paths lose evidence. `phases/reaction.md` Step 2.5.0c says "If `intercept` is not installed, fall back to `PROCEED` (fail-open)." That's an explicit fail-open. But if `intercept` crashes mid-decision (non-zero exit with garbage stdout), the `$(intercept decide ...)` captures garbage and the `if` comparison falls through to the `else` (PROCEED). Only the explicit-absence case is documented. Fix: after `$(intercept decide ...)`, validate the output is `SKIP` or `PROCEED`; else log an error stub and fall-open with an explicit reason.

8. C8. P2: Refusal detection tail-c boundary. `phases/launch.md` Step 2.3 detects the Usage Policy refusal with:
   ```bash
   last_text=$(jq -r ... | tail -c 500)
   ```
   The refusal text "API Error: Claude Code is unable to respond to this request, which appears to violate our Usage Policy" is ~110 chars. 500 chars is ample margin in most cases. But `jq` outputs text messages concatenated with newlines; the refusal text is split across message content blocks in Anthropic's transcript format (role=assistant with multiple content array items). Doing `tail -c 500` on the concatenation could cut the refusal string if the last assistant message is a short acknowledgment and the refusal is earlier. Fix: grep over the full jq output (streaming) or anchor on the last assistant message's `.text` field.

9. C9. P2: `find /tmp/claude-*/` on parallel session correctness. `phases/synthesize.md` Step 3.4c:
   ```bash
   jsonl_path=$(find /tmp/claude-*/  -name "${agent_id}.output" -type l 2>/dev/null | head -1)
   ```
   Multiple concurrent flux-drive runs (or other Claude sessions) will have their own `/tmp/claude-<uid>/` directories. `agent_id` is unique per session (that's how the harness works), so `head -1` should be fine in the happy case — but if two sessions dispatch the same agent within the same second, there's a theoretical race. More importantly, the `2>/dev/null` swallows permission errors (other users' `/tmp/claude-*/` dirs that appear in the glob but are mode 700). Fix: scope to `/tmp/claude-$(id -u)/` which is the session-owner's directory.

10. C10. P2: Stale Oracle output contaminates a fixed OUTPUT_DIR. SKILL.md L83-92 explains that timestamped OUTPUT_DIR exists to prevent cross-run contamination: "a still-writing agent's `.partial` gets deleted, but when it renames to `.md`, the file reappears — contaminating the new run's synthesis". The suggested clean approach for `--output-dir`: `rm -f *.md *.md.partial peer-findings.jsonl`. But Oracle's internal timeout is 1800s (30min); a user invoking flux-drive with `--output-dir` twice in succession can trigger the same race inside 30 minutes. The "clean" variant deletes mid-run. Fix: when `--output-dir` is passed, abort if any `.md.partial` is still being written, or use process-group-based locking.

### Improvements

1. IMP-1. Define the agent-completion state machine explicitly. States: `dispatched`, `writing`, `completed`, `failed`, `retried`, `timeout_original_still_running`. Transitions make the race hazards visible. Currently the state machine is encoded across Step 2.3 retry logic, the `.md.partial` → `.md` rename convention, and the synthesis validation in Step 3.1 — no single place captures it.

2. IMP-2. Move all SQLite UPDATEs into a single script `scripts/record-agent-tokens.py` that takes a session_id and a list of agent results, and does the update inside a transaction. Inline SQL in prose orchestration instructions is a correctness hazard.

3. IMP-3. Replace the prose "MUST complete before" constraints with a concrete barrier. E.g., Phase 2.5.2b could be gated by the existence of a marker file `{OUTPUT_DIR}/.phase2-complete` written at the end of Phase 2. Barrier files are cheap and checkable.

4. IMP-4. Consider switching temp files from `/tmp/flux-drive-${INPUT_STEM}-${TS}*` to `$(mktemp -d)` which is race-safe by construction and lets cleanup be a single `rm -rf $tempdir`.

5. IMP-5. Add a Findings Index grammar definition in `shared-contracts.md`. A single regex `^-\s+(P[0-3]|BLOCKING|NOTABLE)\s+\|\s+[A-Z]+\d+\s+\|\s+"[^"]+"\s+\|\s+.+$` plus a `Verdict: (safe|needs-changes|risky|error)$` line would let synthesis validate with `grep -E` before committing to a parser.

<!-- flux-drive:complete -->
