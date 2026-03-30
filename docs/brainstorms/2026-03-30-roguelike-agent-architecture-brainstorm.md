---
bead: sylveste-rsj.3
date: 2026-03-30
type: brainstorm
source: flux-research (4-agent parallel research session)
---

# Roguelike-Inspired Agent Architecture — Brainstorm

## Research Question

What are Arcgentica, NLE (NetHack Learning Environment), and related environments? How might any of these be beneficial, relevant, inspirational, or surprisingly related to Sylveste's vision of a "garden salon of systems geniuses"?

## Key Findings

### Arcgentica (Not a Roguelike)

Arcgentica is Symbolica AI's ARC-AGI agent harness (~350-line Python orchestrator). Architecture is strikingly parallel to Sylveste:

- Orchestrator delegates to sub-agents, never touches environment directly
- Sub-agents return compressed textual summaries (context control)
- Stateful REPL for interleaved reasoning + execution
- Parallel hypothesis exploration
- **340x cost-efficiency over raw model**: 0.25% → 36% on ARC-AGI-3 at 1/9th cost

This validates PHILOSOPHY.md claim #1 (infrastructure bottleneck, not intelligence) on abstract reasoning, not just coding.

### NLE & Ecosystem

| Environment | Key Property | Status |
|---|---|---|
| NLE (NeurIPS 2020) | Full NetHack, 14x faster than Atari, procedural | Gold standard |
| MiniHack (NeurIPS 2021) | Modular NLE sandbox, controllable complexity | Active |
| BALROG (ICLR 2025) | 6-game unified LLM benchmark | Active leaderboard |
| BRAID (2025-26) | BALROG fork with modern agentic loops | Claude Opus 4.5 = 6.96% |
| Crafter/Craftax | 2D survival, JAX 250x speedup | Multi-agent extension 2025 |
| TALES (2025) | 122 text games unified benchmark | Best LLMs < 15% |
| GameDevBench (2025) | Agents *building* games, 3x SWE-bench complexity | New |

**State of art (2026):** GPT 5.2 = 12.56% NetHack progression. No AI has ascended. Scaffolding matters as much as model capability.

**Critical finding from NetHack Challenge (NeurIPS 2021):** Symbolic bots (AutoAscend, 11 hand-engineered strategies) beat neural agents by 3x. Structure beats raw capability when problems require long-horizon planning under compounding uncertainty.

### Six Structural Isomorphisms

1. **Permadeath ↔ Evidence-based trust** — irreversible consequences force meaningful decisions. "Permaconsequence" (Zeno Rogue): sessions end, world persists = beads, calibration files, routing overrides.

2. **Procedural generation ↔ Dynamic decomposition** — structure from constraints, not templates. Every dungeon is unique; every sprint's task graph is unique.

3. **Emergent gameplay ↔ Stigmergic coordination** — simple rule interactions → unplanned complexity. Research: stigmergy outperforms direct messaging by 36-41% at 500+ agents (arxiv 2601.08129v2).

4. **Character progression ↔ Progressive autonomy** — capability gated behind demonstrated competence. Don't give level-1 Excalibur; don't give untested agents deploy permissions.

5. **Item identification ↔ Tool/model discovery** — graduated discovery: cheap signals first (price ID / metadata), expensive last (scroll of identify / full benchmark). NetHack wiki: "identification is the heart of NetHack."

6. **Dungeon phases ↔ Sprint phases** — exploration/combat/loot/descent maps to brainstorm/build/review/ship. Both feature irreversible state transitions with rising stakes.

### What NetHack Tests That SWE-bench Misses

LLMs: 45%+ SWE-bench, 12.56% NetHack. The gap reveals untested capabilities:
- Long-horizon planning under compounding uncertainty
- Irreversible state changes (permadeath vs easy rollback)
- Emergent complexity (unanticipated interactions)
- Resource management under scarcity

These are exactly what makes real software engineering hard and what Sylveste's durability/evidence/trust systems address.

## Actionable Themes

### P2 — Direct Design Implications

1. **Identification-as-calibration (rsj.3.1):** Interspect should model an explicit "identification phase" for tool/model discovery. Try cheap signals first (metadata, prior traces), escalate to expensive ones (benchmarks) only when ambiguous. Inspired by NetHack's graduated item identification system.

2. **BALROG evaluation (rsj.3.2):** Run Skaffen against BALROG to test whether our infrastructure outperforms raw models on long-horizon, irreversible, emergent problems. This tests the core thesis on harder ground than SWE-bench.

3. **Stigmergic coordination evidence (rsj.3.3):** Cite the 36-41% advantage finding in vision doc. Evaluate whether current CRDT design captures "temporal decay" and "pressure field" patterns from the research.

### P3 — Evaluations and UX

4. **Permaconsequence visibility (rsj.3.4):** Make evidence compounding visible in Meadowsyn UX. Roguelike permadeath works because players see it. Users should see how session N's evidence changed session N+5's routing.

5. **Agentica SDK evaluation (rsj.3.5):** Evaluate specific patterns (stateful REPL, context compression via sub-agent summaries) for adoption in Skaffen.

6. **GameDevBench (rsj.3.6):** Secondary benchmark for complex multi-file work (132 tasks, 3x SWE-bench code changes).

## Sources

- Symbolica AI: arcgentica (github.com/symbolica-ai/arcgentica), blog posts on ARC-AGI-2 (85.28%) and ARC-AGI-3 (36.08%)
- NLE: Kuttler et al. NeurIPS 2020 (arxiv 2006.13760)
- MiniHack: Samvelyan et al. NeurIPS 2021
- NetHack Challenge: Hambro et al. PMLR 2022 (arxiv 2203.11889)
- BALROG: ICLR 2025 (arxiv 2411.13543), balrogai.com
- Craftax: ICML 2024 Spotlight
- TALES: Microsoft Research 2025 (arxiv 2504.14128)
- GameDevBench: 2025 (arxiv 2602.11103)
- Stigmergy: Pressure Fields and Temporal Decay (arxiv 2601.08129v2)
- Permaconsequence: Zeno Rogue (zenorogue.medium.com)
- "It's 2026. Can LLMs Play Nethack Yet?": kenforthewin.github.io
