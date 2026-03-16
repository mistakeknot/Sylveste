# SimpleMem Context Compression Assessment

**Assessed:** 2026-03-16
**Source:** [arxiv.org/abs/2601.02553](https://arxiv.org/abs/2601.02553) (v3, Jan 2026)
**Authors:** Jiaqi Liu, Yaofeng Su, Peng Xia, Siwei Han, Zeyu Zheng, Cihang Xie, Mingyu Ding, Huaxiu Yao
**Code:** [github.com/aiming-lab/SimpleMem](https://github.com/aiming-lab/SimpleMem) (Python, pip-installable)
**Related brainstorm:** D8 in `docs/brainstorms/2026-03-10-skaffen-sovereign-agent-brainstorm.md`

---

## What It Is

SimpleMem is a lifelong memory framework for LLM agents that achieves ~30x token reduction while improving answer quality (+26.4% F1 over Mem0). It targets multi-session conversational agents that accumulate history over days/weeks. Three-stage pipeline:

1. **Semantic Structured Compression** — Sliding window (W=10 turns, 50% overlap) scored by an information function, then transformed into context-independent memory units via coreference resolution and temporal anchoring.

2. **Online Semantic Synthesis** — Background process that clusters related memory units and merges them into abstract representations (e.g., multiple "user drinks coffee at 8am" entries become a single pattern).

3. **Adaptive Query-Aware Retrieval** — Hybrid dense+sparse+metadata scoring with dynamic depth adjustment based on query complexity.

---

## Technical Details

### Information Scoring (Not Entropy)

Despite the "entropy-aware" framing in secondary sources, the scoring function is entity-centric, not information-theoretic:

```
H(W_t) = alpha * |E_new| / |W_t| + (1-alpha) * (1 - cos(E(W_t), E(H_prev)))
```

- `|E_new|` = novel named entities absent from prior history
- `cos(E(W_t), E(H_prev))` = semantic similarity to prior context
- Windows below tau_redundant=0.35 are filtered entirely

This is a redundancy detector: high score = new entities + semantically different from history. Low score = repetitive content that gets dropped.

### Memory Unit Construction

Each surviving window goes through a pipeline:

```
m_k = Phi_time . Phi_coref . Phi_extract(W_t)
```

- Extract factual statements
- Resolve coreferences (pronouns -> entity names)
- Anchor temporal expressions to ISO-8601

Output: self-contained facts interpretable without conversational context.

### Consolidation Trigger

Pairwise affinity combining embedding similarity and temporal proximity:

```
omega_ij = beta * cos(v_i, v_j) + (1-beta) * exp(-lambda * |t_i - t_j|)
```

Clusters above tau_cluster=0.85 trigger merge. This runs asynchronously, not on the critical path.

### Retrieval

Hybrid scoring (dense embedding + BM25 + metadata constraints) with dynamic k:

```
k_dyn = floor(k_base * (1 + delta * C_q))
```

Query complexity classifier determines k_min=3 to k_max=20.

### Benchmark Results

| System | Avg F1 | Tokens/query |
|--------|--------|-------------|
| Full context | ~30 | 16,900 |
| Mem0 | 34.20 | ~980 |
| SimpleMem | 43.24 | 530-580 |

Construction cost: 92.6s/sample (14x faster than Mem0). Total pipeline: 481s vs Mem0's 1,934s.

---

## Skaffen Baseline

Skaffen's current compaction is deliberately minimal (v0.1 focus was loop correctness, not context sophistication):

### What Exists

1. **Truncation** (`session.go:truncate`) — When messages exceed `maxTurns*2`, keeps first message (context anchor) + last N messages. Pure recency heuristic. No semantic awareness.

2. **Manual compaction** (`commands.go:execCompact`) — User-triggered `/compact` command. Replaces history with a one-line summary ("Previous conversation had N messages covering M turns") + last 4 messages. The summary contains zero semantic content.

3. **Priority-based prompt rendering** (`priompt_session.go`) — PriomptSession uses priority-scored prompt sections with a token budget. This handles system prompt composition, not conversation history compression. Closest thing to "intelligent" context management but operates on a different axis.

4. **No reactive compaction** — The agent loop (`agentloop/loop.go`) has no mid-turn compaction trigger. It estimates message tokens for prompt budget calculation but never triggers compaction when context grows large.

### What D8 Planned

The brainstorm specifies hybrid compaction: structured summaries at phase boundaries (goal, decisions, artifacts, file lists) + reactive mid-phase compaction when context threshold is crossed. Neither is implemented yet — the loop just accumulates messages and relies on truncation.

---

## Applicability Analysis

### Where SimpleMem Fits

SimpleMem solves a **different problem** than Skaffen needs. Key mismatches:

| Dimension | SimpleMem | Skaffen |
|-----------|-----------|---------|
| **Time horizon** | Days/weeks of conversation | Single session (minutes to hours) |
| **Turn count** | 200-400 turns | 20-100 turns |
| **Content type** | Personal facts, preferences, temporal events | Code, tool results, file contents, error traces |
| **Key entities** | People, places, dates | Files, functions, classes, test names |
| **Redundancy pattern** | "User likes coffee" repeated across sessions | Same file read multiple times with edits between |
| **Retrieval need** | Recall a fact from 3 weeks ago | Keep recent tool context coherent |
| **Consolidation value** | High (many sessions about same topic) | Low (single session, linear progression) |

### What Would Not Transfer

1. **Entity-based scoring** — SimpleMem's NER-driven information score is tuned for personal facts. Code entities (file paths, function names, variable names) have fundamentally different distribution. A `config.yaml` mentioned 15 times is not redundant — each mention may have different content. SimpleMem would aggressively filter the repetitions, losing the edit trail.

2. **Coreference resolution** — Pronoun resolution matters in dialogue ("he said", "that restaurant"). Code agent conversations reference entities by name ("the `handleRequest` function", "`/src/api/routes.go`"). Coreference adds latency without value.

3. **Temporal anchoring** — Converting "next Friday" to ISO-8601 is irrelevant in a coding session. Agent time is measured in turns and tool calls, not calendar dates.

4. **Asynchronous consolidation** — SimpleMem consolidates across sessions in the background. Skaffen sessions are typically standalone. Cross-session memory is handled by beads (work tracking) and cass (session intelligence), not the agent runtime itself.

5. **Retrieval pipeline** — SimpleMem's hybrid retrieval (LanceDB + BM25 + metadata) is the heaviest component. Skaffen's context window is the conversation itself — it doesn't need to retrieve from an external memory store within a single session.

### What Could Transfer (With Significant Adaptation)

1. **Redundancy detection heuristic** — The core idea of scoring conversation windows for information novelty and filtering low-scoring ones. But the scoring function needs to be completely rewritten for code content. Instead of entity novelty, score by: (a) whether tool results changed since last read of same file, (b) whether the assistant's reasoning introduced new decisions vs. restating known facts, (c) whether error traces are variants of already-seen failures.

2. **Structured compression format** — The idea of transforming raw conversation into self-contained factual units is sound. For Skaffen, this maps to the structured phase summaries D8 already specifies: goal, decisions made, artifacts modified, current file state. This is simpler and more useful than SimpleMem's general-purpose memory units.

3. **Dynamic retrieval depth** — Adjusting how much context to include based on task complexity. Skaffen's priompt already does budget-based priority rendering, which is a more principled version of this for system prompts. Extending it to conversation history would be the right integration point.

---

## Verdict: inspire-only

### Rationale

SimpleMem is a strong paper for its target domain (lifelong personal assistant memory) but its architecture assumes a problem shape Skaffen does not have:

- **Single-session agent, not lifelong memory.** Skaffen sessions are 20-100 turns over minutes to hours. SimpleMem's 30x compression comes from cross-session deduplication over weeks. Within a single session, the compression ratio would be far lower (maybe 2-3x from removing redundant tool output), and the construction cost (92.6s/sample even at 14x faster than Mem0) would dominate any token savings.

- **Code content breaks the information score.** The entity-novelty + embedding-divergence formula was validated on personal conversational data (LoCoMo benchmark). Code agent conversations have different information patterns — file paths are repeated intentionally, tool results are structurally similar but semantically different, and the most "redundant-looking" content (repeated test runs) is often the most important (regression confirmation).

- **Skaffen already has better primitives for the transferable ideas.** Priority-based prompt rendering (priompt) is a more principled version of dynamic context budgeting. Phase-boundary structured summaries (D8) are a more appropriate version of semantic compression for code work. What Skaffen is missing is implementation of D8, not a new compression architecture.

### What to Take

Three concrete lessons worth recording from the paper:

1. **Score-then-filter is better than summarize-everything.** SimpleMem's key insight is that most conversation windows add zero new information. Rather than summarizing all content (Skaffen's current `/compact` approach, which produces a useless one-line summary), score each segment and drop low-value ones entirely. When implementing D8's reactive mid-phase compaction, apply this: score message pairs by information delta (did this turn change the agent's file-state model? introduce a new error? change the plan?) and drop turns that are pure repetition.

