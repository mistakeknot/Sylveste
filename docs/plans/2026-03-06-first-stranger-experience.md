---
artifact_type: plan
bead: iv-t712t
stage: build
---

# Plan: First-Stranger Experience

**Bead:** iv-t712t
**PRD:** docs/prds/2026-03-06-first-stranger-experience.md
**Date:** 2026-03-06

## Batch 1: README (F1 + F2)

These are pure documentation changes to `README.md`. No code changes, no test requirements.

### Task 1.1: Add prerequisites section to README.md

**File:** `README.md`
**Insert after:** The quick-start curl command block
**Content:**

```markdown
### Prerequisites

**Required:**
- [jq](https://jqlang.github.io/jq/) — JSON processor
- [Go 1.22+](https://go.dev/dl/) (1.24+ for Intermute/Autarch)
- git

**Recommended (full platform):**
- Python 3.10+ with PyYAML (`pip install pyyaml`)
- [Node.js 20+](https://nodejs.org/) (for JS-based MCP plugins)
- [yq v4](https://github.com/mikefarah/yq) (for fleet registry queries)

Install takes ~2 minutes (power user) or ~30 minutes (full platform).
Disk: ~2 GB core, ~5 GB with all plugins and node_modules.
```

**Verification:** Read README.md after edit, confirm section is between curl command and guide links.

### Task 1.2: Add troubleshooting section to README.md

**File:** `README.md`
**Insert:** New section before the license/footer

```markdown
## Troubleshooting

| Problem | Symptom | Fix |
|---------|---------|-----|
| jq missing | `install.sh` exits immediately | `sudo apt install jq` or `brew install jq` |
| Go too old | Version check fails during install | Install Go 1.22+ from [go.dev](https://go.dev/dl/) |
| `ic` not found | Commands fail after successful install | Add `export PATH="$HOME/.local/bin:$PATH"` to your shell profile |
| ic build fails | Install exits with Go compilation error | Ensure `go env GOPATH` is set and you have network access |
| Plugins missing | `/clavain:setup` shows gaps | Re-run `install.sh` with Claude Code running |
| `bd` hangs | Beads commands never return | Run `bash .beads/recover.sh` |

Run `/clavain:doctor` for a full health check.
```

**Verification:** Read README.md after edit.

## Batch 2: Enhanced Doctor (F3)

### Task 2.1: Add soft dependency checks to doctor.md

**File:** `os/clavain/commands/doctor.md`
**Section:** Add new check category "Soft Dependencies" after the existing "External Tools" section

New checks to add (each with PASS/WARN format):

1. **Python 3 + PyYAML**: `python3 -c "import yaml" 2>/dev/null` — WARN if fails ("spec loader will use hardcoded defaults")
2. **yq v4**: `command -v yq && yq --version 2>/dev/null | grep -q 'v4'` — WARN if fails ("fleet registry queries unavailable")
3. **Node.js 20+**: `command -v node` — WARN if fails ("JS-based MCP plugins won't start")
4. **PATH includes ~/.local/bin**: `echo "$PATH" | grep -q "${HOME}/.local/bin"` — WARN if fails and ic was built there ("ic kernel not on PATH")

**Important:** These are all WARN, not FAIL. They're optional deps.

### Task 2.2: Add config validation checks to doctor.md

**File:** `os/clavain/commands/doctor.md`
**Section:** Add "Config Validation" check category

1. **agency-spec.yaml parseable**: Try `python3 -c "import yaml; yaml.safe_load(open('os/clavain/config/agency-spec.yaml'))"` or `yq '.' os/clavain/config/agency-spec.yaml > /dev/null 2>&1` — FAIL if neither works and file exists
2. **fleet-registry.yaml parseable**: Same approach — FAIL if broken
3. **routing.yaml parseable**: Same approach — FAIL if broken

### Task 2.3: Add Dolt timeout check to doctor.md

**File:** `os/clavain/commands/doctor.md`
**Section:** Modify existing "Beads Tracking" check

Change the `bd stats` check to use a 5-second timeout:
```bash
timeout 5 bd stats 2>/dev/null
```
If timeout: FAIL with "Dolt server hung — run `bash .beads/recover.sh`"

### Task 2.4: Add hook syntax check to doctor.md

**File:** `os/clavain/commands/doctor.md`
**Section:** Add to "Companion Plugins" check

For each installed plugin with hooks:
```bash
for hook in ~/.claude/plugins/cache/*/*/hooks/*.sh; do
    bash -n "$hook" 2>/dev/null || echo "WARN: syntax error in $hook"
done
```

This is fast (<100ms for all hooks) and catches broken shell syntax.

**Verification for all Batch 2:** Run `/clavain:doctor` after changes and verify new checks appear.

## Batch 3: First-Run Verification (F4)

### Task 3.1: Add first-run health check to session-start hook

**File:** `os/clavain/hooks/session-start.sh` (or wherever session-start hooks are registered)
**Logic:**

```bash
if [[ ! -f ".clavain/setup-verified" ]]; then
    _health_ok=true

    # Critical: ic on PATH
    if ! command -v ic >/dev/null 2>&1; then
        echo "Warning: ic kernel not found on PATH. Run install.sh or add ~/.local/bin to PATH." >&2
        _health_ok=false
    fi

    # Critical: bd available
    if ! command -v bd >/dev/null 2>&1; then
        echo "Warning: bd (beads) not found. Install: go install github.com/mistakeknot/beads/cmd/bd@latest" >&2
        _health_ok=false
    fi

    # Soft: Python
    if ! python3 -c "import yaml" 2>/dev/null; then
        echo "Note: PyYAML not available — some features will use defaults." >&2
    fi

    # Soft: yq
    if ! command -v yq >/dev/null 2>&1; then
        echo "Note: yq not found — fleet registry queries unavailable." >&2
    fi

    if [[ "$_health_ok" == "true" ]]; then
        mkdir -p .clavain
        touch .clavain/setup-verified
    fi
fi
```

**Performance requirement:** Must complete in <200ms. All checks use `command -v` (fast) or single python import (fast).

**Verification:** Delete `.clavain/setup-verified`, start a new session, verify warnings appear. Then verify marker file exists on next session start.

## Execution Order

1. Batch 1 (README) — no dependencies, pure docs
2. Batch 2 (Doctor) — independent of Batch 1
3. Batch 3 (First-run) — can reference doctor for "run /clavain:doctor for details"

Batches 1 and 2 can execute in parallel.

## Test Plan

- [ ] Read README.md — prerequisites and troubleshooting sections present and accurate
- [ ] Run `/clavain:doctor` — new checks appear (soft deps, config validation, Dolt timeout, hook syntax)
- [ ] Delete `.clavain/setup-verified` — first-run check triggers on next session-start
- [ ] Verify all check messages include actionable fix instructions
