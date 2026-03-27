# Authority Schema Design: Per-Agent Domain-Scoped Authority Tiers

**Date:** 2026-03-19
**Agent:** fd-authority-schema-design (distributed systems architect, IAM schema)
**Context:** Phase 4 of AI factory orchestration brainstorm — graduated authority earned through evidence
**Inputs:** brainstorm doc, fleet-registry.yaml, route.md, Interspect memory, fleet-registry.schema.json

---

## 1. Access Control Model Selection: RBAC vs ABAC vs Capability-Based

### The Lookup Triple

Every authority decision resolves: **can agent A perform action X in domain D?** This is the (agent_id, domain, action_class) triple. The model must answer this at dispatch time with sub-millisecond overhead (route.md already chains 5+ shell calls in Step 2).

### Model Comparison for Agent x Domain x Action

| Model | Strengths for Sylveste | Weaknesses | Verdict |
|-------|----------------------|------------|---------|
| **RBAC** (role-based) | Simple. Fleet registry already has `roles` and `category` fields. Maps cleanly to T0-T3 tiers. | Roles are coarse — "reviewer" doesn't distinguish "can review intercore" from "can review interflux." Per-domain granularity requires role explosion (agent x domain = hundreds of roles). | Necessary but insufficient alone. |
| **ABAC** (attribute-based) | Dynamic. Can evaluate `agent.success_rate_in_domain >= 0.85 AND domain.blast_radius <= "moderate"`. Composes naturally with Interspect evidence. | Requires policy engine at runtime. Every authority check becomes a policy evaluation, not a table lookup. Adds latency and debugging complexity. | Overkill for Phase 4. Reserve for Phase 5+ when confidence scoring adds dynamic attributes. |
| **Capability-based** | Each authority grant is an unforgeable token scoping (domain_pattern, action_class, expiry). No ambient authority — agents can only do what their grants explicitly allow. Delegation is natural (pass a subset of your capabilities). | Requires capability storage and revocation infrastructure. Harder to audit "what can agent X do?" (must enumerate all held capabilities). | Best fit for delegation model but complex to bootstrap. |

### Recommendation: Hybrid RBAC+Capability with ABAC Extension Point

Use a **two-layer model**:

1. **Fleet tier (RBAC layer):** T0-T3 from Mycroft sets the ceiling. Stored in fleet-registry.yaml as a new `mycroft_tier` field per agent entry. This is coarse, role-based, and human-assigned.

2. **Domain authority grants (capability layer):** Fine-grained records binding (agent_id, domain_pattern, action_class). Earned through Interspect evidence, stored in Dolt, queryable at dispatch. Each grant is a capability token with expiry and evidence chain.

3. **ABAC extension point (Phase 5+):** When confidence scoring arrives, authority checks can add attribute predicates (blast_radius, test_coverage_delta, cost_estimate) without changing the core schema. The grant record gains an optional `conditions` field.

This matches the brainstorm's "Five tiers (Propose/Execute/Commit/Deploy/Spend) x domain scope" and composes with the existing fleet registry without requiring a policy engine.

---

## 2. Concrete Schema: Authority Grant Records

### 2.1 Authority Grant Table (Dolt: `authority_grants`)

```sql
CREATE TABLE authority_grants (
  grant_id        VARCHAR(36) PRIMARY KEY,  -- UUID v7 (time-sortable)
  agent_id        VARCHAR(64) NOT NULL,     -- fleet-registry key: "fd-architecture", "clavain-sprint"
  domain_pattern  VARCHAR(256) NOT NULL,    -- glob: "interverse/interspect/**", "core/**", "*.go"
  action_class    ENUM('propose','execute','commit','deploy','spend') NOT NULL,
  tier_floor      TINYINT NOT NULL DEFAULT 0,  -- minimum Mycroft tier required (0-3)
  granted_at      TIMESTAMP NOT NULL,
  granted_by      VARCHAR(64) NOT NULL,     -- "interspect:auto-promote", "principal:mk", "agent:mycroft"
  expires_at      TIMESTAMP NULL,           -- NULL = no expiry (human grants). Auto-grants get 90d default.
  revoked_at      TIMESTAMP NULL,           -- soft delete. NULL = active.
  revoked_by      VARCHAR(64) NULL,
  revoke_reason   VARCHAR(256) NULL,
  conditions      JSON NULL,                -- Phase 5+: {"min_test_coverage": 0.8, "max_blast_radius": "moderate"}

  INDEX idx_lookup (agent_id, action_class, revoked_at),  -- primary query path
  INDEX idx_domain (domain_pattern),                       -- for "who can touch X?" audits
  INDEX idx_expiry (expires_at)                            -- for reaper sweep
);
```

