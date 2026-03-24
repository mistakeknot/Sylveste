# fd-conflict-resolution-boundary — Protocol Boundary Definition

> attp (protocol) vs interweave/interlock (framework): where detection ends and resolution begins.

## Summary

attp is a transport protocol. It detects and reports conflicts. It never resolves them. The boundary line: **attp compares incoming token state against local known state and emits a structured conflict event. Everything after that event — negotiation, merge, force-accept, reject — belongs to the framework layer.**

---

## 1. What attp Detects

attp operates at exactly two detection levels:

### 1a. Structural Conflicts (file-level)

attp compares the `files_changed` manifest in an incoming token against local state. A structural conflict exists when:

- **Same-path divergence:** Both the incoming token and local state have modifications to the same file path, and neither is an ancestor of the other (determined by comparing the `base_commit` in the token against local HEAD and merge-base).
- **Create-create:** Both sides created a file at the same path that did not exist at the common ancestor.
- **Delete-modify:** One side deleted a file the other side modified.

attp does NOT detect:
- **Semantic conflicts** (two files that don't overlap but break each other's logic). That requires build/test, which is framework territory.
- **Line-level or hunk-level conflicts.** attp knows "both touched `router.go`", not "both touched line 47." Hunk-level analysis is a resolution concern — the framework may use `git merge-file`, AST diffing, or LLM-assisted merge. attp must not prescribe the method.
- **Dependency conflicts** (e.g., one side updated a Go module, the other added a new import of the old version). Out of scope — requires toolchain knowledge attp does not have.

### 1b. Sensitivity Conflicts (exclusion boundary disagreement)

A sensitivity conflict exists when the two peers' exclusion manifests disagree about what is shareable:

- **Path visibility mismatch:** The incoming token references a file path that the local peer's `.attpignore` or sensitivity config marks as excluded (or vice versa — the local peer wants to share a path the remote has excluded).
- **Exclusion proof inconsistency:** The Merkle root in the token is inconsistent with the claimed exclusion set — either a hash mismatch (content was tampered or stale) or an attestation gap (the sender did not attest exclusion for a path the receiver expected to be excluded).

Sensitivity conflicts are never auto-resolved. They always surface to the framework as a distinct conflict type.

### Detection boundary rule

> **attp answers: "Is there a conflict?" and "What kind?"**
> **attp never answers: "How should it be resolved?"**

---

## 2. Conflict Event Schema

When attp detects a conflict, it emits a `ConflictDetected` event. This event must be self-contained — the framework must be able to resolve without querying attp again.

```json
{
  "schema_version": "1.0.0",
  "event_type": "conflict_detected",
  "conflict_id": "uuid-v7",
  "detected_at": "2026-03-19T14:23:01.003Z",
  "token_id": "uuid-v7 of the incoming token that triggered detection",
  "session_id": "local attp session/connection identifier",

  "conflict_class": "structural | sensitivity",

  "peers": {
    "local": {
      "agent_id": "agent identifier on this machine",
      "machine_id": "tailscale hostname or stable machine ID",
      "head_commit": "abc123f",
      "branch": "main",
      "dirty_paths": ["src/router.go", "src/handler.go"]
    },
    "remote": {
      "agent_id": "agent identifier on the remote machine",
      "machine_id": "tailscale hostname of sender",
      "head_commit": "def456a",
      "branch": "main",
      "token_base_commit": "aaa111b (the commit the token was built against)"
    }
  },

  "merge_base": "aaa111b (last common ancestor, null if unknown)",

  "conflicts": [
    {
      "path": "src/router.go",
      "conflict_type": "divergent_modify",
      "local_state": {
        "modification_type": "modified",
        "content_hash": "sha256:abcdef...",
        "is_staged": true
      },
      "remote_state": {
        "modification_type": "modified",
        "content_hash": "sha256:123456...",
        "inlined": false,
        "fetch_ref": "attp://peer-machine:8400/fetch/src/router.go@def456a"
      }
    },
    {
      "path": "config/secrets.yaml",
      "conflict_type": "sensitivity_mismatch",
      "local_excluded": true,
      "remote_excluded": false,
      "local_exclusion_source": ".attpignore:7",
      "remote_attestation_present": true,
      "merkle_verification": "passed | failed | not_attempted"
    }
  ],

  "resolution_hint": null,
  "callback": {
    "protocol": "mcp",
    "tool": "attp_resolve_conflict",
    "required_payload": {
      "conflict_id": "uuid-v7",
      "resolution": "accept_local | accept_remote | merged | deferred | escalated"
    }
  }
}
```

