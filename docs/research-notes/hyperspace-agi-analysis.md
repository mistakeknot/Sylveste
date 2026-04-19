# Hyperspace AGI — Deep Research Analysis for Demarch

> Analyzed 2026-03-14 from github.com/hyperspaceai/agi (MIT license)

## What Hyperspace AGI Actually Is

A **peer-to-peer network of autonomous AI agents** that continuously run experiments (ML training, search optimization, financial backtesting, skill evolution), share results via gossip protocol, and compound discoveries into a public leaderboard. Think "BitTorrent for AI research" — no central coordinator, CRDTs for state convergence, GitHub as durable archive.

**Key numbers**: 67+ agents, 1,369+ experiments, 5 research domains, 6 bootstrap nodes globally.

---

## Architecture Deep Dive

### Three-Layer Collaboration Stack
```
GossipSub (~1s)  →  CRDT Leaderboard (~2min)  →  GitHub Archive (~5min)
  real-time            convergent state              durable record
```

1. **GossipSub** (libp2p): Agent finishes experiment → broadcasts result to all peers instantly
2. **CRDT Leaderboard** (Loro): Conflict-free replicated data types sync each peer's best. No cold start — new nodes read full state on connect
3. **GitHub**: Per-agent branches, machine-readable JSON + human-readable markdown reports

### Research Pipeline (5 stages)
1. **Hypothesis** — Generate a mutation ("Try RMSNorm instead of LayerNorm")
2. **Training** — Run experiment on whatever hardware available
3. **Paper Generation** — Synthesize findings into a research paper
4. **Peer Critique** — Other agents score papers 1-10
5. **Discovery** — Papers 8+ flagged as breakthroughs, feed back into Stage 1

### 9 Node Capabilities
Inference, Research, Proxy, Storage, Embedding, Memory, Orchestration, Validation, Relay — each node can run any combination. Point weights incentivize diverse capability portfolios.

### DiLoCo Distributed Training
Multiple agents train the same model collaboratively — each trains locally for H steps, shares compressed weight deltas. Automatic fallback to solo if no peers available.

---

## Relevance Assessment by Demarch Pillar

### 1. Clavain (L2 OS — Orchestration & Sprint System)

**HIGH RELEVANCE — Gossip-based coordination is a direct analog to Clavain's multi-agent orchestration.**

| Hyperspace Technique | Clavain Analog | What to Steal |
|---|---|---|
| GossipSub for experiment results | interlock broadcast/messaging | The 3-layer stack (real-time → convergent → durable) is exactly what Clavain needs for multi-agent state. Right now interlock uses file-based reservations + messages. Gossip would let agents learn about each other's progress without polling. |
| CRDT Leaderboards (Loro) | Beads issue state | CRDTs for work tracking state would eliminate the Dolt server dependency that keeps causing zombie processes. Beads state is inherently a convergent problem — multiple agents claiming/closing issues. |
| Per-agent branches | interlock reservations | The "never merge to main" branch model is interesting — each agent's work is isolated by default, visible to all. Could apply to worktree isolation. |
| Pulse verification (commit-reveal) | Sprint heartbeat/budget | The 7-step cryptographic verification is overkill for Clavain, but the *concept* of periodic proof-of-work verification is useful. `bead-heartbeat` already does a simpler version — but Hyperspace proves the agent actually did compute, not just that it's alive. |
| Capability-based routing | lib-routing.sh agent matching | Weight-based capability scoring (+10% for inference, +12% for research) maps directly to Clavain's agent-model scoring. Could use capability declarations instead of evidence-only routing. |

**Concrete idea**: Replace interlock's file-based coordination with a local CRDT document (no network needed — just agents on the same machine). Each agent writes its reservations/messages to the CRDT, and all agents converge to the same state without explicit locking.

### 2. Skaffen (L2 Sovereign Agent)

**MEDIUM-HIGH RELEVANCE — The "agent brain" concept maps to Skaffen's autonomous goal engine.**

