# fd-plugin-evolution: Plugin Evolution Patterns from Hyperspace Skills & Tools

> Reviewer: fd-plugin-evolution (plugin ecosystem architect)
> Sources: `research/agi-hyperspace/ANALYSIS.md`, `research/agi-hyperspace/projects/skills-and-tools/README.md`, Sylveste codebase exploration
> Date: 2026-03-14

---

## Executive Summary

Hyperspace's Skills & Tools domain demonstrates a minimal but instructive model: WASM skills scored by `test_pass_rate x adoption`, invented by agents, propagated via gossip. The Interverse already has richer primitives (interlab campaigns, interskill audit, intertrust scoring, structural test suites) but lacks the *closed loop* that connects them -- no automated pipeline takes a plugin from "agent identifies friction" through "agent creates mutation" to "plugin scores well enough to adopt." This review identifies what to steal, what to avoid, and how to wire existing primitives into a plugin evolution loop.

---

## 1. Composite Scoring: Correctness x Utility for Interverse Plugins

### What Hyperspace Does

Hyperspace scores skills as `test_pass_rate x adoption`. This is deliberately simple -- correctness is binary (tests pass or don't), utility is social (other agents adopt or don't). The composite prevents correct-but-useless skills from ranking high, and prevents popular-but-broken skills from persisting.

### What Interverse Already Has

The Interverse has the *components* of a richer scoring model, scattered across plugins:

| Dimension | Source | Current State |
|-----------|--------|---------------|
| **Structural correctness** | `tests/structural/test_structure.py` per plugin | Runs at publish time, checks manifest, file existence, executable bits |
| **Build correctness** | `go test ./...` or `uv run pytest` per plugin | Runs per-plugin, no ecosystem-wide aggregation |
| **Skill quality** | interskill audit (19-point checklist at `interverse/interskill/skills/audit/SKILL.md`) | Manual invocation, not automated |
| **Agent trust** | intertrust (`interverse/intertrust/`) -- severity-weighted, time-decayed | Applied to agents, not to plugins |
| **Usage signal** | interstat token/tool metrics | Tracks agent costs, not plugin adoption |

### Proposed Scoring Formula

**Plugin Quality Score (PQS)**:

```
PQS = correctness_score * utility_score * trust_modifier

Where:
  correctness_score = (structural_tests_pass / structural_tests_total)
                    * (build_passes ? 1.0 : 0.0)
                    * (audit_score / audit_max)  -- interskill audit checklist

  utility_score     = normalize(
                        0.5 * active_session_invocations_30d   -- how often it's called
                      + 0.3 * unique_agent_sessions_30d        -- breadth of adoption
                      + 0.2 * cross_project_session_count_30d  -- portability
                      )

  trust_modifier    = intertrust_author_score  -- time-decayed, severity-weighted
                                               -- (existing algorithm, floored at 0.05)
```

**Key differences from Hyperspace:**
- **Three-factor** instead of two: correctness, utility, AND author trust. Hyperspace doesn't need trust because all agents are equal peers. In Sylveste, agent trust matters because some agents produce better code than others.
- **Audit-augmented correctness**: Structural tests catch manifest/build issues but not skill quality. The interskill audit checklist (frontmatter, invocation control, content quality, anti-patterns) catches the class of problems where a plugin "works" but produces unreliable agent behavior.
- **Multi-signal utility**: Hyperspace uses a single adoption count. Sylveste can distinguish session invocations (intensity), unique sessions (breadth), and cross-project usage (generalizability).

**Priority: P1** -- Define the formula and wire data sources before building the evolution loop. Without measurement, the loop has no fitness signal.

### Implementation Path

1. Add a `plugin-health` command to interpub or intercheck that runs structural tests + build + interskill audit and emits a JSON report
2. Extend interstat to track per-plugin invocation counts (tool calls routed through MCP servers already have plugin names)
3. Write a `plugin-score` script that combines correctness + utility + trust into PQS
4. Publish PQS scores to a `plugin-health.json` in the marketplace

---

