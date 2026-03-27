# Dispatch Integration: Domain-Scoped Authority at Decision Time

> Flux-drive research on how domain-scoped authority checks integrate with route.md, Mycroft dispatch, and beads — enforcement points, failure modes, and a minimal Phase 4 implementation.

## 1. Current Dispatch Flow Map

### Route.md Decision Path

The current dispatch flow in `os/Clavain/commands/route.md` follows a four-step pipeline:

```
Step 1: Check Active Sprints (Resume)
  └─ clavain-cli sprint-find-active → resume or Step 2

Step 2: Parse Arguments
  └─ Empty → discovery scan (Step 3)
  └─ Bead ID → bd show + metadata gather → Step 4
  └─ Free text → classify-complexity → Step 4

Step 3: Discovery Scan
  └─ lib-discovery.sh discovery_scan_beads
  └─ AskUserQuestion: top 3 beads + actions
  └─ claim-bead pattern → dispatch to /work, /sprint, etc.

Step 4: Classify and Dispatch
  └─ 4a: Fast-path heuristic table (14 rows, first-match-wins)
  └─ 4b: LLM classification (haiku fallback if no heuristic)
  └─ 4c: Dispatch → claim-bead → auto-dispatch via Skill tool
```

**Where authority does NOT currently exist.** The claim-bead pattern (`bd update <id> --claim` + claim-identity) checks only whether the bead is already claimed. It does not check whether the claiming agent has authority over the bead's domain. The fast-path heuristic table routes by complexity and type — it has no domain dimension at all.

### Model Routing vs. Work Routing

The codebase has a well-developed model routing layer (`scripts/lib-routing.sh`) with a clear resolution chain:

```
kernel overrides → per-agent yaml → interspect override/calibration
  → phase-category → phase → default → safety floor clamp
```

This is **model selection** — which LLM runs the agent. Domain authority is orthogonal: which **work** the agent is allowed to touch. The distinction maps cleanly to the military credentialing analogue: model routing is "pay grade" (what resources you command), domain authority is "specialty code" (what domains you operate in).

### Where Mycroft T0-T3 Fits

Per the `mycroft-fleet-dispatch` CUJ and Phase 4 in the orchestration brainstorm, Mycroft's trust tiers are **fleet-level**: T0 (observe) through T3 (fully autonomous dispatch). These tiers govern *whether Mycroft can dispatch at all*, not *what domains an agent can touch*.

The two axes compose:

| | T0 (observe) | T1 (suggest) | T2 (allowlist auto) | T3 (full auto) |
|---|---|---|---|---|
| **No domain authority** | Shadow only | Suggest, human decides | Auto-dispatch blocked | Auto-dispatch blocked |
| **Domain authority granted** | Shadow only | Suggest with authority badge | Auto-dispatch allowed | Auto-dispatch allowed |

**Key rule: domain authority is a necessary condition for T2+ auto-dispatch, never sufficient on its own.** An agent with domain authority at T0 still only generates shadows. Mycroft tier gates *action type*; domain authority gates *action scope*.

## 2. Enforcement Point Design

### Three Candidate Insertion Points

**Option A: Check at bead assignment only (pre-execution)**
- Where: Inside the claim-bead pattern, after `bd show` succeeds, before `bd update --claim`
- Pro: Single enforcement point, no mid-execution overhead
- Con: Agent could discover work outside its domain during execution (e.g., bead touches files in unexpected modules)

**Option B: Check at action execution only (runtime)**
- Where: Before each file write/commit, checking affected paths against authority
- Pro: Catches scope creep during execution
- Con: Expensive, requires intercepting tool calls, breaks flow

**Option C: Check at assignment + lightweight runtime audit (recommended)**
- Where: Synchronous deny at claim time; async audit of affected paths post-execution
- Pro: Fast-path enforcement where it matters (assignment), detection where it's hard to predict (execution)
- Con: Slightly more complex, but each piece is simple

### Recommended: Option C with Two Enforcement Points

**Enforcement Point 1 (synchronous, blocking): Pre-claim authority check**

Insert between Step 3/4's metadata gathering and the claim-bead pattern. This is the PEP (Policy Enforcement Point) in XACML terms.

```
[existing] bd show <bead_id> → gather metadata
[NEW]      authority_check <agent_id> <bead_id> → ALLOW | DENY(reason) | DEGRADE(fallback_tier)
[existing] claim-bead pattern → bd update --claim
```

