### Findings Index
- P1 | JGC-1 | "Current Cost Model" | All agents run at uniform model tier — colotomic structure absent
- P1 | JGC-2 | "Cross-model dispatch" | Irama tier shift is partial: tier changes within Claude family only, no cross-family coordination
- P2 | JGC-3 | "Current Architecture" | Balungan (shared document) dispatched identically to all agents — no garap differentiation
- P2 | JGC-4 | "Question / Model diversity as a signal" | Kotekan principle is named but not operationalized: disagreement is noted but not structurally required
- P3 | JGC-5 | "Question / Tiered dispatch" | No density-layer taxonomy exists to assign agent types to natural density levels

Verdict: needs-changes

---

## Agent: fd-javanese-gamelan-colotomic-interlocking

**Persona:** A Javanese court musician who understands that the gong plays once per 256-beat cycle while the gambang plays at 8x density — and the beauty emerges from their interlocking, not from any instrument playing faster or louder.

---

## Summary

The interflux design question exposes a colotomic failure at the core: all 17 agents currently play at the same density. A gamelan that assigns the same rhythmic role to gong and gambang is not a gamelan — it is noise. The question recognizes this intuitively ("model diversity as a signal") but has not yet mapped the insight to a structural density-layer architecture. The three density levels needed — rare-structural (gong), medium-reference (saron), dense-elaborative (gambang) — map directly to Opus/Sonnet/DeepSeek-class dispatch with precisely defined coverage responsibilities per layer.

---

## Findings

### P1 | JGC-1 | All agents run at uniform model tier — colotomic structure absent

**Location:** `input.md` § "Current Cost Model" — "All agents currently dispatch as Claude models (opus/sonnet/haiku) via Claude Code's Agent tool. Cross-model dispatch adjusts tiers but stays within the Claude family."

**Colotomic diagnosis:** The gong plays once per gong-cycle. The saron plays at 2x density. The gambang plays at 8x density. No instrument is a worse version of another instrument — each instrument exists at its natural density and produces the notes that only it can produce at that density. The current interflux architecture dispatches all agents at the same density tier (same model family, same capability profile), producing redundant same-depth coverage rather than complementary multi-depth interlocking. When all instruments play gambang patterns, there is no gong to mark the cycle — the structure collapses.

**Failure scenario:** A review of a complex multi-file diff currently launches 6 Claude-family agents all producing similar reasoning-heavy analysis. The synthesis receives 6 findings at the same depth and from the same training perspective. Cross-convergence (finding X reported by 3 agents) does not increase confidence meaningfully — it measures agreement within one instrument family, not across density layers. A genuine P0 that requires gambang-density pattern matching (e.g., "does this response schema match the 15 other endpoints?") goes undetected because the gong-playing Opus agents are not optimized for that density.

**Smallest viable fix:** Define a 3-layer density taxonomy in `config/flux-drive/budget.yaml`:
```yaml
density_layers:
  gong:   # 1x — structural validation, rare, Claude Opus
    agents: [fd-architecture, fd-safety, synthesis]
    model: opus
  saron:  # 4x — reference review, medium, Claude Sonnet
    agents: [fd-correctness, fd-quality, fd-performance]
    model: sonnet
  gambang: # 16x — elaborative/coverage checks, dense, DeepSeek/Qwen
    agents: [fd-user-product, fd-game-design, generated-agents]
    model: openrouter/deepseek-v3
```

This is a configuration addition, not a rewrite. The density taxonomy establishes the structural principle; the dispatch routing follows from it.

---

### P1 | JGC-2 | Irama tier shift is partial — cross-family coordination missing

**Location:** `input.md` § "Cross-model dispatch" — "Routes Stage 2 agents to different model tiers (haiku/sonnet/opus) based on expansion score and budget pressure"

**Colotomic diagnosis:** In gamelan, irama changes (tempo/density shifts) happen as a coordinated ensemble transition. The angklung section does not shift to irama dadi while the bonang section remains in irama tanggung. The ensemble shifts together, or the music breaks. The current interflux budget-pressure tier shift moves individual agents between haiku/sonnet/opus — but these are all within the Claude family (same instrument family). When budget pressure hits and tiers shift, there is no mechanism for the shift to be coordinated across a future multi-family dispatch: some gambang-layer agents (DeepSeek) will continue at high density while saron-layer agents (Claude Sonnet) are demoted, breaking the interlocking structure.

**Failure scenario:** During a large multi-file review with OpenRouter integration, budget pressure causes the orchestrator to demote Stage 2 Claude agents from sonnet→haiku. DeepSeek gambang-layer agents continue at full density. The result: dense elaborative coverage (gambang) continues at full rate while medium reference review (saron) is thinned. This breaks the colotomic structure from the opposite direction — gambang running without saron produces a texture of unmoored elaboration with no structural reference.

