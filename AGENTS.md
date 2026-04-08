# Sylveste — Agent Development Guide

Open-source autonomous software development agency platform. Six pillars (Intercore, Clavain, Skaffen, Interverse, Autarch, Interspect) across three layers (L1 kernel, L2 OS, L3 apps). 58 Interverse plugins, 18 with MCP servers.

## Quick Reference

```bash
bd ready                                  # See available work
git rev-parse --show-toplevel             # Verify which repo you're in
cd interverse/<name> && uv run pytest tests/structural/ -v  # Plugin tests
cd core/intercore && go test ./...        # Kernel tests
ic publish --patch                        # Publish plugin (Go CLI)
scripts/bump-version.sh <ver>             # Publish plugin (shell)
bd close <id> && git push                 # Complete work (`bd sync` first only if your local bd build supports it)
```

## Topic Guides

| Topic | File | Covers |
|-------|------|--------|
| Architecture | [agents/architecture.md](agents/architecture.md) | Overview, glossary, directory layout, dependency chains, compatibility |
| Session Protocol | [agents/session-protocol.md](agents/session-protocol.md) | Agent quickstart, git autosync, instruction loading order, landing the plane, memory provenance |
| Design Doctrine | [agents/design-doctrine.md](agents/design-doctrine.md) | Philosophy filters, anti-patterns, brainstorming/planning guidelines |
| Development Workflow | [agents/development-workflow.md](agents/development-workflow.md) | Running/testing by module type, publishing, cross-repo changes |
| Plugin Publishing | [agents/plugin-publishing.md](agents/plugin-publishing.md) | Publish gate, version bumping (interbump), ecosystem diagram |
| Beads Workflow | [agents/beads-workflow.md](agents/beads-workflow.md) | Bead tracking, label taxonomy, recovery scripts, roadmap |
| Critical Patterns | [agents/critical-patterns.md](agents/critical-patterns.md) | Six must-know patterns from production failures |
| Prerequisites | [agents/prerequisites.md](agents/prerequisites.md) | Required tools, secrets, Go module path convention |
| Operational Guides | [agents/operational-guides.md](agents/operational-guides.md) | Guide index, prior solutions search, prior art pipeline, operational notes |
| v1.0 Roadmap | [docs/roadmap-v1.md](docs/roadmap-v1.md) | Parallel track model (Autonomy, Safety, Adoption), version gates, milestone exit criteria |

## Conventions

**Naming:** All module names are lowercase (`interflux`, `intermute`). Exceptions (proper nouns): Clavain, Interverse, Sylveste, Autarch, Interspect, Intercore, Skaffen, Zaka, Alwe, Ockham. GitHub repos: `github.com/mistakeknot/<name>`. Pillar directories use proper casing (`os/Clavain/`, `apps/Autarch/`). Never create lowercase duplicates — causes triple-loading. See also [CONVENTIONS.md](CONVENTIONS.md) for artifact paths.

**Plugin collisions:** Claude Code autodiscovers all `.claude-plugin/plugin.json` in the monorepo. One canonical owner per command/skill — when extracted from Clavain, remove from Clavain's plugin.json. Extracted plugins own their domain. Delegation facades (namespaced commands like `interkasten:doctor`) are safe.

**Work tracking:** Beads (`bd create/close`) is the single source of truth. Never create TODO files, markdown checklists, or pending-beads lists. See [agents/beads-workflow.md](agents/beads-workflow.md).

**Git workflow:** Owner/agents commit directly to `main` (trunk-based). External contributors: Fork + PR (branch protection enabled). See [docs/guide-contributing.md](docs/guide-contributing.md).

**Philosophy alignment:** When planning, brainstorming, or reviewing changes in any module, read that module's `PHILOSOPHY.md`. Add two short lines to planning outputs: **Alignment** (how it supports the module's purpose) and **Conflict/Risk** (any tension, or 'none'). If a high-value change conflicts, either adjust the plan or create follow-up to update the module's `PHILOSOPHY.md`.

## Recent Changes

**interlab v0.4.2 — Mutation store and provenance tracking.** The `internal/mutation/` package adds a SQLite-backed mutation history store at `~/.local/share/interlab/mutations.db` with three new MCP tools:
- `mutation_record` — Persist an approach attempt with hypothesis, quality signal, and provenance (inspired_by, session_id, campaign_id). Returns `is_new_best` status.
- `mutation_query` — Query mutation history by task_type, campaign, quality threshold. Returns mutations sorted by quality (best first). Use at campaign start to seed hypotheses.
- `mutation_genealogy` — Trace inspired_by provenance chains to visualize idea evolution across sessions and campaigns.

**Agent quality benchmark.** `interverse/interlab/scripts/agent-quality-benchmark.sh` scores agent `.md` files and emits `METRIC agent_quality_score=N.NNNN` lines for use as interlab campaign benchmark commands.

**Plugin quality scanner.** `interverse/interlab/scripts/scan-plugin-quality.sh` scores all Interverse plugins via `plugin-benchmark.sh`, ranks by PQS, and outputs a report. `scripts/generate-campaign-spec.sh` converts scan results into campaign specs consumable by `plan_campaigns` for automated multi-plugin improvement.

**Delta sharing via interlock.** After recording a mutation, `/autoresearch` broadcasts it via interlock's `broadcast_message` (topic: `"mutation"`) so parallel sessions discover and build on each other's approaches. At campaign start, agents check `list_topic_messages` for cross-session mutations alongside `mutation_query`. Broadcasting is best-effort — failure does not block the campaign.

## Session Close Protocol

1. File beads for remaining work (`bd create`)
2. Run quality gates (tests, linters, builds)
3. Close/update beads (`bd close <id>`)
4. **Push** — `git pull --rebase`, run `bd sync` if your local bd build supports it, then `git push`
5. Verify `git status` shows "up to date with origin"

Work is NOT complete until `git push` succeeds. See [agents/session-protocol.md](agents/session-protocol.md) for full details.

<!-- bv-agent-instructions-v1: beads commands and workflow covered in agents/beads-workflow.md -->

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
