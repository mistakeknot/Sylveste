# Recursive Language Models (RLMs) — Self-Managing Context Assessment

**Assessed:** 2026-03-16
**Source:** Alex L. Zhang, Tim Kraska, Omar Khattab (MIT CSAIL). arXiv:2512.24601, Dec 2025.
**Extension:** Prime Intellect "RLMs: the paradigm of 2026" (primeintellect.ai/blog/rlm, Jan 2026).
**Library:** github.com/alexzhang13/rlm (Python, plug-and-play inference library)
**Skaffen reference:** D10 (git-context architecture) in docs/brainstorms/2026-03-10-skaffen-sovereign-agent-brainstorm.md

---

## What It Is

RLMs are an inference-time paradigm where the model never receives large context directly.
Instead, context is loaded as a Python variable in a persistent REPL (Jupyter-like notebook).
The root model gets only the user query plus instructions for interacting with the variable
via code cells. It can slice, grep, transform, and recursively spawn sub-LLM calls over
portions of the context — treating context management as a programming problem rather than a
prompt-stuffing problem.

### Core Architecture

```
User query ──► Root LM (lean context: query + REPL instructions)
                  │
                  ▼
              Python REPL (persistent, pre-loaded with context as `data` variable)
                  │
                  ├── data[:1000]            # peek at slices
                  ├── grep("pattern", data)  # search
                  ├── sub_llm(chunk, query)  # recursive LM call (depth=1)
                  └── answer["content"] = x  # iterative answer refinement
```

Key constraints:
- REPL output capped at 8,192 chars per cell (configurable)
- Root model context stays lean — tool outputs and large context live only in REPL memory
- Sub-LLMs get tools (web search, file ops); root model cannot use tools directly
- Answer is a mutable state variable, refined iteratively ("diffusion over reasoning chain")
- Termination: `answer["ready"] = True` or `FINAL(answer)` / `FINAL_VAR(variable_name)`

### Prime Intellect Extensions (Jan 2026)

Prime Intellect took the MIT RLM paper and added:
- **Tool restriction to sub-LLMs only** — root model is a pure reasoning coordinator
- **`llm_batch()`** — parallelized sub-LLM dispatch for MapReduce-style decomposition
- **Environment answer protocol** — `answer["content"]` / `answer["ready"]` state machine
- **RLMEnv in verifiers repo** — RL-ready environment for training models to use the scaffold
- **Sandbox options** — local exec, Docker, Modal, E2B, Daytona, Prime Intellect sandboxes

Their thesis: the real breakthrough comes from training models via RL to manage their own
context, not just prompting them to do it. Current results are "exploratory ablations."

---

## Key Results

### Performance

| Benchmark | Baseline | RLM | Improvement |
|-----------|----------|-----|-------------|
| OOLONG (132K tokens, info extraction) | GPT-5: ~53 | RLM(GPT-5-mini): ~114 | >33% over GPT-5 |
| BrowseComp-Plus (1000 docs) | GPT-5: degrades | RLM(GPT-5): perfect | No degradation |
| CodeQA | GPT-5 base: 24.0 | RLM: 62.0 | 158% |
| Verbatim-copy (JSON) | Baseline | RLM | Improved via iterative refinement |
| math-python | Baseline | RLM | Decreased (model wastes effort on scaffolding) |

RLM-Qwen3-8B (RL-trained) outperforms base Qwen3-8B by 28.3% average, approaches vanilla
GPT-5 on three tasks — demonstrating that small models with RLM training can punch above
their weight.

### Token Economics

- **Main model context:** Reduced 60%+ on tool-heavy tasks (context offloaded to sub-LLMs)
- **Total tokens:** Increases for long-context tasks due to sub-LLM calls
- **Cost parity:** RLM(GPT-5-mini) achieves superior results at roughly the same API cost
  as vanilla GPT-5 on OOLONG — because the mini model is much cheaper per token
- **No prefix caching:** Each recursive call is blocking, no KV cache sharing between calls

### Limitations Identified

