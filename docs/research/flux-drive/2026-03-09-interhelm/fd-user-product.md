# User & Product Review — interhelm (2026-03-09-interhelm)

**Reviewer role:** Flux-drive User & Product Reviewer
**Plan:** `docs/plans/2026-03-09-interhelm.md`
**Bead:** Sylveste-ekh
**Plan stage at review time:** design (v0.1.0 plan; plugin already implemented at v0.2.0 with a fourth skill added post-plan)

---

## Primary User and Job

The primary user is a **Claude Code agent** working on a project that contains a running native application (Tauri, Electron, CLI tool) and needs to verify runtime behavior without resorting to screenshots. The secondary user is the **human developer** who writes the diagnostic server and CLI client that the agent then uses.

The job the agent is completing: "Verify that my code change did not break runtime behavior in an application I cannot inspect with browser DevTools."

The job the human developer is completing: "Set up the infrastructure so that the agent can observe and control my running application via structured JSON rather than visual inspection."

Both user types need to be served — the plan addresses both, but with different emphasis.

---

## Problem Validation

**Strength of the problem statement:** High. The plan identifies a concrete, real pain: screenshot-based debugging in native apps is expensive (the plan cites 7.5x token cost differential at ~3000 tokens per screenshot-pair vs ~400 tokens for structured queries), slow, and non-deterministic. This is not assumed pain — the PHILOSOPHY.md notes it is "extracted from production-grade implementation" against a real P0 desync bug with 25+ state fields. The evidence base is specific and credible.

**Where the problem definition is less tight:** The plan targets Tauri and Electron apps primarily, but positions the plugin as "framework-agnostic." These are different user populations with different toolchains and different tolerance for adding a diagnostic server dependency. The plan does not segment them. A Tauri developer adding a Rust/hyper server inline has a very different setup burden than an Electron developer adding a Node HTTP server. The framework-agnostic claim weakens the specificity of the guidance without broadening it enough to be genuinely useful for all targets.

**Alternative approaches not evaluated:** The plan does not mention `mcp__plugin_tuivision_tuivision__get_screenshot` at all in the skills (though the hooks reference it). The existing `tuivision` plugin already provides TUI state capture. It is not clear whether interhelm is complementary to tuivision or partially overlapping — particularly the `/diag/ui/state` concept maps closely to what tuivision provides for terminal UIs. No competitive analysis between the two approaches is present. This is a mild gap; the reviewer-level concern is whether agents will reach for `interhelm:cuj-verification` when they should reach for tuivision, or vice versa.

---

## UX / CLI Ergonomics Review

### Skill discoverability

The three skill descriptions are adequate for automated Claude Code routing. The `runtime-diagnostics` description covers the key use-case triggers (native apps, no DevTools, state desync). The `smoke-test-design` description is narrower and may be missed when agents have a working app but want to add structured contracts — it reads as "when setting up end-to-end verification for a new application" which under-signals applicability to brown-field work.

The `cuj-verification` skill correctly scopes itself against the presence of `/diag/ui/state`, which is the right prerequisite signal. However, the description says "queries structured /diag/ui/state endpoints" — this pre-requires knowledge of the endpoint name, which agents who haven't yet run `runtime-diagnostics` won't have. The description would be stronger if it said "after a diagnostic server is available" as the trigger condition.

### Skill composability

The plan assumes agents will naturally compose `runtime-diagnostics` → `smoke-test-design` → `cuj-verification` in that order. This composition is never made explicit in any skill or in the plugin README. An agent encountering these skills without prior context has no stated dependency order. The `runtime-diagnostics` skill does not reference the other two skills as logical next steps. This is a composability gap for the multi-step setup case.

### Hook behavior

**Browser-on-native hook (F5):** The hook fires after any use of the tuivision screenshot tool if the project has a diagnostic server configured in CLAUDE.md and detects Tauri/Electron markers. This is well-scoped. The output message names the skill to invoke (`interhelm:runtime-diagnostics`), which is the right nudge format.

However, the hook fires *after* the screenshot is already taken — the token cost is already spent. A `PreToolUse` hook would prevent the screenshot and suggest the diagnostic CLI instead, which is more aligned with the "token reduction" goal. PostToolUse makes the agent aware for next time but does not intercept the expensive behavior.

