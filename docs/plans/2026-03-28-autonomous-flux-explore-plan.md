---
bead: sylveste-d39
title: "Plan: Autonomous flux-gen semantic space exploration"
date: 2026-03-28
type: plan
revised: true
revision_reason: "Plan review: separate command (not mode flag), synthesis reads JSON specs (not .md), upfront confirmation, tighter anti-clustering"
---

# Plan: Autonomous Flux-Gen Semantic Space Exploration (Revised)

## Summary

New `/flux-explore` command (separate from flux-gen) that automates multi-round semantic space exploration with synthesis. 1 new command file + no script changes (pure prompt orchestration).

## Key Revisions from Plan Review

- **Separate command** (`flux-explore`) instead of `--mode=explore` flag — different loop shape from flux-gen's one-shot skeleton
- **Synthesis reads JSON specs**, not generated .md files — exploration metadata (source_domain, expected_isomorphisms) lives only in specs
- **No generate-agents.py changes** — exploration fields stay in JSON specs for synthesis; no `## Exploration Context` section, no version bump
- **Hard-coded defaults** (3 rounds, 5 agents) with override flags as escape hatches
- **Upfront confirmation gate** showing full plan shape before any writes

## Tasks

### Task 1: Create flux-explore command
**File:** `interverse/interflux/commands/flux-explore.md`

**Step 0: Parse Arguments**
- Extract target description from `$ARGUMENTS`
- Accept optional `--rounds=N` (default 3), `--agents-per-round=N` (default 5)
- If target is empty, derive from project context (same as flux-gen Step 0)

**Step 1: Confirm**
- AskUserQuestion with plan shape:
  ```
  Explore semantic space for: {target}
  Rounds: {N} × {M} agents = up to {N×M} agent files

  Round 1: Domain-appropriate agents (standard flux-gen)
  Rounds 2+: Maximally distant domains with structural isomorphism search
  Final: Cross-domain synthesis document

  Proceed? [Yes / Adjust rounds / Cancel]
  ```

**Step 2: Round 1 — Seed**
- Display: `Round 1/{N}: Generating domain-appropriate agents...`
- Use standard flux-gen Step 1 design prompt (with severity_examples from sylveste-pkx)
- Save specs to `flux-gen-specs/{slug}-round-1.json`
- Run generate-agents.py with `--mode=skip-existing`
- Collect generated agent names + focus descriptions for next round context

**Step 3: Rounds 2..N — Explore**
For each round R:
- Display: `Round {R}/{N}: Exploring distant domains...`
- Launch Sonnet subagent with exploration prompt:

```
You are exploring the semantic space of knowledge domains to find structural
isomorphisms relevant to: {target}

Domains already covered (do not repeat these or closely adjacent fields):
{accumulated_agent_name}: {focus} (source: {source_domain or "standard"})
...

Severity reference:
- P0: Blocks other work or causes data loss/corruption. Drop everything.
- P1: Required to exit the current quality gate.
- P2: Degrades quality or creates maintenance burden.
- P3: Improvements and polish.

Design {M} review agents from domains MAXIMALLY DISTANT from all prior coverage.

Selection constraints:
- Each domain must come from a different field, era, or modality than any prior domain
- DO NOT use common AI-analogy domains: biology, military, sports, information theory,
  thermodynamics, ecology, evolutionary biology, game theory, economic markets
- PREFER: pre-modern craft disciplines, physical processes at non-human scales,
  non-Western knowledge systems, professional practices with centuries of refinement
- Each domain must have rich internal structure that maps to {target}'s concerns

For each agent, output a JSON object with standard fields (name, focus, persona,
decision_lens, review_areas, severity_examples, success_hints, task_context,
anti_overlap) PLUS these exploration fields:
- source_domain: the real-world knowledge domain (e.g., "physical oceanography")
- distance_rationale: 1 sentence — why is this distant from all prior coverage?
- expected_isomorphisms: 1-2 sentences — what structural parallels do you expect to find?

Design rules:
- Agent names: fd-{domain-noun}-{concern} (e.g., fd-perfumery-accord)
- severity_examples must be concrete and domain-specific
- expected_isomorphisms must name specific mechanisms, not vague analogies
- anti_overlap entries should reference other agents in THIS round by name

Return ONLY a valid JSON array of objects. No markdown, no explanation.
```

