---
artifact_type: brainstorm
bead: Demarch-csq
stage: discover
---
# Diagnostic Maturation Skill — Brainstorm

## What We're Building

A fourth skill for interhelm (`diagnostic-maturation`) that guides agents through evolving a basic diagnostic server scaffold into a production-grade operator toolkit. The skill has two modes:

1. **Maturation mode** — step-by-step guide through 6 levels of diagnostic server maturity
2. **Audit mode** — evaluate an existing diagnostic server against the maturation ladder, report current level and gaps

## Why This Approach

Interhelm's existing `runtime-diagnostics` skill scaffolds a skeleton diagnostic server. But the gap between "skeleton" and "production-grade" (like Shadow Work's sw-agent, 1,525 lines across 6 files) is enormous. Agents need structured guidance to cross that gap — otherwise they stop at Level 1 and think they're done.

The 6-level ladder gives agents clear milestones. The conformance audit gives agents a way to assess existing servers. Extra depth on domain modeling (Level 1) addresses the hardest part — mapping an app's actual subsystems to meaningful health checks.

## Key Decisions

1. **6-level maturation ladder** (not fewer): Each level is independently useful and session-sized
   - L1: Domain Health Modeling (deep — the hardest and most important level)
   - L2: Smoke Test Suite (5-15 E2E assertions)
   - L3: Assert Language (expression evaluator for scripted verification)
   - L4: CLI Formatting (human-readable output, compact numbers, colored status)
   - L5: Diff Engine (snapshot-before/after with domain-specific deltas)
   - L6: Interactive REPL + Watch Mode

2. **Conformance audit mode**: Agents can evaluate an existing diagnostic server's maturity level by checking which capabilities exist. Reports: "Level 3/6 — has health, smoke tests, assert. Missing: formatters, diff, REPL."

3. **Domain modeling gets extra depth**: This is where agents struggle most — deciding WHAT to check, not HOW. The skill should guide agents through: identify subsystems → define healthy/degraded/unhealthy per subsystem → wire detail fields with domain-specific metrics → set meaningful thresholds. Shadow Work's 6-subsystem health check (simulation, economy, finance, emergence, countries, errors) is the reference.

4. **Shadow Work as reference implementation**: Concrete code excerpts from sw-agent at each level show what "done" looks like. Not copy-paste templates — distilled patterns with adaptation guidance.

5. **"You know you're done when" gates**: Each level ends with a concrete verification (e.g., L1: "curl /diag/health returns per-subsystem status with detail fields, not just a boolean").

## Open Questions

- Should the audit mode produce a structured JSON report (machine-readable) or just prose guidance?
- Should levels be sequential or can agents jump to any level? (Leaning: sequential recommended, but not enforced — some apps need diff before formatters)