2. **Self-contained memory units beat raw history.** SimpleMem's coreference+temporal normalization creates units that work without surrounding context. Skaffen's phase summaries should follow this principle — a phase summary must be interpretable without the conversation that produced it. Include absolute file paths, final function signatures, test pass/fail state — not "the file we discussed" or "the test that was failing."

3. **Consolidation should be background, not blocking.** SimpleMem correctly runs clustering as an async process. When Skaffen implements cross-phase compaction, do it between phases (when the agent is waiting for the next phase gate), not during the turn loop.

### Integration Path (If We Revisit)

If Skaffen later adds multi-session memory (v0.3+ "cross-session context folding"), SimpleMem's architecture becomes more relevant. At that point, evaluate against MAGMA (multi-graph retrieval, also from the D8 research queue) and AgentFold (learned context folding). The retrieval component (LanceDB + BM25) could integrate via intersearch (Demarch's embedding search plugin) rather than a standalone store.

For now, the priority is implementing D8 as designed: structured phase-boundary summaries + reactive mid-phase compaction with a code-aware scoring heuristic. That delivers the immediate context management improvement without the integration cost of porting a Python memory framework into a Go agent runtime.

---

## References

- Paper: [arxiv.org/abs/2601.02553](https://arxiv.org/abs/2601.02553)
- Code: [github.com/aiming-lab/SimpleMem](https://github.com/aiming-lab/SimpleMem)
- Related D8 research queue items: MAGMA (arxiv.org/abs/2601.03236), AgentFold (arxiv.org/abs/2510.24699), RLMs (primeintellect.ai/blog/rlm)
- Skaffen session code: `os/Skaffen/internal/session/session.go`, `os/Skaffen/internal/agentloop/loop.go`
