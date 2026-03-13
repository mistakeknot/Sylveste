---
artifact_type: cuj
journey: plugin-discovery-install
actor: new user (developer discovering and installing Interverse plugins)
criticality: p2
bead: Demarch-2c7
---

# Plugin Discovery and Installation

## Why This Journey Matters

The Interverse is Demarch's plugin ecosystem — 50+ plugins that extend the platform with review agents, coordination tools, knowledge systems, analytics, and more. But an ecosystem is only as good as its discovery experience. A developer who can't find the right plugin, or who installs one and can't figure out how to use it, gets no value from the entire ecosystem.

The plugin lifecycle — discover, install, configure, use — must be seamless enough that installing a new capability feels like flipping a switch, not reading a manual. Each plugin is independently installable, has its own CLAUDE.md with instructions, and registers its commands/skills/hooks automatically.

## The Journey

A developer using Clavain wants code review capabilities. They've heard about Interflux but aren't sure what else is available. They browse the marketplace: `claude plugin list` (or the equivalent marketplace UI) shows available plugins categorized by function — review, coordination, analytics, knowledge, development.

They install Interflux: `claude install interflux`. The plugin registers its MCP server, skills (`/flux-drive`, `/flux-gen`), and agents (fd-architecture, fd-safety, fd-correctness, etc.). The developer restarts their Claude Code session to load the plugin.

First use: `/flux-drive docs/plans/my-plan.md`. Interflux triages which review agents are relevant, dispatches them in parallel, synthesizes findings, and presents a verdict. The developer didn't need to configure anything — sensible defaults work out of the box.

For plugins that need configuration (Interkasten for Notion, Intercom for Telegram), the first-use experience guides the developer: "Notion token not configured. To set up, create an integration at..." The plugin degrades gracefully without the config — it works locally, just without the external sync.

Over time, the developer installs more plugins. Each adds capabilities without conflicting with others. The developer's skill list grows: `/help` shows all available commands from all installed plugins. Interspect tracks which plugin agents perform well and which don't.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Plugin install completes in under 30 seconds | measurable | Time from `claude install` to ready ≤ 30s |
| Installed plugin's commands appear in `/help` | measurable | Skill list includes new plugin's commands |
| First use works without configuration for core features | measurable | Plugin works with default config |
| Missing optional config produces a helpful message, not a crash | measurable | Graceful degradation with setup instructions |
| Multiple plugins coexist without conflicts | measurable | Installing plugin B doesn't break plugin A |
| Plugin can be uninstalled cleanly | measurable | `claude uninstall` removes all plugin artifacts |
| Developer finds relevant plugin within 2 minutes of searching | qualitative | Marketplace categories and descriptions are useful |

## Known Friction Points

- **Session restart required** — plugins don't hot-load. Developer must restart Claude Code after install.
- **No dependency management** — plugins don't declare dependencies on other plugins. Installing interflux doesn't auto-install interspect.
- **Marketplace discovery is basic** — no ratings, no usage stats, no "recommended for your project" suggestions.
- **MCP server startup overhead** — each plugin with an MCP server adds startup latency. 10+ plugins can make session start slow.
- **Plugin versioning is manual** — `claude install` gets the latest. No pinning, no rollback, no lock file.