### Field rationale

| Field | Why it exists |
|-------|---------------|
| `conflict_id` | Stable reference for the framework to report resolution back |
| `conflict_class` | Framework routes structural vs sensitivity to different resolvers |
| `peers.local.dirty_paths` | Framework needs to know ALL local uncommitted state, not just the conflicting file |
| `merge_base` | Enables three-way merge without re-computing ancestry |
| `conflicts[].content_hash` | Framework can short-circuit if hashes match (false-positive: same content, different metadata) |
| `conflicts[].fetch_ref` | Framework can lazy-fetch remote content for diff/merge without a separate discovery step |
| `conflicts[].local_exclusion_source` | For sensitivity conflicts: which config line caused the exclusion, so the human can evaluate |
| `callback` | attp tells the framework how to report resolution back — framework-agnostic (any MCP client works) |
| `resolution_hint` | Always null from attp. Reserved for framework use when forwarding events internally |

### What is deliberately absent

- **Diff hunks.** attp provides hashes and fetch refs. The framework computes diffs.
- **Resolution recommendation.** attp never suggests "accept local" or "accept remote."
- **Priority/urgency.** That is interlock's domain (see `negotiate_release` urgency levels).
- **File content.** Only hashes and fetch references. Content stays on its machine until the framework explicitly fetches it.

---

## 3. Event vs Blocking Model

**Recommendation: Non-blocking event emission with a resolution gate before token application.**

### The model

1. attp receives an incoming token.
2. attp validates crypto (Merkle proof, exclusion attestation). If invalid, reject immediately (this is NOT a conflict — it is a protocol error).
3. attp compares the token's file manifest against local state.
4. If no conflicts: apply the token (update local context). No event emitted.
5. If conflicts detected: emit `conflict_detected` event. **Do not apply the token. Do not block the transport.**
6. The token enters a `pending_resolution` state. attp holds it in a local buffer.
7. The framework calls `attp_resolve_conflict` with a resolution decision.
8. Based on resolution:
   - `accept_remote`: attp applies the incoming token, local state is overwritten.
   - `accept_local`: attp discards the incoming token, notifies the remote peer via a `conflict_resolution` token.
   - `merged`: the framework provides a merged state; attp applies it and notifies remote.
   - `deferred`: token stays in `pending_resolution`. Framework will resolve later.
   - `escalated`: token stays in `pending_resolution`. Framework routes to human.

### Why non-blocking

- Blocking the transport stalls ALL token transfer, not just the conflicting file. If agents are exchanging tokens about 10 topics and 1 file conflicts, blocking kills throughput on the other 9.
- Interlock already has a blocking-wait mode (`negotiate_release` with `wait_seconds`). The framework should own the blocking decision, not the protocol.
- The `pending_resolution` buffer gives the framework time to negotiate without attp timing out.

### Buffer limits

attp should have a configurable `max_pending_conflicts` (default: 32). If exceeded, attp emits a `conflict_overflow` event and the oldest unresolved conflict is auto-escalated to `escalated` state. This prevents unbounded memory growth from unresponsive frameworks.

---

## 4. Local State Conflicts

The hardest case: a valid incoming token conflicts with local uncommitted state that the remote peer could not have known about.

