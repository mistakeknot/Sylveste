# PRD: Skaffen Quality Signals (Compound → Orient Feedback Loop)

**Bead:** Sylveste-khlh
**Parent:** Sylveste-3j0i (Hyperspace AGI adoption)
**Priority:** P0
**Date:** 2026-03-14

## Problem

Skaffen's OODARC loop runs 6 phases per session but every session starts cold. The Compound phase (terminal) is a stub — it persists turn data via Session but generates no quality signals. The Orient phase reads no historical data. Result: Skaffen cannot learn from past sessions and repeats the same mistakes (high tool error rates, poor model selection, wasted budget).

## Solution

Close the feedback loop by:
1. **Defining** a `QualitySignal` type with hard/soft/human dimensions
2. **Implementing** Compound phase logic that aggregates per-turn evidence into quality signals and writes them to a persistent mutation store
3. **Implementing** Orient phase reading — system prompt injection (passive) + quality_history tool (active)

## Non-Goals

- Signal-based model routing (v0.2 — Orient reads signals, but router doesn't yet)
- Signal rotation/compaction (quality-signals.jsonl grows unbounded for now)
- Cross-project signal sharing (signals are per-Skaffen-install)
- RPC steering from quality signals (deferred per PRD F7)

## Features

### F1: Mutations Package (`internal/mutations/`)

New package for cross-session persistent data.

**Types:**
- `QualitySignal` — three-dimension signal (hard/soft/human)
- `HardSignals` — measurable: tests, build, token efficiency, turn count
- `SoftSignals` — observable: complexity tier, tool error rate, tool denial rate
- `HumanSignals` — qualitative: approval rate, outcome

**Store:**
- `Store.Write(QualitySignal) error` — append to `~/.skaffen/mutations/quality-signals.jsonl`
- `Store.ReadRecent(n int) ([]QualitySignal, error)` — read last N signals (tail-read, not full scan)

### F2: Compound Phase Aggregation

New `internal/mutations/aggregate.go`:
- `Aggregate(evidenceDir, sessionID string) (QualitySignal, error)`
- Reads the session's evidence JSONL
- Computes hard signals from turn data (token efficiency = output/input ratio, turn count)
- Computes soft signals from tool calls (error rate, denial rate, complexity tier from router)
- Human signals from hook approvals (approval rate from trust evaluator)
- TestsPassed and BuildSuccess are nil by default (populated only if bash tool ran test/build commands)

### F3: Compound Phase Wiring

In `agent.go`, after the Compound phase loop completes:
- Read evidence for current session
- Call `Aggregate()` to produce QualitySignal
- Call `Store.Write()` to persist

### F4: Orient System Prompt Injection

In `session.go`, when `phase == PhaseOrient`:
- Read last 5 quality signals from mutations store
- Format a compact summary (under 200 tokens)
- Append to system prompt

### F5: Quality History Tool

New Orient-gated tool:
- `quality_history` — returns last N quality signals as formatted JSON
- Gated to `PhaseOrient` only in `gated_registry.go`
- Allows the LLM to drill down on specific patterns

## Success Criteria

1. After a session completes, a QualitySignal record exists in `~/.skaffen/mutations/quality-signals.jsonl`
2. New sessions started with `--phase orient` see quality history in their system prompt
3. `quality_history` tool is available during Orient phase and returns historical data
4. All existing tests pass (`go test ./... -count=1`)
5. New unit tests cover: signal aggregation, store read/write, prompt injection, tool execution
