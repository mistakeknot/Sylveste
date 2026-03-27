---
artifact_type: plan
bead: Sylveste-6i0.10
stage: design
requirements:
  - F1: SandboxPolicy types and config loading
  - F2: In-process tool path validation
  - F3: bwrap backend (Linux)
  - F4: Seatbelt backend (macOS)
  - F5: Bash tool sandbox integration
  - F6: MCP subprocess sandboxing
  - F7: CLI flags and sandbox mode selection
---
# Skaffen Sandbox Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-6i0.10
**Goal:** Add cross-platform OS-level sandboxing to Skaffen so LLM tool calls and MCP plugins are restricted to project-scoped filesystem/network access by default.

**Architecture:** New `internal/sandbox/` package defines `Policy` (rules) and `Sandbox` (enforcer). Two platform backends: bwrap (Linux) wraps subprocesses in mount/PID/network namespaces; Seatbelt (macOS) generates `.sb` profiles and wraps with `sandbox-exec`. In-process tools get Go-level path validation via `Sandbox.CheckPath()`. The `Sandbox` is injected into `tool.Registry`, `tool.BashTool`, and `mcp.Manager` at startup.

**Tech Stack:** Go stdlib only (os/exec, path/filepath, encoding/json, runtime). No new dependencies.

---

## Must-Haves

**Truths** (observable behaviors):
- Bash command `cat ~/.ssh/id_rsa` is blocked with a sandbox error in default mode
- In-process `read` tool cannot read `~/.ssh/id_rsa` in default mode
- MCP plugin subprocesses cannot access denied paths
- `--yolo` flag disables all sandbox enforcement
- `--sandbox=strict` restricts to workdir only
- Sandbox works on both Linux (bwrap) and macOS (Seatbelt)

**Artifacts** (files that must exist):
- `internal/sandbox/policy.go` exports `Policy`, `Mode`, `DefaultPolicy()`, `Load()`, `Merge()`
- `internal/sandbox/sandbox.go` exports `Sandbox`, `New()`, `CheckPath()`, `WrapCommand()`
- `internal/sandbox/bwrap.go` exports `bwrapWrap()` (Linux only via build tags)
- `internal/sandbox/seatbelt.go` exports `seatbeltWrap()` (macOS only via build tags)

**Key Links:**
- `cmd/skaffen/main.go` creates `Sandbox` and passes it to `Registry` and `BashTool`
- `Registry.Execute()` calls `Sandbox.CheckPath()` before delegating to in-process tools
- `BashTool.Execute()` calls `Sandbox.WrapCommand()` before spawning bash subprocess
- `mcp.NewClient()` receives sandbox for wrapping MCP server subprocess

---

### Task 1: Define Policy types and defaults

**Files:**
- Create: `os/Skaffen/internal/sandbox/policy.go`
- Test: `os/Skaffen/internal/sandbox/policy_test.go`

**Step 1: Write the failing test**

```go
package sandbox

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultPolicy(t *testing.T) {
	p := DefaultPolicy("/home/user/project")
	if len(p.WriteDirs) == 0 {
		t.Fatal("expected write dirs in default policy")
	}
	if !p.DenyNet {
		t.Fatal("expected network denied by default")
	}
	if len(p.DenyDirs) == 0 {
		t.Fatal("expected deny dirs in default policy")
	}
}

func TestExpandVars(t *testing.T) {
	home, _ := os.UserHomeDir()
	got := expandVars("~/.ssh", "/work")
	want := filepath.Join(home, ".ssh")
	if got != want {
		t.Fatalf("expandVars(~/.ssh) = %q, want %q", got, want)
	}
	got = expandVars("$WORKDIR/src", "/work")
	if got != "/work/src" {
		t.Fatalf("expandVars($WORKDIR/src) = %q, want /work/src", got)
	}
}

func TestStrictPolicy(t *testing.T) {
	p := StrictPolicy("/work")
	if len(p.ReadDirs) != 1 || p.ReadDirs[0] != "/work" {
		t.Fatalf("strict policy should only allow workdir, got ReadDirs=%v", p.ReadDirs)
	}
	if !p.DenyNet {
		t.Fatal("strict should deny network")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1 -run TestDefault`
Expected: FAIL — package doesn't exist yet

**Step 3: Write minimal implementation**

