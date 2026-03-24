# fd-multiparty-topology: N-Party Generalization Analysis

> Reviewer: distributed systems architect (multiparty topology focus)
> Source: `docs/brainstorms/2026-03-19-attp-interweave-brainstorm.md`
> Date: 2026-03-19

## Executive Summary

The brainstorm uses bilateral language throughout ("two people's Claude Code sessions," "sender/receiver," "symmetric topology") but never commits to bilateral data structures. This is good — the design is underspecified rather than wrongly specified. The danger is that implementors will fill in the gaps with bilateral assumptions (a `from`/`to` pair on every token, a single peer per session) that calcify before v2.

**Recommendation: Design for N from the start, ship for 2.** The cost is ~15% more schema fields and one extra abstraction (session with participant list instead of peer pair). The benefit is avoiding a flag day when the third agent arrives.

---

## 1. Agent Identity Model

### What the brainstorm says
The brainstorm describes "Machine A" and "Machine B" with a sender/receiver dynamic. No identity model is specified — no agent IDs, no participant registry, no role taxonomy.

### Where bilateral assumptions break

A `from`/`to` pair on a token is inherently 2-party. When agent C joins, every token must be re-addressed. Worse, forwarded tokens (A sends to B, B relays to C) lose provenance — C sees `from: A, to: B` and has no way to know B is authorized to forward.

### Concrete recommendation

Use a **participant set with roles**, not a sender/receiver pair.

```json
{
  "token": {
    "origin": "agent-id-a",
    "session_id": "ses_abc123",
    "participants": {
      "agent-id-a": { "role": "contributor", "joined_at": "2026-03-19T10:00:00Z" },
      "agent-id-b": { "role": "contributor", "joined_at": "2026-03-19T10:00:05Z" },
      "agent-id-c": { "role": "observer", "joined_at": "2026-03-19T10:02:00Z" }
    },
    "sequence": 7
  }
}
```

Key properties:
- **`origin`** is who produced this token (always singular — tokens are authored, not co-authored).
- **`participants`** is the session membership at token creation time. This is a snapshot, not a live roster.
- **Roles** are extensible: `contributor` (read/write), `observer` (read-only), `coordinator` (can add/remove participants). v1 ships with `contributor` only.
- **Agent IDs** are opaque strings. In the Tailscale transport, they map to `hostname.tailnet` but the protocol layer does not assume this.

For 2-party use, this collapses to a participants map with 2 entries. No fields are wasted or invalid. Adding a third agent means adding a key to the map and issuing a `participant_joined` event — no schema change.

---

## 2. Sensitivity Policy: Per-Recipient Exclusion

### What the brainstorm says
Exclusion is binary: paths are either in the Merkle tree or excluded. The policy source is `.gitignore` + `.attpignore` + explicit config. No per-recipient differentiation.

### Where bilateral assumptions break

With 2 agents, there is only one "other" — the exclusion set is global. With 3+ agents, agent A might share `config/staging.yaml` with agent B (ops partner) but not agent C (external contributor). A single exclusion set per token cannot express this.

### Concrete recommendation

**Per-recipient exclusion manifests.** The sensitivity policy is evaluated once per recipient, producing a different Merkle tree (and therefore different token) for each.

```
Session with A, B, C:

A's sensitivity policy:
  default_exclude: [".env", "secrets/"]
  per_recipient:
    agent-id-c:
      additional_exclude: ["config/staging.yaml", "internal/"]
```

Implementation:
- The `.attpignore` file defines the **floor** — paths excluded from all recipients.
- Per-recipient overrides add paths on top of the floor.
- Each token is addressed to a **specific recipient** even in a multi-party session. There is no broadcast token for content (though there can be for metadata like decisions and requests).
- This means content tokens are inherently point-to-point, while coordination tokens (decisions, work requests) can be multicast.

