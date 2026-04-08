# Architecture Review: intersite Brainstorm

**Source:** `docs/brainstorms/2026-03-29-intersite-brainstorm.md`
**Reviewed:** 2026-03-27
**Scope:** GSV public site — projects, experiments, articles, sketches, live dev panel

---

## Summary Verdict

The brainstorm describes a dual-function artifact: a *publishing surface* and a *live workspace*. These are architecturally distinct regimes — one is read-optimized, the other is session-stateful — and the document treats them as naturally unified. That unification is the primary structural tension. Everything else follows from how that tension is resolved.

---

## 1. The Two-Regime Problem

### Tidal zonation as structural analogy

Coastal ecologists distinguish the *littoral zone* (intertidal — episodically wet, episodically dry) from the *subtidal zone* (permanently submerged). Species adapted to one regime cannot freely colonize the other. The stress-tolerance strategies are incompatible: a barnacle that survives desiccation every six hours has a fundamentally different physiology than a subtidal coral.

The intersite brainstorm proposes a littoral architecture: a site that is simultaneously a static/SSR publishing surface (the dry zone — cacheable, CDN-friendly, no session state) and a persistent WebSocket terminal relay (the wet zone — session-stateful, latency-sensitive, process-managing). These are not enemy regimes, but they do impose incompatible deployment, scaling, and failure-mode requirements.

The current architecture sketch — Astro + xterm.js relay on sleeper-service — handles this by separating concerns at the infrastructure level (Cloudflare Tunnel for the relay, static hosting for Astro content). That's correct. The risk is in the *experiential* layer: a user who opens the dev panel from a project page expects both halves to feel like one thing. Any seam between the static content zone and the terminal zone will degrade trust.

**Structural implication:** The authentication boundary is also the zone boundary. Session token that authenticates the terminal relay should be issued by the same system that controls content publishing. If Clerk is used for the dev panel, it should also gate any authenticated content-management surfaces. A split auth model (Clerk for terminal, something else for editing) will create credential-management debt.

### The relay as tide-predictor problem

A tide prediction system needs accurate models of basin geometry, tidal constituents, and forcing functions to produce reliable forecasts. The intersite dev panel needs accurate state about what Claude Code process is running for which project, for which user session, and what its current working directory is. This is *not trivial state*. A WebSocket server managing PTY sessions must handle:

- Session reconnection (browser refresh, network dropout)
- Concurrent sessions (two browsers open to same project page)
- PTY orphan cleanup (browser closed without graceful disconnect)
- Context switch (user navigates from Project A page to Project B page while terminal is open)

The brainstorm identifies context-awareness ("pre-loads that project's directory") as a feature, not an architectural concern. In practice, context-aware terminal sessions require the relay to maintain a mapping from `(user_session, project_page_path) → PTY_pid`. That mapping needs persistence (at least in-memory with session affinity) and invalidation logic. This is the hardest part of the dev panel, and it is currently described as a single bullet point.

**Recommendation:** Scope the dev panel to single-session, single-project, desktop-only for v1. Defer concurrent sessions and mobile entirely. This reduces the PTY management problem to a manageable subset without foreclosing future complexity.

---

## 2. Content Pipeline Architecture

### Monastic scriptoria and the chain of custody

Medieval scriptoria operated a custody chain for manuscript production: the *exemplar* (source text) was held by the librarian, *stationarii* rented sections to copyists, and the *corrector* reviewed the copy before it was bound. No text moved from draft to final without traversing a defined role sequence. The chain of custody was the quality guarantee — not the skill of any individual scribe.

The intersite content pipeline has the same structural problem. The brainstorm defines a custody chain:

```
beads/git/CLAUDE.md → auto-generate → Texturaize review → interfluence voice check → mk review → publish
```

This is correct in form. The gaps are:

1. **The stationarii role is undefined.** Who or what assigns auto-generation tasks to specific projects? Is this a cron job? A bead state trigger? An explicit `intersite generate-project-page sylveste-Clavain` command? The brainstorm says "auto-generated from beads/git/filesystem" but doesn't specify the agent or trigger.

2. **The corrector role is conflated.** Texturaize review and interfluence voice check are described as sequential, but they address different failure modes (factual accuracy vs. voice consistency). These should be explicitly separate gates, not bundled as "Texturaize/interfluence" — otherwise both checks will be skipped when one passes.

3. **The exemplar provenance is mixed.** Project pages for Sylveste subprojects pull from beads/git/CLAUDE.md. Standalone project pages (Typhon, Horza, Nartopo, etc.) may not have beads or standardized CLAUDE.md structure. The pipeline needs a fallback for projects that lack structured metadata.

**Recommendation:** Define the content pipeline as a first-class artifact: a state machine with explicit states (raw_draft | texturaize_review | voice_review | mk_review | published | archived) and explicit trigger conditions for each transition. This is a one-page spec, not a multi-sprint epic.

---

## 3. The "Show Breadth" Bet

### Judicial evidence and the coherence test

In adversarial proceedings, circumstantial evidence accumulates persuasive weight only if each piece is independently credible and the pattern they form is non-coincidental. A jury presented with 13 coincidences may be less convinced than a jury presented with 3 direct witnesses — not because 13 < 3, but because the coherence of coincidences is harder to evaluate.

The brainstorm's "show breadth" rationale — listing 13+ standalone projects alongside 54+ Interverse plugins — faces the same coherence problem. The argument is: *early/dormant/private is fine; the point is coherent reach across domains*. This is a claim about how visitors will interpret a large, heterogeneous project list. The risk is that heterogeneity reads as lack of focus rather than coherent vision.

The brainstorm signals awareness of this ("coherent reach across domains" is the phrasing) but doesn't specify what *coherent* means in practice. What is the organizing principle that makes elf-revel (browser elven colony sim) and Enozo (macOS Core Audio) and Typhon (prediction markets) legible as a portfolio rather than a miscellany?

**Architectural implication:** The project page template (Open Question #2) is doing heavy lifting here. The template must surface the *thematic connection* between projects — not just status/description/commits. A field like "domain" or "lineage" (this project exists because of X insight from Y project) would allow the site to render coherence that isn't obvious from the project names alone.

---

## 4. Integration Points and Load-Bearing Assumptions

The brainstorm rests on several integration assumptions that are not validated:

| Assumption | Risk |
|---|---|
| beads/git/CLAUDE.md data is sufficient for auto-generating project pages | CLAUDE.md files vary enormously in structure and quality across the monorepo |
| Astro SSR handles both static content and the authenticated dev panel surface | Astro SSR on Cloudflare Workers has known limitations with WebSocket upgrades; the relay may need a separate process |
| Clerk (implied) provides session tokens compatible with xterm.js WebSocket auth | Not stated explicitly; auth architecture is entirely deferred |
| interblog's existing Astro app can be extended or ported without significant rework | Open Question #4 is unresolved; this could be a 2-day task or a 2-week task |

None of these are blockers, but each deserves a one-paragraph spike note before the bead for this work is claimed.
