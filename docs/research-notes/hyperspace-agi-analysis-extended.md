# Hyperspace AGI — Extended Analysis (Round 2)

> Deep dive findings beyond the initial ANALYSIS.md, incorporating web research and codebase grounding from 5 flux-drive agents.

## New Discoveries Not in Initial Analysis

### 1. Karpathy's Three Design Primitives

The original autoresearch (630 lines of Python) is built on exactly three constraints:

1. **Editable asset** — A single file the agent may modify (`train.py`)
2. **Scalar metric** — A single number determining improvement (`val_loss`)
3. **Time-boxed cycle** — Fixed 5-minute compute budget, making all experiments comparable

This is *more disciplined* than the initial analysis suggested. The key insight isn't "mutation" — it's **constraint**. By fixing the compute budget, every experiment becomes directly comparable regardless of what the agent changed.

**Demarch adoption**: interlab already implements all three primitives:
- Editable asset = `files_in_scope` in campaign config
- Scalar metric = `METRIC` lines from benchmark command
- Time-boxed cycle = `max_duration_sec` in campaign config (+ circuit breaker at 50 experiments)

What interlab is *missing* that Karpathy's version has: the agent reads its *own source code* before generating a hypothesis. Skaffen should read its own prior session transcripts (via CASS) and mutation history before planning — not just project code.

### 2. Scientific Rediscovery in 17 Hours

Web sources report that in 17 hours, Hyperspace agents independently rediscovered:
- **RMSNorm** (Google Brain, 2019)
- **Tied embeddings** (various labs, ~2016-2017)
- **Kaiming initialization** (He et al., 2015)

These are ML milestones that took human researchers years to formalize. The agents didn't read papers about these techniques — they discovered them through mutation search on a constrained problem space.

