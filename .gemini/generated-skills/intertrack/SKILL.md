---
name: intertrack
description: "Feature-level success metric tracking for Sylveste"
---
# Gemini Skill: intertrack

You have activated the intertrack capability.

## Base Instructions
# intertrack — Development Guide

## Philosophy Alignment

intertrack follows Sylveste's "receipts over narratives" principle: metric observations are durable, timestamped records of feature behavior. The plugin measures only — routing decisions and policy changes are downstream concerns for interspect and clavain.

## Architecture

- **Hooks + skills only** — no MCP server (same pattern as interstat)
- **SQLite at `~/.claude/intertrack/metrics.db`** — WAL mode, busy_timeout=5000
- **Shell scripts as public API** — `track-record.sh` (write), `track-query.sh` (read)
- **YAML-defined metrics** — `config/metrics.yaml` seeded into DB via `seed-metrics.sh`

## Execution Rules

- Small, testable, reversible changes
- Run `bash scripts/init-db.sh` after schema changes
- Test with `bash scripts/track-record.sh <metric> <value>` then `bash scripts/track-query.sh metric <name>`
- Never break caller hooks — `track-record.sh` always exits 0


