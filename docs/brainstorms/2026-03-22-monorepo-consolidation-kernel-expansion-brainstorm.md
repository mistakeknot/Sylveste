# Monorepo Consolidation & Kernel Expansion — Brainstorm

**Date:** 2026-03-22
**Epic:** Sylveste-og7m (29 children: 2 P0, 18 P1, 6 P2, 3 P3)
**Input:** 4 structural + 7 esoteric review agents, synthesis at `.claude/flux-drive-output/synthesis-esoteric-cross-cutting.md`

## Context

Multi-agent analysis of the full Sylveste monorepo (54 plugins, 6 pillars, 3 layers) identified systemic patterns across architecture, security, calibration, and governance. Three cross-agent patterns emerged independently from 7 different analytical lenses:

1. **Static constants masquerading as intelligence** — hardcoded thresholds (interspect confidence, routing safety floors, complexity tiers) lack calibration loops. PHILOSOPHY.md's 4-stage closed-loop pattern is incomplete for 4/6 domains.
2. **Silent degradation under concurrent load** — interspect.db drops writes at 5+ agents, event pipeline crowds out low-volume sources, reservations grow O(N*M) with no cap.
3. **Architecture intent vs. code reality** — Ockham (empty), Alwe (copy of Skaffen), Work Context (unnamed type), Authority Scope (prose-only). Documentation target state diverging from code.

## Sprint Scope Decision

The epic has 29 children. This sprint should land a **coherent first batch** that:
- Fixes the P0 (Skaffen code duplication) — blocks further Skaffen/Alwe/Zaka work
- Addresses the most dangerous security P1s — agent impersonation + bead poisoning
- Lands the highest-leverage architecture fix — phase contract (unblocks .14, .20, .22)
- Establishes one complete closed-loop pattern — proving the calibration approach works

### Proposed Batch 1 (this sprint): 6-8 children

| Child | Priority | Category | Why now |
|-------|----------|----------|---------|
| .10 | P0 | Dedup | Skaffen→Alwe/Zaka import. Active drift risk. Blocks Skaffen evolution. |
| .11 | P1 | Security | Agent impersonation via X-Agent-ID. Localhost exploit. Simplest security win. |
| .13 | P1 | Security | Bead content poisoning via bd set-state. Poisons sprint operations. |
| .14 | P1 | Architecture | Phase FSM divergence (9 vs 6). Unblocks .20 (phase skip) and .22 (invasive species). |
| .15 | P1 | Architecture | Routing superstar effect. Simple fix — add `maxPerAgent` to `selectQuality()`. |
| .16 | P1 | Architecture | Work Context type. Reduces 8 reconstruction sites to 1. Structural win. |
| .25 | P1 | Calibration | Interspect confidence calibration from canary outcomes. Proves closed-loop pattern. |

### Deferred to Batch 2

| Child | Priority | Why defer |
|-------|----------|-----------|
| .1 | P1 | Phase FSM lift (1,717 lines) is too large for one sprint. .14 (contract) first. |
| .2 | P1 | Event unification (3 systems → 1) requires .16 (Work Context) as prerequisite. |
| .3 | P1 | Routing always-on needs .14 (phase contract) and .15 (superstar cap) first. |
| .12 | P1 | Reservation starvation is lower risk than .11/.13 (exploitable now). |
| .17-.24, .26-.27 | P1 | Depend on Batch 1 foundations or lower immediate impact. |

## Key Design Questions

### Q1: How does Skaffen import from Alwe/Zaka?
- **Option A:** Go module dependency (`go.mod replace` pointing to local monorepo paths). Monorepo-native.
- **Option B:** Shared package in `sdk/interbase/`. Centralized but requires extracting stable interfaces.
- **Recommended: A.** Direct imports keep ownership clear (Alwe owns observer, Zaka owns adapter). Interbase extraction (.9) is a separate, lower-priority item.

### Q2: What is the phase contract format?
- **Option A:** Go interface in `sdk/interbase/phases/phases.go` with phase names as constants.
- **Option B:** YAML/JSON schema in `core/intercore/config/` that both Clavain and Skaffen read.
- **Recommended: A.** Go interface gives compile-time safety. Skaffen already uses Go. Clavain's bash reads it via `ic phase list`.

### Q3: Where does WorkContext live?
- **Option A:** `core/intercore/types/workcontext.go` — kernel owns it, everyone imports.
- **Option B:** `sdk/interbase/types/workcontext.go` — SDK layer, lighter dependency.
- **Recommended: A.** WorkContext is fundamental infrastructure (bead_id, run_id, session_id). Kernel is right.

### Q4: How do we scope the X-Agent-ID fix?
- Agent identity must bind to registration-time session token, not per-request header.
- Intermute already has agent registration. Fix: verify `X-Agent-ID` matches the registered identity for the session token.
- **Scope guard:** This sprint fixes localhost auth only. mTLS/external auth is Batch 2+.

### Q5: What does "closed-loop calibration for Interspect" (.25) concretely mean?
- Currently: hardcoded confidence thresholds in interspect (e.g., ≥3 events + ≥0.7 confidence = propose).
- Target: read canary outcomes (did the routing override improve/worsen agent quality?) and adjust thresholds.
- **Minimum viable:** Write canary outcomes to interspect.db, add a `calibrate-thresholds` command that reads them and writes adjusted thresholds, wire it into `/interspect:calibrate`. This is one complete loop of the 4-stage pattern.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Skaffen import breaks existing tests | Medium | High | Run Skaffen test suite before/after. Monorepo makes this easy. |
| Phase contract requires Clavain bash changes | High | Medium | Phase contract is additive — new Go constants don't break existing bash aliases immediately. Deprecation path. |
| WorkContext refactor touches 8+ files | Medium | Low | Mechanical refactor. Each site independently testable. |
| bd set-state auth breaks existing workflows | Medium | High | Writer verification is opt-in for critical keys first (.13 specifies which keys). |

## Success Criteria

1. `go test ./...` passes in Skaffen with Alwe/Zaka as imports (no copy-forks)
2. Intermute rejects mismatched X-Agent-ID headers in test
3. Phase contract exists and both Clavain/Skaffen reference it
4. WorkContext type exists, ≥3 reconstruction sites converted
5. `selectQuality()` has `maxPerAgent` cap with test
6. Interspect has one complete predict→observe→calibrate→fallback loop
7. No child bead left in_progress without a follow-up bead for remaining work
