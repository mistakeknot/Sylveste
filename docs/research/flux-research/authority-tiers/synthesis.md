# Authority Tiers for AI Software Factories: Synthesis Report

**Date:** 2026-03-19
**Status:** Complete synthesis from 5 specialist agents
**Audience:** Phase 4 implementation team (architecture, safety review, dispatch integration)

---

## Executive Summary

Domain-scoped authority for AI agents requires a **two-layer hybrid model**: a fleet-level ceiling (Mycroft T0-T3) combined with fine-grained domain authority grants that agents earn through evidence. This synthesis draws from distributed systems (RBAC, capability-based security, XACML), progressive delivery (Argo Rollouts, Spinnaker), and real-world credentialing (military, medical, aviation) to produce:

1. **Concrete schema:** Three Dolt tables (`authority_grants`, `authority_evidence`, `authority_audit`) plus YAML authority.owners file for human-readable governance
2. **Evidence thresholds:** Asymmetric promotion/demotion gates (0.80 success for Execute, 0.90 for Commit) with exponential decay and domain staleness penalties
3. **Safety invariants:** Five checkable predicates (no self-promotion, delegation ceiling, action-time validation, audit completeness, human halt supremacy)
4. **Dispatch integration:** Two enforcement points (pre-claim check + post-execution audit) in route.md with fail-closed/fail-open per domain
5. **Phase 4 minimal:** 80-line shell library + YAML config, shadow mode rollout

---

## 1. Recommended Authority Model: Hybrid RBAC + Capability with ABAC Extension Point

### Why This Model?

The research unanimously converges on a **ceiling model** where:
- **Fleet tier (RBAC):** Mycroft T0-T3 sets the upper bound on what ANY agent can do (T0=propose only, T3=autonomous deploy/spend)
- **Domain authority (capability):** Agents earn (domain_pattern, action_class, evidence) grants within their fleet tier ceiling
- **Human overrides:** Principals can grant/revoke/elevate at any time, with full audit trail
- **ABAC extension point:** Phase 5+ can add condition evaluation (e.g., `if blast_radius <= "moderate"`) without schema changes

### Rationale from Credentialing Analogues

This mirrors:
- **Military:** Pay grade (T0-T3) vs. specialty code (domain). A Colonel still cannot direct fire missions in an unfamiliar branch.
- **Medicine:** MD license vs. hospital privileges. Privileging committees grant procedure-specific authority with continuous OPPE monitoring.
- **Aviation:** Pilot certificate level vs. type rating per aircraft. An ATP needs separate A320 rating even with 10K Boeing hours.

**Critical distinction:** Authority over people (fleet tier) ≠ authority in a domain (specialization). Moving between domains requires independent qualification even at high general rank.

---

## 2. Concrete Schema: Three Tables + One Config File

### 2.1 Authority Grants Table (Dolt: `authority_grants`)

Primary table storing all active and historical authority grants:

```sql
CREATE TABLE authority_grants (
  grant_id        VARCHAR(36) PRIMARY KEY,  -- UUID v7 (time-sortable)
  agent_id        VARCHAR(64) NOT NULL,     -- fleet-registry key: "fd-architecture", "clavain-sprint"
  domain_pattern  VARCHAR(256) NOT NULL,    -- glob: "interverse/interspect/**", "core/**", "*.go"
  action_class    ENUM('propose','execute','commit','deploy','spend') NOT NULL,
  tier_floor      TINYINT NOT NULL DEFAULT 0,  -- minimum Mycroft tier required (0-3)
  granted_at      TIMESTAMP NOT NULL,
  granted_by      VARCHAR(64) NOT NULL,     -- "authority.owners:L42", "interspect:auto-promote", "principal:mk"
  expires_at      TIMESTAMP NULL,           -- NULL = no expiry (human grants). Auto: 90d default.
  revoked_at      TIMESTAMP NULL,           -- soft delete. NULL = active.
  revoked_by      VARCHAR(64) NULL,
  revoke_reason   VARCHAR(256) NULL,
  conditions      JSON NULL,                -- Phase 5+: {"min_test_coverage": 0.8}

  INDEX idx_lookup (agent_id, action_class, revoked_at),
  INDEX idx_domain (domain_pattern),
  INDEX idx_expiry (expires_at)
);
```

