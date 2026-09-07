# Autonomous roadmap and backlog maintenance

Date: 2026-09-07. Bead: `sylveste-7jj5`. Status: implementation charter; scheduled reprioritization is not yet enabled.

The principal requested a refreshed Sylveste roadmap and backlog, then a token-efficient
scheduled Codex or Hermes workflow. The principal selected **full reprioritization**:
strategic order and Beads priorities may change autonomously when evidence supports
it. This is planning authority. It does not approve experiments, accept product
changes, promote models, or grant implementation, push, deployment, or release
powers to an experiment executor.

## Decision and alternatives

| Option | Operation | Cost and tradeoff |
|---|---|---|
| Conservative | Interwatch detects drift; Interpath refreshes factual projections; humans rank work | Zero model cost for generation, but priorities can remain stale |
| Selected | Remontoire judges meaningful changes through its existing Codex harness; deterministic adapters validate and apply planning deltas | Reuses the installed server timer and state mechanisms; requires a separate maintenance action and publication contract |
| Aggressive | A Hermes gateway with event watchers continuously revisits portfolio changes | Fresh isolated cron sessions are supported, but this proposal adds another runtime, scheduler, and failure surface before demonstrating added value |

Remontoire owns portfolio attention and is the right owner for the selected option.
Interwatch supplies drift signals; Beads owns tasks and dependencies; Interpath owns
rendering; Intercore owns durable decisions and receipts; Ockham owns policy.
A separate trusted publisher may commit only the authorized planning artifacts.
Remontoire's existing one-experiment cycle and production landing boundary remain intact.

