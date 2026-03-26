# Flux Drive Research Synthesis

## Research Question
"new routing architecture"

## Sources
- `docs/plans/2026-02-21-static-routing-table.md` (Internal, High Authority)
- `docs/prds/2026-02-17-heterogeneous-collaboration-routing.md` (Internal, High Authority)

## Key Answer
The new routing architecture in Demarch transitions from simple homogeneous dispatch to a two-pronged system: a highly performant **Static Routing Table** driven by `config/routing.yaml` for deterministic agent and phase resolution, and an experimental **Heterogeneous Collaboration Routing** system that dynamically routes tasks to role-aware multi-agent topologies based on cost and quality tradeoffs.

## Findings

### 1. Deterministic Static Routing Table (B1)
The architecture unifies dispatch tiers and subagent routing into a single `config/routing.yaml`. It is parsed using a bespoke, zero-dependency bash parser (`lib-routing.sh`) to eliminate LLM-inference overhead during routing decisions. The schema supports:
- **Default and Phase-based Models**: Resolves models based on context (e.g., `brainstorm` phase gets Opus, `research` gets Haiku).
- **Fallback Chains**: Resolves dispatch tiers (e.g., `fast` -> `gpt-5.3-codex-spark`) with fallback logic.

### 2. Heterogeneous Collaboration Routing (Experimental)
A parallel architectural track explores mixing model sizes, roles (planner, editor, reviewer), and collaboration topologies (sequential, parallel). 
- **Task Taxonomies**: Incoming tasks are tagged by risk and novelty to map them to optimal candidate agent topologies.
- **Policy Selection**: Evaluates baseline vs. cost-first vs. quality-first strategies, using `interspect` and `intermute` to track conflict telemetry and time-to-completion.

### 3. Fail-Closed Guardrails
The static routing design enforces a fail-closed behavior on missing or malformed configuration to avoid silently selecting an inappropriate model, maintaining backward compatibility via the `/model-routing` command fallback.

## Confidence
- **High confidence**: The design of the Static Routing Table is fully formalized with concrete plans and PRDs.
- **Medium confidence**: The Heterogeneous Routing capabilities are explicitly marked as experimental, with success gates pending telemetry evaluation.

## Gaps
- **Transition Mechanics**: It is unclear how successful dynamic routing policies from the heterogeneous experiments graduate into the static `routing.yaml` configuration.
- **Conflict Thresholds**: The acceptable rate of redundancy and conflict in parallel topologies remains an open research question.