### 2.2 Evidence References Table (Dolt: `authority_evidence`)

```sql
CREATE TABLE authority_evidence (
  evidence_id     VARCHAR(36) PRIMARY KEY,
  grant_id        VARCHAR(36) NOT NULL REFERENCES authority_grants(grant_id),
  evidence_type   ENUM('bead_completion','gate_pass','incident','human_override','review_accepted','review_rejected') NOT NULL,
  evidence_ref    VARCHAR(256) NOT NULL,    -- bead ID, Interspect event_id, or "principal:mk:2026-03-19"
  evidence_at     TIMESTAMP NOT NULL,
  outcome         ENUM('positive','negative','neutral') NOT NULL,
  weight          DECIMAL(3,2) NOT NULL DEFAULT 1.00,  -- recency-decayed weight
  notes           VARCHAR(512) NULL,

  INDEX idx_grant (grant_id, evidence_at DESC)
);
```

### 2.3 Audit Trail Table (Dolt: `authority_audit`)

```sql
CREATE TABLE authority_audit (
  audit_id        VARCHAR(36) PRIMARY KEY,
  timestamp       TIMESTAMP NOT NULL,
  agent_id        VARCHAR(64) NOT NULL,
  action_class    VARCHAR(16) NOT NULL,
  domain_tested   VARCHAR(256) NOT NULL,     -- actual path/label tested
  bead_id         VARCHAR(64) NULL,          -- bead context if applicable
  decision        ENUM('allow','deny','escalate') NOT NULL,
  grant_id_used   VARCHAR(36) NULL,          -- which grant matched (NULL if denied)
  mycroft_tier    TINYINT NOT NULL,          -- agent's tier at decision time
  effective_tier  TINYINT NOT NULL,          -- min(mycroft_tier, grant ceiling)
  resolution_ms   DECIMAL(6,2) NOT NULL,     -- lookup latency

  INDEX idx_agent_time (agent_id, timestamp DESC),
  INDEX idx_bead (bead_id)
);
```

### 2.4 Fleet Registry Extension

Add to `fleet-registry.schema.json` agent_entry definition:

```json
{
  "mycroft_tier": {
    "type": "integer",
    "minimum": 0,
    "maximum": 3,
    "default": 0,
    "description": "Fleet-level Mycroft trust tier. T0=observe, T1=propose, T2=execute, T3=autonomous."
  },
  "authority_scope": {
    "type": "string",
    "enum": ["narrow", "moderate", "broad"],
    "default": "narrow",
    "description": "Default domain breadth. Narrow=single module, moderate=pillar, broad=monorepo."
  }
}
```

Concrete fleet-registry.yaml addition:

```yaml
  fd-architecture:
    source: interflux
    category: review
    mycroft_tier: 1          # Can propose, not execute
    authority_scope: broad   # Reviews across entire monorepo
    # ... existing fields unchanged
```

### 2.5 Domain Pattern Syntax

Domain patterns use a CODEOWNERS-compatible glob syntax, resolved against the monorepo root:

```
# Exact file
core/intercore/config/costs.yaml

# Directory subtree (recursive)
interverse/interspect/**

# Pillar-level
os/Clavain/**

# File type across monorepo
**/*.go

# Bead label pattern (prefix with @)
@intercore-*
@phase:strategy

# All domains (dangerous — only for T3 with principal grant)
**
```

Pattern matching uses the same algorithm as `.gitignore` / CODEOWNERS: last-match-wins for overlapping patterns within the same agent, most-specific-match-wins across agents.

---

## 3. Fleet Tier x Domain Authority Interaction

### The Three Models

| Model | Behavior | Risk |
|-------|----------|------|
| **Cap (ceiling)** | `effective_action = min(mycroft_tier_allows, domain_grant_allows)` | Agent with T3 fleet tier but only `propose` domain grant can only propose. Safe. |
| **Floor** | `effective_action = max(mycroft_tier_allows, domain_grant_allows)` | Domain grant can escalate beyond fleet tier. Dangerous — defeats fleet-level safety. |
| **Orthogonal** | Fleet tier and domain authority checked independently, both must pass. | Strictest. May be too restrictive — T2 agent with `execute` domain grant still needs T2 fleet tier. |

