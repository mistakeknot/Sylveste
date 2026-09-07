<!-- flux-drive:complete -->

## Findings Index

- P1 | SAF-01 | "discourse-health.sh:39" | Shell injection via `config_path` interpolated into python3 -c heredoc
- P1 | SAF-02 | "estimate-costs.sh:51" | `agent_type` interpolated into `grep` pattern without escaping
- P1 | SAF-03 | "fluxbench-sync.sh:108" | `safe_slug` sed pipeline incomplete — Windows-style paths, unicode slashes, and backslash bypass the traversal guard
- P2 | SAF-04 | "discover-models.sh:83" | `eval task="\$${tier^^}_TASK"` — eval on variable-name interpolation (safe today, fragile)
- P2 | SAF-05 | "fluxbench-qualify.sh:338" + "fluxbench-calibrate.sh:221" | manifest.json fields re-read without checksum; manifest-path traversal check is partial
- P2 | SAF-06 | "launch-openrouter.sh:22" | Auto-build runs `npm ci` on first use with no checksum verification of package-lock.json

## Verdict

**MINOR-ISSUES — one P1 shell-injection in discourse-health.sh (user-controlled config_path lands in a python heredoc), one P1 unvalidated grep pattern in estimate-costs.sh, and two P1-adjacent boundary issues in the sync path-traversal guard. None are remotely exploitable today (all inputs come from trusted config files on disk), but defense-in-depth says harden them.**

De-duplication note: The v0.2.58 campaign already flagged `generate-agents.py:~516` (name regex) and `persona/decision_lens/review_areas` sanitization gap. I **do not** restate those — they converge with my review, and I add only the additional untrusted-content pathways I found.

## Summary

I reviewed scripts/ for shell injection, path traversal, credential leakage, and untrusted-content handling. The trust model is "all configs, manifests, and result files come from disk and are trusted; LLM specs are the only untrusted path." Within that model, three issues materially weaken the boundary; the rest are acceptable progressive-enhancement choices.

**Credential handling**: Clean. `EXA_API_KEY` and `OPENROUTER_API_KEY` are checked via `[[ -z ... ]]` guards and never echoed. No secrets land in logs.

**Shell injection surface**: Small but non-zero. Four paths deserve attention (SAF-01 through SAF-04).

**Path traversal**: Two partial guards (fluxbench-sync.sh:107–117, fluxbench-qualify.sh:368–380) correctly use `realpath -m` prefix checks — but the filename sanitization at sync.sh:108 is incomplete.

**LLM-output trust**: Already tracked in Phase 1 (fd-safety earlier findings F1–F2).

## Issues Found

### P1 | SAF-01 | `config_path` interpolated into python3 -c heredoc (discourse-health.sh:39)

**File**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/discourse-health.sh`

**Lines 37–43**:
```bash
if [[ -n "$config_path" && -f "$config_path" ]]; then
  _read_yaml() { python3 -c "import yaml,sys; d=yaml.safe_load(open('$config_path')); print(d$1)" 2>/dev/null || echo "$2"; }
  gini_max=$(_read_yaml "['flow_envelope']['participation_gini_max']" "$gini_max")
```

**What breaks**: `$config_path` comes from the `--config` CLI flag. It is interpolated directly into a Python string literal with `open('$config_path')`. A path containing a single quote closes the `open()` call and allows arbitrary Python to execute before a second unpaired quote reopens the literal. The `2>/dev/null` suppresses the stderr that would have tipped off the user.

**Exploitability**: Requires attacker-controlled `--config` arg. Today, `discourse-health.sh` is only invoked by other flux-drive scripts with hardcoded paths. But the CLI is documented (`Usage: discourse-health.sh <OUTPUT_DIR> [--config <sawyer-config.yaml>]`). If a user runs it manually on a path they don't control (e.g., from a cloned repo), the injection fires.

**Fix**: Pass `config_path` via env var, not interpolation (same pattern used elsewhere in the plugin):
```bash
_read_yaml() {
  CONFIG_PATH="$config_path" python3 -c "
import yaml, os, sys
d = yaml.safe_load(open(os.environ['CONFIG_PATH']))
print(d$1)
" 2>/dev/null || echo "$2"
}
```

Note this pattern is **already the house style** (see fluxbench-challenger.sh:136, fluxbench-qualify.sh:261–267, discover-merge.sh:14–22). This site just missed the migration.

### P1 | SAF-02 | `agent_type` interpolated into grep pattern without escaping

**File**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/estimate-costs.sh`

