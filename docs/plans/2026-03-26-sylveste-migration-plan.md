# Sylveste Migration Plan

**Decision date:** 2026-03-26
**Rename:** Sylveste → Sylveste (Dan Sylveste, Reynolds' Revelation Space)
**Interverse:** Stays as-is (no rename)

## Context

After checking 14 candidates from the SF canon against namespace collisions (npm, PyPI, GitHub, commercial products, trademarks), Sylveste was chosen. Zero collisions across all registries and commercial space. Same Reynolds universe as Clavain.

## Pre-migration Checklist

- [ ] Pause mutagen sync to sleeper-service
- [ ] Run `slsebackup` on server (restic snapshot)
- [ ] Local git backup: `git bundle create ~/Sylveste-pre-rename.bundle --all`

## Phase 0: GitHub

- [ ] Rename repo: `github.com/mistakeknot/Sylveste` → `github.com/mistakeknot/Sylveste` (Settings → General)
- [ ] Update local remote: `git remote set-url origin https://github.com/mistakeknot/Sylveste.git`
- [ ] Update server remote via SSH

## Phase 1: Identity Files

Prose replacement "Sylveste" → "Sylveste" in:
- [ ] `CLAUDE.md` (3 occurrences)
- [ ] `AGENTS.md` (1 occurrence)
- [ ] `README.md` (~10 occurrences)
- [ ] `PHILOSOPHY.md` (~9 occurrences — rewrite naming section to explain rename)
- [ ] `MISSION.md` (1 occurrence)
- [ ] `CONTRIBUTING.md` (1 occurrence)
- [ ] `CONVENTIONS.md` (4 occurrences)
- [ ] `GEMINI.md` (2 occurrences)
- [ ] `.gitignore` (1 occurrence, comment)
- [ ] `.github/CODEOWNERS` (1 occurrence, comment)
- [ ] `docs/guides/naming-conventions.md` (update proper nouns table)
- [ ] `install.sh` (25 occurrences — URLs, paths, messages)
- [ ] `uninstall.sh` (5 occurrences)

## Phase 2: Config and Tooling

- [ ] `.beads/config.yaml` — `issue-prefix: "Sylveste"` (new beads only; historical IDs stay `Sylveste-*`)
- [ ] `.serena/project.yml` — `project_name: "Sylveste"`
- [ ] `.interwatch/watchables.yaml` — update doc path references
- [ ] `.gemini/settings.json` — server paths `/home/mk/projects/Sylveste/` → `.../Sylveste/`
- [ ] `.claude/settings.local.json` — update path references
- [ ] 46 `.gitleaks.toml` — batch: `sylveste-managed` → `sylveste-managed`, title update
- [ ] 45 `.github/workflows/secret-scan.yml` — batch: `sylveste-managed` → `sylveste-managed`
- [ ] `interverse/intername/data/themes/sylveste.json` → `sylveste.json`, update `"name"` field

## Phase 3: Source Code

### Rust (8 files in `apps/Intercom/rust/`)
- [ ] `sylveste.rs` → `sylveste.rs`
- [ ] Rename: `SylvesteConfig` → `SylvesteConfig`, `SylvesteStatus` → `SylvesteStatus`, `SylvesteResponse` → `SylvesteResponse`, `SylvesteCommandPlan` → `SylvesteCommandPlan`, `SylvesteAdapter` → `SylvesteAdapter`
- [ ] Update `mod sylveste` → `mod sylveste` in `lib.rs`
- [ ] Update imports in `config.rs`, `events.rs`, `ipc.rs`, `main.rs`, `telegram_poller.rs`, `integration_smoke.rs`

### Go (17 files across multiple modules)
- [ ] `tools_sylveste.go` → `tools_sylveste.go`
- [ ] `RegisterSylvesteTools()` → `RegisterSylvesteTools()`
- [ ] Tool names: `sylveste_read` → `sylveste_read`, `sylveste_write` → `sylveste_write`
- [ ] SQL defaults: `'sylveste'` → `'sylveste'` (3 columns — needs schema migration)
- [ ] Update across `apps/Intercom/go/`, `apps/Autarch/`, `core/interweave/`, `core/intermute/`, `sdk/interbase/`, `interverse/intermux/`

### TypeScript (4 files in `apps/Intercom/container/`)
- [ ] `sylveste-tools.ts` → `sylveste-tools.ts`
- [ ] `ipc-sylveste.ts` → `ipc-sylveste.ts`
- [ ] 14 exported functions: `sylvesteRunStatus()` → `sylvesteRunStatus()`, etc.
- [ ] Update imports in `system-prompt.ts`, agent runner files

### Shell (1 file)
- [ ] `sylveste-query.sh` → `sylveste-query.sh`

### masaq (2 files)
- [ ] `masaq/theme/theme.go` — comment update
- [ ] `masaq/masaq.go` — package comment update

## Phase 4: Documentation (batch sed)

- [ ] 15 subproject `CLAUDE.md` files
- [ ] 45 subproject `AGENTS.md` files
- [ ] ~666 `docs/` markdown files
- [ ] ~50 JSON data files (manual review for structured data)
- [ ] ~20 `.claude/flux-gen-specs/` files
- [ ] Plugin JSON files (`plugin.json`, `marketplace.json`) — scan for "Sylveste" references
- [ ] **DO NOT rename** sprint transcript filenames (`docs/sprints/Sylveste-*.md`) — historical records

## Phase 5: Filesystem Renames

### Local machine
- [ ] `mv /Users/sma/projects/Sylveste /Users/sma/projects/Sylveste`
- [ ] `mv ~/.local/share/Sylveste ~/.local/share/Sylveste`
- [ ] Copy memory files from `~/.claude/projects/-Users-sma-projects-Sylveste/memory/` to new auto-created path
- [ ] Update any shell aliases or PATH entries

### Server (sleeper-service)
- [ ] `mv /home/mk/projects/Sylveste /home/mk/projects/Sylveste`
- [ ] Update compatibility symlinks if any
- [ ] Resume mutagen sync with new paths

## Phase 6: Post-migration Verification

- [ ] `grep -ri "Sylveste" --include="*.go" --include="*.rs" --include="*.ts" --include="*.yaml" --include="*.json"` — catch missed renames (excluding sprint docs, bead records)
- [ ] `bd doctor` — verify beads works with new prefix
- [ ] Build Rust: `cargo build` in `apps/Intercom/rust/`
- [ ] Build Go: `go build ./...` in each Go module
- [ ] Build TS: `npm run build` or `tsc` in `apps/Intercom/container/`
- [ ] Delete `.tldrs/cache/` and re-index
- [ ] Regenerate `.gemini/generated-skills/` if needed
- [ ] Run `interwatch` baseline refresh
- [ ] `git push` — verify GitHub redirect works
- [ ] Resume mutagen: `mutagen sync resume <session>`

## What NOT to Rename

| Item | Reason |
|------|--------|
| Historical bead IDs (`Sylveste-*`) | Immutable identifiers in JSONL, referenced in sprint docs and git history |
| Sprint transcript filenames | Historical records, contain bead IDs |
| Git history | Never rewrite; the rename is a point-in-time event |
| `.tldrs/cache/` | Auto-generated, delete and regenerate |

## Risk Mitigation

- **Mutagen**: MUST be paused before filesystem renames. Directory rename propagating as delete+create would be catastrophic.
- **Beads**: Old `Sylveste-*` IDs remain valid for lookups. `bd show Sylveste-5u8u` should still work. Test this.
- **SQL schema**: Go code has `'sylveste'` as DEFAULT in 3 columns. Write a migration script: `ALTER TABLE ... ALTER COLUMN ... SET DEFAULT 'sylveste'`. Existing rows can stay.
- **Install script URLs**: GitHub redirects last indefinitely, but update install.sh to point to new URL.

## Execution Order

```
1. Pre-migration (backup, pause mutagen)
2. Phase 0 (GitHub rename)
3. Phase 1 (identity files)
4. Phase 2 (config/tooling)
5. Phase 3 (source code)
6. Phase 4 (documentation — batch)
7. Phase 5 (filesystem — local then server)
8. Phase 6 (verify, build, push, resume mutagen)
```

Estimated effort: ~2-3 focused sessions. Phase 4 is the largest by file count but most mechanical. Phase 3 requires the most care.