The check consults a local authority store (YAML or `.clavain/authority/` directory — not a remote service). Decision is synchronous, <10ms. On DENY, the bead is skipped and the next candidate is tried. On DEGRADE, the agent operates at a reduced authority tier (e.g., can read but not commit).

**Enforcement Point 2 (async, non-blocking): Post-execution audit**

After bead completion (in the Stop hook or quality-gates flow), compare the actual files modified against the agent's domain authority scope. Log any out-of-scope modifications as Interspect evidence events. This feeds the demotion pipeline — repeated out-of-scope writes trigger FPPE-style focused review (from the credentialing analogues).

### Rollback Path for Mid-Execution Authority Violations

If the post-execution audit detects out-of-scope modifications:

1. **No automatic rollback.** The work is done; reverting risks losing correct changes.
2. **Quarantine the bead.** Mark it with `bd set-state <id> "authority_violation=true"`. The bead enters quarantine status (from the manufacturing rework model in Phase 1).
3. **Escalate to human review.** The quarantined bead requires human review before merge/close.
4. **Record evidence.** Write an Interspect evidence event for the authority violation. This feeds the authority erosion pipeline.

This matches AWS IAM's pattern: deny at the API boundary (pre-claim), audit at CloudTrail (post-execution), but never silently revert completed work.

## 3. Cloud IAM Pattern Analysis

### AWS IAM: Explicit Deny Wins

AWS policy evaluation follows a strict order: explicit deny always wins, regardless of any allow elsewhere. The evaluation is synchronous — every API call is checked before execution.

Key structural insights for Sylveste:

- **Deny is a hard veto, not a vote.** If any policy says deny, the action is denied. This maps to: if the authority store says an agent lacks domain authority, that's a hard block — Mycroft tier doesn't override it.
- **Multiple policy layers compose via intersection.** SCPs (org-level) AND identity policies AND resource policies must all allow. For Sylveste: fleet tier (Mycroft T0-T3) AND domain authority AND bead constraints all must allow.
- **Evaluation is per-request, not per-session.** Each action is checked independently. For Sylveste: check at claim time (one request), not once at session start.

### OPA/Rego: Admission Controllers

OPA Gatekeeper in Kubernetes intercepts API requests through a validating admission webhook, evaluates them against Rego policies, and rejects violations before the object is persisted.

Key structural insights:

- **Webhook is synchronous and blocking.** The API server waits for the webhook response. This is the model for the pre-claim authority check — it must be fast and synchronous.
- **ConstraintTemplate + Constraint separation.** The policy logic (Rego) is separate from the parameterization (which resources, which rules). For Sylveste: the authority check function is generic; the domain-authority YAML configures it per agent and domain.
- **Dry-run mode.** Gatekeeper supports `enforcement: dryrun` — log violations but don't block. This maps directly to Sylveste's shadow mode convention (already used in complexity routing B2 and calibration B3).

### XACML PDP/PEP: Decoupled Architecture

The XACML pattern cleanly separates:
- **PEP** (Policy Enforcement Point): intercepts request, formats authorization query, enforces decision
- **PDP** (Policy Decision Point): evaluates policies, returns permit/deny/indeterminate
- **PIP** (Policy Information Point): provides attribute values (bead metadata, agent history)
- **PAP** (Policy Administration Point): manages policies

For Sylveste's Phase 4 minimal:
- **PEP** = the authority check function inserted in route.md
- **PDP** = a shell function that reads the authority YAML and returns allow/deny
- **PIP** = `bd show` output (bead metadata) + `bd state` (agent history)
- **PAP** = the YAML file itself, edited by the principal or by Interspect's promote/demote pipeline

No need for a separate service. The PDP is a function call.

### Three Response Modes

Drawing from all three patterns:

| Mode | Description | Sylveste Mapping |
|------|-------------|-----------------|
| **Synchronous deny** | Block the request before execution | Pre-claim authority check returns DENY |
| **Async audit** | Allow but log for review | Post-execution file scope audit via Interspect |
| **Challenge-response** | Ask for additional authorization | AskUserQuestion: "Agent X lacks authority for domain Y. Override?" |

Phase 4 starts with synchronous deny + async audit. Challenge-response is deferred to Phase 5+ (requires the re-engagement protocol from Phase 6).

