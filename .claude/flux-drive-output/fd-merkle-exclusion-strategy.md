# Merkle Tree Exclusion Proof Strategy — Design Analysis

**Reviewer focus:** Cryptographic soundness, performance, and implementability of the Merkle exclusion proof mechanism described in the attp brainstorm (`docs/brainstorms/2026-03-19-attp-interweave-brainstorm.md`).

**Threat model reminder:** The brainstorm explicitly scopes out malicious senders. The goal is preventing *accidental* leaks of sensitive content across the wire. Both agents are trusted; the protocol enforces the sensitivity boundary mechanically.

---

## 1. Zero-Knowledge Properties

### What the proposed design hides

In a standard Merkle tree with excluded subtrees replaced by their root hashes, the receiver learns:

- **Nothing about excluded file content.** The subtree root hash is a one-way commitment. Preimage resistance of SHA-256 (or BLAKE3) prevents content recovery.
- **Nothing about excluded file sizes** — if the hash is computed over content only and the tree uses a fixed branching structure independent of file size.
- **Nothing about the internal structure of excluded subtrees** — how many files, how deep, what names — provided the subtree is collapsed to a single opaque hash.

### What the proposed design leaks

**P0 — Directory structure leakage via tree topology.** If the Merkle tree mirrors the filesystem directory hierarchy (the natural implementation), the *position* of excluded nodes in the tree reveals:

- The depth of the excluded path (how many directories deep).
- Sibling relationships — the receiver sees sibling hashes at each level, revealing how many entries exist alongside the excluded subtree in each parent directory.
- Whether excluded content is concentrated in one subtree or scattered.

**Concrete scenario:** Repo has `secrets/prod/database.env` excluded. If the tree mirrors `secrets/ > prod/ > database.env`, the receiver sees that a node was excluded at depth 3, with N siblings at the `prod/` level. This reveals the *existence* of a directory structure even if file names are hidden.

**Mitigation options (choose one):**

1. **Flatten before hashing.** Build the Merkle tree over a sorted list of `(path, content_hash)` pairs rather than mirroring directory structure. Excluded entries are simply omitted from the list. The receiver sees a balanced binary tree with no structural information about directory nesting. Trade-off: loses the ability to do subtree-level inclusion/exclusion proofs efficiently.

2. **Pad excluded subtrees.** Replace each excluded subtree with a single opaque hash regardless of its internal depth. The receiver cannot distinguish a single excluded file from a directory of 10,000 files. This is the recommended approach — it preserves tree structure for included content while collapsing excluded content to fixed-size opaque nodes.

3. **Content-only sorted Merkle tree (recommended for v1).** Hash over sorted `(path_hash, content_hash)` pairs. Path names are hashed (SHA-256) before inclusion, so the receiver sees `H(path)` not the path string. Excluded entries are omitted entirely. The receiver cannot determine excluded path names, counts, or structure. The sender attests to the set of excluded `H(path)` values in a signed manifest.

### Recommendation

**Use approach 3 (content-only sorted Merkle tree with hashed paths) for v1.** It provides the strongest privacy guarantees with the simplest implementation. Directory-structured trees are an optimization for incremental updates that can come in v2 if performance requires it.

### Residual leakage even with approach 3

- The **total count of included files** is visible (tree leaf count).
- The **Merkle root changes** when excluded files change, which reveals *that* something changed in excluded content (but not what). This is unavoidable unless excluded subtrees are fully omitted from the root computation — but then the receiver cannot verify completeness.
- The **signed exclusion manifest** reveals how many paths are excluded (count of `H(path)` entries). Consider whether this count itself is sensitive. If so, use a single aggregate "N paths excluded" attestation without listing individual hashed paths.

---

## 2. Performance Analysis

### Hash function choice

BLAKE3 is the clear winner for this use case. It is tree-structured internally (parallelizable), ~3-5x faster than SHA-256 on modern CPUs, and produces 256-bit digests.

### Baseline: file content hashing

The dominant cost is reading file content from disk, not computing hashes. BLAKE3 processes ~5 GB/s on a single core (AMD Ryzen 5000 / Apple M-series). SHA-256 with hardware acceleration (SHA-NI on x86, ARMv8 crypto extensions): ~1-2 GB/s.

