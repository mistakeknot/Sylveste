---
artifact_type: cuj
journey: interlens-conceptual-analysis
actor: regular user (developer or thinker applying conceptual frameworks)
criticality: p3
bead: Demarch-2c7
---

# Interlens Conceptual Analysis

## Why This Journey Matters

Difficult decisions benefit from multiple perspectives — not just technical perspectives (architecture, performance, security) but conceptual ones drawn from philosophy, systems thinking, game theory, cognitive science, and other disciplines. Interlens provides a curated library of "lenses" — mental models with structured application protocols — that help developers think more rigorously about design decisions, tradeoffs, and strategic choices.

The value isn't the lenses themselves (most are well-known mental models) but the structured application: given your specific problem, which lenses are most relevant? How do they interact? What blind spots does each lens reveal? Interlens turns ad-hoc "let me think about this differently" into a systematic analytical process.

## The Journey

The developer faces a design decision: "Should Mycroft auto-promote based on metrics, or require manual promotion?" They ask Interlens for help: `analyze_with_lens("mycroft promotion mechanism", "principal-agent")`. Interlens applies the principal-agent lens — identifying the developer as principal, Mycroft as agent, and analyzing information asymmetry, incentive alignment, and monitoring costs.

For broader exploration, `suggest_thinking_mode("mycroft autonomy tier design")` recommends which lenses are most relevant. Interlens might suggest: principal-agent (delegation trust), Goodhart's Law (metrics gaming), gradual trust escalation, and Cynefin (complexity domains for dispatch decisions).

The developer can explore lens relationships: `get_related_lenses("principal-agent")` shows connected concepts — moral hazard, adverse selection, mechanism design. `find_contrasting_lenses("principal-agent")` surfaces perspectives that challenge the principal-agent framing — perhaps stewardship theory (agents act in principals' interests without monitoring).

For synthesis: `synthesize_solution("mycroft promotion", ["principal-agent", "goodharts-law", "gradual-trust"])` combines multiple lenses into a unified analysis with recommendations. The output: "Manual promotion avoids Goodhart's Law (Mycroft gaming its own metrics) while the principal-agent lens suggests this is appropriate given the early trust relationship. Gradual trust supports the tier model. Recommendation: keep manual promotion at T0→T1→T2, consider auto-promotion at T2→T3 once the feedback loop is proven."

The developer can also browse episodically: `get_lenses_by_episode("6")` returns lenses introduced in a specific episode of the Interlens series. `random_lens_provocation()` surfaces a surprising lens for creative ideation.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Lens analysis produces actionable insight for the stated problem | qualitative | Developer learns something non-obvious from the analysis |
| Suggested lenses are relevant to the problem domain | qualitative | ≥3 of 5 suggested lenses feel applicable |
| Contrasting lenses challenge the initial framing | qualitative | At least one contrasting lens reveals a blind spot |
| Synthesis combines lenses without contradiction | qualitative | Output is coherent, not a list of disconnected observations |
| Lens library covers major conceptual frameworks | measurable | ≥50 lenses across philosophy, systems, game theory, cognition |
| Graph operations (related, contrasting, journey) complete in <2s | measurable | MCP tool response time ≤ 2s |

## Known Friction Points

- **Lens quality varies** — some lenses are deeply developed with application protocols, others are thin. Curation is ongoing.
- **Abstract by nature** — developers expecting "tell me what code to write" will find lens analysis too conceptual. It's a thinking tool, not a coding tool.
- **Synthesis can be hand-wavy** — combining 4 lenses into a coherent recommendation is hard. Output quality depends heavily on the LLM's reasoning.
- **No project context** — Interlens doesn't read your codebase. Analysis is based on the problem description you provide. Richer context = better analysis.
- **Web app and API are separate** — the MCP server, web frontend, and Flask API are three separate systems with separate deployments.
