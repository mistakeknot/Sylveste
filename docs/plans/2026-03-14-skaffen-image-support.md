---
artifact_type: plan
bead: Sylveste-6i0.12
stage: design
---
# Skaffen Image Support — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-6i0.12
**Goal:** Add image input via `@filepath` auto-detection — when a user references an image file (.png/.jpg/.jpeg/.gif/.webp), Skaffen base64-encodes it and sends it as an image content block alongside the text prompt.

**Architecture:** Extend `ContentBlock` with an `ImageSource` field, add `expandImageMentions()` to extract image refs from user input, change the agent loop to accept multimodal content blocks, update token estimation for images. Session JSONL persistence needs no changes (already schema-agnostic). TUI shows `[img filename.ext (size)]` badge.

**Tech Stack:** Go stdlib (encoding/base64, path/filepath, mime). No new dependencies.

---

## Must-Haves

**Truths:**
- `@screenshot.png describe this` sends an image content block + text to the Anthropic API
- `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp` files are auto-detected by extension
- Files > 5MB are rejected with a user-friendly error (left as `@path` in text)
- Non-image `@file.go` references still work exactly as before (text inlining)
- Multiple images per message work: `@a.png @b.png compare these`
- TUI displays `[img screenshot.png (245KB)]` badge in chat viewport
- Token estimation accounts for image blocks (~1600 tokens per image)
- Session JSONL round-trips correctly with image content blocks

**Artifacts:**
- `os/Skaffen/internal/provider/types.go` exports `ImageSource` struct, `ContentBlock.Source` field
- `os/Skaffen/internal/tui/app.go` exports `expandImageMentions()`, `isImageFile()`, `imageBadge()`
- `os/Skaffen/internal/agentloop/loop.go` handles "image" type in `estimateMessageTokens()`

**Key Links:**
- `tui/app.go:433` calls `expandImageMentions()` before `expandAtMentions()` — images extracted first, remaining text processed normally
- `tui/app.go` calls `runAgentMultimodal()` (new) when images are present, which builds a multi-block `provider.Message`
- `agentloop/loop.go:87-89` creates user message from `[]ContentBlock` instead of single text block
- `provider/anthropic` serializes image blocks to Anthropic API via existing JSON marshaling (no changes needed)

---

### Task 1: Add ImageSource to ContentBlock

**Files:**
- Modify: `os/Skaffen/internal/provider/types.go`
- Test: `os/Skaffen/internal/provider/types_test.go`

**Step 1: Write the failing test**

```go
package provider

import (
	"encoding/json"
	"testing"
)

func TestContentBlock_ImageJSON(t *testing.T) {
	block := ContentBlock{
		Type: "image",
		Source: &ImageSource{
			Type:      "base64",
			MediaType: "image/png",
			Data:      "iVBORw0KGgo=",
		},
	}
	data, err := json.Marshal(block)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	// Verify JSON contains source field
	var raw map[string]interface{}
	json.Unmarshal(data, &raw)
	if raw["type"] != "image" {
		t.Errorf("type: got %v, want image", raw["type"])
	}
	if raw["source"] == nil {
		t.Error("source field missing from JSON")
	}
	// Verify text field is omitted
	if _, ok := raw["text"]; ok {
		t.Error("text field should be omitted for image blocks")
	}

	// Round-trip
	var decoded ContentBlock
	json.Unmarshal(data, &decoded)
	if decoded.Source == nil {
		t.Fatal("decoded source is nil")
	}
	if decoded.Source.MediaType != "image/png" {
		t.Errorf("media_type: got %q, want image/png", decoded.Source.MediaType)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./internal/provider/ -run TestContentBlock_ImageJSON -v`
