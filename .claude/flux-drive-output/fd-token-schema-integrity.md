# fd-token-schema-integrity — Token Schema Review

> Reviewer: protocol specification engineer (token schema integrity)
> Source: `/home/mk/projects/Sylveste/docs/brainstorms/2026-03-19-attp-interweave-brainstorm.md`
> Comparison: Intercom `handoff.json` schema, Clavain `handoff.md` format
> Date: 2026-03-19

## Executive Summary

The brainstorm identifies the right high-level shape (hybrid payloads, crypto-enforced sensitivity, versioned JSON tokens) but leaves the schema entirely unspecified. The "open questions" section explicitly calls this out: "Token schema specifics: exact fields, nesting, versioning strategy. Needs spec work in the attp repo." This review provides that spec work.

Key risks if the schema is designed loosely:
- **Silent data loss** if inline vs. reference payloads share a field without a discriminator
- **Version deadlocks** if the versioning strategy doesn't support forward compatibility (old consumers receiving tokens from newer producers)
- **Sensitivity metadata opacity** if exclusion information lives only inside the Merkle proof and not in human-readable token fields

---

## 1. Proposed Top-Level JSON Structure

The token must be fully self-describing. A consumer with no prior state should be able to parse any valid token and extract: what repo state it describes, what content is included, what content was excluded, who produced it, and how to fetch anything not inlined.

```json
{
  "attp": "1.0",
  "id": "attp_01J7X3K9M2...",
  "created_at": "2026-03-19T14:30:00Z",
  "provenance": { ... },
  "repo": { ... },
  "sensitivity": { ... },
  "payloads": [ ... ],
  "requests": [ ... ],
  "decisions": [ ... ],
  "extensions": { ... }
}
```

### Field definitions

| Field | Type | Required | Description |
|---|---|---|---|
| `attp` | `string` | yes | Protocol version (see section 2). Always present, always first field by convention. |
| `id` | `string` | yes | Unique token ID. Format: `attp_` + 20-char base62. Globally unique, not sequential. |
| `created_at` | `string` | yes | ISO 8601 timestamp with timezone. When the token was assembled. |
| `provenance` | `object` | yes | Origin and chain-of-custody metadata (see section 5). |
| `repo` | `object` | yes | Repository state snapshot. |
| `sensitivity` | `object` | yes | Exclusion manifest and attestation (see section 3). |
| `payloads` | `array` | yes | Content items, each either inline or reference (see section 4). May be empty `[]`. |
| `requests` | `array` | no | Work requests from sender to receiver. Structured asks, not prose. |
| `decisions` | `array` | no | Decisions made by sender that receiver should know about. |
| `extensions` | `object` | no | Namespaced extension data (see section on framework-agnostic positioning). |

### `repo` object

