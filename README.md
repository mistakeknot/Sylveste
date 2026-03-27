# Sylveste

A monorepo for building software with agents, where the review phases matter more than the building phases, and the point is not to remove humans from the loop but to make every moment in the loop count.

Sylveste is the platform behind [Clavain](https://github.com/mistakeknot/Clavain), a self-improving Claude Code agent rig that orchestrates the full development lifecycle from brainstorm to ship. It coordinates Claude, Codex, and GPT-5.2 Pro into something more useful than any of them alone.

## Quick start

Install Clavain and the full companion plugin ecosystem in one command:

```bash
curl -fsSL https://raw.githubusercontent.com/mistakeknot/Sylveste/main/install.sh | bash
```

### Prerequisites

**Required:** [jq](https://jqlang.github.io/jq/), [Go 1.22+](https://go.dev/dl/), git

**Why Go?** The intercore kernel (`ic`) and `clavain-cli` are Go binaries built from source during installation. Go 1.22+ is the minimum; 1.24+ is recommended.

**Recommended:** Python 3.10+ with PyYAML, [Node.js 20+](https://nodejs.org/), [yq v4](https://github.com/mikefarah/yq)

Install takes ~2 minutes (power user) or ~30 minutes (full platform). Disk: ~2 GB core, ~5 GB with all plugins.

### Managing your installation

```bash
bash install.sh --update      # Update to latest (skip first-time setup)
bash install.sh --uninstall   # Remove all Demarch components
bash install.sh --dry-run     # Preview what would happen
```

Then open Claude Code in your project and run:

```
/clavain:project-onboard
```

This sets up beads tracking, CLAUDE.md/AGENTS.md, docs structure, observability, and seeds your first roadmap. After that, use `/clavain:route` to start building.

## What you get

- **Clavain**: the agent rig (brainstorm → strategy → plan → execute → review → ship)
- **55+ companion plugins**: multi-agent code review, phase tracking, doc freshness, semantic search, TUI testing (43 installed by default, 14 optional)
- **Multi-model orchestration**: Claude does the heavy lifting, Codex runs parallel tasks, GPT-5.2 Pro provides a second opinion via Oracle
- **Sprint management**: track work with Beads, auto-discover what to work on next

## Guides

| Guide | Who it's for | Time |
|-------|-------------|------|
| [Power User Guide](docs/guide-power-user.md) | Claude Code users adding Clavain to their workflow | 10 min read |
| [Full Setup Guide](docs/guide-full-setup.md) | Users who want the complete platform (Go services, TUI tools) | 30 min setup |
| [Contributing Guide](docs/guide-contributing.md) | Developers who want to modify or extend Demarch | 45 min setup |

## How it works

Most agent tools skip the product phases (brainstorm, strategy, specification) and jump straight to code generation. The thinking phases are where the real leverage is. Clavain makes them first-class:

1. **Discover**: scan backlog, surface ready work, recommend next task
2. **Brainstorm**: collaborative dialogue to explore the problem space
3. **Strategize**: structure ideas into a PRD with trackable features
4. **Plan**: write bite-sized implementation tasks with TDD
5. **Execute**: dispatch agents (Claude subagents or Codex) to implement
6. **Review**: multi-agent quality gates catch issues before shipping
7. **Ship**: land the change with verification and session reflection

## Philosophy

Three principles, applied recursively: every action produces evidence, evidence earns authority, and authority is scoped and composed. The cycle compounds — more autonomy produces more data, more data improves routing, better routing cuts cost, lower cost enables more autonomy.

See [PHILOSOPHY.md](PHILOSOPHY.md) for the full design bets, tradeoffs, and convictions.

## Architecture

Demarch is a monorepo with 5 pillars:

| Pillar | Layer | Description |
|--------|-------|-------------|
| [Intercore](https://github.com/mistakeknot/intercore) | L1 (Core) | Orchestration kernel: runs, dispatches, gates, events |
| [Clavain](https://github.com/mistakeknot/Clavain) | L2 (OS) | Self-improving agent rig |
| [Interverse](https://github.com/mistakeknot/interagency-marketplace) | L2-L3 | 51 companion plugins |
| [Autarch](https://github.com/mistakeknot/Autarch) | L3 (Apps) | TUI interfaces (Bigend, Gurgeh, Coldwine, Pollard) |
| [Interspect](interverse/interspect/) | L2 | Agent performance profiler and routing optimizer |

Additional infrastructure: [Intermute](https://github.com/mistakeknot/intermute) (multi-agent coordination), [interbase](https://github.com/mistakeknot/interbase) (SDK), [interbench](https://github.com/mistakeknot/interbench), [interband](https://github.com/mistakeknot/interband).

### Plugin ecosystem

[Interactive ecosystem diagram](https://mistakeknot.github.io/interchart/): explore how all plugins, skills, agents, and services connect.

All plugins are installed from the [interagency-marketplace](https://github.com/mistakeknot/interagency-marketplace).

### Naming convention

All module names are **lowercase** except **Clavain** (proper noun), **Demarch** (project name), **Interverse** (ecosystem name), and **Autarch** (proper noun).

## Troubleshooting

| Problem | Symptom | Fix |
|---------|---------|-----|
| jq missing | `install.sh` exits immediately | `sudo apt install jq` or `brew install jq` |
| Go too old | Version check fails during install | Install Go 1.22+ from [go.dev](https://go.dev/dl/) |
| `ic` not found | Commands fail after install | Add `export PATH="$HOME/.local/bin:$PATH"` to your shell profile |
| ic build fails | Install exits with Go error | Check `go env GOPATH` and network access |
| Plugins missing | `/clavain:setup` shows gaps | Re-run `install.sh` with Claude Code running |
| `bd` hangs | Beads commands never return | Run `bash .beads/recover.sh` |

Run `/clavain:doctor` for a full health check.

## License

MIT