**Design rationale:**
- Time-sortable UUID (v7) enables efficient range queries for audit
- `granted_by` field distinguishes static grants (authority.owners) from evidence-based (interspect) from manual (principal)
- `tier_floor` enforces that a grant only applies to agents at that fleet tier or above
- NULL expiry for human grants (indefinite until revoked); auto-grants expire at 90d default

### 2.2 Evidence References Table (Dolt: `authority_evidence`)

Tracks the evidence chain that justified each grant (for auditability and learned-from analysis):

```sql
CREATE TABLE authority_evidence (
  evidence_id     VARCHAR(36) PRIMARY KEY,
  grant_id        VARCHAR(36) NOT NULL REFERENCES authority_grants(grant_id),
  evidence_type   ENUM('bead_completion','gate_pass','incident','human_override',
                       'review_accepted','review_rejected') NOT NULL,
  evidence_ref    VARCHAR(256) NOT NULL,    -- bead ID, Interspect event_id, or "principal:mk:2026-03-19"
  evidence_at     TIMESTAMP NOT NULL,
  outcome         ENUM('positive','negative','neutral') NOT NULL,
  weight          DECIMAL(3,2) NOT NULL DEFAULT 1.00,  -- recency-decayed weight
  notes           VARCHAR(512) NULL,

  INDEX idx_grant (grant_id, evidence_at DESC)
);
```

**Design rationale:**
- Links each grant to the observable facts that justified it
- `weight` field stores pre-computed exponential decay factor (λ = ln(2)/30d) for fast scoring
- Enables post-hoc discovery of "which evidence was wrong?" if an agent misbehaves

### 2.3 Audit Trail Table (Dolt: `authority_audit`)

Every authority decision logged for compliance and debugging:

```sql
CREATE TABLE authority_audit (
  audit_id        VARCHAR(36) PRIMARY KEY,
  timestamp       TIMESTAMP NOT NULL,
  agent_id        VARCHAR(64) NOT NULL,
  action_class    VARCHAR(16) NOT NULL,
  domain_tested   VARCHAR(256) NOT NULL,
  bead_id         VARCHAR(64) NULL,
  decision        ENUM('allow','deny','escalate') NOT NULL,
  grant_id_used   VARCHAR(36) NULL,
  mycroft_tier    TINYINT NOT NULL,
  effective_tier  TINYINT NOT NULL,         -- min(mycroft_tier, grant ceiling)
  resolution_ms   DECIMAL(6,2) NOT NULL,

  INDEX idx_agent_time (agent_id, timestamp DESC),
  INDEX idx_bead (bead_id)
);
```

**Design rationale:**
- Records every check: allow, deny, escalate paths
- `resolution_ms` enables SLO monitoring (sub-millisecond target)
- `effective_tier` is the computed min — helps debug composition

### 2.4 Fleet Registry Extension

Add two fields to each agent entry in fleet-registry.yaml:

```json
{
  "mycroft_tier": {
    "type": "integer",
    "minimum": 0,
    "maximum": 3,
    "description": "Fleet-level trust tier (T0=observe, T3=autonomous)"
  },
  "authority_scope": {
    "type": "string",
    "enum": ["narrow", "moderate", "broad"],
    "description": "Default domain breadth: narrow=single module, broad=monorepo"
  }
}
```

Example:

```yaml
agents:
  fd-architecture:
    source: interflux
    category: review
    mycroft_tier: 1          # Can propose, not execute
    authority_scope: broad   # Reviews across entire monorepo
```

### 2.5 Authority.owners File (Human-Readable Source of Truth)

Version-controlled CODEOWNERS-style file at monorepo root. Last-match-wins semantics:

```
# authority.owners — domain-scoped authority grants
# Format: <glob> <action_class> <agent_id> [<agent_id>...]
# Last matching rule wins.

# Default: all agents can propose anywhere
**                          propose   *

# Interflux agents execute in their domains
interverse/interflux/**     execute   fd-architecture fd-correctness fd-quality

# Interspect agent commits within its plugin
interverse/interspect/**    commit    interspect-agent

# Core kernel: narrow authority
core/intercore/**           propose   *
core/intercore/**           commit    clavain-sprint  # only if T3

# Deploy and spend are narrow
**                          deploy    mycroft-deploy
@budget:*                   spend     mycroft-budget
```

