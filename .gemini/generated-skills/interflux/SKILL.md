---
name: interflux
description: "Multi-agent review and research with scored triage, domain detection, content slicing, intermediate finding sharing, and knowledge injection. 17 agents (12 review + 5 research), 4 commands, 1 skill (unified flux-drive with review/research modes), 1 MCP server. Companion plugin for Clavain."
---
# Gemini Skill: interflux

You have activated the interflux capability.

## Base Instructions
# interflux — Development Guide

Multi-agent review and research engine for Claude Code. Companion plugin for [Clavain](https://github.com/mistakeknot/Clavain).

## Canonical References
1. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/interflux` |
| Version | See `.claude-plugin/plugin.json` (currently 0.2.x) |
| Namespace | `interflux:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 17 agents (12 review + 5 research), 4 commands, 1 skill (unified flux-drive), 1 MCP server (exa), 2 hooks |
| Spec | flux-drive-spec 1.0.0 — 8 documents in `docs/spec/` |
| License | MIT |

### Release Workflow

- Run `scripts/bump-version.sh <version>` (or `/interpub:release <version>` in Claude Code) for any released changes.
- It updates `.claude-plugin/plugin.json`, `infra/marketplace/.claude-plugin/marketplace.json`, and discovered versioned artifacts.
- The command commits and pushes both plugin and marketplace repos atomically.
- Use patch bumps for routine user-facing updates (`0.2.x -> 0.2.x+1`).

## Topic Guides

| Topic | File | Covers |
|-------|------|--------|
| Architecture | [agents/architecture.md](agents/architecture.md) | Directory layout, flux-drive/flux-research orchestration, domain detection, agent generation, knowledge lifecycle |
| Components | [agents/components.md](agents/components.md) | Review agents (fd-*), research agents, commands, MCP servers, protocol specification |
| Finding Sharing | [agents/finding-sharing.md](agents/finding-sharing.md) | Peer-findings JSONL, severity levels, helper script, synthesis |
| Testing | [agents/testing.md](agents/testing.md) | Structural test suites, validation checklist |
| Measurement | [agents/measurement.md](agents/measurement.md) | Token types, cost types, scopes, budget configuration |
| Dual-Mode | [agents/dual-mode.md](agents/dual-mode.md) | Standalone vs integrated operation, interbase SDK, known constraints |

---

## Architecture

```
interflux/
├── agents/
│   ├── review/              # 12 fd-* review agents (7 technical + 5 cognitive)
│   │   ├── references/      # Supplemental material (concurrency-patterns.md)
│   │   ├── fd-architecture.md
│   │   ├── fd-correctness.md
│   │   ├── fd-game-design.md
│   │   ├── fd-performance.md
│   │   ├── fd-quality.md
│   │   ├── fd-safety.md
│   │   ├── fd-user-product.md
│   │   ├── fd-systems.md       # cognitive
│   │   ├── fd-decisions.md     # cognitive
│   │   ├── fd-people.md        # cognitive
│   │   ├── fd-resilience.md    # cognitive
│   │   └── fd-perception.md    # cognitive
│   ├── research/            # 5 research agents
│   │   ├── best-practices-researcher.md
│   │   ├── framework-docs-researcher.md
│   │   ├── git-history-analyzer.md
│   │   ├── learnings-researcher.md
│   │   └── repo-research-analyst.md
│   ├── architecture.md      # Topic guide
│   ├── components.md         # Topic guide
│   ├── dual-mode.md          # Topic guide
│   ├── finding-sharing.md    # Topic guide
│   ├── measurement.md        # Topic guide
│   └── testing.md            # Topic guide
├── commands/
│   ├── flux-drive.md         # Multi-agent review
│   ├── flux-research.md      # Multi-agent research (routes to flux-drive mode=research)
│   ├── flux-gen.md           # Generate project-specific agents from domains or prompts
│   └── fetch-findings.md     # Inspect shared findings from parallel reviews
├── config/flux-drive/
│   ├── domains/              # 11 domain profiles + index.yaml
│   ├── knowledge/            # Knowledge entries (managed by interknow)
│   ├── agent-roles.yaml      # Model tier per agent role (planner/reviewer/editor/checker)
│   └── budget.yaml           # Token budgets by input type, per-agent defaults, dropout
├── docs/
│   ├── spec/                 # flux-drive protocol spec v1.0.0 (8 documents)
│   ├── brainstorms/
│   ├── plans/
│   ├── prds/
│   └── research/
├── hooks/
│   ├── hooks.json            # Registers SessionStart hooks
│   ├── session-start.sh      # Ecosystem status (interbase-aware)
│   ├── write-capabilities.sh # Writes plugin capabilities
│   ├── interbase-stub.sh     # Sources live SDK or falls back to inline no-ops
│   └── python-hook-example.py
├── scripts/
│   ├── bump-version.sh       # Version bump + commit + push
│   ├── estimate-costs.sh     # Per-agent cost estimation (interstat + budget.yaml fallback)
│   ├── findings-helper.sh    # Write/read peer findings JSONL
│   ├── generate-agents.py    # LLM specs → .claude/agents/fd-*.md
│   ├── launch-exa.sh         # Exa MCP server launcher
│   ├── launch-qmd.sh         # qmd launcher (vestigial — moved to interknow)
│   ├── update-domain-profiles.py  # Refresh domain profile markdown from index
│   ├── validate-gitleaks-waivers.sh
│   └── validate-roster.sh    # Validate agent roster integrity
├── skills/
│   ├── flux-drive/           # Primary skill (review + research modes)
│   │   ├── SKILL.md          # Full orchestration protocol (30K)
│   │   ├── SKILL-compact.md  # Compact variant (15K)
│   │   ├── phases/           # launch.md, synthesize.md, slicing.md, shared-contracts.md, cross-ai.md, launch-codex.md
│   │   └── references/       # agent-roster.md, scoring-examples.md
│   └── flux-research/        # DEPRECATED — merged into flux-drive mode=research
│       ├── SKILL.md
│       └── SKILL-compact.md
├── tests/
│   ├── structural/           # pytest suite (agents, commands, skills, namespace, slicing, generate-agents)
│   ├── test-budget.sh        # Budget estimation tests
│   ├── test-findings-flow.sh # Findings JSONL flow tests
│   └── test_estimate_costs.bats
├── .claude-plugin/plugin.json
├── AGENTS.md
├── CLAUDE.md
├── PHILOSOPHY.md
└── README.md
```

## Review Agents (12)

### Technical Agents (7)

Auto-detect language from code under review. Each reads project CLAUDE.md/AGENTS.md for codebase-aware analysis. YAML frontmatter: `name`, `description` (with `<example>` blocks), `model: sonnet`.

| Agent | Domain | Role |
|-------|--------|------|
| fd-architecture | Module boundaries, coupling, design patterns, anti-patterns, complexity | planner (opus tier) |
| fd-safety | Threats, credentials, trust boundaries, deploy risk, rollback | reviewer (sonnet, safety floor) |
| fd-correctness | Data consistency, race conditions, transactions, async bugs | reviewer (sonnet, safety floor) |
| fd-quality | Naming, conventions, test approach, language-specific idioms | reviewer (sonnet) |
| fd-user-product | User flows, UX friction, value prop, scope, missing edge cases | editor (sonnet) |
| fd-performance | Bottlenecks, resource usage, algorithmic complexity, scaling | editor (sonnet) |
| fd-game-design | Balance, pacing, player psychology, feedback loops, emergent behavior | editor (sonnet) |

### Cognitive Agents (5)

Review documents only (plans, PRDs, strategies, brainstorms). Pre-filtered by SKILL.md Step 1.2a: only activate for `.md`/`.txt` inputs of document types. Never included for code or diff reviews. Use cognitive severity mapping: Blind Spot -> P1, Missed Lens -> P2, Consider Also -> P3.

| Agent | Domain | Role |
|-------|--------|------|
| fd-systems | Feedback loops, emergence, causal reasoning, systems dynamics | planner (opus tier) |
| fd-decisions | Decision quality, framing effects, option coverage, reversibility | checker (haiku) |
| fd-people | Human systems, incentive alignment, organizational dynamics | checker (haiku) |
| fd-resilience | Adaptive capacity, failure modes, graceful degradation | checker (haiku) |
| fd-perception | Sensemaking, context sensitivity, signal/noise, cognitive bias | checker (haiku) |

### Agent Output Contract

- **Findings Index**: `SEVERITY | ID | "Section" | Title`
- **Verdict**: `safe | needs-changes | risky`
- **Completion signal**: `.partial` sentinel -> rename to final

### Model Routing

Agents get models resolved at launch time from Clavain's `config/routing.yaml` via `routing_resolve_agents()`. Resolution chain: agent override > phase+category > phase > default category > default model. Safety floors: fd-safety and fd-correctness never run below sonnet (enforced by `lib-routing.sh`).

The `model:` line in agent frontmatter serves as a fallback when routing.yaml is unavailable.

Role-to-tier mapping is in `config/flux-drive/agent-roles.yaml`.

## Research Agents (5)

Orchestrated by flux-drive in `mode=research`. Not invoked directly. Research Directives in domain profiles guide their search terms. All use `model: haiku`.

| Agent | Focus |
|-------|-------|
| best-practices-researcher | Industry standards, community conventions, implementation guidance |
| framework-docs-researcher | Official documentation, framework APIs, configuration reference |
| git-history-analyzer | Commit history patterns, file change frequency, authorship |
| learnings-researcher | Project learnings, past review findings, knowledge entries |
| repo-research-analyst | Codebase structure, module relationships, dependency analysis |

Selection uses a query-type affinity table (onboarding, how-to, why-is-it, what-changed, best-practice, debug-context, exploratory). Agents scoring >= 2 are dispatched. Domain bonus (+1) for agents with Research Directives in detected domain.

## Commands (4)

| Command | Description |
|---------|-------------|
| `/interflux:flux-drive` | Multi-agent document/code review (default mode=review) |
| `/interflux:flux-research` | Multi-agent research — routes to flux-drive with mode=research |
| `/interflux:flux-gen` | Generate project-specific review agents from detected domains or free-form prompts |
| `/interflux:fetch-findings` | Inspect shared findings from parallel reviews |

### flux-gen Modes

- **Domain mode** (default): Deterministic template expansion from domain profiles. 11 known domains.
- **Prompt mode**: LLM (Sonnet subagent) designs 3-5 task-specific agents, then deterministic rendering.
- **Specs mode** (`--from-specs <path>`): Regenerate from saved specs without re-running LLM design.

Generated agents are written to `.claude/agents/fd-*.md` and get +1 category bonus in triage scoring.

## Skill: flux-drive

Single unified skill registered in plugin.json. Two modes selected by invocation:

- `/interflux:flux-drive` -> `MODE = review`
- `/interflux:flux-research` -> `MODE = research`

### Three-Phase Protocol

1. **Triage** — Detect project domains, profile input, score agents (base_score 0-3 + domain_boost 0-2 + project_bonus 0-1 + domain_agent 0-1 = max 7), present roster for user approval. Dynamic slot ceiling (4-10 agents). Budget-aware selection via `scripts/estimate-costs.sh`. Document slicing for inputs > 200 lines.
2. **Launch** — Dispatch Stage 1 agents in parallel, monitor completion, optionally expand to Stage 2 based on findings severity + adjacency scoring. Incremental expansion launches speculative Stage 2 agents as Stage 1 results arrive. AgentDropout prunes redundant agents (threshold 0.6). Safety-critical agents (fd-safety, fd-correctness) exempt from budget cuts and dropout.
3. **Synthesize** — Validate outputs, deduplicate findings, track convergence, compute verdict (safe/needs-changes/risky), generate findings.json + summary.md. Research mode delegates to `intersynth:synthesize-research`.

Phase files in `skills/flux-drive/phases/`:

| File | Content |
|------|---------|
| `shared-contracts.md` | Output format, completion signals, content routing |
| `slicing.md` | Document and diff slicing algorithm, section mapping, routing patterns |
| `launch.md` | Stage dispatch, expansion scoring, interserve/Codex mode, AgentDropout |
| `launch-codex.md` | Codex CLI dispatch for interserve mode |
| `synthesize.md` | Deduplication, convergence, verdict, knowledge compounding |
| `cross-ai.md` | Optional cross-AI comparison via Oracle CLI |

Reference files in `skills/flux-drive/references/`:

| File | Content |
|------|---------|
| `agent-roster.md` | Full roster: Project Agents, Plugin Agents, Cognitive Agents, Cross-AI |
| `scoring-examples.md` | 4 worked scoring examples across document types |

### Compact Variant

`SKILL-compact.md` (15K) is a single-file version of the same triage algorithm. When a `.skill-compact-manifest.json` exists, the compact version loads instead of the multi-file instructions.

## MCP Servers (1)

| Server | Type | Purpose |
|--------|------|---------|
| **exa** | stdio | External web research via Exa API. Progressive enhancement — requires `EXA_API_KEY`. Falls back to Context7 + WebSearch if unavailable. |

**Note:** qmd MCP server (semantic search for knowledge) has moved to the **interknow** plugin. The `launch-qmd.sh` script in `scripts/` is vestigial.

## Hooks (2)

Registered in `hooks/hooks.json` under `SessionStart`:

| Hook | Purpose |
|------|---------|
| `session-start.sh` | Ecosystem status reporting (`[interverse] beads=... \| ic=...`). Sources interbase SDK or falls back to no-ops. |
| `write-capabilities.sh` | Writes plugin capabilities for interbase integration |

## Domain Classification

LLM-based classification. Flux-drive Step 1.0.1 classifies the project into domains based on README, build files, and source files read during Step 1.0. No external scripts — the LLM already has the context.

### 11 Domains

`game-simulation`, `web-api`, `ml-pipeline`, `cli-tool`, `mobile-app`, `embedded-systems`, `data-pipeline`, `library-sdk`, `tui-app`, `desktop-tauri`, `claude-code-plugin`

Each domain profile (`config/flux-drive/domains/<name>.md`) contains:
- Review criteria injected into agent prompts
- Agent injection specifications (which agents get domain-specific bullets)
- Research Directives for external research agents

## Knowledge Lifecycle

Managed by the **interknow** plugin (not interflux). Key concepts:

- **Provenance tracking**: `independent` (re-discovered without prompting) vs `primed` (re-confirmed while in context)
- **Temporal decay**: entries not independently confirmed in 10 reviews are archived
- **Injection**: top 5 relevant entries injected into agent prompts via semantic search (qmd, served by interknow)
- **Compounding**: new patterns extracted from review findings and saved via interknow

Local knowledge entries exist in `config/flux-drive/knowledge/` for reference and migration.

## Intermediate Finding Sharing

During parallel flux-drive reviews, agents share high-severity findings via `{OUTPUT_DIR}/peer-findings.jsonl`.

- **blocking**: contradicts another agent's analysis (MUST acknowledge)
- **notable**: significant finding that may affect others (SHOULD consider)

Helper script: `scripts/findings-helper.sh` (write/read operations).

## Budget and Cost

Configuration in `config/flux-drive/budget.yaml`:

- Budgets by input type: plan (150K), brainstorm (80K), diff-small (60K), diff-large (200K), repo (300K)
- Per-agent defaults: review (40K), cognitive (35K), research (15K), oracle (80K), generated (40K)
- Slicing multiplier: 0.5x for non-cross-cutting agents when slicing is active
- Minimum 2 agents always dispatched regardless of budget
- Enforcement: soft (warn + offer override)
- Exempt agents: fd-safety, fd-correctness (never dropped by budget or AgentDropout)
- AgentDropout threshold: 0.6 redundancy score

Cost estimation: `scripts/estimate-costs.sh` queries interstat historical data, falls back to budget.yaml defaults.

## Model Routing Experiments

`config/flux-drive/agent-roles.yaml` tracks routing experiments:

| Experiment | Status | Finding |
|------------|--------|---------|
| exp1_complexity_routing | complete | Hypothesis inverted — role-aware routing increases cost 20% |
| exp2_role_aware | complete | fd-safety on Haiku 47%, fd-correctness 26% — quality risk |
| exp3_collaboration_modes | deferred | Requires flux-drive dispatch changes |
| exp4_pareto_frontier | partial | B1 + safety floors is Pareto-optimal for current workload |

## Protocol Specification

Formal spec in `docs/spec/` (flux-drive-spec 1.0.0). Extracts the abstract protocol from the interflux reference implementation into standalone, framework-agnostic documents.

Three conformance levels:
- **Core**: 3-phase lifecycle, base scoring (0-4), staging, contracts, synthesis
- **Core + Domains**: adds domain detection, domain_boost/domain_agent_bonus (0-7)
- **Core + Knowledge**: adds provenance-tracked review memory with temporal decay

### Documents

| Path | Content |
|------|---------|
| `docs/spec/README.md` | Overview, conformance levels, reading order |
| `docs/spec/core/protocol.md` | 3-phase lifecycle |
| `docs/spec/core/scoring.md` | Agent selection algorithm |
| `docs/spec/core/staging.md` | Two-stage dispatch |
| `docs/spec/core/synthesis.md` | Findings aggregation |
| `docs/spec/contracts/findings-index.md` | Agent output format |
| `docs/spec/contracts/completion-signal.md` | Completion signaling |
| `docs/spec/extensions/domain-detection.md` | Domain signal scoring |
| `docs/spec/extensions/knowledge-lifecycle.md` | Knowledge decay + accumulation |

## Dual-Mode Architecture

interflux supports standalone (marketplace) and integrated (Interverse ecosystem) operation via the interbase SDK.

- **Standalone**: Stub falls back to no-ops. All review/research features work. No ecosystem features (phase tracking, nudges, sprint gates).
- **Integrated**: `~/.intermod/interbase/interbase.sh` sourced. Session-start hook reports ecosystem status. Nudge protocol suggests missing companions.

## Testing

### Structural Tests (pytest)

```bash
cd /home/mk/projects/Demarch/interverse/interflux && uv run pytest tests/ -q
```

Key test suites in `tests/structural/`:

| Test File | Coverage |
|-----------|----------|
| `test_agents.py` | Agent frontmatter, structure, required sections |
| `test_commands.py` | Command frontmatter, structure |
| `test_skills.py` | Skill structure, phase files |
| `test_namespace.py` | Guards against stale `clavain:` references |
| `test_slicing.py` | Content routing, section mapping |
| `test_detect_domains.py` | Domain detection signals, scoring |
| `test_content_hash.py` | Deterministic hashing, staleness |
| `test_generate_agents.py` | Agent generation from domains and prompts |

### Shell Tests

| Test File | Coverage |
|-----------|----------|
| `test-budget.sh` | Budget estimation, slicing multipliers |
| `test-findings-flow.sh` | Peer findings write/read flow |
| `test_estimate_costs.bats` | Cost estimation edge cases (bats framework) |

### Validation Checklist

```bash
# Component counts
ls agents/review/*.md | wc -l         # Should be 12
ls agents/research/*.md | wc -l       # Should be 5
ls commands/*.md | wc -l              # Should be 4
ls skills/*/SKILL.md | wc -l          # Should be 2 (1 active + 1 deprecated)

# Domain profiles
ls config/flux-drive/domains/*.md | wc -l  # Should be 11

# Manifest
python3 -c "import json; d=json.load(open('.claude-plugin/plugin.json')); print(list(d['mcpServers'].keys()))"  # ['exa']

# Namespace check
uv run pytest tests/structural/test_namespace.py -v
```

## Scripts Reference

| Script | Language | Purpose |
|--------|----------|---------|
| `bump-version.sh` | bash | Version bump, commit, push (plugin + marketplace) |
| `estimate-costs.sh` | bash | Per-agent cost estimation (interstat historical + budget.yaml fallback) |
| `findings-helper.sh` | bash | Write/read peer findings JSONL during parallel reviews |
| `generate-agents.py` | python | Generate `.claude/agents/fd-*.md` from LLM-designed specs JSON |
| `launch-exa.sh` | bash | Launch Exa MCP server (checks `EXA_API_KEY`) |
| `update-domain-profiles.py` | python | Refresh domain profile markdown from index.yaml |
| `validate-gitleaks-waivers.sh` | bash | Validate gitleaks waiver entries |
| `validate-roster.sh` | bash | Validate agent roster integrity |

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `EXA_API_KEY` | No | Exa API key for web research. Agents degrade gracefully without it. |
| `CLAUDE_PLUGIN_ROOT` | Auto | Set by Claude Code to plugin directory. Used in hooks and scripts. |
| `FLUX_ROUTING_OVERRIDES_PATH` | No | Path to routing overrides JSON (default: `.claude/routing-overrides.json`) |

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


