# CUJ: Running an Autoresearch Campaign

**Bead:** projects-z6k
**Date:** 2026-03-15
**Persona:** Skaffen developer (agent or human) optimizing a subsystem

## Flow

### 1. Campaign Setup
**Actor:** User or Clavain skill
**Action:** Create campaign YAML defining metric, benchmark command, and initial ideas.
**Success signal (observable):** Campaign YAML exists at `~/.skaffen/campaigns/{name}.yaml` and passes schema validation.

### 2. Start Campaign
**Actor:** Agent (via `/autoresearch {campaign-name}`)
**Action:** Skill reads YAML, creates git worktree, generates `autoresearch.md` living document and `autoresearch.ideas.md`, calls `init_experiment` for first idea.
**Success signal (observable):** Git worktree exists at `/tmp/autoresearch-{name}`, living document contains campaign metadata and first hypothesis.

### 3. Experiment Loop (repeat)
**Actor:** Agent
**Action:** Make code changes → `run_experiment` (executes benchmark, extracts metrics) → compare to baseline → `log_experiment` with keep/discard decision.
**Success signal (measurable):** JSONL log contains experiment record with `status: completed`, metric values, and decision. On keep: git commit in worktree. On discard: working tree matches last commit.

### 4. Context Recovery
**Actor:** System (auto-resume hook)
**Trigger:** Context window > 80% OR session end.
**Action:** Checkpoint written, session ends. New session starts, reads `autoresearch.md`, resumes from last experiment.
**Success signal (observable):** New session's first action references the living document and continues from the correct experiment number.

### 5. Campaign Completion
**Actor:** Agent
**Action:** Ideas exhausted or budget reached. Summary written to JSONL. User prompted to merge worktree branch.
**Success signal (measurable):** JSONL contains `summary` record with total experiments, kept count, cumulative improvement. Worktree cleaned up after merge/discard.

### 6. TUI Monitoring
**Actor:** User watching Skaffen TUI
**Action:** Observe status bar showing `[exp: N/M +X%]` updating in real-time.
**Success signal (qualitative):** User can see at a glance how many experiments have run, how many are planned, and the cumulative improvement.

## Edge Cases

- **All experiments fail:** After `max_consecutive_failures`, campaign stops with summary showing 0 improvements. No changes merged.
- **Benchmark times out:** `run_experiment` returns error, experiment logged as `status: timeout`, counted toward failure cap.
- **Secondary metric regresses:** Experiment logged as `status: rejected_secondary`, decision forced to `discard` with reason noting which secondary metric regressed.
- **Worktree already exists:** Detect and resume from existing worktree rather than creating a new one.
