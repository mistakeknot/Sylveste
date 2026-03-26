# Architecture Review — interhelm Implementation Plan

**Document:** `docs/plans/2026-03-09-interhelm.md`
**Plugin:** `interverse/interhelm/`
**Plan date:** 2026-03-09
**Review date:** 2026-03-24
**Reviewer:** fd-architecture (Flux-drive)

---

## Grounding

Read: `CLAUDE.md`, `AGENTS.md`, `agents/architecture.md`, `agents/design-doctrine.md`, `interverse/interhelm/.claude-plugin/plugin.json` (live, v0.2.0), `interverse/interlock/hooks/hooks.json` (reference), `interverse/interflux/.claude-plugin/plugin.json` (reference).

The plan targets a new Interverse plugin named interhelm. The plugin is documented as standalone (no intercore dependency, confirmed in architecture.md's standalone list). The live plugin has already diverged from the plan: it ships 4 skills (vs 3 in the plan), is at v0.2.0, and the CLAUDE.md quick-commands reference `ls skills/*/SKILL.md | wc -l  # Should be 4`. Several structural observations below apply to the plan as written rather than solely to the already-implemented artifact; where the implementation has already resolved a concern, this is noted.

---

## 1. Boundaries and Coupling

### Plugin boundary is clean and intentional

The "standalone" classification is correct. interhelm has no declared dependencies on intercore, Clavain, or any other plugin. The plan correctly avoids importing shared SDK code and keeps all runtime logic inside the plugin boundary. This aligns with the design doctrine: "standalone plugins" listed in architecture.md include interhelm explicitly.

### auto-health-check hook reaches into target project filesystem

The auto-health-check.sh hook parses a path out of stdin JSON, checks whether it ends in `.rs`, then reads the target project's `CLAUDE.md` to discover a `CLI:` line and executes that binary. This creates an undeclared runtime coupling to the consuming project's local filesystem layout and binary availability. The hook cannot know whether the diagnostic CLI is compiled or accessible, and a failing `$diag_cli health` call is silenced with `|| true`. This is acceptable for an advisory hook, but the filesystem read creates a hidden dependency on CLAUDE.md's specific format (`CLI: \`...\``). If that format changes in the target project, the hook silently degrades without logging.

The design doctrine says hooks handle per-file automatic enforcement at the single-concern level. This hook merges three concerns: (a) detecting that the edited file is a Rust source, (b) discovering the diagnostic CLI path from CLAUDE.md, (c) executing the CLI and filtering its output. The discovery concern (b) is a hidden contract with the consuming project that is not described in the plugin's AGENTS.md contract table.

Smallest fix: document the CLAUDE.md contract format in AGENTS.md under "Core Patterns" so consuming projects know the hook depends on `CLI: \`...\`` being present.

### browser-on-native hook conflates project-type detection with diagnostic server detection

The hook checks for a diagnostic server in CLAUDE.md first, then checks for native-app markers. The logical dependency is inverted: the actionable condition is "this is a native app project and it has a diagnostic server." Reading CLAUDE.md before checking the filesystem layout is harmless but reads more than necessary. This is minor.

### cuj-reminder hook fires on every `git commit` Bash invocation

The hook triggers on any Bash command containing `git commit`, regardless of whether any files relevant to CUJ verification were changed. In a monorepo session where an agent commits documentation or test fixtures, this reminder fires. Because the hook is async and advisory the impact is noise rather than breakage, but it reduces signal-to-noise ratio and may erode trust in the reminder over time. A session that commits 6 times will receive 6 reminders if the project has a diagnostic server.

Smallest fix: check whether the committed files include `src/` or app-relevant paths before emitting the reminder. Alternatively, limit the hook to sessions within a known diagnostic-server project by requiring not just "diagnostic server in CLAUDE.md" but also a resolvable diagnostic CLI.

### Runtime reviewer agent lacks tool restrictions

The `runtime-reviewer.md` frontmatter sets `model: sonnet` but does not declare `allow_tools` or a minimal tool set. The agent's review task (reading source files to check for `#[cfg(debug_assertions)]`, identifying endpoint implementations, checking bindings) requires only read-access tools. Without tool restrictions, the agent inherits the full tool surface and could, under adversarial or confused conditions, execute code or modify files while conducting what is supposed to be a read-only review. Both the reference agent `fd-architecture.md` and interflux's other review agents omit explicit tool restrictions, so this is an ecosystem-wide gap, but it is worth flagging here because the reviewer's security checks include "control endpoints have guards" — the same principle applies to the reviewer agent itself.

### Plan/implementation divergence: 4th skill not in plan

The live plugin at v0.2.0 includes a 4th skill, `diagnostic-maturation`, which is not in the plan. The CLAUDE.md quick-commands section already reflects `# Should be 4`. The structural tests in `test_skills.py` assert `len(skills) == 3`, which means the test suite will fail against the live plugin. This creates a plan-implementation gap that will mislead an agent executing the plan task-by-task (Task 10 step 7 says "all tests pass" but the count assertion is now wrong).

This is the most operationally risky gap: the tests explicitly hardcode 3 and the live state is 4.

---

## 2. Pattern Analysis

### Hook format follows the documented event-key object format

The hooks.json uses the correct record format (not flat array), matching the reference at `interverse/interlock/hooks/hooks.json`. The prior learning about silent failures on the wrong format is correctly applied. This is correct.

### plugin.json follows the established plugin scaffold pattern

The manifest structure matches `interverse/interflux/.claude-plugin/plugin.json` in all key respects: lowercase name, semver version, skills as relative paths, agents as relative paths. No mcpServers key is registered (appropriate, since this is a pattern plugin with no server process). Correct.

### Rust template uses `Arc<Mutex<T>>` — appropriate but underconstrained

The state.rs template uses `Arc<Mutex<T>>` for shared state. The comment in main.rs recommends gating behind `#[cfg(debug_assertions)]`. The handlers.rs template for `handle_health` calls `state.lock().unwrap()` — panicking on mutex poisoning. In a diagnostic server that runs on a separate tokio task, a panicking diagnostic handler would tear down only that connection, not the application. However, an agent copying this template might not realize that `unwrap()` on a mutex lock is inappropriate for a server context. A `match` or `?`-returning error path would be safer. This is a template quality concern rather than an architecture violation.

### Smoke test handler returns a hardcoded pass — misrepresents readiness

`handle_smoke_test` in handlers.rs returns a hardcoded `"passed": 1, "failed": 0` response. The comment says "CUSTOMIZE: add your smoke test checks." This means an agent running `app-diag smoke-test` against an unmodified template will see `1/1 passed` even though nothing has been verified. This is a false-positive pattern that contradicts the smoke-test-design skill's principle "never delete a smoke test check to make tests pass." A stub that returns `501 Not Implemented` would be more honest — consistent with how `handle_diff` and `handle_assert` are stubbed.

### assert expression evaluator is underdefined across the skill/template boundary

The cuj-verification skill teaches `app-diag assert "panels.inspector.visible == true && panels.inspector.selected_entity == 'country_42'"` and the smoke-test-design skill teaches inline assertion expressions like `"simulation.tick > 0 && economy.gdp > 0"`. However, `handle_assert` in the server template returns 501, and the CLI's `Commands::Assert` sends the expression as a JSON string but the server has no expression evaluator. Agents following the skill guidance would write assertions, send them to the server, and receive 501. The skill does not explain that the assert evaluator must be implemented before assertions work. This creates a gap between the skill's teaching and the template's readiness: the skill implies assertions are available after scaffolding, but they require custom implementation.

This is a cohesion issue between the skill layer (what to do) and the template layer (how to implement it). The skill should clarify that the assert pattern requires implementing the expression evaluator before use.

### Watch command uses blocking thread sleep in async binary

The CLI template uses `reqwest::blocking` throughout and `std::thread::sleep` in the `Watch` subcommand, but the binary's `main` is annotated `#[tokio::main]`. Mixing `reqwest::blocking` with a `tokio::main` entry point requires the blocking runtime feature but can deadlock if the blocking calls execute on the tokio executor thread. The CLI template does not use `.await` or tokio's async APIs, so the `#[tokio::main]` annotation is vestigial. An agent customizing this template should either remove `#[tokio::main]` and drop the tokio dependency, or switch to `reqwest`'s async API. As a reference template this will compile but misleads readers about the architectural choice.

---

## 3. Simplicity and YAGNI

### Three skills cover distinct concerns with no overlap

`runtime-diagnostics` (scaffold the server), `smoke-test-design` (design the contract), `cuj-verification` (use the contract to verify journeys). Each skill is independently useful. The live fourth skill, `diagnostic-maturation`, teaches evolution from scaffold to production-grade tooling. All four have a single, bounded concern. No skill duplication detected.

### Two template directories duplicate Cargo.toml boilerplate

Both `templates/rust-hyper/Cargo.toml` and `templates/cli/Cargo.toml` are standalone templates that an agent copies. There is no shared Cargo workspace. This is intentional — these are copy-and-customize templates, not integrated packages. The duplication is appropriate here.

### bump-version.sh is four lines and does one thing

The script is appropriately minimal. No concern.

### Structural tests hardcode counts

Both `test_skill_count` (expects 3) and `test_agent_count` (expects 1) are assertions on absolute counts. This makes the tests brittle to any future capability addition and will fail against the current live state (4 skills). These tests should either use `>=` comparisons with minimum viable counts, or be updated to reflect 4 skills. Count-exact tests are a Goodhart trap: they do not verify the right thing (that declared components exist and are well-formed), they verify component count, which is a proxy that becomes wrong as soon as the plugin grows.

### PostToolUse matcher `"Edit|Write"` is ambiguous

The hooks.json matcher `"Edit|Write"` assumes pipe-delimited OR matching. The reference hook format from interlock uses plain strings for matchers (`"Edit"`, `"startup|resume|clear|compact"`). The plan references `interverse/interlock/hooks/hooks.json` as the canonical format. Interlock does use pipe-delimited strings for SessionStart, so pipe-OR is the established convention. The pattern `"Edit|Write"` should work, but it has not been validated against a Write-tool invocation in the current codebase and the plan does not include a test for it. Minor, but worth a note.

### Python inline execution in bump-version.sh is fragile

The bump-version.sh script embeds a Python heredoc inside a single `-c` string using variable interpolation (`d['version'] = '$VERSION'`). If `$VERSION` contains a single quote or shell-special character this produces broken Python. This is unlikely for semver strings but represents a shell injection risk. Using `jq` or a separate Python file would be safer. This matches the global CLAUDE.md restriction against heredocs in Bash tool calls, though here it appears in a committed script rather than an ad-hoc Bash invocation.

---

## Summary of Must-Fix vs Optional

**Must-Fix:**

1. `test_skills.py` hardcodes `len(skills) == 3` but the live plugin has 4 skills. The test suite will fail and will mislead agents executing the plan. Update the count to 4 (or use `>=3` minimum assertions) and reflect `diagnostic-maturation` in the plan's artifacts list.

2. `handle_smoke_test` returns a hardcoded pass, creating false-positive results for any agent using an unmodified template. Change to 501 Not Implemented to match `handle_diff` and `handle_assert`, or return an explicit "stub — customize before use" payload with passed=0.

3. The plan's "Must-Haves / Artifacts" section lists the 4th skill (diagnostic-maturation) does not appear as a planned requirement. The plan should either document F11 as a requirement or the CLAUDE.md/plugin.json should revert to 3 skills. As written, the plan describes a plugin that does not match what has been built.

**Should-Fix:**

4. The cuj-verification skill does not warn that `POST /diag/assert` requires implementing the expression evaluator before assertions will work. Add a "Prerequisites" callout that `handle_assert` starts as a 501 stub.

5. The runtime-reviewer agent should specify a read-only tool allowlist (e.g., `allow_tools: [Read, Grep, Glob]`) to enforce that it cannot mutate files during a review pass.

6. Document the CLAUDE.md hook contract (`CLI: \`...\``) in AGENTS.md so consuming projects know what format enables the auto-health-check hook.

**Optional Cleanup:**

7. `test_skill_count` and `test_agent_count` should use minimum-count assertions rather than exact counts, or add a comment justifying the exact count.

8. The CLI template should remove `#[tokio::main]` since all HTTP calls use `reqwest::blocking` and the async runtime is unused.

9. bump-version.sh should use `jq` or a separate Python script to avoid the embedded inline Python with variable interpolation.

10. The cuj-reminder hook fires on every `git commit` regardless of which files were committed. Consider scoping the trigger to commits that include `src/` paths.

---

### Findings Index
- P1 | ARCH-001 | "Task 10: Scripts and Structural Tests" | Structural test hardcodes 3 skills but live plugin has 4 — test suite will fail
- P1 | ARCH-002 | "Task 8: Rust/Hyper Server Templates" | handle_smoke_test returns hardcoded pass — false-positive result on unmodified template
- P1 | ARCH-003 | "Must-Haves / Artifacts" | diagnostic-maturation skill added in live plugin but absent from plan requirements and artifacts list
- P2 | ARCH-004 | "Task 5: CUJ Verification Skill" | Skill teaches assert pattern without warning that handle_assert starts as 501 stub requiring custom implementation
- P2 | ARCH-005 | "Task 6: Runtime Reviewer Agent" | Agent definition omits tool restrictions — review agent should be read-only but inherits full tool surface
- P2 | ARCH-006 | "Task 7: Hooks" | auto-health-check hook depends on undocumented CLAUDE.md format contract; consuming projects have no guidance
- P3 | ARCH-007 | "Task 9: CLI Client Templates" | CLI template uses reqwest::blocking throughout but declares #[tokio::main] — async runtime is unused and misleads readers
- P3 | ARCH-008 | "Task 7: Hooks" | cuj-reminder fires on every git commit regardless of changed files — degrades signal-to-noise ratio over long sessions
- P3 | ARCH-009 | "Task 10: Scripts and Structural Tests" | test_skill_count and test_agent_count use exact counts, making tests brittle to future capability additions

<!-- flux-drive:complete -->
