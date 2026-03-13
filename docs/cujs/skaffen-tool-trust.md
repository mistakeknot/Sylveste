---
artifact_type: cuj
journey: skaffen-tool-trust
actor: regular user (developer calibrating agent tool permissions)
criticality: p2
bead: Demarch-2c7
---

# Skaffen Tool Trust and Approval

## Why This Journey Matters

An autonomous agent that can run arbitrary bash commands, write files, and make API calls needs guardrails. But guardrails that require approval for every action turn the agent into a glorified autocomplete — the developer spends more time clicking "approve" than they save. The trust system must find the sweet spot: auto-approve safe, predictable actions while requiring confirmation for novel, destructive, or sensitive ones.

Skaffen's smart trust evaluator learns from the developer's approval patterns. Early sessions require frequent approval. As patterns emerge — "this developer always approves file reads in the project directory", "this developer always approves test runs" — the evaluator starts auto-approving those patterns. Destructive actions (file deletes, force pushes, network calls to unknown hosts) always require approval regardless of history.

This journey is critical because trust calibration determines the practical autonomy of every Skaffen session. Miscalibrated trust (too permissive) risks destructive actions. Miscalibrated trust (too restrictive) makes the agent too slow to be useful.

## The Journey

The developer starts a new Skaffen instance. No trust history exists. They give Skaffen a task: "Add a priority boost test to selector_test.go." Skaffen enters the Act phase and attempts to read `selector_test.go`. The TUI prompts: "Read file internal/mycroft/scheduler/selector_test.go? [y/n/always]"

The developer approves with "always" — file reads in the project directory are always safe. Skaffen notes the pattern: `read_file(path matches "internal/**") → auto_approve`. Next time Skaffen reads a file under `internal/`, no prompt appears.

Skaffen writes the test code. Prompt: "Write file internal/mycroft/scheduler/selector_test.go?" The developer approves. Skaffen runs `go test ./internal/mycroft/scheduler/`. Prompt: "Run bash: go test ./internal/mycroft/scheduler/? [y/n/always]" The developer approves with "always" for `go test` commands.

Over several sessions, the trust evaluator builds a profile:
- File reads: auto-approve for project files, prompt for external paths
- File writes: auto-approve for test files, prompt for production code
- Bash: auto-approve for `go test`, `go build`, `go vet`; prompt for everything else
- Network: always prompt (no auto-approve for network calls)

The developer can review and edit trust rules: the profile is stored in the session config, not hidden. They can tighten rules ("never auto-approve writes to cmd/") or loosen them ("auto-approve all git commands").

Phase gating adds a structural layer on top of trust. During the Orient phase, only read tools are available — even with full trust, Skaffen can't write files while orienting. During Act, the full tool set is available, gated by the trust evaluator. During Reflect, only read and evidence-emission tools are available.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Auto-approve rate reaches >80% after 5 sessions | measurable | Trust evaluator approves ≥80% of tool calls without prompting (configurable promotion threshold, default 5 approvals) |
| Destructive actions always require approval | measurable | File deletes, force pushes, rm commands never auto-approved |
| Phase gating blocks out-of-phase tool use | measurable | Write tool blocked during Orient phase |
| "Always" approval creates a persistent rule | measurable | Rule persists across sessions for same pattern |
| Developer can review and edit trust rules | measurable | Trust profile file is readable and editable |
| Trust calibration doesn't degrade safety | qualitative | No unintended destructive actions from auto-approval |
| New patterns prompt for approval (no silent failures) | measurable | Unknown tool+args patterns trigger approval prompt |

## Known Friction Points

- **Pattern matching granularity** — "auto-approve reads in internal/" is coarse. The developer might want "approve reads in internal/mycroft/ but not internal/secrets/". Pattern refinement UI is basic.
- **Trust doesn't transfer across projects** — a new project starts with zero trust even if the developer has extensive history elsewhere. Project-scoped by design, but cold-start is slow.
- **Trust sharing is read-only** — dispatched agents inherit the developer's global trust rules but cannot promote new patterns to global scope. This provides a safe cold-start for fleet agents while preventing untested patterns from propagating.
- **Phase gating uses softened boundaries** — Review phase allows `edit` (always prompted, rate-limited to 3 calls). Ship phase allows `edit`/`write` for manifest files (CHANGELOG, VERSION, *.md) but blocks code file edits. Brainstorm and Plan remain strictly read-only. Future evolution: risk scoring per action replaces static file-glob rules with learned risk thresholds.
