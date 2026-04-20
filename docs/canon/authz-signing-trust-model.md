---
artifact_type: canon
bead: sylveste-qdqr
supersedes: (none)
superseded_by: (none)
---

# Authz audit signing — trust model (v1.5)

This document pins the exact trust claim of the v1.5 audit-signing system,
and what it does NOT cover. It is the normative answer to "what does a
valid signature on an `authorizations` row actually prove?"

## Claim

**Tamper-evident-post-write.** Any post-cutover row with an invalid or
missing signature is flagged as suspect by `clavain-cli policy audit
--verify`. An attacker who mutates row data (op_type, target, agent_id,
etc.) directly in the SQLite file cannot produce a matching Ed25519
signature without access to the project signing key.

## Non-claims

The v1.5 system does **not** claim:

1. **Tamper-proof-at-write.** An attacker with permission to invoke
   `clavain-cli policy sign` (i.e. read access to
   `.clavain/keys/authz-project.key`) can produce forged rows that
   verify cleanly. The signing key read path is minimized but not
   separated from the gate wrapper in v1.5 — the gate wrapper invokes
   `policy sign` as a sub-process after `policy record`. True
   separation of duties (out-of-band signer daemon) ships in v1.6.

2. **Protection against host compromise.** Root on the host reads the
   key file. If an adversary can read the key, signatures prove
   authenticity of the *signer*, not of the action. Host security is
   out of scope for this system.

3. **Protection against backup-file substitution.** Replacing the DB
   with an older snapshot (lower `PRAGMA user_version`, fewer rows) is
   detectable only if verification walks the migration-cutover marker;
   substituting a v1.5-era snapshot for another v1.5-era snapshot is
   **not** detectable through signatures alone. Snapshot integrity is a
   filesystem/OS concern.

4. **Cross-project chain-of-custody.** Each project holds its own key
   and signs its own records. A token issued in project A and consumed
   in project B writes rows signed by each project's key independently;
   no cross-project Merkle chain exists. v2 cross-project delegation
   may add one.

## What an attacker *can* still do

| Attack | v1.5 detects? | Mitigation lever |
|---|---|---|
| Direct SQL: rewrite `op_type`, `target`, `mode` on a signed row | Yes — `audit --verify` flags row | Run `--verify` periodically; alert on mismatch |
| Direct SQL: insert a new row with NULL signature | Yes — visible as pre-cutover-vintage when compared against marker timestamp | Compare row `created_at` to cutover-marker timestamp; reject new rows with `created_at > marker AND signature IS NULL` |
| Direct SQL: delete signed rows | No (signatures cover rows, not a chain) | Per-row deletion is not detectable via signatures alone; audit log should be append-only at the OS level (backup + WORM-ish policy) |
| Invoke `clavain-cli` to produce legitimate signed rows | No — signatures are valid | Access control on the CLI path and signing key (0400 perms); rotate key on suspected compromise |
| Steal key, sign forged rows offline | No | Key rotation + quarantine (`policy audit quarantine --before-key=<fp>`) flags all pre-breach rows |
| Replace key with attacker-controlled key | Partially — rotation history shows fingerprint change, but rows signed with the new key verify | Commit `authz-project.pub` to the repo so verifiers see the intended fingerprint; rotation is observable via git history of the pubkey |

## Deprecation path to v1.6 (separation of duties)

v1.6 moves `policy sign` out of the gate-wrapper process into a
standalone watcher (systemd/launchd/cron job) that owns the signing
key. Gate wrappers write unsigned rows only; the watcher signs on its
own schedule. Post-v1.6 trust claim upgrades to **tamper-proof-at-rest
for rows written outside the watcher's privilege boundary**.

Interim guidance: document the trust claim honestly; do not market v1.5
signatures as "unforgeable." The `audit --verify` command will detect
retroactive tampering; that's real value, even if it does not prevent
write-time forgery by a privileged caller.

## Key distribution

- `authz-project.key` (private, 0400) — **never commit**. Host-local.
- `authz-project.pub` (public, 0444) — **commit** to the repo so
  verifiers agree on the expected fingerprint.
- `KeyFingerprint(pub)` = first 8 bytes of `sha256(pub)` as hex.
  Shown in audit output + git logs of pub file changes.

Rotation procedure:
1. `clavain-cli policy rotate-key` generates new `authz-project.key`;
   old key is archived as `authz-project.key.<oldfp>.archive`.
2. Old pubkey archived as `authz-project.pub.<oldfp>`.
3. Old rows keep `sig_version=1`; new rows are `sig_version=2+`.
4. Verifier walks sig_version and loads the matching archived pubkey.

Rotation does NOT re-sign old rows. A compromised key means
`quarantine --before-key=<fp>` flags everything signed under it, and
those rows are downgraded to "pre-breach vintage" in audit output.

## Out-of-scope

- Multi-principal identity (who is "the user" vs "the agent") — see v2 token model.
- Cross-host key distribution — Sylveste is single-host in v1.x.
- Certificate transparency / witness servers — not in scope; single-host trust.
- HSM-backed signing — deferred indefinitely; file-based key is sufficient for the single-user threat model.
