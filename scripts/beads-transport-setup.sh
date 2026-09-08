#!/usr/bin/env bash
# Check, and optionally install, the Beads git transport for THIS checkout.
#
#   scripts/beads-transport-setup.sh            # check (default); exit 1 on any problem
#   scripts/beads-transport-setup.sh install    # make the tracked hooks effective here
#   scripts/beads-transport-setup.sh --json     # machine-readable check
#
# What "installed" means. The hooks are tracked files in .beads/hooks/ — they
# arrive with every clone. What does not arrive is git's decision to RUN them:
# core.hooksPath. The isolated roadmap-publishing clone had every hook file
# and ran none of them, and every file-presence check called it healthy. So
# this checks the EFFECTIVE hook path, per worktree, and it checks which
# database `bd` in this checkout actually talks to, because a hook that
# exports the wrong database exits 0 too (sylveste-vqlu).
#
# Worktrees. A linked worktree shares the main checkout's git config, so
# `git config core.hooksPath` written here would rewrite it for every
# worktree at once. Installation therefore enables extensions.worktreeConfig
# and writes core.hooksPath into this worktree's own config.worktree; every
# other worktree keeps exactly the effective path it had, and `install`
# proves that by reading each one before and after. Native `bd hooks install`
# writes the shared value and its own shims; it is composed, not replaced —
# it does not install Sylveste's transport blocks, which are in the tracked
# hook files this command verifies.
#
# What it never does: initialise a database. A checkout whose `bd info`
# fails is reported, with the native command that would bring it up, and
# nothing is written. `bd init` makes its own commit and its own metadata,
# and a wrong one silently rebinds the checkout to another database.
set -uo pipefail

MODE=check
JSON=0
EXPECT_DB=""
EXPECT_PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    check|install) MODE="$1" ;;
    --json) JSON=1 ;;
    --expect-database) EXPECT_DB="${2:-}"; shift ;;
    --expect-project) EXPECT_PROJECT="${2:-}"; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not inside a git worktree" >&2; exit 2; }
cd "$TOP" || exit 2
GITDIR="$(git rev-parse --path-format=absolute --git-dir)"
COMMON="$(git rev-parse --path-format=absolute --git-common-dir)"
LINKED=0; [ "$GITDIR" != "$COMMON" ] && LINKED=1
MAIN_TOP="$(cd "$(dirname "$COMMON")" && pwd -P)"
HOOKS_DIR="$TOP/.beads/hooks"
STATE_DIR="$TOP/.beads/transport"

# shellcheck source=scripts/lib-beads-transport.sh
[ -f "$TOP/scripts/lib-beads-transport.sh" ] && . "$TOP/scripts/lib-beads-transport.sh"

problems=0
warnings=0
checks=()      # "level|name|detail" — level: ok | warn | FAIL | info
report() { checks+=("$1|$2|$3"); case "$1" in FAIL) problems=$((problems + 1)) ;; warn) warnings=$((warnings + 1)) ;; esac; }

realpath_of() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

# Effective hook path for a worktree, resolved the way git resolves it:
# relative paths are relative to the worktree top.
effective_hooks_path() {   # effective_hooks_path <worktree-top>
  local wt="$1" raw
  raw="$(git -C "$wt" config --get core.hooksPath 2>/dev/null || true)"
  if [ -z "$raw" ]; then
    printf '%s\n' "$(git -C "$wt" rev-parse --path-format=absolute --git-dir)/hooks"
  elif [ "${raw#/}" != "$raw" ]; then
    realpath_of "$raw"
  else
    realpath_of "$wt/$raw"
  fi
}

# ─── 1. Layout ────────────────────────────────────────────────────────

report info "worktree" "$TOP (linked=$LINKED, main=$MAIN_TOP)"
[ -f "$TOP/.beads/issues.jsonl" ] && report ok "transport file" ".beads/issues.jsonl present" \
  || report FAIL "transport file" ".beads/issues.jsonl missing — this checkout carries no bead state"

helpers=(scripts/beads-auto-export.sh scripts/beads-import-merged.sh scripts/beads-confirm-deletion.sh \
         scripts/lib-beads-transport.sh scripts/check_beads_jsonl_dolt_sync.py scripts/beads_apply_deletions.py)
