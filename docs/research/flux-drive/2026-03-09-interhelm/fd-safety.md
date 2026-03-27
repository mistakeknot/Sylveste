# Safety Review — interhelm Implementation Plan

**Document:** `docs/plans/2026-03-09-interhelm.md`
**Bead:** Sylveste-ekh
**Reviewer:** Flux-Drive Safety (fd-safety)
**Date:** 2026-03-24

---

## Threat Model

**Deployment context:** Claude Code plugin, runs as the local developer's user account. No network exposure of the plugin itself. The plugin teaches agents to scaffold diagnostic HTTP servers that bind locally, and ships hooks that execute as PostToolUse side-effects in Claude Code sessions.

**Trust boundary:** The hook scripts (`auto-health-check.sh`, `cuj-reminder.sh`, `browser-on-native.sh`) run with full developer privileges after every matching tool invocation. They receive arbitrary tool input from Claude Code's PostToolUse hook pipeline — specifically, the JSON blob from the tool call including user-controlled fields. The diagnostic server templates, once instantiated by agents in target projects, expose HTTP endpoints locally. The `handle_assert` template endpoint evaluates expressions.

**Untrusted inputs:**
- `tool_input` JSON parsed by hook scripts (originates from Claude Code tool calls, which may carry user-supplied strings)
- HTTP request bodies to `/diag/assert` and `/diag/diff` in templates generated from the skill
- `CLAUDE_PROJECT_ROOT` environment variable used by hooks

**Credentials:** No credentials are generated, stored, or processed by this plugin or its templates. No tokens appear in hook scripts.

**Risk classification: Medium** — new PostToolUse hooks that run shell scripts on every file edit and bash command; template code that includes a stub expression evaluator (`handle_assert`) which, when implemented, could be a code-execution surface; agent definition with unrestricted tool surface.

---

## Findings

### P0 — Critical

#### SAFE-001: handle_smoke_test returns hardcoded pass — false-positive safety signal

**Section:** Task 8 — Rust/Hyper Server Templates (F8), `handlers.rs`, `handle_smoke_test`

The `handle_smoke_test` stub always returns `"passed": 1, "failed": 0` regardless of actual application state. The stub locks on `state`, calls `health()`, but then ignores the result entirely and emits a fabricated pass response with a `CUSTOMIZE` note.

**Impact:** An agent using the `cuj-verification` skill will call `app-diag smoke-test` and receive a passing result even when the application is broken or the diagnostic server is not wired to real state. The runtime-reviewer agent's security review criteria explicitly checks whether production builds gate the diagnostic server — but an agent following `smoke-test-design` skill guidance will interpret the hardcoded pass as confirmation that the smoke test contract is functioning. This creates a false go signal for CUJ verification, which is the entire purpose of the plugin.

This is the ARCH-002 finding confirmed as a real safety concern. In the context of agent-driven verification, a hardcoded pass at the trust boundary between "does the app work" and "should I proceed" is a security-relevant false positive, not just a correctness issue.

**Mitigation:** The stub must return `501 Not Implemented` (consistent with how `handle_diff` and `handle_assert` are handled) rather than a fabricated pass. Alternatively, always return `"passed": 0, "failed": 1` with an explicit `"note": "CUSTOMIZE: not yet implemented"` so agents know the endpoint is a stub and cannot mistake it for a working verification.

---

### P1 — High Priority

#### SAFE-002: hook scripts extract and execute a binary path derived from CLAUDE.md without sanitization

**Section:** Task 7 — Hooks (F5, F6, F7), `auto-health-check.sh`

The hook reads a diagnostic CLI path from CLAUDE.md via regex, then executes it:

```bash
diag_cli=$(grep -oP 'CLI:\s*`\K[^`]+' "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null || true)
if [[ -n "$diag_cli" && -x "$PROJECT_ROOT/$diag_cli" ]]; then
    health_output=$("$PROJECT_ROOT/$diag_cli" health 2>/dev/null) || true
```

The value of `$diag_cli` comes directly from CLAUDE.md content. There is no character-set validation and no check that the resolved path stays within `$PROJECT_ROOT`. A path like `../../bin/malicious` would be accepted and executed.

**Attack surface:** The Sylveste CLAUDE.md security rules explicitly flag submodule and dependency CLAUDE.md files as untrusted. If a project has a symlinked path, a cloned dependency with its own CLAUDE.md, or an attacker-controlled CLAUDE.md (e.g., via a poisoned upstream), the hook will execute an attacker-chosen binary on every Rust source file edit.

**Mitigation:**
1. Validate `$diag_cli` against an allowlist: `[[ "$diag_cli" =~ ^[a-zA-Z0-9_./-]+$ ]]` and reject values containing `..`.
2. Resolve to an absolute path and assert it is a prefix of `$PROJECT_ROOT`.
3. Verify the file is a known interhelm-registered CLI (e.g., check for an interhelm marker in the binary's help output or alongside a companion `.interhelm-cli` sentinel file).

#### SAFE-003: runtime-reviewer agent definition omits tool restrictions — agent inherits full tool surface

**Section:** Task 6 — Runtime Reviewer Agent (F4), `agents/review/runtime-reviewer.md`

The agent frontmatter specifies only `name`, `description`, and `model`. No `allowed_tools` field is defined. In Claude Code, sub-agents inherit the full tool surface of the invoking session unless explicitly restricted. The runtime-reviewer agent's task is read-only review — it should only need Read, Grep, and Glob-type access. Without restrictions, the agent can execute arbitrary shell commands via Bash, modify files via Write/Edit, and make network requests.

This is the ARCH-005 finding confirmed. The agent's own security checklist (which it applies to target projects) explicitly flags unrestricted control access as a risk. The reviewer should model the principle it enforces.

**Mitigation:** Add `allowed_tools: [Read, Glob, Grep]` (or the Claude Code equivalent) to the agent frontmatter. Reference the fd-architecture agent at `interverse/interflux/agents/review/fd-architecture.md` to confirm the correct YAML field name for tool restrictions in this codebase.

#### SAFE-004: auto-health-check CLAUDE.md CLI path contract is undocumented and regex-fragile

**Section:** Task 7 — Hooks (F6), `auto-health-check.sh`

The hook assumes CLAUDE.md contains a backtick-fenced `CLI:` entry matching `CLI:\s*\`...\``. This contract appears only implicitly in the `runtime-diagnostics` skill's "Discovery Convention" section. There is no formal schema, no validation that the matched path refers to an interhelm CLI rather than any other backtick-surrounded string following the word "CLI:", and no documentation for project authors that this exact format is machine-parsed.

**Impact:** Projects using CLAUDE.md patterns like `CLI: \`clap\`-based argument parser` or `CLI: \`aws\`` in unrelated sections will have their CLI extracted and executed after every Rust source file edit. The first match wins — there is no disambiguation.

This is ARCH-006 confirmed.

**Mitigation:**
1. Define a namespaced marker: `<!-- interhelm:diag-cli: tools/app-diag -->` or a dedicated `.interhelm` config file, rather than parsing free-form CLAUDE.md text.
2. Document the exact contract in the plugin's AGENTS.md under "Discovery Convention."
3. Apply path-safety validation (see SAFE-002) regardless of source.

#### SAFE-005: control endpoint templates lack authentication — unauthenticated localhost mutations

**Section:** Task 8 — Rust/Hyper Server Templates (F8), `handlers.rs`

The `/control/restart`, `/control/reset`, and `/control/step` handlers perform state mutations with no authentication:

```rust
pub async fn handle_restart(_state: SharedState) -> Response<BoxBody> {
    json_response(serde_json::json!({"status": "restarted"}))
}
```

The server binds to `127.0.0.1` (correct), but bind address alone does not prevent other local processes from calling these endpoints. Any code running on the developer's machine — including browser tabs, other Claude Code sessions, npm scripts, or other plugins — can restart or reset the application state.

The runtime-reviewer agent's own security checklist flags "Control endpoints have guards (at minimum: only accept localhost connections)" as a P0 check, and "Rate limiting or request size limits on control endpoints" as P1 — but the templates ship without implementing either.

**Mitigation:** Add a static shared-secret header check at the top of control handlers. A token can be generated at server startup (printed to stderr and stored in a local temp file) and passed by the CLI via `--token`. Alternatively, mark the control handlers as `todo!()` stubs with an explicit comment that authentication is required before use, preventing agents from treating the stubs as production-ready.

---

### P2 — Notable

#### SAFE-006: handle_assert expression evaluation guidance absent — injection risk for template implementers

**Section:** Task 8 — Rust/Hyper Server Templates (F8); Task 3 — Runtime Diagnostics Skill (F1)

The `handle_assert` stub correctly returns 501. However, the `runtime-diagnostics` skill documents the endpoint accepting arbitrary expression strings like `"simulation.tick > 0 && economy.gdp > 0"`. No guidance is provided on how to implement the expression evaluator safely.

**Impact:** Template users following the skill will implement expression evaluation over application state. Naive implementations in interpreted language backends (Python, Node.js) commonly reach for dynamic code execution functions. The template provides no warning and no safe implementation sketch.

**Mitigation:** Add a `CUSTOMIZE` comment in `handle_assert` warning that the expression string must be treated as untrusted input, and recommending a bounded field-path comparison (key, operator, value triple) rather than arbitrary code execution. Consider providing a minimal safe implementation sketch in the skill documentation.

#### SAFE-007: CLI assert subcommand passes expression string to server verbatim with no length bound

**Section:** Task 9 — CLI Client Templates (F9), `main.rs`

The CLI `Assert` subcommand passes the raw command-line expression string directly as JSON to the server with no length limit or character filter. This is the entry point for expression injection if the server implements the assertion evaluator using a code-execution approach (see SAFE-006).

**Mitigation:** Low priority given the server stub returns 501, but the CLI should enforce a reasonable length limit (e.g., 1024 characters) and add a comment noting the expression is sent verbatim and the server must validate it.

#### SAFE-008: VERSION variable interpolated into Python source in bump-version.sh

**Section:** Task 10 — Scripts (F10), `bump-version.sh`

The shell script interpolates `$VERSION` directly into a Python one-liner string using single-quote wrapping. A version value containing a single quote or semicolon could break out of the Python string context and execute code.

**Impact:** This is a developer tool, not a hook processing untrusted input, so realistic risk is low. Automated CI systems or agent-driven version bumping with unusual version strings could trigger this.

**Mitigation:** Pass `$VERSION` as an environment variable and read it via `os.environ['VERSION']` in the Python code, or use `jq` for the JSON update to avoid source-embedding the version string.

---

### P3 — Low Priority

#### SAFE-009: cuj-verification skill examples lack note against non-localhost use

**Section:** Task 5 — CUJ Verification Skill (F3), `SKILL.md`

The skill documentation shows `curl -X POST http://localhost:9876/control/select ...` as a pattern. No note restricts this to localhost-only servers. Developers following the pattern may copy it verbatim for remote development or staging environments.

**Mitigation:** Add a one-line callout: "Diagnostic servers must bind to localhost only (127.0.0.1). Never expose `/control/*` over a network interface."

#### SAFE-010: Broad PostToolUse matchers fire on all tool uses across all projects

**Section:** Task 7 — Hooks (F7), `hooks.json`

The matchers `"Edit|Write"` and `"Bash"` fire on every file edit and every bash command in any session where the plugin is loaded, across all projects. While the hooks are advisory and fast-path exit quickly, a bug in either script (unexpected exit code, Python import error, parse failure) could disrupt the PostToolUse pipeline for all matching tool calls.

**Mitigation:** Add a fast-fail guard at the top of each hook that exits 0 immediately if `$CLAUDE_PROJECT_ROOT` does not contain a diagnostic server marker, or scope the matchers more narrowly (e.g., match only tool calls that include Rust source paths in their input).

---

## Deployment and Migration Review

This is a net-new plugin with no migration steps. No existing data or schemas are modified.

**Rollback:** Fully reversible. The plugin is a self-contained directory at `interverse/interhelm/`. Removal is non-destructive to other plugins. Templates are reference code and are not compiled as part of the plugin.

**Pre-deploy checks with measurable pass/fail criteria:**
1. `python3 -c "import json; json.load(open('interverse/interhelm/.claude-plugin/plugin.json'))"` — exits 0
2. `python3 -c "import json; d=json.load(open('interverse/interhelm/hooks/hooks.json')); assert 'PostToolUse' in d['hooks']"` — exits 0
3. `cd interverse/interhelm/tests && uv run pytest -q` — all pass, no failures
4. `test -x interverse/interhelm/hooks/auto-health-check.sh && test -x interverse/interhelm/hooks/browser-on-native.sh && test -x interverse/interhelm/hooks/cuj-reminder.sh` — exits 0

**Post-deploy verification:**
- Load the plugin in a test Claude Code session; confirm `interhelm:runtime-diagnostics`, `interhelm:smoke-test-design`, `interhelm:cuj-verification` appear in `/skills`
- Confirm `runtime-reviewer` appears in `/agents`
- Edit a non-Rust file; confirm `auto-health-check.sh` exits silently (no hook pipeline error)
- Edit a Rust file in a project without a diagnostic marker; confirm hook exits silently

**Sequencing note:** Autodiscovery will load interhelm on the next Claude Code session start after the directory exists. If `hooks.json` is malformed or hook scripts are not executable at that moment, hooks may silently fail (per the plan's Prior Learnings note). All pre-deploy checks must pass before the first session that uses the plugin.

---

## Summary Table

| ID | Severity | Area | Issue |
|----|----------|------|-------|
| SAFE-001 | P0 | templates/rust-hyper/handlers.rs | handle_smoke_test returns hardcoded pass — false-positive safety signal |
| SAFE-002 | P1 | hooks/auto-health-check.sh | CLI binary path derived from CLAUDE.md content executed without sanitization |
| SAFE-003 | P1 | agents/review/runtime-reviewer.md | Agent definition omits tool restrictions — full tool surface inherited |
| SAFE-004 | P1 | hooks/auto-health-check.sh | CLAUDE.md CLI path contract undocumented, fragile regex, wrong binary execution risk |
| SAFE-005 | P1 | templates/rust-hyper/handlers.rs | Control endpoints lack authentication guards in template |
| SAFE-006 | P2 | templates + runtime-diagnostics skill | Expression evaluator guidance absent — injection risk for template implementers |
| SAFE-007 | P2 | templates/cli/main.rs | CLI assert subcommand passes expression verbatim with no bounds |
| SAFE-008 | P2 | scripts/bump-version.sh | VERSION interpolated into Python source — code injection via unusual version strings |
| SAFE-009 | P3 | skills/cuj-verification/SKILL.md | curl examples lack note against non-localhost use |
| SAFE-010 | P3 | hooks/hooks.json | Broad PostToolUse matchers fire on all tool uses across all projects |

---

### Findings Index
- P0 | SAFE-001 | "Task 8: Rust/Hyper Server Templates (F8)" | handle_smoke_test returns hardcoded pass — false-positive safety signal
- P1 | SAFE-002 | "Task 7: Hooks (F5, F6, F7)" | CLI binary path derived from CLAUDE.md content executed without sanitization
- P1 | SAFE-003 | "Task 6: Runtime Reviewer Agent (F4)" | Agent definition omits tool restrictions — agent inherits full tool surface
- P1 | SAFE-004 | "Task 7: Hooks (F6)" | auto-health-check CLAUDE.md CLI path contract undocumented and fragile
- P1 | SAFE-005 | "Task 8: Rust/Hyper Server Templates (F8)" | Control endpoints lack authentication guards in template
- P2 | SAFE-006 | "Task 8 + Task 3" | Expression evaluator guidance absent — injection risk for template implementers
- P2 | SAFE-007 | "Task 9: CLI Client Templates (F9)" | CLI assert subcommand passes expression verbatim with no bounds
- P2 | SAFE-008 | "Task 10: Scripts (F10)" | VERSION interpolated into Python source in bump-version.sh
- P3 | SAFE-009 | "Task 5: CUJ Verification Skill (F3)" | curl examples lack note against non-localhost use
- P3 | SAFE-010 | "Task 7: Hooks (F7)" | Broad PostToolUse matchers fire on all tool uses across all projects

<!-- flux-drive:complete -->