- Save specs to `flux-gen-specs/{slug}-round-{R}.json`
- Run generate-agents.py with `--mode=skip-existing`
- If any agents skipped (name collision), log: `NOTE: {name} already exists, skipped`
- Accumulate new agents into coverage context for next round

**Step 4: Synthesize**
- Display: `Synthesizing cross-domain findings from {total} agents across {N} rounds...`
- Read all round spec files: `flux-gen-specs/{slug}-round-*.json`
- Launch Sonnet subagent with synthesis prompt:

```
You are synthesizing cross-domain structural isomorphisms from a multi-round
semantic space exploration about: {target}

The exploration generated {total} agents across {N} rounds, each round drawing
from progressively more distant knowledge domains.

Agent specs (JSON):
{all_specs_from_all_rounds}

Produce a brainstorm document with these sections:

## Per-Domain Highlights
For each source_domain, 2-3 key structural insights and the specific mechanism
that could transfer to {target}. Name the agent (e.g., fd-perfumery-accord).

## Cross-Domain Structural Isomorphisms
Patterns that appear independently in 2+ unrelated domains. These are the
highest-value findings — they suggest deep structural truths, not surface analogies.
For each isomorphism, name the domains and agents that independently suggest it.

## Novel Mechanism Transfers
Specific, implementable mechanisms from distant domains that could be adopted.
Each must include: source domain, mechanism name, how it maps, and which
component of {target} it would modify. Be concrete — name files or modules.

## Open Questions
Domains or angles not yet explored that the synthesis suggests would be productive
for a future exploration round. Include the expected value of exploring each.

Write in direct, technical prose. Reference agents by name (e.g., fd-tidal-resonance).
Do not summarize — synthesize. Find the patterns the individual agents cannot see alone.
```

- Write synthesis to `docs/brainstorms/{date}-flux-explore-{slug}.md` with frontmatter:
  ```yaml
  artifact_type: brainstorm
  bead: {bead_id if set}
  method: flux-explore
  rounds: {N}
  total_agents: {count}
  ```

**Step 5: Report**
```
Exploration complete: {total} agents across {N} rounds.

Round 1: {names} (domain-appropriate)
Round 2: {names} (distant domains)
Round 3: {names} (maximally distant)

Synthesis: docs/brainstorms/{date}-flux-explore-{slug}.md
Specs: .claude/flux-gen-specs/{slug}-round-{1..N}.json

To activate these agents in a review: /flux-drive <target>
To regenerate without LLM: /flux-gen --from-specs .claude/flux-gen-specs/{slug}-round-N.json
```

### Task 2: Register command in plugin manifest
**File:** `interverse/interflux/.claude-plugin/plugin.json`
**Change:** Add `flux-explore` to commands list (if not auto-discovered).

### Task 3: Validate end-to-end
**Action:**
1. Run `/flux-explore "Review of interflux agent architecture" --rounds=2 --agents-per-round=3`
2. Verify upfront confirmation shows plan shape
3. Verify Round 1 produces standard agents, Round 2 produces distant-domain agents with exploration metadata in specs
4. Verify synthesis document exists with cross-domain isomorphisms
5. Compare synthesis against garden-salon brainstorm — at least 1 named mechanism transfer

## Execution Order

Task 1 (command) → Task 2 (manifest) → Task 3 (validate)

## Deferred

- Embedding-based distance verification
- Novelty-based stopping criteria
- Budget integration with interstat
- Auto-running flux-drive per round
- Lightweight interrupt before final round (showing proposed domains)
- `## Exploration Context` section in generated .md files (no current consumer)

## Original Intent (cut from plan review)

- `--mode=explore` flag on flux-gen — replaced with separate command (different loop shape)
- generate-agents.py changes for exploration fields — unnecessary (synthesis reads JSON specs)
- Version bump for exploration context — unnecessary (no template change)