This is the right decomposition:
- **Content tokens** (carrying file data, diffs, ASTs): point-to-point, because the Merkle tree varies per recipient.
- **Coordination tokens** (decisions, status, requests): multicast to all participants, because they contain no sensitive file content.

```json
{
  "token": {
    "origin": "agent-id-a",
    "recipient": "agent-id-b",
    "type": "content",
    "exclusion_manifest": {
      "merkle_root": "sha256:abc...",
      "excluded_paths": ["secrets/", ".env"],
      "attestation": "sig:..."
    }
  }
}
```

```json
{
  "token": {
    "origin": "agent-id-a",
    "recipients": ["agent-id-b", "agent-id-c"],
    "type": "coordination",
    "payload": {
      "decision": "Use interface X for the adapter pattern",
      "request": "Implement tests for module Y"
    }
  }
}
```

Note the asymmetry: `recipient` (singular) for content, `recipients` (plural) for coordination. This is deliberate — it makes the sensitivity boundary structural, not a convention.

Scaling: generating N-1 different Merkle trees for N participants is O(N * tree_build_cost). For the typical case (same floor exclusion, 1-2 per-recipient overrides), the trees share structure and only the excluded subtrees differ — an incremental delta approach avoids full recomputation.

---

## 3. Conflict Model: Causal Ordering for 3+ Agents

### What the brainstorm says
"When both agents modify the same file, does attp detect/surface conflicts, or is that interlock's job via interweave?" — listed as an open question with 2-party framing ("both agents").

### Where bilateral assumptions break

With 2 agents, conflicts are always pairwise. With 3, you get diamond conflicts: A sends to B and C, both modify, then B and C's tokens conflict. A single "last writer wins" or "sender/receiver" model cannot express the causal graph.

### Concrete recommendation

**Vector clocks per participant, carried in every token.** Not a full CRDT — attp surfaces conflicts, it does not resolve them (per the fd-conflict-resolution-boundary spec).

```json
{
  "token": {
    "origin": "agent-id-b",
    "vector_clock": {
      "agent-id-a": 3,
      "agent-id-b": 5,
      "agent-id-c": 2
    },
    "parent_tokens": ["tok_abc", "tok_def"],
    "affected_paths": ["src/adapter.go", "src/adapter_test.go"]
  }
}
```

Properties:
- **Vector clock**: each agent increments its own counter on every token it produces. On receiving a token, an agent merges (component-wise max) the received clock with its own. This gives causal ordering.
- **`parent_tokens`**: explicit DAG edges. Each token references the token(s) it was based on. This is the same model as git commits — and for good reason: the agents are collaborating on a git repo, so the token DAG mirrors the commit DAG.
- **Conflict detection**: two tokens conflict if neither's vector clock dominates the other's AND they touch overlapping `affected_paths`.

Why vector clocks and not Lamport timestamps:
- Lamport timestamps give total ordering but not causal ordering. With 3 agents, you need to know "did B see A's change before editing?" — Lamport cannot answer this, vector clocks can.
- Vector clock size is O(N) per token. For coding agent sessions, N < 20 is a safe upper bound for the foreseeable future. The overhead is negligible.

Why not a full DAG/CRDT:
- attp detects conflicts and surfaces them. Resolution is interlock/interweave's job (per the boundary spec). Carrying a full CRDT state in every token is unnecessary overhead when the protocol's job is detection, not resolution.

For 2 agents, the vector clock degenerates to a pair of counters and `parent_tokens` is always a single reference. No wasted complexity.

---

## 4. Topology: Mesh vs Hub-and-Spoke on Tailscale

### What the brainstorm says
"Symmetric topology — each server controls what it shares. No central coordinator." + "Tailscale MCP server relay" + "peer-to-peer MCP servers discoverable via Tailscale DNS."

### Analysis

Tailscale is inherently a mesh — every node can reach every other node directly. The brainstorm's instinct to use symmetric/peer-to-peer is correct and Tailscale-native.

Scaling characteristics:

| Topology | Connections | Session join cost | Single point of failure | Sensitivity policy |
|---|---|---|---|---|
| Full mesh | O(N²) | Negotiate with every peer | None | Natural — each edge has its own policy |
| Hub-and-spoke | O(N) | Negotiate with hub only | Hub | Hub sees all content (breaks sensitivity model) |
| Gossip mesh | O(N log N) | Negotiate with k peers | None | Complex — forwarding must respect per-recipient exclusion |

### Concrete recommendation

**Full mesh for content, gossip/multicast for coordination.**

- **Content tokens** (file data, diffs): always point-to-point. Agent A connects directly to agent B via Tailscale. Each connection has its own sensitivity policy. This is O(N²) connections but since content is the heavy payload and N is small (< 20), this is fine.
- **Coordination tokens** (decisions, requests, status): can use gossip or relay through any participant. These contain no sensitive file content, so forwarding is safe.

Hub-and-spoke is explicitly rejected because:
1. The hub would see all content, violating the sensitivity boundary.
2. The hub is a single point of failure.
3. Tailscale's mesh makes hub-and-spoke an unnatural fit — you would be artificially restricting a mesh to a star.

Connection count reality check: for N=10 agents (an extreme case for coding collaboration), full mesh is 45 connections. Each is a long-lived MCP connection over Tailscale WireGuard. This is well within Tailscale's design parameters (Tailscale handles thousands of peers per tailnet).

For N=2, full mesh is 1 connection. No overhead from the generalized design.

---

## 5. Session/Handshake: O(N²) Bilateral vs Broadcast

### What the brainstorm says
No session or handshake model is specified. The brainstorm mentions "discovery via Tailscale DNS" but not how sessions are established.

### Where bilateral assumptions break

If sessions are bilateral (A initiates with B), adding C requires A-C and B-C handshakes, plus notifying all parties. With naive bilateral negotiation, adding the Nth agent requires N-1 new handshakes plus N-1 notifications — O(N) work per join, O(N²) total.

### Concrete recommendation

**Session-as-resource with join semantics, not bilateral pairing.**

```
Session lifecycle:
1. Agent A creates session → gets session_id
2. A invites B → B joins session (negotiates capabilities with A)
3. A or B invites C → C joins session (negotiates with existing members)
4. On join: new participant sends a `join` token with its capabilities
5. Existing participants each send a `welcome` token with their capabilities
6. Capability negotiation is the intersection of all participants' capabilities
```

Data structure:

```json
{
  "session": {
    "id": "ses_abc123",
    "created_at": "2026-03-19T10:00:00Z",
    "created_by": "agent-id-a",
    "protocol_version": "attp/0.1",
    "capabilities": ["content_transfer", "lazy_fetch", "coordination"],
    "participants": [
      {
        "agent_id": "agent-id-a",
        "endpoint": "alice-laptop.tailnet:8400",
        "capabilities": ["content_transfer", "lazy_fetch", "coordination"],
        "joined_at": "2026-03-19T10:00:00Z"
      },
      {
        "agent_id": "agent-id-b",
        "endpoint": "bob-desktop.tailnet:8400",
        "capabilities": ["content_transfer", "coordination"],
        "joined_at": "2026-03-19T10:00:05Z"
      }
    ],
    "effective_capabilities": ["content_transfer", "coordination"]
  }
}
```

Join cost: O(N) per new participant (one handshake with each existing member). Not O(N²) total because joins are incremental.

The session object lives on every participant's server (replicated, not centralized). Consistency is eventual — a participant might briefly have a stale participant list, but tokens carry a participant snapshot so the recipient can detect staleness.

For 2 agents, the session has 2 participants and 1 handshake. Identical to a naive bilateral design but with the session abstraction already in place.

---

## 6. Bilateral vs Generalizable: Component Table