Codex desktop automations are an alternative for a Mac-only pilot, but local tasks
need the computer awake and the app running. The already-running zklw systemd timer
avoids making canonical portfolio upkeep depend on the Mac app. Hermes cron requires
its gateway to be running; adopting it solely for a second scheduler has no established
benefit. [Hermes cron documentation](https://hermes-agent.nousresearch.com/docs/user-guide/features/cron/). [Codex automation documentation](https://learn.chatgpt.com/docs/automations?surface=app).

## Bounded scheduled cycle

1. **Observe without a model.** Acquire a portfolio maintenance lock. Read a complete
   Beads snapshot from the configured Sylveste root, declared strategy/policy hashes,
   new accepted receipts, relevant producer heads, and previous publication state.
   Validate portfolio identity, duplicate IDs, dependencies, and source availability.
   Failed reads are unavailable evidence, never an empty backlog.
2. **Compute a semantic delta.** Sort records and exclude generation timestamps,
   display order, and the maintenance bot's bookkeeping. If unchanged, make zero
   model calls and preserve artifact bytes. A once-weekly aging boundary can trigger
   reconsideration without pretending new delivery evidence exists.
3. **Orient with a small packet.** Include changed issues, direct blockers, current
   six outcomes, and a bounded rotating slice of older work. Start with at most
   24 KiB of input, 8 KiB of structured output, one call per daily cycle, and a
   five-minute wall limit. These are proposed operational bounds, not token quotas.
   Carry an explicit coverage list; incomplete selection must not masquerade as a
   whole-backlog assessment. Across weekly cycles, every eligible item gets a turn.
4. **Judge once in a fresh context.** Invoke the existing Codex transport with an
   explicit binary, model, effort, schema, read-only sandbox, and curated evidence.
   No ambient extensions or persistent chat history. Begin with the already-approved
   model policy. Benchmark `high` against `xhigh` on the same frozen packets before
   changing the scheduled effort policy; savings are a hypothesis, not a guarantee.
5. **Validate a planning delta.** Require issue IDs, prior values, proposed priority,
   evidence references, rationale, and ordered outcomes. Unknown IDs, omitted evidence,
   invalid priorities, contradictory changes, and invented acceptance claims fail.
   Full reprioritization includes strategic order; it does not invent completed work
   or infer human acceptance. Bulk deletion, mass closure, and new implementation
   dispatch are outside this action. New work is deduplicated before creating a Bead.
6. **Persist before applying.** Store the immutable decision, source hashes, usage,
   attempt identity, and before-values in Intercore. Beads remains the sole task store.
   Re-read affected records before mutation. The installed `bd update` has no atomic
   expected-version flag: a read-then-write check alone is not a concurrency guarantee.
   Implement a supported transactional compare-and-set or an enforced writer contract
   before enabling unattended priority writes. Preserve a pending decision on failure.
7. **Render and publish.** Interpath generates JSON and Markdown from one frozen
   post-decision snapshot. A separate publisher stages only `docs/roadmap.json`,
   `docs/backlog.md`, and approved strategic roadmap paths in an isolated clean main
   checkout. Verify expected base commit, file hashes, regular paths, tests, and review
   disposition; never force-push or stage unrelated files. Advance the publication
   cursor only after successful push. Retry publication from the stored decision,
   without paying for another judgment or repeating already-applied task mutations.
8. **Reflect and compound.** Record model calls, actual reported usage and its coverage,
   failures, stale decisions, reversals, and subsequent corrections. Keep unchanged
   ticks quiet; surface an actionable exception or a short change digest. Do not send
   external messages without specific authorization.

## Implementation sequence and dependencies

| Slice | Producer / existing task | Acceptance |
|---|---|---|
| Factual generation | Interpath; current refresh | Complete snapshot validation, frozen input, stable no-op, two-output validation, wrong-root rejection |
| Tracker continuity | `sylveste-bkrh` | Supported cross-host sync preserves all histories and later edits; matching authorized records on both hosts |
| Backlog binding | Remontoire | Optional `backlog_dir` separates Beads from `project_dir` kernel/policy; preserve historical cycle recovery |
| Decision action | Remontoire + Intercore + Ockham | Strict schema, declared authority, real usage receipts, unchanged input makes zero model calls, concurrent updates safe |
| Publication | Sylveste trusted adapter | Allowlisted files, review and fresh base checks, resumable push, exact cursor semantics |
| Scheduled canary | Existing systemd infrastructure | One live bounded assessment, one unchanged tick, one conflict and failed-push recovery; then enable maintenance schedule |

Do not fold this into an ordinary proposal cycle: that cycle is allowed one bounded
experiment and has different approval and mutation semantics. Keep installed configuration
fixed during paired context experiments; activate changes between recorded boundaries.

## Present evidence and unresolved limits

- Before this refresh, published roadmap JSON and backlog were last generated on 2026-08-08; the strategic
  roadmap was dated 2026-07-11 and v1 roadmap 2026-04-27.
- The server portfolio config pointed Beads at `~/projects` (61 nonclosed Shadow Work
  and Revel issues), while Sylveste's tracker had 512 nonclosed issues before this
  refresh. Kernel/policy state must stay at its existing root.
- Mac and zklw tracker snapshots differ. A native GitHub Dolt pull timed out; no history
  was reset. A native server backup was verified first. The existing reconciliation
  task remains open. Only the three named current delivery objectives missing on zklw
  were imported under their original IDs for this refresh.
- The generator now fails on missing tools or invalid snapshots, preserves both old
  outputs when rendering fails, and retains identical bytes/mtimes on unchanged input.
  The two file replacements are individually atomic; a Git publication commit supplies
  the pair boundary. Generation is not independent task acceptance.
- Remontoire already runs scheduled proposal cycles. Autonomous strategic rewriting,
  transactional priority updates, and an allowlisted publisher still require the
  implementation slices above; this charter does not claim they are installed.

## Token savings to measure in the next goal

Prioritize deterministic no-op ticks and small evidence packets before changing models.
Use compact skills and bounded tool output, cache source hashes, fetch only changed
material, batch independent reads, and dispatch reviews with precise files and criteria.
Keep fresh task contexts when they retain the relevant evidence; escalate effort for
ambiguous cross-repository decisions instead of using maximum effort on every check.
Measure total usage per independently accepted change, including failures and repair,
not tokens per successful model reply. Human intervention minutes require an explicit
estimate. Neither elapsed time nor a lower reasoning setting proves savings.

**Alignment:** improves correct portfolio attention and evidence per unit of cost using
existing owners and durable mechanisms.
**Conflict/Risk:** unattended planning can oscillate or overwrite concurrent intent;
control it with recorded deltas, real concurrency enforcement, bounded changes, replay,
and revocable planning authority.
