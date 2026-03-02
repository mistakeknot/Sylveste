---
name: interflux
description: "Multi-agent review and research with scored triage, domain detection, content slicing, intermediate finding sharing, and knowledge injection. 17 agents (12 review + 5 research), 4 commands, 1 skill (unified flux-drive with review/research modes), 1 MCP server. Companion plugin for Clavain."
---
# Gemini Skill: interflux

You have activated the interflux capability.

## Base Instructions
# interflux — Development Guide

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
- **Alignment:** one sentence on how the proposal supports the module's purpose within Demarch's philosophy.
- **Conflict/Risk:** one sentence on any tension with philosophy (or 'none').

If a high-value change conflicts with philosophy, either:
- adjust the plan to align, or
- create follow-up work to update `PHILOSOPHY.md` explicitly.


Multi-agent review and research engine for Claude Code. Companion plugin for [Clavain](https://github.com/mistakeknot/Clavain).

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/interflux` |
| Namespace | `interflux:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 17 agents (12 review + 5 research), 4 commands, 2 skills, 2 MCP servers, 1 hook |
| License | MIT |

### Release workflow

- Run `scripts/bump-version.sh <version>` (or `/interpub:release <version>` in Claude Code) for any released changes.
- It updates `.claude-plugin/plugin.json`, `infra/marketplace/.claude-plugin/marketplace.json`, and discovered versioned artifacts.
- The command commits and pushes both plugin and marketplace repos atomically.
- Use patch bumps for routine user-facing updates (`0.2.x -> 0.2.x+1`).

## Architecture

```
interflux/
├── agents/review/       # 8 fd-* review agents (7 technical + fd-systems cognitive)
├── agents/research/     # 5 research agents (best-practices, framework-docs, git-history, learnings, repo-research)
├── commands/            # 3 commands: flux-drive, flux-gen, flux-research
├── skills/flux-drive/   # Review orchestration (triage, launch phases, synthesis) + references/
├── skills/flux-research/# Research orchestration
├── config/flux-drive/domains/  # 11 domain detection profiles + index.yaml
├── docs/spec/           # flux-drive protocol spec v1.0.0 (9 documents)
├── hooks/               # SessionStart (interbase-aware)
├── scripts/             # content-hash, generate-agents, validate-roster
└── tests/structural/    # 120 pytest tests
```

## How It Works

### flux-drive (Review Orchestration)

Three-phase protocol: **Triage** → **Launch** → **Synthesize**.

1. **Triage** — Detect project domains, profile input, score agents (base_score 0-3 + domain_boost 0-2 + project_bonus 0-1 + domain_agent 0-1), present roster for user approval
2. **Launch** — Dispatch Stage 1 agents in parallel, monitor completion, optionally expand to Stage 2 based on findings severity + adjacency scoring
3. **Synthesize** — Validate outputs, deduplicate findings, track convergence, compute verdict (safe/needs-changes/risky), generate findings.json + summary.md

See `docs/spec/README.md` for the full protocol specification.

### flux-research (Research Orchestration)

Three-phase protocol: **Triage** → **Launch** → **Synthesize**.

Uses a query-type affinity table to select research agents, dispatches in parallel, and synthesizes answers with source attribution. Progressive enhancement: uses Exa MCP for external research when available, falls back to Context7 + WebSearch.

### Domain Detection

LLM-based classification — a Haiku subagent reads README + build files + key source files and classifies the project into 11 known domains. Cached in `.claude/intersense.yaml` with `content_hash` for staleness detection. Staleness computed deterministically by `scripts/content-hash.py`. Domain detection scripts delegate to the intersense plugin (canonical location).

11 domains defined in intersense `config/domains/` (with local fallback at `config/flux-drive/domains/`). Each domain profile contains review criteria, agent specs, and Research Directives for external research agents.

### Agent Generation

`scripts/generate-agents.py` reads cached domain classification + domain profile markdown → writes `.claude/agents/fd-*.md` files. Deterministic template expansion (no LLM involvement). Three modes: `skip-existing`, `regenerate-stale` (checks `flux_gen_version` in frontmatter), `force`.

### Knowledge Lifecycle

Durable patterns from past reviews, managed by the **interknow** plugin:
- **Provenance tracking** — `independent` (re-discovered without prompting) vs `primed` (re-confirmed while in context)
- **Temporal decay** — entries not independently confirmed in 10 reviews are archived
- **Injection** — top 5 relevant entries injected into agent prompts via semantic search (qmd, served by interknow)
- **Compounding** — new patterns extracted from review findings and saved via interknow

## Intermediate Finding Sharing

During parallel flux-drive reviews, agents can share high-severity findings via `{OUTPUT_DIR}/peer-findings.jsonl`.

**Severity levels:**
- `blocking` — contradicts another agent's analysis (MUST acknowledge)
- `notable` — significant finding that may affect others (SHOULD consider)

**Helper script:** `scripts/findings-helper.sh`
- `write <file> <severity> <agent> <category> <summary> [file_refs...]`
- `read <file> [--severity blocking|notable|all]`

**Timeline in synthesis:** The synthesis agent reads the findings timeline for convergence tracking and contradiction detection.

**Command:** `/interflux:fetch-findings <output_dir> [--severity ...]` — inspect shared findings.

## MCP Servers

| Server | Type | Purpose |
|--------|------|---------|
| **exa** | stdio | External web research via Exa API. Progressive enhancement — requires `EXA_API_KEY`. Falls back to Context7 + WebSearch if unavailable. |

**Note:** qmd MCP server (semantic search for knowledge) has moved to the **interknow** plugin.

## Protocol Specification

The flux-drive review protocol is formally specified in `docs/spec/` (flux-drive-spec 1.0.0). The spec extracts the abstract protocol from this reference implementation into standalone, framework-agnostic documents.

Three conformance levels:
- **Core** — 3-phase lifecycle, base scoring (0-4), staging, contracts, synthesis
- **Core + Domains** — adds domain detection, domain_boost/domain_agent_bonus scoring (0-7)
- **Core + Knowledge** — adds provenance-tracked review memory with temporal decay

See `docs/spec/README.md` for the full document index and reading order.

## Component Conventions

### Review Agents (fd-*)

- 8 agents: 7 technical (auto-detect language) + 1 cognitive (fd-systems, documents only)
- YAML frontmatter: `name`, `description` (with `<example>` blocks), `model: sonnet`
- Each reads project CLAUDE.md/AGENTS.md for codebase-aware review
- Findings output uses the Findings Index contract: `SEVERITY | ID | "Section" | Title`
- Verdict: `safe | needs-changes | risky`
- **Cognitive agents** (fd-systems) are pre-filtered: only activate for `.md`/`.txt` document reviews (PRDs, brainstorms, plans, strategy docs), never for code or diffs. Use cognitive severity mapping: Blind Spot → P1, Missed Lens → P2, Consider Also → P3

### Research Agents

- 5 agents for different research tasks (best practices, framework docs, git history, learnings, repo analysis)
- Orchestrated by flux-research skill, not invoked directly
- Research Directives in domain profiles guide their search terms

### Commands

| Command | Description |
|---------|-------------|
| `/interflux:flux-drive` | Multi-agent document/code review |
| `/interflux:flux-research` | Multi-agent research with source attribution |
| `/interflux:flux-gen` | Generate project-specific review agents from detected domains |
| `/interflux:fetch-findings` | Inspect shared findings from parallel reviews |

## Testing

```bash
# Run all structural tests (103 tests)
cd /root/projects/Interverse/plugins/interflux && uv run pytest tests/ -q

# Key test suites
uv run pytest tests/structural/test_namespace.py -v  # Guards against stale clavain: refs
uv run pytest tests/structural/test_agents.py -v     # Agent structure validation
uv run pytest tests/structural/test_skills.py -v     # Skill structure validation
uv run pytest tests/structural/test_slicing.py -v    # Content routing tests
```

## Validation Checklist

```bash
# Count components
ls agents/review/*.md | wc -l         # Should be 8
ls agents/research/*.md | wc -l       # Should be 5
ls commands/*.md | wc -l              # Should be 3
ls skills/*/SKILL.md | wc -l          # Should be 2

# Domain profiles
grep -l '## Research Directives' config/flux-drive/domains/*.md | wc -l  # Should be 11

# Manifest
python3 -c "import json; d=json.load(open('.claude-plugin/plugin.json')); print(list(d['mcpServers'].keys()))"  # ['exa']

# Namespace check — no stale clavain: references
uv run pytest tests/structural/test_namespace.py -v
```

## Measurement Definitions

Standard definitions for token metrics used across interflux and companion plugins.

### Token Types
| Type | Field | Description |
|------|-------|-------------|
| Input | `input_tokens` | Tokens sent to the model (prompt + system + tool results) |
| Output | `output_tokens` | Tokens generated by the model |
| Cache Read | `cache_read_tokens` | Previously cached input tokens reused (free for billing) |
| Cache Creation | `cache_creation_tokens` | New tokens added to cache this turn |
| Total | `total_tokens` | All tokens (input + output + cache_read + cache_creation) |

### Cost Types
| Type | Formula | Use For |
|------|---------|---------|
| Billing tokens | `input_tokens + output_tokens` | Cost estimation, budget enforcement |
| Effective context | `input_tokens + cache_read_tokens + cache_creation_tokens` | Context window decisions |

**Critical:** Billing tokens and effective context can differ by 600x+ due to cache hits being free for billing but consuming context. Budget caps use billing tokens (what costs money). Context overflow checks use effective context (what fits in the window).

### Scopes
| Scope | Granularity | Source |
|-------|-------------|--------|
| Per-agent | Single Task dispatch | interstat `agent_runs` table |
| Per-invocation | All agents in one flux-drive run | interstat `v_invocation_summary` |
| Per-session | All tokens in a Claude Code session | Session JSONL |
| Per-sprint | All sessions in a Clavain sprint | Future: interbudget |

### Budget Configuration
See `config/flux-drive/budget.yaml` for token budgets per review type, per-agent defaults, slicing multipliers, and enforcement mode.

## Dual-Mode Architecture

interflux supports both standalone (Claude Code marketplace) and integrated (Interverse ecosystem) operation via the interbase SDK.

### Files
- `hooks/interbase-stub.sh` — sources live SDK or falls back to inline no-ops
- `hooks/session-start.sh` — sources stub, emits ecosystem status
- `hooks/hooks.json` — registers SessionStart hook
- `.claude-plugin/integration.json` — declares standalone/integrated feature surface

### How It Works
- **Standalone**: User installs interflux from marketplace. Stub falls back to no-ops. All review/research features work. No ecosystem features (phase tracking, nudges, sprint gates).
- **Integrated**: User has `~/.intermod/interbase/interbase.sh` installed. Stub sources the live SDK. Session-start hook reports `[interverse] beads=... | ic=...`. Nudge protocol suggests missing companions.

### Testing
```bash
# Standalone (no ecosystem)
INTERMOD_LIB=/nonexistent bash hooks/session-start.sh 2>&1
# Expected: no output

# Integrated (with ecosystem)
bash hooks/session-start.sh 2>&1
# Expected: [interverse] beads=active | ic=...
```

## Known Constraints

- **No build step** — pure markdown/JSON/Python/bash plugin
- **Phase tracking is caller's responsibility** — interflux commands do not source lib-gates.sh; Clavain's lfg pipeline handles phase transitions
- **Exa requires API key** — set `EXA_API_KEY` env var; agents degrade gracefully without it
- **qmd must be installed** — semantic search used for knowledge injection; if unavailable, reviews run without knowledge context


