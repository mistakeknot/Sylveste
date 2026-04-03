### Findings Index
- P1 | DGC-01 | "Dispatch integration via weight multipliers" | Stale authority grants persist through `ic state` eventual consistency
- P1 | DGC-02 | "Split evidence/policy ownership" | No conflict resolution when Ockham and interspect disagree on agent reliability
- P2 | DGC-03 | "Dispatch integration via weight multipliers" | Dispatch weights have undefined consistency model and unbounded convergence time
- P2 | DGC-04 | "Safety invariants" | Action-time validation relies on a read from `ic state` that can return stale data
- P3 | DGC-05 | "Four subsystems" | No quorum or cross-subsystem agreement required for authority decisions

Verdict: needs-changes

### Summary

The vision describes a system where Ockham writes policy state (weights, authority grants) to `ic state`, and Clavain reads it during dispatch. This is a single-writer/single-reader architecture with no coordination protocol between the writer and reader. The split evidence/policy ownership between interspect and Ockham creates a second consistency boundary: interspect's `agent_reliability()` is consumed asynchronously by Ockham, meaning authority decisions can be based on stale evidence. The most concerning gap is that authority revocation flows through the same `ic state` channel as weight updates, with no fencing or monotonic version guarantees, so a revoked grant could be read as still-active if the revocation write hasn't propagated.

### Issues Found

1. **P1 | DGC-01 | Stale authority grant after revocation (split-brain between write and read)**

   The brainstorm (Section 2, line 53) specifies that Ockham writes weights via `ic state set "ockham_weight" <bead_id>`, and lib-dispatch.sh reads them in `dispatch_rescore()`. But `ic state` is backed by intercore state, which is a key-value store with no transactional guarantees across keys. If Ockham revokes a domain grant (setting `authority_grant=revoked` for agent X in domain Y) and simultaneously adjusts the dispatch weight, there is no atomic operation that ensures both writes are visible to Clavain at the same time.

   **Failure scenario:** Ockham detects a quarantine pattern and simultaneously (a) revokes agent X's authority for `core/*` and (b) zeroes the dispatch weight for beads tagged to agent X in that domain. If the weight write lands first but the authority revocation is delayed (even by one dispatch cycle), agent X could claim a bead in `core/*` at weight 0 but with the old authority grant still visible. Safety invariant 3 ("action-time validation") is supposed to catch this, but the brainstorm does not specify where action-time validation reads authority from, or whether it uses the same `ic state` channel subject to the same staleness.

   **Fix:** Define a monotonic version number on authority state. The dispatch reader must see an authority version >= the version at which the weight was written. This can be as simple as Ockham writing `ockham_authority_version` alongside `ockham_weight`, and lib-dispatch.sh refusing to dispatch if the authority version it reads is older than the weight's declared version.

2. **P1 | DGC-02 | No conflict resolution between interspect evidence and Ockham policy**

   Section "Split evidence/policy ownership" (line 28-32) defines the interface as `interspect exposes agent_reliability(agent, domain) -> {hit_rate, sessions, confidence, last_active}`. Ockham consumes this to make promotion/demotion decisions. But the brainstorm does not define what happens when:
   - Interspect's confidence band is wide (few sessions) but Ockham has already promoted the agent based on earlier data
   - Interspect retroactively corrects a hit_rate (e.g., a bead thought to be first_attempt_pass is later quarantined during review)
   - The principal manually overrides an authority tier that contradicts interspect evidence

   **Failure scenario:** Interspect recalculates hit_rate after a delayed quarantine. The rate drops below the demotion threshold. Meanwhile, Ockham last read the old rate and the agent is dispatching at autonomous level. The next Ockham evaluation cycle demotes the agent, but between the evidence update and the policy update, 3-4 beads are dispatched at the wrong tier.

   **Fix:** Ockham should subscribe to interspect evidence changes (event-driven, not polling) or at minimum define a maximum staleness window for evidence reads, documented in the vision as a design parameter.

3. **P2 | DGC-03 | Undefined consistency model for dispatch weights**

   The brainstorm says lib-dispatch.sh reads `ockham_weight` "after lane-pause check, before perturbation" (line 53-54). Looking at the actual `dispatch_rescore()` in `os/Clavain/hooks/lib-dispatch.sh:133-218`, there is no read of `ockham_weight` today -- it is listed as the "single missing wire." The brainstorm does not specify whether this read should happen once per dispatch cycle (batch consistency), once per bead evaluation (per-item freshness), or cached with a TTL.

   **Consequence:** If weights are read per-bead in a single dispatch cycle, an Ockham write mid-cycle could cause the first 5 beads to be scored with old weights and the last 5 with new weights, producing an inconsistent ordering within a single dispatch decision.

   **Fix:** Specify in the vision that Ockham weights are snapshot-read once at the start of each `dispatch_rescore()` invocation and applied uniformly to all candidates in that cycle.

4. **P2 | DGC-04 | Action-time validation depends on the same stale channel**

   Safety invariant 3 (line 82) says "Authority is checked at execution time, not just claim time." But if execution-time validation reads authority from the same `ic state` / `bd set-state` that Ockham writes to, it inherits the same staleness window. The invariant is only as strong as the consistency of its data source.

   **Fix:** The vision should specify that action-time validation reads authority from a source with at-least-as-fresh guarantees as the revocation write. If Ockham revokes via `ic state set`, the validator must read from the same store with a read-after-write guarantee (same process) or use a different synchronization mechanism (e.g., file-based with fsync).

5. **P3 | DGC-05 | Single-authority decisions with no quorum**

   All four subsystems (intent, authority, anomaly, dispatch) are single-writer. There is no quorum or cross-subsystem agreement for any decision. This is fine for a single-factory deployment, but open question 4 (line 101) asks about multi-factory federation. In a federated model, single-writer authority becomes a coordination problem.

   **Improvement:** Not actionable for Wave 1, but the vision should note that authority state is designed as single-writer and that federation would require a consensus layer (e.g., Raft over authority decisions, or explicit leader election per domain).

### Improvements

1. Add a "Consistency Model" section to the vision that explicitly states: (a) weights are eventually consistent with a bounded staleness window, (b) authority revocations must be fenced -- no dispatch should proceed with a weight newer than the last-seen authority version, (c) interspect evidence is read at a defined cadence (e.g., per-dispatch-cycle, not per-bead).

2. Define a conflict resolution rule for the interspect-Ockham boundary: when Ockham has promoted an agent but interspect evidence later contradicts the promotion, does demotion happen immediately or after multi-window confirmation? The brainstorm says demotion is faster than promotion (line 71) but does not address the retroactive-evidence case.

3. Specify whether `ockham_weight` absence (key not found in `ic state`) means "weight 1.0" (neutral) or "weight 0" (blocked). The brainstorm implies unlinked beads get 0.6, but the actual `dispatch_rescore()` in lib-dispatch.sh has no default-weight logic today and would need one.