```go
package sandbox

import (
	"os"
	"path/filepath"
	"strings"
)

// Mode controls the sandbox enforcement level.
type Mode int

const (
	ModeDefault  Mode = iota // project-scoped policy
	ModeStrict               // minimal: workdir only
	ModeDisabled             // --yolo: no enforcement
)

// Policy defines filesystem and network access rules.
type Policy struct {
	WriteDirs []string `json:"write"`   // read-write access
	ReadDirs  []string `json:"read"`    // read-only access
	DenyDirs  []string `json:"deny"`    // always blocked (overrides read)
	AllowNet  []string `json:"allow_net"` // allowed network domains
	DenyNet   bool     `json:"deny_net"`  // block all network by default
}

// DefaultPolicy returns the project-scoped default policy.
func DefaultPolicy(workDir string) Policy {
	home, _ := os.UserHomeDir()
	return Policy{
		WriteDirs: []string{workDir, "/tmp"},
		ReadDirs:  []string{"/usr", "/bin", "/lib", "/etc", home},
		DenyDirs: []string{
			filepath.Join(home, ".ssh"),
			filepath.Join(home, ".gnupg"),
			filepath.Join(home, ".aws"),
			filepath.Join(home, ".config", "gh"),
			filepath.Join(home, ".netrc"),
		},
		AllowNet: []string{"api.anthropic.com"},
		DenyNet:  true,
	}
}

// StrictPolicy returns a minimal policy: only workdir accessible, no network.
func StrictPolicy(workDir string) Policy {
	return Policy{
		WriteDirs: []string{workDir},
		ReadDirs:  []string{workDir},
		DenyDirs:  nil,
		AllowNet:  nil,
		DenyNet:   true,
	}
}

// DisabledPolicy returns a policy that allows everything (yolo mode).
func DisabledPolicy() Policy {
	return Policy{
		WriteDirs: []string{"/"},
		ReadDirs:  []string{"/"},
		DenyDirs:  nil,
		AllowNet:  nil,
		DenyNet:   false,
	}
}

// Merge overlays project policy on top of a base policy.
// Project WriteDirs/ReadDirs are appended. Project DenyDirs override.
// DenyNet is true if either policy denies.
func Merge(base, overlay Policy) Policy {
	return Policy{
		WriteDirs: append(base.WriteDirs, overlay.WriteDirs...),
		ReadDirs:  append(base.ReadDirs, overlay.ReadDirs...),
		DenyDirs:  appendUnique(base.DenyDirs, overlay.DenyDirs),
		AllowNet:  appendUnique(base.AllowNet, overlay.AllowNet),
		DenyNet:   base.DenyNet || overlay.DenyNet,
	}
}

func appendUnique(a, b []string) []string {
	seen := make(map[string]bool, len(a))
	for _, s := range a {
		seen[s] = true
	}
	result := append([]string{}, a...)
	for _, s := range b {
		if !seen[s] {
			result = append(result, s)
		}
	}
	return result
}

// expandVars replaces ~ and $WORKDIR in a path string.
func expandVars(path, workDir string) string {
	if strings.HasPrefix(path, "~/") {
		home, _ := os.UserHomeDir()
		path = filepath.Join(home, path[2:])
	} else if path == "~" {
		home, _ := os.UserHomeDir()
		path = home
	}
	path = strings.ReplaceAll(path, "$WORKDIR", workDir)
	return filepath.Clean(path)
}
```

