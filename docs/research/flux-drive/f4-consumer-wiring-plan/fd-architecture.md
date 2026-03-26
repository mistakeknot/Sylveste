# Architecture Review: F4 Consumer Wiring Plan (iv-nh3d7)

**Reviewer:** fd-architecture
**Focus:** Module boundary violations, coupling between clavain and interflux, error propagation paths, shared state design (env vars vs explicit passing).

---

### Findings Index

| SEVERITY | ID | Section | Title |
|----------|----|---------|-------|
| MEDIUM | A1 | Task 3 | launch.md sources lib-compose.sh via fragile path probe |
| MEDIUM | A2 | Task 4 | Session-start sources lib-compose.sh redundantly — lib-sprint.sh already does it |
| MEDIUM | A3 | Task 4 | `sprint_find_active` called a third time in session-start — documented anti-pattern |
| LOW | A4 | Task 1 | `_compose_has_agency_spec` probes env vars not in the established resolution order |
| LOW | A5 | Task 3 | `PHASE` variable naming conflicts with existing `PHASE` in launch.md Step 2.0.5 |
| LOW | A6 | Task 3 | Agent dispatch loop is a stub — its incompleteness will silently no-op |
| INFO | A7 | Task 1 | `compose_available` probes live CLI on every call — no guard against slow paths |

**Verdict: needs-changes**

---

### Summary

The plan correctly identifies lib-compose.sh as the integration seam between clavain and interflux, and the stored-artifact-first pattern in `compose_dispatch()` is sound. The Task 1 shell library extensions are well-structured and self-contained. The two boundary problems worth fixing before implementation are: (1) launch.md's path probe for lib-compose.sh deviates from the established pattern already in the existing Step 2.0.4 stub, creating two inconsistent discovery mechanisms in the same file; and (2) the Task 4 session-start injection calls `sprint_find_active` a third time in the same hook execution, directly contradicting the comment at session-start.sh:243 that documents the removal of a prior duplicate call for this exact reason. Both are fixable with one-line changes. The remaining issues are low-severity clarifications.

---

### Issues Found

**A1. MEDIUM: launch.md sources lib-compose.sh via fragile path probe — The plan's Task 3 replacement introduces a new two-candidate for-loop probe (`CLAVAIN_SOURCE_DIR`, `CLAUDE_PLUGIN_ROOT`) to locate lib-compose.sh. The existing Step 2.0.4 stub (launch.md line 24) already uses `source "${CLAVAIN_SOURCE_DIR:-$CLAUDE_PLUGIN_ROOT}/scripts/lib-compose.sh"` — a single-expression fallback that is both correct and already established. The plan's loop adds lines without adding correctness and creates two different sourcing idioms in the same file. The fix is to keep the existing one-liner pattern from the stub.**

**A2. MEDIUM: Session-start sources lib-compose.sh redundantly — lib-sprint.sh (sourced at session-start.sh line 212 via sprint-scan.sh) already sources lib-compose.sh unconditionally at lib-sprint.sh:19-21. The plan's Task 4 adds another `source "${PLUGIN_ROOT}/scripts/lib-compose.sh"` before line 210. This creates a double-source that is harmless only because `_COMPOSE_LIB_SOURCED` is set — but it adds an extra `source` call that may not fire in the right order relative to `set -euo pipefail` (session-start.sh line 4 enables this). The fix: rely on the lib-sprint.sh transitive source; do not add a second explicit source in session-start.sh. Verify `_compose_find_cli` is available after `source sprint-scan.sh` before referencing it.**

**A3. MEDIUM: `sprint_find_active` called a third time — session-start.sh:243 contains the comment "Removed duplicate sprint_find_active call here (iv-zlht)" documenting that a prior redundant call was deliberately excised. The Task 4 block re-introduces exactly this pattern: it calls `sprint_find_active` after `sprint_brief_scan` already called it internally (sprint-scan.sh:355, 411). This re-runs a bd-querying scan for every session start with an active sprint. The sprint data is already available inside `sprint_brief_scan`'s internal `_scan_active_sprints`/`_full_active_sprints` variables, but those are local and not exported. The fix: extend `sprint_brief_scan` (or add a companion `sprint_get_active_cached`) to set a module-level variable like `SPRINT_ACTIVE_JSON` after the scan, then Task 4 reads from that variable instead of re-calling `sprint_find_active`.**