### Recommendation: Cap Model (Ceiling)

The fleet tier is an **upper bound**. Domain authority can only grant actions *up to* the fleet tier ceiling.

```
effective_action_class(agent, domain, action) =
  IF action_class_rank(action) > tier_action_ceiling(agent.mycroft_tier):
    DENY  -- fleet tier caps it
  ELIF has_domain_grant(agent, domain, action):
    ALLOW
  ELSE:
    DENY  -- no domain grant
```

Where tier_action_ceiling maps:

| Mycroft Tier | Max Action Class | Description |
|-------------|------------------|-------------|
| T0 | (none) | Observe only. Cannot claim beads. |
| T1 | propose | Can propose changes, create brainstorms, write plans. |
| T2 | commit | Can execute and commit within granted domains. |
| T3 | spend | Full autonomy within granted domains. Can deploy and spend budget. |

This means:
- A T1 agent with `execute` domain grant for `interverse/interspect/**` is **capped at propose** — the fleet tier wins.
- A T3 agent with `propose` domain grant for `core/intercore/**` is **capped at propose** — the domain grant wins.
- Promotion to a higher action class requires BOTH fleet tier upgrade AND domain grant.

This is the safest composable rule. It means the principal can raise/lower fleet tiers as a global throttle without touching individual domain grants, and domain grants can be fine-tuned without worrying about fleet-tier bypass.

### Action Class Ordering (Strict Total Order)

```
propose < execute < commit < deploy < spend
   1         2        3        4       5
```

Each higher class subsumes the lower. An agent with `commit` authority implicitly has `execute` and `propose` for that domain.

---

## 4. CODEOWNERS as Authority Model

### What CODEOWNERS Gets Right

GitHub CODEOWNERS maps file paths to required reviewers. The Sylveste authority model is structurally identical but substitutes:
- **Reviewers** → **agents with authority**
- **Required approval** → **action class ceiling**
- **Code review** → **any action (propose/execute/commit/deploy/spend)**

### CODEOWNERS-Style Authority File: `authority.owners`

Place at monorepo root. Human-readable, version-controlled, auditable:

```
# authority.owners — per-path authority grants
# Format: <glob> <action_class> <agent_id> [<agent_id>...]
# Last matching rule wins (CODEOWNERS semantics)
# Lines starting with @ match bead labels, not file paths

# Default: all agents can propose anywhere
**                          propose   *

# Interflux review agents can execute (run tests, generate review artifacts) in their domains
interverse/interflux/**     execute   fd-architecture fd-correctness fd-quality fd-safety

# Interspect agent can commit within its own plugin
interverse/interspect/**    commit    interspect-agent

# Clavain can commit across the OS layer
os/Clavain/**               commit    clavain-sprint clavain-work

# Core kernel requires T3 + explicit grant for commit
core/intercore/**           propose   *
core/intercore/**           commit    clavain-sprint  # only sprint agent, only if T3

# Deploy authority is narrow
**                          deploy    mycroft-deploy  # single deployment agent

# Spend authority (budget allocation)
@budget:*                   spend     mycroft-budget

# Bead label authority
@intercore-*                execute   clavain-sprint intercore-agent
@phase:strategy             propose   *
```

### Why Not Just Use CODEOWNERS Directly?

1. CODEOWNERS is read-only from CI — no runtime query API.
2. CODEOWNERS binds to GitHub users/teams, not agent IDs.
3. Action classes don't exist in CODEOWNERS (it's binary: owner or not).
4. Authority needs expiry, evidence, and revocation — CODEOWNERS is static.

But the **pattern syntax and resolution semantics** are directly reusable. Developers already understand `**/*.go` globs and last-match-wins. The `authority.owners` file is the human-readable source of truth; the Dolt `authority_grants` table is the queryable runtime store populated from it.

### Sync Pipeline

```
authority.owners (git) → parse + expand → authority_grants (Dolt)
                        ↑
Interspect evidence → auto-promote/demote → authority_grants (Dolt)
                        ↑
Principal override → manual grant/revoke → authority_grants (Dolt)
```

Three sources of grants, all audit-logged, all queryable from the same table. The `granted_by` field distinguishes: `"authority.owners:L42"` vs `"interspect:auto-promote"` vs `"principal:mk"`.

---

## 5. Authority Lookup Algorithm

### Input

```
resolve_authority(agent_id, bead_id, action_class) → ALLOW | DENY | ESCALATE
```

### Resolution Algorithm