### Detection mechanism

attp maintains a **local state shadow** — a lightweight record of:
- Files with uncommitted modifications (from `git status` or equivalent)
- Files currently reserved via intermute/interlock (if interweave integration is active)
- Files the local agent has declared intent to modify (via an `intent_manifest` in outgoing tokens)

When an incoming token arrives, attp checks its `files_changed` against this shadow. Conflicts with uncommitted local state produce a `conflict_detected` event with an additional field:

```json
{
  "local_state_source": "uncommitted | reserved | intent_declared",
  "local_committed": false
}
```

### Surfacing rules

1. **Never silently accept.** If the incoming token modifies a file the local agent has dirty, attp MUST emit a conflict event. The framework decides whether the local changes are expendable.
2. **Never silently reject.** The incoming token is valid. Rejecting it without telling anyone loses work.
3. **Always surface ambiguity.** The conflict event includes `local_committed: false` so the framework knows this is not a git divergence but a working-tree collision. The resolution options are the same, but the framework may apply different heuristics (e.g., "local uncommitted changes are expendable if they are < 30 seconds old").

### Interaction with interlock reservations

If interweave is active and the local agent holds an interlock reservation on the conflicting file, attp includes the reservation metadata:

```json
{
  "interlock_reservation": {
    "reservation_id": "uuid",
    "exclusive": true,
    "reason": "Refactoring router middleware",
    "expires_at": "2026-03-19T15:00:00Z"
  }
}
```

This is informational. attp does not enforce the reservation — that is interlock's job. But including it lets a non-interlock framework make an informed decision (e.g., "the local agent explicitly reserved this file, so prefer local").

---

## 5. Stable Delegation Interface

The contract between attp and any framework's conflict resolver. This interface is framework-agnostic — a non-Demarch system can implement it.

### Contract: ConflictResolver

Any conflict resolver must implement exactly two MCP tools that attp will call:

#### Tool 1: `on_conflict_detected`

Called by attp when a conflict is detected. The resolver receives the full `conflict_detected` event (Section 2 schema).

**Input:** The `conflict_detected` event JSON.

**Output:** One of:
```json
{ "action": "resolve_now", "resolution": { "conflict_id": "...", "decision": "accept_local | accept_remote | merged", "merged_content": { "path": "base64-encoded content (only if decision=merged)" } } }
```
```json
{ "action": "defer", "reason": "Negotiating with remote agent", "ttl_seconds": 300 }
```
```json
{ "action": "escalate", "reason": "Cannot auto-resolve, needs human review" }
```

If the resolver returns `defer`, attp holds the token in `pending_resolution` and will call `on_conflict_timeout` after `ttl_seconds`.

#### Tool 2: `on_conflict_timeout`

Called by attp when a deferred conflict exceeds its TTL without resolution.

**Input:**
```json
{
  "conflict_id": "uuid-v7",
  "original_event": { "...full conflict_detected event..." },
  "deferred_at": "ISO timestamp",
  "elapsed_seconds": 300
}
```

**Output:** Same as `on_conflict_detected` — resolve, defer again (with new TTL), or escalate.

### Registration

The framework registers its conflict resolver with attp at connection time:

```json
{
  "tool": "attp_register_resolver",
  "params": {
    "resolver_name": "interweave-interlock",
    "mcp_endpoint": "unix:///tmp/interlock.sock",
    "capabilities": ["structural", "sensitivity"],
    "priority": 100
  }
}
```

If no resolver is registered, attp's default behavior is to emit `conflict_detected` events to its MCP tool response stream and hold tokens in `pending_resolution` until the client explicitly calls `attp_resolve_conflict`. This ensures attp works standalone (no framework) with manual resolution.

### Multiple resolvers

