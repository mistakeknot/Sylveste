---
date: 2026-04-30
session: sylveste-2ss-c2-migration
topic: C2 routing migrated to Qwen3.6-35B-A3B; CONFIG_REGISTRY pruned of dominated configs
beads: [Sylveste-2ss, Sylveste-6f0, Sylveste-bvh, Sylveste-6ru, Sylveste-ep8, Sylveste-0gi]
---

## Session Handoff — 2026-04-30 C2 migration shipped

### Directive (next session)

> Flash-moe debug remains the highest-leverage outstanding item. Pick one of:
> (a) Sylveste-6f0 — investigate flash-moe slowness (4 tok/s actual vs 12.9 spec'd) and worker crash at problem 151 (urlopen err 60). Reproduction needs telemetry that wasn't captured during the 5h45m matrix run.
> (b) Sylveste-bvh — add cloud:deepseek-v4-flash + cloud:deepseek-v4-pro to LCB v6 matrix (V4 doesn't fit on 128GB, must be cloud-API).
> (c) Sylveste-0gi — port DeepSeek V4 Flash to flash-moe (now higher priority since flash-moe-397B under-delivered).

### Shipped this session

1. **os/Clavain `99ce7f8`** — `feat(routing): migrate C2 to Qwen3.6-35B-A3B + demote flash-moe`. C1/C2 → `local:qwen3.6-35b-a3b-4bit`, C3 → `cloud` (was flash-moe). `lib-routing.sh:_routing_model_tier()` updated to recognize the new ID so safety floors enforce on fd-safety/fd-correctness.
2. **interverse/interfer `9fcdd8b`** — `chore(interfer): prune dominated configs from LCB matrix registry`. Dropped 5 dominated configs (3.5-35b, 3.5-122b, 3.6-27b, 3.6-DWQ, 3.6-DWQ-thinking) + companion fixes to MODEL_ALIASES, test fixtures (8/8 pass), docstring CLI examples.
3. **anthropics/claude-code#38181** — added a comment with monorepo-with-subrepos reproduction of the GIT_INDEX_FILE pollution bug (208k-line phantom diff scenario).

### Dead Ends

- **bd dolt auto-start was wedged** — 5 zombie dolt sql-server processes (PPID 1, no clients) from sessions going back to 2026-04-18 held exclusive write locks on the database. Killed all 5 with TERM, bd recovered immediately.
- **Subrepo git status returned `fatal: unable to read <SHA>`** — *not* repo damage. Claude Code sets `GIT_INDEX_FILE=<umbrella>/.git/index-<session-uuid>` per shell, which poisons every git op in subrepos with phantom blob refs. Always prefix with `env -u GIT_INDEX_FILE`. Documented in `docs/handoffs/2026-04-19-mac-repo-repair.md` (Sylveste-ql9). Worth ~1 hour of false-corruption diagnosis.
- **`bd backup`** is now `bd export --output .beads/issues.jsonl` (CLI changed; many docs/hooks still reference the old name).
- **`.beads/push.sh`** requires TTY confirmation — not callable from agent context. User must run interactively.

### Context

- Clavain rebase: local main was 4 commits behind origin during the push. Stashed unrelated drift (`bin/clavain-cli-go-darwin-arm64`, `commands/sprint.md`), `pull --rebase`, push, `stash pop`. Final HEAD: `99ce7f8`.
- Untouched local drift in both subrepos (per global Unexpected Changes Policy):
  - `os/Clavain`: `bin/clavain-cli-go-darwin-arm64`, `commands/sprint.md`
  - `interverse/interfer`: `pyproject.toml`, `uv.lock`, untracked `.clavain/`
- Sylveste-2ss kept in_progress per directive — only the C2 migration + registry prune deliverables shipped; flash-moe stability/perf scope still open. Full progress note appended to the bead.
- `.beads/issues.jsonl` re-exported (1294 issues). **Not pushed** — push.sh needs TTY.
- Memory entry added: `feedback_git_index_file_pollution.md` so future sessions skip the false-corruption rabbit hole.

### Open beads (carried forward)

- **Sylveste-6f0** (P2) flash-moe slowness/crash investigation
- **Sylveste-bvh** (P2) Add DeepSeek V4 cloud configs to LCB v6 matrix
- **Sylveste-6ru** (P2) Qwen3.6 quantization sweep — partially answered by DWQ prune
- **Sylveste-ep8** (P2) Qwen3.6-27B-OptiQ — superseded by 27B-dense dominance finding, low priority
- **Sylveste-0gi** (P2) Port DeepSeek V4 Flash to flash-moe — higher priority post-matrix
- **Sylveste-ql9.b** (still open from 2026-04-19) — structural fix to autosync hook so it can't recontaminate child indexes. Note: my repro found Claude harness itself sets GIT_INDEX_FILE even with autosync hook absent, so ql9.b alone isn't sufficient.

### Pre-flight for next session

```bash
# 1. Always clear GIT_INDEX_FILE env:
unset GIT_INDEX_FILE

# 2. Push beads from this session:
bash .beads/push.sh

# 3. Push umbrella docs (this handoff):
git add docs/handoffs/2026-04-30-sylveste-2ss-c2-migration-shipped.md docs/handoffs/latest.md
git commit -m "docs(handoffs): 2026-04-30 C2 migration shipped"
git push

# 4. Verify bd reachable:
bd list --status=in_progress | head
```
