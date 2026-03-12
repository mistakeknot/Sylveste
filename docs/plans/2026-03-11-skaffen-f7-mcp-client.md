---
artifact_type: plan
bead: Demarch-o5u
stage: executed
requirements:
  - F1: Plugin config parsing
  - F2: MCP stdio client
  - F3: Registry integration
  - F4: Lifecycle management
---
# F7: MCP Stdio Client — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-o5u
**Goal:** Give Skaffen access to Interverse plugin MCP tools with config-driven discovery, lazy spawn, and per-plugin phase gating.

**Architecture:** New `internal/mcp/` package with 5 files: config parser, client wrapper, tool adapter, lifecycle manager, and package doc. The manager is wired into `main.go` after `RegisterBuiltins()`. Uses the official MCP Go SDK (`modelcontextprotocol/go-sdk`) for JSON-RPC stdio transport. Plugins declared in `plugins.toml` with per-plugin phase lists.

**Tech Stack:** Go 1.22, `modelcontextprotocol/go-sdk` (MCP client), `BurntSushi/toml` (config), existing `tool.Registry` for phase gating.

**Prior Learnings:**
- `docs/solutions/patterns/critical-patterns.md` — MCP servers use launcher scripts (`bin/launch-mcp.sh`), not bare binaries. Skaffen must invoke the `command` from plugin.json as-is (it's already a launcher).
- `docs/solutions/workflow-issues/auto-build-launcher-go-mcp-plugins-20260215.md` — MCP servers launch before SessionStart hooks. Stderr stays clean for JSON-RPC.
- `docs/solutions/integration-issues/graceful-mcp-launcher-external-deps-interflux-20260224.md` — External deps need graceful degradation. If MCP server fails to spawn, skip it, don't abort.

---

## Must-Haves

**Truths** (observable behaviors):
- Skaffen can call tools from configured MCP plugins during agent loop execution
- MCP tools are filtered by phase — a plugin configured for `["build"]` is invisible during brainstorm
- If a configured plugin fails to spawn, Skaffen continues with remaining tools (no abort)
- Tool names are namespaced to prevent collisions between plugins

**Artifacts:**
- `os/Skaffen/internal/mcp/config.go` exports `LoadConfig`, `PluginConfig`, `ServerConfig`
- `os/Skaffen/internal/mcp/client.go` exports `Client`, `NewClient`
- `os/Skaffen/internal/mcp/tool.go` exports `MCPTool`
- `os/Skaffen/internal/mcp/manager.go` exports `Manager`, `NewManager`
- `os/Skaffen/internal/tool/registry.go` exports `RegisterForPhases`

**Key Links:**
- `Manager.EnsureRunning()` calls `Client.Connect()` which spawns the subprocess
- `MCPTool.Execute()` calls `Client.CallTool()` which sends JSON-RPC to the subprocess
- `Manager.RegisterTools()` calls `Registry.RegisterForPhases()` to add tools with phase gating
- `main.go` calls `Manager.LoadAll()` after `RegisterBuiltins()` and `Manager.Shutdown()` on exit

---

### Task 1: Extend Registry with RegisterForPhases

**Files:**
- Modify: `os/Skaffen/internal/tool/registry.go`
- Modify: `os/Skaffen/internal/tool/registry_test.go`

The existing `Register()` hardcodes tools into the build phase only. We need `RegisterForPhases()` so MCP tools can be gated to specific phases.

**Step 1: Write the failing test**

Add to `os/Skaffen/internal/tool/registry_test.go`:

```go
func TestRegistry_RegisterForPhases(t *testing.T) {
	r := NewRegistry()
	custom := &stubTool{name: "mcp_search"}
	r.RegisterForPhases(custom, []Phase{PhaseBrainstorm, PhaseBuild})

	// Available in brainstorm
	names := toolNames(r.Tools(PhaseBrainstorm))
	if !names["mcp_search"] {
		t.Error("mcp_search should be in brainstorm")
	}

	// Available in build
	names = toolNames(r.Tools(PhaseBuild))
	if !names["mcp_search"] {
		t.Error("mcp_search should be in build")
	}

	// NOT available in review
	names = toolNames(r.Tools(PhaseReview))
	if names["mcp_search"] {
		t.Error("mcp_search should not be in review")
	}

	// NOT available in ship
	names = toolNames(r.Tools(PhaseShip))
	if names["mcp_search"] {
		t.Error("mcp_search should not be in ship")
	}
}

func TestRegistry_RegisterForPhases_Empty(t *testing.T) {
	r := NewRegistry()
	custom := &stubTool{name: "mcp_nophase"}
	r.RegisterForPhases(custom, nil)

	// Default: build only
	names := toolNames(r.Tools(PhaseBuild))
	if !names["mcp_nophase"] {
		t.Error("nil phases should default to build")
	}

	names = toolNames(r.Tools(PhaseBrainstorm))
	if names["mcp_nophase"] {
		t.Error("should not be in brainstorm with nil phases")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/tool/ -run TestRegistry_RegisterForPhases -v`
Expected: FAIL — `RegisterForPhases` not defined

**Step 3: Implement RegisterForPhases**

Add to `os/Skaffen/internal/tool/registry.go`:

```go
// RegisterForPhases adds a tool to the registry, gated to specific phases.
// If phases is nil or empty, defaults to build-only (same as Register).
func (r *Registry) RegisterForPhases(t Tool, phases []Phase) {
	r.tools[t.Name()] = t
	if len(phases) == 0 {
		phases = []Phase{PhaseBuild}
	}
	for _, phase := range phases {
		if r.gates[phase] == nil {
			r.gates[phase] = make(map[string]bool)
		}
		r.gates[phase][t.Name()] = true
	}
}
```

**Step 4: Run tests to verify they pass**

Run: `cd os/Skaffen && go test ./internal/tool/ -v`
Expected: ALL PASS (both new tests + all existing tests)

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/tool/registry.go internal/tool/registry_test.go
git commit -m "feat(tool): add RegisterForPhases for MCP phase gating"
```

<verify>
- run: `cd os/Skaffen && go test -race ./internal/tool/ -v`
  expect: exit 0
</verify>

---

### Task 2: Plugin Config Parser

**Files:**
- Create: `os/Skaffen/internal/mcp/config.go`
- Create: `os/Skaffen/internal/mcp/config_test.go`

Parses `plugins.toml` and reads `mcpServers` from each referenced `plugin.json`.

**Step 1: Add TOML dependency**

Run: `cd os/Skaffen && go get github.com/BurntSushi/toml@latest`

**Step 2: Write the failing test**

Create `os/Skaffen/internal/mcp/config_test.go`:

```go
package mcp

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/mistakeknot/Skaffen/internal/tool"
)

