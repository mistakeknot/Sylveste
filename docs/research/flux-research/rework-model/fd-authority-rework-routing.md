# Authority Tier Model for Disposition Routing

**Date:** 2026-03-19
**Agent:** fd-authority-rework-routing (quality systems researcher, disposition governance)
**Context:** Rework model research — mapping Sylveste's 5-tier domain-scoped authority to MRB-style disposition decisions
**Inputs:** authority-tiers/synthesis.md, authority-tiers/fd-authority-schema-design.md, MRB/AS9100 literature, MIL-HDBK-61A deviation frameworks

---

## 1. Problem Statement

When an agent's work output is nonconforming (tests fail, review rejected, lint violations, blast-radius exceeded), something must decide: scrap it, rework it, use it as-is, or authorize a deviation from the spec. In manufacturing, this is the Material Review Board (MRB) problem. In Sylveste's AI factory, the question is: **which authority tier can authorize which disposition type, and when must the decision escalate?**

The existing authority model defines five action classes (Propose, Execute, Commit, Deploy, Spend) scoped to domains via `authority_grants`. This document extends that model to cover disposition decisions — the governance of *what happens to failed work*.

---

## 2. Disposition Types Mapped to Software Factory

Manufacturing has four canonical dispositions. Each has a direct analogue in an AI software factory:

| Manufacturing Disposition | Software Factory Analogue | Description |
|--------------------------|--------------------------|-------------|
| **Scrap** | Abandon the change | Discard the branch/patch entirely. No salvageable value. Work-hours lost. |
| **Rework** | Fix and resubmit | Correct the output to meet the original spec. Most common disposition. |
| **Use-As-Is** | Merge with known deficiency | Accept the output despite spec deviation. Requires documented risk justification. |
| **Deviation (Waiver)** | Change the spec itself | The spec was wrong or overly strict. Modify acceptance criteria, then the output conforms. |

A fifth state, **Return to Supplier**, maps to **reassign to different agent** — the work is not dispositioned but re-routed to an agent with better domain authority or different capabilities.

---

## 3. Authority Tier to Disposition Mapping

### 3.1 The Disposition Authority Matrix

Using the existing 5-tier action classes (Propose/Execute/Commit/Deploy/Spend) and Mycroft tiers (T0-T3), disposition authority maps as follows:

| Disposition | Minimum Action Class | Minimum Mycroft Tier | Domain Scope Required | Escalation Trigger |
|------------|---------------------|---------------------|----------------------|-------------------|
| **Scrap (own work)** | Execute | T0 | Same domain as failed work | None — any agent can abandon its own output |
| **Scrap (other's work)** | Commit | T2 | Same domain | Requires review evidence |
| **Rework (self)** | Execute | T0 | Same domain | Auto if within retry budget |
| **Rework (reassign)** | Commit | T1 | Parent domain or broader | When original agent exhausted retries |
| **Use-As-Is** | Commit | T2 | Same domain + blast-radius assessment | Always requires second authority (dual-key) |
| **Deviation (minor)** | Commit | T2 | Domain owning the spec | Spec owner must be grantor or co-signer |
| **Deviation (major)** | Deploy | T3 | Cross-domain or safety-relevant | Always escalates to principal |
| **Deviation (critical)** | — | — | — | **Human-only.** No agent authority. |

### 3.2 Rationale from Manufacturing Standards

This mapping draws directly from established frameworks:

**AS9100 8.7.1** requires that disposition authority be documented, competence-based, and that Design/Engineering authorize use-as-is or repair dispositions. In Sylveste terms: only agents with Commit-level domain authority (earned through evidence of successful work in that domain) can accept nonconforming output.

**MIL-HDBK-61A** defines three deviation severity levels — Minor (local MRB), Major (government CCB), Critical (commanding officer only). This maps directly to the three deviation tiers above: minor (domain-local T2), major (cross-domain T3), critical (human principal only, no agent delegation).

**MRB composition** requires cross-functional membership (quality, design, manufacturing, stress). The dual-key requirement for Use-As-Is mirrors this: the dispositioning agent and at least one independent authority in the affected domain must concur.

---

## 4. MRB Authority Scoping in an Agent Fleet

### 4.1 Who Constitutes the MRB?

In manufacturing, the MRB is a standing cross-functional board chaired by Quality Assurance. In the agent fleet, the MRB equivalent is a **disposition quorum** — a set of authority holders whose combined domain coverage spans the nonconformance.

```
Disposition Quorum = {
  chair:    agent with highest domain authority in affected area (QA analogue)
  design:   agent with Commit authority in the spec-owning domain
  execute:  agent that produced or will rework the output
  review:   independent agent with review authority (Interspect analogue)
}
```

Not all members are needed for every disposition:

| Disposition | Required Quorum Members |
|------------|------------------------|
| Scrap (own) | Execute only (self) |
| Rework (self) | Execute only (self) |
| Rework (reassign) | Chair + new Execute |
| Use-As-Is | Chair + Design + Review (minimum 2 of 3) |
| Deviation (minor) | Chair + Design |
| Deviation (major) | Chair + Design + Principal notification |
| Deviation (critical) | Principal decision (agents advise only) |

### 4.2 Domain Scoping Rules

MRB authority is scoped to domain patterns, matching the `authority_grants.domain_pattern` field:

1. **Narrow scope** (e.g., `interverse/interspect/**`): Agent can disposition within that module only
2. **Moderate scope** (e.g., `core/**`): Agent can disposition across the core layer
3. **Broad scope** (e.g., `**`): Agent can participate in any disposition quorum

An agent's disposition authority cannot exceed its domain authority grant. An agent with Execute authority in `interverse/interflux/**` cannot disposition Use-As-Is for `core/intercore/**` output, regardless of Mycroft tier.

---

## 5. Self-Disposition vs. Escalation

### 5.1 Self-Disposition Rights

Agents can self-disposition (decide without escalation) under these conditions:

**Scrap own work:**
- Always permitted. An agent can abandon its own output at any time.
- Audit record required (disposition_type=scrap, reason, work_hours_lost).
- No approval needed — this is the "stop digging" principle.

**Rework own work:**
- Permitted if retry_count < retry_budget (default: 3 per bead).
- Each retry must address a distinct failure mode (no identical re-runs).
- After retry budget exhausted: escalate to reassignment or scrap.

**Scrap others' work:**
- Never self-dispositioned. Requires review evidence + Commit authority.

### 5.2 Escalation Triggers

Escalation from self-disposition to quorum/MRB is **mandatory** when any of these conditions hold:

| Trigger | Rationale | Escalation Target |
|---------|-----------|-------------------|
| Retry budget exhausted (3 attempts) | Diminishing returns on same approach | Reassignment or scrap via Chair |
| Blast radius > "moderate" | Cross-domain impact needs broader authority | Domain-spanning quorum |
| Test regression in unrelated module | Nonconformance has escaped original domain | Affected domain authority holders |
| Cost exceeds bead budget by >50% | Spend authority threshold breached | T2+ or Principal |
| Safety-relevant domain (deploy, infra) | Higher consequence of wrong disposition | T3 or Principal |
| Spec ambiguity discovered | Cannot determine conformance without spec clarification | Deviation path (Design authority) |
| Conflicting review signals | Two reviewers disagree on conformance | Chair breaks tie |
| Agent confidence below threshold | Self-assessed uncertainty exceeds domain's fail-closed policy | Next tier up |

### 5.3 Escalation Mechanics

Escalation writes to the `authority_audit` table with `decision='escalate'` and creates a disposition request:

```
disposition_request = {
  request_id:      UUID v7
  bead_id:         <failing bead>
  requesting_agent: <agent that hit the trigger>
  proposed_disposition: <scrap|rework|use_as_is|deviation>
  trigger:         <which escalation trigger fired>
  evidence_refs:   [<list of Interspect event IDs, test results, review records>]
  domain_affected: <glob pattern>
  status:          pending | approved | rejected
  decided_by:      <quorum member IDs>
  decided_at:      <timestamp>
}
```

---

## 6. Deviation Authority: Spec-Level Changes

### 6.1 Deviation vs. Rework

The critical distinction: **rework changes the output to match the spec; deviation changes the spec to match the output.** Deviation is more powerful and more dangerous — it permanently (or temporarily) alters what "conforming" means.

In manufacturing terms (per MIL-HDBK-61A):
- A **deviation** is a written authorization to depart from requirements for a specific number of units or time period. It does not change the configuration document.
- A **waiver** applies to already-produced items found to depart from spec.
- An **engineering change** permanently modifies the specification.

### 6.2 Deviation Authority Levels

| Deviation Type | Scope | Agent Authority | Human Role |
|---------------|-------|----------------|------------|
| **Minor deviation** | Cosmetic, style, non-functional spec relaxation | T2 Commit + domain ownership of the spec file | Notified post-decision |
| **Major deviation** | Functional spec change, API contract modification, cross-module impact | T3 Deploy + cross-domain authority | Must approve before execution |
| **Critical deviation** | Safety invariant, security boundary, data integrity constraint | No agent authority | Principal decides; agents provide analysis only |
| **Temporary waiver** | Time-boxed acceptance of known deficiency (e.g., skip flaky test for 7 days) | T2 Commit + expiry enforcement | Auto-expires; extension requires re-approval |

### 6.3 Deviation Workflow

```
1. Agent identifies spec mismatch (nonconformance that may be spec-caused)
2. Agent proposes deviation with:
   - Affected spec (file path, line range, or rule ID)
   - Proposed relaxation or change
   - Impact analysis (what else depends on this spec?)
   - Duration (permanent change vs. temporary waiver)
3. Authority check:
   a. Is this agent the spec owner (authority_grants.domain_pattern covers the spec file)?
   b. Does the agent hold sufficient action_class for the deviation severity?
   c. If not → escalate to spec owner or principal
4. If approved → spec change committed (engineering change) or waiver record created (temporary)
5. Original output re-evaluated against modified spec
6. Audit trail records: deviation_request, approval chain, new spec version
```

### 6.4 Guard Rails

- **No self-deviation:** An agent cannot approve a deviation for a spec it also wrote. This prevents the "author lowers the bar" anti-pattern. Cross-authority required.
- **Deviation budget:** Each domain has a maximum number of active deviations (default: 5). Exceeding this triggers a "spec health review" escalation to the principal.
- **Deviation decay:** Temporary waivers auto-expire. If the underlying issue is not fixed, the waiver cannot be renewed more than twice without principal approval.

---

## 7. Quarantine: Authority Limbo

### 7.1 What Quarantine Means

In manufacturing, quarantine is a material status meaning "physically present, not available for use." The material exists but is blocked from all downstream consumption until a disposition decision is made.

In the software factory, quarantine means:

- **Branch exists** but is not mergeable
- **Bead is in-progress** but work is halted
- **Output is produced** but gates are locked
- No agent can use, merge, deploy, or build upon quarantined output

### 7.2 Quarantine Entry Triggers

Output enters quarantine automatically when:

1. **Gate failure** with no self-disposition right (retry budget exhausted, blast radius exceeded)
2. **Conflicting dispositions** — two authorized agents disagree
3. **Authority gap** — no agent in the fleet holds sufficient authority for the required disposition
4. **Incident linkage** — output is associated with a detected incident (Interspect safety signal)
5. **Principal hold** — human explicitly quarantines pending review

### 7.3 Quarantine Properties

```
quarantine_record = {
  quarantine_id:    UUID v7
  bead_id:          <affected bead>
  branch_ref:       <git ref, if applicable>
  entered_at:       <timestamp>
  entered_by:       <agent, system, or principal>
  entry_reason:     <trigger type + details>
  status:           quarantined | released | scrapped
  released_at:      <timestamp, NULL while quarantined>
  released_by:      <authority that dispositioned>
  disposition:      <scrap|rework|use_as_is|deviation, NULL while quarantined>
  max_quarantine_days: 14  -- default; configurable per domain
}
```

### 7.4 Quarantine Governance

**Who can release from quarantine:**

| Release Action | Minimum Authority |
|---------------|------------------|
| Release to scrap | T1 Execute in domain (anyone can authorize destruction) |
| Release to rework | T1 Execute in domain + available agent with capacity |
| Release to use-as-is | T2 Commit + dual-key (same as use-as-is disposition) |
| Release via deviation | Per deviation authority levels (Section 6.2) |

**Quarantine aging:** If output remains quarantined beyond `max_quarantine_days` (default 14), it auto-escalates to the principal with a recommendation (usually scrap, since stale output accumulates merge debt).

**No work on quarantined output:** Agents cannot modify, build upon, or reference quarantined output. This prevents the manufacturing anti-pattern of "using quarantined material in production because it was physically accessible."

---

## 8. Audit Trail Requirements

### 8.1 What Must Be Recorded

Every disposition decision — whether self-dispositioned or escalated — must produce an immutable audit record. This draws from FDA 21 CFR Part 11 principles (time-stamped, user-identified, action-detailed) and ISO 9001 8.5.2 traceability requirements.

**Required fields for every disposition record:**

| Field | Description | Rationale |
|-------|-------------|-----------|
| `disposition_id` | UUID v7 | Unique, time-sortable identifier |
| `bead_id` | Affected work item | Links disposition to work context |
| `disposition_type` | scrap, rework, use_as_is, deviation, reassign | What was decided |
| `decided_by` | Agent ID(s) or principal | Who authorized |
| `decided_at` | Timestamp | When |
| `authority_basis` | grant_id(s) from authority_grants | Which authority grants justified the decision |
| `mycroft_tier_at_decision` | T0-T3 | Fleet tier at decision time (may change later) |
| `evidence_refs` | List of Interspect event IDs, test result IDs, review IDs | What facts supported the decision |
| `escalation_chain` | Ordered list of agents who handled before final decision | Full routing history |
| `domain_affected` | Glob pattern | Scope of impact |
| `nonconformance_description` | Free text | What was wrong |
| `risk_assessment` | For use-as-is/deviation: documented risk justification | Why accepting the deficiency is tolerable |
| `rework_spec` | For rework: what must change and acceptance criteria | Prevents identical re-runs |
| `quarantine_id` | If output was quarantined, link to quarantine record | Joins the quarantine and disposition timelines |

### 8.2 Audit Integrity Properties

1. **Append-only:** Disposition records cannot be modified or deleted. Corrections create new records referencing the original.
2. **Decision-time snapshot:** The `mycroft_tier_at_decision` and `authority_basis` fields capture the state at decision time, not current state. If an agent's authority is later revoked, the historical record remains accurate.
3. **Evidence completeness:** A disposition record with empty `evidence_refs` is a compliance violation. Automated checks (Interspect hook) reject disposition records without at least one evidence reference.
4. **Dual-key verification:** For Use-As-Is and Deviation dispositions, the audit record must contain at least two distinct `decided_by` entries. Single-authority acceptance of nonconforming output is prohibited.

### 8.3 Integration with Existing Schema

Disposition audit records extend the `authority_audit` table from the authority-tiers schema. The `decision` enum gains new values:

```sql
ALTER TABLE authority_audit
  MODIFY decision ENUM(
    'allow', 'deny', 'escalate',
    'disposition_scrap', 'disposition_rework',
    'disposition_use_as_is', 'disposition_deviation',
    'disposition_reassign', 'quarantine_enter', 'quarantine_release'
  ) NOT NULL;
```

A companion `disposition_details` table stores the extended fields (risk_assessment, rework_spec, quarantine linkage) that do not fit the core audit table:

```sql
CREATE TABLE disposition_details (
  audit_id          VARCHAR(36) PRIMARY KEY REFERENCES authority_audit(audit_id),
  disposition_type  ENUM('scrap','rework','use_as_is','deviation','reassign') NOT NULL,
  nonconformance    TEXT NOT NULL,
  risk_assessment   TEXT NULL,          -- required for use_as_is and deviation
  rework_spec       TEXT NULL,          -- required for rework
  quarantine_id     VARCHAR(36) NULL,   -- link to quarantine record if applicable
  deviation_scope   ENUM('minor','major','critical') NULL,
  deviation_expiry  TIMESTAMP NULL,     -- for temporary waivers
  evidence_count    INT NOT NULL,       -- denormalized for compliance queries

  INDEX idx_type (disposition_type),
  INDEX idx_quarantine (quarantine_id)
);
```

---

## 9. Decision Flowchart

```
Nonconforming output detected
           │
           ▼
   ┌─────────────────┐
   │ Is it the agent's│
   │  own work?       │
   └────┬────────┬────┘
        │yes     │no
        ▼        ▼
   Can self-    Escalate to
   disposition?  domain authority
        │
   ┌────┴──────────┐
   │ Retry budget  │
   │ remaining?    │
   └──┬─────────┬──┘
      │yes      │no
      ▼         ▼
   Rework    ┌──────────────┐
   (self)    │ Blast radius │
             │ assessment   │
             └──┬────────┬──┘
                │low     │high
                ▼        ▼
            Scrap or   Quarantine
            reassign   + escalate
                         │
                    ┌────┴─────┐
                    │ Quorum   │
                    │ decision │
                    └──┬───┬───┘
                       │   │
            ┌──────────┘   └──────────┐
            ▼                         ▼
     Rework/Scrap/              Use-As-Is or
     Reassign                   Deviation
     (T1-T2)                    (T2-T3 + dual-key)
                                      │
                                 ┌────┴─────┐
                                 │ Deviation │
                                 │ severity? │
                                 └┬────┬────┬┘
                          minor   │    │    │  critical
                          (T2)  major  │    (human only)
                                (T3)   │
                                       ▼
                              Principal decides
```

---

## 10. Key Design Decisions and Open Questions

### Decisions Made

1. **Self-scrap is always permitted.** An agent should never be forced to continue work it believes is unsalvageable. The cost of preventing self-scrap (stuck agents, wasted cycles) exceeds the cost of occasional premature abandonment.

2. **Use-As-Is requires dual-key.** This is the highest-risk disposition because it introduces known deficiencies into the mainline. Manufacturing (AS9100) requires Design/Engineering authorization; the agent equivalent is domain authority + independent review authority concurrence.

3. **Critical deviations are human-only.** Following MIL-HDBK-61A's "commanding officer" principle — deviations affecting safety invariants, security boundaries, or data integrity constraints are never delegated to agents regardless of tier.

4. **Quarantine has a time limit.** Stale quarantined output becomes more expensive to disposition over time (merge conflicts, context loss). Auto-escalation after 14 days forces a decision.

5. **No self-deviation.** An agent cannot lower the bar for its own output. This is the "separation of duties" principle from manufacturing quality — the producer and the quality authority must be different entities.

### Open Questions

1. **Retry budget calibration:** Is 3 the right default? Should it vary by domain complexity or historical rework success rates?

2. **Quarantine max-age:** 14 days may be too long for fast-moving domains (interverse plugins) and too short for complex domains (core/intercore). Should this be domain-configurable?

3. **Deviation budget enforcement:** The "5 active deviations per domain" limit is arbitrary. Should this be evidence-based (e.g., correlated with defect escape rate)?

4. **MRB composition for small fleets:** If the fleet has fewer than 4 agents with domain authority, can the quorum requirements be relaxed, or must a human fill the gap?

5. **Cost attribution:** When rework disposition is chosen, who "pays" the additional compute cost — the original agent's budget, the domain budget, or a shared rework pool?

---

## Sources

- [Material Review Board – Nonconformance Disposition (SG Systems)](https://sgsystemsglobal.com/glossary/material-review-board-mrb/)
- [How A Material Review Board Works (Agilian)](https://www.agiliantech.com/blog/material-review-board-mrb/)
- [Material Review Board: Deciding the Fate of Nonconforming... (Tulip)](https://tulip.co/blog/material-review-board/)
- [AS9100 Control of Nonconforming Outputs (Elsmar)](https://elsmar.com/elsmarqualityforum/threads/as9100-control-of-nonconforming-outputs-rework-dispositions.81874/)
- [Authority for Disposition of Nonconforming Product – AS9100 (Elsmar)](https://elsmar.com/elsmarqualityforum/threads/authority-for-disposition-of-nonconforming-product-as9100.28000/)
- [Customer Authorization for Use As Is & Repair – AS9100 (Elsmar)](https://elsmar.com/elsmarqualityforum/threads/customer-authorization-for-use-as-is-repair-as-9100.33473/)
- [MIL-HDBK-61A 6.3 Request for Deviation](https://www.product-lifecycle-management.com/mil-hdbk-61a-6-3.htm)
- [SWE-126 Waiver and Deviation Considerations (NASA SWEHB)](https://swehb.nasa.gov/display/SWEHBVB/SWE-126+-+Waiver+and+Deviation+Considerations)
- [Quarantine – Quality Hold Status (SG Systems)](https://sgsystemsglobal.com/glossary/quarantine-quality-hold-status/)
- [Nonconforming Product Control (SG Systems)](https://sgsystemsglobal.com/guides/nonconforming-product-control/)
- [Deviation vs. Waiver (ASQ Forum)](https://my.asq.org/discuss/viewtopic/99/120)
- [FDA 21 CFR Part 11 Audit Trails (SimplerQMS)](https://simplerqms.com/21-cfr-part-11-audit-trail/)
- [ISO 9001 Clause 8.5.2 Identification & Traceability (Qualityze)](https://www.qualityze.com/blogs/iso-9001-clause-8-5-2-identification-traceability)
- [Automating Quality Control: Rework Routing Disposition in SAP (SAP Community)](https://community.sap.com/t5/supply-chain-management-blog-posts-by-sap/automating-quality-control-rework-routing-disposition-in-sap-digital/ba-p/14112891)

<!-- flux-research:complete -->