**A4. LOW: `_compose_has_agency_spec` probes env vars not in the established resolution order — The function checks `CLAVAIN_CONFIG_DIR`, `CLAVAIN_DIR`, `CLAVAIN_SOURCE_DIR`, `CLAUDE_PLUGIN_ROOT` for `agency-spec.yaml`. The authoritative resolution order in lib-spec.sh is: (1) `${SPRINT_LIB_PROJECT_DIR}/.clavain/agency-spec.yaml`, (2) `${_SPEC_CLAVAIN_DIR}/config/agency-spec.yaml`. The plan's function misses the project-local `.clavain/` override path (highest priority in lib-spec.sh) and adds `CLAVAIN_CONFIG_DIR` which is a tool-composition config dir, not the spec config dir. A false negative here means `compose_warn_if_expected` silently swallows errors when it should surface them. The simplest fix: call `spec_load` (from lib-spec.sh, already available via lib-sprint.sh) and check `$_SPEC_LOADED == "ok"`, delegating to the canonical loader.**

**A5. LOW: `PHASE` variable naming conflicts — The plan's Task 3 replacement uses `_fd_stage` for the mapped stage (good, prefixed), but it reads from `${PHASE:-build}` where `PHASE` is unqualified. Step 2.0.5 of launch.md also sets a `PHASE` variable from ic state. If Step 2.0.4 fires before 2.0.5 (which it does, being earlier), `PHASE` is unset and defaults to `build`, which may be correct — but the plan uses two different variable names for the same concept (`PHASE` for triage phase in 2.0.5, `_fd_stage` for the Composer stage in 2.0.4). A clarifying comment stating the intentional defaulting would prevent future confusion.**

**A6. LOW: Agent dispatch loop in Task 3 is an incomplete stub — The replacement block for Step 2.0.4 includes a `while read -r _agent` loop with the comment "Agent() tool dispatch uses _agent_type as subagent_type and _agent_model as model parameter" but no actual Agent() call. This is documented as pseudocode, but because it is inside a bash code fence in an instruction document, an implementing agent could interpret it as complete. The plan should explicitly state that this loop body is a placeholder requiring the same Agent() invocation pattern already present in Step 2.2.**

**A7. INFO: `compose_available` probes live CLI on every invocation — The existing `compose_available()` runs `"$cli" compose --stage=ship >/dev/null 2>&1`, which invokes the Go binary unconditionally. In session-start.sh, this would add a subprocess fork for every session with an active sprint. This is not a blocker but worth noting: if the CLI is slow to start (cold JVM-style), this becomes measurable latency. A binary existence check (`[[ -x "$cli" ]]`) would be cheaper for the session-start path where we only need to know if the CLI is installed, not if compose returns valid output.**

---

### Improvements

**I1. Export sprint data from sprint_brief_scan — Add a module-level `SPRINT_ACTIVE_JSON` variable written by `sprint_brief_scan` after its internal `sprint_find_active` call. This lets Task 4's env var injection reuse cached data and eliminates the duplicate scan without requiring caller changes to the hook structure.**

**I2. Delegate `_compose_has_agency_spec` to `spec_load` — Replace the hand-rolled directory probe with a call to `spec_load` followed by `[[ "$_SPEC_LOADED" == "ok" ]]`. lib-spec.sh is already sourced transitively via lib-sprint.sh in every context where lib-compose.sh is used; this avoids duplicating resolution logic that lib-spec.sh owns.**

**I3. Clarify Task 3's dispatch loop as pseudocode — Add an explicit "Implementation note: replace this loop body with the Agent() invocation from Step 2.2" sentence in the plan, preventing an implementing agent from treating the incomplete stub as production-ready code.**

<!-- flux-drive:complete -->