**Auto-health-check hook (F6):** Fires after every Edit or Write to a Rust source file, then attempts to execute a health CLI found in the project's CLAUDE.md. This hook has a significant false-positive surface:
- It runs after every Rust file edit, not just after a build succeeds. Health checks against the app will fail if the app is not running at edit time (it usually is not during active development), producing noise or silent exits.
- The health check is async, which is good. But the output message "Health regression detected after editing Rust source" implies a before/after comparison that the hook does not actually perform — it only checks current health status without knowing the pre-edit baseline.

**CUJ-reminder hook (F7):** Fires after any `git commit` detected in a Bash tool call. This is a reasonable trigger point. The message correctly names the skill to invoke. The risk is frequency — in a project doing incremental commits (5-10 commits per session), this fires repeatedly. There is no throttle or deduplication. Combined with the auto-health hook, agents working on Rust projects with diagnostic servers will receive multiple interhelm nudges per significant work block.

### Hook noise floor

The combination of three always-on PostToolUse hooks creates a non-trivial noise floor for agents working in interhelm-aware projects. The hooks are "advisory, not blocking" as stated in PHILOSOPHY.md, which is correct, but cumulative advisory noise trains agents (and developers reading logs) to ignore the output. The plan does not address frequency capping or a mechanism for agents to suppress known-irrelevant nudges.

---

## Product Validation

### Core value proposition

The core value — replacing screenshot-based runtime verification with structured JSON queries — is real, well-motivated, and correctly sized as a pattern-teaching plugin rather than a shipped runtime. The decision to teach the pattern rather than ship a framework is the right call; it keeps the plugin language-agnostic and prevents it from becoming a dependency.

### Scope assessment

The plan bundles the following distinct concerns:

1. **Pattern teaching (skills)** — correctly scoped, directly serves the core value prop
2. **Reviewer agent** — correctly scoped, adds review capability for existing implementations
3. **Hooks** — advisory nudges; appropriately advisory but noisier than necessary
4. **Rust/hyper templates** — reference code, not compiled; high value for Rust/Tauri users, low value for anyone else
5. **CLI client template** — reference code; similarly Rust-specific

Items 4 and 5 are the only scope-creep risk. They are Rust-specific despite the framework-agnostic positioning. The README says "works with Tauri, Electron, web apps, CLI tools" but the only templates are Rust. An Electron user gets skills but no starter templates. If the primary reference implementation is Shadow Work (a Tauri/Rust app), this is internally consistent — but the positioning should match the templates, or templates for other targets should exist.

The plan's "while we're here" items are limited. The bump-version script (Task 10) is clearly maintenance scaffolding — legitimate but not user-facing value. Structural tests are good CI discipline.

### Missing success signal

The plan defines no measurable success signal for post-release validation. The "Truths" section verifies structural completeness (files exist, tests pass) but does not specify how the team would know the plugin is actually being used, whether agents discover the skills correctly, or whether the token reduction claim is validated in production. Per Sylveste PHILOSOPHY.md, "wired or it doesn't exist" — a feature with no observation mechanism is inventory, not capability.

The plan needs: (a) a way to know if `interhelm:runtime-diagnostics` is invoked when a native app project opens, (b) a way to measure whether screenshots decrease in sessions where interhelm is active.

---

## Flow Analysis

### Happy path: new project setup

1. Developer has a Tauri app with no diagnostic server
2. Agent invokes `interhelm:runtime-diagnostics`
3. Agent reads existing app state struct, enumerates subsystems
4. Agent scaffolds diagnostic server using templates
5. Agent wires server into app, verifies health check
6. Agent documents server in project CLAUDE.md
7. Future agents find the documented server and use it directly

This path is well-specified in the skill. Steps 1-2 rely on the agent choosing to invoke the skill — either via user request or via skill routing. There is no hook that fires at project load to surface interhelm when a native app is detected. The browser-on-native hook is reactive (fires after a screenshot), not proactive.

**Missing entry point:** A `SessionStart` or `UserPromptSubmit` hook that checks for a native app without a diagnostic server and surfaces the pattern would create a proactive adoption path. Currently, the only proactive path is the `runtime-diagnostics` skill description matching the agent's context.

### Error path: diagnostic server port conflict