**Implication for Demarch**: This validates that mutation-based search can discover non-obvious solutions even without domain knowledge. The search space for code mutations is larger and less smooth than hyperparameter space, but the principle holds for narrow domains (e.g., optimizing a specific function's performance, which interlab already does).

### 3. The "Causes" Meta-Research Domain

The 5th Hyperspace domain ("Causes") is fundamentally different — it optimizes the research process itself:

| Sub-cause | What it optimizes |
|---|---|
| search-ranking | The search algorithm used by other agents |
| literature-analysis | How agents extract knowledge from papers |
| skill-forge | Creating new tools for agents to use |
| infra-optimization | Network/compute efficiency |
| data-curation | Quality of training data selection |

This is **self-improvement infrastructure** — agents making the agent system better.

**Demarch analog**: The Interverse already has the building blocks:
- interlab = the optimization loop itself (could self-optimize)
- interskill = skill quality audit (could audit *itself*)
- intercheck = code quality hooks (could improve *its own hooks*)
- interflux = multi-agent review (could review *its own agent definitions*)

**New bead opportunity**: A "meta-improvement" campaign where interlab optimizes its own benchmark scripts, interskill audits its own checklist, and interflux reviews its own triage logic.

### 4. Agent Brain ≠ Blind Mutation

The v2.1.32 changelog reveals the "agent brain" is more than a mutation engine:

```
CLI v2.1.32 (Mar 8, 2026)
- Added: Agent brain enabled by default (autonomous goal engine)
```

The agent brain has meta-reasoning about exploration strategy:
- Decides *which* mutation type to try next (not random)
- Determines when to stop exploring a dead-end
- Routes results through `Python subprocess → API → agent brain → GitHub`

**Implication**: Skaffen shouldn't just mutate blindly. The "Orient" phase should include **meta-reasoning about exploration strategy**: "I've tried 3 LR mutations with no improvement — switch to architecture mutations." This is the exploration-exploitation tradeoff from reinforcement learning, applied to code.

### 5. Adoption Velocity: ~1 Hour for Cross-Pollination

The overnight report data shows that innovations spread via GossipSub within **1-2 hours**, not days. This means the feedback loop has very low latency — agents can build on each other's discoveries in real time.

**Demarch equivalent**: The mutations store + interlock broadcast gives Skaffen instances a feedback loop, but the latency is session-scoped (only read at session start). For real-time cross-pollination, agents would need to check for new mutation records *during* their session, not just at start. The intermute WebSocket push (P2 bead) would enable this.

### 6. Metrics-Agnostic Leaderboard Pattern

The `build-leaderboard.js` script uses a clever pattern: each project defines its own metric extractor as a config object:

```javascript
const PROJECT_METRICS = {
  'astrophysics':       { field: 'valLoss',    dir: 'asc',  extract: d => d.result?.valLoss ?? d.valLoss ?? Infinity },
  'financial-analysis': { field: 'sharpeRatio', dir: 'desc', extract: d => d.sharpeRatio ?? d.result?.sharpeRatio ?? 0 },
  'search-engine':      { field: 'ndcg10',     dir: 'desc', extract: d => d.ndcg10 ?? d.result?.ndcg10 ?? 0 },
};
```

Key design decisions:
- **Fallback extraction** (`d.result?.valLoss ?? d.valLoss ?? Infinity`) handles schema evolution gracefully
- **Direction-aware sorting** (`asc` vs `desc`) lets the same code rank both "lower is better" and "higher is better"
- **Zero dependencies** — 139 lines of Node.js, uses only `child_process`, `fs`, `path`

**Demarch adoption**: This pattern maps directly to interlab's campaign configuration. A `campaign-leaderboard.sh` script could scan completed campaigns, extract best metrics, and emit a summary markdown — same pattern, different domain.

### 7. Workflow Cadence: 15-Minute CI, Not 6-Hour

The README says leaderboards update every 6 hours, but the GitHub Actions workflow actually runs every **15 minutes** (`cron: '*/15 * * * *'`). This means the leaderboard is near-real-time despite using GitHub Actions as the compute layer.

**Design insight**: Use fast CI cadence for observability artifacts even when the underlying data changes slowly. The cost is near-zero (Actions is free for public repos, each run takes <30 seconds).

### 8. Config Standardization via Template Inheritance

All 7 Hyperspace projects use a shared config pattern derived from `projects/_template/`:

```
projects/_template/
  README.md        — What to explore
  baseline/
    config.yaml    — Starting configuration
    results.json   — Baseline to beat
```

Projects override only what they need. ML projects share architecture/optimizer/schedule/training sections. Non-ML projects replace these with domain-specific sections. The `version: 1` field allows schema evolution.

**Demarch adoption**: interlab campaigns could adopt this template pattern:

```
interverse/interlab/campaigns/_template/
  README.md            — What to optimize
  baseline/
    config.json        — Starting configuration
    benchmark.sh       — Benchmark command
    results.json       — Baseline to beat
  CAMPAIGN-HISTORY.md  — Auto-generated from results.jsonl
```

### 9. The `inspiredBy` Field in Experiment Records

The results.json schema includes an `inspiredBy` field:

```json
{
  "hypothesis": "Try RMSNorm",
  "inspiredBy": "12D3KooWRx43",  // peer ID that inspired this hypothesis
  "isNewBest": true
}
```

This creates a **provenance graph** of ideas — you can trace which discoveries led to which improvements. When agent A's Kaiming init discovery inspires agent B's combined Kaiming+RMSNorm experiment, the `inspiredBy` field records that lineage.

**Demarch adoption**: The mutations store should include a `parent_session` or `inspired_by` field that links back to which previous session's approach was mutated. Combined with CASS session search, this creates a queryable genealogy of approaches.

### 10. Monotonic Progress Guarantees

The `isNewBest` flag in experiment records combined with the CRDT leaderboard creates a **monotonic improvement guarantee** — the global best can never regress. CRDTs ensure that if two agents simultaneously discover improvements, both are preserved and the better one wins.

**Demarch adaptation**: The mutations store should track `isNewBest` per task type. When the best approach for `bug-fix` has quality signal Q, a new approach only becomes the new best if it Pareto-dominates Q. This prevents regression while allowing multi-dimensional improvement.

---

## New Beads to Create from Extended Analysis

### P1 — Meta-improvement campaigns (Causes domain analog)

Agents improving the agent development toolchain:
- interlab optimizing its own benchmark scripts
- interskill auditing its own checklist
- interflux reviewing its own agent definitions

### P2 — Exploration-exploitation strategy in Skaffen Orient phase

Meta-reasoning about which mutation type to try next, based on recent history of successes/failures per type. If 3 consecutive mutations of type X failed, switch to type Y.

### P2 — `inspiredBy` provenance tracking in mutation records

Link each mutation to the parent session/approach that inspired it. Creates a queryable genealogy of approaches via CASS integration.

### P3 — Campaign template directory pattern

Standardize interlab campaigns with `_template/` containing README, baseline config, benchmark script, baseline results. Enable discovery of campaigns without reading interlab docs.

---

## Sources

- [Hyperspace AGI GitHub](https://github.com/hyperspaceai/agi)
- [Karpathy's Autoresearch](https://github.com/karpathy/autoresearch)
- [VentureBeat: Karpathy's autoresearch](https://venturebeat.com/technology/andrej-karpathys-new-open-source-autoresearch-lets-you-run-hundreds-of-ai)
- [MarkTechPost: AutoResearch in Google Colab](https://www.marktechpost.com/2026/03/12/how-to-build-an-autonomous-machine-learning-research-loop-in-google-colab-using-andrej-karpathys-autoresearch-framework-for-hyperparameter-discovery-and-experiment-tracking/)
- [The New Stack: Karpathy autonomous experiment loop](https://thenewstack.io/karpathy-autonomous-experiment-loop/)
- [Loro CRDT documentation](https://loro.dev/docs/concepts/crdt)
- [Go CRDT library](https://github.com/cshekharsharma/go-crdt)
- [OpenDiLoCo framework](https://www.primeintellect.ai/blog/opendiloco)
