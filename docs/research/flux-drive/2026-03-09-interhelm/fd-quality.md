---
artifact_type: flux-drive-review
reviewer: fd-quality
plan: docs/plans/2026-03-09-interhelm.md
bead: Demarch-ekh
---

# Quality & Style Review — interhelm Implementation Plan

## Scope

Plan at `docs/plans/2026-03-09-interhelm.md` — 11 tasks spanning plugin scaffold, docs, 3 skills, 1 agent, 3 hooks, Rust/hyper server templates, CLI client templates, and structural tests. Languages in scope: Bash (hooks, scripts), Rust (templates — reference only, not compiled), Python (structural tests via pytest). The review aligns against the Demarch monorepo conventions documented in `CLAUDE.md` and `AGENTS.md`, plus the prevailing patterns visible in `interverse/intertest/`, `interverse/interlock/`, and `interverse/interflux/`.

---

## Universal Review

### Naming

Conventions are well-aligned throughout. All identifiers follow kebab-case for skill dirs (`runtime-diagnostics`, `smoke-test-design`, `cuj-verification`), snake_case for Python, and the `interhelm:` namespace prefix is stated explicitly in AGENTS.md. The agent file `runtime-reviewer.md` and skill names all match their frontmatter `name:` fields. The directory hierarchy mirrors the established `skills/*/SKILL.md` and `agents/review/*.md` pattern from intertest and interflux.

One inconsistency: `CLAUDE.md` as written in the plan says "3 skills, 1 agent, 3 hooks" (Task 2, Step 1), but the existing `interverse/interhelm/CLAUDE.md` already reads "4 skills". This suggests a fourth skill was added after the plan was frozen. The plan's structural test `test_skill_count` hard-codes `len(skills) == 3`, which will fail immediately against the live repo. This is a concrete correctness issue for anyone executing the plan as written.

### File Organization

The directory layout proposed in Task 1 (`mkdir -p ...`) matches the interverse plugin standard: `.claude-plugin/`, `skills/*/`, `agents/review/`, `hooks/`, `templates/`, `scripts/`, `tests/structural/`. The `tests/` subtree uses `pyproject.toml` + `uv run pytest`, consistent with the project's Python tooling preference.

The `conftest.py` fixture `project_root` resolves as `Path(__file__).resolve().parent.parent.parent`. This traverses `tests/structural/ → tests/ → interhelm/`, which is correct. Worth noting so implementors don't offset by one.

### Error Handling

**Bash hooks.** All three hook scripts open with `set -euo pipefail`, which is correct. However, the Python-in-subprocess pattern used to parse stdin JSON is fragile in a specific way: the `except: pass` bare-except clauses swallow all errors silently, including import errors, decode errors, and unexpected JSON shapes. This means hooks will silently produce no output rather than a useful error message when the JSON is malformed or the `python3` binary is missing. For advisory-only hooks this is tolerable, but a bare `except` is not a good habit in scripts that are supposed to communicate intent to agents.

The `auto-health-check.sh` script constructs the diagnostic CLI invocation with `"$PROJECT_ROOT/$diag_cli"`. If `diag_cli` contains spaces or path components with unusual characters, this could fail. The `grep -oP` for extracting the CLI path from CLAUDE.md is the fragile core: it reads a freeform markdown file with a Perl regex to extract a path. If the CLAUDE.md section is formatted differently, the hook silently exits without a health check — which is acceptable given the advisory design, but worth calling out as a known brittleness.

**Rust templates.** `state.lock().unwrap()` is used throughout `handlers.rs` and in `handle_step`. For a diagnostic server that is intentionally simple and template-focused, `unwrap()` on mutex locks is defensible since a poisoned mutex signals a programmer bug in the main application. However, the comment in main.rs's `start_diag_server` uses `expect("Failed to bind diagnostic server")` and `expect("Failed to accept connection")`, which will panic the server on bind failure or accept error. A template that agents copy from should model at minimum logging + continue on accept errors rather than panicking the entire server on a transient connection failure.

**Python tests.** Test failures produce the standard pytest output. No silent swallowing. This is fine.

### Test Strategy