for h in "${helpers[@]}"; do
  if [ ! -f "$TOP/$h" ]; then
    report FAIL "helper $h" "missing"
  elif [[ "$h" == *.sh ]] && [ ! -x "$TOP/$h" ] && [[ "$h" != *lib-* ]]; then
    report FAIL "helper $h" "not executable"
  fi
done

# ─── 2. The tracked hooks carry the transport blocks ──────────────────

declare -A MARK=(
  [pre-commit]="SYLVESTE BEADS JSONL/DOLT DRIFT GUARD"
  [post-commit]="SYLVESTE BEADS AUTO-EXPORT"
  [post-merge]="SYLVESTE BEADS AUTO-IMPORT"
  [pre-push]="SYLVESTE BEADS EGRESS WARNING"
)
for hook in pre-commit post-commit post-merge pre-push; do
  f="$HOOKS_DIR/$hook"
  if [ ! -f "$f" ]; then
    report FAIL "hook $hook" "missing from .beads/hooks/"
  elif [ ! -x "$f" ]; then
    report FAIL "hook $hook" "present but not executable"
  elif ! grep -q "${MARK[$hook]}" "$f"; then
    report FAIL "hook $hook" "present but lacks the '${MARK[$hook]}' block"
  else
    foreign="$(grep -c 'BEGIN BEADS INTEGRATION\|interwatch managed block\|dolt auto-push block' "$f")"
    report ok "hook $hook" "transport block present; $foreign foreign section(s) preserved"
  fi
done
# post-merge: bd's own block must come AFTER the transport block, which
# disables bd's unclassified auto-import for that invocation (BD_IMPORT_AUTO).
# An import that ran before the classifier would overwrite independent local
# edits, and nothing afterwards could undo it.
pm="$HOOKS_DIR/post-merge"
if [ -f "$pm" ]; then
  ours_at="$(grep -n 'BEGIN SYLVESTE BEADS AUTO-IMPORT' "$pm" | head -1 | cut -d: -f1)"
  native_at="$(grep -n 'BEGIN BEADS INTEGRATION' "$pm" | head -1 | cut -d: -f1)"
  override_at="$(grep -n '^export BD_IMPORT_AUTO' "$pm" | head -1 | cut -d: -f1)"
  if [ -z "$override_at" ]; then
    report FAIL "hook post-merge order" "no BD_IMPORT_AUTO override; bd's block would import the JSONL unclassified"
  elif [ -n "$native_at" ] && [ "$native_at" -lt "$override_at" ]; then
    report FAIL "hook post-merge order" "bd's block (line $native_at) runs before the transport override (line $override_at); it would import unclassified"
  else
    report ok "hook post-merge order" "transport block (line ${ours_at:-?}) and BD_IMPORT_AUTO override precede bd's block (line ${native_at:-none})"
  fi
fi

# ─── 3. Are they effective HERE? ──────────────────────────────────────

EFFECTIVE="$(effective_hooks_path "$TOP")"
WANT="$(realpath_of "$HOOKS_DIR")"
HOOKS_ACTIVE=0
if [ "$EFFECTIVE" = "$WANT" ]; then
  HOOKS_ACTIVE=1
  report ok "effective hooksPath" "$EFFECTIVE"
else
  report FAIL "effective hooksPath" "$EFFECTIVE — the tracked hooks at $WANT are NOT the ones git runs here"
fi
scope="$(git config --show-scope --get core.hooksPath 2>/dev/null | awk '{print $1}' || true)"
[ -n "$scope" ] && report info "hooksPath scope" "$scope"
if [ "$LINKED" -eq 1 ] && [ "$HOOKS_ACTIVE" -eq 1 ] && [ "$scope" != "worktree" ]; then
  report warn "hooksPath scope" "inherited from the shared config, not set per worktree; another worktree's install could change it"
fi

# ─── 3b. What would stop running if core.hooksPath moved? ─────────────

