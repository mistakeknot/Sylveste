---
artifact_type: brainstorm
bead: Sylveste-e1mi
stage: discover
---

# attp + interweave: Cross-Machine Agent Collaboration

## What We're Building

**attp** (Agent Token Transfer Protocol) is a standalone, framework-agnostic protocol for structured bidirectional context transfer between AI coding agents on separate machines. It enables two (or more) people's Claude Code sessions to collaborate seamlessly — sharing repo state, decisions, file content, and work requests — without shared tmux, screen-sharing, or pasting prose summaries.

**interweave** is Sylveste's L1 kernel implementation of attp, sitting at `core/interweave/` alongside intercore and intermute. It bridges attp to Sylveste's existing coordination primitives.

### Primary Use Case

Same repo, asymmetric access. Machine A has sensitive gitignored data (credentials, PII, proprietary datasets). Machine B's human and agent cannot see that data. Both agents collaborate on the shared codebase, but the protocol cryptographically enforces that sensitive content never crosses the wire — even accidentally.

### Computer Analogy

| L1 component | Analogy | Scope |
|---|---|---|
| intercore | CPU / ISA | Config, routing, cost, identity |
| intermute | Local bus / IPC | Same-machine messaging, reservations |
| **interweave** | NIC + driver | Sylveste's attp transport implementation |
| **attp** | TCP/IP | Cross-machine context transfer protocol |

## Why This Approach

### Standalone Protocol (Not an A2A Extension)

Google's A2A protocol (Linux Foundation, 150+ orgs) covers generic agent-to-agent interop — task lifecycle, capability discovery, enterprise workflows. attp is purpose-built for a narrower, deeper problem: coding agent context transfer with codebase-aware payloads (diffs, ASTs, file trees, sensitivity manifests). A2A's enterprise abstractions are overhead for "two people's Claude Code sessions talking." An A2A bridge can come later if adoption demands it.

### Content-Addressed Crypto Enforcement

The sensitivity boundary isn't trust-based ("the agent promises not to leak"). It uses content-addressed exclusion proofs:

1. Sender builds a Merkle tree of the repo
2. Sensitive paths (from `.gitignore`, `.attpignore`, explicit config) are marked as excluded
3. Token includes Merkle root + signed exclusion attestation
4. Receiver can verify: included content hashes are consistent, and the sender attests which paths were excluded

This prevents **accidental** leaks. A malicious sender is out of threat model — both agents are trusted, the protocol prevents mistakes.

### Tailscale MCP Server Relay

Each machine runs its own attp MCP server. Discovery via Tailscale DNS (`alice-laptop.tailnet:8400`). No port forwarding, no public exposure, mutual TLS built in via Tailscale. Sensitive data stays on its machine; only crypto-verified tokens cross the wire.

Symmetric topology — each server controls what it shares. No central coordinator.

### Hybrid Token Payloads

Tokens carry structured metadata plus selectively inlined essentials:

- **Always included:** repo state (branch, commit, dirty files), decisions, requests
- **Inlined when small:** type definitions, interface contracts, config files
- **Referenced for lazy fetch:** large files resolved via follow-up MCP tool calls between servers

Balances self-containment (works async) with weight (doesn't bundle the whole repo).

## Key Decisions

1. **attp is independent** — standalone repo (`~/projects/attp`), no Sylveste dependencies. Framework-agnostic spec + Go reference implementation.

2. **interweave is L1 kernel** — `core/interweave/`, same level as intercore/intermute. Not an interverse plugin. Every higher-level cross-machine feature builds on it.

3. **Crypto from v1** — content-addressed exclusion proofs, not trust-based. The sensitivity boundary is the protocol's core value proposition.

4. **Transport: Tailscale + MCP** — peer-to-peer MCP servers discoverable via Tailscale mesh. Each machine runs its own server, controls its own exposure.

5. **Token format: hybrid** — metadata + inlined essentials + lazy-fetch references. JSON schema with versioning.

6. **Standalone from A2A** — purpose-built for coding agents, not a profile of Google's enterprise protocol. A2A bridge is a future concern.

## Open Questions

- **Token schema specifics:** exact fields, nesting, versioning strategy. Needs spec work in the attp repo.
- **MCP tool surface:** what tools does each attp server expose? (e.g., `attp_send_token`, `attp_fetch_file`, `attp_list_peers`, `attp_verify_token`)
- **Merkle tree implementation:** full repo tree on every token, or incremental? Performance on large repos (100k+ files).
- **Multi-party:** v1 is two agents. Does the protocol need to handle 3+ from the start, or can that be v2?
- **Session continuity:** how does attp interact with intermute's session model? Does interweave register attp peers as intermute agents?
- **CLI tool:** should `attp` ship a CLI for manual pack/unpack/verify, or is the MCP server the only interface?
- **Conflict resolution:** when both agents modify the same file, does attp detect/surface conflicts, or is that interlock's job via interweave?
