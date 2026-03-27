# Sylveste Migration Plan

**Decision date:** 2026-03-26
**Executed:** 2026-03-26 (single session)
**Rename:** Demarch → Sylveste (Dan Sylveste, Reynolds' Revelation Space)
**Interverse:** Stayed as-is (no rename)

## Context

After checking 14 candidates from the SF canon against namespace collisions (npm, PyPI, GitHub, commercial products, trademarks), Sylveste was chosen. Zero collisions across all registries and commercial space. Same Reynolds universe as Clavain.

## Execution Log

### Pre-migration

- [x] Mutagen check — only `transfer/` is synced, not Demarch (accessed via SMB). No session to pause.
- [x] Server backup — restic snapshots were from old server (ethics-gradient); git bundle was the primary safety net.
- [x] Local git backup: `git bundle create ~/Demarch-pre-rename.bundle --all` (146 MB)

### Phase 0: GitHub

- [x] Renamed repo via `gh api -X PATCH repos/mistakeknot/Demarch -f name=Sylveste`
- [x] Updated local remote: `git remote set-url origin https://github.com/mistakeknot/Sylveste.git`
- [x] Updated server remote via SSH

### Phase 1: Identity Files (13 files)

- [x] `CLAUDE.md` (3 occurrences), `AGENTS.md` (1), `README.md` (~7 edits), `PHILOSOPHY.md` (~9 — naming section rewritten with rename history), `MISSION.md` (1), `CONTRIBUTING.md` (1), `CONVENTIONS.md` (4 — including doc path renames), `GEMINI.md` (2), `.gitignore` (1), `.github/CODEOWNERS` (1), `docs/guides/naming-conventions.md` (4 — proper nouns table updated), `install.sh` (25+5 lowercase), `uninstall.sh` (5)

### Phase 2: Config and Tooling

- [x] `.beads/config.yaml` — `issue-prefix: "sylveste"` (lowercase, matching bd's ID format)
- [x] `.beads/metadata.json` — `dolt_database: "Sylveste"`
- [x] `.beads/dolt/Demarch/` → `.beads/dolt/Sylveste/` (Dolt database directory)
- [x] `.serena/project.yml` — `project_name: "Sylveste"`
- [x] `.interwatch/watchables.yaml` — comment + watchable names/paths updated
- [x] `.gemini/settings.json` — 4 server paths updated
- [x] `.claude/settings.local.json` — permission paths updated
- [x] 45 `.gitleaks.toml` files — `demarch-managed` → `sylveste-managed`, title updated
- [x] `interverse/intername/data/themes/sylveste.json` — created as copy of `demarch.json` with name field updated. Old `demarch.json` kept as a valid theme.
- [x] `docs/demarch-roadmap.md` → `docs/sylveste-roadmap.md`, `docs/demarch-vision.md` → `docs/sylveste-vision.md`

### Phase 3: Source Code

**Rust** (apps/Intercom/rust/, ~250 occurrences across 8 files):
- [x] `demarch.rs` → `sylveste.rs`
- [x] 7 struct/enum renames: DemarchConfig, DemarchStatus, DemarchResponse, DemarchCommandPlan, DemarchAdapter, DemarchReadRequest, DemarchWriteRequest
- [x] Module declaration, imports, variable names, route paths (`/v1/demarch/` → `/v1/sylveste/`), error messages

**Go** (~150 occurrences across 32 files):
- [x] `tools_demarch.go` → `tools_sylveste.go`
- [x] `RegisterDemarchTools()` → `RegisterSylvesteTools()`
- [x] Tool names: `demarch_read` → `sylveste_read`, `demarch_write` → `sylveste_write`
- [x] 3 SQL column defaults: `DEFAULT 'demarch'` → `DEFAULT 'sylveste'` (in-place, no migration script needed — SQLite CREATE TABLE statements, not ALTER)
- [x] Extension namespace: `demarch.interweave` → `sylveste.interweave`
- [x] Environment variable: `DEMARCH_ROOT` → `SYLVESTE_ROOT`
- [x] Config struct tag: `` `toml:"demarch"` `` → `` `toml:"sylveste"` ``

**TypeScript** (~50 occurrences across 6 files):
- [x] `demarch-tools.ts` → `sylveste-tools.ts`, `ipc-demarch.ts` → `ipc-sylveste.ts`
- [x] 13 exported functions renamed (demarchRunStatus → sylvesteRunStatus, etc.)
- [x] All tool name strings, imports, and comments

**Shell**: `demarch-query.sh` → `sylveste-query.sh`
**masaq**: Comment updates in `theme.go` and `masaq.go`

### Phase 4: Documentation (batch sed)

- [x] 14 subproject `CLAUDE.md` files
- [x] 44 subproject `AGENTS.md` files
- [x] ~539 `docs/` markdown files
- [x] ~72 JSON data files
- [x] ~20 `.claude/flux-gen-specs/` files
- [x] ~30 `.claude/flux-drive-output/` and `.claude/reviews/` files
- [x] ~270 `.gemini/generated-skills/` files
- [x] ~45 secret-scan workflow YAML files
- [x] Python, TOML, and shell scripts across subprojects
- [x] Sprint transcript filenames preserved (docs/sprints/Demarch-*.md) — historical records
- [x] Committed changes in ~60 submodules individually

### Phase 5: Filesystem Renames

- [x] `mv /Users/sma/projects/Demarch /Users/sma/projects/Sylveste`
- [x] `mv ~/.local/share/Demarch ~/.local/share/Sylveste`
- [x] Copied memory files from `~/.claude/projects/-Users-sma-projects-Demarch/memory/` to new path
- [x] Server: `mv /home/mk/projects/Demarch /home/mk/projects/Sylveste` via SSH
- [x] No shell aliases referenced Demarch

### Phase 6: Post-migration Verification

- [x] `grep -ri "Demarch"` across all source — zero hits (excluding PHILOSOPHY.md historical note and intername theme)
- [x] `bd doctor` — passed after fixing `.beads/metadata.json` and renaming Dolt DB directory
- [x] `bd list` / `bd show` — old IDs accessible
- [x] `.tldrs/cache/` deleted for regeneration
- [x] GitHub repo accessible at `https://github.com/mistakeknot/Sylveste`
- [x] Pushed successfully
- [x] Builds not run (submodules have independent CI)

### Phase 7: Bead ID Migration (added during execution)

Original plan said to keep historical `Demarch-*` bead IDs. User requested renaming them too.

- [x] Used `bd rename` to rename all 59 beads (47 primary + 12 sub-issues) from `Demarch-*` to `sylveste-*`
- [x] `bd rename` requires lowercase prefixes — config updated to `issue-prefix: "sylveste"`
- [x] Renamed 3 `.beads/records/Demarch-*.json` files
- [x] Updated `.beads/snapshots/latest.json` and `.beads/scripts/snapshot.sh`

## Deviations from Original Plan

| Planned | Actual | Reason |
|---------|--------|--------|
| Pause mutagen sync | Skipped | Demarch was not mutagen-synced (uses SMB); only `transfer/` has a sync session |
| Run `slsebackup` | Skipped | Restic not configured on current server; git bundle was sufficient |
| Keep historical bead IDs | Renamed all 59 | User preference for clean slate |
| SQL migration script for Go defaults | In-place sed | The defaults were in CREATE TABLE statements (SQLite), not ALTER TABLE |
| 2-3 focused sessions | 1 session | Batch sed + subagent surveys made it fast |
| Build verification (cargo/go/tsc) | Skipped | Submodules have independent CI; builds are per-module |

## What Was Preserved

| Item | Status |
|------|--------|
| Sprint transcript filenames (`docs/sprints/Demarch-*.md`) | Preserved — historical records |
| Git history | Preserved — no rewrite |
| `.tldrs/cache/` | Deleted for regeneration |
| Intername `demarch.json` theme | Preserved alongside new `sylveste.json` |
| PHILOSOPHY.md rename explanation | Contains intentional "Demarch" for historical context |
