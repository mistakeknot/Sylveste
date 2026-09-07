---
artifact_type: plan
bead: sylveste-qdqr
stage: design
scope: v1.5 — signed audit records + .publish-approved unify
source_brainstorm: docs/brainstorms/2026-04-19-auto-proceed-authz-design.md
source_synthesis: docs/research/flux-drive/2026-04-19-auto-proceed-authz-design-20260419T0239/SYNTHESIS.md
prerequisite: docs/plans/2026-04-19-auto-proceed-authz-v1.md
---

# Auto-proceed authorization framework — v1.5 implementation plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-qdqr (reopen if closed)
**Goal:** Turn the plaintext `authorizations` audit log into a cryptographically verifiable record, and unify the `.publish-approved` marker into the same audit system. After v1.5, any mutation of the table is detectable via `policy audit --verify`, and `ic publish` consults authz records as the primary gate (falling back to `.publish-approved` during the deprecation window).

**Architecture:** Add Ed25519 signatures to each `authorizations` row. The signing key lives outside the DB (`.clavain/keys/authz-project.key`, mode 0400) so the artifact being signed does not host its own key. `clavain-cli policy sign` reads unsigned rows and signs them; `policy audit --verify` validates signatures and surfaces tampering. Gate wrappers run `policy record` → `policy sign` as separate invocations so the signing-key read path is minimal. `RequiresApproval()` in `core/intercore/internal/publish/approval.go` consults `authorizations` before falling back to `.publish-approved`; the marker stays as an additive fallback for one deprecation window (v1.5 → v2).

**Trust claim:** v1.5 ships as **tamper-evident-post-write**, not tamper-proof. If someone can invoke the gate CLI with the signing key readable, they can produce valid signatures; the system detects tampering by anyone who *cannot* invoke the CLI (e.g., direct SQL edits, backup mutations, old-row rewrites). True write-time separation of duties (out-of-band signer daemon) is deferred to v1.6 if the threat model expands. This claim is documented explicitly in `docs/canon/authz-signing-trust-model.md` (new in this plan).

**Tech Stack:** Go (intercore + clavain-cli), `crypto/ed25519` (stdlib), SQLite (migration 033), Bash (gate wrapper extension).

**Prior Learnings:**
- v1 landed `pkg/authz` with `LoadEffective`, `Check`, `Record`. Extend, don't fork.
- v1 schema pre-reserved no signing columns — migration 033 adds `sig_version` + `signature` + `signed_at`.
- `.publish-approved` read path is `core/intercore/internal/publish/approval.go:38` (`RequiresApproval`). Modify there, preserve marker-file fallback.
- Canonical signing input must be stable: JSON-canonical encoding is not stable across Go map ordering; use an explicit field-ordered `|`-delimited string per the brainstorm spec (line 217).
- Key file lives at `.clavain/keys/authz-project.key` (mode 0400) + `.clavain/keys/authz-project.pub` (mode 0444). Do NOT commit; `.gitignore` must exclude the directory.
- v1 authz records are kept as "pre-signing vintage" (NULL signature, `sig_version=0`). A synthetic migration-marker row flags the cutover so NULL-signature ambiguity is resolved.

---

## Must-Haves

**Truths:**
- A fresh key-init (`clavain-cli policy init-key`) produces `.clavain/keys/authz-project.key` (0400) and `.clavain/keys/authz-project.pub` (0444).
- `clavain-cli policy sign` reads all unsigned rows (signature IS NULL, sig_version=0) written after the cutover marker, signs them, and writes `signature` + `signed_at`.
- `clavain-cli policy audit --verify` returns exit 0 when every post-cutover row has a valid signature; exit 1 with row IDs when any row fails.
- A direct SQL mutation of `op_type` or `target` in a post-cutover row makes `--verify` fail on that row.
- `ic publish --patch` on an agent-authored commit succeeds when the `authorizations` table has a recent `ic-publish-patch` row for this plugin (no `.publish-approved` needed); succeeds via `.publish-approved` marker when no authz row exists; fails when neither is present.
- Pre-cutover rows are reported as `vintage=pre-signing` in `--verify --json`, not as failures.

