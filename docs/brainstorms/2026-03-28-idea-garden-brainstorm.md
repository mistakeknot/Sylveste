---
artifact_type: brainstorm
bead: sylveste-e8n
stage: discover
---

# Idea Garden: Background Idea Refinement

## What We're Building

A system that lets you capture half-formed ideas from your phone and have them waiting, enriched and structured, next time you sit down to work.

**Lifecycle:** Message Auraken on Telegram with a rough thought. Auraken creates a structured idea card and plants it in a Garden Salon "idea garden." Refinement agents tend the idea in the background — pulling in related research from interject, running dialectic stress-tests via intermonk, synthesizing against project state. Humans steer via annotations. When an idea matures, it graduates to a bead + brainstorm doc and enters the sprint pipeline.

**An idea has three representations that coexist:**
1. **Structured card** — thesis, supporting evidence, confidence score, maturity stage, open questions. The machine-readable view.
2. **Evolving document** — a Y.Text CRDT doc that agents rewrite and extend. The human-readable view. Proposals show diffs.
3. **Conversation thread** — append-only log of perspectives (agent analyses, human comments, external signals). The history.

## Why This Approach

**interseed as Interverse plugin.** The refinement engine lives in the Demarch monorepo as a standalone plugin. It connects to Garden Salon via salon-core's `connectAsAgent()` protocol — the same way the demo editorial agent works today. This keeps Garden Salon product-agnostic (it doesn't need to know about idea refinement) while giving interseed access to the full Demarch intelligence stack.

**Auraken as capture surface.** Auraken is already deployed on sleeper-service as a Telegram bot. It's the phone-first interface. Adding an `/idea` command (or detecting idea-shaped messages) gives zero-friction capture without building new bot infrastructure. Auraken writes to interseed's store; interseed handles everything downstream.

**Scheduled + event-driven refinement.** Two trigger types:
- **Scheduled:** Cron-triggered (daily or configurable) re-examination of all active ideas. Ensures nothing goes dormant.
- **Event-driven:** interject discovery webhook fires when new research matches an idea's keywords. Bead closures in related domains trigger re-evaluation. Project state changes (new brainstorms, closed epics) prompt synthesis.

## Key Decisions

- **Plugin name:** `interseed` — seeds grow into gardens
- **Capture agent:** Auraken (existing Telegram bot) — add idea capture mode
- **Collaboration surface:** Garden Salon via salon-core agent protocol
- **Visualization:** Meadowsyn ambient layer encodes idea maturity (confidence → color warmth, activity → oscillation speed)
- **Storage:** interseed owns a SQLite DB for idea cards + metadata. Garden Salon CRDT owns the live doc/thread state.
- **Graduation:** When confidence crosses threshold + human approves → interseed creates a bead + brainstorm doc from the accumulated state
- **Success metric:** Capture friction near zero — fire from phone, find enriched idea at desk

## Open Questions

- **Auraken integration depth:** Does Auraken just forward messages to interseed, or does it do initial structuring (extract thesis, tag domains) before handoff?
- **Garden Salon deployment:** Idea gardens need a running relay. Is this the same relay as editorial gardens, or a dedicated instance?
- **Refinement agent identity:** One interseed agent per idea, or one agent that tends all ideas? (Salon presence model suggests per-idea for visibility.)
- **Interject coupling:** Push (interject webhooks to interseed) or pull (interseed queries interject DB on schedule)?
- **Graduation threshold:** Fixed confidence score, human-triggered, or hybrid (agent recommends, human confirms)?
- **Multi-user:** Can multiple people plant ideas in the same garden, or is it single-user with shared viewing?