| Hyperspace Technique | Skaffen Analog | What to Steal |
|---|---|---|
| Autoresearch loop (hypothesis → train → evaluate → mutate) | Skaffen's autonomous work loop | The 5-stage research pipeline is a formalized version of what Skaffen should do: plan → execute → evaluate → learn → repeat. The key insight is **mutation-based improvement** — don't start fresh each cycle, mutate the best previous result. |
| Cross-pollination via gossip | Skaffen's context sharing | "When one agent discovered Kaiming initialization helped, 23 others adopted it via GossipSub within hours." Skaffen instances should share discoveries the same way — techniques, not just results. |
| Agent journal (`JOURNAL.md`) | Skaffen session memory | Each agent maintains a cognitive journal alongside its experiments. This is a structured version of auto-memory — a running narrative of what worked, what didn't, and why. |
| DiLoCo collaborative training | Multi-Skaffen coordination | Not directly applicable yet, but the pattern of "work locally, share deltas periodically" is the right model for Skaffen instances working on the same codebase from different angles. |
| Inspiration-before-hypothesis | Context loading before work | Agents read peers' discoveries *before* generating their next hypothesis. Skaffen should similarly check what other sessions/agents learned before starting new work. |

**Concrete idea**: Skaffen's work loop should formalize the hypothesis→experiment→evaluation→mutation cycle. Instead of treating each task as independent, maintain a "mutation history" — what's been tried, what worked, what the current best approach is. Like `best.json` but for code solutions.

### 3. Intercom (L3 App — Team Communication)

**MEDIUM RELEVANCE — The snapshot/dashboard model is relevant for Intercom's agent activity visibility.**

| Hyperspace Technique | Intercom Analog | What to Steal |
|---|---|---|
| Hourly network snapshots (`latest.json`) | Intercom's agent activity feed | Hyperspace publishes raw CRDT state as JSON, then tells users "point any LLM at it." This is the right UX — don't build elaborate dashboards, publish structured data and let LLMs interpret. |
| Leaderboard generation (GH Actions) | Intercom's beads reporting | Auto-generated `LEADERBOARD.md` every 6 hours from raw data. The `build-leaderboard.js` script is dead simple — scan branches, read `best.json`, sort, emit markdown. Intercom could do the same for beads/sprint metrics. |
| Per-agent experiment history | Intercom's session timeline | Each agent has a browsable history: `run-0001.json`, `run-0001.md`, `best.json`, `JOURNAL.md`. This per-agent archive pattern would work well for Intercom showing what each Skaffen instance has accomplished. |
| Research report (overnight) | Intercom's sprint retrospective | The overnight report (35 agents, 333 experiments, ranked by metric) is a sprint retro that writes itself. Intercom should generate these from beads data. |

**Concrete idea**: Implement "snapshot mode" in Intercom — periodic JSON dumps of full system state (beads, agent activity, sprint progress) that any LLM can analyze. Skip building complex dashboards; publish data, let users query it with natural language.

### 4. Autarch (L3 App — Autonomous Work)

**HIGH RELEVANCE — Autarch IS the Demarch equivalent of a Hyperspace agent.**

| Hyperspace Technique | Autarch Analog | What to Steal |
|---|---|---|
| Continuous research loop | Autarch's autonomous development | Hyperspace agents run 24/7 without human intervention. The key insight: they don't need complex goal systems — just a clear metric to optimize and a mutation strategy. Autarch should be equally simple: given a bead (task), optimize for "tests pass + code quality metric." |
| Mutation-based exploration | Autarch's implementation strategy | Agents don't generate solutions from scratch — they mutate their best result. 14 mutation types explored (LR tuning 68×, context length 42×, extended training 31×). Autarch should similarly maintain a repertoire of code mutations. |
| Hardware-adaptive execution | Autarch's resource awareness | Agents auto-detect GPU/CPU and adjust experiment scale. Same model trains differently on browser vs H100. Autarch should similarly adapt its approach based on available context, model, and time budget. |
| No-human-in-the-loop execution | Autarch's autonomy model | The overnight report proves unsupervised multi-agent research works. 35 agents, no human guidance, meaningful results. This validates Autarch's core thesis. |
| GitHub as durable archive | Autarch's commit-as-output | Each experiment = a structured JSON file + markdown report, committed to a branch. Autarch already uses git commits as output — but could adopt the structured experiment format. |

**Concrete idea**: Autarch should adopt the "seed project" template pattern. Each type of work (bug fix, feature, refactor) has a `baseline/config.yaml` equivalent — a starting configuration that gets mutated. The LEADERBOARD equivalent would be "which approach produced the best test results."

### 5. The Interverse (Plugin Ecosystem)