| Component | Bilateral or Generalizable | Notes |
|---|---|---|
| **Token origin** | Generalizable | Single author per token works at any N |
| **Token recipient (content)** | Inherently bilateral | Per-recipient Merkle tree makes content tokens point-to-point by necessity |
| **Token recipients (coordination)** | Generalizable | Multicast to participant set |
| **Merkle exclusion proof** | Inherently bilateral | Proof is computed for a specific recipient's exclusion policy |
| **Sensitivity floor (.attpignore)** | Generalizable | Global exclusion applies to all recipients |
| **Per-recipient sensitivity overrides** | Requires N-party design | Not in brainstorm; must be added |
| **Tailscale transport** | Generalizable | Mesh is natively N-party |
| **MCP server per machine** | Generalizable | Each server handles connections from any number of peers |
| **Conflict detection** | Requires N-party design | Vector clocks needed; Lamport timestamps insufficient |
| **Session establishment** | Requires N-party design | Must be session-with-participants, not peer-pair |
| **Lazy fetch (reference resolution)** | Generalizable | Fetch is always point-to-point (ask the origin server) |
| **Repo state snapshot** | Generalizable | Branch/commit/dirty-files is per-agent, not per-pair |
| **Decision/request payloads** | Generalizable | Coordination is naturally multicast |
| **Discovery (Tailscale DNS)** | Generalizable | DNS resolution is per-host, not per-pair |

Summary: 4 components are inherently bilateral (content tokens, Merkle proofs — by design, not by limitation). 3 components need explicit N-party design now (per-recipient sensitivity, conflict detection, session establishment). The rest generalize without changes.

---

## 7. Final Recommendation

**Design for N, ship for 2.**

The cost of N-compatible primitives over bilateral primitives:

| Primitive | Bilateral cost | N-compatible cost | Delta |
|---|---|---|---|
| Token identity | `from`, `to` fields | `origin`, `participants` snapshot | +1 field (participants map) |
| Session model | Implicit (peer pair) | Explicit session object with participant list | +1 abstraction |
| Conflict ordering | Lamport timestamp (1 counter) | Vector clock (N counters) | +N-1 integers per token |
| Sensitivity policy | Single exclusion set | Floor + per-recipient overrides | +1 config section |
| Handshake | Single negotiation | Join protocol with O(N) negotiation | Same for N=2 |

For N=2, the N-compatible design adds:
- A `participants` map with 2 entries instead of a `to` field (same information, different shape).
- A vector clock with 2 entries instead of a Lamport timestamp (same information, richer).
- A session object that would exist implicitly anyway.
- A sensitivity config section that is empty when there are no per-recipient overrides.

The cost is negligible. The benefit is avoiding a breaking schema change when the third agent arrives. In protocol design, the third party always arrives sooner than expected.

### Specific actions for the attp spec

1. **Token schema**: use `origin` + `participants` snapshot, not `from`/`to`. Content tokens add `recipient` (singular). Coordination tokens add `recipients` (plural, optional — default all).
2. **Session lifecycle**: define session as a first-class resource with `create`, `join`, `leave` operations. Sessions have IDs and participant lists.
3. **Vector clocks**: include in every token. For v1, the implementation can treat a 2-entry vector clock as a pair of counters internally, but the wire format must be a map.
4. **Sensitivity config**: `.attpignore` defines the floor. `attp-policy.yaml` (or equivalent) allows per-recipient overrides. v1 can ship with floor-only support, but the config schema must have the `per_recipient` key even if it is initially empty.
5. **Content vs coordination token type**: make the distinction explicit in the schema. Content tokens are point-to-point with per-recipient Merkle trees. Coordination tokens are multicast with no file content.

### What to defer to v2

- **Participant roles beyond contributor**: observer, coordinator roles are useful but not needed for 2-party.
- **Gossip protocol for coordination**: for N < 10, direct multicast is fine.
- **Dynamic capability renegotiation**: v1 can require that adding a participant degrades to the intersection of all capabilities without renegotiation.
- **Forwarding/relay semantics**: when B forwards A's content token to C, how is provenance tracked? This is complex and not needed until someone asks for it.
