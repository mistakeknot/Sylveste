---
artifact_type: brainstorm
bead: sylveste-jrua
stage: discover
---

# Ecosystem-Wide Simplification Pass

## What We're Building

A comprehensive simplification of the Sylveste codebase targeting cross-boundary duplication, god functions, and configuration sprawl identified by a 6-agent flux-review scan across all pillars and plugins.

**Phase 1 (completed):** 6 parallel agents removed ~1,100 LOC across 6 repos — duplicate packages (Zaka/Alwe), CLI flag parser extraction (intercore), message scan dedup (intermute), test fixture consolidation (interfer), telemetry dedup (Clavain), shared test infra creation (3 plugins converted).

**Phase 2 (this sprint):** 18 remaining items across ~8 repos, executed via repo-grouped delegation.

## Why This Approach

The 6-agent scan revealed a dominant pattern: **cross-boundary duplication**. The monorepo structure encourages self-contained modules, but 10+ plugins copy-pasted identical test infrastructure, 3+ plugins reimplemented session hooks, and apps duplicated middleware. The highest leverage is creating shared libraries that prevent recurrence.

Repo-grouped delegation (one agent per repo) is the right execution strategy because:
- Each subproject has its own git repo — no file conflicts between agents
- All items within a repo can be done atomically with one commit
- Agents can verify builds/tests locally before pushing

## Key Decisions

1. **All 18 remaining items in scope.** No items deferred. Includes incremental completions, new shared infra, god function decomposition, and config cleanup.
2. **Agents commit directly.** Build/test verification required; no staging-for-review gate. Same pattern as Phase 1 which was successful.
3. **Repo-grouped parallelism.** ~6 agents, one per repo cluster. Natural conflict avoidance.

## Execution Grouping

| Agent | Repo(s) | Items |
|-------|---------|-------|
| 1 | interverse/_shared + 7 plugins | Convert remaining plugins to shared test infra |
| 2 | core/intercore | Convert 9 remaining cmd files to shared flag parser + split run.go + store boilerplate |
| 3 | core/intermute | HTTP handler method switch dedup |
| 4 | os/Clavain + interflux | Agent definition bloat (12 review agents) + session context lib |
| 5 | apps/ (interblog, intersite, Autarch, Intercom) | Clerk middleware factory, API helpers, chatpanel.go decompose, container-runner.ts decompose, content schema overlap |
| 6 | root (monorepo) | Install/uninstall script dedup, stale flux-gen spec cleanup |

## Open Questions

- **Content schema overlap** between interblog/intersite: should this live in `sdk/interbase/typescript/astro/` or stay app-local? Decision: sdk/interbase if both apps import it; app-local if patterns diverge.
- **Agent definition bloat**: extracting preamble/focus-rules from 12 agents risks reducing agent clarity. Mitigation: keep domain-specific content in agents, only extract the generic "Read CLAUDE.md" and "What NOT to Flag" boilerplate into the flux-drive skill docs.
- **run.go split**: 2214 LOC across 20+ functions. Split by domain (create, lifecycle, config, replay) into 4-5 files. The shared flag parser (already done for 3 files) makes this cleaner.

## Success Criteria

- All items committed with passing builds/tests
- No behavioral changes — pure structural refactoring
- Total LOC removed: target ~800 additional (on top of ~1,100 from Phase 1)
- Shared test infra covering 10+ plugins (currently 3)
