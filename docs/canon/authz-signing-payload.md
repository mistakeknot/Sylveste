---
artifact_type: canon
bead: sylveste-qdqr
supersedes: (none)
superseded_by: (none)
---

# Authz audit signing — canonical payload (v1.5)

This document pins the **exact byte sequence** that Ed25519 signs for
each `authorizations` row. Signatures depend on byte-for-byte
agreement; any deviation in encoding produces non-verifying signatures
for correct rows and verifying signatures for tampered rows. This is
the spec. Implementations MUST match.

## Field order

Signed fields, in strict order:

```
id
op_type
target
agent_id
bead_id
mode
policy_match
policy_hash
vetted_sha
vetting
cross_project_id
created_at
```

12 fields. `sig_version` and `signature` and `signed_at` are metadata
about the signing itself and are NOT part of the signed payload. This
avoids a circular dependency and lets `sig_version` change without
invalidating old signatures.

## Encoding rules

1. **Separator:** a single line feed byte (`\n`, 0x0A) between fields.
2. **Trailing newline:** none. The payload ends with the last field's
   bytes; no terminator.
3. **NULL representation:** the empty string. A SQL NULL and an empty
   string in the row both encode as zero bytes at that position.
4. **Unicode normalization:** NFC. All text fields (anything that isn't
   strictly hex/int) must be NFC-normalized before concatenation.
5. **Integer formatting:** decimal, no leading zeros, no leading `+`,
   no thousands separators. `created_at` uses its unsigned integer
   representation (SQLite INTEGER → Go int64 → `strconv.FormatInt`).
   Negative values are prohibited by the schema and signer rejects them
   explicitly.
6. **Vetting JSON:** the `vetting` column stores a JSON string. For
   signing, include the stored bytes verbatim — do NOT re-canonicalize
   the JSON at signing time. The row's stored value is authoritative.
   If the stored JSON is not NFC-normalized at store time, it is
   likewise not NFC-normalized at sign time (asymmetry forbidden; use
   the stored bytes exactly).
7. **Forbidden characters:** `\r` (0x0D) and control characters in
   [0x00, 0x1F] \ {\n} are not permitted in text fields. The signer
   MUST reject rows containing them rather than silently stripping.
   Strip at insertion time, not at signing time.

## Output format

`Sign()` returns the raw 64-byte Ed25519 signature. Callers that need
a text form use lowercase hex (no prefix, no separator). The
`signature BLOB` column stores raw bytes.

## Worked examples

### Example 1 — All fields populated

Row (column → value):

```
id              = "01HQ8YR7JCMV7K8WK5T6V9BGQF"
op_type         = "bead-close"
target          = "sylveste-qdqr"
agent_id        = "claude-opus-4-7"
bead_id         = "sylveste-qdqr"
mode            = "auto"
policy_match    = "bead-close#0"
policy_hash     = "f3f77555ffc398ff8af8e63f8518e3d9d6764fc7e487dfb9b3999755ccf10340"
vetted_sha      = "0a1e85a6f9b7119988109b796dd2ca14f46b28c9"
vetting         = "{\"shas\":{\"intercore\":\"0a1e85a\"}}"
cross_project_id = ""
created_at      = 1776616956
```

Canonical payload (12 lines joined by `\n`, no trailing newline, shown
with literal `\n` for clarity; real bytes are LF):

```
01HQ8YR7JCMV7K8WK5T6V9BGQF\n
bead-close\n
sylveste-qdqr\n
claude-opus-4-7\n
sylveste-qdqr\n
auto\n
bead-close#0\n
f3f77555ffc398ff8af8e63f8518e3d9d6764fc7e487dfb9b3999755ccf10340\n
0a1e85a6f9b7119988109b796dd2ca14f46b28c9\n
{"shas":{"intercore":"0a1e85a"}}\n
\n
1776616956
```

(Note the empty `cross_project_id` shows as a bare `\n` between lines
10 and 11 — this is the empty-string convention. Line 11 is literally
zero bytes followed by `\n`.)

### Example 2 — Optional fields absent (NULL)

Row:

```
id              = "01HQ8YRDABDCEFGHJKMNPQRSTV"
op_type         = "git-push-main"
target          = "origin/main"
agent_id        = "claude-opus-4-7"
bead_id         = NULL
mode            = "confirmed"
policy_match    = "git-push-main#1"
policy_hash     = "9b2a..."
vetted_sha      = NULL
vetting         = NULL
cross_project_id = NULL
created_at      = 1776617000
```

Canonical payload:

```
01HQ8YRDABDCEFGHJKMNPQRSTV\n
git-push-main\n
origin/main\n
claude-opus-4-7\n
\n
confirmed\n
git-push-main#1\n
9b2a...\n
\n
\n
\n
1776617000
```

Four lines (5, 9, 10, 11) are empty strings → zero bytes between their
surrounding `\n` delimiters.

### Example 3 — `migration.signing-enabled` cutover marker row

Row:

```
id              = "01HQ8YSAAAAAAAAAAAAAAAAAAA"
op_type         = "migration.signing-enabled"
target          = "authorizations"
agent_id        = "system:migration-033"
bead_id         = NULL
mode            = "auto"
policy_match    = NULL
policy_hash     = NULL
vetted_sha      = NULL
vetting         = NULL
cross_project_id = NULL
created_at      = 1776618000
```

Canonical payload:

```
01HQ8YSAAAAAAAAAAAAAAAAAAA\n
migration.signing-enabled\n
authorizations\n
system:migration-033\n
\n
auto\n
\n
\n
\n
\n
\n
1776618000
```

The migration row is itself signed (it is the FIRST signed row in the
table). Its signature anchors the cutover timestamp: verifiers use
`created_at` of this row as the "anything-before-this-is-pre-signing"
boundary.

## Implementation-level test

A reference-implementation test must verify that all three worked
examples, when serialized by the production `CanonicalPayload()`
function, produce the exact byte sequences shown (after expanding the
`\n` literals). This test ships alongside the implementation in
`pkg/authz/sign_test.go` as `TestCanonicalPayload_GoldenFixtures`.

## Why not JSON

Several factors rule out JSON as the canonical form:

1. **Go map iteration is not stable.** `map[string]any` in Go iterates
   in pseudo-random order; two `json.Marshal` calls on equivalent maps
   produce different bytes. Deterministic JSON requires a canonical
   library (not in stdlib) or manual key sorting.
2. **Number encoding is ambiguous.** `1776616956` vs `1776616956.0` vs
   `1.776616956e+09` — all valid JSON, different bytes. Signing needs
   ONE form.
3. **Whitespace is free.** Canonicalizers strip it, but the rule must
   be spelled out.

A pipe-or-LF-delimited ordered sequence avoids all of this. Spec tight,
implementation trivial.

## Forbidden deviations

- No trailing newline.
- No BOM.
- No UTF-16 / UTF-32 encodings — UTF-8 only.
- No CRLF. LF only. Inputs with CR must be rejected, not transliterated.
- No field reordering across signer versions. A new field requires a
  new `sig_version` and a parallel signer path; the old path continues
  to sign using the old field set for backward compatibility.