```json
{
  "repo": {
    "url": "git@github.com:org/repo.git",
    "branch": "main",
    "commit": "a1b2c3d4e5f6...",
    "dirty_paths": ["src/auth.go", "config.yaml"],
    "merkle_root": "sha256:abcdef..."
  }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `url` | `string` | yes | Canonical repo URL. Used for identity, not cloning. |
| `branch` | `string` | yes | Current branch name. |
| `commit` | `string` | yes | Full commit SHA at token creation time. |
| `dirty_paths` | `string[]` | yes | Paths with uncommitted changes (may be empty). |
| `merkle_root` | `string` | yes | Content-addressed root hash of the repo tree. Format: `algorithm:hex`. |

### `requests` array items

```json
{
  "kind": "review",
  "summary": "Review auth middleware changes for timing attack vectors",
  "paths": ["src/auth/middleware.go"],
  "priority": "high"
}
```

| Field | Type | Required |
|---|---|---|
| `kind` | `string` (enum: `"review"`, `"implement"`, `"debug"`, `"question"`, `"other"`) | yes |
| `summary` | `string` | yes |
| `paths` | `string[]` | no |
| `priority` | `string` (enum: `"high"`, `"normal"`, `"low"`) | no (default: `"normal"`) |

### `decisions` array items

```json
{
  "summary": "Chose bcrypt over argon2 due to library maturity",
  "rationale": "argon2 Go bindings require CGO; bcrypt is pure Go",
  "paths": ["src/auth/hash.go"],
  "reversible": true
}
```

| Field | Type | Required |
|---|---|---|
| `summary` | `string` | yes |
| `rationale` | `string` | no |
| `paths` | `string[]` | no |
| `reversible` | `boolean` | no (default: `true`) |

---

## 2. Versioning Strategy

**Recommendation: two-component `major.minor` string, not semver, not monotonic integer.**

Rationale:
- Semver's patch component is meaningless for a wire format — there are no "bug fixes" to a schema, only additions or breaking changes.
- Monotonic integers (1, 2, 3) provide no signal about compatibility. A consumer seeing version `7` has no idea if it can handle it.
- `major.minor` is the standard for interchange formats (JSON:API uses `1.1`, OpenAPI uses `3.1`, JSON Schema uses `draft/2020-12` but effectively major.minor).

### Rules

1. **Minor bump** (e.g., `1.0` -> `1.1`): New optional fields added. Old consumers MUST ignore unknown fields (see below). New consumers SHOULD NOT require new fields.
2. **Major bump** (e.g., `1.x` -> `2.0`): Breaking change — field removed, field type changed, required field added. Consumers MUST reject tokens with an unrecognized major version.
3. **Unknown field policy: ignore and forward.** A consumer encountering a field it doesn't recognize MUST preserve it in any re-serialization (forwarding). It MUST NOT reject the token. This enables minor-version additions without flag-day upgrades.
4. **`attp` field is always a string**, never a number. `"1.0"` not `1.0`. This avoids JSON numeric precision issues and allows future non-numeric suffixes if needed (e.g., `"1.0-rc1"` during development).

### Compatibility matrix

```
Consumer 1.0, Token 1.0  →  full support
Consumer 1.0, Token 1.3  →  works, ignores unknown fields
Consumer 1.0, Token 2.0  →  REJECT (unknown major version)
Consumer 2.0, Token 1.0  →  MAY support (backward compat at implementor discretion)
```

### Concrete validation logic

```
Parse attp field as "MAJOR.MINOR"
If MAJOR != supported_major → reject with error "unsupported attp version"
If MINOR > supported_minor → warn "token from newer minor version, some fields may be ignored"
Proceed with parsing, skipping unknown fields
```

### Comparison with Intercom's handoff.json

Intercom uses `version: 1` (integer literal, not a string). The reader does `if (parsed.version !== 1) return null` — a hard reject of any version other than exactly `1`. This is appropriate for a local-only, single-implementation file. For attp (cross-machine, multi-implementation, framework-agnostic), the stricter major.minor string approach is necessary.

---

## 3. Sensitivity Metadata Representation

The brainstorm describes Merkle tree exclusion proofs but doesn't specify how excluded paths appear in the token itself. The token MUST be self-describing without requiring proof verification.

### `sensitivity` object

```json
{
  "sensitivity": {
    "policy": "gitignore+attpignore",
    "excluded_paths": [
      "credentials/",
      "data/pii/",
      ".env",
      "internal/proprietary/"
    ],
    "excluded_count": 47,
    "exclusion_attestation": {
      "merkle_root": "sha256:abcdef...",
      "algorithm": "sha256",
      "proof": "base64-encoded-exclusion-proof",
      "signer": "tailscale:alice-laptop"
    },
    "classification": {
      "credentials/": "secret",
      "data/pii/": "pii",
      ".env": "secret",
      "internal/proprietary/": "proprietary"
    }
  }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `policy` | `string` | yes | Human-readable label for the exclusion policy that was applied. Not parsed programmatically. |
| `excluded_paths` | `string[]` | yes | Directory and file paths that were excluded. Directories end with `/`. These are the paths themselves, not their content. Revealing path names is acceptable in attp's threat model (prevents accidental content leaks, not path enumeration). |
| `excluded_count` | `integer` | yes | Total number of individual files excluded (post-glob expansion). Provides magnitude without enumerating every file. |
| `exclusion_attestation` | `object` | yes | Crypto proof that the listed paths were actually excluded. |
| `classification` | `object` | no | Optional per-path sensitivity labels. Values are free-form strings, but recommended vocabulary: `"secret"`, `"pii"`, `"proprietary"`, `"internal"`. |

### Design rationale

- **`excluded_paths` is required** because the token must be self-describing. A receiver needs to know "the sender excluded `credentials/`" without running Merkle proof verification. The proof is for *cryptographic* verification; the path list is for *human and agent comprehension*.
- **Path names are not sensitive** in attp's stated threat model ("prevents accidental leaks, not malicious exfiltration"). If path names are sensitive, a future minor version could add an `excluded_paths_redacted: true` flag and omit the array.
- **`excluded_count`** serves as a sanity check. If `excluded_paths` lists 3 directories but `excluded_count` is 47, the receiver knows there are 47 files across those 3 directories. This prevents confusion about granularity.
- **`classification`** is optional because not all users will categorize their sensitive data. But when present, it enables the receiver's agent to make better decisions (e.g., "I can ask about the auth *architecture* but shouldn't ask for credential values").

---

## 4. Hybrid Payload Disambiguation

The brainstorm describes three tiers: "always included," "inlined when small," and "referenced for lazy fetch." The schema must make the tier unambiguous without requiring the consumer to probe the content.

### `payloads` array items — discriminated union via `mode` field

Every payload item has a `mode` field that is either `"inline"` or `"ref"`. There is no third option and no implicit mode.

#### Inline payload

```json
{
  "mode": "inline",
  "path": "src/auth/types.go",
  "content_type": "text/x-go",
  "content": "package auth\n\ntype User struct {\n\tID string\n\tEmail string\n}",
  "hash": "sha256:9f86d08...",
  "size_bytes": 73
}
```

#### Reference payload

```json
{
  "mode": "ref",
  "path": "src/auth/middleware.go",
  "content_type": "text/x-go",
  "hash": "sha256:4e1243b...",
  "size_bytes": 12847,
  "fetch_via": "attp_fetch_file"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `mode` | `"inline"` or `"ref"` | yes | Discriminator. Determines whether `content` is present. |
| `path` | `string` | yes | Repo-relative file path. |
| `content_type` | `string` | yes | MIME type or `text/x-{lang}` for source files. |
| `content` | `string` | yes if `mode: "inline"`, absent if `mode: "ref"` | The file content, UTF-8 encoded. Binary files should use `"ref"` mode. |
| `hash` | `string` | yes | Content hash in `algorithm:hex` format. For inline payloads, consumer SHOULD verify hash matches content. For ref payloads, used as cache key and integrity check after fetch. |
| `size_bytes` | `integer` | yes | Content size in bytes. For ref payloads, allows the consumer to decide whether to fetch before committing. |
| `fetch_via` | `string` | yes if `mode: "ref"`, absent if `mode: "inline"` | MCP tool name to call for lazy fetch. Always `"attp_fetch_file"` in v1 but specified per-item for forward compatibility. |

### Why a discriminator field, not content presence

A schema that says "if `content` is present it's inline, otherwise it's a reference" creates ambiguity:
- What if `content` is present but empty string? Is that an inline empty file or a reference?
- What if a future version adds `content_delta` as an alternative to `content`? The presence-based heuristic breaks.

The explicit `mode` field eliminates this class of bugs. Validators can enforce: if `mode: "inline"`, `content` MUST be present and `fetch_via` MUST be absent; if `mode: "ref"`, `content` MUST be absent and `fetch_via` MUST be present.

### Size thresholds

The spec should recommend (not mandate) inlining for files under 4 KiB and referencing for files over 4 KiB. The producer is free to inline larger files or reference smaller ones. The consumer must handle both modes regardless of size.

---

## 5. Provenance Fields for Audit Trails

### `provenance` object

```json
{
  "provenance": {
    "agent": {
      "identity": "claude-code",
      "version": "1.42.0",
      "session_id": "sess_abc123"
    },
    "machine": {
      "tailscale_id": "alice-laptop.tailnet",
      "hostname": "alice-mbp"
    },
    "chain": [
      {
        "token_id": "attp_PREV_TOKEN_ID...",
        "agent_identity": "claude-code",
        "machine": "bob-workstation.tailnet",
        "timestamp": "2026-03-19T14:00:00Z",
        "action": "responded"
      }
    ],
    "sequence": 3
  }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `agent.identity` | `string` | yes | Agent name/type (e.g., `"claude-code"`, `"cursor"`, `"copilot"`). Framework-agnostic — not a Sylveste-specific identifier. |
| `agent.version` | `string` | no | Agent software version. |
| `agent.session_id` | `string` | no | Opaque session identifier from the agent runtime. Not required because some agents don't expose session IDs. |
| `machine.tailscale_id` | `string` | no | Tailscale machine identity. Present when transport is Tailscale. |
| `machine.hostname` | `string` | yes | Machine hostname. Always present as a human-readable identifier. |
| `chain` | `array` | no | Previous tokens in the conversation chain, in chronological order. Enables audit trails for multi-round exchanges. Each entry is a summary, not the full token. |
| `chain[].token_id` | `string` | yes (within chain entry) | ID of the previous token. |
| `chain[].agent_identity` | `string` | yes (within chain entry) | Who produced that token. |
| `chain[].machine` | `string` | yes (within chain entry) | Where it was produced. |
| `chain[].timestamp` | `string` | yes (within chain entry) | When it was produced. |
| `chain[].action` | `string` | yes (within chain entry) | What the token represented: `"initiated"`, `"responded"`, `"forwarded"`. |
| `sequence` | `integer` | yes | Monotonically increasing sequence number within a conversation. First token is `1`. Enables ordering even if timestamps are skewed. |

### Design rationale

- **`chain` is append-only.** Each new token appends a summary of the previous token to the chain. The chain grows linearly with the conversation length but each entry is small (~200 bytes). For long conversations (50+ rounds), producers MAY truncate the chain to the last 20 entries and set a `chain_truncated: true` flag.
- **`sequence` is per-conversation, not global.** Two unrelated conversations both start at 1. The conversation is identified by the chain — if two tokens share no chain entries, they are from different conversations.
- **`machine.tailscale_id` is transport-specific but schema-level.** This is the only transport-aware field in the token. It's acceptable because Tailscale identity is the primary authentication mechanism in v1. Future transports would add sibling fields (e.g., `machine.wireguard_pubkey`) rather than replacing it.

---

## 6. Framework-Agnostic Positioning: Extension Namespacing

The brainstorm correctly states attp is standalone and framework-agnostic. The base token spec MUST NOT contain Sylveste-specific fields. Sylveste's interweave implementation uses the `extensions` object.

```json
{
  "extensions": {
    "sylveste.interweave": {
      "bead_id": "Sylveste-e1mi",
      "sprint_id": "sprint-42",
      "intercore_routing": {
        "stage": "implement",
        "domain": "auth"
      }
    }
  }
}
```

### Rules

1. Extension keys use reverse-domain-ish naming: `"sylveste.interweave"`, `"cursor.workspace"`, `"copilot.session"`. No registry required — key is producer's namespace.
2. Extensions are always optional. A consumer that doesn't understand an extension MUST ignore it (same as unknown fields).
3. Extensions MUST NOT duplicate base fields. If interweave needs to attach a bead ID, it goes in `extensions.sylveste.interweave.bead_id`, not in a top-level `bead_id`.
4. The `extensions` object itself is optional. A valid token with no extensions omits the field entirely.

---

## 7. Comparison with Existing Sylveste Handoff Formats

### Intercom's `handoff.json` (local, same-machine)

| Aspect | handoff.json | attp token |
|---|---|---|
| Scope | Single container, same machine | Cross-machine, cross-agent |
| Versioning | `version: 1` (integer, hard reject) | `attp: "1.0"` (string, major.minor, forward-compat) |
| Sensitivity | None (local file, gitignored) | Core feature (Merkle exclusion proofs) |
| Content | No file content, only text summaries | Inline files + lazy-fetch references |
| Provenance | `session_id` only | Full chain-of-custody |
| Consumption | One-shot (renamed to `.consumed`) | Persistent (tokens are immutable records) |
| Size limit | 2000 chars | No hard limit (hybrid payloads keep metadata small) |

The formats serve entirely different purposes. handoff.json is a volatile internal memo; attp tokens are durable protocol messages. No unification is needed or desirable.

### Clavain's `/handoff` command (human-readable prose)

Clavain's handoff generates freeform markdown for human copy-paste. attp tokens are structured JSON for machine consumption. The `/handoff` command could be extended to optionally emit an attp token alongside the markdown, but the formats should not converge.

---

## 8. Complete Example Token

```json
{
  "attp": "1.0",
  "id": "attp_7kR9mX2pLq4nB8vW3jY5",
  "created_at": "2026-03-19T14:30:00Z",
  "provenance": {
    "agent": {
      "identity": "claude-code",
      "version": "1.42.0",
      "session_id": "sess_abc123"
    },
    "machine": {
      "tailscale_id": "alice-laptop.tailnet",
      "hostname": "alice-mbp"
    },
    "chain": [],
    "sequence": 1
  },
  "repo": {
    "url": "git@github.com:acme/backend.git",
    "branch": "main",
    "commit": "a1b2c3d4e5f67890abcdef1234567890abcdef12",
    "dirty_paths": ["src/auth/middleware.go"],
    "merkle_root": "sha256:deadbeef..."
  },
  "sensitivity": {
    "policy": "gitignore+attpignore",
    "excluded_paths": [
      "credentials/",
      ".env",
      "data/pii/"
    ],
    "excluded_count": 23,
    "exclusion_attestation": {
      "merkle_root": "sha256:deadbeef...",
      "algorithm": "sha256",
      "proof": "base64...",
      "signer": "tailscale:alice-laptop"
    }
  },
  "payloads": [
    {
      "mode": "inline",
      "path": "src/auth/types.go",
      "content_type": "text/x-go",
      "content": "package auth\n\ntype User struct {\n\tID    string\n\tEmail string\n}\n",
      "hash": "sha256:9f86d081...",
      "size_bytes": 67
    },
    {
      "mode": "ref",
      "path": "src/auth/middleware.go",
      "content_type": "text/x-go",
      "hash": "sha256:4e1243bd...",
      "size_bytes": 12847,
      "fetch_via": "attp_fetch_file"
    }
  ],
  "requests": [
    {
      "kind": "review",
      "summary": "Review auth middleware changes — I added rate limiting but need a second pair of eyes on the timing-safe comparison",
      "paths": ["src/auth/middleware.go"],
      "priority": "high"
    }
  ],
  "decisions": [
    {
      "summary": "Using bcrypt instead of argon2 for password hashing",
      "rationale": "argon2 Go bindings require CGO; bcrypt is pure Go and sufficient for our scale",
      "paths": ["src/auth/hash.go"],
      "reversible": true
    }
  ],
  "extensions": {
    "sylveste.interweave": {
      "bead_id": "Sylveste-e1mi",
      "sprint_id": "sprint-42"
    }
  }
}
```

---

## 9. Open Issues for Spec Authors

1. **Binary content encoding.** The current proposal assumes UTF-8 `content` for inline payloads. Binary files (images, compiled protos) should use `mode: "ref"`. Should the spec explicitly forbid inline binary, or allow base64 with a `content_encoding: "base64"` field?

2. **Token size soft limit.** Should the spec recommend a maximum token size (e.g., 1 MiB) to prevent producers from inlining entire repos? This is a SHOULD, not a MUST — the consumer can always stop parsing.

3. **Diff payloads.** The brainstorm mentions "diffs" as a payload type. Should there be a `mode: "diff"` alongside `"inline"` and `"ref"`, carrying a unified diff against a known commit? Or is a diff just an inline payload with `content_type: "text/x-diff"`?

4. **Token signing.** The exclusion attestation is signed, but is the entire token signed? If not, a man-in-the-middle could modify `requests` or `decisions` while leaving the exclusion proof intact. Tailscale's mutual TLS provides transport-level integrity, but tokens might be stored/forwarded outside the Tailscale mesh.

5. **Compression.** Large tokens (many inline payloads) could benefit from gzip/zstd compression. Should the spec define a compressed envelope format, or leave compression to the transport layer?