**Lines 47–55**:
```bash
get_default() {
  local agent_type="$1"
  local default_val="40000"
  local line
  line=$(grep "^  ${agent_type}:" "$BUDGET_FILE" 2>/dev/null || echo "")
  ...
```

**What breaks**: `agent_type` flows from `classify_agent()` which returns hard-coded strings (`cognitive`, `research`, `oracle`, `review`, `generated`) — the five hardcoded types are safe today.

**BUT** the `agent_type` is used **directly as a regex pattern** in `grep`. If someone extends `classify_agent` to return a derived value (e.g., `echo "$name"` for future per-agent defaults), regex metacharacters (`.`, `*`, `[`) in agent names become active — at minimum producing wrong matches, at worst infinite loops on pathological regexes.

**Exploitability**: Zero today; activates the moment `classify_agent` returns a derived value.

**Fix**: `grep -F -- "^  ${agent_type}:"` won't work (literal mode can't anchor with `^`). Use an awk comparison:
```bash
line=$(awk -v t="$agent_type" '$1 == t":" { $1=""; sub(/^ */,""); sub(/ *#.*/,""); print; exit }' "$BUDGET_FILE")
```
This treats `agent_type` as a literal string comparison.

### P1 | SAF-03 | Filesystem-safe slug sanitization is incomplete

**File**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/fluxbench-sync.sh`

**Line 108**:
```bash
safe_slug=$(echo "$model_slug" | sed 's|/|--|g' | sed 's|\.\.|_|g')
```

**What breaks**: The guard strips `/` → `--` and `..` → `_`. Then line 112–117 defense-in-depth verifies `realpath -m` of target stays under agmodb_repo. But the sed pipeline misses:

- **Null byte** `\x00` — sed handles it inconsistently across platforms; on GNU sed, `\x00` truncates the string, which can produce collision with a short attacker-controlled slug ending at a different position.
- **Newline** `\n` — multi-line `model_slug` values split into multiple filenames (bash `>` only takes the last line as path).
- **Leading dash** — `-my-model` as filename tricks some cp/mv variants into flag parsing (though this script uses `mv "$tmp" "$target"` which is safe; still a footgun for future edits).
- **Unicode slash** `/` (U+FF0F FULLWIDTH SOLIDUS) — file systems treat it as a regular character, but sed's `/` pattern doesn't match it, so it passes through. Not traversal-exploitable today because realpath won't resolve it, but it produces filenames that look like directories in the AgMoDB repo.

**Downstream consequence**: The `realpath -m` check at line 112–117 **does** catch actual directory traversal. So this is a defense-in-depth weakening, not an active exploit. But the sanitization function is used as a filename-builder — so anomalous filenames (bidi-override characters, Windows-reserved names like `CON`, `NUL` on cross-platform clones) silently appear in the repo.

**Fix**: Whitelist rather than blacklist:
```bash
# Use the same regex as discover-merge.sh VALID_SLUG — tightest
if [[ ! "$model_slug" =~ ^[a-zA-Z0-9][a-zA-Z0-9/_.-]{0,127}$ ]]; then
  echo "Error: model_slug rejected" >&2
  continue
fi
safe_slug=$(echo "$model_slug" | tr '/' '-')
```
Rejecting non-matching slugs early is cleaner than sanitizing.

### P2 | SAF-04 | `eval task="\$${tier^^}_TASK"` (discover-models.sh:83)

**File**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/discover-models.sh`

**Line 82–83**:
```bash
for tier in checker analytical judgment; do
    eval task="\$${tier^^}_TASK"
```

**What breaks**: `$tier` comes from a hardcoded `for` list (`checker analytical judgment`), so `eval` is safe today. But `${tier^^}` uppercases and interpolates into an `eval` — if a future edit adds `$1` or derived tiers to the loop list, the eval evaluates whatever expression `${tier^^}_TASK` names.

**Fix**: Use indirect expansion, no eval:
```bash
var_name="${tier^^}_TASK"
task="${!var_name}"
```
Same result, no eval.

### P2 | SAF-05 | Manifest-path traversal check is partial (fluxbench-qualify.sh:368–380)