1. **No async execution** — sub-LLM calls are blocking (except Prime Intellect's `llm_batch()`)
2. **No prefix caching** — each sub-call starts cold, no shared KV cache
3. **Recursive depth limited** — practical tests only go to depth=1
4. **Degrades on simple tasks** — math-python shows overhead without benefit
5. **No runtime or cost guarantees** — model decides how many sub-calls to make
6. **Security** — LocalREPL exec is unsafe for untrusted inputs

---

## Does This Require Custom Training?

**No, but training dramatically improves it.**

The MIT paper's core results use off-the-shelf API models (GPT-5, GPT-5-mini) with zero
fine-tuning. The Python REPL and sub-LLM calling convention are purely prompt-injected.
Prime Intellect tested with GPT-5-mini, GLM 4.6, GLM 4.5 Air, and INTELLECT-3 via APIs.

However, RLM-Qwen3-8B (RL-trained to use the scaffold) shows 28.3% improvement over base,
suggesting that models trained specifically for RLM usage are substantially better at
deciding when to peek, when to delegate, and when to stop. Prime Intellect's thesis is that
RL training on the RLM scaffold is the real unlock — current prompt-only results are a floor.

**Bottom line for Skaffen:** Works today with prompted Claude/GPT. Gets better with training
we cannot do ourselves. The prompt-only version is what we can evaluate.

---

## Comparison to Skaffen's Current Context Design

### Skaffen D10: git-context Architecture

Skaffen's current design (from the brainstorm) defines four explicit context tools:

```go
enum ContextTool {
    Commit { summary }     // Checkpoint working state
    Retrieve { query }     // Pull from L2/L3 into L1
    Anchor { key, value }  // Pin stable signal (survives compression)
    Fold { scope }         // Compress completed sub-task
}
```

Three memory tiers: L1 (context window), L2 (session index), L3 (persistent store).
Priority rendering (D9/priompt) handles eviction. The model calls these tools explicitly.

### How RLMs Compare

| Dimension | Skaffen D10 | RLMs |
|-----------|-------------|------|
| **Who manages context** | Model calls explicit tools (Commit, Retrieve, Anchor, Fold) | Model writes arbitrary Python code |
| **Context storage** | Three tiers: window / session index / persistent store | Single REPL variable + sub-LLM results |
| **Eviction policy** | Priority rendering (priompt) — knapsack over prompt elements | No eviction — context never enters the window |
| **Summarization** | Hybrid compaction (D8) — structured summaries at phase boundaries | Never summarizes — always operates on raw data via code |
| **Sub-agent delegation** | Not in v0.1-v0.2 (orchestration via Autarch) | Core primitive — root model spawns sub-LLMs in REPL |
| **Tool access** | Model has direct tool access (phase-gated) | Root model has no tools; sub-LLMs get tools |
| **Cost model** | Pay for what's in context window | Pay for all sub-LLM calls (potentially more total tokens) |
| **Training required** | No (prompted tools) | No (but RL training helps significantly) |
| **Implementation complexity** | Moderate (4 tool types + priompt) | High (sandboxed REPL + sub-LLM dispatch + security) |

### Key Insight: Different Problems

RLMs solve "input too large for context window" — the model needs to process 132K tokens of
data but has a 32K window. The REPL lets it examine the data programmatically.

Skaffen's context tools solve "session too long for context window" — the model has been
working for 50 turns and needs to manage accumulated conversation, tool outputs, and
decisions. This is an accumulation problem, not an input-size problem.

These are complementary, not competing approaches:
- RLMs excel at **intake** — processing large inputs the model hasn't seen yet
- Skaffen's context tools excel at **retention** — managing what the model has already
  produced and consumed over a long session

---

## Is "Never Summarize" Viable at Pay-Per-Token?

The RLM "never summarize" claim is misleading when applied to coding agents:

1. **RLMs don't eliminate tokens — they redistribute them.** The root model's context is
   lean, but sub-LLM calls consume tokens. Total token cost can exceed standard approaches.
   The win is that a cheap model (GPT-5-mini) can coordinate while sub-LLMs do the heavy
   lifting, so cost per quality unit drops.

2. **Coding agents have a different cost structure.** An RLM processing a 132K-token
   document makes many read-only sub-calls. A coding agent's context is mostly its own
   prior actions (edits, test runs, tool outputs). Spawning a sub-LLM to re-read your own
   prior edit is wasteful compared to a structured summary.

3. **Skaffen already has the right economics.** Priority rendering (priompt) + hybrid
   compaction keeps the context window lean without losing critical information. Phase
   boundary summaries are durable (persisted to beads). This is cheaper than spawning
   sub-LLMs to re-derive what a 3-line summary captures.

4. **The real cost concern is cache invalidation.** Anthropic's prompt caching gives 90%
   discount on cached prefix tokens. Skaffen's priompt stable prefix optimization already
   targets this. RLM's approach — where the model writes arbitrary code that changes the
   REPL state — would invalidate caches constantly.

**Verdict on "never summarize":** Not viable as a blanket policy for coding agents. Viable
as a principle for specific sub-tasks (large file analysis, codebase-wide search).

---

## What to Borrow

### 1. Sub-LLM Delegation for Large-Input Tasks (HIGH VALUE)

When Skaffen needs to process something larger than its context window — a full test suite
output, a large diff, a codebase-wide analysis — spawning a sub-LLM with a focused query
is better than truncating or summarizing. This maps to Skaffen's future sub-agent
capability (Q1 in the brainstorm).

**Concrete integration point:** When a tool result exceeds a threshold (e.g., 30K tokens),
instead of truncating, Skaffen could spawn a sub-LLM call:
```
"This bash output is 45K tokens. Spawning analysis sub-task:
 query='Extract test failures and their stack traces from this output'
 result=[structured summary from sub-LLM]"
```

This is the RLM pattern applied surgically, not as the entire architecture.

### 2. Iterative Answer Refinement via State Variable (MEDIUM VALUE)

RLM's `answer["content"]` pattern — where the model writes an initial answer then
iteratively improves it by re-examining data — maps well to code generation. Skaffen could
expose a "draft" tool where the model writes code, examines it, and refines before
committing. This is distinct from the current write-then-edit flow because the draft never
enters the conversation history until finalized.

**Risk:** This adds complexity for marginal gain on most coding tasks. Reserve for
complex multi-file refactors where iterative planning matters.

### 3. Code-Based Context Examination (LOW VALUE for Skaffen)

The core RLM insight — "let the model write code to examine its context" — is less
valuable for Skaffen because Skaffen already has first-class tools for this: grep, glob,
read, bash. The model already writes code (via bash tool) to examine the codebase. Adding
a separate REPL for context examination would duplicate existing capability.

### 4. RL Training for Context Management (FUTURE / NOT ACTIONABLE)

Prime Intellect's strongest claim — that RL-trained models manage context dramatically
better — is interesting but not actionable. Skaffen uses API models; we cannot RL-train
them. If/when Anthropic or open-source models ship with RLM-style training, Skaffen would
benefit automatically through improved model behavior, no architecture change needed.

---

## Implementation Complexity

Adopting the full RLM architecture would require:

1. **Sandboxed Python REPL** — Security-critical, significant engineering (or dependency
   on alexzhang13/rlm library). Skaffen is Go; bridging to Python adds a runtime dependency.
2. **Sub-LLM dispatch** — Provider abstraction for spawning secondary model calls. Skaffen's
   provider layer supports this but the agent loop doesn't.
3. **Answer state machine** — `answer["content"]` / `answer["ready"]` protocol. Moderate
   complexity, conflicts with Skaffen's streaming response model.
4. **Security hardening** — LocalREPL exec is explicitly unsafe. Docker/E2B adds latency.

Estimated effort for full adoption: 3-4 weeks. For the surgical "sub-LLM for large inputs"
pattern: 3-5 days.

---

## Verdict: inspire-only

**Rationale:**

1. **Problem mismatch.** RLMs solve large-input processing; Skaffen's primary context
   challenge is long-session retention. The D10 context tools (Commit, Retrieve, Anchor,
   Fold) + priompt priority rendering are better fitted to the actual problem.

2. **Cost structure conflict.** RLMs trade main-model tokens for sub-LLM tokens. Skaffen's
   prompt caching strategy (stable prefix optimization) is more cost-effective for the
   turn-by-turn coding agent pattern.

3. **Architecture mismatch.** RLMs assume the root model is a coordinator that never touches
   tools directly. Skaffen's OODARC loop requires the model to use tools (read, write, edit,
   bash) directly during the Act phase. Inserting a REPL intermediary would break phase-gated
   tool access.

4. **The RL training thesis is the real value** — and it's not something we can act on.
   When models are RL-trained for context management, Skaffen benefits regardless of whether
   we adopt the RLM scaffold.

### Ideas to Borrow

| Idea | Priority | Where in Skaffen | When |
|------|----------|------------------|------|
| Sub-LLM delegation for oversized tool results | P2 | v0.3+ sub-agent capability | After sub-agent RPC (Q1) is built |
| Iterative draft refinement (answer state variable) | P3 | New "draft" tool in tool registry | Evaluate after v0.2 usage data |
| "Model writes code to examine context" pattern | Skip | Already covered by bash + grep + read tools | N/A |
| RL training for context management | Watch | No architecture change needed — benefits come from model improvements | When API models ship with this training |

### Research Bead Status

The existing research bead reference in D10 ("RLMs — Prime Intellect, Jan 2026 — model
writes code to manage own context. Most radical.") is accurate. This assessment supersedes
that placeholder with a full evaluation. Verdict: the ideas are sound but the architecture
doesn't fit Skaffen's constraints. Borrow the sub-LLM delegation pattern surgically;
skip the full scaffold adoption.
