---
bead: sylveste-rsj.3.2
date: 2026-03-30
type: assessment
verdict: adopt-phased
---

# Assessment: BALROG as Skaffen Evaluation Harness

## Summary

BALROG (Benchmarking Agentic LLM and VLM Reasoning On Games) tests exactly the capabilities that SWE-bench leaves on the table: long-horizon planning under uncertainty, irreversible consequences, emergent complexity, and resource scarcity in procedurally generated worlds. These are the capabilities Sylveste claims its orchestration infrastructure unlocks. Running Skaffen's OODARC loop against BALROG environments would produce the first direct measurement of whether phase-gated agent architecture (brainstorm-plan-build-review-ship) yields measurable progression improvements over raw model prompting — validating the core thesis that infrastructure, not model intelligence, is the bottleneck.

**Published:** November 2024, accepted at ICLR 2025
**Source:** github.com/balrog-ai/BALROG
**Leaderboard:** balrogai.com
**Environments:** 6 (BabyAI, Crafter, TextWorld, Baba Is You, MiniHack, NetHack)

---

## What BALROG Tests That SWE-bench Doesn't

| Capability | SWE-bench | BALROG |
|------------|-----------|--------|
| Long-horizon planning | 1-5 steps to patch | 100-10,000+ steps per episode |
| Irreversible consequences | Git revert always available | Death, resource loss, locked paths |
| Emergent complexity | Static codebase | Procedural generation, no memorization |
| Resource scarcity | Unlimited tool calls | Food, health, inventory management |
| Partial observability | Full repo context | Fog of war, limited perception |
| Multi-objective reasoning | Single: pass tests | Survive + explore + achieve goals |

SWE-bench measures whether an agent can produce a correct patch. BALROG measures whether an agent can sustain coherent behavior over extended horizons where mistakes compound. The latter is what matters for autonomous software development at scale — a 500-turn coding session is closer to NetHack than to a one-shot patch.

---

## Environment Relevance Ranking

Ranked by relevance to Sylveste's claimed differentiators (orchestration infrastructure unlocks autonomy):

### 1. TextWorld — Start Here

Language-based interactive fiction with procedural generation. Closest to Skaffen's natural domain: text observations, text actions, requires planning chains of 10-50 steps. Controlled complexity via difficulty settings. Fast iteration (no rendering, pure text). The ideal first adapter target.

### 2. MiniHack — Modular Complexity

NetHack derivative with configurable task composition. Key advantage: you can construct specific capability tests (navigation, combat, inventory management) without the full NetHack difficulty cliff. Tests compositional reasoning — combining sub-skills into coherent strategies.

### 3. NetHack — The Ultimate Test

The hardest environment in the benchmark. Best LLM result: GPT 5.2 at 12.56% progression. Claude Opus 4.5 via BRAID: 6.96%. Any measurable improvement from Skaffen orchestration here would be a strong signal. However, the absolute difficulty makes it a poor starting point — too easy to burn cycles with no legible signal.

### 4. Crafter — Resource Management

Open-world survival with crafting progression. Tests resource allocation under uncertainty — relevant to how agents manage token budgets and tool selection. Less directly applicable to Skaffen's code-oriented domain but exercises the planning-under-scarcity muscle.

### 5. Baba Is You — Rule Manipulation

Puzzle game where you change the rules of the game itself. Interesting for meta-reasoning but less directly relevant to orchestration infrastructure claims. Better suited as a secondary benchmark for reasoning quality rather than planning capability.

### 6. BabyAI — Too Simple

Gridworld navigation with language goals. Saturated by current models. Would not produce meaningful signal about Skaffen's orchestration value.

**Recommendation:** Start with TextWorld, expand to MiniHack once the adapter pattern stabilizes.

---

## Adapter Design Sketch

BALROG exposes a Gymnasium-compatible interface: `observation, reward, done, info = env.step(action)`. Skaffen's OODARC loop maps cleanly onto this:

### OODARC-to-BALROG Mapping