**Artifacts:**
- `core/intercore/internal/db/migrations/033_authz_signing.sql` adds `sig_version` / `signature` / `signed_at` columns + cutover-marker row insert.
- `core/intercore/pkg/authz/sign.go` new file: `Sign`, `Verify`, canonical field encoding.
- `core/intercore/pkg/authz/keys.go` new file: `GenerateKey`, `LoadKey`, `LoadPubKey`, path resolution.
- `os/Clavain/cmd/clavain-cli/authz.go` gains `policy {sign,verify,init-key,rotate-key,quarantine}` subcommands (in addition to the v1 set).
- `core/intercore/internal/publish/approval.go` consults authz records; marker-file path preserved as fallback.
- `os/Clavain/scripts/gates/_common.sh` adds `gate_sign` helper; wrappers call it after `gate_record`.
- `docs/canon/authz-signing-trust-model.md` documents the tamper-evident-post-write claim and what it does NOT cover.

**Key Links:**
- Gate wrapper flow becomes: `policy check` → op → `policy record` → `policy sign` (all four are separate CLI invocations).
- `ic publish` → `RequiresApproval(pluginRoot)` → authz DB lookup first; marker fallback second.
- `policy audit --verify` walks rows, loads pubkey, verifies each signature. Reports per-row status in JSON with `vintage`, `valid`, `sig_version`.

---

## Task 1: Spec-lock round — trust model + signing payload (no code)

**Files:**
- Create: `docs/canon/authz-signing-trust-model.md`
- Create: `docs/canon/authz-signing-payload.md`
- Modify: `docs/brainstorms/2026-04-19-auto-proceed-authz-design.md:~226` (backlink)