Expected: FAIL (Source field doesn't exist)

**Step 3: Add ImageSource type and Source field**

In `types.go`, add after the ContentBlock struct:

```go
// ImageSource represents a base64-encoded image for multimodal messages.
type ImageSource struct {
	Type      string `json:"type"`       // "base64"
	MediaType string `json:"media_type"` // "image/png", "image/jpeg", etc.
	Data      string `json:"data"`       // base64-encoded binary
}
```

Add to ContentBlock:

```go
type ContentBlock struct {
	Type  string          `json:"type"`
	Text  string          `json:"text,omitempty"`
	ID    string          `json:"id,omitempty"`
	Name  string          `json:"name,omitempty"`
	Input json.RawMessage `json:"input,omitempty"`

	// Image support
	Source *ImageSource `json:"source,omitempty"`

	// tool_result fields
	ToolUseID     string `json:"tool_use_id,omitempty"`
	ResultContent string `json:"content,omitempty"`
	IsError       bool   `json:"is_error,omitempty"`
}
```

**Step 4: Run test**

Run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./internal/provider/ -run TestContentBlock_ImageJSON -v`
Expected: PASS

**Step 5: Run full test suite to verify no regressions**

Run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./... -count=1`
Expected: PASS (adding an optional field doesn't break existing JSON serialization)

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/provider/types.go internal/provider/types_test.go
git commit -m "feat(image): add ImageSource type to ContentBlock for multimodal messages"
```

<verify>
- run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./internal/provider/ -v`
  expect: exit 0
- run: `cd os/Skaffen && GOTOOLCHAIN=auto go build ./cmd/skaffen`
  expect: exit 0
</verify>

---

### Task 2: Image Detection and Base64 Encoding

**Files:**
- Create: `os/Skaffen/internal/tui/image.go`
- Create: `os/Skaffen/internal/tui/image_test.go`

**Step 1: Write the failing test**

```go
package tui

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"
)

func TestIsImageFile(t *testing.T) {
	tests := []struct {
		path string
		want bool
	}{
		{"screenshot.png", true},
		{"photo.jpg", true},
		{"pic.jpeg", true},
		{"anim.gif", true},
		{"logo.webp", true},
		{"code.go", false},
		{"data.csv", false},
		{"readme.md", false},
		{"PHOTO.PNG", true},  // case insensitive
	}
	for _, tt := range tests {
		if got := isImageFile(tt.path); got != tt.want {
			t.Errorf("isImageFile(%q) = %v, want %v", tt.path, got, tt.want)
		}
	}
}

func TestMediaTypeFromExt(t *testing.T) {
	tests := []struct {
		ext  string
		want string
	}{
		{".png", "image/png"},
		{".jpg", "image/jpeg"},
		{".jpeg", "image/jpeg"},
		{".gif", "image/gif"},
		{".webp", "image/webp"},
	}
	for _, tt := range tests {
		if got := mediaTypeFromExt(tt.ext); got != tt.want {
			t.Errorf("mediaTypeFromExt(%q) = %q, want %q", tt.ext, got, tt.want)
		}
	}
}

func TestExpandImageMentions(t *testing.T) {
	dir := t.TempDir()

	// Create a small "image" file (just bytes, not a real image — that's fine for encoding)
	imgData := []byte{0x89, 0x50, 0x4E, 0x47} // PNG magic bytes
	os.WriteFile(filepath.Join(dir, "test.png"), imgData, 0644)
	os.WriteFile(filepath.Join(dir, "code.go"), []byte("package main"), 0644)

	text := "check @test.png and @code.go"
	cleanText, blocks := expandImageMentions(text, dir)

	// Image ref should be extracted
	if len(blocks) != 1 {
		t.Fatalf("blocks: got %d, want 1", len(blocks))
	}
	if blocks[0].Type != "image" {
		t.Errorf("block type: got %q, want image", blocks[0].Type)
	}
	if blocks[0].Source == nil {
		t.Fatal("source is nil")
	}
	if blocks[0].Source.MediaType != "image/png" {
		t.Errorf("media_type: got %q, want image/png", blocks[0].Source.MediaType)
	}
	// Data should be valid base64
	if _, err := base64.StdEncoding.DecodeString(blocks[0].Source.Data); err != nil {
		t.Errorf("invalid base64: %v", err)
	}

	// Text should have image ref replaced with badge, code.go left as-is
	if cleanText == text {
		t.Error("text should be modified (image ref replaced)")
	}
	// @code.go should still be in the text (not an image)
	if !contains(cleanText, "@code.go") {
		t.Error("non-image @mention should be preserved")
	}
}

func TestExpandImageMentions_TooLarge(t *testing.T) {
	dir := t.TempDir()
	// Create a 6MB file (over 5MB limit)
	bigData := make([]byte, 6*1024*1024)
	os.WriteFile(filepath.Join(dir, "huge.png"), bigData, 0644)

	text := "check @huge.png"
	cleanText, blocks := expandImageMentions(text, dir)

	if len(blocks) != 0 {
		t.Errorf("blocks: got %d, want 0 (file too large)", len(blocks))
	}
	// Original text should be left as-is
	if cleanText != text {
		t.Error("text should be unchanged for oversized image")
	}
}

func TestExpandImageMentions_Multiple(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "a.png"), []byte{0x89}, 0644)
	os.WriteFile(filepath.Join(dir, "b.jpg"), []byte{0xFF, 0xD8}, 0644)

	text := "@a.png and @b.jpg compare"
	_, blocks := expandImageMentions(text, dir)

	if len(blocks) != 2 {
		t.Fatalf("blocks: got %d, want 2", len(blocks))
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsStr(s, substr))
}

func containsStr(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
```

**Step 2: Write image.go**

```go
package tui

import (
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/mistakeknot/skaffen/internal/provider"
)

const maxImageSize = 5 * 1024 * 1024 // 5MB — Anthropic limit

var imageExts = map[string]bool{
	".png":  true,
	".jpg":  true,
	".jpeg": true,
	".gif":  true,
	".webp": true,
}

// isImageFile returns true if the path has an image extension.
func isImageFile(path string) bool {
	ext := strings.ToLower(filepath.Ext(path))
	return imageExts[ext]
}

// mediaTypeFromExt returns the MIME type for an image extension.
func mediaTypeFromExt(ext string) string {
	switch strings.ToLower(ext) {
	case ".png":
		return "image/png"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".gif":
		return "image/gif"
	case ".webp":
		return "image/webp"
	default:
		return "application/octet-stream"
	}
}

// imageBadge returns a TUI-friendly placeholder for an image.
func imageBadge(filename string, sizeBytes int64) string {
	size := formatSize(sizeBytes)
	return fmt.Sprintf("[img %s (%s)]", filename, size)
}

func formatSize(bytes int64) string {
	switch {
	case bytes >= 1024*1024:
		return fmt.Sprintf("%.1fMB", float64(bytes)/(1024*1024))
	case bytes >= 1024:
		return fmt.Sprintf("%dKB", bytes/1024)
	default:
		return fmt.Sprintf("%dB", bytes)
	}
}

// expandImageMentions extracts image @references from text and returns
// image ContentBlocks plus the cleaned text (with badges replacing refs).
// Non-image @mentions are left untouched for expandAtMentions to handle.
func expandImageMentions(text, workDir string) (string, []provider.ContentBlock) {
	if !strings.Contains(text, "@") {
		return text, nil
	}

	var blocks []provider.ContentBlock

	cleaned := atMentionRe.ReplaceAllStringFunc(text, func(match string) string {
		path := match[1:] // strip @
		if !isImageFile(path) {
			return match // not an image, leave for expandAtMentions
		}

		fullPath := path
		if !filepath.IsAbs(path) && workDir != "" {
			fullPath = filepath.Join(workDir, path)
		}

		info, err := os.Stat(fullPath)
		if err != nil || info.IsDir() {
			return match // file not found
		}
		if info.Size() > maxImageSize {
			return match // too large, leave as-is
		}

		data, err := os.ReadFile(fullPath)
		if err != nil {
			return match
		}

		ext := filepath.Ext(path)
		blocks = append(blocks, provider.ContentBlock{
			Type: "image",
			Source: &provider.ImageSource{
				Type:      "base64",
				MediaType: mediaTypeFromExt(ext),
				Data:      base64.StdEncoding.EncodeToString(data),
			},
		})

		return imageBadge(filepath.Base(path), info.Size())
	})

	return cleaned, blocks
}
```

**Step 3: Run tests**

Run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./internal/tui/ -run "TestIsImageFile|TestMediaType|TestExpandImage" -v`
Expected: PASS

**Step 4: Commit**

```bash
cd os/Skaffen && git add internal/tui/image.go internal/tui/image_test.go
git commit -m "feat(image): add image detection, base64 encoding, and expandImageMentions"
```

<verify>
- run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./internal/tui/ -run TestExpandImage -v`
  expect: exit 0
</verify>

---

### Task 3: Wire Image Expansion into TUI Message Flow

**Files:**
- Modify: `os/Skaffen/internal/tui/app.go`

**Step 1: Update the user message handling (around line 433)**

Change the message-sending flow to handle images:

```go
// Before (line 432-433):
// expanded := expandAtMentions(msg.Text, m.workDir)

// After:
// First pass: extract images (produces ContentBlocks + cleaned text with badges)
displayText, imageBlocks := expandImageMentions(msg.Text, m.workDir)
// Second pass: expand remaining text @mentions (non-images)
expanded := expandAtMentions(displayText, m.workDir)
```

Then update the TUI viewport to show badges instead of raw @refs for images. The `msg.Text` displayed at line 431 should use `displayText` for user-facing rendering when images are present.

**Step 2: Update runAgent to support multimodal**

Add a new method or modify `runAgent` to accept optional image blocks:

```go
func (m *appModel) runAgent(prompt string) tea.Cmd {
	return m.runAgentWithImages(prompt, nil)
}

func (m *appModel) runAgentWithImages(prompt string, imageBlocks []provider.ContentBlock) tea.Cmd {
	a := m.agent
	ctx, cancel := context.WithCancel(context.Background())
	m.cancelRun = cancel
	m.spinner = spinner.New()
	m.spinner.Label = "Thinking"
	agentCmd := func() tea.Msg {
		if a == nil {
			cancel()
			return agentDoneMsg{Err: fmt.Errorf("no agent configured")}
		}
		var result *agent.RunResult
		var err error
		if len(imageBlocks) > 0 {
			result, err = a.RunWithImages(ctx, prompt, imageBlocks)
		} else {
			result, err = a.Run(ctx, prompt)
		}
		// ... rest unchanged
```

Then update the call site (line 449):

```go
if len(imageBlocks) > 0 {
	cmds = append(cmds, m.runAgentWithImages(prompt, imageBlocks))
} else {
	cmds = append(cmds, m.runAgent(prompt))
}
```

**Step 3: Update viewport display for images**

When displaying the user message (line 431), use the badge text:

```go
if len(imageBlocks) > 0 {
	m.viewport.AppendContent("\n" + userStyle.Render("You") + "\n" + displayText + "\n")
} else {
	m.viewport.AppendContent("\n" + userStyle.Render("You") + "\n" + msg.Text + "\n")
}
```

**Step 4: Build and verify**

Run: `cd os/Skaffen && GOTOOLCHAIN=auto go build ./cmd/skaffen`
Expected: May fail until Task 4 (agent.RunWithImages) is implemented

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/tui/app.go
git commit -m "feat(image): wire expandImageMentions into TUI message flow"
```

<verify>
- run: `cd os/Skaffen && GOTOOLCHAIN=auto go vet ./internal/tui/...`
  expect: exit 0
</verify>

---

### Task 4: Agent Loop Multimodal Support

**Files:**
- Modify: `os/Skaffen/internal/agent/agent.go`
- Modify: `os/Skaffen/internal/agentloop/loop.go`

**Step 1: Add RunWithImages to agent**

In `agent.go`, add:

```go
// RunWithImages is like Run but prepends image ContentBlocks to the user message.
func (a *Agent) RunWithImages(ctx context.Context, task string, images []provider.ContentBlock) (*RunResult, error) {
	// Build content blocks: images first, then text
	var content []provider.ContentBlock
	content = append(content, images...)
	content = append(content, provider.ContentBlock{Type: "text", Text: task})

	return a.runWithContent(ctx, content)
}
```

This requires extracting the core loop logic to accept `[]ContentBlock` instead of just a string. The simplest approach: add a `RunWithContent` to the agentloop.

**Step 2: Update agentloop.Loop to accept content blocks**

In `loop.go`, add:

```go
// RunWithContent is like Run but accepts pre-built content blocks.
func (l *Loop) RunWithContent(ctx context.Context, content []provider.ContentBlock, config LoopConfig) (*RunResult, error) {
	messages := l.session.Messages()
	taskMsg := provider.Message{
		Role:    provider.RoleUser,
		Content: content,
	}
	if len(messages) == 0 {
		messages = []provider.Message{taskMsg}
	} else {
		messages = append(messages, taskMsg)
	}
	// ... rest is identical to Run() — extract shared logic into runLoop()
```

Refactor: extract the shared loop body into `runLoop(ctx, messages, config)` and have both `Run()` and `RunWithContent()` call it.

**Step 3: Update estimateMessageTokens for images**

In the switch block (line 464), add:

```go
case "image":
	total += 1600 // approximate token cost per image
```

**Step 4: Run tests**

Run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./internal/agentloop/ -v -count=1`
Expected: PASS

Run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./internal/agent/ -v -count=1`
Expected: PASS

**Step 5: Build full binary**

Run: `cd os/Skaffen && GOTOOLCHAIN=auto go build ./cmd/skaffen`
Expected: PASS

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/agent/agent.go internal/agentloop/loop.go
git commit -m "feat(image): add RunWithImages and multimodal content block support to agent loop"
```

<verify>
- run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./internal/agentloop/ -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./internal/agent/ -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && GOTOOLCHAIN=auto go build ./cmd/skaffen`
  expect: exit 0
</verify>

---

### Task 5: Print Mode Image Support

**Files:**
- Modify: `os/Skaffen/cmd/skaffen/main.go` (or wherever print mode builds its prompt)

**Step 1: Find print mode prompt construction**

Print mode reads from stdin or `--prompt` flag and passes directly to the agent. Add image expansion there too:

```go
// In print mode path:
displayText, imageBlocks := tui.ExpandImageMentions(prompt, workDir)
expanded := tui.ExpandAtMentions(displayText, workDir)
if len(imageBlocks) > 0 {
	result, err = agent.RunWithImages(ctx, expanded, imageBlocks)
} else {
	result, err = agent.Run(ctx, expanded)
}
```

Note: `expandImageMentions` and `expandAtMentions` may need to be exported (capitalized) for use from main.go. Alternatively, add a helper in the tui package: `ExpandPrompt(text, workDir) (string, []provider.ContentBlock)`.

**Step 2: Export necessary functions**

In `tui/image.go`, export:

```go
func ExpandImageMentions(text, workDir string) (string, []provider.ContentBlock) {
	return expandImageMentions(text, workDir)
}
```

In `tui/app.go`, export:

```go
func ExpandAtMentions(text, workDir string) string {
	return expandAtMentions(text, workDir)
}
```

**Step 3: Build and test**

Run: `cd os/Skaffen && GOTOOLCHAIN=auto go build ./cmd/skaffen`
Expected: PASS

**Step 4: Commit**

```bash
cd os/Skaffen && git add cmd/skaffen/main.go internal/tui/image.go internal/tui/app.go
git commit -m "feat(image): support @image refs in print mode"
```

<verify>
- run: `cd os/Skaffen && GOTOOLCHAIN=auto go build ./cmd/skaffen`
  expect: exit 0
</verify>

---

### Task 6: Integration Test

**Files:**
- Create: `os/Skaffen/internal/tui/image_integration_test.go`

**Step 1: Write integration test**

```go
package tui

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"
)

func TestImagePipeline_EndToEnd(t *testing.T) {
	dir := t.TempDir()

	// Create test files
	pngData := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A} // PNG header
	jpgData := []byte{0xFF, 0xD8, 0xFF, 0xE0}                          // JPEG header
	goData := []byte("package main\nfunc main() {}")

	os.WriteFile(filepath.Join(dir, "screenshot.png"), pngData, 0644)
	os.WriteFile(filepath.Join(dir, "photo.jpg"), jpgData, 0644)
	os.WriteFile(filepath.Join(dir, "main.go"), goData, 0644)

	// Test: mixed input with images and code
	input := "compare @screenshot.png with @photo.jpg and check @main.go"

	// Phase 1: Extract images
	displayText, imageBlocks := expandImageMentions(input, dir)

	if len(imageBlocks) != 2 {
		t.Fatalf("expected 2 image blocks, got %d", len(imageBlocks))
	}

	// Verify PNG block
	if imageBlocks[0].Source.MediaType != "image/png" {
		t.Errorf("block 0: got %q, want image/png", imageBlocks[0].Source.MediaType)
	}
	decoded, _ := base64.StdEncoding.DecodeString(imageBlocks[0].Source.Data)
	if len(decoded) != len(pngData) {
		t.Errorf("block 0: decoded %d bytes, want %d", len(decoded), len(pngData))
	}

	// Verify JPG block
	if imageBlocks[1].Source.MediaType != "image/jpeg" {
		t.Errorf("block 1: got %q, want image/jpeg", imageBlocks[1].Source.MediaType)
	}

	// Verify display text has badges
	if !containsStr(displayText, "[img screenshot.png") {
		t.Error("display text missing PNG badge")
	}
	if !containsStr(displayText, "[img photo.jpg") {
		t.Error("display text missing JPG badge")
	}
	// @main.go should still be in text (not an image)
	if !containsStr(displayText, "@main.go") {
		t.Error("non-image ref should be preserved")
	}

	// Phase 2: Expand remaining text mentions
	expanded := expandAtMentions(displayText, dir)

	// @main.go should now be expanded to [File: main.go]...[/File]
	if !containsStr(expanded, "[File: main.go]") {
		t.Error("text @mention should be expanded after image extraction")
	}
}

func TestImagePipeline_NoImages(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "code.go"), []byte("package main"), 0644)

	text := "check @code.go please"
	cleanText, blocks := expandImageMentions(text, dir)

	if len(blocks) != 0 {
		t.Error("no image blocks expected for non-image file")
	}
	if cleanText != text {
		t.Error("text should be unchanged when no images present")
	}
}
```

**Step 2: Run integration test**

Run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./internal/tui/ -run TestImagePipeline -v`
Expected: PASS

**Step 3: Run full test suite**

Run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./... -count=1`
Expected: PASS

**Step 4: Commit**

```bash
cd os/Skaffen && git add internal/tui/image_integration_test.go
git commit -m "test(image): integration test for full image pipeline"
```

<verify>
- run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./internal/tui/ -run TestImagePipeline -v`
  expect: exit 0
- run: `cd os/Skaffen && GOTOOLCHAIN=auto go test ./... -count=1`
  expect: exit 0
- run: `cd os/Skaffen && GOTOOLCHAIN=auto go build ./cmd/skaffen`
  expect: exit 0
</verify>