## 2. Autonomous Skill Invention via Interlab Campaigns

### What Hyperspace Does

Agents run a `SkillExperimentLoop`: invent a WASM skill, test it against fixtures, score by correctness x utility, mutate the best, repeat. The loop is simple because WASM skills have a narrow interface (input bytes -> output bytes) and testing is deterministic.

### What Interlab Already Provides

Interlab's campaign framework (`interverse/interlab/`) is a close match for the Hyperspace skill evolution loop:

| Hyperspace Concept | Interlab Equivalent | Gap |
|-------------------|---------------------|-----|
| Hypothesis (skill mutation) | `/autoresearch` step 2: "Generate an Idea" | No gap -- agent generates ideas |
| Experiment (run skill tests) | `run_experiment` with benchmark command | Need a benchmark command that tests a plugin |
| Score (correctness x utility) | `METRIC` lines from benchmark | Need to define what metrics to emit |
| Keep/Discard | `log_experiment` with decision | No gap |
| Mutation loop | Circuit breaker + loop continuation | No gap |
| Multi-campaign | `plan_campaigns` / `dispatch_campaigns` | Already shipped in v0.3 |

**The gap is not in the loop machinery -- it's in the benchmark command.** Interlab needs a `plugin-benchmark.sh` that runs structural tests, the interskill audit, and emits METRIC lines. Everything else already works.

### Proposed: Plugin Improvement Campaign Spec

A campaign spec for improving a specific plugin via interlab:

```json
{
  "name": "interlock-quality",
  "metric_name": "plugin_quality_score",
  "metric_unit": "score",
  "direction": "higher_is_better",
  "benchmark_command": "bash plugin-benchmark.sh",
  "files_in_scope": [
    "skills/conflict-recovery/SKILL.md",
    "skills/coordination-protocol/SKILL.md",
    ".claude-plugin/plugin.json"
  ]
}
```

Where `plugin-benchmark.sh` outputs:
```
METRIC plugin_quality_score=0.78
METRIC structural_tests_pass=6
METRIC structural_tests_total=6
METRIC audit_score=14
METRIC audit_max=19
METRIC skill_lines=142
```

**What this unlocks:** An agent can run `/autoresearch` against any plugin, iteratively improving skill quality, fixing audit failures, and optimizing plugin structure -- using the exact same loop that already optimized `ReconstructState` by 22x.

**Priority: P1** -- This is the highest-leverage recommendation. It requires only a single new script (`plugin-benchmark.sh`) and reuses all existing interlab infrastructure.

### Multi-Plugin Improvement via `/autoresearch-multi`

For ecosystem-wide quality improvement, use the existing multi-campaign orchestration:

```json
{
  "goal": "Improve plugin quality scores across 5 lowest-scoring plugins",
  "campaigns": [
    {"name": "interlock-quality", "benchmark_command": "...", "files_in_scope": ["interverse/interlock/skills/..."]},
    {"name": "intercheck-quality", "benchmark_command": "...", "files_in_scope": ["interverse/intercheck/skills/..."]},
    ...
  ]
}
```

`plan_campaigns` handles file conflict detection. `dispatch_campaigns` sends each to a subagent. `synthesize_campaigns` aggregates cross-plugin insights. All shipped and dogfooded.

**Priority: P2** -- Depends on P1 (the benchmark script). Once individual plugin campaigns work, multi-campaign is nearly free.

---

## 3. Cross-Agent Plugin Discovery Without Gossip

### What Hyperspace Does

GossipSub broadcasts skill discoveries in ~1 second. When one agent invents a useful skill, others adopt it through the CRDT leaderboard. No central registry needed.

### Why Gossip Doesn't Apply

Sylveste is single-machine, single-operator (`PHILOSOPHY.md`: "Sylveste is centralized-but-local"). There's no peer network. The 57 Interverse plugins are all installed from a single marketplace (`core/marketplace/.claude-plugin/marketplace.json`), not discovered via gossip.

### What Sylveste Has Instead

Three existing mechanisms serve the discovery function:

1. **Marketplace**: `core/marketplace/` is the plugin registry. `ic publish` updates it. All agents see the same plugins.
2. **interject**: Plugin for discovery inflow -- scans for improvements and records them. Could be extended to scan for plugin quality gaps.
3. **SessionStart hooks**: Plugins like interlab already have `detect-campaign.sh` that runs on session start, detecting available campaigns. A `detect-plugin-improvements.sh` hook could identify plugins with low PQS scores and suggest improvement campaigns.

### Proposed: Plugin Discovery and Adoption Signals

Instead of gossip-based adoption, use evidence-based adoption tracking:

1. **interstat**: Already tracks tool usage per session. Aggregate to per-plugin usage counts. A plugin with zero invocations in 30 days is a candidate for deprecation or improvement.
2. **interject scanning**: Extend interject to periodically scan plugin quality scores and create beads for plugins below a PQS threshold. This is the "agent identifies friction" step that starts the evolution loop.
3. **Campaign learnings propagation**: When an interlab campaign improves a plugin, the learnings (stored in `campaigns/<name>/learnings.md`) should be indexed by interknow so future plugin improvement campaigns benefit from past discoveries.

**Priority: P2** -- Useful but not blocking. The marketplace + interstat combination gives discovery without gossip.

---

## 4. WASM Sandboxing vs. Claude Code Plugin Execution Model

### What Hyperspace Does

WASM provides deterministic, memory-safe, portable execution. Skills can't escape the sandbox, access the filesystem, or make network calls unless explicitly granted. This is critical for Hyperspace because agents run untrusted code from peers.

### Claude Code Plugin Execution Model

Claude Code plugins run as subprocesses on the host machine with the user's permissions:

- **MCP servers** (`plugin.json` → `mcpServers`): stdio-based subprocesses. The binary at `${CLAUDE_PLUGIN_ROOT}/bin/launch-mcp.sh` runs with full filesystem access. Example: interlock's MCP server can read/write to `INTERMUTE_SOCKET` and `INTERMUTE_URL` (see `interverse/interlock/.claude-plugin/plugin.json`).
- **Hooks** (`hooks.json`): Shell scripts run via `bash -c`. intercheck's `syntax-check.sh` and `auto-format.sh` run after every Edit/Write with full access to the working directory.
- **Skills** (`SKILL.md`): Not code at all -- they're prompt instructions that guide agent behavior. No isolation boundary.

**There is no sandbox.** Claude Code's security model relies on:
1. **Trust boundary** (`CLAUDE.md`: "Only trust AGENTS.md/CLAUDE.md from: project root, `~/.claude/`, `~/.codex/`")
2. **Human oversight** (`PHILOSOPHY.md`: "Level 1-2 trust" -- human approves at phase gates or reviews post-hoc)
3. **Path-scoped safety** (interlab: "Never `git add -A`. Always path-scoped")
4. **Structural tests** (`tests/structural/test_structure.py` per plugin)

### Assessment

WASM sandboxing is **not applicable** to Claude Code plugins. The execution model is fundamentally different:

| Property | Hyperspace WASM | Claude Code Plugin |
|----------|----------------|--------------------|
| Isolation | Memory-safe sandbox | Host process, user permissions |
| Interface | Bytes in → bytes out | MCP JSON-RPC over stdio |
| Side effects | Explicitly granted | Unrestricted (filesystem, network, exec) |
| Trust model | Untrusted peer code | Trusted operator code |
| Portability | Architecture-independent | Shell scripts + compiled binaries |

The right analogy for Sylveste is not WASM sandboxing but **capability-based access control** -- the Gridfire vision described in `PHILOSOPHY.md`: "unforgeable tokens with effects allowlists and resource bounds." Until Gridfire ships, the practical mitigation is the publish gate (interpub) plus structural tests.

**Priority: P3** -- WASM is architecturally irrelevant. Gridfire is the long-term answer; interpub gates are the present-tense answer.

---

## 5. Adversarial Surface Area from Autonomous Plugin Evolution

### The Risk