**File**: `fluxbench-qualify.sh:368–380`:
```bash
if [[ -n "$manifest_gt" && -f "$manifest_gt" ]]; then
  _real_gt=$(realpath -m "$manifest_gt")
  _real_fixtures=$(realpath -m "$fixtures_dir")
  if [[ "$_real_gt" == "$_real_fixtures"/* ]]; then
    ground_truth="$manifest_gt"
  else
    echo "  Warning: manifest ground_truth_path outside fixtures dir, using default" >&2
    ...
```

**What breaks**: The guard uses `realpath -m` which **resolves symlinks**. If `fixtures_dir` itself contains a symlink (e.g., a dev puts `tests/fixtures/qualification → /other/fixture-set`), the prefix check passes for `/other/fixture-set/*` — **correctly**, since it was the dev's intent. But in an automated environment where `fixtures_dir` is set via env var to an untrusted path, a symlink inside `fixtures_dir/fixture-001/ground-truth.json → /etc/passwd` would resolve, the realpath would be `/etc/passwd`, and the prefix check would FAIL (correct) — BUT the fallback at line 379 then uses `"${fixtures_dir}/${fixture_id}/ground-truth.json"` which **is still a symlink pointing to `/etc/passwd`**, because the fallback doesn't re-validate.

**Fix**: Apply the same realpath-prefix check to the fallback path, or resolve+validate once at the top of the loop:
```bash
resolved_gt=$(realpath -m "${fixtures_dir}/${fixture_id}/ground-truth.json")
real_fixtures=$(realpath -m "$fixtures_dir")
[[ "$resolved_gt" == "$real_fixtures"/* ]] || { echo "  skip: $fixture_id"; continue; }
ground_truth="$resolved_gt"
```

**Exploitability**: Requires an attacker with write access to `fixtures_dir` (normally local-only for tests). Low priority but the guard is misleading as written.

### P2 | SAF-06 | `launch-openrouter.sh` runs `npm ci` from script dir on first use

**File**: `/home/mk/projects/Sylveste/interverse/interflux/scripts/launch-openrouter.sh`

**Lines 20–23**:
```bash
if [[ ! -f "${SERVER_DIR}/dist/index.js" ]]; then
    echo "Building openrouter-dispatch MCP server..." >&2
    (cd "$SERVER_DIR" && npm ci && npm run build) >&2
fi
```

**What breaks**: `npm ci` runs `package-lock.json` install scripts from the plugin's directory — packages with `preinstall`/`postinstall` lifecycle scripts execute arbitrary code at plugin-launch time. If a future plugin update ships a dependency that is later compromised upstream (supply-chain attack), the script auto-runs it the next time an agent triggers MCP dispatch.

**Fix**: Two options:
- Use `npm ci --ignore-scripts` (safer but may break legitimate build deps).
- Ship a pre-built `dist/index.js` in the plugin repo — no auto-build path. This is the pattern every other Claude Code plugin I've reviewed uses.

**Severity**: P2 — no active supply-chain risk today (OPENROUTER_API_KEY gate limits blast radius), but auto-build is an unexpected security boundary for a plugin.

## Improvements

1. **Adopt the env-var-for-python-heredoc pattern uniformly** — discourse-health.sh:39 is the one remaining site that interpolates a path directly. Migration is mechanical (see fluxbench-challenger.sh:136 for the idiom).
2. **Consolidate slug-validation into a single helper** — 4 sites validate model/agent slug formats with slightly different regexes (discover-merge.sh:30, fluxbench-qualify.sh:46, fluxbench-drift.sh:16, fluxbench-sync.sh:108 implicit). Pick one canonical regex and a `validate_slug.sh` helper.
3. **Add a first-line-defense `umask 077` to atomic writers** — `_atomic_write` in generate-agents.py and flux-agent.py creates temp files with default umask. When running in a multi-user context (shared dev server), tmp files are world-readable for the blink-of-an-eye window before rename. Not a real threat in practice but trivial to harden.
4. **Document the trust model for scripts/** — a short `scripts/SECURITY.md` clarifying: "configs and manifests are trusted; LLM specs are untrusted; subagent output is partially trusted (see F3 in Phase 1 security review)" would prevent future sanitization regressions.
5. **Move `launch-openrouter.sh` to a pre-built dist** — eliminates the `npm ci` supply-chain surface entirely.
