# MAGMA Multi-Graph Retrieval Assessment

**Assessed:** 2026-03-16
**Source:** [arxiv.org/abs/2601.03236](https://arxiv.org/abs/2601.03236) (Jan 2026)
**Full title:** MAGMA: A Multi-Graph based Agentic Memory Architecture for AI Agents
**Applicability target:** Skaffen context management (`os/Skaffen/internal/session/`)

---

## What It Is

MAGMA is a memory architecture for LLM agents that decomposes the memory store
into 4 orthogonal graph structures instead of the conventional monolithic
vector database. Each memory item (event) is a node that exists simultaneously
in all 4 graphs, connected by different edge types:

| Graph | Edge semantics | Construction | Query type served |
|-------|---------------|--------------|-------------------|
| **Temporal** | Strict chronological ordering (t_i < t_j) | Automatic on ingestion (immutable chain) | "When" / sequence questions |
| **Causal** | Logical entailment (A caused B) | LLM-inferred async (slow path) | "Why" / root cause questions |
| **Semantic** | Cosine similarity above threshold | Embedding comparison (fast path) | "What" / concept similarity |
| **Entity** | Events share a named entity | NER extraction, async consolidation | "Who/what" / object permanence |

Retrieval is **policy-guided traversal**: a query classifier determines intent
(Why/When/Entity), sets adaptive weight vectors across the 4 graph types, then
performs beam search from anchor nodes. The transition score at each hop is:

    score = w_structural * graph_alignment + w_semantic * cosine(neighbor, query)

where `w_structural` is intent-adaptive (e.g., high causal weight for "Why"
queries, high temporal weight for "When" queries).

### Dual-Stream Indexing

- **Fast path** (non-blocking): event segmentation, vector embedding, temporal
  backbone update. Runs on every memory write.
- **Slow path** (async): LLM consolidation infers causal and entity edges by
  analyzing 2-hop neighborhoods. Trades compute for relational depth.

### Claimed Results

| Metric | MAGMA | Best baseline | Full context |
|--------|-------|---------------|--------------|
| Token consumption (LongMemEval) | 0.7-4.2K | varies | 101K |
| Query latency | 1.47s | 2.26s (A-MEM) | N/A |
| Accuracy (single-session) | 83.9% | varies | 89.3% |
| Token reduction | >95% | -- | baseline |

### Ablation Results (removing each component)

| Removed | Score | Delta |
|---------|-------|-------|
| Nothing (full MAGMA) | 0.700 | -- |
| Adaptive policy | 0.637 | -0.063 (largest) |
| Causal links | 0.644 | -0.056 |
| Temporal backbone | 0.647 | -0.053 |
| Entity links | 0.666 | -0.034 (smallest) |

The adaptive policy (routing queries to the right graph) matters more than any
single graph type. Causal and temporal are roughly equal contributors; entity
links provide the smallest marginal gain.

---

## Skaffen's Current Context Management

Skaffen uses a layered approach that is simple by design:

1. **JSONL session persistence** (`session.go`): Linear message history with
   turn-based append. Truncation keeps first message (context anchor) + last
   `maxTurns*2` messages.

2. **Priority rendering** (`priompt_session.go` + `masaq/priompt/`): System
   prompt composed from prioritized `Element` sections with phase-aware boosts.
   Greedy bin-packing within token budget. Stable elements form a cache prefix.

3. **Compaction** (`Compact()`): Replaces old history with a summary message,
   keeping the last 4 messages. Triggered manually via `/compact` command.

4. **Quality signals**: Recent session statistics (turns, token efficiency,
   tool errors) injected into Orient phase prompt.

5. **Phase-specific injection**: Fault localization guidance appended during
   Act phase. Inspiration data during Orient.

The design is deterministic, zero-latency (no async indexing), and cache-
friendly (stable prefix for Anthropic prompt caching). There is no embedding
infrastructure, no graph database, no async consolidation pipeline.

---

## Applicability Analysis

### 1. Indexing Cost

MAGMA's slow path requires an LLM call per consolidation window to infer
causal and entity edges. For a coding agent:

- **Per-turn cost**: Each tool call result (file read, grep, bash output) would
  need consolidation. A typical Skaffen session has 10-20 turns with 2-5 tool
  calls each = 20-100 consolidation calls.
- **Latency**: 1-3s per LLM call for edge inference. Even async, this means
  the graph lags 30-300s behind the conversation in a fast session.
- **Dollar cost**: At Haiku rates ($0.25/1M input), 100 consolidation calls
  with ~2K tokens each = $0.05 per session. Negligible, but adds up at fleet
  scale (Sylveste targets $1.17/landable change).

The fast path (temporal + semantic) is cheap: timestamp append + one embedding
call per event. This is feasible. The slow path (causal + entity) is where the
cost-benefit breaks down for coding agents.

### 2. Comparison to Current Approach (grep + priority rendering)

| Dimension | MAGMA | Skaffen priompt + grep |
|-----------|-------|------------------------|
| Latency to first useful context | 1.47s retrieval | ~0ms (already in prompt) |
| Token efficiency | 95% reduction vs full context | Priority packing achieves ~60-70% budget utilization |
| Cache hit rate | Unknown (reconstructed context varies per query) | High (stable prefix design) |
| Implementation complexity | 4 graph stores + beam search + LLM consolidation + NER | ~200 lines of Go |
| Failure modes | Stale causal edges, hallucinated entity links, graph corruption | Truncation loses old context (but that's the intent) |
| Determinism | Non-deterministic (LLM-inferred edges, beam search) | Fully deterministic |

The key insight: MAGMA solves a **memory retrieval** problem (finding relevant
past events across a long history). Skaffen solves a **context composition**
problem (fitting the right prompt sections into a token budget). These are
different problems.

MAGMA shines when an agent has 100K+ tokens of accumulated memory across many
sessions and needs to recall specific facts. Skaffen's context pressure is
within a single session (20-40 turns), where the conversation is already
ordered and causal relationships are implicit in the turn sequence.

### 3. Is 95% Token Reduction Realistic for Code?

No, not as MAGMA implements it. The 95% reduction comes from replacing full
conversation replay with targeted retrieval. But coding context has properties
that make aggressive reduction dangerous:

- **Code is dense**: A 50-line function has no redundant tokens. You can't
  "summarize" `if err != nil { return fmt.Errorf(...) }` without losing the
  exact error handling logic.
- **Positional precision matters**: "Line 47 of session.go" is load-bearing.
  Graph retrieval may return the right file but lose the line context.
- **Causal chains in code are structural**: `A imports B, B calls C, C returns
  error` is already captured by the dependency graph / call graph. You don't
  need an LLM to infer these edges -- `tldr-code` already provides this via
  AST analysis.
- **Multi-file coherence**: A typical bug fix touches 2-5 files. All must be
  in context simultaneously. Graph retrieval optimized for "find the one
  relevant memory" may scatter related edits across separate traversal paths.

For conversational memory (MAGMA's benchmark domain), 95% reduction makes
sense because conversations are naturally sparse -- most turns are social
glue. Code is the opposite: almost every token is structural.

A realistic target for coding context: 30-50% reduction through intelligent
compaction (which Skaffen already does via `Compact()` + priority rendering).

### 4. Which Graph Type Is Most Useful?

From the ablation study and coding-agent-specific analysis:

**Temporal graph: already implemented.** Skaffen's JSONL persistence is a
temporal chain. Turn order IS the temporal graph. Free.

**Semantic graph: partially useful.** Could help cross-session recall ("I
fixed a similar bug in package X last week"). But Skaffen can get this from
`cass search` (already integrated into the Sylveste ecosystem) without building
a dedicated embedding index.

**Causal graph: the interesting one, but redundant for code.** Code has
explicit causal structure (imports, function calls, error propagation) that
tools like `tldr-code` already expose via static analysis. LLM-inferred
causal edges add noise, not signal, compared to AST-derived call graphs.

**Entity graph: least useful for coding.** "Object permanence" across
conversation segments matters for tracking people, places, and objects in
natural conversation. In code, entities are files, functions, and variables --
which are already tracked by the filesystem and language server.

### 5. Engineering Complexity vs. Benefit

Building MAGMA-style infrastructure into Skaffen would require:

- Embedding service (or local model like all-MiniLM-L6-v2) -- Go bindings
- Graph storage (likely SQLite + adjacency tables, or embedded graph DB)
- Async consolidation worker with LLM calls
- Beam search traversal with intent classification
- Cache invalidation when graphs update
- ~2000-4000 lines of Go, plus operational complexity

Current priompt system: ~225 lines of Go, zero external dependencies, zero
async infrastructure, deterministic behavior, cache-friendly.

---

## Verdict: inspire-only

MAGMA's core insight -- that different query intents should traverse different
relational structures -- is sound. But the implementation targets long-context
conversational memory, not coding-agent context management. The gap is
fundamental:

1. **Wrong problem shape.** MAGMA retrieves from 100K+ token memory stores.
   Skaffen's pressure is composing 10-20 prompt sections within a budget.

2. **Code has explicit structure.** The causal and entity graphs that MAGMA
   infers via LLM consolidation already exist as AST/call-graph data in
   `tldr-code`. Reimplementing them with lower fidelity adds no value.

3. **Determinism matters.** Skaffen's priority rendering is deterministic and
   cache-friendly. Graph traversal with beam search is neither.

4. **The ecosystem already has the pieces.** Cross-session semantic search
   exists via `cass`. Code structure exists via `tldr-code`. Temporal ordering
   is inherent in JSONL persistence.

### What to Steal (Ideas, Not Code)

- **Intent-adaptive retrieval weighting.** When Skaffen's `/compact` generates
  a summary, it could classify the conversation's dominant concern (debugging
  vs. feature-building vs. refactoring) and weight which context sections to
  preserve. This is a 20-line enhancement to `Compact()`, not a new subsystem.

- **Salience-based budgeting.** MAGMA's structured context construction
  summarizes low-salience nodes ("...3 intermediate events...") while
  preserving high-salience ones verbatim. Priompt could adopt a similar
  strategy: instead of binary include/exclude, allow elements to provide a
  "compressed" variant at lower priority.

- **Dual-stream processing pattern.** The fast-path/slow-path separation is
  a clean architecture for any system that needs both low-latency responses
  and deep analysis. If Skaffen ever adds cross-session learning, the
  dual-stream model is the right way to structure it.

### What NOT to Build

- Do not build a multi-graph memory store. Use `cass` for cross-session search
  and `tldr-code` for code structure.
- Do not add LLM-based consolidation for causal/entity inference. AST analysis
  is faster, cheaper, and more accurate for code.
- Do not add embedding infrastructure to Skaffen. The ecosystem already has
  `intersearch` for embedding indices.

### Recommended Next Steps

1. Add a `CompressedContent` field to `priompt.Element` -- used when the full
   content doesn't fit but a shorter version is acceptable. ~30 lines.
2. Add intent classification to `Compact()` -- classify dominant concern and
   bias summary toward preserving relevant sections. ~50 lines.
3. If cross-session recall becomes a real bottleneck (not speculative), pipe
   `cass search` results into a priompt section at Orient phase. ~40 lines.

Total: ~120 lines of Go, zero new infrastructure, captures the useful ideas.

---

## References

- [MAGMA paper](https://arxiv.org/abs/2601.03236) (arxiv, Jan 2026)
- [MAGMA HTML](https://arxiv.org/html/2601.03236v1) (full text)
- Skaffen session code: `os/Skaffen/internal/session/`
- Skaffen priompt: `masaq/priompt/priompt.go`
- Skaffen brainstorm D10 mention: `docs/brainstorms/2026-03-10-skaffen-sovereign-agent-brainstorm.md`