**Smallest viable fix:** Add a `density_lock` field to `budget.yaml` so that irama shifts apply uniformly across a density layer:
```yaml
budget_pressure:
  on_demotion:
    strategy: density_layer_aware  # demote entire layer together, not individual agents
    protect: [gong]  # never demote gong-layer (Opus structural agents)
```

---

### P2 | JGC-3 | Balungan dispatched identically — no garap differentiation

**Location:** `input.md` § "Current Architecture" — all 17 agents receive the same input

**Colotomic diagnosis:** In gamelan, the balungan (skeleton melody) is the shared input all instruments elaborate. But each instrument's garap (realization) is completely different — the gambang's realization of balungan note 5 is a rapid flourish of ornamental tones; the gong's realization is a single, weighty strike. The current architecture dispatches the same prompt+document to all agents. This is correct for the balungan itself, but the garap instructions (what each density layer does with the shared input) are not differentiated. The gambang-layer agents should receive explicit instruction to run at high coverage density (check every endpoint, flag every naming inconsistency, verify every type), not reasoning-heavy analysis. Currently all agents receive the same reasoning-heavy instruction set.

**Concrete impact:** DeepSeek V3 dispatched with a reasoning-heavy agent prompt (fd-architecture) will attempt to reason architecturally — a task it can perform, but not its natural density. Its value in the gambang layer is dense coverage at low cost, not architectural reasoning (that is the gong's role). Misaligned garap produces findings that are weaker than the agent could produce in its natural density.

**Fix:** Add density-layer garap overlays to agent prompts at dispatch time. The orchestrator injects a 3-line preamble based on which density layer the agent is assigned to. No changes to individual agent files needed.

---

### P2 | JGC-4 | Kotekan principle named but not operationalized

**Location:** `input.md` § "Question" — "disagreements between Claude and DeepSeek on the same finding might be more meaningful than agreement between two Claude agents"

**Colotomic diagnosis:** The kotekan insight is correct and precisely stated. Kotekan works because the two parts (polos and sangsih) are composed as interlocking complements — each part alone is incomplete and would sound wrong; together they form the correct melody. The document recognizes this principle but proposes no mechanism to operationalize it. "Disagreements might be more meaningful" is not a structural design — it is an observation. The structural implementation requires: (1) defining which agent pairs are kotekan partners (Claude gong + DeepSeek gambang on the same finding), (2) a synthesis step that flags cross-family disagreements as higher-signal than within-family agreement, and (3) a convergence metric that distinguishes within-family convergence from cross-family convergence.

**Fix:** In `docs/spec/core/synthesis.md`, add a convergence tier:
```
cross_family_convergence = findings confirmed by both Claude-family AND non-Claude-family agents
within_family_convergence = findings confirmed by agents within the same model family
```
Cross-family convergence → confidence: high (kotekan confirmed)
Within-family convergence → confidence: medium (one instrument family only)

---

### P3 | JGC-5 | No density-layer taxonomy for agent type assignment

**Location:** `input.md` § "Question / Tiered dispatch" — "Which agent types benefit most from Claude's strengths vs which could run on cheaper models without quality loss?"

The document asks the right question but does not propose a structural answer. The colotomic answer: agent types have natural density levels determined by their cognitive operation type.

**Density classification heuristic:**
- **Gong (Opus):** Agents whose primary operation is structural/relational reasoning (does this architecture hold together? does this security model hold under adversarial assumptions?). Operations that require holding a large context model in mind. Claude Opus is the only current model with sufficient context + reasoning for gong-layer work.
- **Saron (Sonnet):** Agents whose primary operation is comparative reference (does this conform to the project's conventions? does this match the existing API patterns?). Operations that require codebase awareness but not novel reasoning.
- **Gambang (DeepSeek/Qwen):** Agents whose primary operation is coverage density (is every function documented? does every endpoint have an error handler? is every type correct?). Operations that are mechanically exhaustive, not reasoning-heavy.

This taxonomy should be codified as a field in agent frontmatter: `density_layer: gong|saron|gambang`.

---

## Decision Lens Assessment

Does the system create interlocking complementary parts from heterogeneous sources, or does it try to make every model do the same thing at the same density?

**Current state:** Every model does the same thing at the same density. The architecture is one instrument playing all parts simultaneously — not a gamelan.

**Required state:** Three density layers with explicit garap instructions per layer, coordinated irama shifts, and a synthesis step that treats cross-family convergence as kotekan (higher signal than within-family agreement).

The path from current to required is additive: density taxonomy in config, garap overlays in dispatch, convergence tier in synthesis. No existing components need to be removed or rewritten.