The structural test suite is the right type for this kind of pattern plugin. It validates layout contracts (files exist, frontmatter has required keys, hooks use valid event names, scripts are executable) without trying to execute runtime behavior. This matches the risk profile: the thing most likely to go wrong is an agent misplacing a file or omitting a frontmatter field.

`test_skill_frontmatter` validates `name`, `description`, and that `name` matches the directory name. `test_agent_frontmatter` validates `name`, `description`, and `model`. These are the right checks given the domain criteria.

One gap: there is no test that validates skill descriptions meet the project's one-line standard (non-empty string, not just whitespace). The `runtime-diagnostics` description is 57 words long and well-formed. The test ensures `description` is present but does not guard against a future empty string or placeholder.

A second gap: `test_hooks_scripts_executable` checks `hooks/*.sh` but not `scripts/*.sh`. The separate `test_scripts_executable` covers `scripts/*.sh` — this is fine but the duplication could be collapsed to a single parametrized fixture. Minor.

### API Consistency

The hooks.json in Task 7 uses `${CLAUDE_PLUGIN_ROOT}` to locate hook scripts. This matches the `interverse/interlock/hooks/hooks.json` reference format. Consistent.

The skill frontmatter format (YAML block with `name:` and `description:`) matches `interverse/intertest/skills/systematic-debugging/SKILL.md`. Consistent.

The agent frontmatter includes `name`, `description`, and `model: sonnet`. The interflux reference agents use the same three fields. Consistent.

### Complexity Budget

The plan is well-scoped. Tasks are independent, commit-gated, and each has a `<verify>` block. The hooks have appropriate advisory-only semantics (they emit suggestions but never block). The Rust templates are reference-only and explicitly not compiled as part of the plugin. The Python tests are thin structural checks.

The `auto-health-check.sh` hook is the most complex script (reads stdin, parses JSON via Python subprocess, extracts a CLI path from CLAUDE.md, invokes the CLI). Given its advisory nature, this complexity is acceptable but the grep-from-markdown approach is specifically fragile (see Error Handling above).

### Dependency Discipline

Python tests require only `pytest` and `pyyaml` — both standard, no new dependencies. Rust templates use `hyper 1.x`, `tokio`, `serde`, `serde_json`, `clap 4`, `reqwest 0.12`, `colored 2` — all standard choices for a Rust HTTP CLI in 2026. No unnecessary dependencies introduced.

---

## Language-Specific Review

### Bash

**`set -euo pipefail`** — present in all three hooks and `bump-version.sh`. Correct.

**Bare except in embedded Python:** All three hook scripts use an embedded Python one-liner with `except: pass`. This is the most pervasive quality issue across the hooks. The pattern should be `except Exception as e: import sys; print(f"interhelm: hook parse error: {e}", file=sys.stderr)` or at minimum `except (json.JSONDecodeError, KeyError): pass` to catch only expected errors rather than swallowing everything including `SystemExit` and `KeyboardInterrupt`.

**Quoting:** Variables `$FILE_PATH`, `$COMMAND`, `$PROJECT_ROOT`, `$diag_cli` are all double-quoted where used in commands. The case statement patterns (`*src-tauri/*.rs`) are unquoted as required by shell syntax. This is correct.

**`$is_native` boolean flag:** `browser-on-native.sh` sets `is_native=false` then conditionally sets `is_native=true`, then uses `if $is_native`. This pattern executes the value of `$is_native` as a command (`false` or `true` are builtins), which is valid POSIX but unusual. The more idiomatic pattern would be `[[ "$is_native" == "true" ]]`. The current pattern works but may surprise readers.

**No `trap` for cleanup:** None of the hooks create temp files or background jobs, so no `trap` is needed. Correct.

**`bump-version.sh`:** Uses `cd "$ROOT"` (absolute, computed) before the Python one-liner. This is safe. The Python snippet uses `f.seek(0)` + `f.write('\n')` + `f.truncate()` for in-place JSON rewrite — standard pattern, correct.

### Python