func TestLoadConfig_BasicParsing(t *testing.T) {
	dir := t.TempDir()

	// Create a minimal plugin.json
	pluginDir := filepath.Join(dir, "my-plugin", ".claude-plugin")
	os.MkdirAll(pluginDir, 0o755)
	pluginJSON := `{
		"name": "my-plugin",
		"mcpServers": {
			"my-plugin": {
				"type": "stdio",
				"command": "${CLAUDE_PLUGIN_ROOT}/bin/launch-mcp.sh",
				"args": ["--verbose"],
				"env": {
					"API_KEY": "${MY_API_KEY}"
				}
			}
		}
	}`
	os.WriteFile(filepath.Join(pluginDir, "plugin.json"), []byte(pluginJSON), 0o644)

	// Create plugins.toml referencing it
	tomlPath := filepath.Join(dir, "plugins.toml")
	toml := `[plugins.my-plugin]
path = "` + filepath.Join(pluginDir, "plugin.json") + `"
phases = ["brainstorm", "build"]
`
	os.WriteFile(tomlPath, []byte(toml), 0o644)

	// Set env var for expansion
	t.Setenv("MY_API_KEY", "test-key-123")

	cfg, err := LoadConfig(tomlPath)
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}

	if len(cfg) != 1 {
		t.Fatalf("got %d plugins, want 1", len(cfg))
	}

	pc := cfg["my-plugin"]
	if pc.Name != "my-plugin" {
		t.Errorf("Name = %q", pc.Name)
	}
	if len(pc.Phases) != 2 {
		t.Errorf("Phases = %v, want [brainstorm build]", pc.Phases)
	}
	if len(pc.Servers) != 1 {
		t.Fatalf("Servers: got %d, want 1", len(pc.Servers))
	}

	srv := pc.Servers["my-plugin"]
	if srv.Command == "" {
		t.Error("Command is empty")
	}
	// ${CLAUDE_PLUGIN_ROOT} expanded to plugin.json parent dir
	if srv.Command != filepath.Join(pluginDir, "bin", "launch-mcp.sh") {
		t.Errorf("Command = %q, want launcher path", srv.Command)
	}
	if len(srv.Args) != 1 || srv.Args[0] != "--verbose" {
		t.Errorf("Args = %v, want [--verbose]", srv.Args)
	}
}

func TestLoadConfig_ArgsEnvExpansion(t *testing.T) {
	dir := t.TempDir()
	pluginDir := filepath.Join(dir, "arg-test", ".claude-plugin")
	os.MkdirAll(pluginDir, 0o755)
	pluginJSON := `{
		"name": "arg-test",
		"mcpServers": {
			"arg-test": {
				"type": "stdio",
				"command": "echo",
				"args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config.json"]
			}
		}
	}`
	os.WriteFile(filepath.Join(pluginDir, "plugin.json"), []byte(pluginJSON), 0o644)

	tomlPath := filepath.Join(dir, "plugins.toml")
	toml := `[plugins.arg-test]
path = "` + filepath.Join(pluginDir, "plugin.json") + `"
phases = ["build"]
`
	os.WriteFile(tomlPath, []byte(toml), 0o644)

	cfg, err := LoadConfig(tomlPath)
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}

	srv := cfg["arg-test"].Servers["arg-test"]
	expectedArg := filepath.Join(pluginDir, "config.json")
	if len(srv.Args) != 2 || srv.Args[1] != expectedArg {
		t.Errorf("Args = %v, want [--config %s]", srv.Args, expectedArg)
	}
	if srv.Env["API_KEY"] != "test-key-123" {
		t.Errorf("Env[API_KEY] = %q", srv.Env["API_KEY"])
	}
}

func TestLoadConfig_MissingPluginJSON(t *testing.T) {
	dir := t.TempDir()
	tomlPath := filepath.Join(dir, "plugins.toml")
	toml := `[plugins.missing]
path = "/nonexistent/plugin.json"
phases = ["build"]
`
	os.WriteFile(tomlPath, []byte(toml), 0o644)

	cfg, err := LoadConfig(tomlPath)
	if err != nil {
		t.Fatalf("LoadConfig should not error on missing plugin.json: %v", err)
	}
	// Missing plugin should be skipped
	if len(cfg) != 0 {
		t.Errorf("got %d plugins, want 0 (missing should be skipped)", len(cfg))
	}
}

func TestLoadConfig_DefaultPhases(t *testing.T) {
	dir := t.TempDir()
	pluginDir := filepath.Join(dir, "simple", ".claude-plugin")
	os.MkdirAll(pluginDir, 0o755)
	pluginJSON := `{"name":"simple","mcpServers":{"simple":{"type":"stdio","command":"echo"}}}`
	os.WriteFile(filepath.Join(pluginDir, "plugin.json"), []byte(pluginJSON), 0o644)

	tomlPath := filepath.Join(dir, "plugins.toml")
	toml := `[plugins.simple]
path = "` + filepath.Join(pluginDir, "plugin.json") + `"
`
	os.WriteFile(tomlPath, []byte(toml), 0o644)

	cfg, err := LoadConfig(tomlPath)
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}

	pc := cfg["simple"]
	// Default phases should be ["build"]
	if len(pc.Phases) != 1 || pc.Phases[0] != tool.PhaseBuild {
		t.Errorf("default Phases = %v, want [build]", pc.Phases)
	}
}

func TestLoadConfig_NoFile(t *testing.T) {
	cfg, err := LoadConfig("/nonexistent/plugins.toml")
	if err != nil {
		t.Fatalf("missing config should return empty, not error: %v", err)
	}
	if len(cfg) != 0 {
		t.Errorf("got %d plugins for missing config", len(cfg))
	}
}
```

**Step 3: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/mcp/ -run TestLoadConfig -v`
Expected: FAIL — package mcp has no Go files

**Step 4: Implement config parser**

Create `os/Skaffen/internal/mcp/config.go`:

