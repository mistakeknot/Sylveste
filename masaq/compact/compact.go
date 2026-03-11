package compact

import (
	"encoding/json"
	"fmt"
	"path/filepath"

	"github.com/charmbracelet/lipgloss"
)

// Formatter renders tool call summaries in compact or verbose mode.
type Formatter struct {
	width   int
	verbose bool
}

// New creates a Formatter with the given terminal width.
func New(width int) *Formatter {
	return &Formatter{width: width}
}

// SetVerbose enables or disables verbose mode.
func (f *Formatter) SetVerbose(v bool) {
	f.verbose = v
}

// IsVerbose returns the current verbose state.
func (f *Formatter) IsVerbose() bool {
	return f.verbose
}

// FormatToolCall renders a tool call summary.
// name: tool name, paramsJSON: JSON params string, output: tool result, isError: whether it errored.
func (f *Formatter) FormatToolCall(name, paramsJSON, output string, isError bool) string {
	toolStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#7dcfff")).Bold(true)
	subtextStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#565f89"))
	errorStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#f7768e"))

	summary := extractSummary(name, paramsJSON)

	// Errors always expanded
	if isError {
		header := toolStyle.Render(name) + " " + subtextStyle.Render(summary)
		truncated := truncateOutput(output, 500)
		return header + "\n" + errorStyle.Render(truncated)
	}

	// Verbose mode: show output
	if f.verbose {
		header := toolStyle.Render(name) + " " + subtextStyle.Render(summary)
		truncated := truncateOutput(output, 2000)
		mutedStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#565f89"))
		return header + "\n" + mutedStyle.Render(truncated)
	}

	// Compact mode: one line
	return toolStyle.Render(name) + " " + subtextStyle.Render(summary)
}

func extractSummary(name, paramsJSON string) string {
	var params map[string]interface{}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return ""
	}

	switch name {
	case "read", "write", "edit":
		if fp, ok := params["file_path"].(string); ok {
			return filepath.Base(fp)
		}
	case "bash":
		if cmd, ok := params["command"].(string); ok {
			if len(cmd) > 60 {
				return cmd[:60] + "..."
			}
			return cmd
		}
	case "grep":
		if pat, ok := params["pattern"].(string); ok {
			return fmt.Sprintf("/%s/", pat)
		}
	case "glob":
		if pat, ok := params["pattern"].(string); ok {
			return pat
		}
	}
	return ""
}

func truncateOutput(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "\n... (truncated)"
}