**Step 4: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/sandbox/policy.go internal/sandbox/policy_test.go
git commit -m "feat(sandbox): add Policy types, defaults, strict, disabled, and merge"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./internal/sandbox/`
  expect: exit 0
</verify>

---

### Task 2: Config loading from sandbox.json

**Files:**
- Modify: `os/Skaffen/internal/sandbox/policy.go`
- Test: `os/Skaffen/internal/sandbox/policy_test.go`

**Step 1: Write the failing test**

```go
func TestLoadFromJSON(t *testing.T) {
	dir := t.TempDir()
	skDir := filepath.Join(dir, ".skaffen")
	os.Mkdir(skDir, 0755)
	os.WriteFile(filepath.Join(skDir, "sandbox.json"), []byte(`{
		"write": ["$WORKDIR/extra"],
		"deny": ["~/.secret"]
	}`), 0644)

	p, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	// Should have default + overlay
	found := false
	for _, d := range p.WriteDirs {
		if d == filepath.Join(dir, "extra") {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected $WORKDIR/extra in WriteDirs, got %v", p.WriteDirs)
	}
}

func TestLoadNoConfig(t *testing.T) {
	dir := t.TempDir()
	p, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.WriteDirs) == 0 {
		t.Fatal("expected default policy when no config exists")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1 -run TestLoad`
Expected: FAIL — Load not defined

**Step 3: Write minimal implementation**

Add to `policy.go`:

```go
import (
	"encoding/json"
	// ... existing imports
)

// Load reads sandbox.json from ~/.skaffen/ (global) and .skaffen/ (per-project),
// merges them with the default policy. Returns the default policy if no config exists.
func Load(workDir string) (Policy, error) {
	base := DefaultPolicy(workDir)

	home, _ := os.UserHomeDir()
	globalPath := filepath.Join(home, ".skaffen", "sandbox.json")
	if overlay, err := loadFile(globalPath, workDir); err == nil {
		base = Merge(base, overlay)
	}

	projectPath := filepath.Join(workDir, ".skaffen", "sandbox.json")
	if overlay, err := loadFile(projectPath, workDir); err == nil {
		base = Merge(base, overlay)
	}

	return base, nil
}

func loadFile(path, workDir string) (Policy, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Policy{}, err
	}
	var raw Policy
	if err := json.Unmarshal(data, &raw); err != nil {
		return Policy{}, err
	}
	// Expand variables in all path lists
	raw.WriteDirs = expandAll(raw.WriteDirs, workDir)
	raw.ReadDirs = expandAll(raw.ReadDirs, workDir)
	raw.DenyDirs = expandAll(raw.DenyDirs, workDir)
	return raw, nil
}

func expandAll(paths []string, workDir string) []string {
	out := make([]string, len(paths))
	for i, p := range paths {
		out[i] = expandVars(p, workDir)
	}
	return out
}
```

**Step 4: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/sandbox/policy.go internal/sandbox/policy_test.go
git commit -m "feat(sandbox): add Load() for sandbox.json config with variable expansion"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1`
  expect: exit 0
</verify>

---

### Task 3: Sandbox enforcer with CheckPath

**Files:**
- Create: `os/Skaffen/internal/sandbox/sandbox.go`
- Test: `os/Skaffen/internal/sandbox/sandbox_test.go`

**Step 1: Write the failing test**

```go
package sandbox

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCheckPathAllowsWorkdir(t *testing.T) {
	s := New(DefaultPolicy("/work"), ModeDefault)
	if err := s.CheckPath("/work/main.go", false); err != nil {
		t.Fatalf("read in workdir should be allowed: %v", err)
	}
	if err := s.CheckPath("/work/main.go", true); err != nil {
		t.Fatalf("write in workdir should be allowed: %v", err)
	}
}

func TestCheckPathDeniesSSH(t *testing.T) {
	home, _ := os.UserHomeDir()
	s := New(DefaultPolicy("/work"), ModeDefault)
	sshPath := filepath.Join(home, ".ssh", "id_rsa")
	if err := s.CheckPath(sshPath, false); err == nil {
		t.Fatal("read of ~/.ssh/id_rsa should be denied")
	}
}

func TestCheckPathDeniesWriteOutsideWorkdir(t *testing.T) {
	s := New(DefaultPolicy("/work"), ModeDefault)
	if err := s.CheckPath("/etc/passwd", true); err == nil {
		t.Fatal("write to /etc/passwd should be denied")
	}
}

func TestCheckPathAllowsReadUsr(t *testing.T) {
	s := New(DefaultPolicy("/work"), ModeDefault)
	if err := s.CheckPath("/usr/bin/git", false); err != nil {
		t.Fatalf("read /usr/bin/git should be allowed: %v", err)
	}
}

func TestCheckPathDisabledMode(t *testing.T) {
	s := New(DefaultPolicy("/work"), ModeDisabled)
	home, _ := os.UserHomeDir()
	sshPath := filepath.Join(home, ".ssh", "id_rsa")
	if err := s.CheckPath(sshPath, false); err != nil {
		t.Fatalf("disabled mode should allow everything: %v", err)
	}
}

func TestCheckPathStrictMode(t *testing.T) {
	s := New(StrictPolicy("/work"), ModeStrict)
	if err := s.CheckPath("/usr/bin/git", false); err == nil {
		t.Fatal("strict mode should deny /usr/bin/git read")
	}
	if err := s.CheckPath("/work/src/main.go", false); err != nil {
		t.Fatalf("strict mode should allow workdir read: %v", err)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1 -run TestCheckPath`
Expected: FAIL — Sandbox type not defined

**Step 3: Write minimal implementation**

```go
package sandbox

import (
	"errors"
	"fmt"
	"path/filepath"
	"strings"
)

var (
	ErrSandboxDenied   = errors.New("sandbox: access denied")
	ErrSandboxReadOnly = errors.New("sandbox: read-only access")
)

// Sandbox enforces filesystem and network access policy.
type Sandbox struct {
	policy Policy
	mode   Mode
}

// New creates a Sandbox with the given policy and mode.
func New(policy Policy, mode Mode) *Sandbox {
	return &Sandbox{policy: policy, mode: mode}
}

// Disabled returns true if sandbox enforcement is off (yolo mode).
func (s *Sandbox) Disabled() bool {
	return s == nil || s.mode == ModeDisabled
}

// Mode returns the current sandbox mode.
func (s *Sandbox) Mode() Mode { return s.mode }

// Policy returns the current policy (for inspection/logging).
func (s *Sandbox) Policy() Policy { return s.policy }

// CheckPath validates whether a path is accessible under the current policy.
// If write is true, the path must be in WriteDirs. If false, it must be in
// ReadDirs or WriteDirs. DenyDirs always take precedence.
func (s *Sandbox) CheckPath(path string, write bool) error {
	if s.Disabled() {
		return nil
	}

	abs, err := filepath.Abs(path)
	if err != nil {
		return fmt.Errorf("%w: %s", ErrSandboxDenied, path)
	}
	abs = filepath.Clean(abs)

	// Deny list takes precedence
	for _, deny := range s.policy.DenyDirs {
		if isUnderDir(abs, deny) {
			return fmt.Errorf("%w: %s", ErrSandboxDenied, path)
		}
	}

	if write {
		for _, dir := range s.policy.WriteDirs {
			if isUnderDir(abs, dir) {
				return nil
			}
		}
		return fmt.Errorf("%w: %s", ErrSandboxReadOnly, path)
	}

	// Read: allowed if in ReadDirs or WriteDirs
	for _, dir := range s.policy.ReadDirs {
		if isUnderDir(abs, dir) {
			return nil
		}
	}
	for _, dir := range s.policy.WriteDirs {
		if isUnderDir(abs, dir) {
			return nil
		}
	}

	return fmt.Errorf("%w: %s", ErrSandboxDenied, path)
}

// isUnderDir checks whether path is equal to or a subdirectory of dir.
func isUnderDir(path, dir string) bool {
	dir = filepath.Clean(dir)
	path = filepath.Clean(path)
	if path == dir {
		return true
	}
	return strings.HasPrefix(path, dir+string(filepath.Separator))
}
```

**Step 4: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/sandbox/sandbox.go internal/sandbox/sandbox_test.go
git commit -m "feat(sandbox): add Sandbox enforcer with CheckPath and mode support"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./internal/sandbox/`
  expect: exit 0
</verify>

---

### Task 4: bwrap backend (Linux)

**Files:**
- Create: `os/Skaffen/internal/sandbox/bwrap.go` (build tag: `//go:build linux`)
- Create: `os/Skaffen/internal/sandbox/wrap_other.go` (build tag: `//go:build !linux && !darwin`)
- Test: `os/Skaffen/internal/sandbox/bwrap_test.go`

**Step 1: Write the failing test**

```go
//go:build linux

package sandbox

import (
	"os/exec"
	"strings"
	"testing"
)

func TestBwrapArgsContainBinds(t *testing.T) {
	p := DefaultPolicy("/work")
	s := New(p, ModeDefault)
	cmd := exec.Command("echo", "hello")
	wrapped := s.WrapCommand(cmd)
	args := strings.Join(wrapped.Args, " ")
	if !strings.Contains(args, "--ro-bind") {
		t.Fatalf("expected --ro-bind in bwrap args, got: %s", args)
	}
	if !strings.Contains(args, "--bind /work /work") {
		t.Fatalf("expected --bind /work /work in bwrap args, got: %s", args)
	}
}

func TestBwrapArgsNetworkDeny(t *testing.T) {
	p := DefaultPolicy("/work")
	s := New(p, ModeDefault)
	cmd := exec.Command("echo", "hello")
	wrapped := s.WrapCommand(cmd)
	args := strings.Join(wrapped.Args, " ")
	if !strings.Contains(args, "--unshare-net") {
		t.Fatal("expected --unshare-net when DenyNet is true")
	}
}

func TestBwrapDisabledMode(t *testing.T) {
	s := New(DisabledPolicy(), ModeDisabled)
	cmd := exec.Command("echo", "hello")
	wrapped := s.WrapCommand(cmd)
	if wrapped.Path != cmd.Path {
		t.Fatal("disabled mode should return original command unchanged")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1 -run TestBwrap`
Expected: FAIL — WrapCommand not defined

**Step 3: Write minimal implementation**

`bwrap.go`:
```go
//go:build linux

package sandbox

import (
	"fmt"
	"os"
	"os/exec"
)

// WrapCommand wraps a command in bubblewrap on Linux.
// Returns the original command unchanged if sandbox is disabled or bwrap is missing.
func (s *Sandbox) WrapCommand(cmd *exec.Cmd) *exec.Cmd {
	if s.Disabled() {
		return cmd
	}

	bwrapPath, err := exec.LookPath("bwrap")
	if err != nil {
		fmt.Fprintf(os.Stderr, "skaffen: warning: bwrap not found, sandbox disabled for subprocess\n")
		fmt.Fprintf(os.Stderr, "skaffen: install with: apt install bubblewrap\n")
		return cmd
	}

	args := []string{}

	// Read-only binds
	for _, dir := range s.policy.ReadDirs {
		// Skip dirs that are also in DenyDirs
		if s.isDenied(dir) {
			continue
		}
		if dirExists(dir) {
			args = append(args, "--ro-bind", dir, dir)
		}
	}

	// Read-write binds
	for _, dir := range s.policy.WriteDirs {
		if s.isDenied(dir) {
			continue
		}
		if dirExists(dir) {
			args = append(args, "--bind", dir, dir)
		}
	}

	// /dev, /proc, /sys for basic functionality
	args = append(args, "--dev", "/dev")
	args = append(args, "--proc", "/proc")

	// Network isolation
	if s.policy.DenyNet {
		args = append(args, "--unshare-net")
	}

	// Prevent orphans
	args = append(args, "--die-with-parent")

	// Append the original command
	args = append(args, "--")
	args = append(args, cmd.Path)
	args = append(args, cmd.Args[1:]...)

	wrapped := exec.CommandContext(cmd.Context(), bwrapPath, args...)
	wrapped.Dir = cmd.Dir
	wrapped.Env = cmd.Env
	wrapped.Stdin = cmd.Stdin
	wrapped.Stdout = cmd.Stdout
	wrapped.Stderr = cmd.Stderr
	return wrapped
}

func (s *Sandbox) isDenied(path string) bool {
	for _, deny := range s.policy.DenyDirs {
		if isUnderDir(path, deny) {
			return true
		}
	}
	return false
}

func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}
```

`wrap_other.go` (fallback for non-Linux/non-Darwin):
```go
//go:build !linux && !darwin

package sandbox

import (
	"fmt"
	"os"
	"os/exec"
)

func (s *Sandbox) WrapCommand(cmd *exec.Cmd) *exec.Cmd {
	if s.Disabled() {
		return cmd
	}
	fmt.Fprintf(os.Stderr, "skaffen: warning: sandbox not supported on this platform\n")
	return cmd
}
```

**Step 4: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1`
Expected: PASS (on Linux; bwrap_test.go skipped on other platforms via build tag)

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/sandbox/bwrap.go internal/sandbox/bwrap_test.go internal/sandbox/wrap_other.go
git commit -m "feat(sandbox): add bwrap backend for Linux subprocess isolation"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./internal/sandbox/`
  expect: exit 0
</verify>

---

### Task 5: Seatbelt backend (macOS)

**Files:**
- Create: `os/Skaffen/internal/sandbox/seatbelt.go` (build tag: `//go:build darwin`)
- Test: `os/Skaffen/internal/sandbox/seatbelt_test.go`

**Step 1: Write the failing test**

```go
//go:build darwin

package sandbox

import (
	"strings"
	"testing"
)

func TestGenerateProfile(t *testing.T) {
	p := DefaultPolicy("/work")
	profile := generateSeatbeltProfile(p)
	if !strings.Contains(profile, "(deny default)") {
		t.Fatal("expected (deny default) in profile")
	}
	if !strings.Contains(profile, "(allow file-read*") {
		t.Fatal("expected file-read allow in profile")
	}
	if !strings.Contains(profile, "(allow file-write*") {
		t.Fatal("expected file-write allow in profile")
	}
	if !strings.Contains(profile, "(deny network*)") {
		t.Fatal("expected network deny in profile")
	}
}

func TestSeatbeltDisabledMode(t *testing.T) {
	s := New(DisabledPolicy(), ModeDisabled)
	cmd := exec.Command("echo", "hello")
	wrapped := s.WrapCommand(cmd)
	if wrapped.Path != cmd.Path {
		t.Fatal("disabled mode should return original command")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1 -run TestGenerate`
Expected: FAIL — only runs on macOS; on Linux the test file is excluded by build tag

**Step 3: Write minimal implementation**

```go
//go:build darwin

package sandbox

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// WrapCommand wraps a command in sandbox-exec on macOS.
func (s *Sandbox) WrapCommand(cmd *exec.Cmd) *exec.Cmd {
	if s.Disabled() {
		return cmd
	}

	sbExec, err := exec.LookPath("sandbox-exec")
	if err != nil {
		fmt.Fprintf(os.Stderr, "skaffen: warning: sandbox-exec not found\n")
		return cmd
	}

	profile := generateSeatbeltProfile(s.policy)

	// Write profile to temp file
	f, err := os.CreateTemp("", "skaffen-sandbox-*.sb")
	if err != nil {
		fmt.Fprintf(os.Stderr, "skaffen: warning: cannot create sandbox profile: %v\n", err)
		return cmd
	}
	f.WriteString(profile)
	f.Close()
	profilePath := f.Name()

	args := []string{"-f", profilePath, cmd.Path}
	args = append(args, cmd.Args[1:]...)

	wrapped := exec.CommandContext(cmd.Context(), sbExec, args...)
	wrapped.Dir = cmd.Dir
	wrapped.Env = cmd.Env
	wrapped.Stdin = cmd.Stdin
	wrapped.Stdout = cmd.Stdout
	wrapped.Stderr = cmd.Stderr

	// Clean up profile after command completes (best-effort)
	go func() {
		if wrapped.Process != nil {
			wrapped.Process.Wait()
		}
		os.Remove(profilePath)
	}()

	return wrapped
}

func generateSeatbeltProfile(p Policy) string {
	var b strings.Builder
	b.WriteString("(version 1)\n")
	b.WriteString("(deny default)\n")

	// Allow process execution
	b.WriteString("(allow process-exec)\n")
	b.WriteString("(allow process-fork)\n")
	b.WriteString("(allow sysctl-read)\n")
	b.WriteString("(allow mach-lookup)\n")

	// Read access
	for _, dir := range p.ReadDirs {
		fmt.Fprintf(&b, "(allow file-read* (subpath \"%s\"))\n", dir)
	}

	// Write access
	for _, dir := range p.WriteDirs {
		fmt.Fprintf(&b, "(allow file-read* (subpath \"%s\"))\n", dir)
		fmt.Fprintf(&b, "(allow file-write* (subpath \"%s\"))\n", dir)
	}

	// Deny overrides (must come after allows)
	for _, dir := range p.DenyDirs {
		fmt.Fprintf(&b, "(deny file-read* (subpath \"%s\"))\n", dir)
		fmt.Fprintf(&b, "(deny file-write* (subpath \"%s\"))\n", dir)
	}

	// Network
	if p.DenyNet {
		b.WriteString("(deny network*)\n")
	}

	return b.String()
}
```

**Step 4: Verify builds on Linux (build tag excludes darwin file)**

Run: `cd os/Skaffen && go build ./internal/sandbox/`
Expected: Builds without errors (seatbelt.go excluded on Linux, bwrap.go included)

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/sandbox/seatbelt.go internal/sandbox/seatbelt_test.go
git commit -m "feat(sandbox): add Seatbelt backend for macOS subprocess isolation"
```

<verify>
- run: `cd os/Skaffen && go build ./internal/sandbox/`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./internal/sandbox/`
  expect: exit 0
</verify>

---

### Task 6: Wire sandbox into BashTool

**Files:**
- Modify: `os/Skaffen/internal/tool/bash.go`
- Test: `os/Skaffen/internal/tool/bash_test.go`

**Step 1: Write the failing test**

Add to `bash_test.go`:

```go
func TestBashToolUseSandbox(t *testing.T) {
	// Verify BashTool accepts a sandbox and WrapCommand is called
	s := sandbox.New(sandbox.DefaultPolicy(t.TempDir()), sandbox.ModeDefault)
	bt := &BashTool{Sandbox: s}
	if bt.Sandbox == nil {
		t.Fatal("expected sandbox to be set")
	}
}

func TestBashToolNilSandbox(t *testing.T) {
	// BashTool should work without sandbox (backward compat)
	bt := &BashTool{}
	params, _ := json.Marshal(bashParams{Command: "echo hello"})
	result := bt.Execute(context.Background(), params)
	if result.IsError {
		t.Fatalf("expected success, got error: %s", result.Content)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1 -run TestBashTool`
Expected: FAIL — BashTool has no Sandbox field

**Step 3: Modify bash.go**

Add `Sandbox` field to `BashTool` and use `WrapCommand` in `Execute`:

```go
import (
	"github.com/mistakeknot/Skaffen/internal/sandbox"
	// ... existing imports
)

type BashTool struct {
	Sandbox *sandbox.Sandbox
}

// In Execute, after creating the cmd, wrap it:
func (t *BashTool) Execute(ctx context.Context, params json.RawMessage) ToolResult {
	// ... existing param parsing and timeout setup ...

	cmd := exec.CommandContext(ctx, "bash", "-c", p.Command)

	// Sandbox wrapping
	if t.Sandbox != nil {
		cmd = t.Sandbox.WrapCommand(cmd)
	}

	out, err := cmd.CombinedOutput()
	// ... rest unchanged ...
}
```

**Step 4: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/tool/bash.go internal/tool/bash_test.go
git commit -m "feat(sandbox): wire sandbox into BashTool for subprocess isolation"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
  expect: exit 0
</verify>

---

### Task 7: Wire sandbox into tool Registry for in-process path validation

**Files:**
- Modify: `os/Skaffen/internal/tool/registry.go`
- Test: `os/Skaffen/internal/tool/registry_test.go`

**Step 1: Write the failing test**

```go
func TestRegistryBlocksDeniedPath(t *testing.T) {
	home, _ := os.UserHomeDir()
	s := sandbox.New(sandbox.DefaultPolicy("/work"), sandbox.ModeDefault)
	reg := NewRegistry()
	reg.SetSandbox(s)
	RegisterBuiltins(reg)

	// Try to read ~/.ssh/id_rsa — should be denied
	sshPath := filepath.Join(home, ".ssh", "id_rsa")
	params, _ := json.Marshal(map[string]string{"file_path": sshPath})
	result := reg.Execute(context.Background(), PhaseBuild, "read", params)
	if !result.IsError {
		t.Fatal("expected sandbox denial for ~/.ssh read")
	}
	if !strings.Contains(result.Content, "sandbox") {
		t.Fatalf("expected sandbox error message, got: %s", result.Content)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1 -run TestRegistryBlocks`
Expected: FAIL — SetSandbox not defined

**Step 3: Modify registry.go**

Add `Sandbox` field and path extraction + validation in `Execute()`:

```go
import (
	"github.com/mistakeknot/Skaffen/internal/sandbox"
)

type Registry struct {
	tools    map[string]Tool
	gates    map[Phase]map[string]bool
	planMode bool
	sandbox  *sandbox.Sandbox
}

func (r *Registry) SetSandbox(s *sandbox.Sandbox) { r.sandbox = s }

// In Execute(), after phase/plan checks but before calling the tool:
// Extract file_path from params and validate against sandbox.
func (r *Registry) Execute(ctx context.Context, phase Phase, name string, params json.RawMessage) ToolResult {
	// ... existing plan mode and phase checks ...

	// Sandbox path validation for file-accessing tools
	if r.sandbox != nil && !r.sandbox.Disabled() {
		if filePath := extractFilePath(name, params); filePath != "" {
			write := isWriteTool(name)
			if err := r.sandbox.CheckPath(filePath, write); err != nil {
				return ToolResult{
					Content: fmt.Sprintf("sandbox: %v", err),
					IsError: true,
				}
			}
		}
	}

	// ... existing tool execution ...
}

// writeTools are tools that modify files.
var writeTools = map[string]bool{"write": true, "edit": true}

func isWriteTool(name string) bool { return writeTools[name] }

// extractFilePath pulls the file_path param from tool input JSON.
// Returns empty string if not a file-accessing tool or no path found.
func extractFilePath(toolName string, params json.RawMessage) string {
	switch toolName {
	case "read", "write", "edit":
		var p struct {
			FilePath string `json:"file_path"`
		}
		json.Unmarshal(params, &p)
		return p.FilePath
	case "grep", "glob":
		var p struct {
			Path string `json:"path"`
		}
		json.Unmarshal(params, &p)
		return p.Path
	default:
		return ""
	}
}
```

**Step 4: Run test to verify it passes**

Run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/tool/registry.go internal/tool/registry_test.go
git commit -m "feat(sandbox): inject CheckPath into Registry.Execute for in-process tools"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
  expect: exit 0
</verify>

---

### Task 8: Wire sandbox into MCP Manager

**Files:**
- Modify: `os/Skaffen/internal/mcp/client.go`
- Modify: `os/Skaffen/internal/mcp/manager.go`

**Step 1: Add Sandbox field to Manager**

Modify `NewManager` to accept a sandbox and pass it to `NewClient`:

```go
// In manager.go
type Manager struct {
	config   map[string]PluginConfig
	registry *tool.Registry
	handles  map[string]*serverHandle
	mu       sync.RWMutex
	shutdown bool
	sandbox  *sandbox.Sandbox  // added
}

func NewManager(config map[string]PluginConfig, registry *tool.Registry, sb *sandbox.Sandbox) *Manager {
	return &Manager{
		config:   config,
		registry: registry,
		handles:  make(map[string]*serverHandle),
		sandbox:  sb,
	}
}
```

**Step 2: Modify NewClient to accept and use sandbox**

In `client.go`, modify the command creation:

```go
func NewClient(ctx context.Context, command string, args []string, env map[string]string, sb *sandbox.Sandbox) (*Client, error) {
	cmd := exec.Command(command, args...)

	// Apply sandbox wrapping
	if sb != nil {
		cmd = sb.WrapCommand(cmd)
	}

	// ... rest unchanged ...
}
```

**Step 3: Update all call sites**

Update `connectAndRegister` in `manager.go` to pass `m.sandbox` to `NewClient`.

**Step 4: Run tests to verify nothing broke**

Run: `cd os/Skaffen && go test ./internal/mcp/ -v -count=1`
Expected: PASS (existing tests pass with nil sandbox)

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/mcp/client.go internal/mcp/manager.go
git commit -m "feat(sandbox): wrap MCP server subprocesses in sandbox"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/mcp/ -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
</verify>

---

### Task 9: CLI flags and main.go wiring

**Files:**
- Modify: `os/Skaffen/cmd/skaffen/main.go`

**Step 1: Add CLI flags**

```go
var (
	// ... existing flags ...
	flagYolo    = flag.Bool("yolo", false, "Alias for --dangerously-disable-sandbox")
	flagNoSandbox = flag.Bool("dangerously-disable-sandbox", false, "Disable all sandbox enforcement")
	flagSandbox = flag.String("sandbox", "default", "Sandbox mode: default, strict")
)
```

**Step 2: Create sandbox at startup**

After config loading, before registry creation:

```go
// Determine sandbox mode
sandboxMode := sandbox.ModeDefault
if *flagYolo || *flagNoSandbox {
	sandboxMode = sandbox.ModeDisabled
	fmt.Fprintln(os.Stderr, "skaffen: WARNING: sandbox disabled (--yolo)")
} else if *flagSandbox == "strict" {
	sandboxMode = sandbox.ModeStrict
}

// Load sandbox policy
var sb *sandbox.Sandbox
switch sandboxMode {
case sandbox.ModeDisabled:
	sb = sandbox.New(sandbox.DisabledPolicy(), sandbox.ModeDisabled)
case sandbox.ModeStrict:
	sb = sandbox.New(sandbox.StrictPolicy(cfg.WorkDir()), sandbox.ModeStrict)
default:
	policy, err := sandbox.Load(cfg.WorkDir())
	if err != nil {
		fmt.Fprintf(os.Stderr, "skaffen: warning: sandbox config error: %v (using defaults)\n", err)
		policy = sandbox.DefaultPolicy(cfg.WorkDir())
	}
	sb = sandbox.New(policy, sandbox.ModeDefault)
}
```

**Step 3: Pass sandbox to Registry and BashTool**

```go
reg := tool.NewRegistry()
reg.SetSandbox(sb)

// When creating BashTool (if it's registered individually):
// The BashTool needs sandbox injected. Since RegisterBuiltins creates
// tools inline, modify RegisterBuiltins to accept a sandbox parameter,
// or set it on the BashTool after registration:
if bt, ok := reg.Get("bash"); ok {
	if bashTool, ok := bt.(*tool.BashTool); ok {
		bashTool.Sandbox = sb
	}
}

// Pass to MCP manager
mcpMgr := mcp.NewManager(pluginConfigs, reg, sb)
```

**Step 4: Build and verify**

Run: `cd os/Skaffen && go build ./cmd/skaffen`
Expected: Builds successfully

Run: `cd os/Skaffen && go vet ./...`
Expected: No issues

**Step 5: Commit**

```bash
cd os/Skaffen && git add cmd/skaffen/main.go
git commit -m "feat(sandbox): add --yolo/--dangerously-disable-sandbox/--sandbox=strict CLI flags"
```

<verify>
- run: `cd os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./...`
  expect: exit 0
</verify>

---

### Task 10: Integration test — end-to-end sandbox verification

**Files:**
- Create: `os/Skaffen/internal/sandbox/integration_test.go`

**Step 1: Write integration test**

```go
//go:build linux

package sandbox

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestIntegrationBwrapBlocksDeniedPath(t *testing.T) {
	if _, err := exec.LookPath("bwrap"); err != nil {
		t.Skip("bwrap not installed, skipping integration test")
	}

	// Create a secret file outside workdir
	secretDir := t.TempDir()
	secretFile := filepath.Join(secretDir, "secret.txt")
	os.WriteFile(secretFile, []byte("top-secret"), 0644)

	workDir := t.TempDir()
	p := Policy{
		WriteDirs: []string{workDir},
		ReadDirs:  []string{"/usr", "/bin", "/lib", "/tmp"},
		DenyDirs:  []string{secretDir},
		DenyNet:   true,
	}
	s := New(p, ModeDefault)

	// Try to cat the secret file inside bwrap
	cmd := exec.CommandContext(context.Background(), "cat", secretFile)
	wrapped := s.WrapCommand(cmd)
	out, err := wrapped.CombinedOutput()

	// Should fail — the secret dir is not mounted
	if err == nil {
		t.Fatalf("expected bwrap to block access, got output: %s", string(out))
	}
	if strings.Contains(string(out), "top-secret") {
		t.Fatal("secret content should not be readable")
	}
}

func TestIntegrationBwrapAllowsWorkdir(t *testing.T) {
	if _, err := exec.LookPath("bwrap"); err != nil {
		t.Skip("bwrap not installed, skipping integration test")
	}

	workDir := t.TempDir()
	testFile := filepath.Join(workDir, "test.txt")
	os.WriteFile(testFile, []byte("allowed"), 0644)

	p := Policy{
		WriteDirs: []string{workDir},
		ReadDirs:  []string{"/usr", "/bin", "/lib", "/tmp"},
		DenyNet:   false,
	}
	s := New(p, ModeDefault)

	cmd := exec.CommandContext(context.Background(), "cat", testFile)
	wrapped := s.WrapCommand(cmd)
	out, err := wrapped.CombinedOutput()

	if err != nil {
		t.Fatalf("expected workdir access to succeed, got: %v\n%s", err, string(out))
	}
	if !strings.Contains(string(out), "allowed") {
		t.Fatalf("expected 'allowed' in output, got: %s", string(out))
	}
}
```

**Step 2: Run integration test**

Run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1 -run TestIntegration`
Expected: PASS (on Linux with bwrap installed)

**Step 3: Commit**

```bash
cd os/Skaffen && git add internal/sandbox/integration_test.go
git commit -m "test(sandbox): add bwrap integration tests for deny/allow verification"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/sandbox/ -v -count=1 -run TestIntegration`
  expect: exit 0
</verify>

---

### Task 11: Full build verification and final push

**Step 1: Run full test suite**

Run: `cd os/Skaffen && go test ./... -count=1`
Expected: All tests pass

**Step 2: Run vet**

Run: `cd os/Skaffen && go vet ./...`
Expected: No issues

**Step 3: Build binary**

Run: `cd os/Skaffen && go build ./cmd/skaffen`
Expected: Builds successfully

**Step 4: Push**

```bash
cd os/Skaffen && git push
```

<verify>
- run: `cd os/Skaffen && go test ./... -count=1 2>&1 | tail -20`
  expect: exit 0
- run: `cd os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
</verify>