```go
package mcp

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/BurntSushi/toml"
	"github.com/mistakeknot/Skaffen/internal/tool"
)

// PluginConfig holds the resolved configuration for one plugin.
type PluginConfig struct {
	Name    string
	Phases  []tool.Phase
	Servers map[string]ServerConfig
}

// ServerConfig describes one MCP server from plugin.json mcpServers.
type ServerConfig struct {
	Type    string            // "stdio" only
	Command string            // resolved command path
	Args    []string          // command arguments
	Env     map[string]string // resolved environment variables
}

// tomlConfig is the raw TOML structure.
type tomlConfig struct {
	Plugins map[string]tomlPlugin `toml:"plugins"`
}

type tomlPlugin struct {
	Path   string   `toml:"path"`
	Phases []string `toml:"phases"`
	Env    map[string]string `toml:"env"` // extra env overrides
}

// pluginJSON is the structure of plugin.json's mcpServers field.
type pluginJSON struct {
	Name       string                       `json:"name"`
	MCPServers map[string]pluginJSONServer   `json:"mcpServers"`
}

type pluginJSONServer struct {
	Type    string            `json:"type"`
	Command string            `json:"command"`
	Args    []string          `json:"args"`
	Env     map[string]string `json:"env"`
}

// LoadConfig reads plugins.toml and resolves each plugin's MCP servers.
// Returns an empty map (not error) if the config file doesn't exist.
// Skips plugins whose plugin.json is missing or malformed (logs to stderr).
func LoadConfig(tomlPath string) (map[string]PluginConfig, error) {
	result := make(map[string]PluginConfig)

	data, err := os.ReadFile(tomlPath)
	if os.IsNotExist(err) {
		return result, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read plugins config: %w", err)
	}

	var raw tomlConfig
	if err := toml.Unmarshal(data, &raw); err != nil {
		return nil, fmt.Errorf("parse plugins config: %w", err)
	}

	configDir := filepath.Dir(tomlPath)

	for name, entry := range raw.Plugins {
		pc, err := resolvePlugin(name, entry, configDir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "skaffen: warning: plugin %q: %v (skipping)\n", name, err)
			continue
		}
		result[name] = pc
	}

	return result, nil
}

func resolvePlugin(name string, entry tomlPlugin, configDir string) (PluginConfig, error) {
	// Resolve plugin.json path relative to config dir
	pluginPath := entry.Path
	if !filepath.IsAbs(pluginPath) {
		pluginPath = filepath.Join(configDir, pluginPath)
	}
	pluginPath = expandEnv(pluginPath)

	data, err := os.ReadFile(pluginPath)
	if err != nil {
		return PluginConfig{}, fmt.Errorf("read plugin.json: %w", err)
	}

	var pj pluginJSON
	if err := json.Unmarshal(data, &pj); err != nil {
		return PluginConfig{}, fmt.Errorf("parse plugin.json: %w", err)
	}

	// Resolve phases (default: build only)
	phases := make([]tool.Phase, 0, len(entry.Phases))
	if len(entry.Phases) == 0 {
		phases = append(phases, tool.PhaseBuild)
	} else {
		for _, p := range entry.Phases {
			phases = append(phases, tool.Phase(p))
		}
	}

	// CLAUDE_PLUGIN_ROOT = directory containing plugin.json
	pluginRoot := filepath.Dir(pluginPath)

	// Resolve MCP servers
	servers := make(map[string]ServerConfig, len(pj.MCPServers))
	for srvName, srv := range pj.MCPServers {
		if srv.Type != "" && srv.Type != "stdio" {
			fmt.Fprintf(os.Stderr, "skaffen: warning: plugin %q server %q: unsupported type %q (skipping)\n", name, srvName, srv.Type)
			continue
		}

		// Expand ${CLAUDE_PLUGIN_ROOT} and env vars in command
		cmd := srv.Command
		cmd = strings.ReplaceAll(cmd, "${CLAUDE_PLUGIN_ROOT}", pluginRoot)
		cmd = expandEnv(cmd)

		// Expand ${CLAUDE_PLUGIN_ROOT} and env vars in args
		args := make([]string, len(srv.Args))
		for i, a := range srv.Args {
			a = strings.ReplaceAll(a, "${CLAUDE_PLUGIN_ROOT}", pluginRoot)
			args[i] = expandEnv(a)
		}

		// Expand env vars in server env
		env := make(map[string]string, len(srv.Env))
		for k, v := range srv.Env {
			v = strings.ReplaceAll(v, "${CLAUDE_PLUGIN_ROOT}", pluginRoot)
			env[k] = expandEnv(v)
		}

		// Merge extra env overrides from plugins.toml
		for k, v := range entry.Env {
			env[k] = expandEnv(v)
		}

		servers[srvName] = ServerConfig{
			Type:    "stdio",
			Command: cmd,
			Args:    args,
			Env:     env,
		}
	}

	if len(servers) == 0 {
		return PluginConfig{}, fmt.Errorf("no stdio MCP servers found in plugin.json")
	}

	return PluginConfig{
		Name:    name,
		Phases:  phases,
		Servers: servers,
	}, nil
}

// expandEnv replaces ${VAR} patterns with values from os.Environ.
// Does not expand $VAR (bare dollar) or ${VAR:-default} syntax.
func expandEnv(s string) string {
	return os.Expand(s, os.Getenv)
}
```

**Step 5: Run tests to verify they pass**

Run: `cd os/Skaffen && go test ./internal/mcp/ -v`
Expected: ALL PASS

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/mcp/config.go internal/mcp/config_test.go go.mod go.sum
git commit -m "feat(mcp): plugin config parser with TOML + plugin.json resolution"
```

<verify>
- run: `cd os/Skaffen && go test -race ./internal/mcp/ -v`
  expect: exit 0
</verify>

---

### Task 3: MCP Stdio Client Wrapper

**Files:**
- Create: `os/Skaffen/internal/mcp/client.go`
- Create: `os/Skaffen/internal/mcp/client_test.go`
- Create: `os/Skaffen/internal/mcp/testdata/echo-server/main.go`

Wraps the official Go SDK's stdio client into a Skaffen-internal interface.

**Step 1: Add go-sdk dependency**

Run: `cd os/Skaffen && go get github.com/modelcontextprotocol/go-sdk@latest`

**Step 2: Create a test MCP server**

Create `os/Skaffen/internal/mcp/testdata/echo-server/main.go` — a minimal MCP server that registers one tool (`echo`) and returns its input:

```go
//go:build ignore

package main

