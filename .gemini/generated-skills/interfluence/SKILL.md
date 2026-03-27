---
name: interfluence
description: "Analyze your writing style and adapt Claude's output to sound like you. Ingest writing samples, build a voice profile, and apply it to any human-facing documentation or copy."
---
# Gemini Skill: interfluence

You have activated the interfluence capability.

## Base Instructions
# interfluence — Agent Development Guide

## Canonical References
1. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Quick Reference

Voice profile plugin for Claude Code. Analyzes a user's writing corpus and adapts AI-generated documentation/copy to match their style.

- **MCP server:** `server/` (TypeScript, 10 tools — corpus, profile, config, learnings)
- **Skills:** `skills/` — ingest, analyze, apply, refine, compare
- **Build:** `cd server && npm install --cache /tmp/npm-cache && npm run build`
- **Version bump:** `scripts/bump-version.sh <version>` (syncs plugin.json, package.json, marketplace)
- **Plugin entry:** `${CLAUDE_PLUGIN_ROOT}/server/dist/bundle.js`

## Topic Guides

| Topic | File | Covers |
|-------|------|--------|
| Architecture | [agents/architecture.md](agents/architecture.md) | MCP tools, voice resolution, path helpers, skills, agent, hook, command |
| Building | [agents/building.md](agents/building.md) | Build steps, dependencies, version management, MCP bundling |
| Data Layout | [agents/data-layout.md](agents/data-layout.md) | `.interfluence/` structure, voice profile format |
| Design Decisions | [agents/design-decisions.md](agents/design-decisions.md) | Key rationale table (prose profiles, batched learning, manual mode) |
| Roadmap | [agents/roadmap.md](agents/roadmap.md) | MVP (shipped), v0.2.0 code-switching, post-MVP |
| Operational Notes | [agents/operational-notes.md](agents/operational-notes.md) | Ingestion gotchas, marketplace publishing, beads |
| Voice Analyzer | [agents/voice-analyzer.md](agents/voice-analyzer.md) | Opus-powered literary analyst agent |

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