Assumptions for estimates:
- Average file size: 8 KB (typical source code repo)
- SSD random read throughput: ~500 MB/s (NVMe) to ~200 MB/s (SATA)
- Hash computation: 5 GB/s (BLAKE3) or 1.5 GB/s (SHA-256-NI)
- Tree interior node hashing: negligible (N-1 hash operations of 64 bytes each)

| Repo size | File count | Total content | Disk read (NVMe) | BLAKE3 hash | SHA-256 hash | Total (BLAKE3+NVMe) |
|-----------|-----------|---------------|-------------------|-------------|-------------|---------------------|
| Small     | 1,000     | 8 MB          | 16 ms             | 1.6 ms      | 5 ms        | **~20 ms**          |
| Medium    | 10,000    | 80 MB         | 160 ms            | 16 ms       | 53 ms       | **~180 ms**         |
| Large     | 50,000    | 400 MB        | 800 ms            | 80 ms       | 267 ms      | **~900 ms**         |
| XL mono   | 100,000   | 800 MB        | 1.6 s             | 160 ms      | 533 ms      | **~1.8 s**          |

### Verdict: full rehash is acceptable for v1

For repos up to 50k files, full rehash completes under 1 second. The 100k case is borderline at ~2 seconds. Given the threat model (accidental leaks, not millisecond-critical trading), this is within the brainstorm's 2-second budget.

**Recommendation:** Ship v1 with full rehash. Add incremental hashing in v2 when real-world profiling shows it matters. Premature incremental hashing adds significant complexity (dirty tracking, cache invalidation, state persistence) for marginal gain at typical repo sizes.

### Optimization levers if needed

1. **Cache file content hashes by mtime+size.** Stat is ~100x faster than read+hash. On a 100k-file repo, only changed files need re-reading. This alone reduces rehash to near-zero for the common case (few files changed between tokens).
2. **Parallel hashing.** BLAKE3 is internally parallelizable. With 4 cores, content hashing drops by ~3.5x.
3. **Git object reuse.** If the repo is git-managed and clean, git already has content hashes (SHA-1 or SHA-256) for every tracked file. These can be used directly as leaf hashes, skipping file reads entirely. Only untracked/modified files need hashing. This is the single biggest optimization available.

---

## 3. Tree Structure: What to Hash

### Option A: Content only (sorted leaf list)

```
Tree leaves: sorted([ BLAKE3(file_content) for each included file ])
```

- Pros: Simplest. No metadata leakage. Two repos with identical content produce identical roots regardless of directory layout.
- Cons: No path binding — a file moved from `src/foo.go` to `lib/foo.go` without content change produces the same hash. Cannot verify "file X is at path Y" without additional metadata.

### Option B: Content + path (recommended)

```
Tree leaves: sorted([ BLAKE3(canonical_path || file_content) for each included file ])
```

- Pros: Path-bound. Receiver can verify specific files are at specific paths. Moving a file changes its leaf hash. The path is committed to but not extractable from the hash.
- Cons: Path length variations create a side channel (leaf hash changes when path length changes). Mitigated by using `BLAKE3(path)` as a domain separator rather than raw concatenation.

**Refined construction:**

```
leaf_hash = BLAKE3(
    domain = "attp.v1.file",
    key    = BLAKE3(canonical_path),
    data   = file_content
)
```

Using BLAKE3's keyed mode with the path hash as key. This binds content to path without revealing the path in the hash.

### Option C: Content + path + metadata (file mode, mtime)

- **Do not include mtime.** It changes on clone, touch, CI — different machines will never agree on it.
- **File mode (executable bit)** is worth including. It is security-relevant (a script that lost its execute bit behaves differently). Include `mode & 0o111` (executable yes/no) as a single bit in the leaf hash.
- **File size** is redundant if content is hashed, but could be included as a cheap pre-filter for lazy-fetch decisions.

### What leaks if you include directory structure

If the tree mirrors `dir/subdir/file` as internal nodes:

| Leaked information | Severity | Notes |
|---|---|---|
| Directory depth of excluded paths | Medium | Reveals organizational structure |
| Sibling count at each level | Medium | Reveals how many files are in excluded directories' parents |
| Which directories exist | High | Even if contents are hidden, directory *names* may be visible as internal node labels |
| Empty vs. non-empty directories | Low | Structural artifact |

**Recommendation:** Use the flat sorted list (Option B) for v1. Directory-structured trees are only useful for incremental proofs, which are a v2 concern.

---

## 4. Incremental Update Strategy

### O(log N) rehash — how it works

With a balanced binary Merkle tree over N sorted leaves:

1. A single file change modifies one leaf hash.
2. The path from that leaf to the root contains `ceil(log2(N))` internal nodes.
3. Each must be recomputed: `H(left_child || right_child)`.
4. For N = 100,000: `log2(100000) ≈ 17` hash operations of 64 bytes each. Under 1 microsecond.

The bottleneck is never the tree rehash — it is computing the new leaf hash (reading and hashing the changed file).

### Anchoring both parties to the same tree state

This is the harder problem. Two options:

**Option A: Git commit as anchor (recommended for v1)**

- The token includes the git commit hash as the tree state anchor.
- Both parties can independently verify they are looking at the same committed state.
- Dirty (uncommitted) files are handled as a delta overlay: `tree_state = (commit_hash, [(path, content_hash) for dirty files])`.
- The Merkle root is computed over the combined state.
- The receiver verifies: "at commit X, with these dirty file overrides, the Merkle root is Y."

**Option B: Explicit state exchange**

- Sender transmits the full Merkle root + leaf count + timestamp.
- Receiver accepts it as the sender's claimed state.
- No independent verification possible — the receiver trusts the sender's tree construction.
- This is fine given the threat model (accidental leaks, not adversarial).

**Recommendation:** Use Option A (git commit anchor). It provides a shared reference point both parties can independently verify, and it naturally handles the common case where both are working on the same repo.

### Incremental protocol flow

```
Token 1: Full tree. Root = R1, commit = C1, 50k files.
  → Receiver caches R1 and the leaf list.

Token 2: Incremental. Base = R1, commit = C2.
  → Delta: 3 files changed, 1 added, 1 removed.
  → Sender transmits: new leaf hashes for 5 affected entries + Merkle proof path for each.
  → Receiver applies delta to cached tree, verifies new root R2.
  → Total data: 5 leaf hashes + 5 × 17 sibling hashes = ~90 hashes = ~2.8 KB.
```

This is elegant but complex to implement correctly. **Defer to v2.** For v1, retransmit the full tree on every token — the performance analysis shows this is under 2 seconds for 100k files.

---

## 5. Proof Format

### What the proof contains

A self-contained exclusion proof for offline verification needs:

```json
{
  "version": "attp.proof.v1",
  "tree_algorithm": "blake3-sorted-flat",
  "root": "<32-byte hex Merkle root>",
  "anchor": {
    "git_commit": "<40-byte hex>",
    "git_remote": "origin",
    "dirty_files": ["path/to/modified.go"]
  },
  "included_leaves": [
    {
      "path_hash": "<32-byte hex BLAKE3(canonical_path)>",
      "content_hash": "<32-byte hex>",
      "leaf_hash": "<32-byte hex>",
      "index": 0
    }
  ],
  "exclusion_attestation": {
    "excluded_count": 7,
    "policy_sources": [".gitignore", ".attpignore"],
    "signer": "<ed25519 public key of sender>",
    "signature": "<ed25519 signature over (root || excluded_count || policy_hash)>"
  },
  "merkle_siblings": [
    ["<hash at depth 0, sibling of leaf 0>", "<hash at depth 1>", "..."]
  ]
}
```

### Self-containment analysis

The receiver can verify offline:

1. **Leaf reconstruction:** For each included file (content provided in the token), recompute `leaf_hash = BLAKE3(key=BLAKE3(path), data=content)`. Verify it matches the claimed `leaf_hash`.
2. **Merkle path:** Using `merkle_siblings`, walk from each leaf to the root. Verify the computed root matches the claimed `root`.
3. **Exclusion attestation:** Verify the Ed25519 signature over `(root || excluded_count || policy_hash)`. This confirms the sender attests to excluding N paths under the given policy.
4. **Anchor verification:** If the receiver has the same git repo, they can verify the commit exists and check out that state.

