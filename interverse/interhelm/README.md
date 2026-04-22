# interhelm

Agent-as-operator runtime diagnostics for the [Interverse](https://github.com/mistakeknot/Sylveste) plugin ecosystem.

## What

Teaches agents to observe and control running applications via diagnostic HTTP servers and CLI tools. Instead of taking screenshots, agents query structured JSON endpoints for runtime state — including UI state.

## Installation

```bash
claude plugins install interhelm
```

## Core Patterns

| Pattern | What It Does |
|---------|-------------|
| **Health** | Structured pass/fail per subsystem |
| **Diff** | Snapshot state, take action, show what changed |
| **Assert** | Scriptable verification expressions |
| **Smoke Test** | End-to-end flow verification (executable contract) |

## UI Observability

The killer feature: `/diag/ui/state` returns semantic JSON describing what's on screen — active view, panel states, selections, form values. Agents verify CUJs without screenshots at near-zero token cost.

## Usage

The skills guide agents to scaffold a diagnostic server and CLI for your project:

1. **`runtime-diagnostics`** — Scaffolds the full diagnostic HTTP server with all patterns
2. **`smoke-test-design`** — Designs executable contracts between server and client
3. **`cuj-verification`** — Validates user journeys via structured state queries
4. **`diagnostic-maturation`** — Evolves a basic diagnostic server into a production-grade operator toolkit and audits existing servers against the maturation ladder

## Templates

- `templates/rust-hyper/` — Rust diagnostic server skeleton (hyper)
- `templates/cli/` — Thin CLI client with formatters, watch mode, REPL

## Architecture

```
interhelm/
├── .claude-plugin/plugin.json   # Plugin manifest (4 skills, 1 agent)
├── skills/
│   ├── runtime-diagnostics/     # Main skill — 4 patterns + UI state
│   ├── smoke-test-design/       # Executable contract pattern
│   ├── cuj-verification/        # Screenshot-free CUJ validation
│   └── diagnostic-maturation/   # Mature and audit diagnostic servers
├── agents/review/
│   └── runtime-reviewer.md      # Operational review agent
├── hooks/
│   ├── hooks.json               # 3 PostToolUse hooks
│   ├── browser-on-native.sh     # Detect screenshot use on native apps
│   ├── auto-health-check.sh     # Health check after Rust changes
│   └── cuj-reminder.sh          # CUJ verification reminder
├── templates/
│   ├── rust-hyper/              # Diagnostic server skeleton
│   └── cli/                     # CLI client skeleton
├── scripts/bump-version.sh
├── tests/structural/            # Plugin structure validation
├── CLAUDE.md, AGENTS.md, PHILOSOPHY.md, LICENSE
└── README.md
```

- **Standalone** — no intercore dependency
- **Framework-agnostic** — works with Tauri, Electron, web apps, CLI tools
- **Pattern plugin** — teaches the pattern, agents generate the implementation

## Design Decisions

See [PHILOSOPHY.md](PHILOSOPHY.md) for design bets and tradeoffs.

## License

MIT