| OODARC Phase | BALROG Equivalent | Implementation |
|-------------|-------------------|----------------|
| **Observe** | `env.observation` → Skaffen context | Parse BALROG text/visual observation into structured context. For TextWorld, this is raw text. For visual environments, describe the screen (or use vision model). |
| **Orient** | Game state assessment → situation model | Maintain a running world model: inventory, known map, current objectives, threats. This is the key orchestration value — raw models don't do this. |
| **Decide** | Strategy selection → next action | Phase-gated decision: brainstorm possible approaches, select based on evidence from Orient phase. Router selects model complexity based on situation criticality. |
| **Act** | `env.step(action)` | Execute chosen action via BALROG action space. Single discrete action per turn. |
| **Reflect** | Outcome assessment → strategy adjustment | Compare expected vs actual outcome. Update world model. Detect strategy failures early (e.g., health dropping, inventory depleting). |
| **Compound** | Cross-episode learning → persistent state | Accumulate knowledge across episodes: effective strategies per environment type, common failure modes, heuristic improvements. Stored in Skaffen's session persistence (JSONL). |

### Architecture Notes

Skaffen's two-layer architecture (agentloop + agent) makes this clean:

- **agentloop** handles the Decide-Act core: provider calls, tool execution, turn limits. The BALROG adapter registers as a single tool (`balrog_step`) that wraps `env.step()`.
- **agent** handles OODARC phase sequencing: the phase FSM gates which reasoning patterns are active. Orient and Reflect phases add structured state management that raw agentloop would skip.
- **router** selects model complexity per turn: routine navigation gets a cheaper model, critical decision points (boss fight, complex puzzle) get the strongest available.
- **session** provides cross-episode persistence: Compound phase writes to JSONL, next episode reads back accumulated knowledge.
- **evidence** emits structured events for analysis: every OODARC cycle produces a traceable event record.

The adapter is a Go package (`internal/balrog/`) that:
1. Wraps the BALROG Python environment via subprocess or gRPC bridge
2. Translates observations into Skaffen context format
3. Exposes `balrog_step` as a registered tool in the tool registry
4. Manages episode lifecycle (reset, step, done detection)

### Key Design Decision: Text vs Vision

BALROG supports both text and vision observations. The ICLR paper found that vision-based models often performed *worse* than text-only — visual grounding introduces noise without proportional benefit. Start with text-only observations for all environments. TextWorld and NetHack have excellent text representations. Add vision as a controlled variable later.

---

## Baseline Protocol

Two-condition experiment measuring whether Skaffen's orchestration infrastructure produces measurable improvement:

### Condition 1: Raw Model (Control)

Direct model prompting with no orchestration:
- System prompt: environment description + action space
- User message: current observation
- Assistant response: next action
- No state management, no reflection, no cross-episode learning
- Model: Claude Sonnet 4 (mid-tier, to leave room for improvement signal)

### Condition 2: Skaffen-Orchestrated (Treatment)

Full OODARC loop:
- Phase-gated reasoning (Orient builds world model, Reflect updates strategy)
- Router-selected model complexity per turn
- Session persistence for cross-episode Compound learning
- Evidence emission for post-hoc analysis

### Metrics

- **Primary:** BALROG progression percentage (environment-specific, comparable to leaderboard)
- **Secondary:** Episodes to first success, token cost per progression point, strategy coherence (manual annotation of a sample)
- **Success criterion:** >= 50% relative improvement over raw model on >= 3 environments
- **Stretch criterion:** Competitive with published BRAID results (6.96% on NetHack) using a weaker base model

### Statistical Rigor

- Minimum 100 episodes per condition per environment (BALROG uses procedural generation, so each episode is unique)
- Report mean, median, and 95% CI for progression
- Track per-episode token cost to measure efficiency, not just effectiveness

---

## Effort Estimate

