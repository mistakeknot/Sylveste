---
artifact_type: flux-drive-review
reviewer: fd-carolingian-missi-dominici-governance
target: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
track: D (Esoteric)
---

# Ockham Vision — Carolingian Missi Dominici Review

### Findings Index
- P1 | CAROL-01 | "Key Decisions §3" | Tier escalation lacks paired-confirmation; single signal path reaches CONSTRAIN
- P1 | CAROL-02 | "Key Decisions §5" | Safety invariants are stated as behavioral rules, not structural impossibilities
- P2 | CAROL-03 | "Key Decisions §1 / §4" | BYPASS path (Tier 3) conflates missus judgment with royal ban invocation
- P2 | CAROL-04 | "Open Questions §1" | Intent YAML has no temporal validity markers — capitulary staleness risk
- P3 | CAROL-05 | "Open Questions §3" | Cold-start defaults all domains to shadow but doesn't specify a mentored bootstrap window

**Verdict: needs-changes**

---

### Summary

The Carolingian missi dominici system is the closest historical predecessor to Ockham's architecture: envoys produced operating constraints for counts without commanding them directly, enforced five jurisdictional invariants structurally rather than behaviorally, and required paired-missus concurrence before any escalation above the lowest tier. The brainstorm correctly captures the policy/execution separation and the three algedonic tiers, but two structural gaps emerge when read against the Carolingian model. First, CONSTRAIN (Tier 2) can fire on Ockham's own anomaly signal without independent corroboration from interspect — the single-missus judgment that the Carolingian system explicitly prohibited. Second, the five safety invariants are stated as Ockham behavioral commitments rather than as rejection conditions enforced by the consuming systems (lib-dispatch.sh, bd set-state), which means a software fault in Ockham itself, not an adversarial agent, can silently violate them. The capitulary-staleness issue around intent YAML is a real but lower-severity gap. No P0 findings: the policy/execution separation is structurally sound as designed.

---

### Issues Found

**1. P1 — CAROL-01: CONSTRAIN fires on Ockham's own threshold without independent interspect confirmation**

The brainstorm (§3, Tier 2 — CONSTRAIN) specifies: "Signal persists past multi-window confirmation (short 1h AND long 24h)." The multi-window confirmation is purely temporal — it requires the same signal to persist across two time windows. But both windows are Ockham-internal: the anomaly subsystem produces the signal, and the anomaly subsystem checks whether it has persisted. There is no requirement that interspect's `agent_reliability` or canary evidence independently confirms the anomaly before the domain is frozen.

The Carolingian system required both missi to concur before escalating from Tier 1 (instruct the count) to Tier 2 (suspend jurisdiction). A single missus could not suspend a count; the other missus had to independently observe and agree. This was not a courtesy — it was a structural safeguard against false positives from a missus with a personal grievance against the count.

Concrete failure scenario: Ockham's anomaly subsystem has a threshold bug (or is fed stale beads state) and fires a 3x-quarantine signal for a domain. The signal persists for 25h (clearing both windows) simply because no new beads were claimed in that domain. The domain is frozen and the autonomy tier is demoted to shadow — all based on a false positive that interspect's canary monitoring would have refuted if it had been consulted.

Fix: In the anomaly subsystem, before writing a CONSTRAIN decision, require a call to `interspect.agent_reliability(agent, domain)` and confirm that `hit_rate < threshold OR confidence < threshold`. The CONSTRAIN decision should require both Ockham's temporal confirmation AND interspect's independent evidence confirmation. This is one conditional, not an architecture change.

**2. P1 — CAROL-02: Safety invariants are Ockham behavioral commitments, not structural rejections**

The five safety invariants (§5) are stated as things Ockham will not do. Specifically: "No self-promotion. An agent cannot elevate its own authority tier." The phrase "an agent cannot" is ambiguous: does it mean the write path rejects such an elevation, or does it mean Ockham has been designed not to produce such an elevation?

The Carolingian invariant "no missus judges in own benefice" was structural: the local population would not attend a court convened by the local missus because it was understood to be illegitimate. The count would not submit to it. The invariant was enforced by all parties in the execution path, not by the missus choosing to recuse himself.

If Ockham's self-promotion prohibition lives only in Ockham's authority subsystem logic, then a bug in that subsystem (or an adversarial model running as Ockham) can issue a self-elevation that lib-dispatch.sh and bd-set-state will honor, because neither has been told to reject it.

Concrete failure scenario: Ockham's authority subsystem has a logic error where a pleasure signal in `interverse/**` triggers a domain re-scoping that expands the domain boundary to include `core/**`. Ockham writes `autonomy_tier=autonomous` for `core/**` to itself. lib-dispatch.sh reads `ockham_weight` and honors it. No consuming system rejected the write.