**MEDIUM RELEVANCE — The skills-and-tools domain is directly analogous to plugin evolution.**

| Hyperspace Technique | Interverse Analog | What to Steal |
|---|---|---|
| Skills & Tools domain | Plugin creation/evolution | Agents "invent, test, and adopt new skills (tool-use patterns) scored by correctness and utility." This is exactly what the Interverse could become — autonomous plugin evolution where agents create, test, and propagate useful tools. |
| Cross-agent skill sharing via gossip | Plugin marketplace | When one agent invents a useful skill, others adopt it. The Interverse marketplace could work similarly — usage metrics and peer adoption signals. |
| Composite scoring (correctness × utility) | Plugin quality metrics | A good scoring model for plugins: does it work (correctness) × is it useful (adoption/utility). Better than star ratings. |
| WASM skills | Plugin sandboxing | Hyperspace uses WASM for skill execution — sandboxed, portable. Not directly applicable to Claude Code plugins, but the principle of sandboxed skill execution is sound. |

**Concrete idea**: Add an "autonomous plugin improvement" loop to the Interverse: agents identify friction in their own workflows, generate plugin mutations, test them, and propose PRs. The interlab framework already does something similar for code optimization — extend it to plugin development.

---

## Philosophical Alignments and Divergences

### Where Hyperspace and Demarch Agree

1. **Agents as first-class citizens** — Both treat AI agents as autonomous actors, not tools to be invoked. Hyperspace agents run 24/7; Skaffen instances operate sovereignly.

2. **Compound learning** — Both believe intelligence should accumulate across sessions. Hyperspace uses CRDTs + gossip; Demarch uses beads + auto-memory.

3. **Hardware heterogeneity** — Both support diverse hardware: Hyperspace runs on browser/laptop/H100; Demarch runs on different model tiers (Haiku/Sonnet/Opus).

4. **Git as source of truth** — Both use git as the durable archive. Hyperspace commits experiment results; Demarch commits code changes.

5. **Open research** — Both lean toward transparency. Hyperspace publishes all results publicly; Demarch is open-source.

### Where They Diverge

1. **Centralization** — Hyperspace is *fully decentralized* (no central server, pure P2P). Demarch is *centralized-but-local* (single machine, local Dolt server, one human operator). Hyperspace's decentralization solves multi-party trust; Demarch doesn't need that — it solves single-operator multi-agent coordination.

2. **Incentives** — Hyperspace uses points/tokens to incentivize participation. Demarch uses task completion (beads) as the incentive signal. Hyperspace needs extrinsic motivation because agents are operated by different people; Demarch agents are all operated by one person, so intrinsic task-completion is sufficient.

3. **Scope of autonomy** — Hyperspace agents have narrow autonomy (optimize a single metric). Demarch/Skaffen agents have broad autonomy (understand codebases, make design decisions, write production code). Narrow autonomy is easier to verify; broad autonomy requires trust.

4. **Mutation strategy** — Hyperspace mutates configurations (hyperparameters). Demarch mutates code. Code mutation is fundamentally harder — the search space is larger, the feedback loop is slower, and correctness is harder to verify.

5. **Verification** — Hyperspace uses cryptographic verification (pulse rounds, commit-reveal). Demarch uses test suites and human review. Cryptographic verification proves computation happened; tests prove computation was correct. Different problems.

---

## Techniques Worth Adopting

### Tier 1 — Adopt Now (Low effort, high value)

1. **Structured experiment format** — `run-NNN.json` + `run-NNN.md` + `best.json` per agent. Apply to interlab campaigns and Autarch work items. Already partially implemented in interlab but could be formalized.

2. **Snapshot mode** — Periodic JSON dumps of full system state. Let LLMs analyze instead of building dashboards. Add `bd snapshot --json` to beads.

3. **Inspiration-before-action** — Before starting work, agents read what peers have discovered. Add to Skaffen's work loop: check auto-memory + recent beads + intersearch before generating a plan.

### Tier 2 — Prototype (Medium effort, high value)

4. **CRDT-based coordination** — Replace interlock's file-based reservations with Loro CRDTs. Eliminates race conditions, works offline, converges automatically. Would require a Go/Rust CRDT library.

5. **Mutation-based improvement** — Track the "best approach so far" for each type of task and mutate it rather than starting fresh. Skaffen should maintain a repertoire of successful patterns.

