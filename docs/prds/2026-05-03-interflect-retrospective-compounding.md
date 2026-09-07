---
artifact_type: prd
bead: sylveste-l0zc
stage: design
date: 2026-05-03
---

# PRD: Interflect Retrospective Compounding

## Problem

Sylveste/Hermes sessions already contain high-value lessons: mk corrections,
operator preferences, project doctrine updates, routing failures, reusable
procedures, and follow-up tasks. Today those lessons are only promoted when a
human or agent notices them in the moment. The result is lossy continuity:
important corrections may remain trapped in Discord/session history, while
memory, skills, docs, Beads, and routing overlays drift behind lived practice.

Interspect partially closes a different loop: it observes agent/reviewer
performance and turns evidence into routing signals. It does not own
retrospective session internalization. Interflect fills that gap.

## Solution

**Interflect** is the retrospective-compounding plugin/lane. It reads prior
sessions and adjacent work-state, extracts candidate lessons, classifies each
lesson by promotion target, and emits reviewable proposals that can update
future behavior.

Interflect is the **Reflect → Compound** bridge from the OODARC loop:

- **Reflect:** identify what happened, what changed, and what the system should
  learn.
- **Compound:** propose durable updates to the right substrate so future agents
  behave better.

v0 is conservative: Interflect proposes, deduplicates, and routes promotions; it
does **not** silently rewrite long-lived canon.

## Boundary vs Interspect

| System | Owns | Does not own |
|---|---|---|
| Interspect | Agent performance evidence, correction events, routing overrides, canary monitoring | Session-wide lesson extraction, memory/skill/doc promotion proposals |
| Interflect | Retrospective lesson mining, promotion taxonomy, reviewable internalization queue | Low-level agent accuracy scoring, direct routing override application |

Interspect may be an input or downstream consumer when a lesson is clearly a
routing signal. It is not the default container for Interflect.

## Inputs

- Hermes/Amtiskaw sessions and Discord/Telegram thread transcripts available to
  the agent runtime.
- CASS/coding-agent session summaries and handoff receipts.
- Beads issue state, notes, closures, and labels.
- Repo-local docs, skills, PRDs, handoffs, and `AGENTS.md` / `CLAUDE.md` files.
- Explicit mk corrections and preferences in live chat.

## Outputs

Interflect emits a **promotion proposal** with source handles, classification,
confidence, target substrate, idempotency key, and suggested diff/action.

Promotion targets:

1. **User profile / memory** — stable cross-session facts about mk or durable
   environment/project facts.
2. **Skill patch** — reusable procedure, command sequence, pitfall, or workflow.
3. **Repo/project doctrine** — project-local design/operational rule that should
   live in docs or `AGENTS.md`.
4. **Beads follow-up** — task that needs implementation, cleanup, review, or
   investigation.
5. **Routing signal** — evidence that should feed Interspect or an overlay.
6. **Runtime-only / no promotion** — transient state, completed work logs,
   stale debugging residue, or one-off context.

## Promotion policy

- v0 proposals require review before mutating memory, skills, canon docs, or
  routing overlays.
- Beads captures can be created automatically only when scoped, non-duplicative,
  and traceable to a source handle.
- Every proposal carries enough evidence to reject it without re-reading the full
  source transcript.
- Duplicate lessons collapse by idempotency key: `(source_session, normalized
  claim, target_substrate)`.
- Conflicting lessons are held for review; newest correction does not silently
  override stable canon without a reason.

## Example classifications

| Lesson | Classification | Proposed target |
|---|---|---|
| mk corrected the lane: “we're doing Interflect,” not Interspect | Stable project identity / boundary | Memory + this PRD boundary section |
| “Critical lessons from mk should be proposed, not silently rewritten into canon” | Project doctrine / promotion guardrail | Interflect PRD + future skill/command behavior |
| Interspect already exists at `/home/mk/projects/interspect` and covers performance profiling, not session lesson internalization | Prior-art / routing boundary | PRD boundary; possible Beads relation to Interspect only if implementation touches it |
| A repeated shell/Beads pitfall emerges across sessions | Operational procedure | Skill patch proposal, not memory |
| A one-time dirty worktree or live port state appears in a session | Runtime-only | No durable promotion; cite only in immediate handoff if still relevant |

## v0 features

### F0: Source intake and lesson candidate extraction

**What:** Given one or more session handles or a recent-session window, extract
candidate lessons with source snippets and normalized claims.

**Acceptance criteria:**
- CLI/command accepts explicit session IDs and a bounded recent window.
- Output is JSONL proposal candidates with source handles and snippets.
- Candidate extraction separates correction/preference/procedure/task/routing
  signals before any mutation path runs.

### F1: Promotion taxonomy classifier

**What:** Classify each candidate into the six promotion targets above with a
confidence score and rejection reason for runtime-only cases.

**Acceptance criteria:**
- At least 20 fixture lessons cover all six classes.
- Classifier output is deterministic for fixtures.
- Ambiguous or conflicting lessons route to review, not auto-apply.

### F2: Reviewable proposal queue

**What:** Store proposals in a durable queue, deduplicate by idempotency key, and
render compact review cards.

**Acceptance criteria:**
- Re-running the same session window does not duplicate proposals.
- Review cards show source, proposed target, rationale, and suggested action.
- Rejected proposals preserve the reason so they do not reappear unchanged.

### F3: Safe appliers for low-risk targets

**What:** Implement appliers only after proposal review. v0 starts with Beads
follow-up creation and draft skill/doc patches; memory/canon/routing mutations
remain explicitly approved.

**Acceptance criteria:**
- Beads applier searches duplicates before creation.
- Skill/doc appliers produce patch files or diffs, not silent writes, unless the
  operator explicitly accepts.
- Memory/routing appliers require explicit approval and include rollback text.

## Non-goals

- No autonomous canon rewriting in v0.
- No new routing optimizer; route-quality evidence belongs to Interspect.
- No broad repo scaffold until the PRD and first implementation bead are accepted.
- No Discord history scraping beyond messages available to the current runtime or
  explicitly provided session handles.

## Implementation shape

Default home should be an Interverse plugin named `interflect` once scaffolded:

- `commands/interflect.md` — analyze a bounded source window and print proposal
  cards.
- `commands/interflect-review.md` — review/accept/reject proposal queue.
- Optional `hooks/` later — scheduled or session-end candidate generation after
  v0 proves useful manually.
- Local proposal store can start standalone; kernel-native status is earned only
  if Intercore event/state integration becomes necessary.

## Alignment

Interflect supports Sylveste's OODARC philosophy by making Reflect and Compound
operational across sessions instead of relying on opportunistic human recall.

## Conflict/Risk

Main risk is over-promotion: turning transient session residue into canon. v0
mitigates by making proposals reviewable, classifying runtime-only cases, and
requiring approval before memory/canon/routing mutations.