**Key properties:**
- Uses CODEOWNERS syntax (developers already understand `**/*.go`)
- Glob patterns match file paths and bead labels (prefix with `@`)
- Parseable into `authority_grants` table via `authority-sync` job
- Living document: changes are commits, tracked in git history

---

## 3. Fleet Tier × Domain Authority Interaction: Ceiling Model

### The Three Composition Strategies

| Model | Behavior | Risk |
|-------|----------|------|
| **Ceiling** | `effective = min(fleet_tier_allows, domain_grant_allows)` | Overly constraining for narrow domains? |
| **Floor** | `effective = max(fleet_tier_allows, domain_grant_allows)` | Defeats fleet safety |
| **Independent** | Fleet and domain checked separately, both must pass | Complex, two lookups |

### Recommendation: Ceiling with Human Exception

**Default rule:**
```
effective_action(agent, domain, action_class) =
  IF rank(action_class) > tier_ceiling(agent.mycroft_tier):
    DENY
  ELIF has_domain_grant(agent, domain, action_class):
    ALLOW
  ELSE:
    DENY
```

Where `tier_ceiling`:
- T0 → no action (observe only)
- T1 → propose
- T2 → execute, commit
- T3 → deploy, spend

**Escape hatch:** A P1 (human) can issue a time-limited exception that elevates domain authority above fleet ceiling, fully logged as authority event.

**Why:** This prevents the most dangerous failure: a domain-expert agent with poor general judgment gaining Deploy/Spend authority at T1. An exception preserves safety while allowing humans to override.

---

## 4. Evidence Thresholds: From Argo Rollouts to Authority Promotion

### 4.1 Evidence Classes (Ranked by Signal Strength)

| Class | Signal | Weight | Source |
|-------|--------|--------|--------|
| **Incident attribution** | Agent action caused revert/breakage | -4x (critical) | Interspect incident events |
| **Human override** | Human rejected agent proposal | -2x | Interspect `dispatch_rejected` |
| **Successful deployment** | Change merged, tests pass, 24h no rollback | +1x | Bead closure, git history |
| **Review acceptance** | Agent review findings accepted by human | +0.5x | Interspect `finding_accepted` |
| **Rejected proposal** | Agent proposed action rejected (prevented harm) | -0.5x | Interspect `proposal_rejected` |

**Evidence granularity:** Must be scoped to (agent, domain, action_class) triples. Success at test-writing in `internal/mycroft/` ≠ refactor authority in `core/intercore/`.

### 4.2 Promotion Thresholds (Asymmetric by Design)

All of these must be satisfied to promote from tier A to A+1:

| Transition | N_min | S_min | C_min | T_min | O_max |
|-----------|-------|-------|-------|-------|-------|
| Propose → Execute | 5 | 0.80 | 3 consecutive | 1 day | 0.30 override rate |
| Execute → Commit | 15 | 0.90 | 5 consecutive | 7 days | 0.15 |
| Commit → Deploy | 30 | 0.95 | 10 consecutive | 14 days | 0.05 |
| Deploy → Spend | 50 | 0.95 | 15 consecutive | 30 days | 0.05 |

**Rationale for asymmetry:** Lower tiers promote faster (smaller blast radius). A bad proposal costs review time; a bad Deploy costs production.

**Interaction with fleet tier:** An agent at T1 cannot hold domain authority above Execute regardless of evidence. Fleet tier is the ceiling; domain authority is earned within that ceiling.

### 4.3 Demotion Triggers (Fast and Graduated)

**Immediate demotion (critical metric override):**
- Any incident attributed to agent in domain → drop to Propose
- Security violation (credential exposure) → drop to Propose + human re-grant required
- 3 consecutive failures in 24h → drop one tier (matches Mycroft circuit breaker)

**Gradual demotion (score-based):**

| Tier | Success Floor (demote <) | Override Rate Ceiling |
|-----|--------------------------|----------------------|
| Execute | 0.60 | 0.40 |
| Commit | 0.75 | 0.25 |
| Deploy | 0.85 | 0.10 |
| Spend | 0.90 | 0.10 |

