---
name: interrank
description: "Snapshot-backed model/benchmark ranking MCP server for AgMoDB"
---
# Gemini Skill: interrank

You have activated the interrank capability.

## Base Instructions
# interrank — Agent Guide

Follow Demarch root `AGENTS.md` for global policy. This file defines local module workflow.

## Scope

`interrank` is a read-only MCP plugin that queries AgMoDB snapshot data. It should never query Neon directly.

## Local Commands

```bash
pnpm install
pnpm build
pnpm test
pnpm mcp
```

## Rules

- Keep tool output JSON-only on stdout; write logs to stderr.
- Preserve snapshot compatibility with AgMoDB release assets.
- Treat unknown metric/benchmark keys as explicit tool errors.