### What the receiver CANNOT verify offline

- That the sender actually excluded the right files (the receiver does not know what `.attpignore` contains on the sender's machine).
- That the sender did not fabricate additional files not in the repo.
- That `excluded_count` is accurate.

These are all acceptable given the threat model. The sender is trusted; the proof prevents accidents, not fraud.

### Size estimate

For a 50k-file repo with 10 excluded subtrees, including full leaf hashes:

- 49,990 leaf entries × (32 + 32 + 32 + 4) bytes = ~4.9 MB (leaf metadata only, not content)
- Merkle siblings: 49,990 × 17 × 32 bytes = ~26 MB

This is too large to embed in every token. **Recommendation:** The token carries only the root hash + exclusion attestation (~200 bytes). Full proof is available via lazy-fetch (`attp_fetch_proof` MCP tool call) when the receiver wants to verify specific files. The common case does not require full proof transmission.

### Compact proof for specific files

When the receiver wants to verify that file X is included with content Y:

```
Single-file inclusion proof:
  - leaf_hash (32 bytes)
  - merkle_path: 17 sibling hashes (544 bytes)
  - Total: ~600 bytes
```

This is small enough to inline in a token for critical files (type definitions, interfaces).

---

## 6. Degenerate Cases

### Empty repo

- Zero leaves. Merkle root is defined as `BLAKE3("")` (the hash of empty input) or a sentinel value.
- Exclusion attestation with `excluded_count: 0`.
- **Recommendation:** Define `EMPTY_ROOT = BLAKE3("attp.v1.empty")` as a domain-separated constant. This avoids ambiguity with a repo containing a single empty file.

### Single file

- One leaf. Merkle root equals the leaf hash (no interior nodes).
- Merkle proof for the single file is empty (no siblings needed).
- Works correctly with no special casing.

### Root excluded (entire repo is sensitive)

- All files are excluded. The tree has zero included leaves.
- Root = `EMPTY_ROOT` (same as empty repo).
- Exclusion attestation: `excluded_count: N` where N is total file count.
- **The receiver cannot distinguish "empty repo" from "everything excluded."** This is a feature, not a bug — it reveals nothing about excluded content, including its quantity.
- However, `excluded_count` in the attestation does reveal this. **If count sensitivity matters, make `excluded_count` optional or replace with a boolean `has_exclusions: true`.**

### All files included (no exclusions)

- Standard Merkle tree, no exclusion attestation needed.
- The signature can cover `excluded_count: 0` to explicitly attest that nothing was withheld.

### Single excluded file among many

- Standard tree with one leaf omitted from the sorted list.
- The gap in the sorted sequence is not detectable because leaves are identified by `BLAKE3(path)`, not sequential index. The receiver sees a valid tree of N-1 leaves with no indication of where the missing leaf would have been.

### Very deep directory nesting (1000 levels)

- Irrelevant for the flat sorted tree approach. All leaves are at depth 0 in the sorted list.
- Only relevant if a directory-structured tree is used (v2 concern).

---

## 7. Alternative Approaches

### Sparse Merkle Trees (SMT)

A sparse Merkle tree has a fixed depth (e.g., 256 for SHA-256-addressed keys) with most leaves being the default empty value. Inclusion and exclusion proofs are both O(depth) = O(256) hashes.

**Pros:**
- Canonical proof of non-inclusion: proving a key is NOT in the tree is native.
- Fixed-depth proofs regardless of tree size.
- Well-studied in blockchain/rollup literature (Ethereum state trees, Celestia).

**Cons:**
- Proofs are 256 × 32 = 8 KB each (much larger than balanced tree proofs at ~17 × 32 = 544 bytes for 100k files).
- Implementation complexity is higher (efficient sparse representations, default subtree caching).
- Overkill for the accidental-leak threat model — native non-inclusion proofs are valuable when the verifier is adversarial, which is explicitly out of scope.

**Verdict:** Not recommended for v1. The threat model does not require cryptographic non-inclusion proofs. The sender's signed attestation is sufficient.

### Hash Lists (flat, no tree)

Just a sorted list of `(path_hash, content_hash)` pairs, with a single hash over the concatenation as the commitment.

**Pros:**
- Simplest possible implementation. No tree construction.
- No structural leakage (flat list).

**Cons:**
- No incremental proofs — verifying a single file requires the entire list.
- Proof size for single-file verification is O(N) instead of O(log N).
- No path to incremental updates without rebuilding the full list.

**Verdict:** Viable for v1 only if proof size is irrelevant (token always includes everything or nothing). Not recommended because it forecloses the compact single-file proof option, which is valuable for hybrid tokens.

### Bloom Filters for Exclusion

A Bloom filter encoding the set of excluded path hashes, included in the token. The receiver can probabilistically test whether a given path is excluded.

**Pros:**
- Very compact: ~1.2 bytes per element at 1% false positive rate.
- 100 excluded paths = ~120 bytes.
- Fast lookups (O(k) hash lookups, k ≈ 7).

**Cons:**
- Probabilistic — false positives mean the receiver might believe an included file is excluded.
- **Leaks excluded set membership.** Anyone with a candidate path can test it against the Bloom filter. If the attacker guesses `secrets/prod/db.env`, they can confirm it is excluded with high probability. This violates the privacy goal.
- One-directional only: cannot prove inclusion.
- Not a replacement for Merkle proofs, at best a supplement.

**Verdict:** Do not use. The membership-testing property is a privacy anti-feature. It lets a curious receiver probe for likely sensitive paths.

### Recommended Approach for v1

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Tree structure | Flat sorted binary Merkle tree | No structural leakage, simple, O(log N) proofs |
| Hash function | BLAKE3 keyed mode | Fast, domain-separated, parallelizable |
| Leaf construction | `BLAKE3(key=BLAKE3(path), data=content)` | Binds path to content without revealing path |
| Rebuild strategy | Full rehash with mtime+size cache | Under 2s for 100k files, avoids incremental complexity |
| Proof in token | Root hash + exclusion attestation only (~200 bytes) | Compact; full proof via lazy-fetch MCP call |
| Single-file proof | 17 sibling hashes (~600 bytes) | Inlineable for critical files |
| Exclusion attestation | Ed25519 signature over `(root \|\| has_exclusions)` | No count leakage; signed by sender identity |
| Anchor | Git commit hash + dirty file overlay | Shared reference point for both parties |
| Degenerate cases | Domain-separated empty root constant | Handles empty, single-file, and fully-excluded repos |

### v2 candidates (defer, do not build now)

1. **Incremental delta proofs** — transmit only changed leaves + Merkle paths. Valuable at >100k files.
2. **Directory-structured tree** — enables subtree-level proofs. Useful if use cases emerge for "share this directory only."
3. **Sparse Merkle tree** — if the threat model expands to adversarial senders.
4. **Git object reuse** — use git's existing SHA-1/SHA-256 blob hashes as leaf values, skipping file reads for tracked files. Largest single performance optimization available.

---

## Summary of Key Recommendations

1. **Use a flat sorted Merkle tree, not a directory-mirroring tree.** This eliminates structural leakage about excluded paths (directory depth, sibling count, nesting).

2. **Hash with BLAKE3 keyed mode.** `leaf = BLAKE3(key=H(path), data=content)` binds path to content without revealing path structure. Domain-separate the empty root.

3. **Full rehash for v1, with mtime+size caching.** Performance is acceptable (under 2 seconds for 100k files). Incremental hashing is a v2 optimization.

4. **Token carries root + attestation only (~200 bytes).** Full proofs and single-file proofs are available via lazy-fetch MCP tool calls. Do not embed 5+ MB proof data in every token.

5. **Exclusion attestation should NOT include `excluded_count` or individual hashed paths.** Use a boolean `has_exclusions` flag and a policy hash. Revealing counts or testable hashes degrades privacy.

6. **Anchor on git commit.** Both parties can independently verify they are looking at the same repo state. Dirty files are a delta overlay on the committed state.

7. **Do not use Bloom filters for exclusion.** They enable path-guessing attacks against the excluded set, which contradicts the privacy goal.