**Hysteresis band:** Promotion to Commit at 0.90, demotion at 0.75. An agent at 0.82 holds Commit but doesn't promote to Deploy. Prevents oscillation.

### 4.4 Evidence Decay (Recency Weighting)

Evidence is weighted by age with exponential decay:

```
weight(event) = e^(-λ * age_days)   where λ = ln(2) / half_life_days
```

With 30-day half-life:
- 1 day old: weight 0.977
- 7 days: weight 0.851
- 30 days: weight 0.500
- 90 days: weight 0.125

**Weighted success rate:**
```
success_rate = Σ(weight(e) * outcome(e)) / Σ(weight(e))
```

### 4.5 Domain Staleness

An agent that hasn't touched a domain in 90+ days has **stale authority**:

```
staleness_factor =
  if days_inactive < 90: 1.0
  if 90 ≤ days_inactive < 180: linear_decay(1.0, 0.5)
  if days_inactive ≥ 180: 0.5 (floor)
```

**Effect:** Stale authority doesn't auto-demote but degrades in scoring. If combined with evidence decay, stale + bad-luck dip may trigger formal demotion. Agent must re-earn with fresh observations.

### 4.6 Configuration

Thresholds tunable per domain without code changes:

```yaml
# .clavain/authority/thresholds.yaml
defaults:
  promote:
    execute:  { n_min: 5, success_rate: 0.80, consecutive: 3, days: 1, override_ceiling: 0.30 }
    commit:   { n_min: 15, success_rate: 0.90, consecutive: 5, days: 7, override_ceiling: 0.15 }
    deploy:   { n_min: 30, success_rate: 0.95, consecutive: 10, days: 14, override_ceiling: 0.05 }
  demote:
    execute:  { success_floor: 0.60, override_ceiling: 0.40 }
    commit:   { success_floor: 0.75, override_ceiling: 0.25 }
    deploy:   { success_floor: 0.85, override_ceiling: 0.10 }
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

## 5. Safety Invariants: Five Checkable Predicates

These are non-negotiable constraints that must hold at all times:

### INV-1: Authority Monotonicity (No Self-Promotion)

```
∀ agent a, action x modifying a.authority:
  source_principal(x) < agent_principal_level(a)
```

**English:** An agent cannot increase its own authority. Promotion requires a strictly higher principal.

**Implementation:** `authority_store.write()` validates `event.source_principal < event.target_agent.principal_level`.

### INV-2: Delegation Ceiling (No Authority Amplification)

```
∀ parent p, child c spawned by p:
  effective_authority(c, domain, action) ≤ effective_authority(p, domain, action)
```

**English:** A subagent never exceeds its parent's authority.

**Implementation:** At spawn: `dispatch_record.authority_ceiling = parent.effective_authority`. At action: `effective_auth(c) = min(dispatch_ceiling, c.domain_authority)`.

### INV-3: Action-Time Validation (No Stale Authority)

```
∀ agent a, action x at time t:
  authority_check(a, x) reads authority_store at time t (not cached state)
```

**English:** Authority is validated at action time, not dispatch time. If authority revoked between dispatch and action, the action fails.

**Implementation:** All write-path actions call `authority_store.check_current(agent_id, domain, action_class)` synchronously. No multi-second caching.

### INV-4: Audit Completeness (No Silent Authority Changes)

```
∀ authority decision d (grant, revoke, check, exception):
  ∃ event e in kernel_event_log where e.describes(d) ∧ e.hash_chain_valid()
```

**English:** Every authority decision produces a hash-chain-linked kernel event.

**Implementation:** Authority store wrapper emits event for every read/write. Periodic `audit_verify()` walks chain for gaps.

### INV-5: Human Halt Supremacy (Unconditional Override)

```
∀ agent a:
  human_halt_command() → a.stops() within T seconds
  ∧ ¬∃ action capable of disabling human_halt_command
