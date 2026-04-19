---
artifact_type: plan
bead: sylveste-qdqr
stage: design
scope: v1 only (v1.5 and v2 land in follow-up plans)
source_brainstorm: docs/brainstorms/2026-04-19-auto-proceed-authz-design.md
source_synthesis: docs/research/flux-drive/2026-04-19-auto-proceed-authz-design-20260419T0239/SYNTHESIS.md
---

# Auto-proceed authorization framework — v1 implementation plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-qdqr
**Goal:** Ship the pull-model policy engine + per-project audit log so that vetted `/clavain:work` and `/clavain:sprint` flows can auto-proceed on `bd close`, `git push`, `bash .beads/push.sh`, and `ic publish --patch`, while preserving `mode: confirm` for everything else.

**Architecture:** Pull-model policy engine reads a layered `policy.yaml` (global → per-project → env) and per-bead vetting state at op time. Gate wrappers around each irreversible op call `clavain-cli policy check`, execute or confirm based on exit code, then call `policy record` to log the decision into per-project `.clavain/intercore.db`. The `.publish-approved` marker stays as an **additive** parallel gate for v1; unification lands in v1.5. No signing, no tokens in v1.

**Tech Stack:** Go (intercore + clavain-cli), SQLite (modernc.org/sqlite, WAL, `SetMaxOpenConns(1)`), YAML (`gopkg.in/yaml.v3`), Bash (gate wrappers), Markdown skill edits for `/work` and `/sprint` phases.

**Prior Learnings:**
- No `assess-*.md` verdict on authz tooling — greenfield.
- Reuse existing `intercore.db` schema migrations pattern (032_ is next; 031_lane_intent.sql is latest).
- `core/intercore/internal/publish/approval.go:38 RequiresApproval()` is the hook point for the future v1.5 unify — do NOT modify in v1.
- `.beads/push.sh` wraps `bd push`; wrap at the script level, not at `bd` call sites.
- `/work` Phase 3 is sprint-aware (skipped inside sprints); vetting writes must live in BOTH the non-sprint `/work` Phase 3 AND `/sprint` Steps 6-7.

---

## Must-Haves

**Truths:**
- Running `/clavain:sprint` on a vetted bead proceeds through `bd close`, `bash .beads/push.sh`, and `git push` without per-op confirmation prompts.
- Running the same ops **outside** a vetted flow (or with stale vetting >60 min old, or with uncommitted changes since vetting) triggers `mode: confirm` or `mode: block` correctly.
- `clavain-cli policy audit --since=1d` shows every auto-proceed decision with `policy_match`, `policy_hash`, and `vetted_sha` columns populated.
- `ic publish --patch` still honors `.publish-approved` (parallel gate) AND additionally writes an `authorizations` record (additive guard, not bridge).
- `clavain-cli scenario-policy-check` (renamed) still returns the same JSON as today's `policy-check` does — no breaking change for existing callers.

**Artifacts:**
- `core/intercore/internal/db/migrations/032_authorizations.sql` creates the `authorizations` table with all post-review columns.
- `core/intercore/internal/authz/` new package exports `LoadPolicy`, `Check`, `Record`, `MergePolicies`.
- `os/Clavain/cmd/clavain-cli/authz.go` new file exports cmd handlers for `policy check/record/explain/audit/list/lint`.
- `os/Clavain/cmd/clavain-cli/scripts/gates/` new dir with `bead-close.sh`, `git-push-main.sh`, `bd-push-dolt.sh`, `ic-publish-patch.sh`.
- `.clavain/gates/*.gate` registration markers (one per wrapped op).
- `docs/canon/policy-merge.md` with ≥5 worked merge examples.
- `~/.clavain/policy.yaml.example` global default template.

**Key Links:**
- `/clavain:work` Phase 3 + `/clavain:sprint` Steps 6-7 write `vetted_at`, `vetted_sha`, `tests_passed` → gate reads them at op time.
- Gate wrapper calls `policy check` → exits on confirm/block → otherwise runs op → calls `policy record` with `policy_hash` pinned from check.
- `policy record` writes to per-project `.clavain/intercore.db`; `--cross-project-id=<id>` shares a UUID across multi-repo ops.

---

## Task 1: Spec-lock round (no code)

**Files:**
- Create: `docs/canon/policy-merge.md`
- Create: `docs/canon/authz-cross-project-consistency.md`
- Modify: `docs/brainstorms/2026-04-19-auto-proceed-authz-design.md:~170` (backlink to canon docs)