import (
	"context"
	"fmt"
	"os"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func main() {
	server := mcp.NewServer(&mcp.Implementation{
		Name:    "echo-server",
		Version: "1.0.0",
	}, nil)

	server.AddTool(mcp.NewTool("echo",
		mcp.WithDescription("Echo the input text back"),
		mcp.WithString("text", mcp.Description("Text to echo"), mcp.Required()),
	), func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		text, _ := req.Params.Arguments["text"].(string)
		return &mcp.CallToolResult{
			Content: []mcp.Content{mcp.TextContent{Text: fmt.Sprintf("echo: %s", text)}},
		}, nil
	})

	if err := server.Run(context.Background(), mcp.NewStdioTransport()); err != nil {
		fmt.Fprintf(os.Stderr, "server error: %v\n", err)
		os.Exit(1)
	}
}
```

Note: The `//go:build ignore` tag prevents this from being included in the main build. Tests compile it with `go build` into a temp directory.

**Step 3: Write the failing test**

Create `os/Skaffen/internal/mcp/client_test.go`:

```go
package mcp

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

// buildTestServer compiles the echo-server test binary.
func buildTestServer(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	binary := filepath.Join(dir, "echo-server")
	// Find testdata relative to test file
	testdataDir := filepath.Join("testdata", "echo-server")
	cmd := exec.Command("go", "build", "-o", binary, ".")
	cmd.Dir = testdataDir
	cmd.Env = append(os.Environ(), "CGO_ENABLED=0")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("build echo-server: %v\n%s", err, out)
	}
	return binary
}

func TestClient_ConnectAndListTools(t *testing.T) {
	binary := buildTestServer(t)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	c, err := NewClient(ctx, binary, nil, nil)
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	defer c.Close()

	tools, err := c.ListTools(ctx)
	if err != nil {
		t.Fatalf("ListTools: %v", err)
	}
	if len(tools) != 1 {
		t.Fatalf("got %d tools, want 1", len(tools))
	}
	if tools[0].Name != "echo" {
		t.Errorf("tool name = %q, want echo", tools[0].Name)
	}
}

func TestClient_CallTool(t *testing.T) {
	binary := buildTestServer(t)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	c, err := NewClient(ctx, binary, nil, nil)
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	defer c.Close()

	result, err := c.CallTool(ctx, "echo", map[string]any{"text": "hello"})
	if err != nil {
		t.Fatalf("CallTool: %v", err)
	}
	if result.IsError {
		t.Fatalf("tool returned error: %s", result.Content)
	}
	if result.Content != "echo: hello" {
		t.Errorf("content = %q, want %q", result.Content, "echo: hello")
	}
}

func TestClient_CallTool_UnknownTool(t *testing.T) {
	binary := buildTestServer(t)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	c, err := NewClient(ctx, binary, nil, nil)
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	defer c.Close()

	_, err = c.CallTool(ctx, "nonexistent", nil)
	if err == nil {
		t.Fatal("expected error for unknown tool")
	}
}
```

**Step 4: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/mcp/ -run TestClient -v`
Expected: FAIL — `NewClient` not defined

**Step 5: Implement the client wrapper**

Create `os/Skaffen/internal/mcp/client.go`:

```go
package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"

	gomcp "github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/mistakeknot/Skaffen/internal/tool"
)

// ToolInfo describes a tool discovered from an MCP server.
type ToolInfo struct {
	Name        string
	Description string
	InputSchema json.RawMessage
}

// Client wraps an MCP stdio connection to a single server.
type Client struct {
	session *gomcp.ClientSession
	client  *gomcp.Client
}

// NewClient spawns an MCP server subprocess and performs the initialize handshake.
// args and env are optional (may be nil).
func NewClient(ctx context.Context, command string, args []string, env map[string]string) (*Client, error) {
	cmd := exec.CommandContext(ctx, command, args...)

	// Merge env vars into subprocess environment
	if len(env) > 0 {
		cmd.Env = cmd.Environ()
		for k, v := range env {
			cmd.Env = append(cmd.Env, k+"="+v)
		}
	}

	transport := gomcp.NewCommandTransport(cmd)

	client := gomcp.NewClient(&gomcp.Implementation{
		Name:    "skaffen",
		Version: "0.2.0",
	}, nil)

	session, err := client.Connect(ctx, transport, nil)
	if err != nil {
		return nil, fmt.Errorf("mcp connect: %w", err)
	}

	return &Client{session: session, client: client}, nil
}

// ListTools calls tools/list and returns tool metadata.
func (c *Client) ListTools(ctx context.Context) ([]ToolInfo, error) {
	result, err := c.session.ListTools(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("mcp tools/list: %w", err)
	}

	tools := make([]ToolInfo, len(result.Tools))
	for i, t := range result.Tools {
		schema, _ := json.Marshal(t.InputSchema)
		tools[i] = ToolInfo{
			Name:        t.Name,
			Description: t.Description,
			InputSchema: schema,
		}
	}
	return tools, nil
}

// CallTool calls tools/call and returns the result as a tool.ToolResult.
func (c *Client) CallTool(ctx context.Context, name string, arguments map[string]any) (tool.ToolResult, error) {
	result, err := c.session.CallTool(ctx, &gomcp.CallToolParams{
		Name:      name,
		Arguments: arguments,
	})
	if err != nil {
		return tool.ToolResult{}, fmt.Errorf("mcp tools/call %q: %w", name, err)
	}

	// Concatenate text content blocks
	var sb strings.Builder
	for _, content := range result.Content {
		if tc, ok := content.(gomcp.TextContent); ok {
			if sb.Len() > 0 {
				sb.WriteString("\n")
			}
			sb.WriteString(tc.Text)
		}
	}

	return tool.ToolResult{
		Content: sb.String(),
		IsError: result.IsError,
	}, nil
}

// Close gracefully shuts down the MCP session and kills the subprocess.
func (c *Client) Close() error {
	if c.session != nil {
		return c.session.Close()
	}
	return nil
}

