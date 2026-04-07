# Topic: Making Interflux Better — Insight Quality and Token Efficiency

## Context

Interflux is a multi-agent review and research orchestration plugin for Claude Code. It dispatches 5-16 specialized review agents in parallel, each analyzing a document or codebase from a different domain perspective. Findings are synthesized into a unified report.

## Current Architecture

- **17 agents**: 12 review (7 technical + 5 cognitive) + 5 research
- **3-phase pipeline**: Triage (score + select agents) → Launch (staged dispatch with expansion) → Synthesize (dedup + verdict)
- **Budget system**: Per-type token budgets, billing vs total tracking, budget-aware agent selection
- **Cross-model dispatch**: Routes Stage 2 agents to different model tiers (haiku/sonnet/opus) based on expansion score and budget pressure
- **Reaction round**: Inter-agent critique with discourse topology, sycophancy detection, hearsay filtering
- **Domain detection**: Signal-based project classification (11 domains) for domain-specific review criteria injection
- **Progressive enhancement**: Optional systems (knowledge context, trust multiplier, overlays) that activate only when available

## Current Cost Model

- All agents currently dispatch as Claude models (opus/sonnet/haiku) via Claude Code's Agent tool
- Cross-model dispatch adjusts tiers but stays within the Claude family
- Typical review: 3-6 agents, ~60-200K total tokens, ~$1-5 per run
- No integration with non-Anthropic models

## Question

How can interflux be made significantly better in two dimensions:

1. **Insight quality**: More diverse perspectives, better finding precision, reduced blind spots, novel analytical lenses
2. **Token efficiency**: Same or better insights at lower cost, smarter model routing, leveraging cheap high-performance models

Specifically interested in:
- **Chinese models on OpenRouter**: DeepSeek V3/R1, Qwen 2.5/3, Yi, etc. — these models offer strong reasoning at 10-50x lower cost than Claude Opus. How could interflux fan out to these models for certain agent types while keeping Claude for high-judgment tasks?
- **Model diversity as a signal**: Different model families have different training biases — disagreements between Claude and DeepSeek on the same finding might be more meaningful than agreement between two Claude agents
- **Tiered dispatch**: Which agent types benefit most from Claude's strengths vs which could run on cheaper models without quality loss?
- **OpenRouter integration**: How to add OpenRouter as a dispatch backend, routing certain agents through it while keeping the orchestrator on Claude

## Constraints

- Interflux runs inside Claude Code — the orchestrator is always Claude
- Agents are dispatched via Claude Code's Agent tool (subagents) which only supports Claude models natively
- Any non-Claude model integration would need to go through Bash tool (API calls) or MCP server
- The synthesis step should stay on Claude (highest-judgment task)
- Must be backward-compatible — OpenRouter integration should be a progressive enhancement, not a requirement
