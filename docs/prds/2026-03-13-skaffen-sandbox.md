---
artifact_type: prd
bead: Sylveste-6i0.10
stage: design
---

# PRD: Skaffen Sandbox / Tool Isolation

## Problem

Skaffen executes LLM-generated tool calls (bash commands, file operations) and MCP plugin subprocesses with no OS-level restrictions. A malicious model output or buggy plugin can read sensitive files (~/.ssh, ~/.aws), exfiltrate data via network, or damage the filesystem. The existing trust system (Allow/Prompt/Block) is a policy layer — it asks permission but doesn't enforce boundaries at the OS level.

## Solution

Cross-platform OS-level sandboxing with a unified `SandboxPolicy` abstraction. Linux uses bubblewrap (bwrap) for subprocess isolation; macOS uses Seatbelt (sandbox-exec). In-process tools (read/write/edit/grep/glob/ls) get Go-level path validation. Default-on with a `--yolo` escape hatch.

## Features

### F1: SandboxPolicy types and config loading

**What:** Define the `SandboxPolicy` struct and load it from `~/.skaffen/sandbox.json` (global) and `.skaffen/sandbox.json` (per-project, higher precedence). Includes variable expansion ($WORKDIR, ~) and policy merging.

**Acceptance criteria:**
- [ ] `SandboxPolicy` struct with WriteDirs, ReadDirs, DenyDirs, AllowNet, DenyNet fields
- [ ] `sandbox.Load(workDir)` loads and merges global + project policies
- [ ] Default policy applied when no config files exist (project-scoped: workdir writable, sensitive dirs denied, network blocked)
- [ ] Variable expansion: `$WORKDIR` → actual workdir, `~` → home dir
- [ ] Three modes: default, strict, disabled (yolo)
- [ ] `CheckPath(path, write) error` validates a path against the policy
- [ ] Unit tests for policy loading, merging, path validation, and variable expansion

### F2: In-process tool path validation

**What:** Inject sandbox path checks into the tool registry so in-process tools (read, write, edit, grep, glob, ls) are validated against the SandboxPolicy before execution. Cross-platform (pure Go).

**Acceptance criteria:**
- [ ] Registry.Execute() calls sandbox.CheckPath() before delegating to tool
- [ ] Read tools check read access; write/edit tools check write access
- [ ] Denied paths return a clear error message ("sandbox: access denied: /path")
- [ ] Glob/grep results are filtered to exclude denied paths
- [ ] Yolo mode bypasses all checks
- [ ] Unit tests with mocked sandbox policy

### F3: bwrap backend (Linux)

**What:** Wrap subprocess commands (bash, MCP) in bubblewrap on Linux. Translates SandboxPolicy into bwrap arguments (--ro-bind, --bind, --unshare-net, --die-with-parent).

**Acceptance criteria:**
- [ ] `sandbox.WrapCommand(cmd) *exec.Cmd` returns a bwrap-wrapped command on Linux
- [ ] ReadDirs → `--ro-bind`, WriteDirs → `--bind`, DenyDirs excluded from mounts
- [ ] `--unshare-net` when DenyNet is true
- [ ] `--die-with-parent` to prevent orphan processes
- [ ] Auto-detect bwrap binary; fall back to unsandboxed + stderr warning if missing
- [ ] Integration test that verifies bwrap blocks access to a denied path (skip on non-Linux CI)

### F4: Seatbelt backend (macOS)

**What:** Generate a Seatbelt `.sb` profile from SandboxPolicy and wrap subprocess commands in `sandbox-exec` on macOS.

**Acceptance criteria:**
- [ ] `sandbox.WrapCommand(cmd) *exec.Cmd` returns a sandbox-exec-wrapped command on macOS
- [ ] Generated .sb profile: `(deny default)` base, `(allow file-read*)` for ReadDirs, `(allow file-write*)` for WriteDirs, explicit deny for DenyDirs
- [ ] Network: `(deny network*)` when DenyNet, selective `(allow network-outbound)` for AllowNet domains
- [ ] Profile written to temp file, cleaned up after command completes
- [ ] Auto-detect sandbox-exec (should always exist on macOS); skip if missing
- [ ] Integration test that verifies sandbox-exec blocks access to a denied path (skip on non-macOS CI)

### F5: Bash tool sandbox integration

**What:** Wire the sandbox into `tool/bash.go` so every bash command runs inside bwrap/sandbox-exec.

**Acceptance criteria:**
- [ ] `bash.Execute()` calls `sandbox.WrapCommand()` before spawning the subprocess
- [ ] Sandbox errors are returned as tool errors (not panics)
- [ ] When sandbox is disabled (yolo), bash runs directly as before
- [ ] Timeout still works correctly through the sandbox wrapper
- [ ] Existing bash tests pass with sandbox disabled

### F6: MCP subprocess sandboxing

**What:** Apply sandbox policy when spawning MCP server subprocesses. Each plugin gets a policy derived from the project policy intersected with plugin-declared permissions.

**Acceptance criteria:**
- [ ] `mcp.Manager.startServer()` wraps the subprocess command with sandbox.WrapCommand()
- [ ] Plugin policy is intersection of project policy and plugin manifest (plugin can't escalate)
- [ ] Plugins that need network access declare it in plugins.toml; denied if project policy blocks
- [ ] Existing MCP tests pass with sandbox disabled

### F7: CLI flags and mode selection

**What:** Add `--dangerously-disable-sandbox` / `--yolo` and `--sandbox=strict` CLI flags to main.go. Wire mode into sandbox initialization.

**Acceptance criteria:**
- [ ] `--dangerously-disable-sandbox` and `--yolo` both disable all sandbox enforcement
- [ ] `--sandbox=strict` applies minimal policy (only workdir, no network)
- [ ] Default (no flag) applies project-scoped policy
- [ ] Sandbox mode displayed in TUI status bar (icon or text indicator)
- [ ] Warning printed to stderr when yolo mode is active

## Non-goals

- **Windows support** — no bwrap equivalent; deferred to future iteration
- **Seccomp syscall filtering** — can be layered on later without architecture changes
- **Landlock self-sandboxing** — future hardening layer for Linux; doesn't change the bwrap architecture
- **Domain-level network filtering** — bwrap does all-or-nothing; domain filtering would need a proxy. All-or-nothing is sufficient for v1
- **Sandbox escape detection** — monitoring/alerting for sandbox bypass attempts

## Dependencies

- **bubblewrap (bwrap)** — Linux only. Packaged in apt, dnf, pacman. Graceful degradation if missing.
- **sandbox-exec** — macOS only. Ships with the OS (part of the Seatbelt framework).
- No new Go dependencies required (os/exec, path/filepath are stdlib).

## Open Questions

- **Seatbelt profile testing:** macOS profiles are finicky. Need to test with git, npm, python, cargo to find what breaks. May need a compatibility allowlist.
- **bwrap fallback UX:** When bwrap is missing, should we show a one-time install hint (`apt install bubblewrap`)?
- **MCP plugin manifest format:** How do plugins declare required filesystem/network access? Extend plugins.toml or separate sandbox section?