attp supports multiple registered resolvers with priority ordering. For a given conflict:
1. attp calls the highest-priority resolver that declares the relevant capability.
2. If that resolver returns `escalate`, attp falls through to the next resolver.
3. If all resolvers escalate, the conflict enters `escalated` state and surfaces to the human via MCP tool responses.

This lets Demarch register interlock for structural conflicts and a separate sensitivity-policy resolver for sensitivity conflicts, while a non-Demarch system can register a single resolver for both.

---

## 6. Structural vs Sensitivity Conflicts — Different Resolution Paths

### Structural Conflicts

**Definition:** Two agents modified the same file path, and neither modification is an ancestor of the other.

**Detection:** File path + content hash comparison against merge base.

**Resolution path (framework's job, not attp's):**
1. Three-way merge (git merge-file or equivalent)
2. If merge fails: interlock negotiation (who yields?)
3. If negotiation fails: human escalation

**attp's role:** Provide `merge_base`, both content hashes, and `fetch_ref` for the remote version. The framework does the actual merge.

**Interlock integration (interweave-specific):** interweave maps structural conflicts to interlock's `negotiate_release` protocol. The agent holding the interlock reservation has priority. If no reservation exists, interweave uses token timestamps (earlier token wins tiebreak, framework can override).

### Sensitivity Conflicts

**Definition:** The two peers disagree about what is shareable. One side's exclusion manifest conflicts with the other side's expectations.

**Detection:** Comparing exclusion attestations in the Merkle proof. Three sub-types:

| Sub-type | Meaning |
|----------|---------|
| `local_excludes_remote_includes` | Remote token references a path that local config excludes. The remote agent does not know this path is sensitive here. |
| `remote_excludes_local_includes` | Remote excluded a path that local expected to receive. Missing context, not a security issue. |
| `exclusion_proof_invalid` | Merkle verification failed — the exclusion attestation is inconsistent with the content hashes. |

**Resolution path:**
- `exclusion_proof_invalid`: Always reject the token. This is a protocol integrity failure, not a negotiable conflict. attp handles this directly (the one case where attp makes a decision — but it is a validation decision, not a resolution decision).
- `local_excludes_remote_includes`: The framework must decide whether to accept the token with the sensitive path stripped, or reject entirely. attp provides the path and the local exclusion source so the framework (or human) can evaluate.
- `remote_excludes_local_includes`: Informational. The local agent should know it is missing context. attp emits the event; the framework decides whether to proceed with incomplete information or request the remote agent to re-evaluate its exclusions.

**Sensitivity conflicts never auto-merge.** Unlike structural conflicts where three-way merge can succeed silently, sensitivity conflicts always surface to the framework because they involve policy decisions about data exposure.

---

## Boundary Summary

| Concern | Owner | Rationale |
|---------|-------|-----------|
| Detecting file-path overlap | attp | Protocol has the manifests |
| Computing merge-base | attp | Protocol tracks commit ancestry in tokens |
| Content hashing | attp | Part of Merkle tree construction |
| Exclusion proof verification | attp | Core protocol integrity |
| Emitting conflict events | attp | Protocol responsibility |
| Holding tokens pending resolution | attp | Transport buffer management |
| Three-way merge | Framework | Requires toolchain knowledge |
| Negotiation (who yields) | Framework (interlock) | Policy decision |
| Human escalation | Framework | UX concern |
| Reservation awareness | Framework (interlock) | Local coordination primitive |
| Sensitivity policy decisions | Framework + Human | Cannot be automated safely |
| Line-level / AST diffing | Framework | Resolution method, not detection |
| Build/test validation | Framework | Semantic correctness, out of protocol scope |

---

## Non-Goals (explicitly out of scope for this boundary)

- Token schema field design (covered by fd-token-schema-integrity)
- MCP tool naming/response format (covered by fd-mcp-tool-surface)
- Multi-party conflict topology (covered by fd-multiparty-topology)
- Merkle tree performance on large repos (implementation concern, not boundary concern)
- A2A bridge implications (future concern)
