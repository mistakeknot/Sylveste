package diff_test

import (
	"strings"
	"testing"

	"github.com/mistakeknot/masaq/diff"
)

func TestRenderUnifiedDiff(t *testing.T) {
	d := diff.New(80)
	before := "func hello() {\n\treturn \"hello\"\n}\n"
	after := "func hello() {\n\treturn \"hello world\"\n}\n"
	result := d.Render(before, after, "main.go")
	if result == "" {
		t.Fatal("diff should not be empty for different inputs")
	}
	// Should contain some indication of added/removed content
	if !strings.Contains(result, "hello world") {
		t.Fatal("diff should contain the new content")
	}
}

func TestNoDiffReturnsEmpty(t *testing.T) {
	d := diff.New(80)
	result := d.Render("same", "same", "file.go")
	if result != "" {
		t.Fatalf("identical content should produce empty diff, got: %q", result)
	}
}

func TestMultiLineDiff(t *testing.T) {
	d := diff.New(80)
	before := "line1\nline2\nline3\n"
	after := "line1\nmodified\nline3\nnew line\n"
	result := d.Render(before, after, "test.txt")
	if result == "" {
		t.Fatal("diff should not be empty")
	}
}
