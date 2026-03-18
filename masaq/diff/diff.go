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
	"github.com/mistakeknot/Masaq/theme"
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

type myersTrace struct {
	v []int
}

// myersDiff computes the shortest edit script between a and b using Myers'
// O(nd) algorithm, where n = len(a)+len(b) and d = edit distance.
// Returns a flat sequence of diff operations (context, add, remove).
//
// For small changes (d << n), this is dramatically faster than O(n*m) LCS
// and uses O(d) space instead of O(n*m).
func myersDiff(a, b []string) []diffLine {
	n, m := len(a), len(b)
	if n == 0 && m == 0 {
		return nil
	}
	if n == 0 {
		result := make([]diffLine, m)
		for i, line := range b {
			result[i] = diffLine{op: opAdd, text: line}
		}
		return result
	}
	if m == 0 {
		result := make([]diffLine, n)
		for i, line := range a {
			result[i] = diffLine{op: opRemove, text: line}
		}
		return result
	}

	// Myers algorithm: find shortest edit script by exploring diagonals.
	// V[k] stores the furthest-reaching x on diagonal k for the current d.
	max := n + m
	// Use offset so negative indices work: V[k+offset]
	vSize := 2*max + 1
	v := make([]int, vSize)
	// Store trace for backtracking: trace[d] = copy of V at step d.
	var trace []myersTrace

	offset := max
	for d := 0; d <= max; d++ {
		// Save V state for backtracking.
		vc := make([]int, vSize)
		copy(vc, v)
		trace = append(trace, myersTrace{v: vc})

		for k := -d; k <= d; k += 2 {
			// Decide whether to go down or right.
			var x int
			if k == -d || (k != d && v[k-1+offset] < v[k+1+offset]) {
				x = v[k+1+offset] // move down (insert from b)
			} else {
				x = v[k-1+offset] + 1 // move right (delete from a)
			}
			y := x - k

			// Follow diagonal (matching lines).
			for x < n && y < m && a[x] == b[y] {
				x++
				y++
			}
			v[k+offset] = x

			// Check if we've reached the end.
			if x >= n && y >= m {
				// Backtrack through trace to build edit script.
				return myersBacktrack(trace, a, b, d)
			}
		}
	}
	// Should never reach here for valid inputs.
	return nil
}

// myersBacktrack reconstructs the edit script from Myers trace.
// It walks the trace backwards, identifying each edit (insert/delete) and
// diagonal run (context), then reverses to produce forward-order operations.
func myersBacktrack(trace []myersTrace, a, b []string, finalD int) []diffLine {
	n, m := len(a), len(b)
	offset := n + m

	// Collect operations in reverse order.
	result := make([]diffLine, 0, n+m)
	x, y := n, m

	for d := finalD; d > 0; d-- {
		k := x - y
		prev := trace[d-1].v
		var prevK int
		if k == -d || (k != d && prev[k-1+offset] < prev[k+1+offset]) {
			prevK = k + 1 // came from above (insert)
		} else {
			prevK = k - 1 // came from left (delete)
		}
		prevX := prev[prevK+offset]
		prevY := prevX - prevK

		// Diagonal (snake) from (prevX,prevY) to before the edit at (x,y).
		// The snake runs forward: positions (prevX..editX-1, prevY..editY-1).
		// But the edit happened first, then the snake followed.
		// So: snake is from (prevX or prevX+1, ...) to (x, y).

		// Walk back the diagonal portion (matching lines).
		for x > prevX+1 && y > prevY+1 {
			x--
			y--
			result = append(result, diffLine{op: opContext, text: a[x]})
		}

		// The edit step.
		if prevK == k+1 {
			// Insert from b (moved down: y increased).
			y--
			result = append(result, diffLine{op: opAdd, text: b[y]})
		} else {
			// Delete from a (moved right: x increased).
			x--
			result = append(result, diffLine{op: opRemove, text: a[x]})
		}
	}

	// Remaining diagonal at d=0 (initial matching prefix).
	for x > 0 && y > 0 {
		x--
		y--
		result = append(result, diffLine{op: opContext, text: a[x]})
	}

	// Reverse to get forward order.
	for l, r := 0, len(result)-1; l < r; l, r = l+1, r-1 {
		result[l], result[r] = result[r], result[l]
	}
	return result
}

// computeHunks groups a flat diff into hunks, keeping ctx context lines
// around each change (standard unified diff convention, usually ctx=3).
func computeHunks(a, b []string, ctx int) []hunk {
	ops := myersDiff(a, b)
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
