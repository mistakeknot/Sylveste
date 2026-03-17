package compact_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/compact"
)

func makeParams(tool string) string {
	var params map[string]interface{}
	switch tool {
	case "read":
		params = map[string]interface{}{"file_path": "/home/mk/projects/Demarch/masaq/priompt/priompt.go"}
	case "bash":
		params = map[string]interface{}{"command": "cd /home/mk/projects/Demarch && go test -v ./masaq/priompt/..."}
	case "grep":
		params = map[string]interface{}{"pattern": "func.*Render", "path": "/home/mk/projects/Demarch/masaq"}
	case "glob":
		params = map[string]interface{}{"pattern": "**/*.go"}
	case "edit":
		params = map[string]interface{}{
			"file_path":  "/home/mk/projects/Demarch/masaq/priompt/priompt.go",
			"old_string": strings.Repeat("old content line\n", 10),
			"new_string": strings.Repeat("new content line\n", 10),
		}
	default:
		params = map[string]interface{}{"key": "value"}
	}
	b, _ := json.Marshal(params)
	return string(b)
}

func BenchmarkFormatToolCallCompact(b *testing.B) {
	f := compact.New(120)
	tools := []string{"read", "bash", "grep", "glob", "edit"}
	outputs := []string{
		"file contents here",
		"PASS\nok github.com/mistakeknot/Masaq 0.5s",
		"priompt.go:128:func Render(",
		"/home/mk/projects/Demarch/masaq/priompt/priompt.go",
		"",
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for j, tool := range tools {
			f.FormatToolCall(tool, makeParams(tool), outputs[j], false)
		}
	}
}

func BenchmarkFormatToolCallVerbose(b *testing.B) {
	f := compact.New(120)
	f.SetVerbose(true)
	output := strings.Repeat("line of output\n", 100) // 1500 chars
	params := makeParams("bash")
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		f.FormatToolCall("bash", params, output, false)
	}
}

func BenchmarkFormatToolCallError(b *testing.B) {
	f := compact.New(120)
	errOutput := strings.Repeat("error: something went wrong at line N\n", 20) // 780 chars
	params := makeParams("bash")
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		f.FormatToolCall("bash", params, errOutput, true)
	}
}

func BenchmarkFormatToolCallLargeOutput(b *testing.B) {
	f := compact.New(120)
	f.SetVerbose(true)
	largeOutput := strings.Repeat("x", 10000)
	params := makeParams("read")
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		f.FormatToolCall("read", params, largeOutput, false)
	}
}

func BenchmarkExtractSummaryJSON(b *testing.B) {
	f := compact.New(120)
	tools := []string{"read", "bash", "grep", "glob"}
	paramsList := make([]string, len(tools))
	for i, t := range tools {
		paramsList[i] = makeParams(t)
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for j, tool := range tools {
			f.FormatToolCall(tool, paramsList[j], "", false)
		}
	}
}
