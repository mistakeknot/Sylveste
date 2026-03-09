# interhelm Philosophy

## Purpose
Agent-as-operator runtime diagnostics — teaches agents to observe and control running applications via structured diagnostic interfaces instead of screenshot-based debugging.

## North Star
Every running application should be queryable by agents through structured APIs, making runtime verification as natural as running tests.

## Working Priorities
- Structured observability over visual inspection
- Pattern teaching over runtime code shipping
- Framework-agnostic guidance over framework-specific tooling

## Brainstorming Doctrine
1. Start from the agent's perspective — what does the agent need to know about runtime state?
2. Prefer patterns that produce parseable output over human-readable output.
3. Validate patterns against real applications (Shadow Work reference) before documenting.
4. Consider the token cost of each observability approach.

## Planning Doctrine
1. Each pattern (Health, Diff, Assert, Smoke Test) should be independently usable.
2. Templates should compile and run with minimal customization.
3. Skills should work for any framework, with framework-specific guidance as supplements.
4. Hooks should suggest, never block.

## Decision Filters
- Does this reduce the agent's need for screenshots?
- Does this produce structured, parseable output?
- Can this pattern work for native apps (Tauri, Electron) not just web apps?
- Is the pattern validated against a real implementation?

## Evidence Base
- Reference implementation: Shadow Work `sw-agent` + Rust debug server
- Battle-tested on P0 desync bug (25+ state fields requiring reset verification)
- Source confidence: high (extracted from production-grade implementation)