**Step 1: Write `docs/canon/policy-merge.md`** with ≥5 worked examples covering: (a) global `vetted_within_minutes:60` + project `vetted_within_minutes:30` → result 30 (min), (b) global `tests_passed:true` + project attempts to drop → rejected unless `allow_override:true` on global, (c) global `op:"*" mode:confirm` + project `op:"*" mode:auto` → rejected (non-removable floor), (d) global `mode:auto` + project `mode:force_auto` → result `force_auto` with WARNING log, (e) two specific rules match — first-match wins, catchall `"*"` is terminal fallback.

**Step 2: Write `docs/canon/authz-cross-project-consistency.md`** pinning: `ic-publish-patch` is strict-all-or-nothing (fail any project → fail all, no partial records). All other ops (`bead-close`, `git-push-main`, `bd-push-dolt`) are best-effort; `policy audit --verify` surfaces gaps when `cross_project_id` groups have missing rows.

**Step 3: Commit**
```bash
git add docs/canon/policy-merge.md docs/canon/authz-cross-project-consistency.md docs/brainstorms/2026-04-19-auto-proceed-authz-design.md
git commit -m "docs(authz): spec-lock policy merge + cross-project consistency (sylveste-qdqr)"
```

<verify>
- run: `test -f docs/canon/policy-merge.md && grep -c '^### Example' docs/canon/policy-merge.md`
  expect: contains "5"
- run: `test -f docs/canon/authz-cross-project-consistency.md`
  expect: exit 0
</verify>

---

## Task 2: Rename existing `policy-check` / `policy-show` → `scenario-policy-*`

**Files:**
- Modify: `os/Clavain/cmd/clavain-cli/main.go:188-190` (rename cases, add deprecation alias)
- Modify: `os/Clavain/cmd/clavain-cli/policy.go` (rename functions, update doc comments)
- Modify: `os/Clavain/cmd/clavain-cli/policy_test.go` (update test names)
- Grep for callers: `grep -rn 'clavain-cli policy-check\|clavain-cli policy-show' ~/.claude/plugins/cache /home/mk/projects/Sylveste 2>/dev/null`

**Step 1: Write failing test**
`os/Clavain/cmd/clavain-cli/policy_test.go`:
```go
func TestScenarioPolicyCheckAlias(t *testing.T) {
    // Old name still works via alias (logs deprecation)
    out, err := runCLI(t, "policy-check", "--phase=plan", "--tool=Read")
    require.NoError(t, err)
    require.Contains(t, string(out), `"allowed"`)
    // New name is primary
    out2, err := runCLI(t, "scenario-policy-check", "--phase=plan", "--tool=Read")
    require.NoError(t, err)
    require.Equal(t, normalizeJSON(out), normalizeJSON(out2))
}
```

**Step 2: Run — expect FAIL** (`scenario-policy-check` not registered).

**Step 3: Add cases in `main.go`**
```go
case "scenario-policy-check":
    err = cmdScenarioPolicyCheck(args)
case "scenario-policy-show":
    err = cmdScenarioPolicyShow(args)
case "policy-check":
    fmt.Fprintln(os.Stderr, "DEPRECATED: use scenario-policy-check; will be removed in v0.7")
    err = cmdScenarioPolicyCheck(args)
case "policy-show":
    fmt.Fprintln(os.Stderr, "DEPRECATED: use scenario-policy-show; will be removed in v0.7")
    err = cmdScenarioPolicyShow(args)
```
Rename `cmdPolicyCheck` → `cmdScenarioPolicyCheck`, `cmdPolicyShow` → `cmdScenarioPolicyShow` in `policy.go`.

**Step 4: Run tests — expect PASS.**

**Step 5: Commit**
```bash
git add os/Clavain/cmd/clavain-cli/main.go os/Clavain/cmd/clavain-cli/policy.go os/Clavain/cmd/clavain-cli/policy_test.go
git commit -m "refactor(clavain-cli): rename policy-check/show → scenario-policy-* (sylveste-qdqr)

Frees the 'policy' subcommand namespace for the auto-proceed authz layer.
Old names kept as deprecation aliases; removal in v0.7."
```

<verify>
- run: `cd os/Clavain && go test ./cmd/clavain-cli/ -run TestScenarioPolicyCheckAlias -v`
  expect: exit 0
