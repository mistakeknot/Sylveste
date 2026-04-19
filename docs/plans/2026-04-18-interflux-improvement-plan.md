---
artifact_type: plan
campaign: sylveste-qv33
bead: sylveste-e34c
date: 2026-04-18
---

# Interflux Refactor Blueprint — sylveste-qv33 Campaign Synthesis

## 1. Executive Summary

Nine analysis passes against interflux v0.2.58-0.2.59 across 3 phases: static validation
(Phase 0), targeted deep-dives (Phase 1), and dogfood flux-drive/flux-review runs against
interflux's own code (Phase 2). After deduplication and exclusion of 9 already-shipped
v0.2.59 items, total findings: 9 P0, 38 P1, 40 P2, 8 P3. Classified into 18 Category A
immediate fixes, 6 Category B bundles, 4 Category C epics, 12 Category D deferrals.

Top 3 convergent signals (3+ independent sources each):

1. "Silent failure as architecture." Every pipeline stage has a "silent OK" exit that makes
real failures indistinguishable from success: MCP servers exit 0 on missing config, a 0-byte
file carries .lock semantics, || echo "[]" masks SQL schema drift, flock-subshell Python
exceptions are invisible to the outer script, trap RETURN does not fire on SIGINT. The 3/3
cross-semantic-track convergence (plugin-architecture, release-engineering, and lost-wax
casting lenses independently naming the same pattern) is the highest-confidence finding.

2. LLM spec validation weakness at the JSON→render boundary. The anti_overlap incident
(v0.2.58, 116 corrupted agent files) is the confirmed exploitation. Phase 1 security (F1,
F2), Phase 1 type-design (4 P0s around AgentSpec), and Phase 2.1 scripts review (ARC-04,
ARC-05) independently converged on AgentSpec TypedDict + validate_agent_spec() as the fix.

3. Systemic shell patterns with cumulative drift. Python-in-flock-subshell (4 scripts),
yq-parse-fails-silently (4 scripts), registry-write copy-pasted 5x with diverging error
handling. Found by 4 independent reviewers. Risk is not current bugs but the next edit.

Plugin health verdict: structurally sound and runtime-capable. Core orchestration is
well-disciplined. Problems concentrate in (a) the fluxbench calibration/scoring/drift layer
— 3 P0 silent failures corrupt the learning signal — and (b) the LLM→filesystem boundary
in agent generation. The dual SKILL.md/SKILL-compact.md design is a live P1 content-loss
bug: compact silently drops Phase 2.5 reaction orchestration; users loading compact never
see reaction-round logic.

---

## 2. Category A — Immediate Fixes