Fix: The invariant enforcement belongs in the consuming systems, not (only) in Ockham. `bd set-state autonomy_tier=<tier>` should accept a `--asserting-principal=<id>` argument and reject writes where the asserting principal and the target agent are the same entity. This pushes the invariant into the execution path where it cannot be bypassed by Ockham faults.

**3. P2 — CAROL-03: Tier 3 BYPASS conflates two distinct Carolingian roles**

In the Carolingian escalation ladder, Tier 3 (the royal ban) was invoked by the king, not by the missi. The missi could recommend a royal ban, but the ban itself required the palace to act. The brainstorm's Tier 3 (§3) has Ockham itself writing `factory-paused.json` and emitting direct notification. This conflates the missus recommending a ban with the palace issuing one — Ockham is both the evidence-gathering envoy and the authority that invokes the highest-level halt.

This is not a P1 because the brainstorm also specifies "Human halt supremacy: The principal can halt the entire factory at any time. No Ockham policy can override or delay a human halt." The principal retains ultimate authority. But the design allows Ockham to invoke Tier 3 autonomously, which means a false positive in anomaly detection can pause the entire factory without principal involvement. The Carolingian answer: the missus could freeze a county (Tier 2) unilaterally, but only the palace could invoke the royal ban.

Fix (smallest viable): Tier 3 BYPASS should not write `factory-paused.json` directly. Instead, Ockham should write a `factory-pause-requested.json` and emit the algedonic notification. The principal's explicit acknowledgment (any key, a `yes` to the notification, or a timed expiration) converts the request into an actual pause. This preserves the signal-reaching-principal function while keeping the irreversible act in principal hands.

**4. P2 — CAROL-04: Intent YAML has no temporal validity markers**

Open Question 1 asks how constraints compose with theme budgets. The deeper gap is that intent YAML has no expiry field. A principal running `ockham intent --theme auth --budget 40%` in Q1 will find that budget still shaping dispatch weights in Q3 unless they explicitly revoke it.

The Carolingian capitularies issued for one region and year were often misapplied years later in different regions because the palace lacked visibility into whether local conditions had changed. The missi were supposed to flag when capitularies had become inapplicable, but this depended on the missus knowing the original context.

Fix: Intent entries in `intent.yaml` should include a `valid_until` field (ISO timestamp or a bead count / cycle count). Ockham's dispatch subsystem should log a warning when reading an intent entry whose `valid_until` has passed, and should zero-weight that entry (treat as if no intent was set) rather than continue applying stale intent. This is an additive schema change.

**5. P3 — CAROL-05: Cold-start lacks a mentored bootstrap window**

Open Question 3 asks whether cold start defaults all domains to shadow. The brainstorm doesn't address the bootstrapping period: how long does an agent operate in shadow before it has accumulated enough interspect evidence to be eligible for promotion? The Carolingian answer was that new missi traveled with experienced ones for their first full annual circuit before being trusted to ride alone.

Without a bootstrap window, an agent enters shadow mode and could theoretically accumulate enough first_attempt_pass_rate evidence in a few sessions to trigger promotion — before it has been observed across diverse bead types, edge cases, or high-stakes domains.

Suggestion: Define a minimum observation window (not just a threshold): an agent must have been observed in shadow mode for at least N sessions AND meet the metric threshold. This prevents promotion based on a lucky streak in easy beads. The specific N is a calibration question (see Open Question 5), but the presence or absence of a minimum-sessions floor is a design question the brainstorm leaves open.

---

### Improvements

1. **Paired confirmation before CONSTRAIN**: Add `require_interspect_corroboration: true` to the CONSTRAIN tier specification. The anomaly subsystem checks Ockham's temporal windows AND calls `interspect.agent_reliability` before writing the domain freeze — two independent sources must agree before jurisdiction is suspended.

2. **Push invariant enforcement to execution path**: Add a `--asserting-principal` check to `bd set-state` (or a wrapper `ockham-apply-authority` command that lib-dispatch.sh calls) so that self-issued authority changes are rejected at the write layer, not by conditional logic inside Ockham. Document this as "structural enforcement" in the safety invariants section.

3. **Separate Tier 3 invocation from Tier 3 signaling**: Define `factory-pause-requested.json` (Ockham writes) vs. `factory-paused.json` (principal or timed-acknowledgment writes). Ockham never writes the latter directly — it signals, the principal acts.

4. **Add `valid_until` to intent YAML schema**: Make the field optional with a default of 90 days. Ockham's dispatch subsystem emits a WARN-level algedonic signal when reading an expired intent entry, and treats it as weight=1.0 (neutral) rather than applying the stale budget.

5. **Specify minimum observation floor for promotion**: In the autonomy ratchet description, add a minimum N sessions in current tier alongside the metric threshold, so promotion requires evidence breadth (diverse bead exposure) not just evidence depth (repeated high scores on similar beads).
