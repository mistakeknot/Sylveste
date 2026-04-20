---
artifact_type: handoff
bead: sylveste-qdqr
date: 2026-04-20
session: 31bf39f9-e40a-4472-9ad6-253a03cf9a52
status: complete
---

# Session handoff — authz v1.5 shipped (sylveste-qdqr)

## Directive achieved

Executed Tasks 4–8 of `docs/plans/2026-04-19-auto-proceed-authz-v1.5.md`. Tasks 1–3 had been shipped in the prior session. v1.5 is now end-to-end: Ed25519 signing pipeline, gate-wrapper integration, publish-approval unification, bootstrap script, E2E tests. Full matrix green. All six commits pushed.

## Commits (all on main, all pushed)

| Repo | SHA | Task | One-liner |
|---|---|---|---|
| Clavain | `dffbe42` | 4 | `policy {init-key,sign,verify,rotate-key,quarantine}` subcommands + `audit --verify` |
| intercore | `ba1a1f2` | 5a | `authz.Record` sets `sig_version=1` on insert |
| Clavain | `a5253c2` | 5b | `gate_sign` helper + called from all 4 wrappers; smoke test asserts signature + verify |
| intercore | `394f530` | 6 | `RequiresApproval` consults authz records first; marker-file fallback w/ deprecation warning |
| Clavain | `a00efed` | 7 | `scripts/authz-init.sh` (idempotent bootstrap) + README v1.5 quickstart + policy example note |
| Clavain | `46a92fe` | 8 | `tests/authz-v15-e2e_test.sh` (4 scenarios); v1 E2E updated to assert signature |

## What shipped

- **Key management:** `clavain-cli policy init-key` / `rotate-key` write `.clavain/keys/authz-project.{key,pub}` at 0400 / 0444 under `.clavain/keys/` (0700). `LoadPrivKey` rejects any perms broader than 0400.
- **Canonical signing payload:** 12 ordered fields, LF-separated, NFC-normalized, no trailing newline, control-char rejection. Spec: `docs/canon/authz-signing-payload.md`.
- **Gate-wrapper flow:** `policy check` → op → `policy record` → `policy sign` (four separate CLI invocations). Private key is read only during `policy sign`.
- **Tamper detection:** `policy audit --verify` (and `policy verify`) classify every row as `marker` / `pre-signing` / `post-signing`, verify each post-signing signature, exit 1 on any failure.
- **Publish approval unification:** `RequiresApproval(pluginRoot)` reads `.clavain/intercore.db` for a fresh, signed `ic-publish-patch` row before falling back to `.publish-approved`. Marker-file approval now emits a one-line deprecation warning to stderr.
- **Bootstrap:** `bash os/Clavain/scripts/authz-init.sh` runs the 5-step idempotent install (migrate → policy → key → sign → verify).
- **Trust claim:** tamper-evident-post-write. Documented honestly in `docs/canon/authz-signing-trust-model.md`.

## Self-dogfood status

Sylveste's own `.clavain/` has been bootstrapped this session:
- Project signing key at `.clavain/keys/authz-project.{key,pub}`
- DB at schema v33
- 3 pre-existing v1 rows classified as `pre-signing` vintage (not failures)
- Cutover marker signed, verify OK

`/home/mk/.local/bin/{ic,clavain-cli}` both rebuilt from the new code and installed.

## Caveats worth naming

- **v1 rows are pre-signing vintage.** Anything written by the v1-era `authz.Record` has `sig_version=0`. `policy audit --verify` treats them as `vintage: pre-signing` / `valid: true` — detection applies only to post-cutover rows. This is by design per the trust model.
- **Key rotation requires re-signing.** After `policy rotate-key`, rows signed with the old key fail verify under the new key. The archived pubkey stays on disk so verifiers can check historical rows manually, but the day-to-day `policy audit --verify` expects rows signed with the current active key. Production projects rotating keys will need a post-rotate `policy sign` pass.
- **`gate_sign` is best-effort.** A missing project key logs `policy: sign failed ...; row remains unsigned` to stderr but does NOT fail the op. The row is recoverable — a later `policy sign` pass picks it up. This keeps ops from breaking during partial rollout.
- **Freshness window on publish approval:** default 60 min, overridable via `PUBLISH_AUTHZ_FRESHNESS_MIN` (minutes). Pre-signing vintage rows are rejected on this path regardless of freshness — publish auto-approval requires a real signature.

## Deferred to later phases

- **v1.6** — move `policy sign` into an out-of-band watcher (systemd/launchd) owning the signing key. Gate wrappers write unsigned rows; the watcher signs on its own schedule. Upgrades the trust claim to tamper-proof-at-rest.
- **v2** — `authz_tokens` table, atomic consume, proof-of-possession on delegate, `root_token` + `depth` cascade revoke, CLI surface. Prerequisite for Claude → codex delegation already live in sprints. Plan TBD.
- **`.publish-approved` full removal** — after telemetry shows >95% of publish approvals going through authz records, strip the marker-file fallback. Est. 2 hours.

## Test matrix (all green)

| Test | Result |
|---|---|
| `core/intercore ./...` (30+ packages) | ok |
| `os/Clavain/cmd/clavain-cli ./...` | ok |
| `scripts/gates/gates-smoke_test.sh` | PASS + signature verified |
| `tests/vetting-writes_test.sh` | PASS (pre-existing regression) |
| `tests/authz-e2e_test.sh` (v1 + signing) | PASS |
| `tests/authz-v15-e2e_test.sh` (new, 4 scenarios) | PASS |

## Open questions (none blocking)

- `policy sign` default scope stayed as "sign all unsigned post-cutover rows" — no flag required. Gate wrappers narrow via `--op/--target/--bead`. If this becomes noisy in practice, consider requiring `--all` for the unfiltered case.
- `gate_sign` runs every wrapper; in a burst (e.g., multi-bead close during sprint wrap) this means N CLI invocations signing N rows. Performance measurable but not pathological in a 1 MB DB. Batch signing (single invocation covering multiple rows) is a v1.6 candidate.

## If the next session wants to continue this

- Consider wiring `authz-init.sh` into `agent-rig install mistakeknot/Clavain` so fresh installs auto-bootstrap.
- Consider a `.gitignore` entry for `.clavain/keys/*.key` at the Clavain and Sylveste repo root (pubkey intentionally committed; private never).
- Consider writing v2 token protocol plan now while context is warm — delegation is the next real pressure point.
