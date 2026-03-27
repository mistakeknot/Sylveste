---
artifact_type: plan
bead: Sylveste-6i0.19
stage: design
requirements:
  - F1: Skill Loader Package
  - F2: Skill Injector
  - F3: Implicit Trigger Matching
  - F4: Skill Pinning
  - F5: TUI Slash Command Invocation
  - F6: /skills Management Command
  - F7: /help and Implicit Activation
  - F8: Agent Loop Integration
---
# Skaffen Skills System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-6i0.19
**Goal:** Add SKILL.md discovery, parsing, and invocation to Skaffen so users can extend agent behavior with reusable instructional documents.

**Architecture:** New `internal/skill/` package handles discovery, parsing, injection, triggers, and pinning. Skills are SKILL.md files with YAML frontmatter discovered from a 4-tier directory hierarchy. Activated skills inject their body as user-role messages into the agent loop, keeping the system prompt stable for Anthropic prompt caching. The TUI wires skill invocation into the existing command dispatch pipeline.

**Tech Stack:** Go 1.24, `gopkg.in/yaml.v3` (new dependency), Bubble Tea TUI framework, existing `internal/command/` pattern as template.

## Prior Learnings

- `docs/plans/2026-02-15-token-efficient-skill-loading.md` — Earlier plan for token-efficient skill loading; validates the lazy-load approach (metadata at startup, body on first activation). Our plan follows the same pattern.
- `internal/command/command.go` — Established pattern for disk-based discovery with graceful degradation (skip bad files, missing dirs return nil). Mirror this pattern exactly for skill loading.

---

## Must-Haves

**Truths** (observable behaviors):
- User can type `/skill-name` in the TUI and the skill's instructions are sent to the agent
- User can type `/skills` and see all discovered skills grouped by source tier
- Skills from `.skaffen/skills/` override same-named skills from `~/.skaffen/skills/`
- Pinned skills persist across turns until explicitly unpinned
- Implicit trigger matching auto-activates skills when user messages contain trigger phrases
- System prompt remains stable when skills are activated (prompt caching preserved)

**Artifacts** (files that must exist):
- [`internal/skill/skill.go`] exports [`Def`, `Loader`, `LoadAll`]
- [`internal/skill/inject.go`] exports [`FormatInjection`]
- [`internal/skill/trigger.go`] exports [`MatchTriggers`]
- [`internal/skill/pin.go`] exports [`Pinner`]
- [`internal/config/config.go`] exports [`SkillDirs`] (method on Config)

**Key Links** (breakage causes cascading failures):
- `config.SkillDirs()` feeds into `skill.LoadAll()` which feeds into `tui.Config.Skills`
- `tui.submitMsg` handler calls `skill.MatchTriggers()` then prepends results to agent prompt
- `tui.executeCommand` default case checks skills map before returning "Unknown command"
- `skill.FormatInjection()` wraps skill body for `appModel.runAgent()` prompt

---

### Task 1: Add YAML dependency

**Files:**
- Modify: `os/Skaffen/go.mod`
- Modify: `os/Skaffen/go.sum` (auto-updated)

**Step 1: Add gopkg.in/yaml.v3 to go.mod**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go get gopkg.in/yaml.v3`

**Step 2: Verify the dependency resolves**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go mod tidy`
Expected: exit 0, `gopkg.in/yaml.v3` appears in go.mod

**Step 3: Commit**

```bash
cd /home/mk/projects/Sylveste/os/Skaffen
git add go.mod go.sum
git commit -m "deps: add gopkg.in/yaml.v3 for SKILL.md frontmatter parsing"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && grep 'yaml.v3' go.mod`
  expect: contains "gopkg.in/yaml.v3"
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./...`
  expect: exit 0
</verify>

---

### Task 2: Add SkillDirs() to config package

**Files:**
- Modify: `os/Skaffen/internal/config/config.go`
- Create: `os/Skaffen/internal/config/config_test.go`

**Step 1: Write the failing test**

Create `os/Skaffen/internal/config/config_test.go`:

```go
package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSkillDirs_AllTiers(t *testing.T) {
	home := t.TempDir()
	project := t.TempDir()

	// Create all 4 skill directory tiers
	os.MkdirAll(filepath.Join(project, ".skaffen", "skills"), 0o755)
	os.MkdirAll(filepath.Join(project, ".skaffen", "plugins", "foo", "skills"), 0o755)
	os.MkdirAll(filepath.Join(home, ".skaffen", "skills"), 0o755)
	os.MkdirAll(filepath.Join(home, ".skaffen", "plugins", "bar", "skills"), 0o755)

	cfg := &Config{
		userDir:    filepath.Join(home, ".skaffen"),
		projectDir: project,
	}

	dirs := cfg.SkillDirs()
	// Should return all 4 tiers that exist
	if len(dirs) < 4 {
		t.Fatalf("got %d dirs, want >= 4: %v", len(dirs), dirs)
	}
}

func TestSkillDirs_MissingDirs(t *testing.T) {
	cfg := &Config{
		userDir:    "/nonexistent/.skaffen",
		projectDir: "",
	}
	dirs := cfg.SkillDirs()
	if len(dirs) != 0 {
		t.Errorf("got %d dirs, want 0 for missing dirs", len(dirs))
	}
}

func TestSkillDirs_NoProjectDir(t *testing.T) {
	home := t.TempDir()
	os.MkdirAll(filepath.Join(home, ".skaffen", "skills"), 0o755)

	cfg := &Config{
		userDir:    filepath.Join(home, ".skaffen"),
		projectDir: "",
	}
	dirs := cfg.SkillDirs()
	if len(dirs) != 1 {
		t.Fatalf("got %d dirs, want 1: %v", len(dirs), dirs)
	}
}