## 4. Authority Decision Record

### What Gets Logged

Every authority check (grant or deny) produces an Authority Decision Record:

```yaml
authority_decision:
  timestamp: "2026-03-19T14:32:05Z"
  agent_id: "grey-area"                  # Fleet agent name
  bead_id: "Sylveste-4f2a"
  domain: "core/intercore"               # Resolved domain from bead metadata
  action: "claim"                        # claim | execute | commit
  decision: "allow"                      # allow | deny | degrade
  reason: "agent has Execute authority for core/intercore"
  authority_source: "authority.yaml:12"  # File:line of matching rule
  mycroft_tier: "T2"                     # Current fleet tier
  enforcement_mode: "enforce"            # enforce | shadow
  fallback_applied: false                # True if degraded from deny to allow
  session_id: "abc123"
```

On deny, additional fields:

```yaml
  deny_reason: "agent grey-area has no authority for domain security/*"
  deny_action: "skip"                   # skip | quarantine | escalate
  next_candidate: "Sylveste-4f2b"        # Bead tried next (if skip)
```

### Flow to Interspect

Authority decisions flow to Interspect via the existing evidence pipeline. The `hook_id` for authority events is `interspect-authority` (must be added to the `_interspect_validate_hook_id` allowlist in `interverse/interspect/hooks/lib-interspect.sh`).

```
authority_check() → ALLOW/DENY
  ├─ [always] append to .clavain/authority/decisions.jsonl (local audit trail)
  ├─ [always] ic events emit --type=authority_decision --data=<json> (Interspect pipeline)
  └─ [deny only] bd set-state <bead_id> "authority_denied_by=<agent_id>"
```

The JSONL local log is the source of truth for authority decisions, just as `.beads/backup/*.jsonl` is for bead state. Interspect consumes these events for:
- **OPPE equivalent:** Ongoing authority compliance rate per agent per domain
- **FPPE trigger:** If deny rate exceeds threshold (e.g., >20% of claims for a domain), trigger focused review
- **Promotion evidence:** Consistent allow + successful completion feeds the authority promotion pipeline

### Bead Audit Trail

Each bead's state includes authority metadata:

```bash
bd set-state "$bead_id" "authority_granted_to=${agent_id}"
bd set-state "$bead_id" "authority_domain=${domain}"
bd set-state "$bead_id" "authority_level=execute"
```

On post-execution audit, if scope violation detected:

```bash
bd set-state "$bead_id" "authority_violation=true"
bd set-state "$bead_id" "authority_violation_paths=core/intermute/foo.go,sdk/interbase/bar.go"
```

## 5. Degraded Mode: Fail-Closed vs. Fail-Open

### When Authority Store is Unavailable

The authority store is a local YAML file — "unavailable" means the file is missing, corrupted, or unreadable. This is different from a network service being down.

### Configurable Per Domain

```yaml
# .clavain/authority/authority.yaml
domains:
  "core/*":
    fail_mode: closed        # No agent can act without explicit authority
  "interverse/*":
    fail_mode: open           # Fall back to fleet tier (any agent at T2+ can act)
  "docs/*":
    fail_mode: open
  "security/*":
    fail_mode: closed
  default:
    fail_mode: open           # Default: fail-open with fleet tier fallback
```

### Fail-Closed Behavior

- Authority check returns DENY for all agents
- Bead goes to the bottom of the queue (not permanently blocked — authority store may be restored)
- Interspect alert emitted: `authority_store_unavailable` with domain
- Human-in-the-loop override: principal can issue manual dispatch with `--override-authority`
- Factory does NOT pause — other domains with fail-open continue operating

### Fail-Open Behavior

- Authority check returns ALLOW with `fallback_applied: true`
- All authority decisions during fallback are logged with `enforcement_mode: degraded`
- Fleet tier (Mycroft T0-T3) becomes the sole gating mechanism
- When authority store recovers, all beads assigned during fallback get post-hoc audit
- Repeated fallback triggers an alert: "authority store unavailable for domain X for >N minutes"

### Why Default to Fail-Open

The factory's primary value is throughput. Fail-closed on all domains would halt the factory on a YAML parse error. Safety-critical domains (security, core kernel) should be fail-closed because the cost of unauthorized changes exceeds the cost of delay. Plugin and docs domains should be fail-open because a temporary authority gap is cheaper than blocked agents.

