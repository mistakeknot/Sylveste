---
name: intername
description: "Agent and agency naming for legible orchestration — memorable, deterministic identities across all surfaces."
---
# Gemini Skill: intername

You have activated the intername capability.

## Base Instructions
# intername — Development Guide

## Canonical References
1. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Philosophy Alignment Protocol
Review [`PHILOSOPHY.md`](../../PHILOSOPHY.md) during:
- Intake/scoping
- Brainstorming
- Planning
- Execution kickoff
- Review/gates
- Handoff/retrospective

For brainstorming/planning outputs, add two short lines:
- **Alignment:** one sentence on how the proposal supports the module's purpose within Sylveste's philosophy.
- **Conflict/Risk:** one sentence on any tension with philosophy (or 'none').

If a high-value change conflicts with philosophy, either:
- adjust the plan to align, or
- create follow-up work to update `PHILOSOPHY.md` explicitly.


Agent and agency naming for legible orchestration. Companion plugin for [Clavain](https://github.com/mistakeknot/Clavain).

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/intername` |
| Namespace | `intername:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 2 commands, 1 library, 4 themes, 0 hooks, 0 MCP servers |
| License | MIT |

### Release workflow

```bash
ic publish --patch   # or: ic publish <version>
```

## Architecture

```
intername/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── hooks/
│   └── lib-naming.sh            # Name resolution library (sourced, not executed)
├── data/
│   ├── config.json              # Active theme + custom override toggle
│   └── themes/
│       ├── culture.json         # Banks-style names (default)
│       ├── demarch.json         # Boundary/diplomatic names
│       ├── nato.json            # NATO phonetic names
│       └── custom.json          # User overrides
├── commands/
│   ├── name.md                  # Look up / list names
│   └── name-theme.md            # Switch theme packs
└── tests/
    └── test_naming.sh           # 16 tests
```

### Theme file schema

```json
{
  "_meta": {
    "name": "Theme Name",
    "description": "One-line description",
    "author": "author"
  },
  "agencies": {
    "agency-type": "Display Name"
  },
  "agents": {
    "agent-type": "Display Name"
  }
}
```

### Library API

```bash
source "$INTERNAME_PLUGIN/hooks/lib-naming.sh"

# Core resolution
_name_resolve "fd-safety"              # → "Lapsed Pacifist" (or "fd-safety" if disabled)
_name_resolve_agency "flux-drive"      # → "The Difficult Second Album"

# Dispatch formatting
_name_dispatch "fd-safety" 2 5         # → "Lapsed Pacifist (2/5)"
_name_dispatch "fd-safety"             # → "Lapsed Pacifist"

# Listing
_name_list                             # → agent_type\tdisplay_name (TSV)
_name_list_agencies                    # → agency_type\tdisplay_name (TSV)

# Configuration
_name_enabled                          # → 0 (enabled) or 1 (disabled)
_name_active_theme                     # → "culture"
```

### Resolution order

1. If `INTERNAME_DISABLED=1` → return raw ID
2. If `jq` not available → return raw ID
3. Check `custom.json` (if `customOverrides: true`) → return if found
4. Check active theme file → return if found
5. Return raw ID as fallback

### Consumer discovery

```bash
INTERNAME_PLUGIN=$(find ~/.claude/plugins/cache -path "*/intername/*/hooks/lib-naming.sh" 2>/dev/null | head -1)
if [[ -n "$INTERNAME_PLUGIN" ]]; then
    source "$INTERNAME_PLUGIN"
fi
```

### Planned consumer integration points

| Consumer | What it shows | Status |
|----------|--------------|--------|
| intermux | tmux pane titles | Planned |
| interflux | dispatch logs, verdict attribution | Planned |
| interspect | evidence table, pattern reports | Planned |
| intertrust | trust score reports | Planned |
| autarch | TUI dashboard agent panels | Planned |
| interline | statusline agent display | Planned |

All integrations are opt-in: if intername is not installed, consumers fall back to raw IDs.

## Testing

```bash
bash tests/test_naming.sh
```

16 tests covering: theme loading, agent/agency resolution, unknown ID fallback, dispatch formatting, disable/enable toggle, list functions, name uniqueness.

## Adding a new theme

1. Create `data/themes/<name>.json` following the schema above
2. Ensure every agent in `culture.json` has an entry (for consistency)
3. Run tests: `bash tests/test_naming.sh`
4. Update README.md with a description and sample output

## Adding names for new agents

When a new agent type is registered (e.g., via flux-gen), add an entry to each theme file. If a theme has no entry for an agent, the raw ID is returned — this is safe but less legible.

## Design decisions

- **Deterministic, not hash-based** — same agent always gets same name regardless of project
- **Project as context, not identity** — show "Lapsed Pacifist @ Sylveste", don't encode project into name
- **Dispatches inherit** — "Lapsed Pacifist (2/5)" not a fresh name per dispatch
- **jq dependency** — acceptable since jq is available on all target platforms; graceful fallback if missing
- **No hooks** — purely a library + commands plugin; consumers source the library on demand
- **Separate from intership** — intership is cosmetic (spinner verbs); intername is infrastructure (persistent identity)


