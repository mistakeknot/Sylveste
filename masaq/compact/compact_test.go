package compact_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/compact"
)

func TestCompactSummary(t *testing.T) {
	c := compact.New(80)
	result := c.FormatToolCall("read", `{"file_path": "/home/mk/foo.go"}`, "file contents...", false)
	if !strings.Contains(result, "read") {
		t.Fatal("compact should contain tool name")
	}
	if !strings.Contains(result, "foo.go") {
		t.Fatal("compact should extract filename from params")
	}
}

func TestVerboseMode(t *testing.T) {
	c := compact.New(80)
	c.SetVerbose(true)
	result := c.FormatToolCall("bash", `{"command": "go test ./..."}`, "PASS", false)
	if !strings.Contains(result, "PASS") {
		t.Fatal("verbose mode should include output")
	}
}

func TestErrorAlwaysExpanded(t *testing.T) {
	c := compact.New(80)
	result := c.FormatToolCall("bash", `{"command": "go build"}`, "compilation error", true)
	if !strings.Contains(result, "compilation error") {
		t.Fatal("errors should always show output regardless of compact mode")
	}
}

func TestCompactOneLine(t *testing.T) {
	c := compact.New(80)
	result := c.FormatToolCall("grep", `{"pattern": "TODO"}`, "found stuff", false)
	lines := strings.Split(result, "\n")
	if len(lines) != 1 {
		t.Fatalf("compact mode should be one line, got %d lines", len(lines))
	}
}

func TestGlobSummary(t *testing.T) {
	c := compact.New(80)
	result := c.FormatToolCall("glob", `{"pattern": "**/*.go"}`, "", false)
	if !strings.Contains(result, "**/*.go") {
		t.Fatal("glob should show pattern in summary")
	}
}

func TestBashTruncation(t *testing.T) {
	c := compact.New(80)
	longCmd := strings.Repeat("x", 100)
	result := c.FormatToolCall("bash", `{"command": "`+longCmd+`"}`, "", false)
	if !strings.Contains(result, "...") {
		t.Fatal("long commands should be truncated with ellipsis")
	}
}

func TestIsVerbose(t *testing.T) {
	c := compact.New(80)
	if c.IsVerbose() {
		t.Fatal("should default to non-verbose")
	}
	c.SetVerbose(true)
	if !c.IsVerbose() {
		t.Fatal("should be verbose after SetVerbose(true)")
	}
}
