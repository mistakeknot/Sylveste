---
artifact_type: prd
bead: iv-t712t
stage: design
---

# PRD: First-Stranger Experience

**Bead:** iv-t712t
**Priority:** P0
**Date:** 2026-03-06

## Problem

No external user has ever successfully set up Demarch. The installation infrastructure exists and is more complete than expected (install.sh has PATH validation, progress output, prerequisite checks), but a stranger hitting any deviation from the happy path has no recovery guidance. The README lists no prerequisites. The doctor command doesn't check soft dependencies (Python, yq, Node.js) or validate config files. There is no first-run verification on session-start.

## Scope

Three deliverables matching the epic description:

1. **README prerequisites and troubleshooting** — so a stranger knows what to install before running the curl command
2. **Enhanced doctor checks** — so a stranger can diagnose silent failures after install
3. **First-run session-start verification** — so a stranger's first Claude Code session surfaces problems immediately

### Out of scope (deferred)

- Pre-built ic binaries (CI complexity not justified yet)
- Interactive install wizard (current imperative flow works)
- Offline mode
- install.sh progress bar (already has step-by-step output)
- Plugin description output during install (nice-to-have, not blocking)

## Features

### F1: README Prerequisites Section

Add to README.md between the quick-start curl command and the guide links:

**Required:**
- jq
- Go 1.22+ (1.24+ for full platform)
- git

**Recommended (for full platform):**
- Python 3.10+ with PyYAML
- Node.js 20+
- yq v4

**Also add:**
- Install time estimate (~2 min power user, ~30 min full platform)
- Link to troubleshooting section
- Disk space note (~2GB for core, ~5GB with all plugins + node_modules)

### F2: README Troubleshooting Section

New section at bottom of README.md covering the top failure modes from the taxonomy:

| Problem | Symptom | Fix |
|---------|---------|-----|
| jq missing | install.sh exits immediately | `sudo apt install jq` / `brew install jq` |
| Go missing or old | install.sh exits with version error | Install Go 1.22+ from go.dev |
| ~/.local/bin not on PATH | `ic` not found after install | Add to shell profile |
| ic build fails | install.sh exits with Go error | Check `go env GOPATH`, ensure network |
| Plugins not installed | `/clavain:setup` shows missing | Re-run `install.sh` with Claude Code open |
| Dolt hangs | `bd` commands never return | `bash .beads/recover.sh` |

Plus: "Run `/clavain:doctor` to check your setup health."

### F3: Enhanced Doctor Checks

Add these checks to `os/clavain/commands/doctor.md`:

1. **Python 3 + PyYAML** — `python3 -c "import yaml"` (needed for spec loader)
2. **yq v4** — `command -v yq && yq --version` (needed for fleet registry)
3. **Node.js 20+** — `command -v node && node --version` (needed for JS MCP servers)
4. **~/.local/bin on PATH** — `echo "$PATH" | grep -q "$HOME/.local/bin"` (needed for ic)
5. **agency-spec.yaml valid** — `python3 -c "import yaml; yaml.safe_load(open('...'))"` or `yq '.' ... > /dev/null`
6. **fleet-registry.yaml valid** — same approach
7. **routing.yaml valid** — same approach
8. **Dolt responsive** — `bd stats` with 5-second timeout (not hang forever)
9. **Plugin hook syntax** — `bash -n` on each `*.sh` in plugin hooks dirs

Each check: PASS/WARN/FAIL with one-line fix recommendation.

### F4: First-Run Session-Start Verification

Add to session-start hook chain: if `.clavain/setup-verified` doesn't exist, run a quick subset of doctor (PATH, ic, bd, Python, yq — ~200ms). If any critical check fails, inject a one-line warning. If all pass, create `.clavain/setup-verified` marker file.

**Critical checks (block warning):** ic on PATH, bd available
**Soft checks (warn only):** Python, yq, Node.js

This is the lightest-touch feature — just surfaces problems, doesn't fix them.

## Acceptance Criteria

- [ ] README.md has prerequisites section with required/recommended tools and versions
- [ ] README.md has troubleshooting section covering top 6 failure modes
- [ ] `/clavain:doctor` checks Python, yq, Node.js, PATH, YAML validity, Dolt timeout, hook syntax
- [ ] Session-start runs quick health check on first run, creates marker file after pass
- [ ] All changes committed and pushed

## Dependencies

- iv-t712t.3 (taxonomy research) — CLOSED, feeds this work
- doctor.md — will be modified
- README.md — will be modified
- Session-start hooks — will be modified

## Risks

- **Doctor scope creep:** Keep checks fast (<5s total). Don't turn doctor into a test suite.
- **Session-start latency:** First-run check must be <200ms. Use marker file to skip on subsequent sessions.
- **False positives:** Python/yq/Node are truly optional for some workflows. Use WARN not FAIL for these.
