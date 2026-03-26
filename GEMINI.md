# Gemini Context

Please refer to the following documents for more information:
- [AGENTS.md](./AGENTS.md)
- [CLAUDE.md](./CLAUDE.md)

## Gemini (Antigravity) Specifics

Gemini should expose the same Demarch slash commands as Claude Code and Codex. Project-local commands are generated into `.gemini/commands/`, and the installer also links them into `~/.gemini/commands/` for global use.

Follow these environment-specific deviations:

1. **Slash Commands Are Supported**: Prefer Demarch slash commands when they exist (for example `/clavain:route`, `/interflux:flux-drive`, `/interpath:roadmap`). If a workflow has no slash command entrypoint, run the underlying shell commands directly.
2. **Issue Tracking (Beads)**: Never run the interactive `bv` TUI command, as it blocks the automated terminal. Stick strictly to the `bd` CLI (e.g., `bd ready`, `bd list --status=open`).
3. **Execution Autonomy**: You have the ability to run terminal commands via the `run_command` tool. Proactively build, test, and run validation scripts (e.g., `go test ./...`, `uv run pytest`) without asking for explicit permission.
