---
artifact_type: reflection
bead: sylveste-nfqo
stage: reflect
---

# intermute: live tmux transport — sprint reflection

## What shipped

A focus-state-aware live delivery path for intermute. Two concurrent Claude Code sessions on the same host can now signal each other directly — via tmux pane injection when the recipient is at-prompt, via a durable-queue-plus-hook surface when the recipient is busy. The manual workaround demonstrated earlier on 2026-04-19 (sylveste-myyw.7 ↔ sylveste-qdqr) is now formalized: policy-gated, rate-limited, audit-recorded, prompt-injection-hardened, and controllable via a single feature flag. Local-only in v1; cross-host deferred.

Code state at sprint close: 2 Codex commits already landed (hooks + docs) on main, 20 modified + 11 new files staged for the remaining 13 tasks, all tests green (default + `tmux_integration`), `go vet` clean, `go build` clean. Plan and reviews ship alongside the code under `docs/`.

## What worked

1. **Plan review paid for itself twice.** The 4-agent pre-execution review surfaced 4 P0 + 11 P1 issues. Every one of those findings either prevented a ship-blocker or saved hours of per-task rework. The `storage.Store`-interface-extension-as-prerequisite-Task-0 insight alone would have caused 14 cascading compile failures otherwise. Running the same 4 agents post-execution as the quality-gate confirmed 5 more plan-drifts that the plan had called for but execution had not honored — plan-drift checking is the highest-value signal a post-review gate can produce.

2. **Type-alias migration for boundary refactors.** `type Target = core.WindowTarget` let the `livetransport` package move its concrete type to `core` without breaking the 14 existing call sites in tests and the injector itself. Same pattern will be useful the next time a package boundary needs to shift mid-sprint.

3. **Atomic multi-event commit via `AppendEvents`.** Collapsing the three peer-event types (injected / failed / deferred) into one `EventPeerWindowPoke{result}` and making `AppendEvents(ctx, ev...)` the single transactional entry point eliminated an entire class of crash-window bugs by construction. The correctness P0-1 about orphan staging simply stopped being possible — not "guarded against" but "not representable."

4. **Session-only tmux target in ValidateTarget.** The integration-test failure revealed that `tmux has-session -t session:0.0` rejects pane specs, and that many tmux configs set `base-index 1`. Validating the session portion only and letting `paste-buffer` surface pane-level errors naturally is portable across configs and eliminates the config-divergence class of test failures.

## What broke / cost us time

1. **Codex sandbox had no `go` on PATH** — every task's validator subphase reported "go: command not found" and emitted WARN. The tasks *wrote* correct code but the orchestrator's verdict output made it look like 9/15 tasks failed. Debugging burned ~15 min before I realized the code was right; tests passed when run directly with `PATH=/usr/local/go/bin:$PATH`. Dispatch.sh should inject `go` into the sandbox PATH, or the verdict reporter should distinguish "could not validate" from "validation failed."

2. **Model routing defaulted to `-xhigh` variants** that 400 on the ChatGPT-account Codex auth. Dispatch.sh silently swallowed the 400s. First orchestrator run emitted "15/15 skipped (task-0 failed)" with no visible error. Root-cause-finding required `codex exec -m gpt-5.3-codex-spark-xhigh "hi"` directly. Routing now defaults to `gpt-5.4` across all tiers (memory saved). Dispatch.sh failure-to-surface-model-errors is a dispatch-side bug worth a follow-up bead.

3. **Execution plan-drift in two places.** Even with explicit plan guidance ("handleSendMessage should be ~30-50 lines", "internal/http must not import internal/livetransport concretely"), Codex shipped a 180-line handler and 3 concrete livetransport imports. The fixes were mechanical (~30 min) but the drift itself is informative: the plan's *structural* requirements need automated checks (e.g., a linter that fails CI when `internal/http` imports `internal/livetransport` outside the interface binding). Plan prose doesn't enforce structure.

4. **WARN verdicts hid real failures in the aggregate summary.** Because orchestrate.py reports "Passed: 15, Failed/Skipped: 0" when all tasks were WARN, I almost advanced to Step 6 (Test & Verify) before noticing. The orchestrator should distinguish PASS from WARN in its summary stats, not just in per-task output.

## What I would do differently next time

- **Wire build-env checks into dispatch.sh preflight** — `command -v go` (or language-appropriate equivalent) per task file extension. Fail fast with a clear message if the sandbox can't compile the language the task targets.
- **Add import-graph assertions as a sprint-level verification step** — specifically for plans that declare package-boundary constraints. One-line `go list -deps` check between Step 5 (Execute) and Step 6 (Test) would have caught plan-drift P0-1 before Step 7.
- **Write the `fakeTmux` mutex requirement as a comment in the plan** instead of leaving it to discover via `go test -race`. The plan asked for `t.Parallel()` safety but didn't specify the implementation; Codex initially shipped without the mutex, then I patched it. A one-line example would have prevented the back-and-forth.

## Key technical decisions preserved

- `type TransportMode string` (named, not alias) — compile-time protection at call sites.
- `StalenessFocusThreshold = 2 * time.Second` enforced inside storage, not at every caller.
- `INSERT OR IGNORE` (not REPLACE) on `pending_pokes` — retry-safe, no ghost redelivery.
- `sanitizeBody` escapes `---` lines + strips C0 controls — envelope marker collision + bracketed-paste escape both closed.
- Single `rateLimiter` primitive with `allow(key)` — broadcast and live limiters share one implementation, key composition in wrapper helpers on Service.
- Feature flag (`config.live_transport_enabled`) read per-request, no in-process cache — runtime rollback without binary redeploy.

## Follow-ups (file as beads before close)

1. **dispatch.sh model-error surfacing** — 400 responses from codex-exec should propagate as a task verdict with the error message, not silently succeed with 0 tokens.
2. **dispatch.sh build-env preflight** — detect language from task file list, verify compiler/runtime on PATH before dispatching.
3. **Plan import-graph assertion** — add a verify step that lints declared package-boundary constraints from the plan.
4. **orchestrate.py summary clarity** — distinguish PASS / WARN / FAIL in the final counts.
5. **Active-probe readiness pattern (v1.5)** — the `echo INTERMUTE-PROBE-<nonce>` + capture-pane verification, documented in `live-transport.md` as residual risk. Useful when 2s staleness proves insufficient.
6. **Cross-host transport (v2)** — SSH + tmux orchestration via Skaffen; noted in plan follow-ups.

## Cost / scope notes

Plan was 2,564 lines post-review. 15 tasks dispatched across 8 waves with max parallelism 4. Codex ran 15 tasks to completion (minus verification step). Post-Codex fix-up for 3 P0 + 7 P1 quality-gate findings took ~45 minutes of direct editing plus continuous test-re-runs. Total wall-clock from brainstorm start to quality-gates-pass was ~5 hours across brainstorm/plan/review/execute/quality/resolve — within the range I'd estimate for a C3 feature of this surface area. The delta vs a pure-Claude subagent execution would have been more Claude tokens but probably similar wall clock and fewer plan-drifts.