This mirrors hospital privileging: the OR has fail-closed privileging (no surgeon operates without verified privileges), but the outpatient clinic has fail-open scheduling (any credentialed provider can see patients if the privileges system is down, with post-hoc audit).

## 6. Phase 4 Minimal Implementation

### Design Constraint: Diff to route.md, Not a New Service

The entire authority check is a single shell function added to an existing library, plus a YAML config file. No new daemon, no new binary, no new service.

### Implementation: Three Files

**File 1: `os/Clavain/scripts/lib-authority.sh` (new, ~80 lines)**

```bash
# lib-authority.sh — Domain-scoped authority check for route.md dispatch
# Source this file; do not execute directly.
#
# Public API:
#   authority_check <agent_id> <bead_id> [--mode enforce|shadow]
#     Returns: 0 (allow), 1 (deny), 2 (degrade)
#     Writes decision to stdout as JSON
#
#   authority_resolve_domain <bead_id>
#     Returns: domain string (e.g., "core/intercore") from bead labels/paths

[[ -n "${_AUTHORITY_LOADED:-}" ]] && return 0

_AUTHORITY_CONFIG_PATH=""
_AUTHORITY_MODE="shadow"   # Default: shadow (log but don't block)

_authority_find_config() {
  local root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  [[ -n "$root" && -f "$root/.clavain/authority/authority.yaml" ]] && {
    echo "$root/.clavain/authority/authority.yaml"
    return 0
  }
  return 1
}

authority_resolve_domain() {
  local bead_id="$1"
  # Extract domain from bead labels or affected paths
  # Priority: explicit domain label > primary path prefix > "unknown"
  local domain
  domain=$(bd state "$bead_id" domain 2>/dev/null) || domain=""
  if [[ -z "$domain" ]]; then
    domain=$(bd show "$bead_id" 2>/dev/null | jq -r '.labels[]? | select(startswith("domain:")) | sub("domain:"; "")' 2>/dev/null) || domain=""
  fi
  [[ -z "$domain" ]] && domain="unknown"
  echo "$domain"
}

authority_check() {
  local agent_id="$1" bead_id="$2" mode="${_AUTHORITY_MODE}"
  # Parse optional --mode flag
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) mode="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local domain
  domain=$(authority_resolve_domain "$bead_id")

  # Load config
  local config
  config=$(_authority_find_config) || config=""

  if [[ -z "$config" ]]; then
    # Authority store unavailable — check fail mode
    # Default fail-open: allow with degraded flag
    _authority_log_decision "$agent_id" "$bead_id" "$domain" "allow" \
      "authority store unavailable, fail-open default" "degraded"
    return 0
  fi

  # Look up agent's authority for this domain
  # Resolution: exact domain match > wildcard parent > default
  local granted
  granted=$(_authority_lookup "$config" "$agent_id" "$domain")

  case "$granted" in
    allow)
      _authority_log_decision "$agent_id" "$bead_id" "$domain" "allow" \
        "agent has authority" "$mode"
      return 0
      ;;
    deny)
      if [[ "$mode" == "shadow" ]]; then
        _authority_log_decision "$agent_id" "$bead_id" "$domain" "deny" \
          "would deny: agent lacks authority for $domain" "shadow"
        return 0  # Shadow: allow but log
      fi
      _authority_log_decision "$agent_id" "$bead_id" "$domain" "deny" \
        "agent lacks authority for $domain" "enforce"
      return 1
      ;;
    *)
      # Unknown → fail-open
      _authority_log_decision "$agent_id" "$bead_id" "$domain" "allow" \
        "no rule matched, default allow" "$mode"
      return 0
      ;;
  esac
}

_AUTHORITY_LOADED=1
```

**File 2: `.clavain/authority/authority.yaml` (new, project-specific config)**

```yaml
# Domain-scoped agent authority configuration
# Composable with Mycroft T0-T3 fleet tiers
version: 1
mode: shadow  # shadow | enforce (start in shadow, promote after validation)

agents:
  grey-area:
    domains:
      - pattern: "interverse/*"
        level: execute
      - pattern: "docs/*"
        level: execute
      - pattern: "core/*"
        level: propose  # Can suggest but not claim
  falling-outside:
    domains:
      - pattern: "core/intercore"
        level: execute
      - pattern: "os/Clavain"
        level: execute
      - pattern: "interverse/*"
        level: execute

# Domain-level fail modes
domains:
  "core/*":
    fail_mode: closed
  "security/*":
    fail_mode: closed
  "interverse/*":
    fail_mode: open
  "docs/*":
    fail_mode: open
  default:
    fail_mode: open
```