```

**Important:** The exact import path and API for `modelcontextprotocol/go-sdk` may differ slightly from this code. After `go get`, check the actual package structure:
- Run: `go doc github.com/modelcontextprotocol/go-sdk/mcp` to see available types
- The key types are: `Client`, `ClientSession`, `CommandTransport`, `CallToolParams`, `Implementation`
- Adjust import aliases and type names as needed

**Step 6: Run tests to verify they pass**

Run: `cd os/Skaffen && go test ./internal/mcp/ -run TestClient -v -timeout 30s`
Expected: ALL PASS

**Step 7: Commit**

```bash
cd os/Skaffen && git add internal/mcp/client.go internal/mcp/client_test.go internal/mcp/testdata/ go.mod go.sum
git commit -m "feat(mcp): stdio client wrapper using official MCP Go SDK"
```

<verify>
- run: `cd os/Skaffen && go test -race ./internal/mcp/ -run TestClient -v -timeout 30s`
  expect: exit 0
</verify>

---

### Task 4: MCPTool Adapter

**Files:**
- Create: `os/Skaffen/internal/mcp/tool.go`
- Create: `os/Skaffen/internal/mcp/tool_test.go`

Implements `tool.Tool` interface by delegating to an MCP client.

**Step 1: Write the failing test**

Create `os/Skaffen/internal/mcp/tool_test.go`:

```go
package mcp

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/mistakeknot/Skaffen/internal/tool"
)

// mockClient implements the subset of Client used by MCPTool.
type mockClient struct {
	callResult tool.ToolResult
	callErr    error
}

func (m *mockClient) CallTool(ctx context.Context, name string, arguments map[string]any) (tool.ToolResult, error) {
	return m.callResult, m.callErr
}

func TestMCPTool_ImplementsInterface(t *testing.T) {
	ti := ToolInfo{
		Name:        "search",
		Description: "Search for things",
		InputSchema: json.RawMessage(`{"type":"object","properties":{"query":{"type":"string"}}}`),
	}
	mt := NewMCPTool("myplugin", "myserver", ti, &mockClient{
		callResult: tool.ToolResult{Content: "found it"},
	})

	// Verify it satisfies tool.Tool
	var _ tool.Tool = mt

	if mt.Name() != "myplugin_myserver_search" {
		t.Errorf("Name() = %q", mt.Name())
	}
	if mt.Description() != "Search for things" {
		t.Errorf("Description() = %q", mt.Description())
	}

	var schema map[string]interface{}
	if err := json.Unmarshal(mt.Schema(), &schema); err != nil {
		t.Fatalf("Schema() not valid JSON: %v", err)
	}
}

func TestMCPTool_Execute(t *testing.T) {
	ti := ToolInfo{
		Name:        "echo",
		Description: "Echo back",
		InputSchema: json.RawMessage(`{"type":"object"}`),
	}
	mc := &mockClient{
		callResult: tool.ToolResult{Content: "echo: hello"},
	}
	mt := NewMCPTool("test", "srv", ti, mc)

	params := json.RawMessage(`{"text":"hello"}`)
	result := mt.Execute(context.Background(), params)
	if result.IsError {
		t.Fatalf("unexpected error: %s", result.Content)
	}
	if result.Content != "echo: hello" {
		t.Errorf("Content = %q", result.Content)
	}
}

