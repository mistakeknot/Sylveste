---
artifact_type: plan
bead: sylveste-8em
prd: docs/prds/2026-04-03-ockham-vision.md
brainstorm: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
---
# Plan: Ockham Vision Document

**Deliverable:** `os/Ockham/docs/vision.md`
**Source material:** Brainstorm (rev 3, 16-agent reviewed), PRD (light-reviewed), flux-review synthesis
**Scope boundary:** Vision-level (what + why), not spec-level (exact thresholds, function signatures, CLI syntax)

## Task Sequence

All tasks write to a single file (`os/Ockham/docs/vision.md`). Each task adds one major section. Tasks are sequential — each section builds on vocabulary and concepts from prior sections.

### Task 1: Document skeleton + F1 Architecture & Position
**Bead:** sylveste-lj1
**Inputs:** Brainstorm §What We're Building, §Key Decisions 1, §Key Decisions 8; AGENTS.md package map
**Writes:**
- Document header with date, status (draft), and source references
- "What Ockham Is" section — the Cyberstride analogy, 4-subsystem architecture
- Subsystem table (input/output/wave/allowed-deps)
- Dependency direction diagram (ASCII)
- Architecture position diagram (L1/L2/L3 layering)
- "What Ockham Is Not" section (6 distinctions)
- Phased constraint (policy engine through Wave 3)
- Degradation contracts table (all 4 subsystems)
**Verify:** All 6 F1 acceptance criteria checkable by reading the section

### Task 2: F2 Intent Subsystem
**Bead:** sylveste-sg1
**Inputs:** Brainstorm §Key Decisions 2-4; PRD F2 ACs
**Writes:**
- "Intent" section — how the principal expresses strategic intent
- intent.yaml schema (YAML code block) with version, themes, constraints, expiry fields (valid_until, until_bead_count)
- Lane-to-theme mapping explanation
- Fallback behavior (missing/corrupt → hardcoded default)
- Priority-to-offset magnitude principle (high/normal/low, not exact numbers)
- Atomic replacement semantics
**Verify:** All 6 F2 acceptance criteria checkable

### Task 3: F3 Scoring & Dispatch Integration
**Bead:** sylveste-qw4
**Inputs:** Brainstorm §Key Decisions 3, §10; PRD F3 ACs; lib-dispatch.sh (lines 133-218 for context on current scoring)
**Writes:**
- "Scoring & Dispatch" section — how intent becomes dispatch action
- Additive offset formula with priority-ordering reasoning
- Integration boundary: Ockham writes to intercore state, lib-dispatch.sh reads
- Gate-before-arithmetic contract: CONSTRAIN/BYPASS as eligibility gates, not weights
- Dual logging principle
- Weight floor and starvation detection
- Bulk pre-fetch requirement
- Idle capacity release
**Verify:** All 7 F3 acceptance criteria checkable
**Note:** Read lib-dispatch.sh to verify the priority tier gap claim (~24 points) before writing the ordering proof. **Fallback:** If the gap differs or the file has been refactored, write the principle as "offsets bounded within one priority tier gap" without quoting a specific number, and flag for verification.

### Task 4: F4 Anomaly & Algedonic Signals
**Bead:** sylveste-547
**Inputs:** Brainstorm §Key Decisions 5, §10; flux-review findings F4/F9/F10; PRD F4 ACs
**Writes:**
- "Algedonic Signals" section — Stafford Beer's pain/pleasure bypass
- Three tiers with escalation/de-escalation rules
- Multi-window confirmation (principles, not exact durations)
- Rate-of-change fast path
- Signal qualifications (6 items)
- Weight-outcome feedback loop
- Independent observation channel
- Paired confirmation requirement
- Alwe degradation contract
- In-flight bead handling when a theme freezes (agents complete current work at supervised autonomy, no new claims)
**Verify:** All 11 F4 acceptance criteria checkable

### Task 5: F5 Authority & Autonomy Ratchet
**Bead:** sylveste-cnc
**Inputs:** Brainstorm §Key Decisions 6; flux-review findings F2/F5/F7/F12; PRD F5 ACs
**Writes:**
- "Authority & Autonomy" section
- State machine diagram (ASCII) with transition table
- Evidence-quantity promotion guards (not wall-clock)
- Asymmetric thresholds principle
- Per-domain scope with CODEOWNERS-style globs
- Cold start from existing interspect evidence
- Cross-domain min-tier composition rule
- Ratchet runaway prevention (periodic re-confirmation)
- Post-promotion audit
- Pleasure signals (Wave 1)
- Interspect interface contract (named, not specified)
- Interspect degradation behavior (promotions paused, demotions immediate)
- Known gaming surface + interim mitigation
**Verify:** All 12 F5 acceptance criteria checkable

### Task 6: F6 Safety Invariants & Halt Protocol
**Bead:** sylveste-x04
**Inputs:** Brainstorm §Key Decisions 7; flux-review findings F1/F4; PRD F6 ACs
**Writes:**
- "Safety Invariants" section — 8 invariants, each with structural enforcement rationale
- Authority write token approach: MUST name the issuer, signing mechanism, and revocation model (e.g., "HMAC signed by intercore, revoked via interspect event"). Design-phase detail deferred, but the vision doc names the approach.
- Crash-recovery scenario for write-before-notify
- Halt protocol (Tier 3 sequence)
- Clavain-independent notification path
- Restart sequence
- "Policy immutability during halt" rule
**Verify:** All 11 F6 acceptance criteria checkable

### Task 7: Final pass — coherence, open questions, wave roadmap
**Inputs:** Completed vision.md from Tasks 1-6; PRD §Open Questions; brainstorm subsystem table (wave assignments per subsystem); each section's wave references from Tasks 1-6
**Writes:**
- "Phased Rollout" section — Wave 1-4 summary showing which subsystems/features ship when (source: subsystem table wave column from F1, plus wave references scattered through F4-F5)
- "Open Questions" section (2 items from PRD)
- Read full document end-to-end for coherence, remove contradictions between sections
- Ensure each section cross-references related sections where concepts connect
- Enforce per-section word budget: ~300-500 words per section, ~2500-3000 words total
**Verify:** Document reads coherently as a single narrative, not 6 independent sections

## Build Sequence

```
Task 1 (skeleton + F1) ──→ Task 2 (intent) ──→ Task 3 (scoring) ──→ Task 4 (anomaly) ──→ Task 5 (authority) ──→ Task 6 (safety) ──→ Task 7 (coherence pass)
```

Sequential — each section references concepts from earlier sections. No parallelism possible for a single-file document.

## Risk Register

| Risk | Mitigation |
|------|-----------|
| Scope creep into spec-level detail | Scope boundary in PRD. When tempted to write exact thresholds or function signatures, write the design principle instead and note "design-phase detail." |
| Brainstorm rev 3 contradicts flux-review synthesis | Brainstorm already incorporated P0 fixes. Where conflict exists, brainstorm rev 3 takes precedence (it's the later document). |
| Document too long for reviewers | Target 2000-3000 words. Each section should be self-contained enough to review independently. |
| Priority tier gap claim (~24 points) is wrong | Task 3 reads lib-dispatch.sh to verify before writing. Fallback: write principle without specific number. |
| Individual sections run long, compressing Task 7 | Per-section word budget (~300-500 words). Task 7 enforces 2500-3000 word total. |

## Estimated Effort

7 tasks. Tasks 1-3 and 7: ~30 min each. Tasks 4-6: ~45 min each (11-12 ACs each). Total: ~4-5 hours (single session). Most time in Tasks 4-6 (complex design reasoning). Task 7 is fast (coherence editing).
