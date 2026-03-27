---
artifact_type: cuj
journey: skaffen-tool-trust
actor: regular user (developer calibrating agent tool permissions)
criticality: p2
bead: Sylveste-2c7
---

# Skaffen Tool Trust and Approval

## Why This Journey Matters

An autonomous agent that can run arbitrary bash commands, write files, and make API calls needs guardrails. But guardrails that require approval for every action turn the agent into a glorified autocomplete — the developer spends more time clicking "approve" than they save. The trust system must find the sweet spot: auto-approve safe, predictable actions while requiring confirmation for novel, destructive, or sensitive ones.

Skaffen's smart trust evaluator learns from the developer's approval patterns. Early sessions require frequent approval. As patterns emerge — "this developer always approves file reads in the project directory", "this developer always approves test runs" — the evaluator starts auto-approving those patterns. Destructive actions — defined as deny-by-default for unknown bash commands, plus an explicit block list (file deletes, force pushes, `rm`, `git reset --hard`, file truncation via redirect) — always require approval regardless of history.

This journey is critical because trust calibration determines the practical autonomy of every Skaffen session. Miscalibrated trust (too permissive) risks destructive actions. Miscalibrated trust (too restrictive) makes the agent too slow to be useful.

## The Journey

The developer starts a new Skaffen instance. No trust history exists, but built-in rules provide a safe baseline: file reads are auto-approved for project paths, common safe commands (`go test`, `go build`, `go vet`) are auto-approved, and unknown bash commands default to Prompt. They give Skaffen a task: "Add a priority boost test to selector_test.go."

Skaffen enters the Act phase and attempts to read `selector_test.go`. The built-in rule auto-approves file reads in the project directory — no prompt. Skaffen writes the test code. Prompt: "Write file internal/mycroft/scheduler/selector_test.go? [y/n/always]" The developer approves with "always" for test files.

Skaffen runs `go test ./internal/mycroft/scheduler/`. The built-in rule auto-approves `go test` — no prompt. But if Skaffen tries to run an unfamiliar command (`curl`, `docker`, `pip install`), the deny-by-default policy triggers a prompt.

Over several sessions, the trust evaluator builds a learned profile:
- File reads: auto-approve for project files, prompt for external paths
- File writes: auto-approve for test files, prompt for production code
- Bash: auto-approve for `go test`, `go build`, `go vet`; prompt for everything else
- Network: always prompt (no auto-approve for network calls)

After a pattern is approved 5 times (configurable via `PromoteThreshold`), it auto-promotes from session scope to global scope. The developer can review and edit trust rules — the profile is stored as a TOML file (`trust.toml` in the session/project config directory), human-readable and editable. They can tighten rules ("never auto-approve writes to cmd/"), loosen them ("auto-approve all git commands"), or revoke a previously learned pattern that turned out to be unsafe (`skaffen trust revoke <pattern>`).

Phase gating adds a structural layer on top of trust. The relationship between phase gates and trust depends on the current trust level:

- **At default trust (L0-L1):** Strict phase gates. During Orient, only read tools are available — even with full trust, Skaffen can't write files while orienting. During Act, the full tool set is available, gated by the trust evaluator. During Reflect, only read tools are available.
- **At earned trust (L2+):** Softened phase gates. Reflect allows `edit` (always prompted, rate-limited to 3 calls per phase) for fixing typos found during review. Compound allows `edit`/`write` for manifest files (CHANGELOG, VERSION, `*.md`) but blocks code file edits.

This progression matches Sylveste's "evidence earns authority" principle — strict gates are the default, softening is earned through demonstrated safety.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Auto-approve rate reaches >80% after 5 sessions | measurable | Trust evaluator approves ≥80% of tool calls without prompting (configurable promotion threshold, default 5 approvals); measured against novel patterns, not built-in allow-list |
| Destructive actions always require approval | measurable | Deny-by-default for unknown bash commands; explicit block list (rm, force-push, reset, truncation) never auto-approved regardless of history |
| Phase gating enforced at current trust level | measurable | At L0-L1: write tools blocked outside Act. At L2+: softened gates allow scoped edits in Reflect/Compound |
| "Always" approval creates a persistent rule | measurable | Rule persists across sessions for same pattern; stored in `trust.toml` |
| Developer can review, edit, and revoke trust rules | measurable | Trust profile file is human-readable TOML; `skaffen trust revoke <pattern>` removes unsafe rules |
| Trust calibration doesn't degrade safety | qualitative | No unintended destructive actions from auto-approval; user overrides cannot bypass the explicit block list |
| New patterns prompt for approval (no silent failures) | measurable | Unknown tool+args patterns trigger approval prompt (deny-by-default for bash) |

## Known Friction Points

- **Pattern matching granularity** — "auto-approve reads in internal/" is coarse. The developer might want "approve reads in internal/mycroft/ but not internal/secrets/". Pattern refinement UI is basic. Workaround: edit `trust.toml` directly with more specific glob patterns.
- **Trust doesn't transfer across projects** — a new project starts with zero learned trust even if the developer has extensive history elsewhere. Project-scoped by design, but cold-start is slow. Built-in rules provide the baseline.
- **Trust sharing is read-only** — dispatched agents inherit the developer's global trust rules but cannot promote new patterns to global scope. This provides a safe cold-start for fleet agents while preventing untested patterns from propagating.
- **Phase softening is trust-level dependent** — developers at L0-L1 experience strict binary gates. Softened gates (edit in Reflect, manifest writes in Compound) are only available at L2+, which requires demonstrated safety history. This can feel restrictive during early sessions.
- **Compound writes go through trust evaluator** — auto-compound to `docs/solutions/` is gated by the trust evaluator like any other write, ensuring the agent can't write to arbitrary locations during the Compound phase.