**File 3: Diff to `os/Clavain/commands/route.md` (minimal insertion)**

The insertion point is in Step 3 (discovery scan, before claim-bead) and Step 4c (classify-and-dispatch, before claim-bead). Both use the same pattern:

```markdown
## Patterns (reference by name)

**authority-check:** `source "$CLAUDE_PLUGIN_ROOT/scripts/lib-authority.sh" 2>/dev/null; authority_result=$(authority_check "${AGENT_ID:-$CLAUDE_SESSION_ID}" "$CLAVAIN_BEAD_ID" 2>/dev/null); [[ $? -eq 1 ]] && { echo "⚠ Authority denied for $(authority_resolve_domain "$CLAVAIN_BEAD_ID")"; continue; }`
```

In Step 3 item 6 and Step 4c item 3, insert before the existing claim-bead pattern:

```
6. PATTERN: authority-check (skip for closed/verify_done/create_bead).
   Deny → skip to next candidate, log via Interspect.
   PATTERN: claim-bead (skip for closed/verify_done/create_bead). ...
```

### What This Does NOT Include (Explicitly Deferred)

- **Runtime file-path enforcement.** Phase 4 checks at claim time only. Post-execution audit is Phase 5.
- **Automatic promotion/demotion.** Authority YAML is manually edited. Interspect-driven auto-promotion is Phase 5+.
- **Mycroft integration.** Mycroft's T2 allowlist already has type/priority/complexity filters. Domain authority filter is additive when Mycroft reaches T2 implementation.
- **Challenge-response.** "Override authority?" requires the re-engagement protocol from Phase 6.
- **Per-action authority.** Phase 4 checks "can this agent claim this bead?" not "can this agent write to this file?" The latter requires the protected-paths infrastructure Interspect already has.

### Shadow-to-Enforce Rollout

Following the pattern established by complexity routing (B2) and calibration (B3):

1. **Week 1:** Deploy with `mode: shadow`. Authority checks run on every claim, log decisions, never block.
2. **Week 2:** Review decision log. Tune authority YAML based on what would have been denied.
3. **Week 3:** Switch to `mode: enforce` for high-confidence domains (core/*, security/*). Keep shadow for others.
4. **Week 4:** Full enforce. Monitor deny rate and false-deny rate via Interspect.

### Composition Rule (Single Sentence)

**An agent may claim a bead if and only if: (a) Mycroft tier permits the action type, AND (b) domain authority permits the agent for the bead's domain, AND (c) the bead is not already claimed.**

This is the IAM intersection model: all three conditions must be satisfied. Explicit deny at any layer vetoes the claim. The evaluation order is: (b) domain authority first (cheapest, local YAML lookup), then (a) Mycroft tier (if applicable — currently only relevant at T2+), then (c) claim atomicity (existing Dolt transaction).

---

## Sources

- [AWS IAM Policy Evaluation Logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html)
- [AWS IAM Enforcement Code Logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic_policy-eval-denyallow.html)
- [OPA Kubernetes Admission Control](https://www.openpolicyagent.org/docs/v0.12.2/kubernetes-admission-control)
- [OPA Gatekeeper for Kubernetes Policy Enforcement (2026)](https://oneuptime.com/blog/post/2026-02-20-kubernetes-opa-gatekeeper-policies/view)
- [Securing Kubernetes with OPA Gatekeeper](https://spacelift.io/blog/opa-kubernetes)
- [XACML Policy Enforcement Point](https://docs.oracle.com/cd/E27515_01/common/tutorials/authz_xacml_pep.html)
- [XACML Architecture — Wikipedia](https://en.wikipedia.org/wiki/XACML)
- [Policy Enforcement Point — Plurilock (March 2026)](https://plurilock.com/glossary/policy-enforcement-point/)
- [Decoupling PDP/PEP for Zero-Trust — Oracle Cloud](https://blogs.oracle.com/cloud-infrastructure/pdppep-zerotrust-oracle-cloud)

<!-- flux-research:complete -->
