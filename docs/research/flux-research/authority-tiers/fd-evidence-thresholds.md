# Evidence-Based Authority: Earning, Maintaining, and Revoking Agent Trust

**Reviewer lens:** Reliability engineer designing progressive rollout and SLO-based promotion gates.
**Grounded against:** Mycroft T0-T3 tier FSM (`docs/cujs/mycroft-fleet-dispatch.md`, `docs/cujs/mycroft-failure-recovery.md`), Interspect adaptive routing (`docs/brainstorms/2026-03-17-interspect-adaptive-routing.md`), Skaffen tool trust (`docs/cujs/skaffen-tool-trust.md`), Phase 4 graduated authority (`docs/brainstorms/2026-03-19-ai-factory-orchestration-brainstorm.md`), agent trust scoring (`docs/brainstorms/2026-02-25-agent-trust-scoring-brainstorm.md`).
**Anti-overlap:** fd-authority-schema-design covers data model. fd-credentialing-analogues covers real-world analogies. fd-multiagent-trust covers safety/threat models.

---

## 1. Progressive Delivery Promotion Patterns

### 1.1 Canary Analysis Model (Argo Rollouts, Spinnaker/Kayenta)

The strongest prior art for evidence-based promotion comes from progressive delivery systems that automate rollout decisions based on real-time metrics. The structural parallels to agent authority are direct: a deployment earns broader exposure by demonstrating safety at each stage, exactly as an agent should earn broader autonomy by demonstrating competence.

**Argo Rollouts analysis templates** define per-metric evaluation with explicit thresholds:

```yaml
metrics:
- name: success-rate
  interval: 5m           # How often to sample
  count: 10              # Total measurements needed
  successCondition: result[0] >= 0.95
  failureCondition: result[0] < 0.50
  failureLimit: 3        # Max failures before analysis fails
  consecutiveSuccessLimit: 4  # Required consecutive passes
```