**Type hints absent from `conftest.py`:** The fixtures return typed values (`Path`, `dict`) but lack annotations. Given the project uses `pytest>=8.0` and Python `>=3.12`, adding `-> Path` and `-> dict` return annotations on fixtures would match the project's typing expectations and improve IDE support. This is a minor style issue, not a correctness issue.

**`yaml.safe_load` used correctly.** `test_skill_frontmatter` and `test_agent_frontmatter` use `yaml.safe_load` (not `yaml.load`). Correct.

**Bare `import yaml`** without try/except in `test_skills.py`. If `pyyaml` is missing from the venv, the import error will surface at collection time with a clear message. This is fine — pytest handles it gracefully.

**`test_agent_frontmatter` iterates `agents_dir.rglob("*.md")`** — this will pick up any markdown file under `agents/`, not just the direct children. Given the plan places agents at `agents/review/*.md`, this is correct. If someone adds a stray README.md under `agents/`, it will be tested unnecessarily. Minor.

### Rust

**`state.lock().unwrap()` poisoning behavior:** Covered above. In a template, using `unwrap()` is documented behavior — the `CUSTOMIZE:` comments are clear about the pattern. However, `handle_step` acquires a `mut` lock and modifies `simulation.tick` directly without any guard against concurrent control calls. For a template that teaches agents, showing an explicit comment that the `control/step` endpoint should guard against concurrent mutations (per the SKILL.md requirement) would make the template more consistent with its own documentation.

**`expect("Failed to accept connection")` panics the server:** In `start_diag_server`, the `listener.accept().await.expect(...)` call will terminate the server loop on any transient accept error (e.g., a connection reset). The correct pattern for a long-running accept loop is:

```rust
match listener.accept().await {
    Ok((stream, _)) => { /* spawn handler */ }
    Err(e) => { eprintln!("accept error: {e}"); continue; }
}
```

This is a correctness issue in the template: copying it verbatim produces a server that crashes on a transient network error. The `CUSTOMIZE:` comments do not flag this.

**`json_response` and `error_response` use `.unwrap()` on `Response::builder()`:** These builders return errors only when headers contain non-ASCII bytes, which is impossible here. The `unwrap()` is safe in practice. This is fine for a template.

**Timestamp format:** `format!("{:?}", std::time::SystemTime::now())` produces a debug-format timestamp like `SystemTime { tv_sec: ..., tv_nsec: ... }`, not an ISO 8601 string. The CUSTOMIZE comment acknowledges this (`use chrono::Utc::now().to_rfc3339() if chrono is available`), but the comment is buried mid-struct. A better approach for the default: `std::time::UNIX_EPOCH.elapsed().map(|d| d.as_secs().to_string()).unwrap_or_default()` gives a parseable epoch timestamp without adding a dependency. The current debug format will confuse agents reading the health output.

**CLI uses `reqwest::blocking` with `#[tokio::main]`:** `main.rs` uses `clap` + `reqwest::blocking` for a synchronous CLI, which is correct and simple. The `watch` command calls `std::thread::sleep` inside a `#[tokio::main]` context — this blocks the tokio thread. Since the `blocking` feature is being used throughout, there is no async runtime actually needed in the CLI. The `#[tokio::main]` macro could be removed and replaced with a synchronous `fn main()`. Adding `tokio` as a dependency solely for the `#[tokio::main]` macro when using only blocking I/O is an unnecessary dependency.

---

## Claude Code Plugin Domain Checks

**Skill descriptions:** All three skill `description:` fields are present and exceed one line. They read as activation conditions ("Use when..."), which is the correct pattern for skill descriptions in this ecosystem.

**`runtime-diagnostics` description** is 57 words — substantive and useful, though noticeably longer than the `systematic-debugging` reference (8 words). This is a style difference, not a defect. The longer format may be intentional given the plugin's teaching purpose.

**Agent description** in `runtime-reviewer.md` frontmatter includes two `<example>` blocks with `<commentary>` tags and invocation language. This matches the interflux agent reference format and meets the "example outputs and success criteria" criterion.

**Skill file length:** `runtime-diagnostics/SKILL.md` is approximately 180 lines (based on content in the plan). This exceeds the 100-line guideline. The content is substantive and organized into labeled steps, but could be trimmed by extracting the endpoint reference tables to a separate `reference.md` in the same directory and linking from the skill. The `smoke-test-design` and `cuj-verification` skills appear to fall within the 100-line guideline.

