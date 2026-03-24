# attp MCP Tool Surface — API Specification

> Produced by fd-mcp-tool-surface reviewer.
> Source material: `docs/brainstorms/2026-03-19-attp-interweave-brainstorm.md`, interlock MCP patterns (`interverse/interlock/`), `sdk/interbase/go/toolerror/toolerror.go`.

## Design Principles

1. **Framework-agnostic names.** No tool name, parameter, or error code contains "Demarch", "interweave", "Tailscale", "intermute", or any framework identifier. The attp MCP server is usable by any coding agent on any platform.
2. **Follows Demarch toolerror convention** for error shapes (type/message/recoverable/data), but the error type constants are protocol-native, not imported from interbase.
3. **Idempotency documented per tool.** Every tool states whether repeat calls are safe.
4. **Atomic tools composable by higher layers.** interweave (or any integration layer) orchestrates these without knowing attp internals.

---

## 1. Tool Inventory

16 tools across 5 groups: **Discovery**, **Token Lifecycle**, **Content Transfer**, **Verification**, **Session Management**.

| # | Tool | Group | Idempotent | Summary |
|---|------|-------|------------|---------|
| 1 | `list_peers` | Discovery | Yes | List known peers and their online status |
| 2 | `peer_capabilities` | Discovery | Yes | Query a specific peer's supported protocol version and feature flags |
| 3 | `announce` | Discovery | Yes (upsert) | Register/update this server's identity and capabilities with the peer mesh |
| 4 | `push_token` | Token Lifecycle | No (creates) | Send a structured context token to a peer |
| 5 | `pull_tokens` | Token Lifecycle | Yes | Fetch inbound tokens from a peer (or all peers) |
| 6 | `ack_token` | Token Lifecycle | Yes | Acknowledge receipt/processing of a token |
| 7 | `token_status` | Token Lifecycle | Yes | Check delivery/ack status of a previously pushed token |
| 8 | `fetch_content` | Content Transfer | Yes | Lazy-fetch a referenced file/blob from a peer by content hash |
| 9 | `list_available` | Content Transfer | Yes | List fetchable content references from a peer (what they offer) |
| 10 | `verify_token` | Verification | Yes | Verify a token's Merkle root, exclusion proof, and signature |
| 11 | `verify_content` | Verification | Yes | Verify a fetched blob against its content hash |
| 12 | `exclusion_manifest` | Verification | Yes | Return this server's current exclusion manifest (what paths are excluded and why) |
| 13 | `create_session` | Session Mgmt | No (creates) | Establish a collaboration session with a peer |
| 14 | `session_status` | Session Mgmt | Yes | Get current session state, last activity, token counts |
| 15 | `end_session` | Session Mgmt | Yes | Gracefully end a collaboration session |
| 16 | `configure_policy` | Session Mgmt | Yes (upsert) | Set sensitivity policy, auto-share rules, and content filters |

---

## 2. Request/Response Schemas

### 2.1 Discovery

#### `list_peers`

Lists all known peers. No parameters required.

```json
// Request
{}

// Response
{
  "peers": [
    {
      "peer_id": "alice-laptop",
      "display_name": "Alice",
      "endpoint": "alice-laptop.example:8400",
      "status": "online",
      "protocol_version": "1.0",
      "last_seen": "2026-03-19T10:23:00Z",
      "active_session": "sess_a1b2c3"
    }
  ]
}
```

**Parameters:** None.
**Idempotency:** Yes — read-only.

#### `peer_capabilities`