Key parameters that transfer to agent authority:
- **interval**: How frequently to evaluate evidence (patrol cycle in Mycroft terms)
- **count**: Minimum observations before a promotion decision (the "N successful actions" requirement)
- **failureLimit**: How many failures trigger demotion (Mycroft's "3 consecutive failures" trigger)
- **consecutiveSuccessLimit**: Streak requirement for upgrade (guards against lucky single runs)
- **initialDelay**: Warm-up period before evaluation (new agent gets grace period in unfamiliar domain)

**Spinnaker/Kayenta canary analysis** adds two-threshold scoring:

| Threshold | Value | Agent Authority Equivalent |
|-----------|-------|---------------------------|
| Marginal (immediate fail) | 75 | Hard demotion trigger: score below this = immediate tier drop |
| Pass (promotion eligible) | 95 | Promotion gate: score must exceed this for upgrade consideration |
| Critical metric flag | `critical: true` | Certain evidence classes (incident attribution, security violation) bypass scoring and trigger immediate demotion regardless of aggregate score |

**Spinnaker best practice**: "You need at least 50 pieces of time series data per metric for the statistical analysis to produce accurate results." With a 3-hour observation window and 1-hour intervals, you get 3 runs. For agent authority, this translates to: don't promote on fewer than N observations in the target domain.

### 1.2 LaunchDarkly Guarded Rollouts

LaunchDarkly's guarded rollouts combine percentage ramps with real-time metric monitoring and automatic rollback. The progression model (5% -> 25% -> 50% -> 100%) with metric gates at each stage maps to Sylveste's existing Mycroft tiers:

| LaunchDarkly Stage | Mycroft Tier | Authority Level |
|-------------------|-------------|-----------------|
| 0% (shadow) | T0 | Observe only, log shadow suggestions |
| 5% (canary) | T1 | Suggest, require human approval |
| 25-50% (progressive) | T2 | Auto-dispatch within allowlist |
| 100% (full rollout) | T3 | Full autonomous dispatch within budget |

**Key insight from LaunchDarkly**: Progressive rollouts without metric monitoring are just scheduled ramps. Guarded rollouts add automatic rollback when metrics regress. The agent authority equivalent: promotion without evidence-based demotion triggers is just a permission escalation schedule.

### 1.3 Structural Transfer to Agent Authority

The three systems converge on a common pattern:

1. **Observation window before promotion**: Never promote on a single success. Require N observations over T time.
2. **Asymmetric thresholds**: Promotion requires high confidence (95th percentile). Demotion triggers at lower threshold (75th percentile) but acts faster.
3. **Critical metric override**: Certain failure classes bypass the scoring model entirely.
4. **Automatic rollback**: Demotion is automated. Promotion can be automated or human-gated depending on tier.

---

## 2. Evidence Classes for Agent Authority

### 2.1 Evidence Taxonomy

Evidence for agent authority decisions falls into six classes, ordered by signal strength (strongest first):

| Class | Signal | Weight | Source in Sylveste |
|-------|--------|--------|-------------------|
| **Incident attribution** | Agent action caused revert, breakage, security issue | -4x (critical metric — bypasses scoring) | Interspect `incident` events, git revert correlation |
| **Human override** | Human rejected agent proposal or reverted agent action | -2x per override | Interspect `finding_discarded`, `dispatch_rejected` events |
| **Successful deployment** | Agent's change merged, tests pass, no rollback within 24h | +1x base | Bead closure with `status=closed`, no subsequent reopen |
| **Review acceptance** | Agent's review findings accepted by human | +0.5x per accepted finding | Interspect `finding_accepted` events |
| **Rejected proposal** | Agent proposed action that was rejected pre-execution | -0.5x (softer than override — rejection prevented harm) | Interspect `proposal_rejected` events |
| **Review latency** | Time from agent output to human approval/merge | Indirect: fast latency = human trusts output | Bead state timestamps (claimed_at -> closed_at) |

### 2.2 Evidence Granularity: Domain x Action Class

Evidence must be scoped to (agent, domain, action_class) triples. An agent that excels at test-writing in `internal/mycroft/` has demonstrated nothing about its ability to refactor `core/intercore/`. The trust scoring brainstorm already established per-agent per-project scoping with global fallback. Phase 4 authority extends this to per-domain within a project.

**Domain** is a file-path pattern or module scope:
- `internal/mycroft/**` — the Mycroft scheduler subsystem
- `core/intercore/**` — the kernel
- `docs/**` — documentation (lower blast radius, lower threshold)
- `*.go` — Go code broadly (coarser grain, used as fallback)

**Action class** follows the Phase 4 brainstorm's five tiers:
- **Propose**: Suggest a change (no side effects)
- **Execute**: Write code, run commands
- **Commit**: Land changes on main
- **Deploy**: Release to production
- **Spend**: Incur cost (token budget, API calls)

Evidence at action class A counts toward authority at class A and below. Successfully committing (A=Commit) implies competence at Execute and Propose in that domain.

### 2.3 Cold Start

Following the trust scoring brainstorm's precedent:
- New (agent, domain, action_class) triples inherit the agent's **cross-domain average** within the project.
- If no project history exists, inherit the agent's **cross-project global average**.
- If no global history exists, start at the **fleet-tier floor** (Mycroft T0-T3 sets the ceiling; domain authority starts at the floor of that ceiling).
- Blend formula: `authority = (domain_weight * domain_score) + ((1 - domain_weight) * fallback_score)` where `domain_weight = min(1.0, domain_observations / 20)`.

The "5-review threshold" from the trust scoring brainstorm becomes the minimum observation count before domain-specific authority diverges from the fallback.

---

## 3. Threshold Functions

### 3.1 Promotion (Upgrade) Thresholds

Promotion from action class A to A+1 in domain D requires ALL of:

```
PROMOTE(agent, domain, action_class) when:
  observations(agent, domain, action_class) >= N_min(action_class)
  AND success_rate(agent, domain, action_class) >= S_min(action_class)
  AND consecutive_successes(agent, domain, action_class) >= C_min(action_class)
  AND days_since_first_observation(agent, domain) >= T_min(action_class)
  AND critical_incidents(agent, domain, last_90d) == 0
  AND human_override_rate(agent, domain, last_30d) <= O_max(action_class)
```

Default parameters (tunable per domain via YAML config):

| Action Class | N_min (observations) | S_min (success rate) | C_min (consecutive) | T_min (days) | O_max (override rate) |
|-------------|---------------------|---------------------|--------------------|--------------|-----------------------|
| Propose -> Execute | 5 | 0.80 | 3 | 1 | 0.30 |
| Execute -> Commit | 15 | 0.90 | 5 | 7 | 0.15 |
| Commit -> Deploy | 30 | 0.95 | 10 | 14 | 0.05 |
| Deploy -> Spend | 50 | 0.95 | 15 | 30 | 0.05 |

**Rationale for asymmetry**: Lower tiers promote faster because the blast radius is smaller. A bad proposal costs review time. A bad deployment costs production stability. The observation count and time minimums scale with blast radius.

**Interaction with fleet-tier ceiling**: An agent at Mycroft T1 cannot hold domain authority above Execute regardless of domain evidence. Fleet-tier sets the ceiling; domain authority is independently earned within that ceiling. This prevents a domain-excellent agent from self-promoting to Deploy when the fleet coordinator hasn't earned T2+ trust.

```
effective_authority(agent, domain, action) =
  min(domain_authority(agent, domain, action),
      fleet_tier_ceiling(mycroft_tier))
```

### 3.2 Demotion (Downgrade) Triggers

Demotion triggers are designed to fire faster than promotion criteria are earned (asymmetric by design, matching canary analysis best practices):

**Immediate demotion (critical metric override)**:
- Any incident attributed to agent in domain -> drop to Propose
- Security violation (credential exposure, unauthorized network call) -> drop to Propose, require explicit human re-grant
- 3 consecutive failures in domain within 24h -> drop one tier (matches Mycroft circuit breaker)

**Gradual demotion (score-based)**:
```
DEMOTE(agent, domain, action_class) when:
  success_rate(agent, domain, action_class, last_30d) < S_demote(action_class)
  OR human_override_rate(agent, domain, last_30d) > O_demote(action_class)
```

| Action Class | S_demote (success rate floor) | O_demote (override rate ceiling) |
|-------------|------------------------------|----------------------------------|
| Execute | 0.60 | 0.40 |
| Commit | 0.75 | 0.25 |
| Deploy | 0.85 | 0.10 |
| Spend | 0.90 | 0.10 |

**Key asymmetry**: Promotion to Commit requires 0.90 success rate over 15+ observations. Demotion from Commit triggers at 0.75 success rate. This hysteresis band (0.75-0.90) prevents oscillation — an agent at Commit that dips to 0.82 holds its tier, but must recover to 0.90 to earn the next tier.

### 3.3 Configuration

Thresholds are tunable per domain without code changes. The authority config lives alongside route.md:

```yaml
# .clavain/authority/thresholds.yaml
defaults:
  promote:
    execute: { n_min: 5, success_rate: 0.80, consecutive: 3, days: 1, override_ceiling: 0.30 }
    commit:  { n_min: 15, success_rate: 0.90, consecutive: 5, days: 7, override_ceiling: 0.15 }
    deploy:  { n_min: 30, success_rate: 0.95, consecutive: 10, days: 14, override_ceiling: 0.05 }
    spend:   { n_min: 50, success_rate: 0.95, consecutive: 15, days: 30, override_ceiling: 0.05 }
  demote:
    execute: { success_floor: 0.60, override_ceiling: 0.40 }
    commit:  { success_floor: 0.75, override_ceiling: 0.25 }
    deploy:  { success_floor: 0.85, override_ceiling: 0.10 }
    spend:   { success_floor: 0.90, override_ceiling: 0.10 }
  decay:
    half_life_days: 30
    staleness_threshold_days: 90

overrides:
  "core/intercore/**":
    promote:
      commit: { n_min: 25, success_rate: 0.95, consecutive: 8, days: 14 }
    demote:
      commit: { success_floor: 0.85 }
  "docs/**":
    promote:
      commit: { n_min: 5, success_rate: 0.80, consecutive: 2, days: 1 }
```

---

## 4. Evidence Decay

### 4.1 Recency Weighting

Evidence is not eternal. An agent that performed well 6 months ago may have changed (model update, prompt change) or the domain may have changed (major refactor). Following the trust scoring brainstorm's "exponential decay with half-life of 30 days":

```
weight(event) = e^(-lambda * age_days)
where lambda = ln(2) / half_life_days
```

With `half_life_days = 30`:
- 1-day-old evidence: weight 0.977
- 7-day-old evidence: weight 0.851
- 30-day-old evidence: weight 0.500
- 60-day-old evidence: weight 0.250
- 90-day-old evidence: weight 0.125

Weighted success rate:

```
success_rate_weighted(agent, domain, action) =
  sum(weight(e) * outcome(e) for e in evidence(agent, domain, action))
  / sum(weight(e) for e in evidence(agent, domain, action))
```

### 4.2 Domain Drift (Staleness)

An agent that hasn't touched a domain in 90+ days has **stale authority**. The domain may have changed structurally (new modules, different patterns, refactored APIs). Stale authority degrades:

```
staleness_factor(agent, domain) =
  if days_since_last_observation(agent, domain) < 90: 1.0
  elif days_since_last_observation(agent, domain) < 180: linear_decay(90, 180, 1.0, 0.5)
  else: 0.5  # Floor: stale authority never drops below 50% of earned level
```

**Effect**: A stale agent keeps its tier but with reduced effective authority. If the agent's effective score drops below the demotion threshold, the staleness triggers a formal demotion. The agent must re-earn authority with fresh observations.

**Staleness is distinct from decay**: Decay reduces the weight of old evidence in the success rate calculation. Staleness is a separate multiplier that penalizes inactivity regardless of historical performance. An agent with a perfect record 6 months ago still faces staleness — the record was perfect, but the domain has changed.

### 4.3 Evidence Expiry

Evidence older than `max_evidence_age_days` (default: 365) is archived and excluded from authority calculations entirely. This bounds the computational cost of authority evaluation and prevents ancient history from anchoring scores.

Archived evidence remains queryable for audit purposes but does not contribute to promotion or demotion decisions.

---

## 5. Interspect Integration

### 5.1 Evidence Events Emitted

Interspect is the evidence backbone. Phase 4 authority requires six new evidence event types, extending the existing `finding_accepted`/`finding_discarded` types from the trust scoring brainstorm:

| Event Type | Emitted When | Fields | Source Hook |
|-----------|-------------|--------|------------|
| `authority_observation` | Agent completes an action in a domain | `agent_id, domain, action_class, outcome(success/failure), bead_id, session_id, details` | Bead close hook, commit hook |
| `authority_promotion` | Agent crosses promotion threshold | `agent_id, domain, from_class, to_class, evidence_refs[], threshold_snapshot` | Authority evaluator (patrol cycle) |
| `authority_demotion` | Agent crosses demotion threshold or critical trigger | `agent_id, domain, from_class, to_class, trigger(score_based/critical/staleness/manual), evidence_refs[]` | Authority evaluator or human CLI |
| `authority_override` | Human explicitly grants or revokes authority | `agent_id, domain, action_class, override_type(grant/revoke), reason, principal_id, expiry` | `mycroft authority grant/revoke` CLI |
| `authority_staleness` | Agent's domain authority becomes stale | `agent_id, domain, days_since_last, staleness_factor` | Authority evaluator (daily sweep) |
| `incident_attribution` | Agent action attributed to an incident | `agent_id, domain, action_class, incident_id, bead_id, severity, attribution_confidence` | Human via `mycroft incident attribute` |

### 5.2 Evidence Storage

Evidence events are stored in Interspect's existing JSONL pipeline with two storage tiers:

**Hot tier** (last 90 days): Interspect SQLite evidence table, indexed by `(agent_id, domain, action_class, timestamp)`. This is the query path for authority evaluation at dispatch time.

**Cold tier** (90-365 days): JSONL archive in `.interspect/evidence/authority/`. Queryable for audit but not consulted during dispatch. Authority evaluator reads hot tier only.

**Expiry** (>365 days): Moved to `.interspect/evidence/archive/`. Retained for compliance audit only.

### 5.3 Authority Evaluation Query

At dispatch time, the authority evaluator runs:

```sql
-- Hot path: can agent A perform action_class C in domain D?
SELECT
  COUNT(*) as total_observations,
  SUM(CASE WHEN outcome = 'success' THEN weight ELSE 0 END) / SUM(weight) as weighted_success_rate,
  MAX(timestamp) as last_observation,
  SUM(CASE WHEN outcome = 'success' AND rownum <= consecutive_window THEN 1 ELSE 0 END) as recent_consecutive_successes
FROM (
  SELECT *,
    EXP(-0.693 * (julianday('now') - julianday(timestamp)) / :half_life_days) as weight,
    ROW_NUMBER() OVER (ORDER BY timestamp DESC) as rownum
  FROM authority_observations
  WHERE agent_id = :agent_id
    AND domain GLOB :domain_pattern
    AND action_class = :action_class
    AND timestamp > datetime('now', '-' || :max_age_days || ' days')
)
```

This single query produces all inputs for both promotion and demotion evaluation. The authority evaluator then applies the threshold functions from Section 3 and emits `authority_promotion` or `authority_demotion` events as needed.

### 5.4 Canary Monitoring Integration

Interspect already has canary monitoring with a 20% regression threshold for routing overrides. Authority changes should follow the same canary pattern:

1. When an agent is promoted, enter a **canary period** (configurable, default 7 days at the new tier).
2. During canary, the agent operates at the new tier but with heightened monitoring: demotion thresholds are tightened by 10% (e.g., Commit demotion floor rises from 0.75 to 0.825).
3. If the agent survives the canary period without demotion, the tightened thresholds relax to normal.
4. If the agent fails during canary, it reverts to the previous tier and the canary failure is recorded as negative evidence.

This mirrors Interspect's existing canary system (baseline + sampling + regression threshold) applied to authority transitions instead of routing overrides.

---

## 6. Human Override

### 6.1 Explicit Grants and Revocations

The evidence pipeline handles the common case: authority earned through track record. But humans need escape hatches:

**Explicit grant** (`mycroft authority grant <agent> <domain> <action_class> --reason "..." [--expiry 30d]`):
- Immediately sets agent to specified authority level in domain
- Requires `reason` (recorded in Interspect as `authority_override` event)
- Optional `expiry`: authority reverts after duration if not sustained by evidence
- Does NOT bypass fleet-tier ceiling: `effective_authority = min(grant, fleet_ceiling)`

**Explicit revocation** (`mycroft authority revoke <agent> <domain> --reason "..."`):
- Immediately drops agent to Propose in domain
- Recorded as `authority_override` with `override_type=revoke`
- Agent must re-earn authority through evidence (no automatic restoration)
- Revocation overrides evidence-based score for 30 days (configurable cooldown)

**Temporary elevation** (`mycroft authority elevate <agent> <domain> <action_class> --duration 4h --reason "..."`):
- Time-boxed authority grant for specific situations (e.g., "let this agent deploy the hotfix")
- Auto-reverts after duration
- Recorded with full audit trail
- Does NOT count as evidence for future promotion (marked `transient=true`)

### 6.2 Reconciliation with Evidence Pipeline

Human overrides and evidence-based authority coexist through a priority system:

```
effective_authority(agent, domain) =
  if active_revocation(agent, domain):
    Propose  # Revocation wins unconditionally
  elif active_elevation(agent, domain):
    min(elevation_class, fleet_ceiling)  # Temporary elevation, capped
  elif active_grant(agent, domain) AND grant_not_expired:
    min(grant_class, evidence_class, fleet_ceiling)  # Grant is ceiling, not floor
  else:
    min(evidence_class, fleet_ceiling)  # Normal evidence-based authority
```

**Key design choice**: Explicit grants set a ceiling, not a floor. If an agent is granted Commit authority but evidence shows it should be at Execute, evidence wins (the lower of the two). This prevents "rubber-stamp grants" from bypassing the evidence system. The only way to force higher authority than evidence supports is `elevate` (which is time-boxed and audited).

Revocations are the exception: they override evidence unconditionally. A human who revokes authority is expressing a judgment that the evidence system has missed something. The 30-day cooldown before evidence can restore authority ensures the human's concern is addressed, not just out-waited.

### 6.3 Audit Trail

Every authority state change produces an Interspect event. The complete history of an agent's authority in a domain is reconstructable from the event log:

```
mycroft authority history <agent> [--domain <pattern>]

TIMESTAMP           DOMAIN              CLASS     TRIGGER          REASON
2026-03-01 09:00    internal/mycroft/** Propose   initial          cold start
2026-03-03 14:30    internal/mycroft/** Execute   evidence_promote 5 obs, 100% success
2026-03-10 10:15    internal/mycroft/** Commit    evidence_promote 15 obs, 93% success
2026-03-12 16:00    internal/mycroft/** Execute   evidence_demote  3 consecutive failures
2026-03-12 16:30    internal/mycroft/** Commit    human_grant      "root cause was infra, not agent"
2026-03-19 00:00    internal/mycroft/** Commit    grant_expired    30d expiry, evidence sustains at Commit
```

---

## 7. Synthesis: End-to-End Authority Lifecycle

Putting the pieces together, an agent's authority lifecycle in a domain follows this state machine:

```
                     ┌─────────────────────────────────────┐
                     │                                     │
                     ▼                                     │
┌──────────┐   evidence   ┌──────────┐   evidence   ┌──────────┐
│ Propose  │──────────────▶│ Execute  │──────────────▶│ Commit   │ ─── ...
│ (floor)  │   N=5,S=.80  │          │   N=15,S=.90 │          │
└──────────┘              └──────────┘              └──────────┘
     ▲                         ▲                         │
     │                         │                         │ S<.75 or
     │  critical               │  S<.60 or               │ 3 consecutive
     │  incident               │  3 consecutive           │ failures
     │                         │  failures                │
     │                         │                         ▼
     └─────────────────────────┴─────────── DEMOTION ◄───┘

     Human override:
       grant  ──▶  sets ceiling (evidence can be lower)
       revoke ──▶  forces Propose (30d cooldown)
       elevate ──▶ temporary, time-boxed, audited
```

**Every transition has an Interspect event as justification.** No authority change is unauditable. The threshold parameters are tunable per domain via YAML config. Demotion criteria are at least as well-specified as promotion criteria (and fire faster by design).

### 7.1 Phase 4 Minimal Implementation

For Phase 4 of the factory rollout (3 weeks), the minimal implementation is:

1. **Authority observation events**: Emit from bead close hook. Minimal: `agent_id, domain (from bead file paths), action_class (from bead type), outcome`.
2. **Threshold evaluation**: Run during Mycroft patrol cycle. Query hot-tier evidence, apply threshold functions, emit promotion/demotion events.
3. **Dispatch integration**: In route.md agent selection, check `effective_authority(agent, domain_of_bead) >= required_action_class`. Single function call, synchronous, fail-closed.
4. **Human override CLI**: `mycroft authority grant/revoke/history`. Writes override events to Interspect.
5. **Thresholds config**: `thresholds.yaml` with defaults and per-domain overrides.

Deferred to Phase 5+: canary period for promotions, cross-project authority aggregation, staleness sweep automation, Autarch TUI authority dashboard.

---

## Sources

- [Argo Rollouts Analysis Features](https://argo-rollouts.readthedocs.io/en/stable/features/analysis/)
- [Spinnaker Canary Best Practices](https://spinnaker.io/docs/guides/user/canary/best-practices/)
- [LaunchDarkly Progressive Rollouts](https://launchdarkly.com/docs/home/releases/progressive-rollouts)
- [LaunchDarkly Guarded Rollouts](https://www.gocodeo.com/post/progressive-delivery-with-launchdarkly-best-practices-and-benefits)
- [Spinnaker Canary Configuration](https://spinnaker.io/docs/guides/user/canary/config/canary-config/)
- [AI Agent Identity & Zero-Trust 2026 Playbook](https://medium.com/@raktims2210/ai-agent-identity-zero-trust-the-2026-playbook-for-securing-autonomous-systems-in-banks-e545d077fdff)
- [TrustBench: Real-Time Trust Verification for Agentic Actions](https://arxiv.org/html/2603.09157)
- [Recency-Weighted Scoring Explained](https://customers.ai/recency-weighted-scoring)
- [Dynamic Risk Scoring for AML](https://www.flagright.com/post/best-dynamic-risk-scoring-algorithm-for-aml-fraud)
- [Concept Drift to Model Degradation Survey](https://www.sciencedirect.com/science/article/pii/S0950705122002854)
- [NIST AI Agent Standards Initiative](https://www.joneswalker.com/en/insights/blogs/ai-law-blog/nists-ai-agent-standards-initiative-why-autonomous-ai-just-became-washingtons.html)

<!-- flux-research:complete -->