**hooks.json format:** Uses the event-key object format (`{"hooks": {"PostToolUse": [...]}}`) matching the interlock reference. The plan explicitly cites the prior learning about silent failure on wrong format and validates against it.

**plugin.json `skills` paths** use `"./skills/runtime-diagnostics"` format (directory, not file). This matches the interflux reference which uses `"./skills/flux-drive"`. Consistent.

**No `commands` key in plugin.json:** The plan declares 3 skills and 1 agent but no commands. This is intentional — the plugin teaches via skills, not commands. No collision risk with other plugins.

---

## Summary of Issues

### P0 — Must Fix Before Execution

- **Skill count mismatch:** `test_skill_count` asserts `len(skills) == 3`, but `interverse/interhelm/CLAUDE.md` already documents 4 skills. Anyone running the plan as-is will have a failing test immediately. Update the count in the test and in Task 1's plan text to match reality, or document the discrepancy as a plan-vs-reality gap.

### P1 — Should Fix

- **`expect("Failed to accept connection")` panics server:** Task 8, `main.rs`, `start_diag_server`. Accept errors in a long-running TCP server should `continue` the loop, not panic. The template teaches a bad pattern.

- **Bare `except: pass` in all three hooks:** Task 7. Swallows non-JSON parse errors and unexpected tool payload shapes silently. Replace with `except (json.JSONDecodeError, KeyError, TypeError): pass` at minimum so that unexpected exceptions propagate.

- **Debug timestamp format in `state.rs`:** `format!("{:?}", std::time::SystemTime::now())` produces unreadable output in health responses. Use epoch seconds or document a `chrono` addition more prominently.

- **`runtime-diagnostics/SKILL.md` exceeds 100-line guideline:** Approximately 180 lines. Extract endpoint reference tables to a companion `reference.md` and link from the skill body.

### P2 — Consider

- **`if $is_native` boolean pattern in `browser-on-native.sh`:** Unconventional. Use `[[ "$is_native" == "true" ]]` for clarity.

- **`#[tokio::main]` in CLI with blocking I/O only:** `templates/cli/Cargo.toml` lists `tokio` as a dependency, but the CLI uses only `reqwest::blocking`. Removing tokio simplifies the dependency graph and makes the template easier to understand.

- **Python fixture type hints absent:** `conftest.py` fixtures lack return type annotations. With Python 3.12 and pytest 8.0, `-> Path` and `-> dict` annotations are appropriate.

- **`test_agent_frontmatter` over-matches on `.rglob("*.md")`:** Will pick up stray READMEs if added under `agents/`. Scope to `agents/review/*.md` to match the declared structure.

---

### Findings Index
- P0 | Q-01 | "Task 10: Scripts and Structural Tests" | Skill count in test hardcoded to 3, live plugin already has 4
- P1 | Q-02 | "Task 8: Rust/Hyper Server Templates" | `accept().expect()` panics server on transient errors; teach continue-on-error
- P1 | Q-03 | "Task 7: Hooks" | Bare `except: pass` swallows all exceptions including non-JSON errors
- P1 | Q-04 | "Task 8: Rust/Hyper Server Templates" | Debug timestamp format in `state.rs` produces unreadable health output
- P1 | Q-05 | "Task 3: Runtime Diagnostics Skill" | SKILL.md approximately 180 lines, exceeds 100-line guideline; extract reference tables
- P2 | Q-06 | "Task 7: Hooks" | `if $is_native` boolean pattern unconventional; use `[[ "$is_native" == "true" ]]`
- P2 | Q-07 | "Task 9: CLI Client Templates" | tokio dependency unused (blocking I/O only); increases CLI binary size without benefit
- P2 | Q-08 | "Task 10: Scripts and Structural Tests" | Python fixture type annotations absent in conftest.py
- P2 | Q-09 | "Task 10: Scripts and Structural Tests" | `test_agent_frontmatter` uses rglob; scope to `agents/review/*.md`

<!-- flux-drive:complete -->