| # | File:Line | Finding | Fix | Sev |
|---|-----------|---------|-----|-----|
| A-01 | hooks/hooks.json:17-37 | PostToolUse matchers for Edit/Write have no path scope — run check-compact-drift.sh on every file edit in every project globally | Add "pathPattern": "${CLAUDE_PLUGIN_ROOT}/**" to both matchers, or move to PreCompact | P0 |
| A-02 | mcp-servers/openrouter-dispatch/index.ts:9 | process.exit(0) on missing OPENROUTER_API_KEY — Claude Code sees it as clean shutdown, not missing config | Change to process.exit(78) (EX_CONFIG) | P0 |
| A-03 | scripts/launch-exa.sh (exit on missing EXA_API_KEY) | Same exit-0 pattern as A-02 | Change to exit 78 | P0 |
| A-04 | hooks/session-start.sh:78-81 | Malformed _if_pct coerces to 0, awk computes full budget as "remaining", exports phantom FLUX_BUDGET_REMAINING — agents dispatch when budget is exhausted | On corrupted payload, skip export entirely and log once to stderr | P0 |
| A-05 | scripts/estimate-costs.sh:85-96 | sqlite3 ... 2>/dev/null \|\| echo "[]" coerces schema-drift query failure to empty results — cost report uses hardcoded defaults and appears credible | Separate DB-missing (silent OK) from query-failed: capture stderr to tmpfile, check exit code, emit error to stderr on failure | P0 |
| A-06 | skills/flux-drive/phases/launch.md:255-257 | Synthetic-refusal detection uses substring grep on 500 chars of subagent output — adversarial subagent can inject the string to trigger spurious tier-downgrade retries | Anchor: grep -qE '^API Error: Claude Code is unable to respond.*violate our Usage Policy' | P2 |
| A-07 | scripts/generate-agents.py:~516 | Name validated only via startswith("fd-") — path traversal possible with fd-../../etc/cron.d/evil | Replace with re.fullmatch(r"fd-[a-z0-9]+(?:-[a-z0-9]+)*", name) | P1 |
| A-08 | skills/flux-research/ (entire directory) | Deprecated skill on disk — auto-discovery loads it regardless of plugin.json; CLAUDE.md validation comment says "Should be 2" | git rm -r interverse/interflux/skills/flux-research/ then update CLAUDE.md validation to # Should be 1 | P1 |
| A-09 | scripts/fluxbench-score.sh Python heredoc severity comparisons | LLM output "P0 " (trailing space) fails equality check — correctly identified P0s auto-fail qualification | Add _normalize_sev = lambda s: (s or '').strip().upper() and apply to all 4 severity comparison sites | P1 |
| A-10 | scripts/findings-helper.sh:49 | grep '^{' filter silently drops valid JSON not starting with { and keeps malformed lines starting with { — one partial-write line destroys the entire findings parse | Replace with per-line jq validation loop | P1 |
| A-11 | scripts/fluxbench-qualify.sh:143 | trap 'rm -f "$tmp_reg"' RETURN inside flock subshell does not fire on SIGINT — temp files leak on Ctrl-C | Move trap to EXIT at the top of the flock subshell (~line 491), not inside the function | P1 |
| A-12 | scripts/discourse-health.sh:39 | $config_path interpolated into python3 heredoc — shell injection if caller passes attacker-controlled path | Migrate to env-var pattern: export _DH_CONFIG="$config_path" and read os.environ['_DH_CONFIG'] inside heredoc | P1 |
| A-13 | scripts/fluxbench-drift.sh:44-47 | yq ... 2>/dev/null \|\| true on higher_is_better_map — if metrics file present but yq fails, map is empty; false_positive_rate regression reads as improvement | Remove \|\| true; add \|\| { echo "fluxbench-drift: failed to read metrics file" >&2; exit 1; } | P1 |
| A-14 | scripts/fluxbench-score.sh:38-44 _get_threshold() | \|\| true on yq — corrupted thresholds file silently falls back to hardcoded defaults | Log warning when file exists but parse fails; keep fallback only when file is absent | P1 |
| A-15 | scripts/flux-watch.sh:65-70 | INOTIFY_PID=$! captures process-substitution subshell PID, not inotifywait — kill kills nothing, orphaned inotifywait processes exhaust inotify watch slots | Use pgrep -P $$ to find the inotifywait child | P1 |
| A-16 | scripts/token-count.py:~38 | json.loads(line) outside per-line try/except — one malformed JSONL line discards all accumulated valid counts, falls back to character estimate for entire file | Move json.loads inside per-line try/except; accumulate valid lines; fall back only on zero valid | P1 |
| A-17 | scripts/estimate-costs.sh:51 | grep uses agent_type variable as unescaped regex pattern | Replace with grep -F "$agent_type" | P1 |
| A-18 | config/flux-drive/model-registry.yaml.lock (in git) | 0-byte file carries .lock semantics it doesn't implement | Add to .gitignore | P2 |

---

## 3. Category B — Bundled Patches (v0.2.60+)

### B1 — Flock Hardening Bundle

**Scope:** Add flock -w 30 timeouts to all 6 unbounded flock -x 201 sites; fix subshell
exit-code propagation; move tmp cleanup to EXIT not RETURN.

**Rationale:** fluxbench-drift-sample.sh calls fluxbench-drift.sh which takes the same
${registry}.lock with no timeout — a concurrent qualify run deadlocks the drift loop, which
cascades into the session-start hook chain. Found by Phase 1 silent-failure P1-3/P1-4,
Phase 2.1 COR-01/COR-02, fd-architecture ARC-01 — 4 independent reviewers. Concurrently:
bash set -e does not propagate through (flock -x N ...) N>"$lock" subshell redirection,
making Python exceptions inside invisible.

**Files:**
- scripts/fluxbench-challenger.sh:45,:90 — flock -w 30; if ! (...) 201>"$lock" propagation
- scripts/fluxbench-qualify.sh:494,:632 — same
- scripts/fluxbench-drift.sh:64 — flock -w 30; log and skip on timeout (drift is advisory)
- scripts/fluxbench-drift-sample.sh:142 — flock -w 30; log and continue loop on timeout
- scripts/discover-merge.sh:24-96 — flock timeout + exit-code propagation
- scripts/fluxbench-sync.sh:35 — flock -w 30

**Test plan:**
1. flock -x 201 /tmp/test.lock sleep 60 & then run fluxbench-drift-sample.sh — must print
   timeout warning and complete within 35s
2. Ctrl-C during fluxbench-qualify.sh --mock — verify no /tmp/tmp.XXXXXX orphans remain
3. Corrupt model-registry.yaml and run fluxbench-challenger.sh — non-zero exit, no partial write

**Estimated effort:** 2-3 hours

---

### B2 — Python Spec Validation Layer

**Scope:** Add scripts/types.py with AgentSpec TypedDict + validate_agent_spec(); shared
_unwrap_spec_list helper; wire into generate_from_specs at spec-load time.

**Rationale:** anti_overlap bug (v0.2.58, 116 corrupted files) confirmed exploitation of the
LLM-JSON→render boundary gap. Phase 1 type-design: 4 P0s. Phase 1 security: F1+F2.
Phase 2.1: ARC-04 (duplicated _parse_frontmatter). All 4 convergent on same fix.

**Files:**
- scripts/types.py (new) — AgentSpec TypedDict, validate_agent_spec(), _normalize_bullet_list
  (extracted from existing), _normalize_severity_examples, _unwrap_spec_list
- scripts/generate-agents.py:461 — call validate_agent_spec(spec) before render_agent()
- scripts/generate-agents.py:446-451 and scripts/flux-agent.py:673-677 — replace both
  duplicate wrapper-dict unwrap implementations with shared _unwrap_spec_list
- scripts/generate-agents.py:493-494 — fix existing_version int-vs-string cast
- scripts/flux-agent.py:249 — fix use_count = int(fm.get("use_count") or 0)
- scripts/flux-agent.py:273 — normalize comma-joined domains string: split on [,;] and strip
- scripts/token-count.py — integrate A-16 fix; fix int(usage.get("input_tokens") or 0)

**Test plan:** See Section 7 (scripts/tests/test_validate_agent_spec.py, 30+ cases)

**Estimated effort:** 4-5 hours

---

### B3 — Security Hardening Bundle

**Scope:** Implement scripts/sanitize_untrusted.py; apply to agent spec rendering; fix MCP
exit codes (A-02/A-03 are standalone; this adds sanitizer scope); persist openrouter state.

**Rationale:** Phase 1 security F2 (persona/decision_lens/review_areas written verbatim into
agent system prompts). Phase 2.2 S1 (Unicode bypass in existing sanitizer). The trust
boundary is shared across 4 channels (peer-findings, knowledge context, domain overlays,
spec rendering) — a bypass in one amplifies across all.

**Files:**
- scripts/sanitize_untrusted.py (new) — sanitize(text, max_len) → str; NFKC normalization,
  XML tag strip, instruction-override pattern detection, code-fence strip (all languages),
  HTML entity decode+strip, base64 heuristic; see Section 3/C3 for full scope
- scripts/generate-agents.py render_agent() — apply sanitize() to persona (≤500),
  decision_lens (≤500), each review_areas item (≤200), task_context (≤1000), anti_overlap
  items (≤200)
- skills/flux-drive/phases/reaction.md Step 2.5.3 — replace prose sanitization spec with
  pointer to scripts/sanitize_untrusted.py as reference implementation
- skills/flux-drive/phases/synthesize.md compounding step — sanitize() before writing any
  knowledge entry text
- mcp-servers/openrouter-dispatch/index.ts — persist tokenBucket and cumulativeSpendUsd to
  ~/.config/interflux/openrouter-state.json under flock; load on startup

**Test plan:** See Section 7 (scripts/tests/test_sanitize_untrusted.py)

**Estimated effort:** 3-4 hours

---

### B4 — SKILL.md Consolidation

**Scope:** Delete SKILL-compact.md; rewrite SKILL.md with ## Quick Reference at top;
eliminate the dual-file drift that dropped Phase 2.5 reaction orchestration from compact.

**Rationale:** 4-agent convergence in Phase 2.2. SKILL-compact.md (326 lines) is longer
than SKILL.md (301 lines) and silently drops Phase 2.5 reaction-round orchestration from
its phase list — readers following "load compact instead" never see reaction logic. Phase 0
P2 (size); Phase 2.2 upgraded to P1 (content loss); Phase 2.3 B-P2-10 confirmed.

**Files:**
- skills/flux-drive/SKILL.md — add ## Quick Reference section at top (mode table, 5-line
  triage summary, phase list explicitly including Phase 2.5); collapse budget-algorithm
  prose to pointer at references/budget.md
- skills/flux-drive/SKILL-compact.md — git rm
- skills/flux-drive/SKILL.md:8 — remove <!-- compact: SKILL-compact.md ... --> directive
- CLAUDE.md validation line — update to # Should be 1 (after A-08 removes flux-research)

**Test plan:**
1. scripts/validate-manifest.sh — must pass (1 skill on disk, 1 declared)
2. Load SKILL.md — verify Phase 2.5 reaction round is listed in phase routing section
3. Run flux-drive with reaction_round.enabled:true — verify reaction round triggers

**Estimated effort:** 2-3 hours

---

### B5 — Shell Hygiene + Variable Canonicalization

**Scope:** Canonicalize MODEL_REGISTRY env var; fix flock fd 200 overload; fix bare except
Exception in Python scripts; fix 2>&1 $(...) stderr-capture; add scripts/README.md.

**Rationale:** Phase 2.1 ARC-03 (3 names for 1 concept), ARC-06 (fd 200 overloaded for 2
lock domains). Phase 1 type-design P2-7 (bare except). Phase 2.1 QUA-03 (DeprecationWarning
baked into challenger output, silencing model selection).

**Files:**
- scripts/discover-merge.sh:8 — rename REGISTRY_FILE to MODEL_REGISTRY
- scripts/validate-enforce.sh:7 — add MODEL_REGISTRY env override support
- scripts/findings-helper.sh:37 — change flock fd from 200 to 203; add fd-domain comment
- scripts/flux-agent.py:125,153,177,681 — except Exception as exc: logger.debug(...)
- scripts/generate-agents.py:~440 — same logger pattern for _parse_frontmatter
- scripts/fluxbench-challenger.sh:208 — fix 2>&1 $(...) pattern; capture stderr separately
- scripts/README.md (new) — canonical env var names, flock fd table, Python-heredoc
  size convention (>10 lines → extract to scripts/_<name>.py), atomic-mutate pattern

**Test plan:**
1. MODEL_REGISTRY=/tmp/test.yaml bash scripts/validate-enforce.sh — must use override
2. MODEL_REGISTRY=/tmp/test.yaml bash scripts/discover-merge.sh — must use same path
3. Challenger Python block printing DeprecationWarning — .selected field non-empty

**Estimated effort:** 3 hours

---

### B6 — Phase-File Instruction Accuracy Pass

**Scope:** Remove Composer dead branches from skill; fix launch.md step ordering; rename
interserve-mode terminology; fix Lorenzen cwd-relative path; clarify sentinel contract.

**Rationale:** Phase 0 comment-analyzer P1 items outstanding after v0.2.59: Composer guard
branches (P2.1 skill-reviewer, Phase 2.2 A3), step 2.1b out of physical order (Phase 2.2
A2), interserve-mode terminology (Phase 0 P2.4), Lorenzen path (Phase 2.2 A5).

**Files:**
- skills/flux-drive/phases/launch.md — remove Step 2.0.4 Composer block and all
  _COMPOSE_LIB_SOURCED/COMPOSER_ACTIVE skip guards (4 sites); move Step 2.1b to its
  correct position between 2.1a and 2.1c; fix Lorenzen config path to
  ${CLAUDE_PLUGIN_ROOT}/config/flux-drive/discourse-lorenzen.yaml; replace hardcoded
  CHROME_PATH with ${ORACLE_CHROME_PATH:-$(command -v google-chrome-wrapper)}
- skills/flux-drive/SKILL.md:301, references/agent-roster.md:13, phases/launch-codex.md,
  AGENTS.md:74,114,224,225 — rename "interserve mode" to "Codex mode" (6 sites)
- skills/flux-drive/phases/shared-contracts.md — clarify <!-- flux-drive:complete -->
  sentinel is diagnostic metadata only; .md rename is the binding completion signal
- skills/flux-drive/phases/synthesize.md:220-229 — fix total_tokens aliasing: use
  COALESCE(total_tokens, input_tokens + output_tokens + cache_read_tokens +
  cache_creation_tokens) rather than recomputing over the existing column

**Test plan:**
1. grep -r '_COMPOSE_LIB_SOURCED\|COMPOSER_ACTIVE' interverse/interflux/skills/ — zero matches
2. grep -r 'interserve mode' interverse/interflux/ — zero matches
3. Launch.md step numbers ascending top-to-bottom — verify manually
4. Full flux-drive run on small file — no regression in dispatch behavior

**Estimated effort:** 2-3 hours

---

## 4. Category C — Architectural Epics

### C1 — lib_registry.py + Registry Write Consolidation

**Problem statement:** The model-registry.yaml atomic-mutate pattern (flock → cp → python3
heredoc mutate → validate → mv) is copy-pasted 5x across fluxbench-{challenger,qualify,
drift}.sh, discover-merge.sh, fluxbench-sync.sh with diverging trap lifetimes, validation
depth, and lock-path variable naming. The yaml read→mutate→dump heredoc is duplicated ~8x
with different models:null/dict/list normalization. Phase 2.1 ARC-01/ARC-02 confirmed 4
independent reviewers identifying this as the highest-leverage refactor. The 180-line
scoring algorithm is trapped in a shell heredoc (ARC-05), making unit testing infeasible.

**Proposed design:**
- scripts/lib_registry.py — load_registry(path), get_model(reg, slug), set_model_field(reg,
  slug, key, value), validate_and_dump(reg), normalize_models(reg) handles dict/list/null
- scripts/lib-registry.sh — registry_atomic_mutate(registry, mutator_fn, fd=201) shell
  function: flock -w 30, cp to tmp, call python3 -m lib_registry mutate, validate, mv
- Replace 5 heredoc blocks with calls to registry_atomic_mutate
- scripts/_fluxbench_score.py — extract 180-line scoring algorithm; CLI with
  if __name__=="__main__"; enables pytest and mypy on the most complex code in the plugin
- scripts/tests/test_lib_registry.py + test_fluxbench_score.py (see Section 7)

**Scope boundary:** In: 5 registry-write scripts, scoring algorithm extraction.
Out: read-only yq access, validation scripts, FluxBench qualification state machine (C2).

**Dependencies:** B1 (flock hardening) ships first.

**Bead-create recipe:**
- Title: interflux: extract lib_registry.py — consolidate 5 registry-write patterns
- Description: model-registry.yaml atomic-mutate pattern copy-pasted 5x with diverging
  error handling. 180-line scoring algorithm in shell heredoc. Extract scripts/lib_registry.py
  (load/get/set/validate_and_dump) + lib-registry.sh (registry_atomic_mutate) +
  _fluxbench_score.py. Add test_lib_registry.py + test_fluxbench_score.py. Replace 5
  heredoc blocks. Ref: phase2-flux-drive-scripts ARC-01/ARC-02/ARC-05, phase1-silent-failure
  P1-3/P1-4.

**Estimated effort:** 6-8 hours

---

### C2 — Explicit Dispatch State Machine + VerificationStep Primitive

**Problem statement:** The agent dispatch lifecycle across shared-contracts.md, launch.md
Step 2.3, and flux-watch.sh forms an implicit state machine with a known bug (Phase 2.2
C1): Step 2.3 retry has no kill-original clause — a slow original Task renames its partial
over a synchronous retry's completed output. Phase 2.3 full-review's 3/3 convergence
identifies the pattern: every phase transition has a "silent OK" exit. Individual fixes
address instances; this epic addresses the architecture.

**Proposed design:**
- Explicit state machine in phases/shared-contracts.md: states {dispatched, writing,
  completed, timeout_original_running, retried, failed}, transitions, invariants
- Fix retry race: write {OUTPUT_DIR}/{agent}.abort before launching retry; flux-watch.sh
  ignores subsequent renames from the original Task when abort signal exists
- VerificationStep primitive: every phase transition emits {state: VERIFIED |
  FAILED_VERIFICATION | UNVERIFIABLE, evidence: string}; UNVERIFIABLE is not success
- run_uuid in every agent output preamble — synthesis rejects mismatched UUIDs (quire mark)
- decisions.log per run: triage inputs, expansion rule, dropout scores, budget cuts

**Scope boundary:** In: dispatch state machine, retry abort, VerificationStep, run_uuid,
decisions.log. Out: FluxBench qualification pipeline, per-artifact provenance beyond
dispatch outputs (track separately), diversity floor for agent selection (future roadmap).

**Dependencies:** B4 + B6 must complete first.

**Bead-create recipe:**
- Title: interflux: explicit dispatch state machine + VerificationStep primitive
- Description: Agent dispatch lifecycle has an implicit state machine with a retry-race bug
  (slow original Task overwrites retry output). Define explicit states in shared-contracts.md,
  fix retry race with .abort signal in flux-watch.sh, implement VerificationStep primitive
  emitting VERIFIED|FAILED_VERIFICATION|UNVERIFIABLE, add run_uuid quire-mark, decisions.log.
  Ref: phase2-flux-drive-skill C1/C-IMP1, phase2-flux-review-full CF-8/Convergence-3/3.

**Estimated effort:** 8-12 hours

---

### C3 — sanitize_untrusted.py Reference Implementation with Fuzz Tests

**Problem statement:** reaction.md Step 2.5.3 sanitizer is a prose spec with confirmed
bypasses (Phase 2.2 S1): Unicode fullwidth letters, zero-width-space tags, non-bash code
fences, HTML entity angle brackets, base64 payloads. The boundary is shared by 4 channels
(peer-findings, knowledge context, domain overlays, spec rendering) — a bypass amplifies
across all. B3 creates the initial module; this epic delivers the full fuzz harness and
4-channel integration.

**Proposed design:**
- scripts/sanitize_untrusted.py (extending B3): hypothesis property tests, confusable/
  homoglyph detection via Unicode confusables, HTML entity double-encoding, base64 entropy
  threshold detection
- scripts/tests/test_sanitize_untrusted.py — 40+ fixtures; all S1 bypass patterns as
  regression tests; 10+ legitimate findings that must NOT falsely strip
- TrustedContent = NewType('TrustedContent', str) in types.py — sanitize() returns
  TrustedContent; render functions typed to require it; bypasses become mypy type errors
- Full integration into all 4 channels

**Scope boundary:** In: sanitizer, fuzz tests, 4-channel integration, TrustedContent type.
Out: openrouter rate-limit persistence (B3), intertrust scores, knowledge decay policy,
correctorium separation (future roadmap).

**Dependencies:** B2 + B3 are prerequisites.

**Bead-create recipe:**
- Title: interflux: sanitize_untrusted.py reference implementation with fuzz tests
- Description: reaction.md Step 2.5.3 sanitizer has confirmed bypasses: Unicode fullwidth,
  zero-width-space tags, non-bash code fences, HTML entities, base64. Build Python reference
  implementation with hypothesis fuzz tests. Integrate into all 4 untrusted-content channels.
  Define TrustedContent NewType for mypy enforcement. Ref: phase2-flux-drive-skill S1/S-IMP2,
  phase1-security F2.

**Estimated effort:** 6-8 hours

---

### C4 — flux-review Command → Skill Refactor

**Problem statement:** commands/flux-review.md is 551 lines — 10x the size of any other
command (others 9-96 lines). Commands are thin dispatchers; skills contain orchestration.
Phase 2.3 A-P2-9 (plugin-architecture expert): structural misfit invisible from within the
plugin vocabulary. Compare: commands/flux-drive.md is 9 lines; the skill holds all logic.
Composer dead-code also persists in the command (B6 handles the skill side; this is the
command side — both should be removed atomically).

**Proposed design:**
- Create skills/flux-review/ — move orchestration into SKILL.md + phase files
  (phases/track-dispatch.md, phases/track-synthesis.md)
- Reduce commands/flux-review.md to ~20-line dispatcher matching commands/flux-drive.md
- Move track definitions and model routing tables to config/flux-review/tracks.yaml
- Atomically remove all Composer guard branches from the command
- Update plugin.json skills array; update validate-manifest.sh counts

**Scope boundary:** In: flux-review extraction, Composer removal from command, track config
externalization. Out: semantic-distance track design, flux-drive skill changes, test coverage
for flux-review, FluxBench per-track quality metrics.

**Dependencies:** B6 completes first; C4 then removes command-side Composer code atomically.
Independent of C1, C2, C3.

**Bead-create recipe:**
- Title: interflux: refactor commands/flux-review.md (551 lines) into skills/flux-review/
- Description: commands/flux-review.md is 551 lines — 10x any other command. Extract into
  skills/flux-review/ with phase files. Reduce command to ~20-line dispatcher. Atomically
  remove Composer dead branches from the command side. Move track definitions to
  config/flux-review/tracks.yaml. Update plugin.json + validate-manifest.sh.
  Ref: phase2-flux-review-full A-P2-9/A-P1-4.

**Estimated effort:** 5-7 hours

---

## 5. Category D — Deferred / Wontfix

| Finding | Disposition | Rationale |
|---------|-------------|-----------|
| skills/flux-research/ kept in repo | Rename to flux-research-legacy/ | Test-dependency rationale is real. Phase 2.3 A-P2-8 confirms auto-discovery loads any SKILL.md regardless of plugin.json. Rename makes the side-effect visible. |
| config/flux-drive/knowledge/ directory on disk | Human decision required | CLAUDE.md claims migration to interknow but 1 extra file exists only here. Resolving requires a decision: is the local dir canonical? Flag in AGENTS.md. |
| "Discourse" naming collision with Discourse-the-forum | Wontfix | Phase 2.3 B-P2-5: valid finding. Renaming would be a breaking change across all config file names, reaction.yaml keys, documentation. Add clarifying comment to AGENTS.md. |
| Knowledge compounding correctorium separation | Defer to interknow roadmap | Phase 2.2 S3 / Phase 2.3 C-P2-6: requires inter-session confirmation tracking outside interflux scope. |
| Diversity floor against reinforcing agent-selection loop | Future roadmap | Phase 2.2 SY-IMP1: valid explore/exploit concern. File under flux-drive v2 roadmap. |
| Per-severity discourse-health metrics decomposition | Future roadmap | Phase 2.3 C-P1-2: changes discourse-health.sh output schema and all consumers. Save for FluxBench v2. |
| flux-agent.py _count_usage_from_synthesis double-walk | Add TODO comment | PER-02: low impact at current scale. |
| AgentDropout threshold 0.6 anchored not derived | Defer | Phase 2.2 D7: needs FluxBench data to derive empirically. |
| Reflexive review COI declaration | Informational | Phase 2.3 B-P2-8: no action item. Note in AGENTS.md. |
| FLUX_GEN_VERSION integer not SemVer | Defer | Phase 2.3 B-P2-6: migration of all frontmatter is costly. Note in AGENTS.md. |
| Fixture version tracking / baseline invalidation on edit | Defer | Phase 2.3 B-P2-9: valid release-engineering concern. Needs fixture versioning infrastructure. Track as a FluxBench improvement. |
| model-registry.yaml dual dict/list format | Resolve in C1 | The migration check in lib_registry.py's normalize_models() closes this. Not a standalone action. |

---

## 6. Dependency Ordering

```
v0.2.60 (housekeeping — batch all A items):
  A-01 through A-18    independent, can merge individually

v0.2.61 (flock + security foundation):
  B1 — flock hardening (unblocks C1)
  B3 — initial sanitizer (enables B2's F2 integration)

v0.2.62 (validation layer + hygiene):
  B2 — Python spec validation (depends on B3)
  B5 — shell hygiene + canonicalization (independent)

v0.2.63 (skill consolidation):
  B4 — SKILL.md consolidation (prerequisite for C2)
  B6 — phase-file accuracy pass (prerequisite for C4)

Post-bundle epics (separate beads):
  C1 — lib_registry.py         after B1         ~1 sprint
  C3 — sanitize fuzz tests      after B2+B3      ~1 sprint
  C4 — flux-review refactor     after B6         ~1 sprint
  C2 — dispatch state machine   after B4+B6      ~1.5 sprints (most design-intensive)
```

Hard blocking dependencies:
- B1 before C1 (flock patterns validated in isolation before extraction)
- B3 before B2 (sanitizer required for F2 integration in render_agent)
- B4 + B6 before C2 (dead code and dual-file removed before state machine is formalized)

---

## 7. Testing Strategy

Current state: scripts/ has 5500 LOC and zero unit tests (Phase 2.1 ARC-05 explicit gap).

**Immediate (ship with B1-B3):**
- scripts/tests/test_validate_agent_spec.py — 30+ fixture cases for AgentSpec validator;
  cover: list normalization, severity_examples item validation, name regex, path traversal
  rejection, Unicode field values, LLM prose-before-JSON stripping
- scripts/tests/test_sanitize_untrusted.py — 40+ fixtures including all confirmed S1
  bypass patterns as regressions; 10+ legitimate findings that must not falsely strip;
  hypothesis fuzz tests with text() + Unicode categories
- scripts/tests/test_lib_registry.py — cover models:null/dict/list migration, concurrent
  read simulation, corrupt YAML rejection, missing slug creation (ship with C1)

**Near-term (ship with C-series):**
- scripts/tests/test_fluxbench_score.py — Hungarian algorithm edge cases, P0 auto-fail,
  severity downgrade detection; only feasible after _fluxbench_score.py extraction in C1
- scripts/tests/test_domain_inference.py — keyword table comparison between generate-agents
  and flux-agent outputs; would have caught the ARC-04 domain-classification divergence

**CI integration:**
- scripts/ci/shellcheck.sh — shellcheck -s bash scripts/*.sh on every PR; would auto-detect
  the 2>&1 $(...) anti-pattern (QUA-03) and ~50% of Phase 2.1 fd-correctness findings
- Add scripts/validate-manifest.sh as pre-commit hook — already exists and passed Phase 0;
  wiring it closes the "description drifts from filesystem" loop

---

## 8. Risks and Unknowns

1. **FluxBench calibration data integrity unknown.** Three P0 silent failures (estimate-costs
   schema drift, session-start budget override, fluxbench-calibrate --mock overwrite) have
   been present for an unknown number of runs. Current model-registry.yaml qualified baselines
   may derive from corrupted calibration runs. Before relying on any FluxBench qualification
   verdict, validate that qualifying runs used source: claude-baseline (not --mock) and that
   the thresholds file has not been silently replaced.

2. **SKILL-compact.md load frequency unknown.** The <!-- compact: SKILL-compact.md -->
   directive in SKILL.md:8 points to compact when it exists. If compact was the file loaded
   in production sessions, every such review skipped Phase 2.5 reaction round entirely. The
   span of time this was active and the fraction of sessions affected is unknown. B4
   (consolidation) should ship as soon as possible.

3. **interbase-stub.sh is live dead code.** hooks/session-start.sh sources
   hooks/interbase-stub.sh which is a no-op. Phase 2.3 A-P2-7: no discovery logic upgrades
   to live when interbase is available. Whether interbase exists as a working package anywhere
   in the Sylveste ecosystem is unknown. If it does, every interflux session misses it.

4. **OpenRouter rate-limit bypass at scale.** tokenBucket and cumulativeSpendUsd are in-process
   in-memory state (Phase 2.3 A-P1-5). Concurrent sessions or cron-triggered flux-review runs
   each see the full configured limits independently. The configured $1.00 ceiling is effectively
   unbounded at scale. B3's persistence fix is required before flux-review is used in automated
   pipelines.

5. **Progressive enhancement adoption unmeasured.** Phase 2.3 A-P2-10: no telemetry on which
   progressive enhancement gates actually open (qmd, lib-routing.sh, lib-interspect.sh,
   lib-trust.sh, fluxbench-challenger, interrank MCP). Some may be dead for all users with
   silent skip paths that have bugs never triggering. A follow-up review auditing progressive
   enhancement availability across known deployment configurations would be high-leverage.

6. **Campaign blind spots:** Not reviewed — docs/spec/ (9-file protocol spec, may have
   drifted from implementation), agents/review/fd-*.md individual generated files (only
   metadata reviewed), tests/fixtures/qualification/ (fixture content affects FluxBench
   verdicts; Phase 2.3 B-P2-9 notes fixture edits silently invalidate baselines),
   mcp-servers/openrouter-dispatch/index.ts beyond line 30 (only startup/config path reviewed
   for A-02/A-03), interserve/interbase plugin state in the broader Sylveste monorepo.