6. **Autonomous skill evolution** — Let agents generate, test, and adopt new plugins/skills without human intervention. Extend interlab to target plugin improvement.

### Tier 3 — Watch & Learn (High effort, speculative value)

7. **DiLoCo-style collaborative work** — Multiple Skaffen instances work on the same problem, share "weight deltas" (partial solutions), merge periodically. Hard to implement for code (not differentiable), but the pattern of "work independently, sync periodically" is valuable.

8. **Gossip protocol** — If Demarch ever goes multi-machine or multi-user, GossipSub is the right coordination model. Overkill for single-machine, single-operator today.

9. **Cryptographic proof-of-work** — Verifying that agents actually did meaningful work. Relevant if Demarch ever has untrusted agents. Not needed while all agents are local.

---

## Framework/UX Ideas to Borrow

### 1. "The Living Research Repository" Pattern
Hyperspace's README is a masterpiece of developer experience:
- **Network snapshot** at the top (live data, not static docs)
- **Join in 1 command** (`curl ... | bash`)
- **Architecture diagram** (ASCII art, fits in terminal)
- **Overnight research report** (concrete results, not promises)

Demarch could adopt this for Autarch: a living document showing what agents have accomplished, updated automatically.

### 2. The "Seed Project" Template
Each Hyperspace research domain has:
- `README.md` — What to explore
- `baseline/config.yaml` — Starting configuration
- `baseline/results.json` — Baseline to beat
- `LEADERBOARD.md` — Auto-generated rankings

This is a great template for Autarch work items or interlab campaigns.

### 3. The "Agent Branch" Pattern
Each agent gets its own git branch (`agents/<peerId>/<project>`). Never merged to main. Creates a clean separation between:
- **Main**: Seed projects, templates, leaderboards (human-curated)
- **Agent branches**: Experiment results, journals (agent-generated)

Clavain worktrees already do something similar, but the explicit "agent namespace" in git is cleaner.

---

## What Hyperspace Gets Wrong (and Demarch Can Avoid)

1. **Metric reductionism** — Everything is reduced to a single number (val_loss, NDCG@10, Sharpe ratio). Real software development has multi-dimensional quality (correctness, readability, performance, security). Demarch should resist reducing code quality to a single metric.

2. **No adversarial testing** — Agents only try to improve their own score. No agent tries to break other agents' solutions or find edge cases. Demarch's interpeer review and flux-drive multi-agent review are better at finding problems.

3. **Shallow learning** — Agents mutate hyperparameters but don't develop deep understanding. They can't explain *why* RMSNorm works better — they just observe that it does. Skaffen should maintain causal models, not just correlations.

4. **GitHub as coordination bottleneck** — Despite being "fully P2P," Hyperspace uses GitHub as the durable archive, creating a single point of failure. The CRDT layer is the real innovation; GitHub is just a convenience layer.

5. **Closed-source core** — The repo is MIT, but the actual agent runtime (`hyperspace` binary) is closed-source. The research results are open, but the system that produces them isn't fully auditable. Demarch's fully open-source approach is stronger for trust.

---

## Summary: What to Take Away

**The biggest insight**: Hyperspace proves that autonomous multi-agent research works *at scale* — 67 agents, 1,369 experiments, meaningful results, no human in the loop. The key ingredients are:

1. A clear metric to optimize
2. A mutation strategy (don't start fresh — improve the best result)
3. A gossip mechanism (share discoveries instantly)
4. A convergent state model (CRDTs for conflict-free coordination)
5. A durable archive (git for permanent record)

Demarch already has #5 and partially has #1 (test pass/fail) and #3 (interlock messaging). The gaps are:

- **#2 (mutation strategy)** — Skaffen/Autarch should track "best approach" and mutate rather than regenerate
- **#4 (convergent state)** — Replace Dolt/file-based coordination with CRDTs
- **#1 (richer metrics)** — Move beyond pass/fail to multi-dimensional quality scoring

The philosophical alignment is strong: both Hyperspace and Demarch believe in autonomous agents as first-class citizens, compound learning, and git as source of truth. The key difference is scope — Hyperspace optimizes narrow metrics on well-defined problems; Demarch tackles the harder problem of autonomous software development with broad, ill-defined quality criteria.