| Phase | Effort | Notes |
|-------|--------|-------|
| BALROG setup | 1-2 days | Clone repo, install NLE dependencies, verify environments run locally |
| Skaffen adapter (`internal/balrog/`) | 3-5 days | Python bridge, tool registration, observation parsing, episode management |
| TextWorld baseline runs | 1-2 days | Both conditions, 100+ episodes each |
| MiniHack expansion | 1-2 days | Reuse adapter, configure new observation parsing |
| Analysis + writeup | 1 day | Progression comparison, token cost analysis, strategy annotation sample |
| **Total** | **~1-2 weeks** | For TextWorld + MiniHack results |

### Hardware Requirements

- **GPU:** Not required. NLE (NetHack Learning Environment) runs on CPU and is faster than Atari. TextWorld is pure text processing.
- **Compute:** LLM API costs dominate. Estimate ~$50-100 for initial TextWorld runs (100 episodes x 2 conditions x ~500 turns x Sonnet pricing).
- **Storage:** JSONL session logs, ~1GB for full experiment.

---

## Recommended Starting Environment

**TextWorld.** Three reasons:

1. **Domain proximity:** Language-based interaction mirrors Skaffen's natural mode. No vision bridge needed. No observation-to-text translation loss.
2. **Controlled complexity:** TextWorld difficulty scales via recipe parameters (number of rooms, objects, required steps). Start simple, ramp up — isolates orchestration value from raw difficulty.
3. **Fast iteration:** Pure text, no rendering overhead. Episode completion in seconds, not minutes. Enables rapid adapter development with tight feedback loops.

Once the TextWorld adapter proves the OODARC-to-BALROG mapping works, MiniHack is the natural expansion — it adds spatial reasoning and combat while reusing the same adapter pattern.

---

## Follow-on Bead

This assessment closes `sylveste-rsj.3.2`. The actual BALROG integration run should be a new bead under `rsj.3`:

- **Title:** BALROG TextWorld evaluation — raw vs Skaffen-orchestrated baseline
- **Starting environment:** TextWorld
- **Effort estimate:** 1-2 weeks (from above)
- **Success criteria:** >= 50% relative progression improvement with OODARC vs raw model
- **Deliverables:** Adapter code (`internal/balrog/`), raw results data, analysis doc, leaderboard submission if results are competitive

---

## Verdict

**adopt-phased**

Start with a TextWorld adapter to validate the OODARC-to-BALROG mapping and measure orchestration value on the simplest relevant environment. Expand to MiniHack to test compositional reasoning. Defer full NetHack until TextWorld and MiniHack demonstrate that Skaffen's phase-gated architecture produces measurable progression improvements over raw model prompting.

The key insight from the BALROG paper: scaffolding architecture matters as much as model capability. This is exactly Sylveste's thesis. BALROG is the right benchmark to test it.

---

## Alignment / Conflict

**Alignment:**
- Directly validates Sylveste's core thesis (infrastructure unlocks autonomy) with quantitative evidence
- OODARC's Reflect and Compound phases map cleanly to BALROG's need for strategy adaptation and cross-episode learning
- Results are publishable and comparable via the open leaderboard — good for project credibility
- Low hardware barrier (CPU-only) keeps this accessible

**Risks:**
- **Negative result risk:** If Skaffen-orchestrated shows no improvement over raw model, it weakens the thesis. Mitigant: even a negative result is informative and publishable — and the adapter code is reusable for future architecture iterations.
- **Scope creep:** NetHack is seductive but premature. The phased approach (TextWorld first) guards against burning weeks on an environment where even GPT 5.2 only reaches 12.56%.
- **Adapter complexity:** The Python-Go bridge (BALROG is Python, Skaffen is Go) adds integration surface area. Mitigant: subprocess/gRPC bridge is a well-understood pattern; Skaffen already does this for MCP plugins and the Claude Code provider.
- **Metric validity:** BALROG progression percentage measures game performance, not software development capability. The mapping from "better at TextWorld" to "better at autonomous coding" requires careful argumentation. The claim is structural: if OODARC improves coherent long-horizon behavior in games, the same mechanisms should improve coherent long-horizon behavior in coding.