func TestMCPTool_Execute_Error(t *testing.T) {
	ti := ToolInfo{Name: "fail", Description: "Fails", InputSchema: json.RawMessage(`{}`)}
	mc := &mockClient{
		callErr: context.DeadlineExceeded,
	}
	mt := NewMCPTool("test", "srv", ti, mc)

	result := mt.Execute(context.Background(), nil)
	if !result.IsError {
		t.Error("expected IsError=true")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/mcp/ -run TestMCPTool -v`
Expected: FAIL — `NewMCPTool` not defined

**Step 3: Implement MCPTool**

Create `os/Skaffen/internal/mcp/tool.go`:

```go
package mcp

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/mistakeknot/Skaffen/internal/tool"
)

// ToolCaller is the interface that MCPTool uses to call tools.
// Satisfied by *Client and by test mocks.
type ToolCaller interface {
	CallTool(ctx context.Context, name string, arguments map[string]any) (tool.ToolResult, error)
}

// MCPTool wraps an MCP tool as a tool.Tool implementation.
type MCPTool struct {
	plugin      string     // plugin name (for namespacing)
	server      string     // server name within the plugin
	info        ToolInfo   // tool metadata from tools/list
	caller      ToolCaller // the MCP client to delegate to
	qualifiedName string   // cached "plugin_server_tool"
}

// NewMCPTool creates an MCPTool that delegates Execute to the given caller.
func NewMCPTool(plugin, server string, info ToolInfo, caller ToolCaller) *MCPTool {
	return &MCPTool{
		plugin:        plugin,
		server:        server,
		info:          info,
		caller:        caller,
		qualifiedName: plugin + "_" + server + "_" + info.Name,
	}
}

func (t *MCPTool) Name() string             { return t.qualifiedName }
func (t *MCPTool) Description() string       { return t.info.Description }
func (t *MCPTool) Schema() json.RawMessage   { return t.info.InputSchema }

// OriginalName returns the tool name as the MCP server knows it.
func (t *MCPTool) OriginalName() string { return t.info.Name }

func (t *MCPTool) Execute(ctx context.Context, params json.RawMessage) tool.ToolResult {
	// Parse params into map for MCP call
	var arguments map[string]any
	if len(params) > 0 {
		if err := json.Unmarshal(params, &arguments); err != nil {
			return tool.ToolResult{
				Content: fmt.Sprintf("invalid params: %v", err),
				IsError: true,
			}
		}
	}

	result, err := t.caller.CallTool(ctx, t.info.Name, arguments)
	if err != nil {
		return tool.ToolResult{
			Content: fmt.Sprintf("mcp tool %q error: %v", t.qualifiedName, err),
			IsError: true,
		}
	}
	return result
}
```

**Step 4: Run tests to verify they pass**

Run: `cd os/Skaffen && go test ./internal/mcp/ -run TestMCPTool -v`
Expected: ALL PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/mcp/tool.go internal/mcp/tool_test.go
git commit -m "feat(mcp): MCPTool adapter implementing tool.Tool interface"
```

<verify>
- run: `cd os/Skaffen && go test -race ./internal/mcp/ -run TestMCPTool -v`
  expect: exit 0
</verify>

---

### Task 5: MCPManager Lifecycle

**Files:**
- Create: `os/Skaffen/internal/mcp/manager.go`
- Create: `os/Skaffen/internal/mcp/manager_test.go`

Orchestrates lazy spawn, tool registration, shutdown, and crash recovery.

**Step 1: Write the failing test**

Create `os/Skaffen/internal/mcp/manager_test.go`:

```go
package mcp

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/mistakeknot/Skaffen/internal/tool"
)

func TestManager_LoadAll_RegistersTools(t *testing.T) {
	binary := buildTestServer(t)

	dir := t.TempDir()
	pluginDir := filepath.Join(dir, "echo-plugin", ".claude-plugin")
	os.MkdirAll(pluginDir, 0o755)
	pluginJSON := `{"name":"echo-plugin","mcpServers":{"echo-plugin":{"type":"stdio","command":"` + binary + `"}}}`
	os.WriteFile(filepath.Join(pluginDir, "plugin.json"), []byte(pluginJSON), 0o644)

	tomlPath := filepath.Join(dir, "plugins.toml")
	tomlContent := `[plugins.echo-plugin]
path = "` + filepath.Join(pluginDir, "plugin.json") + `"
phases = ["brainstorm", "build"]
`
	os.WriteFile(tomlPath, []byte(tomlContent), 0o644)

	cfg, err := LoadConfig(tomlPath)
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}

	reg := tool.NewRegistry()
	tool.RegisterBuiltins(reg)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	mgr := NewManager(cfg, reg)
	defer mgr.Shutdown()

	// LoadAll should connect to the server and register tools
	if err := mgr.LoadAll(ctx); err != nil {
		t.Fatalf("LoadAll: %v", err)
	}

	// Check that echo tool is registered in brainstorm phase
	names := make(map[string]bool)
	for _, td := range reg.Tools(tool.PhaseBrainstorm) {
		names[td.Name] = true
	}
	if !names["echo-plugin_echo-plugin_echo"] {
		t.Errorf("echo tool not in brainstorm. Available: %v", names)
	}

	// Check that echo tool is registered in build phase
	names = make(map[string]bool)
	for _, td := range reg.Tools(tool.PhaseBuild) {
		names[td.Name] = true
	}
	if !names["echo-plugin_echo-plugin_echo"] {
		t.Errorf("echo tool not in build. Available: %v", names)
	}

	// Check that echo tool is NOT in review phase
	names = make(map[string]bool)
	for _, td := range reg.Tools(tool.PhaseReview) {
		names[td.Name] = true
	}
	if names["echo-plugin_echo-plugin_echo"] {
		t.Error("echo tool should not be in review phase")
	}
}

func TestManager_ExecuteThroughRegistry(t *testing.T) {
	// Tests the full path: LoadAll → registry.Execute → MCP tool call
	binary := buildTestServer(t)

	cfg := map[string]PluginConfig{
		"echo": {
			Name:   "echo",
			Phases: []tool.Phase{tool.PhaseBuild},
			Servers: map[string]ServerConfig{
				"echo": {
					Type:    "stdio",
					Command: binary,
				},
			},
		},
	}

	reg := tool.NewRegistry()
	mgr := NewManager(cfg, reg)
	defer mgr.Shutdown()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	if err := mgr.LoadAll(ctx); err != nil {
		t.Fatalf("LoadAll: %v", err)
	}

	result := reg.Execute(ctx, tool.PhaseBuild, "echo_echo_echo", []byte(`{"text":"round-trip"}`))
	if result.IsError {
		t.Fatalf("Execute error: %s", result.Content)
	}
	if result.Content != "echo: round-trip" {
		t.Errorf("Content = %q", result.Content)
	}
}

func TestManager_Shutdown(t *testing.T) {
	binary := buildTestServer(t)

	cfg := map[string]PluginConfig{
		"echo": {
			Name:   "echo",
			Phases: []tool.Phase{tool.PhaseBuild},
			Servers: map[string]ServerConfig{
				"echo": {Type: "stdio", Command: binary},
			},
		},
	}

	reg := tool.NewRegistry()
	mgr := NewManager(cfg, reg)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	mgr.LoadAll(ctx)
	mgr.Shutdown()

	// After shutdown, tool calls should return errors
	result := reg.Execute(ctx, tool.PhaseBuild, "echo_echo_echo", []byte(`{"text":"dead"}`))
	if !result.IsError {
		t.Error("expected error after shutdown")
	}
}

func TestManager_MissingServer_GracefulDegradation(t *testing.T) {
	cfg := map[string]PluginConfig{
		"broken": {
			Name:   "broken",
			Phases: []tool.Phase{tool.PhaseBuild},
			Servers: map[string]ServerConfig{
				"broken": {Type: "stdio", Command: "/nonexistent/binary"},
			},
		},
	}

	reg := tool.NewRegistry()
	mgr := NewManager(cfg, reg)
	defer mgr.Shutdown()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// LoadAll should NOT error — it should skip broken plugins
	err := mgr.LoadAll(ctx)
	if err != nil {
		t.Fatalf("LoadAll should not error on broken plugin: %v", err)
	}

	// No tools should be registered for the broken plugin
	names := make(map[string]bool)
	for _, td := range reg.Tools(tool.PhaseBuild) {
		names[td.Name] = true
	}
	if names["broken_broken_echo"] {
		t.Error("broken plugin tools should not be registered")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/mcp/ -run TestManager -v`
Expected: FAIL — `NewManager` not defined

**Step 3: Implement MCPManager**

Create `os/Skaffen/internal/mcp/manager.go`:

```go
package mcp

import (
	"context"
	"fmt"
	"os"
	"sync"

	"github.com/mistakeknot/Skaffen/internal/tool"
)

const maxRespawns = 3

// serverHandle tracks a running MCP server connection.
type serverHandle struct {
	plugin string
	server string
	client *Client
	tools  []ToolInfo
	mu     sync.Mutex
	spawns int // number of times this server has been spawned
}

// Manager orchestrates MCP server lifecycles and tool registration.
type Manager struct {
	config   map[string]PluginConfig
	registry *tool.Registry
	handles  map[string]*serverHandle // key: "plugin_server"
	mu       sync.RWMutex
	shutdown bool
}

// NewManager creates a Manager from resolved plugin configs.
func NewManager(config map[string]PluginConfig, registry *tool.Registry) *Manager {
	return &Manager{
		config:   config,
		registry: registry,
		handles:  make(map[string]*serverHandle),
	}
}

// LoadAll connects to all configured MCP servers and registers their tools.
// Servers that fail to connect are skipped with a warning (graceful degradation).
func (m *Manager) LoadAll(ctx context.Context) error {
	for pluginName, pc := range m.config {
		for serverName, sc := range pc.Servers {
			if err := m.connectAndRegister(ctx, pluginName, serverName, sc, pc.Phases); err != nil {
				fmt.Fprintf(os.Stderr, "skaffen: warning: plugin %q server %q: %v (skipping)\n",
					pluginName, serverName, err)
			}
		}
	}
	return nil
}

func (m *Manager) connectAndRegister(ctx context.Context, pluginName, serverName string, sc ServerConfig, phases []tool.Phase) error {
	client, err := NewClient(ctx, sc.Command, sc.Args, sc.Env)
	if err != nil {
		return fmt.Errorf("connect: %w", err)
	}

	tools, err := client.ListTools(ctx)
	if err != nil {
		client.Close()
		return fmt.Errorf("list tools: %w", err)
	}

	key := pluginName + "_" + serverName
	handle := &serverHandle{
		plugin: pluginName,
		server: serverName,
		client: client,
		tools:  tools,
		spawns: 1,
	}

	m.mu.Lock()
	m.handles[key] = handle
	m.mu.Unlock()

	// Register tools into the F2 registry with phase gating
	for _, ti := range tools {
		mcpTool := NewMCPTool(pluginName, serverName, ti, &handleCaller{
			manager: m,
			key:     key,
			name:    ti.Name,
		})
		m.registry.RegisterForPhases(mcpTool, phases)
	}

	return nil
}

// handleCaller implements ToolCaller by going through the manager's handle map.
// This indirection lets the manager replace the underlying client on respawn.
type handleCaller struct {
	manager *Manager
	key     string
	name    string
}

func (hc *handleCaller) CallTool(ctx context.Context, name string, arguments map[string]any) (tool.ToolResult, error) {
	hc.manager.mu.RLock()
	h, ok := hc.manager.handles[hc.key]
	shutdown := hc.manager.shutdown
	hc.manager.mu.RUnlock()

	if shutdown {
		return tool.ToolResult{Content: "mcp manager is shut down", IsError: true}, nil
	}
	if !ok || h == nil {
		return tool.ToolResult{Content: fmt.Sprintf("mcp server %q not connected", hc.key), IsError: true}, nil
	}

	h.mu.Lock()
	client := h.client
	h.mu.Unlock()

	if client == nil {
		return tool.ToolResult{Content: fmt.Sprintf("mcp server %q not connected", hc.key), IsError: true}, nil
	}

	result, err := client.CallTool(ctx, name, arguments)
	if err != nil {
		// Attempt respawn
		if respawned := hc.manager.tryRespawn(ctx, hc.key); respawned {
			// Retry once after respawn
			h.mu.Lock()
			client = h.client
			h.mu.Unlock()
			if client != nil {
				return client.CallTool(ctx, name, arguments)
			}
		}
		return tool.ToolResult{
			Content: fmt.Sprintf("mcp tool %q error: %v", name, err),
			IsError: true,
		}, nil
	}
	return result, nil
}

// tryRespawn attempts to restart a crashed MCP server. Returns true if successful.
func (m *Manager) tryRespawn(ctx context.Context, key string) bool {
	m.mu.RLock()
	h, ok := m.handles[key]
	m.mu.RUnlock()
	if !ok {
		return false
	}

	h.mu.Lock()
	defer h.mu.Unlock()

	if h.spawns >= maxRespawns {
		fmt.Fprintf(os.Stderr, "skaffen: warning: plugin %q server %q: max respawns reached (%d)\n",
			h.plugin, h.server, maxRespawns)
		h.client = nil
		return false
	}

	// Close old client
	if h.client != nil {
		h.client.Close()
	}

	// Look up server config
	pc, ok := m.config[h.plugin]
	if !ok {
		return false
	}
	sc, ok := pc.Servers[h.server]
	if !ok {
		return false
	}

	client, err := NewClient(ctx, sc.Command, sc.Args, sc.Env)
	if err != nil {
		fmt.Fprintf(os.Stderr, "skaffen: warning: respawn %q: %v\n", key, err)
		h.client = nil
		return false
	}

	h.client = client
	h.spawns++
	fmt.Fprintf(os.Stderr, "skaffen: respawned plugin %q server %q (attempt %d/%d)\n",
		h.plugin, h.server, h.spawns, maxRespawns)
	return true
}

// Shutdown closes all MCP server connections and kills subprocesses.
func (m *Manager) Shutdown() {
	m.mu.Lock()
	m.shutdown = true
	handles := make(map[string]*serverHandle, len(m.handles))
	for k, v := range m.handles {
		handles[k] = v
	}
	m.mu.Unlock()

	for _, h := range handles {
		h.mu.Lock()
		if h.client != nil {
			h.client.Close()
			h.client = nil
		}
		h.mu.Unlock()
	}
}

// PluginCount returns the number of successfully connected plugins.
func (m *Manager) PluginCount() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	count := 0
	for _, h := range m.handles {
		h.mu.Lock()
		if h.client != nil {
			count++
		}
		h.mu.Unlock()
	}
	return count
}

// ToolCount returns the total number of MCP tools registered.
func (m *Manager) ToolCount() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	count := 0
	for _, h := range m.handles {
		count += len(h.tools)
	}
	return count
}
```

**Step 4: Run tests to verify they pass**

Run: `cd os/Skaffen && go test ./internal/mcp/ -run TestManager -v -timeout 30s`
Expected: ALL PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/mcp/manager.go internal/mcp/manager_test.go
git commit -m "feat(mcp): MCPManager with lazy spawn, crash recovery, graceful degradation"
```

<verify>
- run: `cd os/Skaffen && go test -race ./internal/mcp/ -v -timeout 30s`
  expect: exit 0
</verify>

---

### Task 6: Wire into main.go

**Files:**
- Modify: `os/Skaffen/cmd/skaffen/main.go`

Add `--plugins` flag and MCP loading after `RegisterBuiltins()`.

**Step 1: Add the --plugins flag and MCP loading**

In `os/Skaffen/cmd/skaffen/main.go`, add:

1. New import: `"github.com/mistakeknot/Skaffen/internal/mcp"`
2. New flag: `flagPlugins = flag.String("plugins", "", "Path to plugins.toml (default: ~/.skaffen/plugins.toml)")`
3. Add a shared helper function to avoid duplicating MCP loading in both `runPrint()` and `runTUI()`:

```go
// loadMCPPlugins loads configured MCP plugins into the registry.
// Returns the manager (may be nil if no plugins configured) — caller must defer Shutdown().
func loadMCPPlugins(ctx context.Context, reg *tool.Registry) *mcp.Manager {
	pluginsPath := *flagPlugins
	if pluginsPath == "" {
		pluginsPath = filepath.Join(os.Getenv("HOME"), ".skaffen", "plugins.toml")
	}
	pluginsCfg, err := mcp.LoadConfig(pluginsPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "skaffen: warning: plugins config: %v\n", err)
		return nil
	}
	if len(pluginsCfg) == 0 {
		return nil
	}
	mgr := mcp.NewManager(pluginsCfg, reg)
	if err := mgr.LoadAll(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "skaffen: warning: MCP plugins: %v\n", err)
	}
	fmt.Fprintf(os.Stderr, "skaffen: loaded %d MCP plugin(s), %d tool(s)\n",
		mgr.PluginCount(), mgr.ToolCount())
	return mgr
}
```

4. In both `runPrint()` and `runTUI()`, after `tool.RegisterBuiltins(reg)`, add:

```go
	mcpMgr := loadMCPPlugins(ctx, reg)
	if mcpMgr != nil {
		defer mcpMgr.Shutdown()
	}