```
FUNCTION resolve_authority(agent_id, bead_id, action_class):

  # Step 1: Fleet tier ceiling check (O(1) — cached from fleet-registry.yaml)
  tier = fleet_registry[agent_id].mycroft_tier
  IF action_class_rank(action_class) > tier_action_ceiling(tier):
    log_audit(agent_id, action_class, bead_id, decision="deny", reason="fleet_tier_ceiling")
    RETURN DENY

  # Step 2: Resolve domains from bead (O(1) — bead metadata cached)
  domains = []
  domains += bead_changed_paths(bead_id)       # files touched / planned to touch
  domains += bead_labels(bead_id)               # e.g., "@intercore-bridge", "@phase:strategy"
  IF domains is empty:
    domains = ["**"]                            # unconstrained bead → needs broadest grant

  # Step 3: Find matching grants (O(k log n) — k domains, n grants, indexed)
  matching_grants = []
  FOR domain IN domains:
    grants = query_grants(
      agent_id = agent_id,
      action_class >= action_class,   # subsumption: commit grant covers execute request
      revoked_at IS NULL,
      expires_at IS NULL OR expires_at > now(),
      domain_pattern MATCHES domain   # glob match
    )
    matching_grants += grants

  # Step 4: Check conditions (Phase 5+ — skip if no conditions)
  FOR grant IN matching_grants:
    IF grant.conditions IS NOT NULL:
      IF NOT evaluate_conditions(grant.conditions, bead_id):
        matching_grants.remove(grant)

  # Step 5: Coverage check — ALL domains must be covered
  uncovered = []
  FOR domain IN domains:
    IF NOT any(grant.domain_pattern MATCHES domain FOR grant IN matching_grants):
      uncovered.append(domain)

  IF uncovered is empty:
    best_grant = most_specific_match(matching_grants)  # longest pattern wins
    log_audit(agent_id, action_class, bead_id, decision="allow", grant_id=best_grant.grant_id)
    RETURN ALLOW

  # Step 6: Partial coverage → escalate
  IF matching_grants is not empty AND uncovered is not empty:
    log_audit(agent_id, action_class, bead_id, decision="escalate",
              reason=f"uncovered domains: {uncovered}")
    RETURN ESCALATE  # agent has some authority but bead crosses domain boundary

  # Step 7: No coverage at all → deny
  log_audit(agent_id, action_class, bead_id, decision="deny", reason="no_matching_grants")
  RETURN DENY
```

### Complexity Analysis

- **Step 1:** O(1) — in-memory hash lookup from fleet registry cache.
- **Step 2:** O(1) — bead metadata from `bd show` (already called in route.md Step 2).
- **Step 3:** O(k * log n) — k domain strings, each matched against a sorted index of n grant patterns. In practice k < 20 (files in a bead) and n < 500 (total grants). Well under 1ms.
- **Step 5:** O(k * m) — k domains, m matching grants. Worst case k=20, m=10 = 200 comparisons.
- **Total:** Sub-millisecond. No external service call. All data in local Dolt.

### Integration with route.md

Insert between Step 2 (Parse Arguments) and Step 4 (Dispatch):

```bash
# After bead metadata gathered, before dispatch
authority_decision=$(clavain-cli authority-check "$agent_id" "$CLAVAIN_BEAD_ID" "$inferred_action" 2>/dev/null) || authority_decision="deny"
case "$authority_decision" in
  allow)    ;; # proceed to dispatch
  escalate) echo "⚠ Authority partial: some paths outside your grants. Requesting review."
            # queue for human or higher-tier agent review
            ;;
  deny)     echo "⛔ Authority denied: $inferred_action on this bead exceeds your grants."
            # offer to propose instead, or show authority status
            ;;
esac
```

### Caching Strategy

```
                    ┌─────────────────────┐
                    │  fleet-registry.yaml │ ← loaded once per session
                    │  (mycroft_tier cache)│
                    └──────────┬──────────┘
                               │
┌──────────────────┐    ┌──────▼──────────┐    ┌─────────────────┐
│ authority.owners │───►│ authority_grants │◄───│ Interspect      │
│ (git, static)    │    │ (Dolt, runtime)  │    │ (auto-promote)  │
└──────────────────┘    └──────┬──────────┘    └─────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │ Grant Cache (in-mem) │ ← refreshed every 60s or on grant change
                    │ agent_id → grants[] │   per-agent sorted by pattern specificity
                    └─────────────────────┘
```

