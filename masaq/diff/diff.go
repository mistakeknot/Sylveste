// Package diff provides a stateless unified diff renderer with Chroma syntax
// highlighting and lipgloss styling. It computes diffs in pure Go using a
// line-based LCS algorithm — no external tools required.
package diff

import (
	"bytes"
	"fmt"
	"strings"

	"github.com/alecthomas/chroma/v2"
	"github.com/alecthomas/chroma/v2/formatters"
	"github.com/alecthomas/chroma/v2/lexers"
	"github.com/alecthomas/chroma/v2/styles"
	"github.com/charmbracelet/lipgloss"
	"github.com/mistakeknot/masaq/theme"
)

// Renderer produces styled unified diffs.
type Renderer struct {
	width int
}

// New creates a Renderer that wraps output to the given column width.
func New(width int) *Renderer {
	return &Renderer{width: width}
}

// Render computes a unified diff between before and after, then returns a
// styled string. filename is used for syntax-highlighting heuristics. If
// before == after the empty string is returned.
func (r *Renderer) Render(before, after, filename string) string {
	if before == after {
		return ""
	}

	bLines := splitLines(before)
	aLines := splitLines(after)

	hunks := computeHunks(bLines, aLines, 3)
	if len(hunks) == 0 {
		return ""
	}

	lexer := lexerForFile(filename)
	highlighter := newHighlighter(lexer)

	c := theme.Current().Semantic()
	headerStyle := lipgloss.NewStyle().Foreground(c.Info.Color()).Bold(true)
	hunkStyle := lipgloss.NewStyle().Foreground(c.Secondary.Color())
	addStyle := lipgloss.NewStyle().Foreground(c.DiffAdd.Color())
	removeStyle := lipgloss.NewStyle().Foreground(c.DiffRemove.Color())
	contextStyle := lipgloss.NewStyle().Foreground(c.DiffContext.Color())

	var sb strings.Builder

	sb.WriteString(headerStyle.Render("--- a/"+filename) + "\n")
	sb.WriteString(headerStyle.Render("+++ b/"+filename) + "\n")

	for _, h := range hunks {
		sb.WriteString(hunkStyle.Render(h.header()) + "\n")
		for _, dl := range h.lines {
			switch dl.op {
			case opContext:
				sb.WriteString(contextStyle.Render(" "+dl.text) + "\n")
			case opAdd:
				highlighted := highlighter.highlight(dl.text)
				sb.WriteString(addStyle.Render("+")+highlighted + "\n")
			case opRemove:
				highlighted := highlighter.highlight(dl.text)
				sb.WriteString(removeStyle.Render("-")+highlighted + "\n")
			}
		}
	}

	return sb.String()
}

// --- line-based LCS diff --------------------------------------------------

// splitLines splits s into individual lines, stripping the trailing newline
// so that "a\nb\n" becomes ["a","b"] (matching diff convention).
func splitLines(s string) []string {
	if s == "" {
		return nil
	}
	lines := strings.Split(s, "\n")
	// Trim trailing empty element from a final newline.
	if len(lines) > 0 && lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	return lines
}

type opKind int

const (
	opContext opKind = iota
	opAdd
	opRemove
)

type diffLine struct {
	op   opKind
	text string
}

type hunk struct {
	oldStart, oldCount int
	newStart, newCount int
	lines              []diffLine
}

func (h hunk) header() string {
	return fmt.Sprintf("@@ -%d,%d +%d,%d @@", h.oldStart+1, h.oldCount, h.newStart+1, h.newCount)
}

// lcs computes the LCS table for two slices of strings using the classic
// O(n*m) dynamic-programming approach.
func lcs(a, b []string) [][]int {
	n, m := len(a), len(b)
	tbl := make([][]int, n+1)
	for i := range tbl {
		tbl[i] = make([]int, m+1)
	}
	for i := 1; i <= n; i++ {
		for j := 1; j <= m; j++ {
			if a[i-1] == b[j-1] {
				tbl[i][j] = tbl[i-1][j-1] + 1
			} else if tbl[i-1][j] >= tbl[i][j-1] {
				tbl[i][j] = tbl[i-1][j]
			} else {
				tbl[i][j] = tbl[i][j-1]
			}
		}
	}
	return tbl
}