```

Note: In `runTUI()`, you may need to create a timeout context for MCP loading since the TUI manages its own context:

```go
	mcpCtx, mcpCancel := context.WithTimeout(context.Background(), 30*time.Second)
	mcpMgr := loadMCPPlugins(mcpCtx, reg)
	mcpCancel()
	if mcpMgr != nil {
		defer mcpMgr.Shutdown()
	}
```

**Step 2: Verify it compiles**

Run: `cd os/Skaffen && go build ./cmd/skaffen/`
Expected: Compiles without error

**Step 3: Test with no plugins.toml (default path, missing file)**

Run: `cd os/Skaffen && echo "hello" | go run ./cmd/skaffen/ --mode print --provider anthropic -p "say hi" --max-turns 1 2>&1 | head -5`
Expected: No MCP warnings (missing config is silent), normal agent output

**Step 4: Commit**

```bash
cd os/Skaffen && git add cmd/skaffen/main.go
git commit -m "feat(skaffen): wire MCP plugin loading into main.go (--plugins flag)"
```

<verify>
- run: `cd os/Skaffen && go build ./cmd/skaffen/`
  expect: exit 0
</verify>

---

### Task 7: Package Doc and Integration Test

**Files:**
- Create: `os/Skaffen/internal/mcp/doc.go`
- Modify: `os/Skaffen/internal/mcp/manager_test.go` (add integration test)

**Step 1: Write package doc**

Create `os/Skaffen/internal/mcp/doc.go`:

```go
// Package mcp provides an MCP stdio client for loading Interverse plugin tools.
//
// The package has four components:
//
//   - Config parser (config.go): reads plugins.toml and resolves MCP servers from plugin.json files
//   - Client wrapper (client.go): wraps the official MCP Go SDK for stdio subprocess communication
//   - Tool adapter (tool.go): MCPTool implements tool.Tool by delegating to an MCP client
//   - Manager (manager.go): orchestrates server lifecycles, tool registration, and crash recovery
//
// Usage in main.go:
//
//	cfg, _ := mcp.LoadConfig("~/.skaffen/plugins.toml")
//	mgr := mcp.NewManager(cfg, registry)
//	mgr.LoadAll(ctx)
//	defer mgr.Shutdown()
//
// Plugins are declared in plugins.toml with per-plugin phase gating:
//
//	[plugins.intermap]
//	path = "interverse/intermap/.claude-plugin/plugin.json"
//	phases = ["brainstorm", "build", "review"]
package mcp
```

**Step 2: Add end-to-end integration test**

Add to `os/Skaffen/internal/mcp/manager_test.go`:

```go
func TestManager_EndToEnd_ConfigToExecution(t *testing.T) {
	// Full integration: config file → parse → connect → register → execute
	binary := buildTestServer(t)

	dir := t.TempDir()
	pluginDir := filepath.Join(dir, "e2e", ".claude-plugin")
	os.MkdirAll(pluginDir, 0o755)
	pluginJSON := `{"name":"e2e","mcpServers":{"e2e":{"type":"stdio","command":"` + binary + `"}}}`
	os.WriteFile(filepath.Join(pluginDir, "plugin.json"), []byte(pluginJSON), 0o644)

	tomlPath := filepath.Join(dir, "plugins.toml")
	tomlContent := `[plugins.e2e]
path = "` + filepath.Join(pluginDir, "plugin.json") + `"
phases = ["build"]
`
	os.WriteFile(tomlPath, []byte(tomlContent), 0o644)

	// Step 1: Load config
	cfg, err := LoadConfig(tomlPath)
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}

	// Step 2: Create registry and manager
	reg := tool.NewRegistry()
	tool.RegisterBuiltins(reg)
	mgr := NewManager(cfg, reg)
	defer mgr.Shutdown()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	// Step 3: Load all plugins
	if err := mgr.LoadAll(ctx); err != nil {
		t.Fatalf("LoadAll: %v", err)
	}

	// Step 4: Execute MCP tool through the registry (same path as agent loop)
	result := reg.Execute(ctx, tool.PhaseBuild, "e2e_e2e_echo", []byte(`{"text":"integration"}`))
	if result.IsError {
		t.Fatalf("Execute error: %s", result.Content)
	}
	if result.Content != "echo: integration" {
		t.Errorf("Content = %q, want %q", result.Content, "echo: integration")
	}

	// Step 5: Verify phase gating (not in brainstorm)
	result = reg.Execute(ctx, tool.PhaseBrainstorm, "e2e_e2e_echo", []byte(`{"text":"blocked"}`))
	if !result.IsError {
		t.Error("expected error for brainstorm phase (tool only in build)")
	}
}
```

**Step 3: Run all tests**

Run: `cd os/Skaffen && go test ./internal/mcp/ -v -timeout 30s`
Expected: ALL PASS

**Step 4: Run full module tests**

Run: `cd os/Skaffen && go test ./... -timeout 60s`
Expected: ALL PASS (no regressions)

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/mcp/doc.go internal/mcp/manager_test.go
git commit -m "feat(mcp): package doc and end-to-end integration test"
```

<verify>
- run: `cd os/Skaffen && go test -race ./internal/mcp/ -v -timeout 30s`
  expect: exit 0
- run: `cd os/Skaffen && go test -race ./... -timeout 60s`
  expect: exit 0
</verify>
