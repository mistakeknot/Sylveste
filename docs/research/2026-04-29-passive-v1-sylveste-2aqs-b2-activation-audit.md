# Passive-v1 dogfood: `sylveste-2aqs` B2 caller activation audit

Date: 2026-04-29
Bead: `sylveste-8r5h.19`
Target: `sylveste-2aqs` — Adaptive routing activation / B2 caller wiring

## Verdict

**Passive-v1 found a real activation gap.**

The B2 caller activation commits exist on the Clavain and interflux remotes, and the Beads closeout for `sylveste-2aqs` accurately describes the intended code changes. However, the local worktrees and installed Claude Code plugin cache are still on stale commits at the same plugin versions:

| Plugin | Installed version | Installed commit | Repo `origin/main` | Activation state |
|---|---:|---|---|---|
| Clavain | `0.6.250` | `222616c` | `d4aa453` | **activation_gap_likely** |
| interflux | `0.2.67` | `78b1c2d` | `e121df8` | **activation_gap_likely** |

Because Claude Code resolves `/clavain:quality-gates` and `/interflux:flux-drive` from `~/.claude/plugins/cache/interagency-marketplace/...`, users invoking those commands currently see the pre-B2 caller behavior. The implementation has landed upstream, but it is not yet activated in the live installed plugin surface.

## Anchor / source of truth

`bd show sylveste-2aqs --long` says the bead closed at 2026-04-29 09:07 with:

- Clavain `d4aa453 feat(routing): shadow B2 compose callers`
- interflux `e121df8 feat(flux-drive): consume Clavain B2 routing contract`

The root Sylveste Beads reconciliation commit is `8cf25cf1 chore(beads): close B2 caller activation beads`.

## Passive evidence checked

### 1. Clavain remote has the intended B2 caller changes

`os/Clavain origin/main` is at `d4aa453` and includes:

- `commands/quality-gates.md`
  - exports `CLAVAIN_REVIEW_TOKENS`, `CLAVAIN_REVIEW_FILE_COUNT`, `CLAVAIN_REVIEW_DEPTH`
  - calls `routing_resolve_agents --phase "quality-gates" ...`
  - invokes `/interflux:flux-drive $DIFF_PATH --phase=quality-gates`
- `scripts/lib-compose.sh`
  - forwards `CLAVAIN_REVIEW_TOKENS`, `CLAVAIN_REVIEW_FILE_COUNT`, `CLAVAIN_REVIEW_DEPTH` into `clavain-cli compose`
- `cmd/clavain-cli/compose.go`
  - emits `complexity_tier`
  - records `b2_shadow:*` warnings/metadata

### 2. interflux remote has the intended B2 caller changes

`interverse/interflux origin/main` is at `e121df8` and includes:

- `skills/flux-drive/phases/launch.md`
  - exports Clavain review signals
  - calls `compose_dispatch`
  - records `CLAVAIN_COMPOSE_PLAN`
  - treats a Composer plan as authoritative when present

### 3. Live/local Clavain surface is stale

Current local repo:

- `os/Clavain HEAD` = `222616c`, behind `origin/main` by 3 commits
- `.claude-plugin/plugin.json` version remains `0.6.250` both at HEAD and origin/main
- `commands/quality-gates.md` at local HEAD has none of:
  - `CLAVAIN_REVIEW_*`
  - `--phase=quality-gates`
  - `routing_resolve_agents`
- `scripts/lib-compose.sh` at local HEAD does not forward `CLAVAIN_REVIEW_*`
- `cmd/clavain-cli/compose.go` at local HEAD does not expose `complexity_tier` or `b2_shadow`

Installed Claude Code cache confirms the same stale state:

- path: `~/.claude/plugins/cache/interagency-marketplace/clavain/0.6.250`
- `installed_plugins.json` records `gitCommitSha = 222616cf12054b169be82cf1a57f934d916bab32`
- cache `commands/quality-gates.md` has none of `CLAVAIN_REVIEW_*`, `--phase=quality-gates`, or `routing_resolve_agents`
- cache `scripts/lib-compose.sh` has no review-signal forwarding
- cache `cmd/clavain-cli/compose.go` has no `complexity_tier` / `b2_shadow`

### 4. Live/local interflux surface is stale

Current local repo:

- `interverse/interflux HEAD` = `78b1c2d`, behind `origin/main` by 1 commit
- `.claude-plugin/plugin.json` version remains `0.2.67` both at HEAD and origin/main
- local `skills/flux-drive/phases/launch.md` does not include `CLAVAIN_COMPOSE_PLAN` or `CLAVAIN_REVIEW_*`

Installed Claude Code cache confirms the same stale state:

- path: `~/.claude/plugins/cache/interagency-marketplace/interflux/0.2.67`
- `installed_plugins.json` records `gitCommitSha = 78b1c2d3b0ecd5819f6d00179714cf617be78e30`
- cache `skills/flux-drive/phases/launch.md` does not include `CLAVAIN_COMPOSE_PLAN` or `CLAVAIN_REVIEW_*`

### 5. Codex dispatch is still fixed-tier even on origin

`skills/flux-drive/phases/launch-codex.md` is unchanged between interflux local HEAD and origin/main:

```bash
CLAVAIN_DISPATCH_PROFILE=clavain bash "$DISPATCH" \
  --template "$REVIEW_TEMPLATE" \
  --prompt-file "$FLUX_TMPDIR/{agent-name}.md" \
  -C "$PROJECT_ROOT" \
  -s workspace-write \
  --tier deep
```

This may be intentional for review quality, but passive-v1 should not count it as B2 activated without an explicit exception. It currently does not consume the B2 complexity tier or routed compose plan the way the Task/Claude path can.

## Per-path classification

| User-facing path | Classification | Why |
|---|---|---|
| `/clavain:quality-gates` | `activation_gap_likely` | B2 signal export and `--phase=quality-gates` exist on Clavain `origin/main`, but the installed cache and local HEAD are stale at `222616c`; live users invoke stale command text. |
| `/interflux:flux-drive` Task launch | `activation_gap_likely` | `CLAVAIN_COMPOSE_PLAN` and review-signal export exist on interflux `origin/main`, but installed cache/local HEAD are stale at `78b1c2d`; live users invoke stale launch instructions. |
| Clavain `compose_dispatch` / `clavain-cli compose` | `activation_gap_likely` | `complexity_tier`, `b2_shadow`, and shell forwarding exist on Clavain `origin/main`, but the installed/local code lacks those fields and forwards no review signals. |
| Claude Code review users | `activation_gap_likely` | Claude Code installed plugin records point to stale commits at the same versions (`clavain@0.6.250` -> `222616c`, `interflux@0.2.67` -> `78b1c2d`). Same-version cache means an ordinary user may not get the remote commits. |
| interflux Codex dispatch | `documented_fixed_tier_exception` | `sylveste-8r5h.19.2` keeps Codex review on fixed `--tier deep` by explicit exception rather than treating it as a B2/Composer-routed consumer path; the exception is structural-test covered. |

## Follow-up beads created

1. `sylveste-8r5h.19.1` — **Publish B2 caller activation into live Clavain/interflux plugin installs**
   - P1 because the upstream work exists but is not yet present in live Claude Code plugin cache.
   - Must make the version/release path unambiguous; current same-version cache is the value gap.

2. `sylveste-8r5h.19.2` — **Route interflux Codex dispatch through B2 complexity tier or record fixed-tier exception**
   - P2 because Codex fixed deep routing may be acceptable, but it must be explicit and tested.

## 2026-04-30 addendum: Codex fixed-tier exception (`sylveste-8r5h.19.2`)

Decision: record and test a fixed-tier exception rather than introducing per-agent B2/Composer complexity routing into Codex review dispatch.

`launch-codex.md` now makes the exception explicit:

- preserves `CLAVAIN_DISPATCH_PROFILE=clavain` for Clavain-in-Codex policy selection;
- preserves fixed `--tier deep` for stable cross-agent review depth;
- adds/preserves `--phase=flux-review` as audit context and a future phase-aware dispatch hook, not a current tier selector;
- points dispatch policy readers at `config/routing.yaml` instead of the non-existent `config/dispatch/tiers.yaml`.

Passive-v1 interpretation: Codex review dispatch is no longer a silent B2 activation gap, but it also should not be counted as a B2/Composer-routed consumer path. The routed compose path remains `phases/launch.md`; Codex mode is an explicit, tested exception.

Structural coverage: `interverse/interflux/tests/structural/test_skills.py::test_flux_drive_codex_launch_records_fixed_tier_exception` asserts the fixed-tier exception language, `--tier deep`, `--phase=flux-review`, `CLAVAIN_DISPATCH_PROFILE=clavain`, and `config/routing.yaml` reference.

## Passive-v1 finding

This is exactly the class of gap passive-v1 is meant to catch: Beads and upstream commits say “done,” but the live user-facing surface still invokes stale plugin content. The most valuable next work is not more routing sophistication; it is publishing/installation activation proof.

## Recommended next action

Follow-up status as of 2026-04-30:

1. `sylveste-8r5h.19.1` fixed the static installed-plugin path ambiguity with patch versions and installed-cache marker smoke proof.
2. `sylveste-8r5h.19.2` resolved the Codex dispatch ambiguity as an explicit tested exception, not a B2/Composer-routed consumer path.

Next passive-v1 work should measure live usage/value evidence from user-facing plugin invocations rather than treating static source/installed markers as final activation telemetry.