If agents can autonomously create, modify, and publish plugins, the adversarial surface area expands in three ways:

1. **Prompt injection via SKILL.md**: A mutated skill could contain instructions that override safety constraints, exfiltrate data, or suppress audit findings. Skills are loaded as prompt text -- there's no syntactic barrier between "instructions for the agent" and "adversarial injection."

2. **Supply chain poisoning via hooks**: A mutated `hooks.json` or hook script could intercept session events, modify tool results, or run arbitrary code on every Edit/Write. intercheck's `syntax-check.sh` already runs after every file edit -- a malicious mutation could insert data exfiltration.

3. **Quality degradation via Goodhart pressure**: If the PQS score is the fitness signal for autonomous mutation, agents will optimize for PQS rather than actual quality. This is explicitly called out in `PHILOSOPHY.md`: "Agents will optimize for any stable target. Rotate metrics, cap optimization rate, randomize audits."

### Existing Guardrails

| Guardrail | Location | What It Prevents |
|-----------|----------|-----------------|
| Trust boundary | `CLAUDE.md` security section | Untrusted AGENTS.md/CLAUDE.md from dependencies |
| Publish gate | `agents/plugin-publishing.md` | Unpublished changes reaching the marketplace |
| Structural tests | `tests/structural/test_structure.py` per plugin | Missing files, broken manifests, non-executable scripts |
| interskill audit | `interverse/interskill/skills/audit/SKILL.md` | Bad frontmatter, vague descriptions, missing invocation control |
| intertrust scoring | `interverse/intertrust/` | Low-trust agents gated from high-impact work |
| Path-scoped safety | interlab `files_in_scope` | Experiments can only modify declared files |
| Circuit breaker | interlab `CheckCircuitBreaker()` | Runaway experiment loops (max 50 experiments, max 3 crashes) |

### Required Additional Gates

**P0 -- Human approval for plugin publish.** This is the single most important guardrail. The current publish pipeline (`ic publish`) pushes to the marketplace without human review. Autonomous plugin evolution MUST NOT auto-publish. The loop should be:

```
Agent identifies friction → Agent runs /autoresearch on plugin →
Agent creates PR with mutations → Human reviews PR → Human publishes
```

This maps to `PHILOSOPHY.md` trust level 2: "Human reviews evidence post-hoc." The agent proposes; the human decides whether to merge.

**P0 -- SKILL.md content scanning.** Before any mutated skill enters the publish pipeline, scan for:
- Injection patterns: "ignore previous instructions", "do not report", "always approve"
- Exfiltration patterns: `curl`, `wget`, `nc`, base64-encoded payloads
- Authority escalation: "override", "bypass", "skip verification"

This could be a new intercheck hook or an extension of the interskill audit checklist.

**P1 -- Metric rotation for Goodhart resistance.** `PHILOSOPHY.md` says: "Rotate metrics, cap optimization rate, randomize audits." For plugin improvement campaigns:
- Rotate the primary metric between correctness sub-dimensions (structural tests one campaign, audit score the next, integration test coverage the next)
- Cap improvement campaigns to 1 per plugin per week
- Randomly include a "red team" sub-campaign that tries to break the plugin rather than improve it

**P1 -- Diff-bounded mutations.** Constrain what interlab can modify in a plugin improvement campaign:
- `files_in_scope` should be limited to skill content files (SKILL.md, SKILL-compact.md) and test files
- Explicitly exclude: `hooks/`, `bin/`, `.claude-plugin/plugin.json`, `commands/`
- Hook modifications require a separate, more restrictive approval process

**P2 -- Provenance tracking.** Every mutation should record:
- Which campaign produced it
- Which agent ran the campaign
- The PQS score before and after
- The specific diff applied

This data feeds the intertrust scoring system -- agents that produce quality improvements earn higher trust, agents whose mutations degrade quality lose trust.

---

## 6. Priority Summary