```

**English:** Human halt stops all agents within T seconds (e.g., 30s). No agent action can prevent halt.

**Implementation:** Halt is a kernel-level sentinel (not agent-mediated). Agents poll it; only P1 principals write it.

---

## 6. Dispatch Integration: Two Enforcement Points

### 6.1 Enforcement Point 1: Pre-Claim Authority Check (Synchronous)

Insert in route.md Step 3/4 after bead metadata gathering, before claim-bead pattern:

```bash
authority_check "$agent_id" "$bead_id" --mode enforce
case $? in
  0) ;;  # ALLOW — proceed to claim
  1) continue ;;  # DENY — skip to next candidate
  2) degrade_to_propose ;;  # DEGRADE — operate at reduced tier
esac
```

**Decision latency:** <10ms (local YAML lookup + glob match).

**Decision record:** JSON logged to `.clavain/authority/decisions.jsonl` and emitted to Interspect as `authority_decision` event.

**Fail modes per domain:**
- `core/*, security/*`: fail-closed (no authority = blocked until restored)
- `interverse/*, docs/*`: fail-open (lack of authority file defaults to fleet tier)

### 6.2 Enforcement Point 2: Post-Execution Audit (Async)

After bead completion, compare actual files modified against agent's domain authority:

```bash
authority_post_audit "$bead_id" "$agent_id"
# Outputs:
#   exit 0 — all files within scope
#   exit 1 — out-of-scope writes detected
```

On out-of-scope detection:
1. Mark bead: `bd set-state "$bead_id" "authority_violation=true"`
2. List violated paths: `bd set-state "$bead_id" "authority_violation_paths=core/intermute/foo.go,..."`
3. Emit Interspect evidence event (feeds demotion pipeline)
4. Escalate to human review before merge

### 6.3 Authority Decision Record

Every authority check logs:

```json
{
  "timestamp": "2026-03-19T14:32:05Z",
  "agent_id": "grey-area",
  "bead_id": "Demarch-4f2a",
  "domain": "core/intercore",
  "action": "claim",
  "decision": "allow",
  "reason": "agent has Execute authority for core/intercore",
  "authority_source": "authority.yaml:12",
  "mycroft_tier": "T2",
  "enforcement_mode": "enforce",
  "fallback_applied": false,
  "resolution_ms": 2.4,
  "session_id": "abc123"
}
```

On deny, additional fields:

```json
  "deny_reason": "agent grey-area has no authority for security/*",
  "deny_action": "skip",
  "next_candidate": "Demarch-4f2b"
```

---

## 7. Phase 4 Minimal Implementation (3 Weeks)

### What to Build (Minimal, Integrated Path)

**Week 1: Baseline + Schema**
1. Add `mycroft_tier` and `authority_scope` to fleet-registry.yaml + schema
2. Create Dolt tables: `authority_grants`, `authority_evidence`, `authority_audit`
3. Create `authority.owners` file with initial mappings
4. Implement `clavain-cli authority-check` (synchronous check against Dolt)

**Week 2: Dispatch Integration**
1. Create `lib-authority.sh` (80-line function library)
2. Insert pre-claim authority check into route.md Step 3/4
3. Emit authority decision events to Interspect
4. Deploy in shadow mode (log but don't block)

**Week 3: Threshold Logic + Config**
1. Create `thresholds.yaml` with defaults + per-domain overrides
2. Implement evidence query SQL (hot-path: success_rate, consecutive_successes)
3. Add `mycroft authority grant/revoke/history` CLI commands
4. Validation: run 2-3 full sprints in shadow, audit decision log

### What to Defer (Phase 5+)

- Runtime file-path enforcement (post-execution audit only)
- Automatic promotion/demotion (YAML edit only)
- Mycroft T2 integration (domain authority filter when T2 implemented)
- Challenge-response (re-engagement protocol)
- Canary period for promotions
- Per-action authority (action class distinctions)

### Implementation Files: Three Artifacts

**File 1: `os/Clavain/scripts/lib-authority.sh` (~80 lines)**
Shell function library with:
- `authority_check(agent_id, bead_id) → ALLOW|DENY|DEGRADE`
- `authority_resolve_domain(bead_id) → domain`
- `authority_post_audit(bead_id, agent_id) → OK|VIOLATION`
- Minimal error handling, fail-open defaults

**File 2: `.clavain/authority/authority.yaml` (project config)**
YAML configuration:
- Version, mode (shadow/enforce)
- Per-agent × domain mappings
- Per-domain fail modes
- Expires after 365 days of stale entries

**File 3: Diff to `os/Clavain/commands/route.md` (<20 lines)**
Two insertions:
- Pattern: `authority-check` (new, before claim-bead)
- Pattern reference in Step 3 item 6 and Step 4c item 3

---

## 8. Top 5 Actionable Recommendations

### 1. Start in Shadow Mode (Week 1 → Week 4)

Deploy with `mode: shadow` in authority.yaml. Authority checks run on every claim, log decisions, but never block. This lets you:
- Collect baseline decision logs (what would have been denied?)
- Tune thresholds based on production traffic
- Identify false-deny edge cases (e.g., cross-module changes)
- Build team confidence before enforcement

Switch to `mode: enforce` for high-confidence domains (core/*, security/*) by Week 3, others in Week 4.

### 2. Use CODEOWNERS Pattern (Not a New Syntax)

The authority.owners file uses glob patterns developers already know (`**/*.go`, `os/Clavain/**`). This:
- Lowers training barrier
- Makes authority visible in `git log authority.owners`
- Enables pull-request workflow for authority changes
- Integrates with existing GitHub CODEOWNERS if needed

Don't invent a new DSL. Mirror GitHub's syntax.

### 3. Evidence Must Be Independent, Never Self-Authored

The attack vector: agent writes "I completed this task successfully" to its own evidence record, auto-promotes itself.

**Enforcement:**
- Every evidence record carries `source_principal` field
- Self-authored evidence (P4/P5 agent) is weighted differently from independent evidence (P1 human, P3 Mycroft, cross-agent review)
- Promotion requires at least one evidence item from P3 or above
- Hash-chain audit trail prevents retroactive alteration

**Don't allow:** An agent's bead self-assessment as promotion evidence. Only human review, Interspect signals, or cross-agent review count.

### 4. Ceiling Model with Human Exception (Not Floor or Orthogonal)

Default rule: `effective_authority = min(fleet_tier_ceiling, domain_authority)`.

This prevents the worst case: a T1 (supervised) agent earning expert domain authority and then self-promoting to Deploy.

Escape hatch: A P1 human can grant a time-limited exception that elevates domain authority above fleet ceiling. This is:
- Fully logged as an authority event with principal attribution
- Time-bounded (N days or N actions)
- Revocable by any P1
- Visible in dashboards

This preserves safety while allowing overrides when the ceiling is demonstrably wrong (e.g., "this agent is genuinely excellent in this domain; fleet tier cap is outdated").

### 5. Authority Demotion Fires Faster Than Promotion (Asymmetric by Design)

Promotion to Commit: 0.90 success rate + 5 consecutive successes + 7+ days.
Demotion from Commit: 0.75 success rate OR 3 failures in 24 hours.

This asymmetry (0.75-0.90 hysteresis) mirrors:
- Argo Rollouts canary analysis (75th percentile failure threshold vs. 95th success target)
- Aviation recurrent training (failure triggers immediate 709 reexam)
- Medical FPPE (triggered when OPPE surfaces concern)

**Why:** Promotion should be conservative (high confidence needed to grant power). Demotion should be fast (safety breach detected quickly). The gap prevents oscillation while protecting against slow degradation.

---

## 9. Authority Resolution Algorithm (Complete Picture)

```
resolve_authority(agent_id, bead_id, action_class) → ALLOW | DENY | ESCALATE

Step 1: Fleet tier ceiling check (O(1) in-memory)
  tier = fleet_registry[agent_id].mycroft_tier
  IF rank(action_class) > tier_ceiling(tier):
    return DENY (fleet tier caps it)

Step 2: Resolve domains from bead (O(1) cached)
  domains = bead_changed_paths(bead_id) + bead_labels(bead_id)
  IF domains empty:
    domains = ["**"]  (unconstrained bead needs broadest grant)

Step 3: Find matching grants (O(k log n) — k domains, n grants)
  matching_grants = []
  FOR domain IN domains:
    grants = query("SELECT * FROM authority_grants
                   WHERE agent_id = ?
                   AND action_class >= ?  (subsumption)
                   AND revoked_at IS NULL
                   AND expires_at > now()
                   AND domain_pattern GLOB ?")
    matching_grants += grants

Step 4: Evaluate conditions (Phase 5+)
  FOR grant IN matching_grants:
    IF grant.conditions NOT NULL AND NOT evaluate_conditions(grant, bead_id):
      matching_grants.remove(grant)

Step 5: Coverage check — ALL domains must be covered
  uncovered = [d for d in domains if NOT any(g.pattern matches d for g in matching_grants)]
  IF uncovered empty:
    best_grant = most_specific_match(matching_grants)
    log_audit(agent_id, decision="allow", grant_id=best_grant.id)
    return ALLOW

Step 6: Partial coverage → escalate
  IF matching_grants not empty AND uncovered not empty:
    log_audit(agent_id, decision="escalate", uncovered_domains=uncovered)
    return ESCALATE

Step 7: No coverage → deny
  log_audit(agent_id, decision="deny", reason="no_matching_grants")
  return DENY
```

**Complexity:** Sub-millisecond. All data in local Dolt, no external service calls.

---

## 10. Cross-Domain Patterns from Research

### From Progressive Delivery (Argo Rollouts, Spinnaker, LaunchDarkly)

- **Multi-stage rollouts:** T0 shadow (0%) → T1 canary (5%) → T2 progressive (50%) → T3 full (100%)
- **Metric gates at each stage:** Promotion requires success_rate ≥ threshold for time period T
- **Automatic rollback:** Demotion fires faster than promotion (asymmetric thresholds)
- **Critical metric override:** Certain failures bypass scoring and trigger immediate halt

**Applied to Demarch:** Authority stages (Propose → Execute → Commit → Deploy → Spend) with evidence gates, exponential decay, and critical incident triggers.

### From Medical Credentialing (OPPE/FPPE)

- **Continuous background monitoring (OPPE):** Every invocation feeds metrics (error rate, latency, correction frequency)
- **Focused review on signal (FPPE):** When OPPE surfaces concern, activate heightened scrutiny
- **Graduated escalation:** Background monitoring → focused review → restriction → revocation
- **Emergency override (summary suspension):** Immediate removal on imminent safety threat

**Applied to Demarch:** Authority audit table (OPPE-equivalent), demotion triggers (FPPE-equivalent), incident escalation to revocation.

### From Military (Pay Grade vs. Specialty)

- **General authority ≠ domain authority:** Colonel outranks Captain everywhere; neither can direct fire missions outside their specialty
- **Specialty transfer requires requalification:** Moving from Infantry to Logistics requires domain-specific training even at high rank
- **Skill levels within specialty:** AFSC system has journeyman/craftsman/superintendent levels — progression couples time-in-grade with demonstrated proficiency

**Applied to Demarch:** Fleet tier (pay grade) vs. domain authority (specialty), requalification on domain change, action-class tiers within domain.

---

## 11. Open Questions for Phase 5+

1. **Authority decay on model updates.** When Anthropic ships a new model, should earned authority partially decay (with floor) or reset? Exponential or linear?

2. **Cross-domain authority composition.** If Agent A has Commit in `core/` and Execute in `interverse/`, and bead spans both, effective authority = min() across domains?

3. **Authority for non-code actions.** How do Propose/Execute/Commit/Deploy/Spend map to documentation, bead state, Interspect config changes?

4. **Collusion detection sensitivity.** How many cross-domain coordination events = signal vs. normal multi-agent work? Avoiding false-positive cascade.

5. **Hidden metric rotation.** How often should Interspect's hidden monitoring thresholds rotate to prevent agent optimization?

---

## 12. Summary Table: Five Agents Converged On

| Dimension | Finding | Confidence |
|-----------|---------|------------|
| **Model choice** | Hybrid RBAC (fleet tier) + capability (domain grants) + ABAC extension | High (all 5 agents) |
| **Composition rule** | Ceiling: `effective = min(fleet_tier_allows, domain_grant_allows)` | High (schema, evidence, multiagent, dispatch agree) |
| **Threshold asymmetry** | Promotion 0.90 success, demotion 0.75 success (canary analysis parallel) | High (evidence-thresholds + progressive-delivery patterns) |
| **Evidence independence** | No self-authored promotion evidence (requires P3+ principal) | High (multiagent threat models, medical/aviation parallels) |
| **Dispatch enforcement** | Two points: pre-claim (sync) + post-execution (async audit) | High (dispatch-integration + cloud IAM patterns) |
| **Minimal Phase 4** | 80-line shell lib + YAML config, shadow mode rollout | High (schema designer, dispatch implementer agree on scope) |
| **Audit completeness** | Hash-chain events for every decision (no silent changes) | High (multiagent corrigibility, medical/aviation parallels) |
| **Staleness penalty** | 90+ days without activity → decay, 180+ → floor 0.5x effective authority | Medium (evidence-thresholds + aviation currency model) |

---

## Sources (Aggregated)

**Schema & Access Control:**
- RBAC/ABAC/Capability security: Auth0, CloudMatos, Wikipedia, Cerbos
- CODEOWNERS: GitHub Docs
- XACML: Oracle, Plurilock, Wikipedia

**Progressive Delivery:**
- Argo Rollouts: official documentation
- Spinnaker/Kayenta: official documentation
- LaunchDarkly: official + community guides

**Credentialing Analogues:**
- Military: Oak and Liberty, Air Force, Army HRC
- Medical: Joint Commission, StatPearls, symplr, Courtemanche
- Aviation: American Flyers, FAA, AOPA

**AI Safety & Multi-Agent:**
- TRiSM: arXiv:2506.04133
- Multi-agent risks: arXiv:2502.14143
- Corrigibility: arXiv:2506.03056, MIRI, OpenReview
- SEAgent (MAC for LLM): arXiv:2601.11893
- OpenAI Model Spec, Knight Institute, 2025 AI Agent Index
- Prompt injection: Lakera, OWASP
- AuditableLLM: MDPI Electronics
- Privilege escalation: The Hacker News (2026)

---

## Appendix: Concrete Example Walkthrough

**Scenario:** Agent `grey-area` (T1 fleet tier, Interflux research agent) claims bead Demarch-4f2a which touches `interverse/interflux/analysis/**` and `docs/investigation/**`.

```
resolve_authority("grey-area", "Demarch-4f2a", "execute"):

Step 1: Fleet tier ceiling
  grey-area.mycroft_tier = 1 → can do up to "execute"
  action_class = "execute" ≤ ceiling ✓

Step 2: Resolve domains
  bead_changed_paths = ["interverse/interflux/analysis/foo.go", "docs/investigation/report.md"]
  domains = ["interverse/interflux/**", "docs/**"]

Step 3: Find matching grants
  Query authority_grants:
    WHERE agent_id = "grey-area"
      AND action_class >= "execute"
      AND domain_pattern GLOB "interverse/interflux/**" ✓ → found: execute in interflux
    WHERE agent_id = "grey-area"
      AND action_class >= "execute"
      AND domain_pattern GLOB "docs/**" ✓ → found: execute in docs

Step 4: No conditions (Phase 5+)

Step 5: Coverage check
  domains = ["interverse/interflux/**", "docs/**"]
  matching_grants cover both ✓

Step 6: Return ALLOW
  log_audit(agent="grey-area", decision="allow",
            grant_id="grant_12345", domains_covered=2, resolution_ms=1.8)
```

Now grey-area claims the bead and works. After completion:

```
authority_post_audit("Demarch-4f2a", "grey-area"):
  actual_paths = ["interverse/interflux/analysis/foo.go", "docs/investigation/report.md"]
  authorized_patterns = ["interverse/interflux/**", "docs/**"]

  ✓ All paths covered by authorization
  → exit 0, no audit event emitted
```

**Contrast: If bead had touched core/intercore:**

```
authority_post_audit("Demarch-4f2a", "grey-area"):
  actual_paths = ["interverse/interflux/analysis/foo.go",
                  "docs/investigation/report.md",
                  "core/intercore/kernel.go"]  ← out of scope!

  → exit 1, quarantine bead, emit Interspect evidence event
  → Demotion pipeline triggered (accumulating violations)
```

---

**End of synthesis. Full audit tables, code samples, and integration guide in Phase 4 implementation docs.**