The grant cache is a simple in-memory map refreshed on a 60s interval (aligned with heartbeat). For 50 agents x 10 grants each = 500 entries — trivially fits in memory. Cache invalidation on Dolt write (Interspect auto-promote triggers cache refresh).

---

## 6. Authority Inheritance and Delegation

### The Delegation Problem

When a T3 agent spawns a subagent (e.g., clavain-sprint spawns fd-architecture as a Task subagent for review), what authority does the subagent inherit?

### Delegation Rules

**Rule 1: Delegation Cannot Escalate.** A delegating agent can only pass a subset of its own effective authority. This is the fundamental capability-security property.

```
subagent_effective(action, domain) = min(
  delegator_effective(action, domain),   # can't exceed parent
  subagent_own_grants(action, domain)    # can't exceed own grants either
)
```

**Rule 2: Delegation is Scoped to Bead.** Authority delegation is not a general capability transfer — it's scoped to the bead being worked. When clavain-sprint delegates to fd-architecture for bead Sylveste-xyz, the delegation only applies to that bead's domains.

**Rule 3: Delegation Requires Explicit Token.** The delegating agent creates a delegation record:

```sql
CREATE TABLE authority_delegations (
  delegation_id   VARCHAR(36) PRIMARY KEY,
  parent_agent_id VARCHAR(64) NOT NULL,
  child_agent_id  VARCHAR(64) NOT NULL,
  bead_id         VARCHAR(64) NOT NULL,
  action_ceiling  ENUM('propose','execute','commit','deploy','spend') NOT NULL,
  domain_patterns TEXT NOT NULL,          -- JSON array of patterns, subset of parent's grants
  created_at      TIMESTAMP NOT NULL,
  expires_at      TIMESTAMP NOT NULL,     -- short-lived: bead completion or 4hr max
  revoked_at      TIMESTAMP NULL,

  INDEX idx_child_bead (child_agent_id, bead_id)
);
```

**Rule 4: Delegation Depth is Bounded.** Maximum delegation depth = 2 (parent → child → grandchild). Prevents authority laundering through long chains. The `resolve_authority` function checks delegation depth:

```
IF delegation_depth(agent_id, bead_id) > MAX_DELEGATION_DEPTH:
  RETURN DENY  -- authority laundering prevention
```

**Rule 5: Human Grants Are Non-Delegatable.** If a grant's `granted_by` starts with `"principal:"`, it cannot be delegated. This prevents a T3 agent from passing a human-granted special exception to a subagent.

### Concrete Delegation Flow

```
1. clavain-sprint (T3, commit authority for os/Clavain/**)
   claims bead Sylveste-abc (touches os/Clavain/hooks/lib-sprint.sh)

2. clavain-sprint spawns fd-correctness as Task subagent for review
   → creates delegation:
     parent=clavain-sprint, child=fd-correctness,
     bead=Sylveste-abc, action_ceiling=propose,  # review = propose, not commit
     domain_patterns=["os/Clavain/hooks/**"]     # narrower than parent's grant

3. fd-correctness resolves authority:
   - Own grants: propose for os/Clavain/** ✓
   - Delegation: propose for os/Clavain/hooks/** ✓ (within parent's commit, capped to propose)
   - Fleet tier: T1 (propose ceiling) ✓
   - Result: ALLOW propose

4. fd-correctness attempts to execute (edit a file):
   - Own grants: no execute grant
   - Delegation: ceiling is propose
   - Result: DENY → escalates back to clavain-sprint
```

### Anti-Laundering Invariants

These are checkable predicates for every authority decision:

```
INVARIANT 1: ∀ delegation D:
  action_rank(D.action_ceiling) ≤ action_rank(effective_authority(D.parent_agent_id, D.bead_id))

INVARIANT 2: ∀ delegation D, ∀ pattern P in D.domain_patterns:
  ∃ parent_grant G where G.domain_pattern COVERS P

INVARIANT 3: ∀ agent A, bead B:
  delegation_chain_length(A, B) ≤ MAX_DELEGATION_DEPTH (=2)

INVARIANT 4: ∀ delegation D:
  D.expires_at ≤ D.created_at + MAX_DELEGATION_TTL (=4h)

INVARIANT 5: ∀ grant G where G.granted_by STARTS WITH "principal:":
  ¬∃ delegation D where D references G
```

---

## 7. Summary: Composable Authority Resolution

The complete resolution for `(agent_id, bead_id, action_class)`:

```
                      ┌──────────────┐
                      │ Fleet Tier   │  T0-T3 from fleet-registry.yaml
                      │ (RBAC ceil)  │  → tier_action_ceiling
                      └──────┬───────┘
                             │ caps
                      ┌──────▼───────┐
                      │ Domain Grants│  authority_grants table (Dolt)
                      │ (Capability) │  → glob match on bead paths/labels
                      └──────┬───────┘
                             │ narrows
                      ┌──────▼───────┐
                      │ Delegation   │  authority_delegations (if subagent)
                      │ (Scoped cap) │  → parent ceiling, bead-scoped
                      └──────┬───────┘
                             │ checks
                      ┌──────▼───────┐
                      │ Conditions   │  Phase 5+ ABAC predicates
                      │ (Optional)   │  → blast_radius, coverage, cost
                      └──────┬───────┘
                             │
                      ┌──────▼───────┐
                      │   DECISION   │  allow / deny / escalate
                      │ + audit log  │
                      └──────────────┘
```

### Key Properties

1. **Monotonic restriction:** Each layer can only narrow, never widen. Fleet tier caps domain grants. Domain grants cap delegations. Conditions cap everything.
2. **Fully auditable:** Every decision logged with grant_id, tier, resolution_ms.
3. **Queryable at dispatch time:** O(k log n), sub-millisecond, no external service.
4. **Evidence-backed:** Every auto-grant traces to Interspect events via authority_evidence.
5. **Human-overridable:** Principal can grant/revoke at any time. Human grants are non-delegatable.
6. **Expiry-aware:** Auto-grants expire (90d default). Reaper sweep on heartbeat interval.
7. **CODEOWNERS-familiar:** authority.owners uses identical glob syntax. Developers know it already.

### Implementation Sequence (Phase 4 Build Order)

1. **Week 1:** Add `mycroft_tier` to fleet-registry.yaml + schema. Implement `clavain-cli authority-check` with fleet-tier-only logic (deny if action > tier ceiling, allow otherwise). Wire into route.md.
2. **Week 2:** Create Dolt tables (`authority_grants`, `authority_evidence`, `authority_audit`). Implement `authority.owners` parser. Populate initial grants from current agent capabilities.
3. **Week 3:** Implement domain grant matching in `authority-check`. Add delegation table and subagent delegation flow. Wire Interspect evidence → auto-promote pipeline.

---

## Sources

- [Access Control in the Era of AI Agents (Auth0)](https://auth0.com/blog/access-control-in-the-era-of-ai-agents/)
- [RBAC Excellence: Policy-Driven Role Control for Smarter AI Agents (CloudMatos)](https://www.cloudmatos.ai/blog/role-based-access-control-rbac-ai-agents/)
- [RBAC vs ABAC vs PBAC: Modern Access Control Models (Security Boulevard)](https://securityboulevard.com/2026/02/rbac-vs-abac-vs-pbac-modern-access-control-models/)
- [Capability-based security (Wikipedia)](https://en.wikipedia.org/wiki/Capability-based_security)
- [Securing Agentic AI: Authorization Patterns for Autonomous Systems (DEV Community)](https://dev.to/siddhantkcode/securing-agentic-ai-authorization-patterns-for-autonomous-systems-3ajo)
- [MCP Security & AI Agent Authorization (Cerbos)](https://www.cerbos.dev/blog/mcp-security-ai-agent-authorization-a-ciso-and-architects-guide)
- [SEP: Capability-based authorization for A2A (GitHub Discussion)](https://github.com/a2aproject/A2A/discussions/1404)
- [AI Agents Are Becoming Authorization Bypass Paths (The Hacker News)](https://thehackernews.com/2026/01/ai-agents-are-becoming-privilege.html)
- [Implement Least Privilege Access for Agentic Workflows (AWS Well-Architected)](https://docs.aws.amazon.com/wellarchitected/latest/generative-ai-lens/gensec05-bp01.html)
- [Agent Authority Least Privilege Framework (FINOS AIR)](https://air-governance-framework.finos.org/mitigations/mi-18_agent-authority-least-privilege-framework.html)
- [Best Practices of Authorizing AI Agents (Oso)](https://www.osohq.com/learn/best-practices-of-authorizing-ai-agents)
- [About Code Owners (GitHub Docs)](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
- [AGENTGUARDIAN: Learning Access Control Policies for AI Agents (arXiv)](https://arxiv.org/pdf/2601.10440)

<!-- flux-research:complete -->
