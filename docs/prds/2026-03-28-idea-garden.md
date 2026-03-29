---
artifact_type: prd
bead: sylveste-e8n
stage: design
---

# PRD: Idea Garden — Background Idea Refinement

## Problem

Half-formed ideas get lost between capture and action. You have a thought on your phone but no low-friction way to plant it where agents can enrich it and have it waiting, structured and researched, when you sit down to work.

## Solution

A new Interverse plugin (`interseed`) that owns the idea lifecycle: capture via Auraken (Telegram), background refinement via scheduled + event-driven agent runs, collaboration via Garden Salon, and graduation to beads when mature.

## Features

### F1: interseed plugin scaffold + idea data model

**What:** Standalone Interverse plugin with SQLite storage for idea cards and an MCP server stub.

**Acceptance criteria:**
- [ ] Plugin at `interverse/interseed/` with valid `.claude-plugin/plugin.json`
- [ ] SQLite schema: `ideas` table (id, thesis, evidence JSON, confidence float, maturity enum [seed/sprouting/growing/mature], keywords JSON, garden_id nullable, created_at, updated_at)
- [ ] `refinement_log` table (id, idea_id, trigger enum [scheduled/event/manual], summary text, confidence_delta float, created_at)
- [ ] MCP server (`uv run interseed-mcp`) with `interseed_status` and `interseed_list_ideas` tools
- [ ] `interseed plant "<thesis>"` CLI command creates a seed idea

### F2: Auraken idea capture

**What:** `/idea` command in Auraken that captures a message from Telegram, structures it, and writes to interseed's store.

**Acceptance criteria:**
- [ ] `/idea <text>` command in Auraken bot creates a new idea in interseed's SQLite DB
- [ ] Initial structuring: Claude extracts thesis (1 sentence), keywords (3-5), and open questions from raw message
- [ ] Confirmation reply to user with thesis + "Planted in idea garden"
- [ ] Works from phone with zero additional setup (just message Auraken)

### F3: Refinement engine

**What:** Core refinement loop that re-examines active ideas, pulls context, and produces improved versions.

**Acceptance criteria:**
- [ ] `interseed refine` CLI command processes all ideas with maturity < mature
- [ ] For each idea: reads thesis + evidence + thread, calls Claude with project context (active beads, recent brainstorms), produces updated thesis/evidence/confidence
- [ ] Confidence score updates based on evidence accumulation (not arbitrary)
- [ ] Refinement logged to `refinement_log` table
- [ ] Runnable via cron (`0 8 * * *` daily) or `/schedule`
- [ ] Idempotent: running twice in a row produces no change if no new context

### F4: Garden Salon agent bridge

**What:** interseed connects to Garden Salon as an agent participant, creating idea gardens and posting refinements as proposals.

**Acceptance criteria:**
- [ ] `interseed sync <idea_id>` creates/connects to a Garden Salon garden for the idea
- [ ] Refinement results posted as proposals via `suggestEdit()` (old thesis → new thesis)
- [ ] Human annotations (approve/reject/comment) read back and stored in interseed DB
- [ ] Rejection feedback incorporated into next refinement cycle
- [ ] Agent presence visible in Meadowsyn ribbon (name: "interseed", activity: "refining <thesis snippet>")

### F5: Signal feeds + graduation

**What:** External signal matching (interject discoveries) and graduation workflow when ideas mature.

**Acceptance criteria:**
- [ ] `interseed match` queries interject DB for discoveries matching active idea keywords
- [ ] Matching discoveries added to idea's evidence and trigger a refinement cycle
- [ ] Graduation command: `interseed graduate <idea_id>` creates a bead + brainstorm doc from accumulated state
- [ ] Graduation guard: requires confidence >= 0.7 AND human annotation approving graduation
- [ ] Graduated ideas marked as maturity=mature, linked to bead ID

## Non-goals

- Real-time streaming refinement (batch is fine for v1)
- Multi-user idea gardens (single-user with shared viewing for v1)
- Custom Meadowsyn visualizations (reuse existing ambient metrics mapping)
- Intermonk dialectic integration (future iteration — refinement engine is extensible)
- Push-based interject webhooks (pull on schedule is simpler for v1)

## Dependencies

- **Auraken** (existing) — Telegram bot, deployed on sleeper-service
- **Garden Salon** (existing) — salon-core agent protocol, relay server
- **interject** (existing) — discovery DB for signal matching
- **Beads** (existing) — graduation target

## Open Questions

- Auraken→interseed transport: HTTP API, shared SQLite, or CLI invocation? (Leaning CLI: `interseed plant` called from Auraken handler)
- Garden Salon relay: shared instance or dedicated for idea gardens? (Leaning shared — fewer processes)
- Refinement depth per cycle: one Claude call per idea or multi-step (research → synthesize → update)? (Leaning single call for v1)