- run: `cd os/Clavain && go build ./cmd/clavain-cli/`
  expect: exit 0
</verify>

---

## Task 3: Migration 032 — `authorizations` table

**Files:**
- Create: `core/intercore/internal/db/migrations/032_authorizations.sql`
- Modify: `core/intercore/internal/db/db_test.go` (add test for migration apply + schema shape)

**Step 1: Write migration**
`core/intercore/internal/db/migrations/032_authorizations.sql`:
```sql
CREATE TABLE IF NOT EXISTS authorizations (
  id               TEXT PRIMARY KEY,
  op_type          TEXT NOT NULL,
  target           TEXT NOT NULL,
  agent_id         TEXT NOT NULL CHECK(length(trim(agent_id)) > 0),
  bead_id          TEXT,
  mode             TEXT NOT NULL CHECK(mode IN ('auto','confirmed','blocked','force_auto')),
  policy_match     TEXT,
  policy_hash      TEXT,
  vetted_sha       TEXT,
  vetting          TEXT CHECK(vetting IS NULL OR json_valid(vetting)),
  cross_project_id TEXT,
  created_at       INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS authz_by_bead  ON authorizations(bead_id,  created_at DESC);
CREATE INDEX IF NOT EXISTS authz_by_op    ON authorizations(op_type,  created_at DESC);
CREATE INDEX IF NOT EXISTS authz_by_agent ON authorizations(agent_id, created_at DESC);
CREATE INDEX IF NOT EXISTS authz_by_xproj ON authorizations(cross_project_id) WHERE cross_project_id IS NOT NULL;
```

**Step 2: Write failing test** (add to existing migration test):
```go
func TestMigration032Authorizations(t *testing.T) {
    db := openMigratedTestDB(t)
    var count int
    err := db.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('authorizations')`).Scan(&count)
    require.NoError(t, err)
    require.Equal(t, 12, count, "authorizations should have 12 columns")
    // Reject garbage mode
    _, err = db.Exec(`INSERT INTO authorizations (id,op_type,target,agent_id,mode,created_at) VALUES ('x','bead-close','a','s','bogus',1)`)
    require.Error(t, err, "CHECK constraint on mode should reject 'bogus'")
    // Reject empty agent_id
    _, err = db.Exec(`INSERT INTO authorizations (id,op_type,target,agent_id,mode,created_at) VALUES ('y','bead-close','a','   ','auto',1)`)
    require.Error(t, err, "CHECK constraint should reject whitespace agent_id")
}
```

**Step 3: Run — expect FAIL** (migration file not present).

**Step 4: Add migration; re-run — expect PASS.**

**Step 5: Commit**
```bash
git add core/intercore/internal/db/migrations/032_authorizations.sql core/intercore/internal/db/db_test.go
git commit -m "feat(intercore): add authorizations table (migration 032, sylveste-qdqr)"
```

<verify>
- run: `cd core/intercore && go test ./internal/db/ -run TestMigration032Authorizations -v`
  expect: exit 0
</verify>

---

## Task 4: Policy engine package `core/intercore/internal/authz/`

**Files:**
- Create: `core/intercore/internal/authz/policy.go` (types, loader)
- Create: `core/intercore/internal/authz/merge.go` (merge algorithm from `docs/canon/policy-merge.md`)
- Create: `core/intercore/internal/authz/evaluator.go` (condition evaluator)
- Create: `core/intercore/internal/authz/record.go` (audit writer)
- Create: `core/intercore/internal/authz/policy_test.go`
- Create: `core/intercore/internal/authz/merge_test.go`
- Create: `core/intercore/internal/authz/evaluator_test.go`

**Step 1: Define types** (`policy.go`):
```go
package authz

type Policy struct {
    Version int    `yaml:"version"`
    Rules   []Rule `yaml:"rules"`
}

type Rule struct {
    Op             string                 `yaml:"op"`
    Mode           string                 `yaml:"mode"`
    Requires       map[string]interface{} `yaml:"requires,omitempty"`
    AllowOverride  bool                   `yaml:"allow_override,omitempty"`
}

type CheckResult struct {
    Mode        string  // auto | confirm | block | force_auto
    PolicyMatch string
    PolicyHash  string  // hash of merged effective policy at check time
    Reason      string
}