# Switching core.hooksPath silently retires every hook in the directory that
# was effective before. That is preservation-or-refusal territory, not
# migration: a previous hook is acceptable only when everything in it that is
# not a known managed transport section is retained, line for line, in the
# tracked hook that would replace it (an older copy of these very hooks, or a
# bare bd shim). Anything else — a custom post-commit, a hook name we do not
# ship — refuses before any config is written, and names the file. Whole old
# Sylveste hooks are never chained or re-run: that would reintroduce the
# unguarded native import or export twice.
FOREIGN_BLOCKERS=()
if [ "$HOOKS_ACTIVE" -eq 0 ] && [ -d "$EFFECTIVE" ]; then
  for f in "$EFFECTIVE"/*; do
    [ -f "$f" ] && [ -x "$f" ] || continue
    name="$(basename "$f")"
    case "$name" in *.sample) continue ;; esac
    ours="$HOOKS_DIR/$name"
    if [ ! -f "$ours" ]; then
      FOREIGN_BLOCKERS+=("$f (no tracked $name to retain it)")
      continue
    fi
    if cmp -s "$f" "$ours"; then
      continue
    fi
    # Only the four transport sections are excluded from the comparison —
    # they are the thing being replaced. Every other line of the old hook,
    # including lines inside bd's or any other manager's block, must be
    # present in the tracked hook or the switch is refused.
    lost="$(python3 - "$f" "$ours" <<'PY'
import re, sys
MANAGED = ("SYLVESTE BEADS AUTO-EXPORT", "SYLVESTE BEADS AUTO-IMPORT",
           "SYLVESTE BEADS JSONL/DOLT DRIFT GUARD", "SYLVESTE BEADS EGRESS WARNING")
def remainder(path):
    keep, skip = [], None
    for line in open(path, encoding="utf-8", errors="replace"):
        s = line.strip()
        m = re.match(r"#\s*-{3}\s*(BEGIN|END) (.+?)\s*-{3}$", s)
        if m and m.group(2) in MANAGED:
            skip = m.group(2) if m.group(1) == "BEGIN" else None
            continue
        if skip or not s or s.startswith("#"): continue
        keep.append(s)
    return keep
old, new = remainder(sys.argv[1]), set(remainder(sys.argv[2]))
missing = [l for l in old if l not in new]
print("\n".join(missing[:5]))
PY
)"
    if [ -n "$lost" ]; then
      FOREIGN_BLOCKERS+=("$f (retains content the tracked $name lacks, e.g. '$(printf '%s' "$lost" | head -1 | cut -c1-80)')")
    else
      report info "previous hook $name" "$f — every non-transport line is retained by the tracked hook"
    fi
  done
  for b in "${FOREIGN_BLOCKERS[@]}"; do
    report FAIL "effective hook would be lost" "$b — move it into the tracked hook's foreign sections, or keep core.hooksPath as it is"
  done
fi

# ─── 4. Which database does bd talk to from here? ─────────────────────

DB_OK=0
if ! command -v bd >/dev/null 2>&1; then
  report FAIL "bd" "not on PATH"
else
  # Run from $TOP (cd above), never `bd -C $TOP`: in a linked worktree -C
  # resolves the .beads/ ABOVE the worktree — on Clavain the ~/projects
  # workspace database — while a cwd run follows the .git file to the main
  # checkout. Verified 2026-09-07 with both `bd context --json` and `bd info`.
  # The structured context is preferred; the legacy text is the fallback.
  ctx="$(beads_capture_bounded "${BEADS_INFO_TIMEOUT:-15}" bd --readonly --sandbox context --json 2>/dev/null)" || ctx=""
  read -r db ctx_project ctx_db ctx_wt <<EOF
$(printf '%s' "$ctx" | python3 -c '
import json, sys
raw = sys.stdin.read(); start = raw.find("{")
try:
    d = json.loads(raw[start:]) if start >= 0 else {}
except Exception:
    d = {}
print(d.get("beads_dir") or "-", d.get("project_id") or "-", d.get("database") or "-", str(d.get("is_worktree", "-")).lower())' 2>/dev/null || echo "- - - -")
EOF
  if [ "$db" = "-" ]; then
    info_out="$(beads_capture_bounded "${BEADS_INFO_TIMEOUT:-15}" bd --readonly --sandbox info 2>/dev/null)" || info_out=""
    db="$(printf '%s\n' "$info_out" | sed -n 's/^Database:[[:space:]]*//p' | head -1)"
  else
    report info "bd context" "project=$ctx_project database=$ctx_db is_worktree=$ctx_wt"
  fi
  if [ -z "$db" ]; then
    report FAIL "database" "bd reports no database for this checkout. Not initialised here? Bring it up yourself with 'bd bootstrap' (a fresh clone) — this command never initialises a database."
  else
    db_real="$(realpath_of "$db")"
    expected_root="$(realpath_of "$MAIN_TOP/.beads")"
    case "$db_real" in
      "$expected_root"|"$expected_root"/*) DB_OK=1; report ok "database" "$db (the main checkout's .beads/)" ;;
      *) report FAIL "database" "$db is NOT $expected_root — this checkout is bound to a different database; exporting from here would publish the wrong project (sylveste-vqlu)" ;;
    esac
    if [ -n "$EXPECT_DB" ] && [ "$db_real" != "$(realpath_of "$EXPECT_DB")" ]; then
      DB_OK=0; report FAIL "database" "expected $EXPECT_DB, got $db"
    fi
    if [ -n "$EXPECT_PROJECT" ] && [ "$ctx_project" != "-" ] && [ "$ctx_project" != "$EXPECT_PROJECT" ]; then
      DB_OK=0; report FAIL "project" "bd context reports $ctx_project, expected $EXPECT_PROJECT"
    fi
  fi
  if [ "$LINKED" -eq 1 ] && [ -f "$TOP/.beads/metadata.json" ]; then
    DB_OK=0; report FAIL "metadata" "$TOP/.beads/metadata.json exists in a linked worktree — a copied binding; bd should resolve the main checkout's database without it"
  fi
  meta="$MAIN_TOP/.beads/metadata.json"
  if [ -f "$meta" ]; then
    project="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("project_id",""))' "$meta" 2>/dev/null || true)"
    if [ -n "$EXPECT_PROJECT" ] && [ "$project" != "$EXPECT_PROJECT" ]; then
      DB_OK=0; report FAIL "project" "expected $EXPECT_PROJECT, main checkout binds $project"
    else
      report info "project" "${project:-unknown} ($meta)"
    fi
  else
    [ -n "$EXPECT_PROJECT" ] && { DB_OK=0; report FAIL "project" "no $meta to verify --expect-project against"; }
  fi
  if git -C "$TOP" ls-files --error-unmatch .beads/metadata.json >/dev/null 2>&1; then
    report FAIL "metadata" ".beads/metadata.json is git-tracked; it is a per-machine binding and must not travel"
  fi

fi

# ─── 5. Transport state ───────────────────────────────────────────────

if [ -f "$STATE_DIR/pending-import.json" ]; then
  report FAIL "pending import" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(f"{d.get(\"rows\")} row(s), reason={d.get(\"reason\")}, before={d.get(\"before\")}, after={d.get(\"after\")}, attempts={d.get(\"attempts\")}")' "$STATE_DIR/pending-import.json" 2>/dev/null) — scripts/beads-import-merged.sh --retry"
fi
if [ -f "$STATE_DIR/conflicts.json" ]; then
  n="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("records",{})))' "$STATE_DIR/conflicts.json" 2>/dev/null || echo 0)"
  [ "${n:-0}" -gt 0 ] && report warn "conflicts" "$n unresolved record(s) in $STATE_DIR/conflicts.json (both versions under evidence/)"
fi
if [ -f "$STATE_DIR/baseline.json" ]; then
  report info "baseline" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(f"{len(d.get(\"records\",{}))} verified record(s), updated {d.get(\"updated_at\",\"?\")}")' "$STATE_DIR/baseline.json" 2>/dev/null)"
else
  report warn "baseline" "no verified baseline yet — every differing record is a conflict until the sides agree or one is seeded"
fi
# Status is read from the per-key records (status.d/), not only from the
# status.json view a slow writer may not have rebuilt yet, and an import that
# was refused admission AFTER the last import verdict is surfaced instead of
# the older success.
if [ -d "$STATE_DIR/status.d" ] || [ -f "$STATE_DIR/status.json" ]; then
  while IFS='|' read -r level name detail; do
    [ -n "$level" ] && report "$level" "$name" "$detail"
  done < <(python3 - "$STATE_DIR" <<'PY'
import json, os, sys
d = sys.argv[1]
MALFORMED = object()
def rec(key):
    # The per-key record is authoritative. If it exists but cannot be read it
    # is reported as such — never replaced by an older value from the view.
    record = os.path.join(d, "status.d", key + ".json")
    if os.path.exists(record):
        try:
            with open(record, encoding="utf-8") as fh:
                data = json.load(fh)
            return data if isinstance(data, dict) else MALFORMED
        except Exception:
            return MALFORMED
    try:
        with open(os.path.join(d, "status.json"), encoding="utf-8") as fh:
            legacy = json.load(fh)
        data = legacy.get(key) if isinstance(legacy, dict) else None
        return data if isinstance(data, dict) else None
    except Exception:
        return None
def line(label, data):
    if data is MALFORMED:
        return f"FAIL|{label}|status record is malformed; kept as evidence under status.d/, no verdict can be read"
    return f"info|{label}|{(data or {}).get('result','never')} at {(data or {}).get('at','-')}"
exp, imp, na = rec("export"), rec("import"), rec("import_not_attempted")
print(line("last export", exp))
print(line("last import", imp))
if na is MALFORMED:
    print("FAIL|import not attempted|status record is malformed; kept as evidence under status.d/")
elif na and (imp is MALFORMED or not imp or str(na.get("at", "")) >= str(imp.get("at", ""))):
    print(f"warn|import not attempted|{na.get('reason')} at {na.get('at','-')}: {na.get('message','')} (newer than the last import verdict)")
try:
    with open(os.path.join(d, "status.json"), encoding="utf-8") as fh:
        bad = json.load(fh).get("_malformed") or []
    if bad:
        print(f"warn|status records|malformed, kept as evidence: {' '.join(bad)}")
except Exception:
    pass
PY
)
fi
if command -v beads_transport_lock_held >/dev/null 2>&1 && beads_transport_lock_held 2>/dev/null; then
  report warn "lock" "a transport operation currently holds the lock"
fi

# ─── 6. Other worktrees (visibility; install proves they are unchanged) ─

other_worktrees=()
while IFS= read -r line; do
  case "$line" in
    "worktree "*) wt="${line#worktree }"; [ "$(realpath_of "$wt")" != "$(realpath_of "$TOP")" ] && other_worktrees+=("$wt") ;;
  esac
done < <(git worktree list --porcelain 2>/dev/null)
declare -A BEFORE_PATHS=()
for wt in "${other_worktrees[@]}"; do
  [ -d "$wt" ] || continue
  BEFORE_PATHS["$wt"]="$(effective_hooks_path "$wt")"
  report info "other worktree" "$wt -> ${BEFORE_PATHS[$wt]}"
done

# ─── 7. Install ───────────────────────────────────────────────────────

if [ "$MODE" = "install" ]; then
  if [ "$DB_OK" -ne 1 ]; then
    report FAIL "install" "refused: the database binding above is not verified; installing hooks here would run the transport against the wrong database"
  elif [ "${#FOREIGN_BLOCKERS[@]}" -gt 0 ]; then
    report FAIL "install" "refused before any config change: ${#FOREIGN_BLOCKERS[@]} effective hook(s) would stop running (listed above)"
  elif [ "$HOOKS_ACTIVE" -eq 1 ] && { [ "$LINKED" -eq 0 ] || [ "$scope" = "worktree" ]; }; then
    report ok "install" "unchanged; already effective"
  else
    need_wt_config=0
    if [ "$LINKED" -eq 1 ] || [ "${#other_worktrees[@]}" -gt 0 ]; then need_wt_config=1; fi
    if [ "$need_wt_config" -eq 1 ] && [ "$(git config --get extensions.worktreeConfig 2>/dev/null)" != "true" ]; then
      # git requires core.bare / core.worktree to move into the main worktree's
      # config.worktree when the extension is enabled; refuse rather than
      # guess at a repository laid out that way.
      if git config --file "$COMMON/config" --get core.worktree >/dev/null 2>&1 || \
         [ "$(git config --file "$COMMON/config" --get core.bare 2>/dev/null)" = "true" ]; then
        report FAIL "install" "refused: core.worktree/core.bare is set in the shared config; enabling extensions.worktreeConfig needs those moved by hand first (git help worktree, CONFIGURATION FILE)"
      else
        git config extensions.worktreeConfig true && report info "install" "enabled extensions.worktreeConfig (shared, one-time; no worktree's effective hooksPath changes by itself)"
      fi
    fi
    if [ "$problems" -eq 0 ] || ! printf '%s\n' "${checks[@]}" | grep -q '^FAIL|install|'; then
      if [ "$need_wt_config" -eq 1 ]; then
        git config --worktree core.hooksPath "$HOOKS_DIR" && report ok "install" "core.hooksPath=$HOOKS_DIR written to this worktree's config.worktree"
      else
        git config core.hooksPath "$HOOKS_DIR" && report ok "install" "core.hooksPath=$HOOKS_DIR written to the repository config"
      fi
      EFFECTIVE="$(effective_hooks_path "$TOP")"
      if [ "$EFFECTIVE" = "$WANT" ]; then
        HOOKS_ACTIVE=1
        # Retire the earlier FAIL for this worktree's path now that it is effective.
        for i in "${!checks[@]}"; do [[ "${checks[$i]}" == "FAIL|effective hooksPath|"* ]] && { checks[$i]="ok|effective hooksPath|$EFFECTIVE (installed)"; problems=$((problems - 1)); }; done
        for i in "${!checks[@]}"; do [[ "${checks[$i]}" == "warn|hooksPath scope|"* ]] && { checks[$i]="ok|hooksPath scope|worktree"; warnings=$((warnings - 1)); }; done
      else
        report FAIL "install" "wrote core.hooksPath but the effective path is still $EFFECTIVE"
      fi
    fi
    for wt in "${other_worktrees[@]}"; do
      [ -d "$wt" ] || continue
      after="$(effective_hooks_path "$wt")"
      if [ "$after" = "${BEFORE_PATHS[$wt]}" ]; then
        report ok "other worktree unchanged" "$wt -> $after"
      else
        report FAIL "other worktree CHANGED" "$wt: ${BEFORE_PATHS[$wt]} -> $after"
      fi
    done
  fi
fi

# ─── 8. Native composition (informational) ────────────────────────────

if command -v bd >/dev/null 2>&1; then
  native="$(beads_capture_bounded 15 bd hooks list 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g')"
  [ -n "$native" ] && report info "bd hooks list" "$native"
fi

# ─── Report ───────────────────────────────────────────────────────────

if [ "$JSON" -eq 1 ]; then
  python3 - "$MODE" "$TOP" "$LINKED" "$EFFECTIVE" "$WANT" "$HOOKS_ACTIVE" "$DB_OK" "$problems" "$warnings" "${checks[@]}" <<'PY'
import json, sys
mode, top, linked, effective, want, active, db_ok, problems, warnings, *checks = sys.argv[1:]
rows = []
for c in checks:
    level, name, detail = c.split("|", 2)
    rows.append({"level": level, "check": name, "detail": detail})
print(json.dumps({
    "mode": mode, "worktree": top, "linked": linked == "1",
    "effective_hooks_path": effective, "tracked_hooks_path": want,
    "hooks_active": active == "1", "database_verified": db_ok == "1",
    "problems": int(problems), "warnings": int(warnings), "ok": int(problems) == 0,
    "checks": rows,
}, indent=2))
PY
else
  for c in "${checks[@]}"; do
    level="${c%%|*}"; rest="${c#*|}"; name="${rest%%|*}"; detail="${rest#*|}"
    printf '[%-4s] %-26s %s\n' "$level" "$name" "$detail"
  done
  if [ "$problems" -eq 0 ]; then
    echo "beads transport: OK in $TOP${warnings:+ ($warnings warning(s))}"
  else
    echo "beads transport: $problems problem(s) in $TOP — hooks are NOT fully effective here" >&2
  fi
fi
[ "$problems" -eq 0 ]