// backtrack walks the LCS table to produce a flat sequence of diff operations.
func backtrack(tbl [][]int, a, b []string) []diffLine {
	var result []diffLine
	i, j := len(a), len(b)
	for i > 0 || j > 0 {
		if i > 0 && j > 0 && a[i-1] == b[j-1] {
			result = append(result, diffLine{op: opContext, text: a[i-1]})
			i--
			j--
		} else if j > 0 && (i == 0 || tbl[i][j-1] >= tbl[i-1][j]) {
			result = append(result, diffLine{op: opAdd, text: b[j-1]})
			j--
		} else {
			result = append(result, diffLine{op: opRemove, text: a[i-1]})
			i--
		}
	}
	// Reverse — backtracking produces lines in reverse order.
	for l, r := 0, len(result)-1; l < r; l, r = l+1, r-1 {
		result[l], result[r] = result[r], result[l]
	}
	return result
}

// computeHunks groups a flat diff into hunks, keeping ctx context lines
// around each change (standard unified diff convention, usually ctx=3).
func computeHunks(a, b []string, ctx int) []hunk {
	tbl := lcs(a, b)
	ops := backtrack(tbl, a, b)
	if len(ops) == 0 {
		return nil
	}

	// Find indices of changed lines.
	var changes []int
	for i, dl := range ops {
		if dl.op != opContext {
			changes = append(changes, i)
		}
	}
	if len(changes) == 0 {
		return nil
	}

	// Group changes that are within 2*ctx of each other into the same hunk.
	type span struct{ start, end int }
	var groups []span
	gStart := changes[0]
	gEnd := changes[0]
	for _, ci := range changes[1:] {
		if ci-gEnd > 2*ctx {
			groups = append(groups, span{gStart, gEnd})
			gStart = ci
		}
		gEnd = ci
	}
	groups = append(groups, span{gStart, gEnd})

	// Build hunks with context.
	var hunks []hunk
	for _, g := range groups {
		lo := g.start - ctx
		if lo < 0 {
			lo = 0
		}
		hi := g.end + ctx
		if hi >= len(ops) {
			hi = len(ops) - 1
		}

		var h hunk
		h.lines = ops[lo : hi+1]

		// Compute line numbers by walking ops from the beginning.
		oldLine, newLine := 0, 0
		for i := 0; i < lo; i++ {
			switch ops[i].op {
			case opContext:
				oldLine++
				newLine++
			case opAdd:
				newLine++
			case opRemove:
				oldLine++
			}
		}
		h.oldStart = oldLine
		h.newStart = newLine

		oldCount, newCount := 0, 0
		for _, dl := range h.lines {
			switch dl.op {
			case opContext:
				oldCount++
				newCount++
			case opAdd:
				newCount++
			case opRemove:
				oldCount++
			}
		}
		h.oldCount = oldCount
		h.newCount = newCount

		hunks = append(hunks, h)
	}
	return hunks
}

// --- Chroma syntax highlighting -------------------------------------------

type highlighter struct {
	lexer     chroma.Lexer
	formatter chroma.Formatter
	style     *chroma.Style
}

func lexerForFile(filename string) chroma.Lexer {
	l := lexers.Match(filename)
	if l == nil {
		l = lexers.Fallback
	}
	return chroma.Coalesce(l)
}

func newHighlighter(l chroma.Lexer) *highlighter {
	// terminal256 is safe for all terminal emulators.
	f := formatters.Get("terminal256")
	if f == nil {
		f = formatters.Fallback
	}
	s := styles.Get("monokai")
	if s == nil {
		s = styles.Fallback
	}
	return &highlighter{lexer: l, formatter: f, style: s}
}

func (h *highlighter) highlight(text string) string {
	iterator, err := h.lexer.Tokenise(nil, text)
	if err != nil {
		return text
	}
	var buf bytes.Buffer
	if err := h.formatter.Format(&buf, h.style, iterator); err != nil {
		return text
	}
	// The formatter may append a trailing newline — strip it so we control
	// newline placement in the diff output.
	out := buf.String()
	out = strings.TrimRight(out, "\n")
	return out
}