The templates hardcode port 9876. If this port is occupied (another project's diagnostic server, a local service), the server fails to start with a bind error. The templates have no port-from-env fallback. The skill does not mention port configuration as a customization point. The CLI client template hardcodes `127.0.0.1:9876` as the default but accepts `--url`, which is the right escape hatch — but the server side has no equivalent.

### Error path: app not running when health hook fires

The auto-health-check hook (F6) executes `$diag_cli health` after every Rust file edit. If the app is not running (common during development), the CLI will fail to connect. The hook catches this via `|| true` but produces no output. Silently failing health checks undermine the nudge — the agent receives no feedback. The hook should at minimum suppress output entirely when the server is unreachable rather than falling through.

### Partial completion path: incomplete scaffold

The `handle_diff` and `handle_assert` handlers in the Rust template return HTTP 501 with a CUSTOMIZE note. This is the correct choice (prevents false positives). However, if an agent invokes `app-diag diff` and gets a 501 response, the formatted output in the CLI will be raw JSON dumped via `serde_json::to_string_pretty` — not a "not implemented" message in the formatted health style. The error path in the CLI `Diff` command needs a handler for 501 status specifically.

### CUJ verification path with UI-only actions

The `cuj-verification` skill correctly notes that actions requiring UI interaction (button clicks, drag-and-drop) need corresponding `/control/*` endpoints added first. However, it does not explain how to verify that the control endpoint correctly drove the UI action vs. the action having no effect. The state-before/action/state-after pattern is clear for observable state, but the failure mode (action had no effect, state unchanged) looks identical to a broken action endpoint. The skill should address this disambiguation.

### Discovery convention completeness

The skill specifies that projects should document their diagnostic server in CLAUDE.md under a `## Diagnostic Server` section. This is a good lightweight convention. But the browser-on-native hook (F5) looks for `"diagnostic server\|/diag/"` in CLAUDE.md, which is different from the `## Diagnostic Server` heading convention specified in the skill. These two patterns should be consistent.

---

## Findings

### P0 Issues

**None.** The plan does not block user success or create adoption-ending defects at the skeleton level. The templates compile (the plan does not require they compile — they are reference code — so this is not a defect).

### P1 Issues

**Hook timing mismatch for token-reduction goal (F5):** The browser-on-native hook fires PostToolUse, after the screenshot is taken. This does not reduce the token cost of the screenshot that already occurred. A PreToolUse hook with the same logic would intercept the expensive behavior. The current design only educates for the *next* time.

**Auto-health hook fires against non-running app (F6):** The hook executes the health CLI after every Rust source file edit, producing silent failures (app not running during development) with no useful output. The "Health regression detected" message implies a before/after comparison that is not performed. This hook will fire frequently in normal development, produce no useful output most of the time, and occasionally fire with a false alarm.

**No measurable success signal defined:** The plan has no post-release measurement defined. There is no way to know if agents discover and use the skills, whether the 7.5x token reduction claim holds in production, or whether the hooks fire at the right frequency. Per Sylveste PHILOSOPHY.md's "wired or it doesn't exist" principle, a feature that emits no observable evidence when it activates is incomplete.

**Rust-only templates vs. framework-agnostic positioning:** The templates are Rust/hyper-specific. The skills are framework-agnostic. An Electron developer receives skill guidance but no starting-point code. The README's "works with Tauri, Electron, web apps" claim is accurate for the skills but not for the templates. Either add a Node/TypeScript template or narrow the positioning.

### P2 Issues

**Hook noise floor not addressed:** Three PostToolUse hooks on Edit, Write, Bash, and tuivision tools will produce multiple interhelm nudges per active development session in an interhelm-aware project. There is no frequency cap or dedup mechanism. Advisory hooks that fire constantly become ignored hooks.

**Skill composition order not documented:** The three skills are logically sequential (set up server → design smoke tests → verify CUJs) but the plugin provides no guidance on sequencing. A new-to-interhelm agent will not know which skill to start with. The README's "Usage" section lists them in order, but the skills themselves contain no forward/backward references.

**CUJ verification failure mode ambiguous:** When an action via `/control/*` has no effect, the state-before and state-after will be identical, which looks the same as a working verification where no state change was expected. The skill does not explain how to distinguish "action had no effect" from "action succeeded and state was unchanged by design."

**Port conflict handling absent in server template:** The server template hardcodes port 9876 with no env-var override or automatic retry on a free port. The CLI provides `--url` as an escape hatch, but the server side requires a code change. A one-liner `DIAG_PORT` override via env var would be a 3-line CUSTOMIZE addition.

**CLAUDE.md/hook pattern inconsistency:** The `runtime-diagnostics` skill documents the discovery convention as `## Diagnostic Server` section. The browser-on-native hook looks for `"diagnostic server\|/diag/"` patterns. These need to be aligned so agents writing CLAUDE.md documentation reliably trigger the hook detection.

### P3 Issues

**`smoke-test-design` description under-signals brown-field applicability:** The description says "when setting up end-to-end verification for a new application." This will cause agents to skip it for existing apps that already have health endpoints but no smoke test contract. "Adding or formalizing end-to-end verification" would be more accurate.

**`cuj-verification` description requires prior endpoint knowledge:** The description mentions `/diag/ui/state` by name. Agents encountering this skill without having run `runtime-diagnostics` first may not recognize the prerequisite. A phrase like "requires a diagnostic server with UI state endpoint" would signal the dependency.

**Template timestamp in state.rs is non-standard:** `format!("{:?}", std::time::SystemTime::now())` produces a debug-format timestamp like `SystemTime { tv_sec: 1741xxx, tv_nsec: 0 }`, not an ISO 8601 string. The comment says to use `chrono::Utc::now().to_rfc3339()` but chrono is not in Cargo.toml. The SKILL.md's health JSON example shows `"timestamp": "2026-03-09T14:30:00Z"` (ISO 8601). Agents adapting the template will produce structurally correct but non-parseable timestamps unless they notice the comment and add the chrono dependency.

---

## Smallest Improvement Set

Highest-value changes that would meaningfully improve user outcome confidence:

1. **Change browser-on-native hook from PostToolUse to PreToolUse** — this is the only change that actually prevents the expensive screenshot behavior rather than logging it after the fact.

2. **Add silent-exit to auto-health hook when server unreachable** — replace the current "health regression detected" false-alarm logic with a pre-check: `if ! curl -s --connect-timeout 1 $port/diag/health > /dev/null 2>&1; then exit 0; fi`. This eliminates the false-alarm problem entirely.

3. **Add a 150-word "Which skill first?" section to the README** — "If you have no diagnostic server yet: start with `runtime-diagnostics`. If you have a server and want a smoke test contract: `smoke-test-design`. If you want to verify user journeys: `cuj-verification`." Three sentences, covers the composition question.

4. **Add `DIAG_PORT=${DIAG_PORT:-9876}` env override to main.rs template** — one-line change, eliminates a common setup friction for teams with port conflicts.

5. **Define one observable success metric in the plan's "Must-Haves"** — e.g., "interhelm:runtime-diagnostics is invoked at least once in sessions where a native app project with no existing diagnostic server is being modified." This can be logged via Interspect or interstat.

---

### Findings Index
- P1 | UX-01 | "Task 7: Hooks" | Browser-on-native hook fires PostToolUse — cannot prevent the screenshot it advises against
- P1 | UX-02 | "Task 7: Hooks" | Auto-health hook fires against non-running app, produces silent failures and misleading "regression" messages
- P1 | PRD-01 | "Must-Haves" | No measurable success signal defined; plugin has no post-release observability
- P1 | PRD-02 | "Task 8/9: Templates" | Rust-only templates contradict framework-agnostic skill positioning
- P2 | UX-03 | "Task 7: Hooks" | Three PostToolUse hooks produce unthrottled advisory noise in active development sessions
- P2 | UX-04 | "Task 3/4/5: Skills" | Skill composition order (runtime-diagnostics -> smoke-test-design -> cuj-verification) not documented anywhere in plugin
- P2 | UX-05 | "Task 5: CUJ Verification Skill" | Failure mode ambiguous when control action has no effect on state
- P2 | UX-06 | "Task 8: Rust/Hyper Templates" | Port conflict not handleable without code change; no env-var override for DIAG_PORT
- P2 | UX-07 | "Task 7: Hooks / Task 3: Runtime Diagnostics Skill" | Discovery pattern in CLAUDE.md section header not consistent with hook grep pattern
- P3 | UX-08 | "Task 4: Smoke Test Design Skill" | Description under-signals applicability to brown-field projects with existing health endpoints
- P3 | UX-09 | "Task 5: CUJ Verification Skill" | Description requires prior knowledge of /diag/ui/state endpoint name; hides prerequisite
- P3 | CODE-01 | "Task 8: Rust/Hyper Templates" | state.rs timestamp uses debug format, not ISO 8601; Cargo.toml missing chrono dependency

<!-- flux-drive:complete -->