func LoadEffective(globalPath, projectPath, envPath string) (*Policy, string, error)
// returns merged policy + sha256 of canonical serialization
```

**Step 2: Write merge tests first** (mirror the 5 examples from `docs/canon/policy-merge.md`):
```go
func TestMerge_NumericMin(t *testing.T) { /* vetted_within_minutes: 60 + 30 → 30 */ }
func TestMerge_BooleanAND(t *testing.T) { /* tests_passed: true + (project drops w/o allow_override) → reject */ }
func TestMerge_CatchallFloor(t *testing.T) { /* global "*" confirm + project "*" auto → reject */ }
func TestMerge_ForceAutoPropagates(t *testing.T) { /* mode becomes force_auto, separate audit class */ }
func TestMerge_FirstMatchWins(t *testing.T) { /* two specific rules: earliest wins */ }
```
Run — all FAIL.

**Step 3: Implement `MergePolicies` in `merge.go`** matching the 5 test cases exactly. Re-run — all PASS.

**Step 4: Write evaluator tests** (`evaluator_test.go`):
```go
func TestEvaluate_VettedWithinMinutes_Fresh(t *testing.T) { /* vetted_at 10m ago, rule wants 60 → pass */ }
func TestEvaluate_VettedShaMismatch(t *testing.T) { /* vetted_sha != HEAD → fail (require confirm) */ }
func TestEvaluate_ClockSkewTolerance(t *testing.T) { /* vetted_at 61m ago, 5m tolerance → fail; 4m over → pass */ }
func TestEvaluate_MultiRepoShasAllMatch(t *testing.T) { /* vetting.shas={"a":"sha1","b":"sha2"}, both HEAD → pass */ }
```
Run — all FAIL.

**Step 5: Implement `Evaluate(rule, beadState, workdirs)` in `evaluator.go`.** Re-run — all PASS.

**Step 6: Write `Record` test + impl** (`record.go`):
```go
func TestRecord_InsertsRowWithPolicyHash(t *testing.T) { /* ... */ }
func TestRecord_CrossProjectIDPropagates(t *testing.T) { /* ... */ }
```
Implement `Record(db, RecordArgs) error` using the `authorizations` table.

**Step 7: Commit**
```bash
git add core/intercore/internal/authz/
git commit -m "feat(intercore/authz): policy engine (loader, merge, evaluator, record) (sylveste-qdqr)"
```

<verify>
- run: `cd core/intercore && go test ./internal/authz/ -v`
  expect: exit 0
- run: `cd core/intercore && go vet ./internal/authz/...`
  expect: exit 0
</verify>

---

## Task 5: `clavain-cli policy` subcommand group

**Files:**
- Create: `os/Clavain/cmd/clavain-cli/authz.go` (cmd handlers)
- Create: `os/Clavain/cmd/clavain-cli/authz_test.go`
- Modify: `os/Clavain/cmd/clavain-cli/main.go` (add cases for `policy check/record/explain/audit/list/lint`)

**Step 1: Write exit-code contract test first** (`authz_test.go`):
```go
func TestPolicyCheck_ExitCodes(t *testing.T) {
    // exit 0 when rule matches and requires satisfied
    // exit 1 when requires fail (confirm needed)
    // exit 2 when rule mode is explicitly 'block'
    // exit 3 when policy YAML is malformed
}
func TestPolicyCheck_JSONOutput_HasSchema(t *testing.T) {
    // stdout JSON has {"policy_match":"...","reason":"...","policy_hash":"...","schema":1}
}
func TestPolicyRecord_WritesRow(t *testing.T) { /* ... */ }
func TestPolicyLint_RejectsMissingCatchall(t *testing.T) { /* ... */ }
func TestPolicyLint_RejectsProjectLoosenWithoutAllowOverride(t *testing.T) { /* ... */ }
```

**Step 2: Run — expect FAIL.**

**Step 3: Implement `authz.go` handlers:**
```go
func cmdPolicyCheck(args []string) error  // exit 0/1/2/3, stdout JSON
func cmdPolicyRecord(args []string) error // writes to .clavain/intercore.db
func cmdPolicyExplain(args []string) error // human-readable
func cmdPolicyAudit(args []string) error   // --since, --op, --agent, --verify
func cmdPolicyList(args []string) error    // effective merged policy
func cmdPolicyLint(args []string) error    // invariants checker
```
Register in `main.go`:
```go
case "policy":
    if len(args) < 1 { err = fmt.Errorf("policy subcommand required"); break }
    sub, rest := args[0], args[1:]
    switch sub {
    case "check":   err = cmdPolicyCheck(rest)
    case "record":  err = cmdPolicyRecord(rest)
    case "explain": err = cmdPolicyExplain(rest)
    case "audit":   err = cmdPolicyAudit(rest)
    case "list":    err = cmdPolicyList(rest)
    case "lint":    err = cmdPolicyLint(rest)
    default: err = fmt.Errorf("unknown policy subcommand: %s", sub)
    }