func TestSkillDirs_Precedence(t *testing.T) {
	home := t.TempDir()
	project := t.TempDir()

	os.MkdirAll(filepath.Join(home, ".skaffen", "skills"), 0o755)
	os.MkdirAll(filepath.Join(project, ".skaffen", "skills"), 0o755)

	cfg := &Config{
		userDir:    filepath.Join(home, ".skaffen"),
		projectDir: project,
	}

	dirs := cfg.SkillDirs()
	// User-global dirs come first (lowest precedence), project dirs last (highest)
	// This mirrors CommandDirs() convention — later overrides earlier in LoadAll
	found := false
	for i, d := range dirs {
		if d == filepath.Join(project, ".skaffen", "skills") {
			// Project skill dir should come after user skill dir
			for j := 0; j < i; j++ {
				if dirs[j] == filepath.Join(home, ".skaffen", "skills") {
					found = true
				}
			}
		}
	}
	if !found {
		t.Errorf("project skills should come after user skills for override precedence: %v", dirs)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/config/ -run TestSkillDirs -v`
Expected: FAIL — `cfg.SkillDirs undefined`

**Step 3: Implement SkillDirs**

Add to `os/Skaffen/internal/config/config.go`, after the `CommandDirs()` method (around line 92):

```go
// SkillDirs returns skill directories to scan for SKILL.md files.
// Returns directories in precedence order: user-global first (lowest),
// then per-project (highest) — matching CommandDirs() convention.
// Plugin skill directories (plugins/*/skills/) are expanded via glob.
// Returns only directories that exist on disk.
func (c *Config) SkillDirs() []string {
	var dirs []string

	// Tier 3: user-global skills (lowest precedence)
	userSkills := filepath.Join(c.userDir, "skills")
	if dirExists(userSkills) {
		dirs = append(dirs, userSkills)
	}

	// Tier 4: user-global plugin skills
	userPluginGlob := filepath.Join(c.userDir, "plugins", "*", "skills")
	if matches, err := filepath.Glob(userPluginGlob); err == nil {
		for _, m := range matches {
			if dirExists(m) {
				dirs = append(dirs, m)
			}
		}
	}

	if c.projectDir == "" {
		return dirs
	}

	// Tier 1: per-project skills (highest precedence)
	projSkills := filepath.Join(c.projectDir, ".skaffen", "skills")
	if dirExists(projSkills) {
		dirs = append(dirs, projSkills)
	}

	// Tier 2: per-project plugin skills
	projPluginGlob := filepath.Join(c.projectDir, ".skaffen", "plugins", "*", "skills")
	if matches, err := filepath.Glob(projPluginGlob); err == nil {
		for _, m := range matches {
			if dirExists(m) {
				dirs = append(dirs, m)
			}
		}
	}

	return dirs
}
```

**Step 4: Run test to verify it passes**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/config/ -run TestSkillDirs -v`
Expected: PASS

**Step 5: Commit**

```bash
cd /home/mk/projects/Sylveste/os/Skaffen
git add internal/config/config.go internal/config/config_test.go
git commit -m "feat(config): add SkillDirs() for 4-tier skill discovery paths"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/config/ -v`
  expect: exit 0
</verify>

---

### Task 3: Skill Loader — types, parsing, discovery (F1)

**Files:**
- Create: `os/Skaffen/internal/skill/skill.go`
- Create: `os/Skaffen/internal/skill/skill_test.go`

**Step 1: Write the failing tests**

Create `os/Skaffen/internal/skill/skill_test.go`:

```go
package skill

import (
	"os"
	"path/filepath"
	"testing"
)

// helper: write a SKILL.md with frontmatter + body
func writeSkill(t *testing.T, dir, name, content string) {
	t.Helper()
	skillDir := filepath.Join(dir, name)
	os.MkdirAll(skillDir, 0o755)
	os.WriteFile(filepath.Join(skillDir, "SKILL.md"), []byte(content), 0o644)
}

func TestLoadDir_BasicSkill(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "commit-review", `---
name: commit-review
description: Review staged changes for quality issues
---
Review the staged git diff and suggest improvements.
`)

	defs := LoadDir(dir, "project")
	if len(defs) != 1 {
		t.Fatalf("got %d defs, want 1", len(defs))
	}
	d := defs[0]
	if d.Name != "commit-review" {
		t.Errorf("Name = %q, want commit-review", d.Name)
	}
	if d.Description != "Review staged changes for quality issues" {
		t.Errorf("Description = %q", d.Description)
	}
	if d.UserInvocable != true {
		t.Error("UserInvocable should default to true")
	}
	if d.Source != "project" {
		t.Errorf("Source = %q, want project", d.Source)
	}
	if d.Body != "" {
		t.Error("Body should be empty before activation (lazy load)")
	}
}

func TestLoadDir_RichFrontmatter(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "code-review", `---
name: code-review
description: Review code for quality
user_invocable: false
triggers:
  - review this code
  - check my code
args: "[file_pattern]"
model: opus
---
Body content here.
`)

	defs := LoadDir(dir, "user")
	if len(defs) != 1 {
		t.Fatalf("got %d defs, want 1", len(defs))
	}
	d := defs[0]
	if d.UserInvocable != false {
		t.Error("UserInvocable should be false")
	}
	if len(d.Triggers) != 2 {
		t.Fatalf("got %d triggers, want 2", len(d.Triggers))
	}
	if d.Triggers[0] != "review this code" {
		t.Errorf("Triggers[0] = %q", d.Triggers[0])
	}
	if d.Args != "[file_pattern]" {
		t.Errorf("Args = %q", d.Args)
	}
	if d.Model != "opus" {
		t.Errorf("Model = %q", d.Model)
	}
}

func TestLoadDir_MissingDir(t *testing.T) {
	defs := LoadDir("/nonexistent/skills", "user")
	if len(defs) != 0 {
		t.Errorf("got %d defs, want 0 for missing dir", len(defs))
	}
}

func TestLoadDir_MissingName(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "bad-skill", `---
description: Missing name field
---
Body.
`)

	defs := LoadDir(dir, "user")
	if len(defs) != 0 {
		t.Errorf("got %d defs, want 0 (missing name)", len(defs))
	}
}

func TestLoadDir_MissingDescription(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "bad-skill", `---
name: bad-skill
---
Body.
`)

	defs := LoadDir(dir, "user")
	if len(defs) != 0 {
		t.Errorf("got %d defs, want 0 (missing description)", len(defs))
	}
}

func TestLoadDir_BadFrontmatter(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "bad", `---
{invalid yaml
---
Body.
`)

	defs := LoadDir(dir, "user")
	if len(defs) != 0 {
		t.Errorf("got %d defs, want 0 (bad YAML)", len(defs))
	}
}

func TestLoadDir_NoFrontmatter(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "plain", `Just a plain markdown file with no frontmatter.`)

	defs := LoadDir(dir, "user")
	if len(defs) != 0 {
		t.Errorf("got %d defs, want 0 (no frontmatter)", len(defs))
	}
}

func TestLoadDir_MultipleSkills(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "alpha", "---\nname: alpha\ndescription: Alpha skill\n---\nAlpha body.\n")
	writeSkill(t, dir, "beta", "---\nname: beta\ndescription: Beta skill\n---\nBeta body.\n")

	defs := LoadDir(dir, "user")
	if len(defs) != 2 {
		t.Fatalf("got %d defs, want 2", len(defs))
	}
}

func TestLoadAll_Shadowing(t *testing.T) {
	userDir := t.TempDir()
	projDir := t.TempDir()

	writeSkill(t, userDir, "review", "---\nname: review\ndescription: User review\n---\nUser body.\n")
	writeSkill(t, userDir, "deploy", "---\nname: deploy\ndescription: Deploy helper\n---\nDeploy body.\n")
	writeSkill(t, projDir, "review", "---\nname: review\ndescription: Project review\n---\nProject body.\n")

	loader := LoadAll(userDir, projDir)
	if len(loader) != 2 {
		t.Fatalf("got %d skills, want 2", len(loader))
	}

	review := loader["review"]
	if review.Source != "project" {
		t.Errorf("review.Source = %q, want project (higher precedence)", review.Source)
	}
	if review.Description != "Project review" {
		t.Errorf("review.Description = %q", review.Description)
	}

	deploy := loader["deploy"]
	if deploy.Source != "user" {
		t.Errorf("deploy.Source = %q, want user", deploy.Source)
	}
}

func TestLoadBody_LazyLoad(t *testing.T) {
	dir := t.TempDir()
	body := "This is the skill body with instructions.\nLine 2.\n"
	writeSkill(t, dir, "test-skill", "---\nname: test-skill\ndescription: Test\n---\n"+body)

	defs := LoadDir(dir, "user")
	if len(defs) != 1 {
		t.Fatalf("got %d defs, want 1", len(defs))
	}

	// Body should be empty before LoadBody
	if defs[0].Body != "" {
		t.Error("Body should be empty before LoadBody")
	}

	// Load body
	got, err := LoadBody(&defs[0])
	if err != nil {
		t.Fatalf("LoadBody error: %v", err)
	}
	if got != body {
		t.Errorf("Body = %q, want %q", got, body)
	}
	// Should be cached
	if defs[0].Body != body {
		t.Error("Body should be cached after LoadBody")
	}

	// Second call returns cached
	got2, err := LoadBody(&defs[0])
	if err != nil {
		t.Fatalf("LoadBody (cached) error: %v", err)
	}
	if got2 != got {
		t.Error("Cached body should match")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/skill/ -v`
Expected: FAIL — package not found

**Step 3: Implement the skill loader**

Create `os/Skaffen/internal/skill/skill.go`:

```go
// Package skill discovers, parses, and manages SKILL.md instruction files
// from a 4-tier directory hierarchy. Skills are instructional markdown
// documents with YAML frontmatter — not executable code.
//
// Discovery is eager (scan dirs, parse frontmatter at startup).
// Body loading is lazy (read full file on first activation, then cached).
package skill

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// Def is a parsed skill definition from a SKILL.md file.
type Def struct {
	Name          string   // skill identifier, used as slash command name
	Description   string   // one-line description for help and metadata
	UserInvocable bool     // true = user can invoke via /name
	Triggers      []string // implicit activation trigger phrases
	Args          string   // argument hint for help display
	Model         string   // preferred model hint (optional)
	Source        string   // source tier: "project", "project-plugin", "user", "user-plugin"
	Path          string   // filesystem path to the SKILL.md file
	Body          string   // skill body (empty until LoadBody is called)
}

// frontmatter is the YAML structure at the top of a SKILL.md file.
type frontmatter struct {
	Name          string   `yaml:"name"`
	Description   string   `yaml:"description"`
	UserInvocable *bool    `yaml:"user_invocable"` // pointer to detect absence (default true)
	Triggers      []string `yaml:"triggers"`
	Args          string   `yaml:"args"`
	Model         string   `yaml:"model"`
}

// LoadDir reads all SKILL.md files from subdirectories of dir.
// Each skill lives in its own subdirectory: dir/<skill-name>/SKILL.md.
// source is a tier label for display ("user", "project", etc.).
// Returns empty slice (not error) if the directory doesn't exist.
// Malformed skills are skipped with a warning on stderr.
func LoadDir(dir, source string) []Def {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}

	var defs []Def
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		skillPath := filepath.Join(dir, e.Name(), "SKILL.md")
		if _, err := os.Stat(skillPath); err != nil {
			continue
		}

		def, err := parseSkill(skillPath, source)
		if err != nil {
			fmt.Fprintf(os.Stderr, "skaffen: warning: skill %q: %v (skipping)\n", e.Name(), err)
			continue
		}
		defs = append(defs, def)
	}
	return defs
}

// parseSkill reads a SKILL.md file and parses its YAML frontmatter.
// The body is NOT loaded — only metadata is parsed (lazy loading).
func parseSkill(path, source string) (Def, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Def{}, fmt.Errorf("read: %w", err)
	}

	fm, err := parseFrontmatter(data)
	if err != nil {
		return Def{}, err
	}

	if fm.Name == "" {
		return Def{}, fmt.Errorf("missing required field 'name'")
	}
	if fm.Description == "" {
		return Def{}, fmt.Errorf("missing required field 'description'")
	}

	invocable := true
	if fm.UserInvocable != nil {
		invocable = *fm.UserInvocable
	}

	return Def{
		Name:          fm.Name,
		Description:   fm.Description,
		UserInvocable: invocable,
		Triggers:      fm.Triggers,
		Args:          fm.Args,
		Model:         fm.Model,
		Source:        source,
		Path:          path,
	}, nil
}

// parseFrontmatter extracts and parses YAML frontmatter delimited by "---".
func parseFrontmatter(data []byte) (frontmatter, error) {
	// Must start with "---"
	trimmed := bytes.TrimSpace(data)
	if !bytes.HasPrefix(trimmed, []byte("---")) {
		return frontmatter{}, fmt.Errorf("no YAML frontmatter (must start with ---)")
	}

	// Find closing "---"
	rest := trimmed[3:]
	rest = bytes.TrimLeft(rest, "\r\n")
	idx := bytes.Index(rest, []byte("\n---"))
	if idx < 0 {
		return frontmatter{}, fmt.Errorf("no closing --- for frontmatter")
	}

	yamlBytes := rest[:idx]
	var fm frontmatter
	if err := yaml.Unmarshal(yamlBytes, &fm); err != nil {
		return frontmatter{}, fmt.Errorf("parse frontmatter: %w", err)
	}
	return fm, nil
}

// LoadBody lazily loads and caches the skill body (everything after frontmatter).
// Returns the cached body on subsequent calls.
func LoadBody(d *Def) (string, error) {
	if d.Body != "" {
		return d.Body, nil
	}

	data, err := os.ReadFile(d.Path)
	if err != nil {
		return "", fmt.Errorf("read skill body: %w", err)
	}

	body := extractBody(data)
	d.Body = body
	return body, nil
}

// extractBody returns everything after the closing "---" of the frontmatter.
func extractBody(data []byte) string {
	trimmed := bytes.TrimSpace(data)
	if !bytes.HasPrefix(trimmed, []byte("---")) {
		return string(data) // no frontmatter, entire file is body
	}

	rest := trimmed[3:]
	rest = bytes.TrimLeft(rest, "\r\n")
	idx := bytes.Index(rest, []byte("\n---"))
	if idx < 0 {
		return "" // no closing delimiter
	}

	body := rest[idx+4:] // skip past "\n---"
	return strings.TrimLeft(string(body), "\r\n")
}

// LoadAll loads skills from multiple directories and merges them.
// Later directories override earlier ones on name collision (project > user).
// Returns a map keyed by skill name.
func LoadAll(dirs ...string) map[string]Def {
	sources := []string{"user", "user-plugin", "project", "project-plugin"}
	result := make(map[string]Def)
	for i, dir := range dirs {
		source := "user"
		if i < len(sources) {
			source = sources[i]
		} else {
			source = "project"
		}
		for _, def := range LoadDir(dir, source) {
			result[def.Name] = def
		}
	}
	return result
}
```

**Step 4: Run test to verify it passes**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/skill/ -v`
Expected: PASS

**Step 5: Commit**

```bash
cd /home/mk/projects/Sylveste/os/Skaffen
git add internal/skill/skill.go internal/skill/skill_test.go
git commit -m "feat(skill): add SKILL.md loader with frontmatter parsing and lazy body loading"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/skill/ -v`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go vet ./internal/skill/`
  expect: exit 0
</verify>

---

### Task 4: Skill Injector (F2)

**Files:**
- Create: `os/Skaffen/internal/skill/inject.go`
- Modify: `os/Skaffen/internal/skill/skill_test.go` (add injection tests)

**Step 1: Write the failing tests**

Append to `os/Skaffen/internal/skill/skill_test.go`:

```go
func TestFormatInjection_Basic(t *testing.T) {
	d := &Def{
		Name:        "test-skill",
		Description: "A test skill",
		Path:        "/fake/path/SKILL.md",
		Body:        "Do the thing.\nSecond line.\n",
	}

	msg := FormatInjection(d, "")
	if !strings.Contains(msg, "test-skill") {
		t.Error("injection should contain skill name")
	}
	if !strings.Contains(msg, "Do the thing.") {
		t.Error("injection should contain skill body")
	}
}

func TestFormatInjection_WithArgs(t *testing.T) {
	d := &Def{
		Name: "review",
		Body: "Review the code.\n",
	}

	msg := FormatInjection(d, "src/main.go")
	if !strings.Contains(msg, "src/main.go") {
		t.Error("injection should contain user arguments")
	}
	if !strings.Contains(msg, "Review the code.") {
		t.Error("injection should contain body")
	}
}

func TestFormatInjection_SizeLimit(t *testing.T) {
	d := &Def{
		Name: "huge",
		Body: strings.Repeat("x", MaxBodyChars+1),
	}

	_, err := FormatInjectionSafe(d, "")
	if err == nil {
		t.Error("expected error for oversized body")
	}
}

func TestFormatInjection_EmptyBody(t *testing.T) {
	d := &Def{
		Name:        "empty",
		Description: "Empty skill",
	}

	msg := FormatInjection(d, "")
	// Should still produce a message (metadata tags, just no body)
	if msg == "" {
		t.Error("injection should produce output even with empty body")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/skill/ -run TestFormatInjection -v`
Expected: FAIL — `FormatInjection` undefined

**Step 3: Implement the injector**

Create `os/Skaffen/internal/skill/inject.go`:

```go
package skill

import (
	"fmt"
	"strings"
)

// MaxBodyChars is the per-skill body size cap (~5K tokens ≈ 15K chars).
const MaxBodyChars = 15000

// FormatInjection formats a skill's content for injection as a user-role message.
// If args is non-empty, it is appended after the skill body.
func FormatInjection(d *Def, args string) string {
	var b strings.Builder
	b.WriteString(fmt.Sprintf("<skill name=%q>\n", d.Name))
	if d.Body != "" {
		b.WriteString(d.Body)
		if !strings.HasSuffix(d.Body, "\n") {
			b.WriteString("\n")
		}
	}
	if args != "" {
		b.WriteString("\nARGUMENTS: ")
		b.WriteString(args)
		b.WriteString("\n")
	}
	b.WriteString("</skill>\n")
	return b.String()
}

// FormatInjectionSafe is like FormatInjection but returns an error if the
// skill body exceeds MaxBodyChars.
func FormatInjectionSafe(d *Def, args string) (string, error) {
	if len(d.Body) > MaxBodyChars {
		return "", fmt.Errorf("skill %q body is %d chars (max %d)", d.Name, len(d.Body), MaxBodyChars)
	}
	return FormatInjection(d, args), nil
}
```

**Step 4: Add `strings` import to test file if not already present, then run tests**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/skill/ -run TestFormatInjection -v`
Expected: PASS

**Step 5: Commit**

```bash
cd /home/mk/projects/Sylveste/os/Skaffen
git add internal/skill/inject.go internal/skill/skill_test.go
git commit -m "feat(skill): add injection formatter with size limit enforcement"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/skill/ -v`
  expect: exit 0
</verify>

---

### Task 5: Implicit Trigger Matching (F3)

**Files:**
- Create: `os/Skaffen/internal/skill/trigger.go`
- Modify: `os/Skaffen/internal/skill/skill_test.go` (add trigger tests)

**Step 1: Write the failing tests**

Append to `os/Skaffen/internal/skill/skill_test.go`:

```go
func TestMatchTriggers_SingleMatch(t *testing.T) {
	skills := map[string]Def{
		"review": {
			Name:          "review",
			UserInvocable: true,
			Triggers:      []string{"review my code", "check changes"},
		},
		"deploy": {
			Name:          "deploy",
			UserInvocable: true,
			Triggers:      []string{"deploy to prod"},
		},
	}

	matched := MatchTriggers(skills, "can you review my code please?")
	if len(matched) != 1 {
		t.Fatalf("got %d matches, want 1", len(matched))
	}
	if matched[0].Name != "review" {
		t.Errorf("matched %q, want review", matched[0].Name)
	}
}

func TestMatchTriggers_MultiMatch(t *testing.T) {
	skills := map[string]Def{
		"review": {
			Name:          "review",
			UserInvocable: true,
			Triggers:      []string{"review"},
		},
		"test": {
			Name:          "test",
			UserInvocable: true,
			Triggers:      []string{"review"},
		},
	}

	matched := MatchTriggers(skills, "please review this")
	if len(matched) != 2 {
		t.Fatalf("got %d matches, want 2", len(matched))
	}
}

func TestMatchTriggers_CaseInsensitive(t *testing.T) {
	skills := map[string]Def{
		"review": {
			Name:          "review",
			UserInvocable: true,
			Triggers:      []string{"Review My Code"},
		},
	}

	matched := MatchTriggers(skills, "review my code")
	if len(matched) != 1 {
		t.Fatalf("got %d matches, want 1 (case insensitive)", len(matched))
	}
}

func TestMatchTriggers_NoMatch(t *testing.T) {
	skills := map[string]Def{
		"review": {
			Name:          "review",
			UserInvocable: true,
			Triggers:      []string{"review my code"},
		},
	}

	matched := MatchTriggers(skills, "deploy to production")
	if len(matched) != 0 {
		t.Errorf("got %d matches, want 0", len(matched))
	}
}

func TestMatchTriggers_SkipsNonInvocable(t *testing.T) {
	skills := map[string]Def{
		"internal": {
			Name:          "internal",
			UserInvocable: false,
			Triggers:      []string{"do something"},
		},
	}

	matched := MatchTriggers(skills, "do something")
	if len(matched) != 0 {
		t.Errorf("got %d matches, want 0 (user_invocable=false should be skipped)", len(matched))
	}
}

func TestMatchTriggers_NoTriggers(t *testing.T) {
	skills := map[string]Def{
		"manual": {
			Name:          "manual",
			UserInvocable: true,
			Triggers:      nil,
		},
	}

	matched := MatchTriggers(skills, "anything at all")
	if len(matched) != 0 {
		t.Errorf("got %d matches, want 0 (no triggers defined)", len(matched))
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/skill/ -run TestMatchTriggers -v`
Expected: FAIL — `MatchTriggers` undefined

**Step 3: Implement trigger matching**

Create `os/Skaffen/internal/skill/trigger.go`:

```go
package skill

import "strings"

// MatchTriggers checks a user message against all skill trigger phrases.
// Returns skills whose triggers match (case-insensitive substring).
// Only matches skills where UserInvocable is true.
// Complexity: O(skills × triggers) — acceptable for <100 skills.
func MatchTriggers(skills map[string]Def, message string) []Def {
	lower := strings.ToLower(message)
	var matched []Def
	for _, d := range skills {
		if !d.UserInvocable {
			continue
		}
		for _, trigger := range d.Triggers {
			if strings.Contains(lower, strings.ToLower(trigger)) {
				matched = append(matched, d)
				break // one trigger match per skill is enough
			}
		}
	}
	return matched
}
```

**Step 4: Run tests to verify they pass**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/skill/ -run TestMatchTriggers -v`
Expected: PASS

**Step 5: Commit**

```bash
cd /home/mk/projects/Sylveste/os/Skaffen
git add internal/skill/trigger.go internal/skill/skill_test.go
git commit -m "feat(skill): add implicit trigger matching with case-insensitive substring"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/skill/ -v`
  expect: exit 0
</verify>

---

### Task 6: Skill Pinning (F4)

**Files:**
- Create: `os/Skaffen/internal/skill/pin.go`
- Modify: `os/Skaffen/internal/skill/skill_test.go` (add pin tests)

**Step 1: Write the failing tests**

Append to `os/Skaffen/internal/skill/skill_test.go`:

```go
func TestPinner_PinUnpin(t *testing.T) {
	skills := map[string]Def{
		"review": {Name: "review"},
		"deploy": {Name: "deploy"},
	}
	p := NewPinner(skills)

	// Pin
	if err := p.Pin("review"); err != nil {
		t.Fatalf("Pin error: %v", err)
	}
	pinned := p.Pinned()
	if len(pinned) != 1 || pinned[0] != "review" {
		t.Errorf("Pinned = %v, want [review]", pinned)
	}

	// Unpin
	p.Unpin("review")
	if len(p.Pinned()) != 0 {
		t.Error("Pinned should be empty after unpin")
	}
}

func TestPinner_DuplicatePin(t *testing.T) {
	skills := map[string]Def{"review": {Name: "review"}}
	p := NewPinner(skills)

	p.Pin("review")
	p.Pin("review") // duplicate — should be a no-op
	if len(p.Pinned()) != 1 {
		t.Error("duplicate pin should not add twice")
	}
}

func TestPinner_PinNonExistent(t *testing.T) {
	skills := map[string]Def{"review": {Name: "review"}}
	p := NewPinner(skills)

	err := p.Pin("nonexistent")
	if err == nil {
		t.Error("expected error for non-existent skill")
	}
}

func TestPinner_UnpinNonExistent(t *testing.T) {
	skills := map[string]Def{"review": {Name: "review"}}
	p := NewPinner(skills)

	// Should not panic
	p.Unpin("nonexistent")
}

func TestPinner_MultiplePins(t *testing.T) {
	skills := map[string]Def{
		"review": {Name: "review"},
		"deploy": {Name: "deploy"},
		"test":   {Name: "test"},
	}
	p := NewPinner(skills)

	p.Pin("review")
	p.Pin("deploy")

	pinned := p.Pinned()
	if len(pinned) != 2 {
		t.Fatalf("got %d pinned, want 2", len(pinned))
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/skill/ -run TestPinner -v`
Expected: FAIL — `NewPinner` undefined

**Step 3: Implement pinning**

Create `os/Skaffen/internal/skill/pin.go`:

```go
package skill

import (
	"fmt"
	"sort"
)

// Pinner manages session-scoped skill pinning.
// Pinned skills are re-injected as user-role messages on every turn.
type Pinner struct {
	skills map[string]Def
	pinned map[string]bool
}

// NewPinner creates a Pinner backed by the given skills map.
func NewPinner(skills map[string]Def) *Pinner {
	return &Pinner{
		skills: skills,
		pinned: make(map[string]bool),
	}
}

// Pin adds a skill to the pinned set. Returns error if skill doesn't exist.
func (p *Pinner) Pin(name string) error {
	if _, ok := p.skills[name]; !ok {
		return fmt.Errorf("skill %q not found", name)
	}
	p.pinned[name] = true
	return nil
}

// Unpin removes a skill from the pinned set. No-op if not pinned.
func (p *Pinner) Unpin(name string) {
	delete(p.pinned, name)
}

// Pinned returns the list of currently pinned skill names, sorted.
func (p *Pinner) Pinned() []string {
	names := make([]string, 0, len(p.pinned))
	for name := range p.pinned {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// IsPinned returns whether a skill is currently pinned.
func (p *Pinner) IsPinned(name string) bool {
	return p.pinned[name]
}
```

**Step 4: Run tests to verify they pass**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/skill/ -run TestPinner -v`
Expected: PASS

**Step 5: Commit**

```bash
cd /home/mk/projects/Sylveste/os/Skaffen
git add internal/skill/pin.go internal/skill/skill_test.go
git commit -m "feat(skill): add session-scoped skill pinning"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./internal/skill/ -v`
  expect: exit 0
</verify>

---

### Task 7: Wire skill loading into main.go and TUI Config

**Files:**
- Modify: `os/Skaffen/cmd/skaffen/main.go` (add skill loading)
- Modify: `os/Skaffen/internal/tui/app.go` (add Skills to Config and appModel)

**Step 1: Add Skills field to tui.Config and appModel**

In `os/Skaffen/internal/tui/app.go`, add to the `Config` struct (after `CustomCommands`):

```go
Skills         map[string]skill.Def
```

Add import for `"github.com/mistakeknot/Skaffen/internal/skill"`.

Add to the `appModel` struct (after `customCmds`):

```go
	// Skills loaded from SKILL.md files
	skills map[string]skill.Def
	pinner *skill.Pinner
```

In `newAppModel`, add after `customCmds: cfg.CustomCommands`:

```go
		skills:     cfg.Skills,
		pinner:     skill.NewPinner(cfg.Skills),
```

Also pass skills to the prompt model (for tab completion) and the command completer. In `newAppModel`, add after `pm.customCmds = cfg.CustomCommands`:

```go
	pm.skills = cfg.Skills
```

**Step 2: Wire skill loading in main.go**

In `os/Skaffen/cmd/skaffen/main.go`, add import for `"github.com/mistakeknot/Skaffen/internal/skill"`.

After line 387 (`customCmds := command.LoadAll(cfg.CommandDirs()...)`), add:

```go
	// Load skills from SKILL.md files
	skills := skill.LoadAll(cfg.SkillDirs()...)
```

In the `tui.Run(tui.Config{...})` call, add the Skills field:

```go
		Skills:         skills,
```

**Step 3: Verify everything compiles**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./...`
Expected: exit 0

**Step 4: Commit**

```bash
cd /home/mk/projects/Sylveste/os/Skaffen
git add cmd/skaffen/main.go internal/tui/app.go
git commit -m "feat: wire skill loading into main.go and TUI config"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./...`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go vet ./...`
  expect: exit 0
</verify>

---

### Task 8: TUI Slash Command Invocation (F5)

**Files:**
- Modify: `os/Skaffen/internal/tui/commands.go` (add skill dispatch in default case)
- Modify: `os/Skaffen/internal/tui/app.go` (wire skill injection into submitMsg → runAgent)

**Step 1: Add skill dispatch to executeCommand**

In `os/Skaffen/internal/tui/commands.go`, in the `default:` case of `executeCommand` (around line 176), add skill lookup between the custom command check and the "Unknown command" error:

```go
	default:
		// Check custom commands loaded from disk
		if def, ok := m.customCmds[cmd.Name]; ok {
			return m.execCustomCommand(def, cmd.Args)
		}
		// Check skills
		if sd, ok := m.skills[strings.ToLower(cmd.Name)]; ok {
			return m.execSkill(sd, cmd.Args)
		}
		return CommandResult{
			Message: fmt.Sprintf("Unknown command /%s. Type /help for available commands.", cmd.Name),
			IsError: true,
		}
```

Add the `execSkill` method to commands.go:

```go
// execSkill activates a skill via slash command invocation.
// The skill body is loaded, formatted, and returned as a message
// for the submitMsg handler to send to the agent.
func (m *appModel) execSkill(d skill.Def, args []string) CommandResult {
	// Handle --pin flag
	pin := false
	filteredArgs := make([]string, 0, len(args))
	for _, a := range args {
		if a == "--pin" {
			pin = true
		} else {
			filteredArgs = append(filteredArgs, a)
		}
	}

	// Lazy-load body
	body, err := skill.LoadBody(&d)
	if err != nil {
		return CommandResult{
			Message: fmt.Sprintf("Failed to load skill %q: %v", d.Name, err),
			IsError: true,
		}
	}

	// Update the cached def with the loaded body
	d.Body = body
	m.skills[d.Name] = d

	// Check size limit
	argStr := strings.Join(filteredArgs, " ")
	msg, err := skill.FormatInjectionSafe(&d, argStr)
	if err != nil {
		return CommandResult{Message: err.Error(), IsError: true}
	}

	// Pin if requested
	if pin {
		if err := m.pinner.Pin(d.Name); err != nil {
			return CommandResult{
				Message: fmt.Sprintf("Skill activated but pin failed: %v", err),
				IsError: true,
			}
		}
	}

	// Store the pending skill injection for the next runAgent call
	m.pendingSkills = append(m.pendingSkills, msg)

	status := fmt.Sprintf("[skill: %s]", d.Name)
	if pin {
		status += " (pinned)"
	}
	return CommandResult{Message: status}
}
```

Add import for `"github.com/mistakeknot/Skaffen/internal/skill"` to commands.go.

**Step 2: Add pendingSkills field to appModel**

In `os/Skaffen/internal/tui/app.go`, add to the `appModel` struct:

```go
	// Pending skill injections to prepend to next agent call
	pendingSkills []string
```

**Step 3: Modify submitMsg handler to inject skills**

In `os/Skaffen/internal/tui/app.go`, in the `submitMsg` case (around line 317, after the slash command check), modify the agent dispatch section:

Replace the existing block starting at `m.running = true` through `cmds = append(cmds, m.runAgent(expanded))`:

```go
		m.running = true
		// Render user message (original text with @mentions)
		userStyle := lipgloss.NewStyle().Foreground(theme.Current().Semantic().Primary.Color()).Bold(true)
		m.viewport.AppendContent("\n" + userStyle.Render("You") + "\n" + msg.Text + "\n")
		// Expand @file mentions before sending to agent
		expanded := expandAtMentions(msg.Text, m.workDir)
		// Prepend any pending skill injections + pinned skill injections
		prompt := m.buildSkillPrompt(expanded)
		cmds = append(cmds, m.runAgent(prompt))
```

Also modify the `commandResultMsg` handler. When a skill command returns a non-error message, we need the TUI to send the pending skills to the agent. Change the `commandResultMsg` case to handle skill activation:

In the `commandResultMsg` handler, after displaying the message, check if there are pending skills and auto-submit them:

```go
	case commandResultMsg:
		if msg.IsError {
			errStyle := lipgloss.NewStyle().Foreground(theme.Current().Semantic().Error.Color())
			m.viewport.AppendContent(errStyle.Render(msg.Message) + "\n")
		} else if msg.Message != "" {
			m.viewport.AppendContent(msg.Message + "\n")
		}
		if msg.Quit {
			return m, tea.Quit
		}
		// If skills were activated by a /skill-name command, auto-submit
		if len(m.pendingSkills) > 0 && !m.running {
			m.running = true
			prompt := m.buildSkillPrompt("")
			cmds = append(cmds, m.runAgent(prompt))
		}
```

Add the `buildSkillPrompt` method to app.go:

```go
// buildSkillPrompt prepends pending + pinned skill injections to the user prompt.
func (m *appModel) buildSkillPrompt(userPrompt string) string {
	var parts []string

	// Pinned skills (re-injected every turn)
	for _, name := range m.pinner.Pinned() {
		if d, ok := m.skills[name]; ok {
			body, err := skill.LoadBody(&d)
			if err != nil {
				continue
			}
			d.Body = body
			m.skills[name] = d
			parts = append(parts, skill.FormatInjection(&d, ""))
		}
	}

	// Pending one-shot skills (from slash command invocation or trigger matching)
	parts = append(parts, m.pendingSkills...)
	m.pendingSkills = nil // clear after consumption

	if userPrompt != "" {
		parts = append(parts, userPrompt)
	}

	return strings.Join(parts, "\n")
}
```

**Step 4: Verify everything compiles**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./...`
Expected: exit 0

**Step 5: Commit**

```bash
cd /home/mk/projects/Sylveste/os/Skaffen
git add internal/tui/commands.go internal/tui/app.go
git commit -m "feat(tui): wire skill slash command invocation with --pin support"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./...`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go vet ./...`
  expect: exit 0
</verify>

---

### Task 9: /skills Management Command (F6)

**Files:**
- Modify: `os/Skaffen/internal/tui/commands.go` (add /skills command)

**Step 1: Add /skills to KnownCommands**

In `KnownCommands()`, add:

```go
"skills": "List, inspect, pin, and manage skills",
```

**Step 2: Add /skills case to executeCommand**

In `executeCommand`, add a new case before the `default:` block:

```go
	case "skills":
		return m.execSkills(cmd.Args)
```

**Step 3: Implement execSkills**

Add to commands.go:

```go
// execSkills handles the /skills management command.
func (m *appModel) execSkills(args []string) CommandResult {
	if len(args) == 0 || args[0] == "list" {
		return m.execSkillsList()
	}
	switch args[0] {
	case "info":
		if len(args) < 2 {
			return CommandResult{Message: "Usage: /skills info <name>", IsError: true}
		}
		return m.execSkillsInfo(args[1])
	case "pin":
		if len(args) < 2 {
			return CommandResult{Message: "Usage: /skills pin <name>", IsError: true}
		}
		return m.execSkillsPin(args[1])
	case "unpin":
		if len(args) < 2 {
			return CommandResult{Message: "Usage: /skills unpin <name>", IsError: true}
		}
		m.pinner.Unpin(args[1])
		return CommandResult{Message: fmt.Sprintf("Unpinned skill %q.", args[1])}
	case "pinned":
		pinned := m.pinner.Pinned()
		if len(pinned) == 0 {
			return CommandResult{Message: "No pinned skills."}
		}
		return CommandResult{Message: "Pinned skills:\n  " + strings.Join(pinned, "\n  ")}
	default:
		return CommandResult{
			Message: "Usage: /skills [list|info <name>|pin <name>|unpin <name>|pinned]",
			IsError: true,
		}
	}
}

func (m *appModel) execSkillsList() CommandResult {
	if len(m.skills) == 0 {
		return CommandResult{Message: "No skills discovered."}
	}

	// Group by source tier
	groups := make(map[string][]skill.Def)
	for _, d := range m.skills {
		groups[d.Source] = append(groups[d.Source], d)
	}

	tierOrder := []struct{ key, label string }{
		{"project", "Project (.skaffen/skills/)"},
		{"project-plugin", "Project Plugins (.skaffen/plugins/*/skills/)"},
		{"user", "User (~/.skaffen/skills/)"},
		{"user-plugin", "User Plugins (~/.skaffen/plugins/*/skills/)"},
	}

	var b strings.Builder
	b.WriteString("Skills:\n")
	for _, tier := range tierOrder {
		defs, ok := groups[tier.key]
		if !ok || len(defs) == 0 {
			continue
		}
		b.WriteString(fmt.Sprintf("\n  %s:\n", tier.label))
		// Sort by name
		sort.Slice(defs, func(i, j int) bool { return defs[i].Name < defs[j].Name })
		for _, d := range defs {
			pinned := ""
			if m.pinner.IsPinned(d.Name) {
				pinned = " (pinned)"
			}
			b.WriteString(fmt.Sprintf("    /%s — %s%s\n", d.Name, d.Description, pinned))
		}
	}
	return CommandResult{Message: b.String()}
}

func (m *appModel) execSkillsInfo(name string) CommandResult {
	d, ok := m.skills[name]
	if !ok {
		return CommandResult{
			Message: fmt.Sprintf("Skill %q not found.", name),
			IsError: true,
		}
	}

	var b strings.Builder
	b.WriteString(fmt.Sprintf("Skill: %s\n", d.Name))
	b.WriteString(fmt.Sprintf("  Description: %s\n", d.Description))
	b.WriteString(fmt.Sprintf("  Source: %s\n", d.Source))
	b.WriteString(fmt.Sprintf("  Invocable: %v\n", d.UserInvocable))
	if len(d.Triggers) > 0 {
		b.WriteString(fmt.Sprintf("  Triggers: %s\n", strings.Join(d.Triggers, ", ")))
	}
	if d.Args != "" {
		b.WriteString(fmt.Sprintf("  Args: %s\n", d.Args))
	}
	if d.Model != "" {
		b.WriteString(fmt.Sprintf("  Model: %s\n", d.Model))
	}
	b.WriteString(fmt.Sprintf("  Path: %s\n", d.Path))

	// Body preview (first 3 lines)
	body, err := skill.LoadBody(&d)
	if err == nil && body != "" {
		m.skills[name] = d // cache loaded body
		lines := strings.SplitN(body, "\n", 4)
		if len(lines) > 3 {
			lines = lines[:3]
		}
		b.WriteString("  Preview:\n")
		for _, line := range lines {
			b.WriteString(fmt.Sprintf("    %s\n", line))
		}
	}

	return CommandResult{Message: b.String()}
}

func (m *appModel) execSkillsPin(name string) CommandResult {
	if err := m.pinner.Pin(name); err != nil {
		return CommandResult{Message: err.Error(), IsError: true}
	}
	return CommandResult{Message: fmt.Sprintf("Pinned skill %q for this session.", name)}
}
```

Add `"sort"` to imports if not already present. Add `"github.com/mistakeknot/Skaffen/internal/skill"` import if not already added in Task 8.

**Step 4: Verify everything compiles**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./...`
Expected: exit 0

**Step 5: Commit**

```bash
cd /home/mk/projects/Sylveste/os/Skaffen
git add internal/tui/commands.go
git commit -m "feat(tui): add /skills management command (list, info, pin, unpin, pinned)"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./...`
  expect: exit 0
</verify>

---

### Task 10: /help Integration and Tab Completion (F7)

**Files:**
- Modify: `os/Skaffen/internal/tui/commands.go` (add skills to /help output)
- Modify: `os/Skaffen/internal/tui/cmdcomplete.go` (add skills to completer)
- Modify: `os/Skaffen/internal/tui/prompt.go` (add skills field to prompt model)

**Step 1: Add skills to formatHelpWithCustom**

In `os/Skaffen/internal/tui/commands.go`, modify `formatHelpWithCustom` to accept skills:

Rename it and change the signature to also accept skills. Or better: add a new method on appModel that uses skills. Replace the `case "help":` handler:

```go
	case "help":
		return CommandResult{Message: m.formatHelp()}
```

Add the `formatHelp` method:

```go
// formatHelp renders help text for built-in + custom commands + skills.
func (m *appModel) formatHelp() string {
	cmds := KnownCommands()
	for name, def := range m.customCmds {
		if _, exists := cmds[name]; !exists {
			cmds[name] = def.Description
		}
	}
	names := make([]string, 0, len(cmds))
	for name := range cmds {
		names = append(names, name)
	}
	sort.Strings(names)

	var b strings.Builder
	b.WriteString("Commands:\n")
	for _, name := range names {
		b.WriteString(fmt.Sprintf("  /%s — %s\n", name, cmds[name]))
	}

	// Skills section
	var skillNames []string
	for name, d := range m.skills {
		if d.UserInvocable {
			skillNames = append(skillNames, name)
		}
	}
	if len(skillNames) > 0 {
		sort.Strings(skillNames)
		b.WriteString("\nSkills:\n")
		for _, name := range skillNames {
			d := m.skills[name]
			b.WriteString(fmt.Sprintf("  /%s — %s [%s]\n", name, d.Description, d.Source))
		}
	}

	return b.String()
}
```

**Step 2: Add skills to the tab completer**

In `os/Skaffen/internal/tui/cmdcomplete.go`, modify `newCmdCompleter` to also accept skills:

Change the signature to:

```go
func newCmdCompleter(custom map[string]command.Def, skills map[string]skill.Def) cmdCompleterModel {
```

Add import for `"github.com/mistakeknot/Skaffen/internal/skill"`.

After the custom command loop, add skills:

```go
	for name, d := range skills {
		if d.UserInvocable {
			if _, exists := known[name]; !exists {
				known[name] = d.Description
			}
		}
	}
```

**Step 3: Update prompt model to pass skills through**

Check `os/Skaffen/internal/tui/prompt.go` for where `newCmdCompleter` is called and add the skills parameter. In `promptModel`, add a `skills` field:

```go
skills     map[string]skill.Def
```

Update the call site where `newCmdCompleter` is invoked to pass `pm.skills`:

```go
pm.completer = newCmdCompleter(pm.customCmds, pm.skills)
```

**Step 4: Verify everything compiles**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./...`
Expected: exit 0

**Step 5: Commit**

```bash
cd /home/mk/projects/Sylveste/os/Skaffen
git add internal/tui/commands.go internal/tui/cmdcomplete.go internal/tui/prompt.go internal/tui/app.go
git commit -m "feat(tui): add skills to /help output and tab completion"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./...`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go vet ./...`
  expect: exit 0
</verify>

---

### Task 11: Implicit Trigger Activation in submitMsg (F7)

**Files:**
- Modify: `os/Skaffen/internal/tui/app.go` (add trigger matching in submitMsg handler)

**Step 1: Add implicit trigger matching**

In `os/Skaffen/internal/tui/app.go`, in the `submitMsg` handler, add trigger matching before the agent dispatch. The relevant section (after `expanded := expandAtMentions(msg.Text, m.workDir)`) becomes:

```go
		// Expand @file mentions before sending to agent
		expanded := expandAtMentions(msg.Text, m.workDir)
		// Implicit trigger matching — auto-activate matching skills
		matched := skill.MatchTriggers(m.skills, msg.Text)
		for _, d := range matched {
			body, err := skill.LoadBody(&d)
			if err != nil {
				continue
			}
			d.Body = body
			m.skills[d.Name] = d
			m.pendingSkills = append(m.pendingSkills, skill.FormatInjection(&d, ""))
			// Show activation indicator
			infoStyle := lipgloss.NewStyle().Foreground(theme.Current().Semantic().FgDim.Color())
			m.viewport.AppendContent(infoStyle.Render(fmt.Sprintf("[skill: %s]", d.Name)) + "\n")
		}
		// Prepend any pending skill injections + pinned skill injections
		prompt := m.buildSkillPrompt(expanded)
		cmds = append(cmds, m.runAgent(prompt))
```

**Step 2: Verify everything compiles**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./...`
Expected: exit 0

**Step 3: Commit**

```bash
cd /home/mk/projects/Sylveste/os/Skaffen
git add internal/tui/app.go
git commit -m "feat(tui): add implicit trigger matching on user messages"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./...`
  expect: exit 0
</verify>

---

### Task 12: Full integration test

**Files:**
- Run existing tests to verify nothing is broken

**Step 1: Run full test suite**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./... -count=1`
Expected: All PASS

**Step 2: Run vet**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go vet ./...`
Expected: exit 0

**Step 3: Build binary**

Run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./cmd/skaffen`
Expected: exit 0, binary produced

<verify>
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go test ./... -count=1`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go vet ./...`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
</verify>