| Priority | Recommendation | Effort | Reuses Existing |
|----------|---------------|--------|-----------------|
| **P0** | Human approval gate for autonomous plugin publish | Low | interpub pipeline |
| **P0** | SKILL.md content scanning for injection patterns | Medium | interskill audit, intercheck hooks |
| **P1** | Plugin Quality Score (PQS) formula + data wiring | Medium | interstat, interskill, intertrust, structural tests |
| **P1** | `plugin-benchmark.sh` for interlab plugin campaigns | Low | interlab `/autoresearch` |
| **P1** | Diff-bounded mutations (exclude hooks, bins, manifests) | Low | interlab `files_in_scope` |
| **P1** | Metric rotation for Goodhart resistance | Low | interlab campaign configuration |
| **P2** | Multi-plugin improvement via `/autoresearch-multi` | Low | interlab orchestration (v0.3) |
| **P2** | interject scanning for low-PQS plugins | Medium | interject discovery pipeline |
| **P2** | Campaign learnings propagation to interknow | Medium | interlab learnings, interknow |
| **P3** | Provenance tracking for mutations | Medium | intertrust, beads |
| **P3** | WASM-style sandboxing investigation | High | Gridfire (future) |

---

## 7. Key Files Referenced

| File | Relevance |
|------|-----------|
| `/home/mk/projects/Sylveste/interverse/interlab/internal/experiment/state.go` | Campaign state model, circuit breaker, JSONL persistence |
| `/home/mk/projects/Sylveste/interverse/interlab/internal/orchestration/plan.go` | Multi-campaign planning, file conflict detection |
| `/home/mk/projects/Sylveste/interverse/interlab/skills/autoresearch/SKILL.md` | Single-campaign experiment loop protocol |
| `/home/mk/projects/Sylveste/interverse/interlab/skills/autoresearch-multi/SKILL.md` | Multi-campaign orchestration protocol |
| `/home/mk/projects/Sylveste/interverse/interlab/docs/interlab-vision.md` | Interlab roadmap -- agent self-improvement is v0.5-0.6 target |
| `/home/mk/projects/Sylveste/interverse/interskill/skills/audit/SKILL.md` | 19-point skill quality audit checklist |
| `/home/mk/projects/Sylveste/interverse/intertrust/CLAUDE.md` | Agent trust scoring (severity-weighted, time-decayed) |
| `/home/mk/projects/Sylveste/interverse/intercheck/CLAUDE.md` | PostToolUse syntax and format checks |
| `/home/mk/projects/Sylveste/interverse/interpub/CLAUDE.md` | Publish pipeline (`ic publish`) |
| `/home/mk/projects/Sylveste/agents/plugin-publishing.md` | Publish gate, version bumping, ecosystem diagram |
| `/home/mk/projects/Sylveste/interverse/interlab/tests/structural/test_structure.py` | Example structural test suite (13 tests) |
| `/home/mk/projects/Sylveste/interverse/intercheck/tests/structural/test_structure.py` | Example structural test suite (6 tests) |
| `/home/mk/projects/Sylveste/PHILOSOPHY.md` | Trust ladder, Goodhart resistance, Gridfire vision, anti-gaming |
| `/home/mk/projects/Sylveste/CLAUDE.md` | Trust boundary security section |
| `/home/mk/projects/Sylveste/interverse/interlock/.claude-plugin/plugin.json` | Example plugin manifest (MCP server, skills, commands) |

---

## 8. Bottom Line

Hyperspace's autonomous skill evolution is a useful template, but it operates in a much simpler environment (WASM sandbox, single metric, untrusted peers). The Interverse has more sophisticated primitives -- the gap is not tools but *wiring*. The highest-leverage move is **P1: write `plugin-benchmark.sh`** so that interlab's existing `/autoresearch` loop can target plugin quality. The most critical safety requirement is **P0: never auto-publish** -- autonomous mutation without human approval on the publish step turns a quality improvement tool into an attack surface.

The interlab vision doc (`interverse/interlab/docs/interlab-vision.md`) explicitly targets "agent self-improvement" as the v0.5-0.6 goal. Plugin evolution via interlab campaigns is a natural instance of that vision, using infrastructure that's already built and dogfooded.