```

**Step 4: Run tests — expect PASS.**

**Step 5: Create `~/.clavain/policy.yaml.example`** (committed template):
```yaml
version: 1
rules:
  - op: bead-close
    mode: auto
    requires:
      vetted_within_minutes: 60
      tests_passed: true
      sprint_or_work_flow: true
      vetted_sha_matches_head: true
  - op: git-push-main
    mode: auto
    requires:
      committed_by_this_session: true
  - op: ic-publish-patch
    mode: auto
    requires:
      vetted_within_minutes: 60
      tests_passed: true
      vetted_sha_matches_head: true
  - op: bd-push-dolt
    mode: auto
    requires:
      sprint_or_work_flow: true
  - op: "*"
    mode: confirm
```

**Step 6: Commit**
```bash
git add os/Clavain/cmd/clavain-cli/authz.go os/Clavain/cmd/clavain-cli/authz_test.go os/Clavain/cmd/clavain-cli/main.go os/Clavain/config/policy.yaml.example
git commit -m "feat(clavain-cli): policy subcommand group (check/record/explain/audit/list/lint) (sylveste-qdqr)"
```

<verify>
- run: `cd os/Clavain && go test ./cmd/clavain-cli/ -run 'TestPolicy' -v`
  expect: exit 0
- run: `cd os/Clavain && go build ./cmd/clavain-cli/ && ./clavain-cli policy list --help 2>&1 | head -3`
  expect: contains "policy"
</verify>

---

## Task 6: Gate wrappers + `.clavain/gates/` registry

**Files:**
- Create: `os/Clavain/scripts/gates/bead-close.sh`
- Create: `os/Clavain/scripts/gates/git-push-main.sh`
- Create: `os/Clavain/scripts/gates/bd-push-dolt.sh`
- Create: `os/Clavain/scripts/gates/ic-publish-patch.sh`
- Create: `os/Clavain/scripts/gates/README.md` (install instructions)
- Create: `.clavain/gates/bead-close.gate` (and one per wrapper; one-line registration)
- Modify: `.beads/push.sh` (wrap at top with policy check)
- Modify: `os/Clavain/cmd/clavain-cli/authz.go` — extend `policy lint` to verify `.clavain/gates/*.gate` entries have matching rules

**Step 1: Write wrapper template** (`os/Clavain/scripts/gates/bead-close.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

BEAD_ID="${1:?usage: bead-close.sh <bead-id> [reason]}"
REASON="${2:-}"

check_output=$(clavain-cli policy check bead-close --target="$BEAD_ID" --bead="$BEAD_ID")
rc=$?
policy_hash=$(echo "$check_output" | jq -r '.policy_hash // empty')
policy_match=$(echo "$check_output" | jq -r '.policy_match // empty')

case $rc in
  0) mode=auto ;;
  1) if [[ -t 0 ]]; then
       read -rp "policy: bead-close requires confirmation. Proceed? [y/N] " ans
       [[ "$ans" =~ ^[yY]$ ]] || { echo "aborted"; exit 1; }
       mode=confirmed
     else
       echo "policy: bead-close requires confirmation; no tty" >&2
       exit 1
     fi ;;
  2) echo "policy: bead-close blocked" >&2; exit 1 ;;
  *) echo "policy: engine error (rc=$rc)" >&2; exit 1 ;;
esac

bd close "$BEAD_ID" ${REASON:+--reason="$REASON"}

clavain-cli policy record \
  --op=bead-close \
  --target="$BEAD_ID" \
  --bead="$BEAD_ID" \
  --mode="$mode" \
  --policy-match="$policy_match" \
  --policy-hash="$policy_hash"
```
Same shape for the other three wrappers, substituting op name and underlying command.

**Step 2: Write registry marker files**
`.clavain/gates/bead-close.gate`:
```
op=bead-close
script=os/Clavain/scripts/gates/bead-close.sh
registered_at=2026-04-19
```
(And one per wrapper.)

**Step 3: Modify `.beads/push.sh`** — add at top:
```bash
if command -v clavain-cli >/dev/null 2>&1; then
  bash "$(dirname "$0")/../os/Clavain/scripts/gates/bd-push-dolt.sh" "$@" || exit $?
  exit 0
fi
# fallthrough to existing logic if clavain-cli not installed
```

**Step 4: Extend `policy lint`** (in `authz.go`) to walk `.clavain/gates/*.gate` and assert every declared op has a rule in the merged policy. Add test:
```go
func TestPolicyLint_FlagsUnregisteredGate(t *testing.T) {
    // Create a .gate file for op 'widget-delete' with no rule in policy → lint fails
}
```

**Step 5: Write integration test**
`os/Clavain/cmd/clavain-cli/gates_integration_test.go`:
```go
func TestBeadCloseWrapper_AutoProceed_VettedBead(t *testing.T) {
    // Set up fake bd + policy + vetted bead state → wrapper exits 0 silently
}
func TestBeadCloseWrapper_ConfirmRequired_StaleVetting(t *testing.T) {
    // vetted_at 61m ago → wrapper exits 1 in non-tty
}
```

**Step 6: Run — implement — pass.**

**Step 7: Commit**
```bash
git add os/Clavain/scripts/gates/ .clavain/gates/ .beads/push.sh os/Clavain/cmd/clavain-cli/authz.go os/Clavain/cmd/clavain-cli/gates_integration_test.go
git commit -m "feat(authz): gate wrappers for bead-close, git-push-main, bd-push-dolt, ic-publish-patch (sylveste-qdqr)

Each wrapper: policy check → op → policy record (policy_hash pinned).
Registry at .clavain/gates/; policy lint asserts coverage."
```

<verify>
- run: `cd os/Clavain && go test ./cmd/clavain-cli/ -run 'Gate' -v`
  expect: exit 0
- run: `bash os/Clavain/scripts/gates/bead-close.sh --help 2>&1 || true; ls .clavain/gates/*.gate | wc -l`
  expect: contains "4"
</verify>

---

## Task 7: Vetting-signal writes in `/clavain:work` + `/clavain:sprint`

**Files:**
- Modify: `os/Clavain/commands/work.md` Phase 3 (non-sprint path)
- Modify: `os/Clavain/commands/sprint.md` Steps 6-7
- Modify: `os/Clavain/skills/executing-plans/SKILL.md` (post-task hook: write `vetted_at` on pass)

**Step 1: Identify insertion points.** In `work.md` Phase 3 quality check — after tests pass, BEFORE returning. In `sprint.md` Step 6 (test) and Step 7 (quality gates) — after pass.

**Step 2: Add vetting writes — `work.md` Phase 3:**
```markdown
**After tests pass**, before dispatch to Phase 4:
```bash
if [[ -n "${CLAVAIN_BEAD_ID:-}" ]]; then
  bd set-state "$CLAVAIN_BEAD_ID" vetted_at="$(date +%s)"
  bd set-state "$CLAVAIN_BEAD_ID" tests_passed=true
  bd set-state "$CLAVAIN_BEAD_ID" vetted_with="$TEST_SUMMARY"
  bd set-state "$CLAVAIN_BEAD_ID" vetted_sha="$(git rev-parse HEAD)"
  bd set-state "$CLAVAIN_BEAD_ID" sprint_or_work_flow=true
fi
```
```

**Step 3: Same insertion in `sprint.md` Step 6 (after test-run success) and Step 7 (after quality gates pass).**

**Step 4: Write regression test** — shell script in `os/Clavain/tests/vetting-writes_test.sh`:
```bash
#!/usr/bin/env bash
# Simulate: /work Phase 3 run on a test bead → bd state has vetted_at, vetted_sha, tests_passed
# Then: policy check bead-close → exit 0
set -euo pipefail
export CLAVAIN_BEAD_ID=test-$$
bd create --title="test" --type=task --id-override="$CLAVAIN_BEAD_ID"
# ... simulate vetting writes ...
out=$(clavain-cli policy check bead-close --target="$CLAVAIN_BEAD_ID" --bead="$CLAVAIN_BEAD_ID"; echo "RC:$?")
echo "$out" | grep -q 'RC:0' || { echo "FAIL: expected exit 0"; exit 1; }
bd close "$CLAVAIN_BEAD_ID" --reason=test
```

**Step 5: Commit**
```bash
git add os/Clavain/commands/work.md os/Clavain/commands/sprint.md os/Clavain/skills/executing-plans/SKILL.md os/Clavain/tests/vetting-writes_test.sh
git commit -m "feat(clavain): write vetting signals from /work and /sprint (sylveste-qdqr)

bd set-state writes vetted_at, vetted_sha, tests_passed, sprint_or_work_flow
so policy gate can evaluate requires conditions at op time."
```

<verify>
- run: `bash os/Clavain/tests/vetting-writes_test.sh`
  expect: exit 0
- run: `grep -c 'vetted_at' os/Clavain/commands/work.md os/Clavain/commands/sprint.md`
  expect: contains ":2" or higher (each file has at least one occurrence)
</verify>

---

## Task 8: End-to-end integration test + example global policy

**Files:**
- Create: `os/Clavain/tests/authz-e2e_test.sh`
- Create: `~/.clavain/policy.yaml` (from example, documented step — NOT committed since it's user-local)
- Modify: `os/Clavain/README.md` (add authz quickstart section)

**Step 1: E2E test script:**
```bash
#!/usr/bin/env bash
# Setup: fake bead, fake commit, vetted state
# Action: call bead-close wrapper
# Assert: auto-proceeds (exit 0), authorizations row exists, mode=auto, policy_hash present
set -euo pipefail
# ... setup ...
bash os/Clavain/scripts/gates/bead-close.sh "$BEAD" test
row=$(sqlite3 .clavain/intercore.db "SELECT mode,policy_match,policy_hash FROM authorizations WHERE bead_id='$BEAD'")
[[ "$row" == "auto|bead-close|"* ]] || { echo "FAIL: $row"; exit 1; }
echo "PASS"
```

**Step 2: Add quickstart to README.md** — 20 lines covering: install example policy, run /sprint, inspect audit.

**Step 3: Run full test matrix:**
```bash
cd core/intercore && go test ./internal/authz/ ./internal/db/ -v
cd os/Clavain && go test ./cmd/clavain-cli/ -v
bash os/Clavain/tests/authz-e2e_test.sh
bash os/Clavain/tests/vetting-writes_test.sh
```

**Step 4: Commit**
```bash
git add os/Clavain/tests/authz-e2e_test.sh os/Clavain/README.md
git commit -m "test(authz): e2e wrapper integration + README quickstart (sylveste-qdqr)"
```

<verify>
- run: `bash os/Clavain/tests/authz-e2e_test.sh`
  expect: contains "PASS"
- run: `cd core/intercore && go test ./internal/authz/... && cd ../../os/Clavain && go test ./cmd/clavain-cli/...`
  expect: exit 0
</verify>

---

## Deferred to follow-up plans

- **v1.5 signing + `.publish-approved` unify** → `docs/plans/TBD-auto-proceed-authz-v1.5.md` (separation-of-duties writer/signer, Ed25519, sig_version, `RequiresApproval()` hook modification). Est. 1.5 days.
- **v2 tokens + delegation** → `docs/plans/TBD-auto-proceed-authz-v2.md` (`authz_tokens` table, atomic consume with expiry, proof-of-possession on delegate, `root_token`+`depth` cascade revoke, CLI surface). Est. 1 week.

Both plans reference this v1 plan as prerequisite and read the same canon docs (`docs/canon/policy-merge.md`, `docs/canon/authz-cross-project-consistency.md`) as spec ground truth.

---

## Notes on discipline

- **Don't bridge `.publish-approved` in v1.** Additive guard only. The shim path was tempting but creates two write paths that can diverge. Wait for v1.5 when `RequiresApproval()` is modified directly.
- **Don't implement v1.5 signing fields in v1 schema** — `sig_version`, `signature` columns belong in a v1.5 migration (033). Keeping them out of 032 means v1 ships without signing infrastructure scaffolding.
- **Gate wrapper TOCTOU** — `policy_hash` pin from check to record is the v1 mitigation. If policy yaml changes mid-op, the record captures the hash the decision was made against. Audit can detect divergence.
- **Cross-project ops** — v1 only ships `bead-close`, `git-push-main`, `bd-push-dolt`, `ic-publish-patch`. Only `ic-publish-patch` is nominally cross-project (plugin spans repos sometimes); start with best-effort and harden in v1.5 alongside unify.