```json
// Request
{
  "peer_id": "alice-laptop"   // required: string
}

// Response
{
  "peer_id": "alice-laptop",
  "protocol_version": "1.0",
  "features": [
    "merkle_exclusion_v1",
    "lazy_fetch",
    "incremental_tree",
    "content_types:diff,ast,file,tree"
  ],
  "max_token_bytes": 1048576,
  "supported_hash_algorithms": ["sha256", "blake3"],
  "status": "online"
}

// Error when peer is offline
{
  "type": "PEER_UNAVAILABLE",
  "message": "peer 'alice-laptop' is not reachable",
  "recoverable": true,
  "data": { "peer_id": "alice-laptop", "last_seen": "2026-03-19T09:00:00Z" }
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `peer_id` | string | yes | Peer identifier to query |

**Idempotency:** Yes — read-only.

#### `announce`

Registers or updates this server's presence and capabilities in the peer mesh. Servers call this on startup and periodically as a heartbeat.

```json
// Request
{
  "display_name": "Bob",                    // optional: string
  "features": ["merkle_exclusion_v1", "lazy_fetch"],  // optional: string[]
  "metadata": {                             // optional: object, free-form
    "repo": "my-project",
    "branch": "main"
  }
}

// Response
{
  "peer_id": "bob-desktop",
  "announced": true,
  "ttl_seconds": 300
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `display_name` | string | no | Human-readable name for this peer |
| `features` | string[] | no | Feature flags this server supports |
| `metadata` | object | no | Arbitrary key-value metadata (repo, branch, etc.) |

**Idempotency:** Yes — upsert semantics. Repeated calls refresh the heartbeat TTL.

---

### 2.2 Token Lifecycle

#### `push_token`

Sends a structured context token to a peer. This is the core operation of attp — packaging repo state, decisions, requests, and selectively inlined content into a verifiable token.

```json
// Request
{
  "peer_id": "alice-laptop",               // required: string
  "session_id": "sess_a1b2c3",            // required: string
  "token": {                               // required: object
    "version": "1.0",
    "type": "context_update",              // "context_update" | "work_request" | "review_request" | "decision" | "question"
    "repo_state": {
      "branch": "main",
      "commit": "abc123f",
      "dirty_files": ["src/handler.go", "tests/handler_test.go"]
    },
    "decisions": [
      {
        "id": "d_001",
        "summary": "Using middleware pattern for auth",
        "rationale": "Keeps handler functions clean",
        "timestamp": "2026-03-19T10:00:00Z"
      }
    ],
    "requests": [
      {
        "id": "r_001",
        "type": "review",
        "description": "Review auth middleware implementation",
        "files": ["src/middleware/auth.go"],
        "priority": "normal"
      }
    ],
    "inlined_content": [
      {
        "path": "src/middleware/auth.go",
        "content_hash": "sha256:e3b0c44298fc...",
        "content": "package middleware\n\nfunc AuthMiddleware..."
      }
    ],
    "content_refs": [
      {
        "path": "src/handler.go",
        "content_hash": "sha256:d7a8fbb307d7...",
        "size_bytes": 15234,
        "fetch_hint": "lazy"
      }
    ]
  },
  "merkle_root": "sha256:9f86d081884c...", // required: string
  "exclusion_proof": {                      // required: object
    "algorithm": "sha256",
    "excluded_count": 3,
    "attestation": "base64-encoded-signature...",
    "excluded_patterns": [".env*", "secrets/", "data/pii/"]
  }
}

// Response
{
  "token_id": "tok_x7y8z9",
  "peer_id": "alice-laptop",
  "session_id": "sess_a1b2c3",
  "status": "delivered",
  "delivered_at": "2026-03-19T10:24:00Z",
  "size_bytes": 4321
}

// Response when peer is offline (queued)
{
  "token_id": "tok_x7y8z9",
  "peer_id": "alice-laptop",
  "session_id": "sess_a1b2c3",
  "status": "queued",
  "queued_at": "2026-03-19T10:24:00Z",
  "size_bytes": 4321,
  "ttl_seconds": 3600
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `peer_id` | string | yes | Target peer |
| `session_id` | string | yes | Collaboration session this token belongs to |
| `token` | object | yes | The context token payload (see schema above) |
| `merkle_root` | string | yes | Hash of the repo Merkle tree root |
| `exclusion_proof` | object | yes | Cryptographic attestation of excluded paths |

**Idempotency:** No — each call creates a new token. Duplicate detection is by `token_id` in responses.

#### `pull_tokens`

```json
// Request
{
  "session_id": "sess_a1b2c3",            // optional: string (filter by session)
  "peer_id": "bob-desktop",               // optional: string (filter by sender)
  "since": "2026-03-19T10:00:00Z",        // optional: ISO 8601 timestamp
  "cursor": "cur_abc123",                  // optional: pagination cursor
  "limit": 10,                            // optional: integer, default 20, max 100
  "status_filter": "unacked"              // optional: "all" | "unacked" | "acked", default "unacked"
}

// Response
{
  "tokens": [
    {
      "token_id": "tok_x7y8z9",
      "from_peer": "bob-desktop",
      "session_id": "sess_a1b2c3",
      "received_at": "2026-03-19T10:24:00Z",
      "acked": false,
      "token": { "...full token payload..." },
      "merkle_root": "sha256:9f86d081884c...",
      "exclusion_proof": { "..." },
      "verified": true
    }
  ],
  "next_cursor": "cur_def456",
  "total_unacked": 3
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `session_id` | string | no | Filter tokens by session |
| `peer_id` | string | no | Filter tokens by sending peer |
| `since` | string | no | Only return tokens received after this ISO 8601 timestamp |
| `cursor` | string | no | Pagination cursor from previous response |
| `limit` | integer | no | Max tokens to return (default: 20, max: 100) |
| `status_filter` | string | no | Filter by ack status: "all", "unacked", "acked" (default: "unacked") |

**Idempotency:** Yes — read-only with cursor-based pagination.

#### `ack_token`

```json
// Request
{
  "token_id": "tok_x7y8z9",               // required: string
  "disposition": "accepted",              // required: "accepted" | "rejected" | "partial"
  "notes": "Reviewed auth middleware, looks good"  // optional: string
}

// Response
{
  "token_id": "tok_x7y8z9",
  "acked": true,
  "disposition": "accepted",
  "acked_at": "2026-03-19T10:30:00Z"
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `token_id` | string | yes | Token to acknowledge |
| `disposition` | string | yes | How the token was handled |
| `notes` | string | no | Free-form response to the sender |

**Idempotency:** Yes — re-acking with the same disposition is a no-op. Re-acking with a different disposition updates it.

#### `token_status`

```json
// Request
{
  "token_id": "tok_x7y8z9"                // required: string
}

// Response
{
  "token_id": "tok_x7y8z9",
  "peer_id": "alice-laptop",
  "session_id": "sess_a1b2c3",
  "status": "acked",
  "delivered_at": "2026-03-19T10:24:00Z",
  "acked_at": "2026-03-19T10:30:00Z",
  "disposition": "accepted",
  "notes": "Reviewed auth middleware, looks good"
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `token_id` | string | yes | Token to check status of |

**Idempotency:** Yes — read-only.

---

### 2.3 Content Transfer

#### `fetch_content`

Lazy-fetches a file or blob from a peer by its content hash (referenced in a token's `content_refs`).

```json
// Request
{
  "peer_id": "bob-desktop",                // required: string
  "content_hash": "sha256:d7a8fbb307d7...",  // required: string
  "session_id": "sess_a1b2c3"             // required: string (for access control)
}

// Response
{
  "content_hash": "sha256:d7a8fbb307d7...",
  "path": "src/handler.go",
  "content": "package main\n\nfunc Handle...",
  "size_bytes": 15234,
  "verified": true
}

// Error when content is excluded by policy
{
  "type": "CONTENT_EXCLUDED",
  "message": "content at 'secrets/api.key' is excluded by sender's sensitivity policy",
  "recoverable": false,
  "data": {
    "content_hash": "sha256:abc123...",
    "excluded_by": "sensitivity_policy"
  }
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `peer_id` | string | yes | Peer that owns the content |
| `content_hash` | string | yes | Content-addressed hash from a token's `content_refs` |
| `session_id` | string | yes | Session context (server validates the requesting peer has a token referencing this hash in this session) |

**Idempotency:** Yes — content-addressed, same hash always returns same content.

#### `list_available`

Lists content references a peer is willing to share in the current session.

```json
// Request
{
  "peer_id": "bob-desktop",                // required: string
  "session_id": "sess_a1b2c3",            // required: string
  "path_prefix": "src/",                  // optional: string (filter by path prefix)
  "limit": 50                             // optional: integer, default 100
}

// Response
{
  "peer_id": "bob-desktop",
  "refs": [
    {
      "path": "src/handler.go",
      "content_hash": "sha256:d7a8fbb307d7...",
      "size_bytes": 15234,
      "modified_at": "2026-03-19T09:45:00Z"
    },
    {
      "path": "src/router.go",
      "content_hash": "sha256:4e074085b5...",
      "size_bytes": 8901,
      "modified_at": "2026-03-19T09:30:00Z"
    }
  ],
  "excluded_count": 3,
  "total_available": 127
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `peer_id` | string | yes | Peer to list content from |
| `session_id` | string | yes | Session context for access control |
| `path_prefix` | string | no | Filter results to paths starting with this prefix |
| `limit` | integer | no | Max results (default: 100) |

**Idempotency:** Yes — read-only.

---

### 2.4 Verification

#### `verify_token`

Verifies a token's integrity: Merkle root consistency, exclusion proof validity, and signature.

```json
// Request
{
  "token_id": "tok_x7y8z9"                // required: string
}

// Response (valid)
{
  "token_id": "tok_x7y8z9",
  "valid": true,
  "checks": {
    "merkle_root": "pass",
    "exclusion_proof": "pass",
    "signature": "pass",
    "content_hashes": "pass"
  }
}

// Response (invalid)
{
  "token_id": "tok_x7y8z9",
  "valid": false,
  "checks": {
    "merkle_root": "pass",
    "exclusion_proof": "fail",
    "signature": "pass",
    "content_hashes": "pass"
  },
  "failures": [
    {
      "check": "exclusion_proof",
      "detail": "attestation signature does not match Merkle root",
      "severity": "error"
    }
  ]
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `token_id` | string | yes | Token to verify (must have been received via `pull_tokens`) |

**Idempotency:** Yes — deterministic verification.

#### `verify_content`

Verifies a fetched blob's integrity against its content hash.

```json
// Request
{
  "content_hash": "sha256:d7a8fbb307d7...",  // required: string
  "content": "package main\n\nfunc Handle..."  // required: string
}

// Response
{
  "content_hash": "sha256:d7a8fbb307d7...",
  "valid": true,
  "algorithm": "sha256"
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `content_hash` | string | yes | Expected hash |
| `content` | string | yes | Content to verify |

**Idempotency:** Yes — pure function.

#### `exclusion_manifest`

Returns this server's current exclusion policy. Allows peers to understand what the sender is withholding and why, without revealing the content itself.

```json
// Request
{}

// Response
{
  "patterns": [
    { "pattern": ".env*", "source": "gitignore", "reason": "environment variables" },
    { "pattern": "secrets/", "source": "attpignore", "reason": "credential store" },
    { "pattern": "data/pii/", "source": "policy_config", "reason": "personally identifiable information" }
  ],
  "excluded_file_count": 7,
  "total_file_count": 1234,
  "hash_algorithm": "sha256"
}
```

**Parameters:** None.
**Idempotency:** Yes — read-only (may change between calls if policy is updated).

---

### 2.5 Session Management

#### `create_session`

Establishes a collaboration session with a peer. Sessions scope token exchange, access control, and content sharing. Both peers must create sessions that reference each other.

```json
// Request
{
  "peer_id": "alice-laptop",               // required: string
  "repo_identifier": "my-project",         // required: string (shared repo name for correlation)
  "purpose": "Implement auth middleware",  // optional: string
  "ttl_hours": 24                          // optional: integer, default 24, max 168 (7 days)
}

// Response
{
  "session_id": "sess_a1b2c3",
  "peer_id": "alice-laptop",
  "repo_identifier": "my-project",
  "created_at": "2026-03-19T10:00:00Z",
  "expires_at": "2026-03-20T10:00:00Z",
  "status": "active"
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `peer_id` | string | yes | Peer to establish session with |
| `repo_identifier` | string | yes | Shared repo name (for session correlation; not a filesystem path) |
| `purpose` | string | no | Human-readable session purpose |
| `ttl_hours` | integer | no | Session lifetime in hours (default: 24, max: 168) |

**Idempotency:** No — creates a new session each time. Use `session_status` to check existing sessions.

#### `session_status`

```json
// Request
{
  "session_id": "sess_a1b2c3"             // required: string
}

// Response
{
  "session_id": "sess_a1b2c3",
  "peer_id": "alice-laptop",
  "repo_identifier": "my-project",
  "status": "active",
  "created_at": "2026-03-19T10:00:00Z",
  "expires_at": "2026-03-20T10:00:00Z",
  "last_activity": "2026-03-19T10:30:00Z",
  "tokens_sent": 5,
  "tokens_received": 3,
  "tokens_unacked": 1
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `session_id` | string | yes | Session to query |

**Idempotency:** Yes — read-only.

#### `end_session`

```json
// Request
{
  "session_id": "sess_a1b2c3",            // required: string
  "reason": "Work complete"                // optional: string
}

// Response
{
  "session_id": "sess_a1b2c3",
  "status": "ended",
  "ended_at": "2026-03-19T12:00:00Z",
  "final_stats": {
    "tokens_sent": 8,
    "tokens_received": 5,
    "duration_minutes": 120
  }
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `session_id` | string | yes | Session to end |
| `reason` | string | no | Why the session is ending |

**Idempotency:** Yes — ending an already-ended session returns the same response.

#### `configure_policy`

```json
// Request
{
  "sensitivity_sources": ["gitignore", "attpignore"],  // optional: string[]
  "additional_excludes": ["*.key", "internal/"],       // optional: string[]
  "auto_inline_threshold_bytes": 4096,                 // optional: integer, default 4096
  "allowed_content_types": ["diff", "ast", "file", "tree"],  // optional: string[]
  "max_token_bytes": 1048576                           // optional: integer, default 1MB
}

// Response
{
  "updated": true,
  "effective_policy": {
    "sensitivity_sources": ["gitignore", "attpignore"],
    "additional_excludes": ["*.key", "internal/"],
    "auto_inline_threshold_bytes": 4096,
    "allowed_content_types": ["diff", "ast", "file", "tree"],
    "max_token_bytes": 1048576,
    "total_excluded_patterns": 12
  }
}
```

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `sensitivity_sources` | string[] | no | Where to read exclusion patterns from |
| `additional_excludes` | string[] | no | Extra glob patterns to exclude beyond source files |
| `auto_inline_threshold_bytes` | integer | no | Files smaller than this are auto-inlined in tokens |
| `allowed_content_types` | string[] | no | Content types this server will include in tokens |
| `max_token_bytes` | integer | no | Maximum token payload size |

**Idempotency:** Yes — upsert semantics. Omitted fields retain their current value.

---

## 3. Error Taxonomy

### Error Type Constants

| Type | Recoverable | HTTP Analog | When Used |
|------|-------------|-------------|-----------|
| `VALIDATION` | false | 400 | Malformed request, missing required fields, invalid enum value |
| `PEER_UNAVAILABLE` | true | 503 | Peer is offline or unreachable; retry after backoff |
| `PEER_NOT_FOUND` | false | 404 | No peer with that ID exists in the mesh |
| `SESSION_NOT_FOUND` | false | 404 | No session with that ID exists |
| `SESSION_EXPIRED` | false | 410 | Session existed but has expired; create a new one |
| `TOKEN_NOT_FOUND` | false | 404 | No token with that ID exists |
| `CONTENT_EXCLUDED` | false | 403 | Requested content is excluded by the sender's sensitivity policy |
| `CONTENT_NOT_FOUND` | false | 404 | Content hash not found on the peer |
| `VERIFICATION_FAILED` | false | 422 | Token or content failed integrity verification |
| `VERSION_MISMATCH` | false | 409 | Peer runs an incompatible protocol version |
| `CAPABILITY_MISSING` | false | 501 | Peer does not support a required feature |
| `POLICY_VIOLATION` | false | 403 | Request violates the local sensitivity policy (e.g., trying to share excluded content) |
| `RATE_LIMITED` | true | 429 | Too many requests; retry after `retry_after_seconds` |
| `TOKEN_TOO_LARGE` | false | 413 | Token payload exceeds `max_token_bytes` |
| `TRANSIENT` | true | 500 | Unexpected server error, safe to retry |
| `INTERNAL` | false | 500 | Unexpected server error, not safe to retry |

### Error Response Shape

Every error response follows this structure (consistent with Demarch's `toolerror` convention but using attp-native type constants):

```json
{
  "type": "PEER_UNAVAILABLE",
  "message": "peer 'alice-laptop' is not reachable (last seen 2026-03-19T09:00:00Z)",
  "recoverable": true,
  "data": {
    "peer_id": "alice-laptop",
    "last_seen": "2026-03-19T09:00:00Z",
    "retry_after_seconds": 30
  }
}
```

### Recovery Matrix

| Category | Error Types | Agent Action |
|----------|-------------|-------------|
| **Retry with backoff** | `PEER_UNAVAILABLE`, `RATE_LIMITED`, `TRANSIENT` | Wait `retry_after_seconds` (or exponential backoff if not provided), then retry same call |
| **Fix input, retry** | `VALIDATION`, `TOKEN_TOO_LARGE` | Correct the request parameters, then retry |
| **Create new resource** | `SESSION_EXPIRED` | Create a new session with `create_session`, then retry the original operation |
| **Negotiate capability** | `VERSION_MISMATCH`, `CAPABILITY_MISSING` | Call `peer_capabilities` to discover what the peer supports, then adapt |
| **Do not retry** | `PEER_NOT_FOUND`, `SESSION_NOT_FOUND`, `TOKEN_NOT_FOUND`, `CONTENT_NOT_FOUND`, `CONTENT_EXCLUDED`, `POLICY_VIOLATION`, `VERIFICATION_FAILED`, `INTERNAL` | Surface to the user/orchestrating layer. These indicate a fundamental problem, not a transient one |

---

## 4. Capability Negotiation

### Protocol Version and Feature Flags

Each attp server advertises:
- **`protocol_version`**: semver string (e.g., `"1.0"`). Major version changes are breaking.
- **`features`**: list of feature flag strings.

### Negotiation Flow

```
Agent A                          Agent B
  │                                 │
  ├──── announce() ─────────────────>│  (registers A in B's peer list)
  │                                 │
  │<──── announce() ────────────────┤  (registers B in A's peer list)
  │                                 │
  ├──── peer_capabilities("B") ────>│  (A discovers B's version + features)
  │                                 │
  │   [A checks: does B support     │
  │    merkle_exclusion_v1?         │
  │    Is protocol_version >= 1.0?] │
  │                                 │
  ├──── create_session("B") ───────>│  (A establishes session)
  │                                 │
  ├──── push_token("B", ...) ──────>│  (A sends first token)
  │                                 │
```

### Feature Flag Registry (v1.0)

| Flag | Description | Required for v1 |
|------|-------------|-----------------|
| `merkle_exclusion_v1` | Supports Merkle-tree exclusion proofs | yes |
| `lazy_fetch` | Supports `fetch_content` for content-addressed lazy loading | yes |
| `incremental_tree` | Supports incremental Merkle tree updates (not full rebuild per token) | no |
| `content_types:X,Y` | Comma-separated content types supported (diff, ast, file, tree) | yes (at least `file`) |

### Version Mismatch Error

When a peer receives a request from an incompatible version:

```json
{
  "type": "VERSION_MISMATCH",
  "message": "peer requires protocol_version >= 2.0, this server supports 1.0",
  "recoverable": false,
  "data": {
    "local_version": "1.0",
    "required_version": "2.0",
    "supported_features": ["merkle_exclusion_v1", "lazy_fetch"]
  }
}
```

### Missing Capability Error

When a specific feature is required but the peer does not support it:

```json
{
  "type": "CAPABILITY_MISSING",
  "message": "peer 'alice-laptop' does not support feature 'incremental_tree'",
  "recoverable": false,
  "data": {
    "peer_id": "alice-laptop",
    "missing_feature": "incremental_tree",
    "peer_features": ["merkle_exclusion_v1", "lazy_fetch", "content_types:file,diff"]
  }
}
```

---

## 5. Framework-Agnosticism Audit

### Naming Compliance

Every tool name, parameter name, and error type was checked against the following exclusion list: `Demarch`, `interweave`, `intercore`, `intermute`, `interlock`, `Tailscale`, `tailnet`, `Clavain`, `Skaffen`, `Autarch`.

**Result: zero leaks.** The tool surface uses only generic terms:
- `peer_id` (not `tailnet_host`)
- `endpoint` (not `tailscale_address`)
- `session_id` (not `intermute_session`)
- `content_hash` (not `merkle_node_id`)

### Transport Abstraction

The `endpoint` field in `list_peers` responses is an opaque string. The protocol spec does not define its format — implementations choose their transport. A Tailscale implementation would populate it as `hostname.tailnet:8400`; an SSH tunnel implementation might use `localhost:8400`; a WebSocket implementation might use `wss://relay.example/peer/alice`.

No tool parameter requires or references a transport mechanism.

### Integration Points

An integration layer (e.g., interweave) composes these tools without attp knowing about it:

1. **Session startup**: `announce()` + `peer_capabilities()` + `create_session()` — interweave maps intermute agent IDs to attp peer IDs.
2. **Context sync**: `push_token()` + `pull_tokens()` + `ack_token()` — interweave decides when to push based on intercore routing events.
3. **Conflict surface**: `list_available()` + `fetch_content()` — interweave feeds content refs to interlock for reservation checks.
4. **Teardown**: `end_session()` — interweave calls this when intermute detects agent departure.

The attp tools are atomic and composable. No tool assumes it will be called in a specific sequence (except `create_session` must precede `push_token` for a given session, enforced by `SESSION_NOT_FOUND` errors).

---

## 6. Design Notes

### Why 16 tools, not fewer

The brainstorm lists 4 candidate tools (`attp_send_token`, `attp_fetch_file`, `attp_list_peers`, `attp_verify_token`). This spec expands to 16 because:

1. **Token lifecycle needs ack/status tracking.** Without `ack_token` and `token_status`, the sender cannot know if the peer processed their context. This causes redundant re-sends and lost work.
2. **Sessions scope access control.** Without `create_session`, every `fetch_content` call would need full re-authentication. Sessions are the access control boundary.
3. **Policy configuration must be a tool.** If sensitivity policy is only file-based (`.attpignore`), agents cannot adjust it at runtime (e.g., temporarily sharing a file that is normally excluded). `configure_policy` makes policy a first-class runtime concept.
4. **Capability negotiation prevents silent failures.** Without `peer_capabilities` and `announce`, an agent pushing tokens to an older peer would get opaque errors instead of "you need feature X."

### Interlock Pattern Reuse

This spec follows interlock's established patterns:
- **Partial success with error arrays** (cf. `reserve_files` returning `{reservations: [...], errors: [...]}`): `push_token` does not use this because tokens are atomic, but `pull_tokens` returns individual verification status per token.
- **Thread-based negotiation** (cf. `negotiate_release`): Token ack/status tracking serves a similar role but is simpler — no escalation path needed because tokens are not locks.
- **Structured error taxonomy** (cf. `toToolError` mapping HTTP codes to toolerror types): Extended with attp-specific error types while keeping the same `{type, message, recoverable, data}` shape.
- **Cursor-based pagination** (cf. `fetch_inbox`): Used in `pull_tokens` and `list_available`.

### What This Spec Does NOT Cover

- **Token schema internals**: The `token` object structure shown in `push_token` is illustrative. The canonical token schema is owned by fd-token-schema-integrity.
- **Merkle tree construction**: How the exclusion proof is generated and what makes it valid is owned by fd-merkle-exclusion-strategy.
- **Conflict resolution**: When two agents modify the same file, how that conflict is surfaced through tokens is owned by fd-conflict-resolution-boundary.
- **Transport binding**: How peers discover each other's endpoints (Tailscale DNS, mDNS, manual config) is a transport concern, not a tool surface concern.