**Step 1: Write `docs/canon/authz-signing-trust-model.md`** — pin the tamper-evident-post-write claim. Document:
(a) what an attacker with gate-CLI execution privilege can still do (forge new rows, sign them),
(b) what they cannot do without compromising the key (rewrite history that's already signed),
(c) what direct-SQL attackers cannot do (any post-cutover mutation becomes detectable),
(d) the deprecation path to real separation-of-duties (v1.6 out-of-band signer).

**Step 2: Write `docs/canon/authz-signing-payload.md`** — lock the canonical signing input byte-for-byte: field order, NULL encoding (empty string), separator (LF `\n`), Unicode normalization (NFC), trailing newline policy (none). Include ≥3 worked examples: (i) all fields populated, (ii) optional fields NULL, (iii) vetting JSON embedded. Each example shows the exact byte sequence going into Ed25519.

**Step 3: Commit**
```bash
git add docs/canon/authz-signing-trust-model.md docs/canon/authz-signing-payload.md docs/brainstorms/2026-04-19-auto-proceed-authz-design.md
git commit -m "docs(authz): spec-lock v1.5 trust model + signing payload (sylveste-qdqr)"
```

<verify>
- run: `test -f docs/canon/authz-signing-trust-model.md && grep -c '^### ' docs/canon/authz-signing-payload.md`
  expect: contains "3"
</verify>

---

## Task 2: Migration 033 — signing columns + cutover marker

**Files:**
- Create: `core/intercore/internal/db/migrations/033_authz_signing.sql`
- Modify: `core/intercore/internal/db/db_test.go`

**Step 1: Write migration**
```sql
ALTER TABLE authorizations ADD COLUMN sig_version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE authorizations ADD COLUMN signature   BLOB;
ALTER TABLE authorizations ADD COLUMN signed_at   INTEGER;

-- Cutover marker: every existing row is "pre-signing vintage" (sig_version=0).
-- A synthetic metadata row marks the boundary so audit can distinguish
-- migration-era absence from tampering-era absence.
INSERT INTO authorizations (
  id, op_type, target, agent_id, mode, created_at, sig_version
) VALUES (
  lower(hex(randomblob(16))),
  'migration.signing-enabled',
  'authorizations',
  'system:migration-033',
  'auto',
  strftime('%s','now'),
  1
);

CREATE INDEX IF NOT EXISTS authz_unsigned
  ON authorizations(sig_version, signed_at)
  WHERE signature IS NULL AND sig_version >= 1;
```

**Step 2: Write failing test** (`db_test.go`): assert `sig_version` + `signature` + `signed_at` columns present, partial index exists, cutover marker row exists with `op_type='migration.signing-enabled'`.

**Step 3: Run — expect FAIL** (columns absent). **Step 4: Add migration; re-run — expect PASS.**

**Step 5: Commit**
```bash
git add core/intercore/internal/db/migrations/033_authz_signing.sql core/intercore/internal/db/db_test.go
git commit -m "feat(intercore): add authz signing columns + cutover marker (migration 033, sylveste-qdqr)"
```

<verify>
- run: `cd core/intercore && go test ./internal/db/ -run TestMigration033 -v`
  expect: exit 0
</verify>

---

## Task 3: Key management + signing primitives in `pkg/authz`

**Files:**
- Create: `core/intercore/pkg/authz/keys.go`
- Create: `core/intercore/pkg/authz/keys_test.go`
- Create: `core/intercore/pkg/authz/sign.go`
- Create: `core/intercore/pkg/authz/sign_test.go`

**Step 1: Implement `keys.go`**
```go
package authz

// KeyPair holds a project signing keypair.
type KeyPair struct {
    Priv ed25519.PrivateKey
    Pub  ed25519.PublicKey
}

func GenerateKey() (KeyPair, error)                    // ed25519.GenerateKey
func KeyPaths(projectRoot string) (priv, pub string)   // .clavain/keys/authz-project.{key,pub}
func WriteKeyPair(projectRoot string, kp KeyPair) error  // 0400 priv, 0444 pub, 0700 dir
func LoadPrivKey(projectRoot string) (KeyPair, error)
func LoadPubKey(projectRoot string) (ed25519.PublicKey, error)
func KeyFingerprint(pub ed25519.PublicKey) string      // hex(sha256(pub)[:8])
```
Defense: refuse to load a private key with permissions broader than 0400; refuse to write over an existing key (force opt-in `--rotate`).

**Step 2: Implement `sign.go`**
```go
// CanonicalPayload returns the exact bytes fed to Ed25519 for an
// authorizations row. Spec: docs/canon/authz-signing-payload.md.
// Field order: id|op_type|target|agent_id|bead_id|mode|policy_match|
// policy_hash|vetted_sha|vetting|cross_project_id|created_at
// NULLs → "". Separator: LF. No trailing newline. NFC Unicode.
func CanonicalPayload(row SignRow) []byte

type SignRow struct {
    ID, OpType, Target, AgentID, BeadID, Mode     string
    PolicyMatch, PolicyHash, VettedSHA            string
    Vetting                                        string // canonical JSON string or ""
    CrossProjectID                                string
    CreatedAt                                      int64
}

func Sign(priv ed25519.PrivateKey, row SignRow) []byte
func Verify(pub ed25519.PublicKey, row SignRow, sig []byte) bool
```

**Step 3: Tests** — generate a keypair in a temp dir, sign three rows matching the canon payload examples, verify. Mutate each field; assert verification fails. Test that `LoadPrivKey` rejects 0644 permissions.

**Step 4: Commit**
```bash
git add core/intercore/pkg/authz/{keys.go,keys_test.go,sign.go,sign_test.go}
git commit -m "feat(authz): Ed25519 sign/verify + key management (sylveste-qdqr)"
```

<verify>
- run: `cd core/intercore && go test ./pkg/authz/ -run 'TestSign|TestVerify|TestKey' -v`
  expect: exit 0
</verify>

---

## Task 4: `clavain-cli policy {init-key,sign,verify,rotate-key,quarantine}`

**Files:**
- Modify: `os/Clavain/cmd/clavain-cli/authz.go` (add 5 handlers + dispatch cases)
- Modify: `os/Clavain/cmd/clavain-cli/authz_test.go` (add tests)
- Modify: `os/Clavain/cmd/clavain-cli/main.go` (unchanged if `policy` dispatcher already routes)

**Step 1: Handlers**
```go
func cmdPolicyInitKey(args []string) error    // refuses existing unless --rotate
func cmdPolicySign(args []string) error       // signs NULL-sig rows, --since/--bead filters
func cmdPolicyVerify(args []string) error     // reads --json, exit 1 on any invalid row
func cmdPolicyRotateKey(args []string) error  // writes new key, old records keep old fingerprint via sig_version bump
func cmdPolicyQuarantine(args []string) error // --before-key=<fp>: flag all pre-breach rows
```
Dispatch in `cmdPolicy` switch.

**Step 2: `--verify` audit output** — augment existing `cmdPolicyAudit` to include:
```json
{"id":"...", "vintage":"post-signing|pre-signing|marker", "valid":true|false, "sig_version":1, "fingerprint":"..."}
```
`--verify` flag sets exit code: 0 if all post-signing rows valid, 1 otherwise.

**Step 3: Tests**
```go
TestPolicyInitKey_CreatesKeypairWithCorrectPerms
TestPolicyInitKey_RefusesOverwriteWithoutRotate
TestPolicySign_SignsUnsignedRows
TestPolicySign_SkipsPreCutoverRows
TestPolicyVerify_DetectsMutation
TestPolicyVerify_ExitCodes
TestPolicyQuarantine_FlagsPreBreachRows
```

**Step 4: Commit**
```bash
git add os/Clavain/cmd/clavain-cli/authz.go os/Clavain/cmd/clavain-cli/authz_test.go
git commit -m "feat(clavain-cli): policy sign/verify/init-key/rotate-key/quarantine (sylveste-qdqr)"
```

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && go test -run 'TestPolicy(InitKey|Sign|Verify|Quarantine)' -v`
  expect: exit 0
</verify>

---

## Task 5: Gate wrapper `gate_sign` + orchestration update

**Files:**
- Modify: `os/Clavain/scripts/gates/_common.sh` (add `gate_sign` helper)
- Modify: `os/Clavain/scripts/gates/{bead-close,git-push-main,bd-push-dolt,ic-publish-patch}.sh`
- Modify: `os/Clavain/scripts/gates/gates-smoke_test.sh` (assert signature present after wrapper run)

**Step 1: `gate_sign`** — after `gate_record`, invoke:
```bash
gate_sign() {
  local op="$1" target="$2" bead="${3:-}"
  local args=( --op="$op" --target="$target" )
  [[ -n "$bead" ]] && args+=( --bead="$bead" )
  # best-effort: if key missing or signing fails, log and continue.
  clavain-cli policy sign "${args[@]}" 2>&1 >/dev/null || \
    echo "policy: sign failed (op=${op} target=${target}); row remains unsigned" >&2
}
```
Call after `gate_record` in each wrapper. Best-effort: missing key is a not-yet-installed case, not an op failure.

**Step 2: Smoke test** — after wrapper run, query DB and assert the row's `signature` is non-NULL and verifies against the installed pubkey.

**Step 3: Commit**
```bash
git add os/Clavain/scripts/gates/
git commit -m "feat(authz): gate wrappers sign audit rows post-record (sylveste-qdqr)"
```

<verify>
- run: `bash os/Clavain/scripts/gates/gates-smoke_test.sh`
  expect: contains "PASS" and "signature verified"
</verify>

---

## Task 6: Unify `.publish-approved` via `RequiresApproval()`

**Files:**
- Modify: `core/intercore/internal/publish/approval.go`
- Modify: `core/intercore/internal/publish/approval_test.go` (add authz-record-wins tests)
- Modify: `core/intercore/cmd/ic/publish.go` if needed for wiring

**Step 1: Extend `RequiresApproval` signature**
```go
// RequiresApproval returns true (approval needed) when the last commit is
// agent-authored AND neither signal says human approved:
//   - a recent ic-publish-patch authz record for this plugin (signed + valid), OR
//   - a .publish-approved marker file in the plugin root (legacy fallback).
//
// The authz path is preferred; marker-file path is kept through one
// deprecation window and scheduled for removal in v2.
func RequiresApproval(pluginRoot string) bool
```

**Step 2: Authz-record lookup** — walk up from `pluginRoot` to find the enclosing `.clavain/intercore.db`; query:
```sql
SELECT id, sig_version, signature, policy_hash
FROM authorizations
WHERE op_type='ic-publish-patch' AND target=?
  AND created_at >= ?   -- freshness window (config; default 60min)
ORDER BY created_at DESC LIMIT 1
```
If row found and signature verifies (or is pre-cutover vintage AND freshness is inside the pre-signing allow window), return false.

**Step 3: Freshness + vintage policy** — post-signing rows: 60min default freshness. Pre-signing vintage: **not** acceptable for this path (force re-authorization). Marker-file path: unchanged.

**Step 4: Deprecation log** — when approval is granted via `.publish-approved` marker (not authz record), log a one-line deprecation warning to stderr pointing at `docs/canon/policy-merge.md` and the deprecation timeline.

**Step 5: Tests** — table-driven: (authz-fresh-valid, no-marker) → false; (authz-stale, no-marker) → true; (no-authz, marker) → false + warning; (authz-mutated-signature, marker) → false via marker, warning includes "authz verification failed"; (neither) → true.

**Step 6: Commit**
```bash
git add core/intercore/internal/publish/approval.go core/intercore/internal/publish/approval_test.go
git commit -m "feat(publish): RequiresApproval consults authz records; marker fallback (sylveste-qdqr)"
```

<verify>
- run: `cd core/intercore && go test ./internal/publish/ -v`
  expect: exit 0
</verify>

---

## Task 7: Bootstrap script + docs

**Files:**
- Create: `os/Clavain/scripts/authz-init.sh` (one-shot: init-key + example policy + migrate DB)
- Modify: `os/Clavain/README.md` (v1.5 section under Auto-proceed authorization)
- Modify: `os/Clavain/config/policy.yaml.example` (add comment explaining signing ships in v1.5, no policy change required)

**Step 1: `authz-init.sh`** — idempotent bootstrap:
```bash
# Migrate DB to v33
ic init --db=.clavain/intercore.db

# Install global policy if missing
[[ -f ~/.clavain/policy.yaml ]] || cp config/policy.yaml.example ~/.clavain/policy.yaml

# Initialize project signing key if missing (never overwrites)
[[ -f .clavain/keys/authz-project.key ]] || clavain-cli policy init-key

# Sanity check
clavain-cli policy audit --verify --json | jq '.summary'
```

**Step 2: README quickstart addition** — one subsection: "Signing audit records" — describes key init, rotation, `policy audit --verify`, `policy quarantine`.

**Step 3: Commit**
```bash
git add os/Clavain/scripts/authz-init.sh os/Clavain/README.md os/Clavain/config/policy.yaml.example
git commit -m "feat(authz): authz-init.sh bootstrap + README v1.5 quickstart (sylveste-qdqr)"
```

<verify>
- run: `bash os/Clavain/scripts/authz-init.sh && clavain-cli policy audit --verify --json | jq '.summary.failed'`
  expect: contains "0"
</verify>

---

## Task 8: End-to-end integration test + full matrix

**Files:**
- Create: `os/Clavain/tests/authz-v15-e2e_test.sh`
- Modify: existing `tests/authz-e2e_test.sh` (assert signature post-run)

**Step 1: E2E script** covers:
1. Fresh sandbox, `ic init`, `policy init-key`, project policy installed.
2. Fake vetted bead close via `bead-close.sh`; assert signature present + valid.
3. Mutate `op_type` via direct SQL; assert `policy audit --verify` exits 1 with the row flagged.
4. Fake `ic publish --patch` on an agent-authored commit with a fresh authz record; assert proceeds without `.publish-approved`.
5. Same publish with a stale authz record (>60min); assert prompts (exit=1 in non-tty).
6. Remove the authz record, add `.publish-approved`; assert proceeds with deprecation warning on stderr.

**Step 2: Run full matrix:**
```bash
cd core/intercore && go test ./... -v
cd os/Clavain && go test ./... -v
bash os/Clavain/scripts/gates/gates-smoke_test.sh
bash os/Clavain/tests/vetting-writes_test.sh
bash os/Clavain/tests/authz-e2e_test.sh
bash os/Clavain/tests/authz-v15-e2e_test.sh
```

**Step 3: Commit**
```bash
git add os/Clavain/tests/authz-v15-e2e_test.sh os/Clavain/tests/authz-e2e_test.sh
git commit -m "test(authz): v1.5 e2e — signing, verify, tamper-detect, publish-unify (sylveste-qdqr)"
```

<verify>
- run: `bash os/Clavain/tests/authz-v15-e2e_test.sh`
  expect: contains "PASS"
</verify>

---

## Deferred to v1.6 and v2

- **v1.6 separation-of-duties signer** — move `policy sign` out of the gate-wrapper process into a standalone watcher (systemd/launchd) that owns the signing key. Gate wrappers write unsigned rows only; the watcher signs on its own schedule. Trust claim upgrades to tamper-proof-at-rest. Est. 1 day.
- **v2 tokens + delegation** — `authz_tokens` table, atomic consume, proof-of-possession on delegate, `root_token`+`depth` cascade revoke, CLI surface. Prerequisite for multi-agent delegation that is already live (Claude → codex). Plan: `docs/plans/TBD-auto-proceed-authz-v2.md`. Est. 1 week.
- **`.publish-approved` full removal** — one window after v1.5 ships and telemetry shows >95% of publish approvals going via authz records, remove marker-file path. Est. 2 hours.

---

## Notes on discipline

- **Don't read the signing key during `policy record`.** Only `policy sign` touches it. Keeping the read path minimal is half the point of separating the calls.
- **Don't skip the cutover marker.** A v1 row with NULL signature AND no migration marker is indistinguishable from a rewritten row post-v1.5. The marker resolves this.
- **Don't break v1 callers.** Every pre-v1.5 column and CLI surface must still work. Signing is additive.
- **Trust claim must be documented honestly.** If separation-of-duties is not shipped in v1.5 (it isn't, per this plan), `docs/canon/authz-signing-trust-model.md` must state "tamper-evident-post-write" plainly — not handwave it as "signed = unforgeable".
- **Key rotation breaks cross-project queries.** `policy audit aggregate` across projects needs each project's pubkey; publish pubkeys alongside the repo (in `.clavain/keys/authz-project.pub` tracked by git) so verifiers don't need live filesystem access.
