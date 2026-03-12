---
artifact_type: brainstorm
bead: Demarch-6qb
stage: brainstorm
---
# Brainstorm: Skaffen v0.1 Completion

## Context

Skaffen v0.1 (Go sovereign agent runtime) is 90%+ complete. 14 packages, 333+ tests, all 8 features (F1-F8) substantially implemented. This brainstorm scopes the remaining work to close the Demarch-6qb epic.

## What's Complete

All features (F1-F8) are implemented with one exception:

| Feature | Status | Tests |
|---------|--------|-------|
| F1: Provider abstraction + Anthropic + Claude Code proxy | Done | anthropic, claudecode pkgs |
| F2: Core tool system (7 tools + phase gating) | Done | tool pkg |
| F3: OODARC agent loop + agentloop library | Done | agent, agentloop pkgs |
| F4: Model routing (phase defaults, budget, complexity) | Done | router pkg (36 tests) |
| F5: Session persistence (JSONL) | Done | session pkg |
| F6: Evidence emission (local + intercore bridge) | Done | evidence pkg |
| F7: CLI entry point (print mode, version, flags) | Done | cmd/skaffen pkg |
| F8: TUI mode (trust, streaming, diff, slash commands) | Done except @-file | tui pkg |

## Remaining Work

### @-file mentions with fuzzy search in input composer

**What:** When the user types `@` in the prompt input, show a fuzzy file picker. Selecting a file inserts `@path/to/file` into the input. Before sending to the LLM, expand `@path` tokens to file contents.

**Design considerations:**
- Use `filepath.WalkDir` for file discovery (respect .gitignore via go-gitignore or simple exclusion list)
- Fuzzy matching: simple substring/prefix matching is sufficient for v0.1 (no need for Smith-Waterman)
- Popup overlay rendered in the prompt's View(), similar to how approval overlay works in app.go
- File content expansion happens in the submit path, before message is sent to the agent
- Token budget awareness: warn if expanded content is very large (>10K tokens)

**Implementation approach:**
1. Add `@` keystroke detection in prompt.go's Update()
2. File walker that caches the directory tree (invalidated on focus)
3. Fuzzy filter component (list of matches, arrow key navigation)
4. Selection inserts `@relative/path` into input
5. Expansion in app.go's submit handler: regex-find `@(\S+)`, read file, inject as context

**Scope:** ~150-200 lines across prompt.go + a new filepicker.go helper.

## Explicitly Deferred to v0.2

These items are marked deferred in the PRD and do NOT block v0.1:
- RPC mode/protocol (F7)
- TOML config file (F7)
- Phase boundary summary (F5)
- Priompt priority rendering, anchors, reactive compaction (F5)
- Goroutine-per-tool parallel execution (F3)
- Steering via RPC (F3)
- MCP client (F2 registry ready, no MCP transport)

## Epic Closure Criteria

1. Implement @-file mentions → check off last F8 criterion
2. All 333+ tests still pass
3. `skaffen` binary builds cleanly
4. Update PRD to mark @-file mentions complete
5. Close Demarch-6qb, unblock Demarch-mvy (Intercom Go rewrite)
