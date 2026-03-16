---
id: "004"
status: open
priority: P3
title: "Autoresearch infrastructure (experiment loop)"
created: 2026-03-16
beads:
  - projects-z6k  # Parent epic: autonomous experiment loop for Skaffen [P3, in_progress]
  - Demarch-jd0   # Experiment tools (init/run/log) in Go [P2]
  - Demarch-rtt   # /autoresearch skill for Clavain [P2]
  - Demarch-zbd   # Evidence bridge + interlab mutation emit [P3]
  - Demarch-e7e   # TUI status bar + experiment overlay [P3]
---

# Autoresearch Infrastructure

## Summary
Port the pi-autoresearch pattern to Skaffen — domain-agnostic experiment loop that continuously optimizes a metric by making code changes, benchmarking, and keeping/reverting based on results.

## Plan
`docs/plans/2026-03-15-autoresearch-skaffen.md` (v2, post-review)

## Tasks

### Foundation (Tasks 1-3) — DONE
- [x] Task 1: Campaign YAML parser (`internal/experiment/campaign.go`)
- [x] Task 2: JSONL experiment store (`internal/experiment/store.go`)
- [x] Task 3: Git worktree operations (`internal/experiment/gitops.go`)

### Tool Adapters (Tasks 4-6) — DONE
- [x] Task 4: InitExperimentTool + narrow interfaces (`internal/tool/experiment_init.go`)
- [x] Task 5: RunExperimentTool + sandbox wrapping (`internal/tool/experiment_run.go`)
- [x] Task 6: LogExperimentTool + decision override (`internal/tool/experiment_log.go`)

### Integration (Tasks 7-10) — DONE
- [x] Task 7: Tool registration + phase gating (`internal/tool/builtin.go`)
- [x] Task 8: TUI experiment status slot (`internal/tui/status.go`, `app.go`)
- [x] Task 9: Evidence bridge (`internal/agent/deps.go`, `internal/evidence/emitter.go`)
- [x] Task 10: Clavain /autoresearch skill (`os/Clavain/skills/autoresearch/`)
