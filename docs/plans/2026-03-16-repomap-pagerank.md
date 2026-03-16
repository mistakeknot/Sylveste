---
artifact_type: plan
bead: Demarch-6i0.17
stage: design
requirements:
  - F1: PriomptSession migration in main.go
  - F2: Repomap package with Go-native PageRank
  - F3: Intermap reference_edges MCP tool
  - F4: Skaffen-intermap integration with graceful degradation
  - F5: Conversation personalization for PageRank
---

# Repo Map PageRank Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-6i0.17
**Goal:** Add a conversation-aware, token-budgeted repo map to Skaffen's system prompt using tree-sitter tag extraction and personalized PageRank.

**Architecture:** Hybrid — intermap supplies multi-language tag extraction via a new `reference_edges` MCP tool, Skaffen owns graph/rank/fit/format in pure Go. Five pipeline stages: Parse (intermap or go/ast fallback) → Graph (Go) → Rank (Go, ~80 LOC PageRank) → Fit (Go, binary-search in priompt ContentFunc) → Format (Go, priompt Element). Layered degradation: PageRank → go/ast flat map → empty.

**Tech Stack:** Go (pure, CGO_ENABLED=0), priompt (masaq/priompt), go/ast + go/parser, intermap Python sidecar (tree-sitter), MCP stdio client.

---

## Must-Haves

**Truths** (observable behaviors):
- Agent system prompt contains a relevance-ranked repo map that adapts per OODARC phase
- Repo map uses more tokens during Orient/Observe, less during Reflect/Compound
- When intermap MCP is unavailable, Skaffen still shows a Go-only flat map (no regression)
- `/map` command in TUI shows the ranked map output
- PageRank ranking changes when conversation mentions different files

**Artifacts** (files that must exist):
- `os/Skaffen/internal/repomap/` — package with `Graph`, `Rank()`, `NewElement()`, `TagExtractor` interface
- `os/Skaffen/internal/repomap/repomap_test.go` — tests for graph, PageRank, token fitting
- `interverse/intermap/python/intermap/analyze.py` — `reference_edges` command
- `interverse/intermap/internal/tools/tools.go` — `referenceEdges` MCP tool

**Key Links:**
- `main.go` passes `[]priompt.Element` (including repomap) to `NewPriomptSession`, which calls `priompt.Render` per turn
- `repomap.ContentFunc` calls MCP `reference_edges` (or falls back to go/ast), builds graph, runs PageRank, binary-search fits to budget
- `agentloop/loop.go:126` calls `session.SystemPrompt(hints)` which triggers priompt Render with budget

---

## Task 1: Extract repomap to internal/repomap/ package (F2)

**Files:**
- Create: `os/Skaffen/internal/repomap/extract.go`
- Create: `os/Skaffen/internal/repomap/extract_test.go`
- Modify: `os/Skaffen/internal/tui/repomap.go` (thin wrapper calling new package)
- Modify: `os/Skaffen/internal/tui/commands.go` (update `/map` handler)

**Step 1: Create the new package with TagDef and RefEdge types**

```go
// internal/repomap/extract.go
package repomap

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strings"
)

// TagDef represents a symbol definition.
type TagDef struct {
	File  string // relative path
	Name  string // symbol name
	Line  int    // definition line
	Kind  string // "func", "type", "method"
	Scope string // receiver type for methods
}

// RefEdge represents a cross-file reference.
type RefEdge struct {
	SrcFile string // file containing the reference
	DstFile string // file containing the definition
	Symbol  string // name being referenced
}

// ExtractGoTags parses Go files under root and returns definitions and
// cross-file reference edges. Skips test files, vendor, hidden dirs.
func ExtractGoTags(root string, maxFiles int) ([]TagDef, []RefEdge) {
	if maxFiles <= 0 {
		maxFiles = 200
	}
	var defs []TagDef
	var edges []RefEdge
	fileCount := 0

	// Phase 1: collect all definitions by package
	pkgDefs := make(map[string]map[string]string) // pkg → symbol → file

	filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			if d != nil && d.IsDir() {
				base := d.Name()
				if strings.HasPrefix(base, ".") || base == "vendor" || base == "testdata" || base == "node_modules" {
					return filepath.SkipDir
				}
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		if fileCount >= maxFiles {
			return filepath.SkipAll
		}
		fileCount++

		rel, _ := filepath.Rel(root, path)
		dir := filepath.Dir(rel)
		fset := token.NewFileSet()
		f, err := parser.ParseFile(fset, path, nil, 0)
		if err != nil {
			return nil
		}

		if pkgDefs[dir] == nil {
			pkgDefs[dir] = make(map[string]string)
		}

		for _, decl := range f.Decls {
			switch d := decl.(type) {
			case *ast.GenDecl:
				for _, spec := range d.Specs {
					if ts, ok := spec.(*ast.TypeSpec); ok && ts.Name.IsExported() {
						defs = append(defs, TagDef{
							File: rel, Name: ts.Name.Name,
							Line: fset.Position(ts.Pos()).Line, Kind: "type",
						})
						pkgDefs[dir][ts.Name.Name] = rel
					}
				}
			case *ast.FuncDecl:
				if d.Name.IsExported() {
					td := TagDef{
						File: rel, Name: d.Name.Name,
						Line: fset.Position(d.Pos()).Line,
					}
					if d.Recv != nil && len(d.Recv.List) > 0 {
						td.Kind = "method"
						td.Scope = formatRecvType(d.Recv.List[0].Type)
					} else {
						td.Kind = "func"
					}
					defs = append(defs, td)
					pkgDefs[dir][d.Name.Name] = rel
				}
			}
		}
		return nil
	})

	// Phase 2: collect cross-file references via SelectorExpr in function bodies
	fileCount = 0
	filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			if d != nil && d.IsDir() {
				base := d.Name()
				if strings.HasPrefix(base, ".") || base == "vendor" || base == "testdata" || base == "node_modules" {
					return filepath.SkipDir
				}
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		if fileCount >= maxFiles {
			return filepath.SkipAll
		}
		fileCount++

		rel, _ := filepath.Rel(root, path)
		fset := token.NewFileSet()
		f, err := parser.ParseFile(fset, path, nil, 0)
		if err != nil {
			return nil
		}

		// Build import alias map: alias → package path
		imports := make(map[string]string)
		for _, imp := range f.Imports {
			impPath := strings.Trim(imp.Path.Value, `"`)
			// Use the last path component as the default alias
			parts := strings.Split(impPath, "/")
			alias := parts[len(parts)-1]
			if imp.Name != nil {
				alias = imp.Name.Name
			}
			imports[alias] = impPath
		}

		// Walk function bodies for SelectorExpr (pkg.Symbol calls)
		for _, decl := range f.Decls {
			fn, ok := decl.(*ast.FuncDecl)
			if !ok || fn.Body == nil {
				continue
			}
			ast.Inspect(fn.Body, func(n ast.Node) bool {
				sel, ok := n.(*ast.SelectorExpr)
				if !ok {
					return true
				}
				ident, ok := sel.X.(*ast.Ident)
				if !ok {
					return true
				}
				// Check if this is a package-qualified reference
				pkgPath, isImport := imports[ident.Name]
				if !isImport {
					return true
				}
				// Try to resolve to a known definition
				// Use the last path component as the package dir guess
				parts := strings.Split(pkgPath, "/")
				for dir, syms := range pkgDefs {
					dirParts := strings.Split(dir, string(filepath.Separator))
					if len(dirParts) > 0 && dirParts[len(dirParts)-1] == parts[len(parts)-1] {
						if defFile, ok := syms[sel.Sel.Name]; ok && defFile != rel {
							edges = append(edges, RefEdge{
								SrcFile: rel,
								DstFile: defFile,
								Symbol:  sel.Sel.Name,
							})
						}
					}
				}
				return true
			})
		}
		return nil
	})

	return defs, edges
}

func formatRecvType(expr ast.Expr) string {
	switch t := expr.(type) {
	case *ast.StarExpr:
		return formatRecvType(t.X)
	case *ast.Ident:
		return t.Name
	default:
		return "?"
	}
}

// FormatMap renders a ranked list of definitions as text for the system prompt.
func FormatMap(defs []TagDef, maxChars int) string {
	if len(defs) == 0 {
		return ""
	}

	// Group by directory
	type pkgInfo struct {
		dir     string
		symbols []string
	}
	pkgMap := make(map[string]*pkgInfo)
	var order []string

	for _, d := range defs {
		dir := filepath.Dir(d.File)
		if pkgMap[dir] == nil {
			pkgMap[dir] = &pkgInfo{dir: dir}
			order = append(order, dir)
		}
		var sym string
		switch d.Kind {
		case "method":
			sym = fmt.Sprintf("func (%s) %s()", d.Scope, d.Name)
		case "func":
			sym = fmt.Sprintf("func %s()", d.Name)
		case "type":
			sym = fmt.Sprintf("type %s", d.Name)
		}
		pkgMap[dir].symbols = append(pkgMap[dir].symbols, sym)
	}

	var b strings.Builder
	b.WriteString("Repository Map (ranked by relevance)\n")
	b.WriteString(strings.Repeat("=", 40) + "\n\n")

	for _, dir := range order {
		info := pkgMap[dir]
		fmt.Fprintf(&b, "%s/\n", info.dir)
		seen := make(map[string]bool)
		for _, s := range info.symbols {
			if !seen[s] {
				seen[s] = true
				fmt.Fprintf(&b, "  %s\n", s)
			}
		}
		b.WriteString("\n")
		if maxChars > 0 && b.Len() > maxChars {
			break
		}
	}

	return strings.TrimRight(b.String(), "\n")
}
```

**Step 2: Write tests for ExtractGoTags**

```go
// internal/repomap/extract_test.go
package repomap

import (
	"os"
	"path/filepath"
	"testing"
)

func TestExtractGoTags_BasicDefinitions(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "main.go"), `package main

import "fmt"

type Server struct{}

func NewServer() *Server { return &Server{} }

func (s *Server) Start() error { fmt.Println("start"); return nil }

func helper() {} // unexported, should be excluded
`)

	defs, _ := ExtractGoTags(dir, 100)

	want := map[string]string{"Server": "type", "NewServer": "func", "Start": "method"}
	got := make(map[string]string)
	for _, d := range defs {
		got[d.Name] = d.Kind
	}

	for name, kind := range want {
		if got[name] != kind {
			t.Errorf("expected %s to be %s, got %s", name, kind, got[name])
		}
	}
	if _, ok := got["helper"]; ok {
		t.Error("unexported helper should not appear in defs")
	}
}

func TestExtractGoTags_CrossFileEdges(t *testing.T) {
	dir := t.TempDir()
	os.MkdirAll(filepath.Join(dir, "pkg"), 0o755)

	writeFile(t, filepath.Join(dir, "pkg", "service.go"), `package pkg

type Service struct{}

func NewService() *Service { return &Service{} }
`)
	writeFile(t, filepath.Join(dir, "main.go"), `package main

import "example/pkg"

func main() {
	s := pkg.NewService()
	_ = s
}
`)

	_, edges := ExtractGoTags(dir, 100)
	found := false
	for _, e := range edges {
		if e.Symbol == "NewService" && e.SrcFile == "main.go" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected cross-file edge for NewService, got edges: %+v", edges)
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
```

**Step 3: Run tests**

Run: `cd os/Skaffen && go test ./internal/repomap/ -v -count=1`
Expected: PASS

**Step 4: Update tui/repomap.go to delegate to new package**

Replace the body of `generateRepoMap` to call `repomap.ExtractGoTags` + `repomap.FormatMap`. Keep `tui/repomap.go` as a thin wrapper.

**Step 5: Verify existing `/map` command still works**

Run: `cd os/Skaffen && go build ./cmd/skaffen && go test ./internal/tui/ -v -count=1 -run Map`
Expected: PASS (or no map-specific tests — verify `go build` succeeds)

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/repomap/ internal/tui/repomap.go
git commit -m "refactor: extract repomap to internal/repomap/ with TagDef/RefEdge types"
```

<verify>
- run: `cd /home/mk/projects/Demarch/os/Skaffen && go test ./internal/repomap/ -v -count=1`
  expect: exit 0
- run: `cd /home/mk/projects/Demarch/os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
</verify>

---

## Task 2: Implement personalized PageRank (F2)

**Files:**
- Create: `os/Skaffen/internal/repomap/pagerank.go`
- Create: `os/Skaffen/internal/repomap/pagerank_test.go`

**Step 1: Write failing test for PageRank convergence**

```go
// internal/repomap/pagerank_test.go
package repomap

import (
	"math"
	"testing"
)

func TestPageRank_SimpleChain(t *testing.T) {
	// A → B → C: C should rank highest (most linked-to)
	g := NewGraph()
	a, b, c := uint32(0), uint32(1), uint32(2)
	g.Link(a, b, 1.0)
	g.Link(b, c, 1.0)

	ranks := make(map[uint32]float64)
	g.Rank(0.85, 1e-6, nil, func(node uint32, rank float64) {
		ranks[node] = rank
	})

	if ranks[c] <= ranks[a] {
		t.Errorf("C should rank higher than A: C=%f A=%f", ranks[c], ranks[a])
	}
}

func TestPageRank_Personalization(t *testing.T) {
	// Star graph: A→B, A→C, A→D
	// Without personalization, B/C/D should be equal
	// With personalization on B, B should rank highest
	g := NewGraph()
	a, b, c, d := uint32(0), uint32(1), uint32(2), uint32(3)
	g.Link(a, b, 1.0)
	g.Link(a, c, 1.0)
	g.Link(a, d, 1.0)

	ranks := make(map[uint32]float64)
	pers := map[uint32]float64{b: 10.0, a: 1.0, c: 1.0, d: 1.0}
	g.Rank(0.85, 1e-6, pers, func(node uint32, rank float64) {
		ranks[node] = rank
	})

	if ranks[b] <= ranks[c] || ranks[b] <= ranks[d] {
		t.Errorf("B should rank highest with personalization: B=%f C=%f D=%f", ranks[b], ranks[c], ranks[d])
	}
}

func TestPageRank_SumsToOne(t *testing.T) {
	g := NewGraph()
	for i := uint32(0); i < 10; i++ {
		g.Link(i, (i+1)%10, 1.0)
	}

	var total float64
	g.Rank(0.85, 1e-6, nil, func(_ uint32, rank float64) {
		total += rank
	})

	if math.Abs(total-1.0) > 0.01 {
		t.Errorf("ranks should sum to ~1.0, got %f", total)
	}
}

func TestPageRank_EmptyGraph(t *testing.T) {
	g := NewGraph()
	called := false
	g.Rank(0.85, 1e-6, nil, func(_ uint32, _ float64) {
		called = true
	})
	if called {
		t.Error("callback should not be called on empty graph")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/repomap/ -v -count=1 -run PageRank`
Expected: FAIL (NewGraph not defined)

**Step 3: Implement personalized PageRank**

```go
// internal/repomap/pagerank.go
package repomap

// Graph holds a sparse weighted directed graph for personalized PageRank.
type Graph struct {
	edges map[uint32]map[uint32]float64
	nodes map[uint32]struct{}
}

func NewGraph() *Graph {
	return &Graph{
		edges: make(map[uint32]map[uint32]float64),
		nodes: make(map[uint32]struct{}),
	}
}

// Link adds a weighted edge from src to dst (weights accumulate).
func (g *Graph) Link(src, dst uint32, weight float64) {
	g.nodes[src] = struct{}{}
	g.nodes[dst] = struct{}{}
	if g.edges[src] == nil {
		g.edges[src] = make(map[uint32]float64)
	}
	g.edges[src][dst] += weight
}

// NodeCount returns the number of distinct nodes.
func (g *Graph) NodeCount() int { return len(g.nodes) }

// Rank computes personalized PageRank via power iteration.
// personalize maps node → teleport weight (normalized internally).
// If nil, uniform teleportation is used.
func (g *Graph) Rank(alpha, tol float64, personalize map[uint32]float64,
	callback func(node uint32, rank float64)) {

	n := len(g.nodes)
	if n == 0 {
		return
	}

	nodeList := make([]uint32, 0, n)
	for id := range g.nodes {
		nodeList = append(nodeList, id)
	}

	idx := make(map[uint32]int, n)
	for i, id := range nodeList {
		idx[id] = i
	}

	// Normalize personalization vector
	teleport := make([]float64, n)
	if personalize != nil {
		var sum float64
		for _, id := range nodeList {
			teleport[idx[id]] = personalize[id]
			sum += personalize[id]
		}
		if sum > 0 {
			for i := range teleport {
				teleport[i] /= sum
			}
		} else {
			for i := range teleport {
				teleport[i] = 1.0 / float64(n)
			}
		}
	} else {
		for i := range teleport {
			teleport[i] = 1.0 / float64(n)
		}
	}

	// Precompute outbound weights
	outWeight := make([]float64, n)
	for src, dsts := range g.edges {
		for _, w := range dsts {
			outWeight[idx[src]] += w
		}
	}

	rank := make([]float64, n)
	for i := range rank {
		rank[i] = 1.0 / float64(n)
	}
	newRank := make([]float64, n)

	for iter := 0; iter < 100; iter++ {
		var danglingSum float64
		for i := range nodeList {
			if outWeight[i] == 0 {
				danglingSum += rank[i]
			}
		}

		for i := range newRank {
			newRank[i] = (1-alpha)*teleport[i] + alpha*danglingSum*teleport[i]
		}

		for src, dsts := range g.edges {
			si := idx[src]
			if outWeight[si] == 0 {
				continue
			}
			for dst, w := range dsts {
				di := idx[dst]
				newRank[di] += alpha * rank[si] * w / outWeight[si]
			}
		}

		var diff float64
		for i := range rank {
			d := newRank[i] - rank[i]
			if d < 0 {
				d = -d
			}
			diff += d
		}

		rank, newRank = newRank, rank
		if diff < tol {
			break
		}
	}

	for i, id := range nodeList {
		callback(id, rank[i])
	}
}
```

**Step 4: Run tests**

Run: `cd os/Skaffen && go test ./internal/repomap/ -v -count=1 -run PageRank`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/repomap/pagerank.go internal/repomap/pagerank_test.go
git commit -m "feat(repomap): add personalized PageRank (~80 LOC, zero deps)"
```

<verify>
- run: `cd /home/mk/projects/Demarch/os/Skaffen && go test ./internal/repomap/ -v -count=1`
  expect: exit 0
</verify>

---

## Task 3: Add priompt Element with ContentFunc and token fitting (F1+F2)

**Files:**
- Create: `os/Skaffen/internal/repomap/element.go`
- Create: `os/Skaffen/internal/repomap/element_test.go`
- Modify: `os/Skaffen/cmd/skaffen/main.go:298-310` (print mode: use PriomptSession)
- Modify: `os/Skaffen/cmd/skaffen/main.go:512-525` (TUI mode: use PriomptSession)

**Step 1: Write the Element factory and ContentFunc**

```go
// internal/repomap/element.go
package repomap

import (
	"sort"

	"github.com/mistakeknot/Masaq/priompt"
)

// RankedEntry is a file with its PageRank score and symbols.
type RankedEntry struct {
	Dir     string
	Symbols []string
	Score   float64
}

// NewElement creates a priompt Element for the repo map.
// workDir is the project root. If ranker is nil, falls back to flat extraction.
func NewElement(workDir string) priompt.Element {
	return priompt.Element{
		Name:     "repomap",
		Priority: 35,
		Stable:   false,
		PhaseBoost: map[string]int{
			"observe": +15, "orient": +15, "decide": +5,
			"act": 0, "reflect": -15, "compound": -20,
		},
		Render: contentFunc(workDir),
	}
}

func contentFunc(workDir string) priompt.ContentFunc {
	return func(ctx priompt.RenderContext) string {
		maxTokens := ctx.Budget * 15 / 100
		if maxTokens < 500 {
			return "" // not worth including
		}
		if maxTokens > 8000 {
			maxTokens = 8000
		}

		defs, edges := ExtractGoTags(workDir, 200)
		if len(defs) == 0 {
			return ""
		}

		// Build graph from edges
		g, fileIDs, idFiles := buildFileGraph(edges)

		// Run PageRank (no personalization yet — added in F5)
		fileRanks := make(map[string]float64)
		g.Rank(0.85, 1e-6, nil, func(node uint32, rank float64) {
			if f, ok := idFiles[node]; ok {
				fileRanks[f] = rank
			}
		})
		_ = fileIDs // used by personalization later

		// Rank definitions by their file's PageRank score
		ranked := rankDefs(defs, fileRanks)

		// Binary-search fit to token budget
		return binarySearchFit(ranked, maxTokens)
	}
}

func buildFileGraph(edges []RefEdge) (*Graph, map[string]uint32, map[uint32]string) {
	g := NewGraph()
	fileIDs := make(map[string]uint32)
	idFiles := make(map[uint32]string)
	nextID := uint32(0)

	getID := func(file string) uint32 {
		if id, ok := fileIDs[file]; ok {
			return id
		}
		id := nextID
		nextID++
		fileIDs[file] = id
		idFiles[id] = file
		return id
	}

	for _, e := range edges {
		src := getID(e.SrcFile)
		dst := getID(e.DstFile)
		g.Link(src, dst, 1.0)
	}

	return g, fileIDs, idFiles
}

func rankDefs(defs []TagDef, fileRanks map[string]float64) []TagDef {
	// Sort defs by file rank (descending), then by file path, then by line
	sorted := make([]TagDef, len(defs))
	copy(sorted, defs)

	sort.Slice(sorted, func(i, j int) bool {
		ri, rj := fileRanks[sorted[i].File], fileRanks[sorted[j].File]
		if ri != rj {
			return ri > rj
		}
		if sorted[i].File != sorted[j].File {
			return sorted[i].File < sorted[j].File
		}
		return sorted[i].Line < sorted[j].Line
	})

	return sorted
}

func binarySearchFit(defs []TagDef, maxTokens int) string {
	h := priompt.CharHeuristic{Ratio: 4}

	full := FormatMap(defs, 0)
	if h.Count(full) <= maxTokens {
		return full
	}

	lo, hi := 1, len(defs)
	best := ""
	for lo <= hi {
		mid := (lo + hi) / 2
		candidate := FormatMap(defs[:mid], 0)
		if h.Count(candidate) <= maxTokens {
			best = candidate
			lo = mid + 1
		} else {
			hi = mid - 1
		}
	}
	return best
}
```

**Step 2: Write test for Element ContentFunc**

```go
// internal/repomap/element_test.go
package repomap

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/priompt"
)

func TestNewElement_RendersInBudget(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "main.go"), `package main

type App struct{}

func NewApp() *App { return &App{} }
func (a *App) Run() {}
`)

	elem := NewElement(dir)
	ctx := priompt.RenderContext{Budget: 100000, Phase: "orient"}
	content := elem.Render(ctx)

	if content == "" {
		t.Fatal("expected non-empty content")
	}
	if !strings.Contains(content, "Repository Map") {
		t.Error("expected header")
	}
	if !strings.Contains(content, "App") {
		t.Error("expected App type in output")
	}
}

func TestNewElement_ReturnsEmptyBelowMinBudget(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "main.go"), `package main
func Foo() {}
`)

	elem := NewElement(dir)
	ctx := priompt.RenderContext{Budget: 1000, Phase: "act"} // 15% of 1000 = 150, below 500 floor
	content := elem.Render(ctx)

	if content != "" {
		t.Errorf("expected empty content below budget floor, got %d chars", len(content))
	}
}

func TestBinarySearchFit_RespectsTokenLimit(t *testing.T) {
	// Generate enough defs to exceed a small budget
	var defs []TagDef
	for i := 0; i < 100; i++ {
		defs = append(defs, TagDef{
			File: "pkg/file.go", Name: "Func" + string(rune('A'+i%26)),
			Line: i + 1, Kind: "func",
		})
	}

	result := binarySearchFit(defs, 200) // very tight budget
	h := priompt.CharHeuristic{Ratio: 4}
	tokens := h.Count(result)

	if tokens > 200 {
		t.Errorf("output exceeds budget: %d tokens > 200", tokens)
	}
}
```

**Step 3: Run tests**

Run: `cd os/Skaffen && go test ./internal/repomap/ -v -count=1`
Expected: PASS

**Step 4: Wire PriomptSession into main.go**

In `cmd/skaffen/main.go`, replace the `session.New()` calls with `session.NewPriomptSession()` wrapping, passing `[]priompt.Element` sections. This covers both print mode (~line 305) and TUI mode (~line 520).

The sections slice:
```go
sections := []priompt.Element{
	{Name: "context-files", Content: systemPrompt, Priority: 85, Stable: true},
	repomap.NewElement(cfg.WorkDir()),
}
```

Both `JSONLSession` and `PriomptSession` implement the `agent.Session` interface (`SystemPrompt(phase, budget) string`), so this is a drop-in replacement.

**Step 5: Run full test suite**

Run: `cd os/Skaffen && go test ./... -count=1`
Expected: PASS

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/repomap/element.go internal/repomap/element_test.go cmd/skaffen/main.go
git commit -m "feat(repomap): add priompt Element with PageRank + migrate main.go to PriomptSession"
```

<verify>
- run: `cd /home/mk/projects/Demarch/os/Skaffen && go test ./... -count=1`
  expect: exit 0
- run: `cd /home/mk/projects/Demarch/os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
</verify>

---

## Task 4: Add intermap `reference_edges` MCP tool (F3)

**Files:**
- Modify: `interverse/intermap/python/intermap/analyze.py` (add `reference_edges` command)
- Modify: `interverse/intermap/internal/tools/tools.go` (add Go MCP wrapper)

**Step 1: Add Python `reference_edges` command in analyze.py**

In the `dispatch()` function, add a new `elif command == "reference_edges":` case that:
1. Auto-detects language from file extensions if `language == "auto"`
2. Calls `build_function_index()` for definitions
3. Calls `build_project_call_graph()` for edges
4. Reshapes the 4-tuple edges into `{definitions: [...], edges: [...]}` response

**Step 2: Extend `build_function_index` to return line numbers**

In each of the 6 `_index_*_file` functions, include the line number from the tree-sitter node's `start_point[0]` in the index value.

**Step 3: Add Go MCP tool wrapper in tools.go**

Follow the exact pattern of `codeStructure()` (line 239 in tools.go):
```go
func referenceEdges(bridge *pybridge.Bridge) server.ServerTool {
	return server.ServerTool{
		Tool: mcp.NewTool("reference_edges",
			mcp.WithDescription("Extract definition tags and cross-file reference edges for graph construction."),
			mcp.WithString("project", mcp.Description("Project root path"), mcp.Required()),
			mcp.WithString("language", mcp.Description("Language hint (auto, python, go, typescript, rust, java, c)")),
			mcp.WithNumber("max_files", mcp.Description("Max files to scan (default 500)")),
		),
		Handler: func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := req.GetArguments()
			project, _ := args["project"].(string)
			if project == "" {
				return mcputil.ValidationError("project is required")
			}
			pyArgs := map[string]any{
				"language":  stringOr(args["language"], "auto"),
				"max_files": intOr(args["max_files"], 500),
			}
			result, err := bridge.Run(ctx, "reference_edges", project, pyArgs)
			if err != nil {
				return mcputil.WrapError(err)
			}
			return jsonResult(result)
		},
	}
}
```

Register in `RegisterAll()`.

**Step 4: Test the Python command directly**

Run: `cd interverse/intermap && python3 -c "from intermap.analyze import dispatch; import json; print(json.dumps(dispatch('reference_edges', '.', {'language': 'auto'}), indent=2)[:500])"`
Expected: JSON with `definitions` and `edges` arrays

**Step 5: Test the Go build**

Run: `cd interverse/intermap && go build ./cmd/intermap-mcp/`
Expected: PASS

**Step 6: Commit (in intermap's git repo)**

```bash
cd interverse/intermap && git add python/intermap/analyze.py internal/tools/tools.go
git commit -m "feat: add reference_edges MCP tool for PageRank graph construction"
```

<verify>
- run: `cd /home/mk/projects/Demarch/interverse/intermap && go build ./cmd/intermap-mcp/`
  expect: exit 0
</verify>

---

## Task 5: Wire Skaffen to intermap MCP with graceful degradation (F4)

**Files:**
- Create: `os/Skaffen/internal/repomap/mcp.go`
- Create: `os/Skaffen/internal/repomap/mcp_test.go`
- Modify: `os/Skaffen/internal/repomap/element.go` (add MCP path in ContentFunc)

**Step 1: Add MCP edge fetcher interface and implementation**

```go
// internal/repomap/mcp.go
package repomap

import (
	"encoding/json"
)

// EdgeFetcher provides cross-file reference edges from an external source.
type EdgeFetcher interface {
	// FetchEdges returns reference edges for the given project root.
	// Returns nil, nil if the source is unavailable (graceful degradation).
	FetchEdges(projectRoot string) ([]RefEdge, []TagDef, error)
}

// MCPEdgeResponse matches the reference_edges tool output schema.
type MCPEdgeResponse struct {
	Definitions []struct {
		File  string `json:"file"`
		Name  string `json:"name"`
		Line  int    `json:"line"`
		Kind  string `json:"kind"`
		Scope string `json:"scope"`
	} `json:"definitions"`
	Edges []struct {
		SrcFile   string `json:"src_file"`
		SrcSymbol string `json:"src_symbol"`
		DstFile   string `json:"dst_file"`
		DstSymbol string `json:"dst_symbol"`
	} `json:"edges"`
}

// ParseMCPResponse converts the MCP tool result JSON into TagDefs and RefEdges.
func ParseMCPResponse(data []byte) ([]TagDef, []RefEdge, error) {
	var resp MCPEdgeResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return nil, nil, err
	}

	defs := make([]TagDef, len(resp.Definitions))
	for i, d := range resp.Definitions {
		defs[i] = TagDef{File: d.File, Name: d.Name, Line: d.Line, Kind: d.Kind, Scope: d.Scope}
	}

	edges := make([]RefEdge, len(resp.Edges))
	for i, e := range resp.Edges {
		edges[i] = RefEdge{SrcFile: e.SrcFile, DstFile: e.DstFile, Symbol: e.DstSymbol}
	}

	return defs, edges, nil
}
```

**Step 2: Update ContentFunc to try MCP first, fall back to go/ast**

Modify `contentFunc` in `element.go` to accept an optional `EdgeFetcher`. If fetcher is non-nil and returns data, use it. Otherwise fall back to `ExtractGoTags`.

**Step 3: Write test with mock MCP response**

```go
// internal/repomap/mcp_test.go
package repomap

import "testing"

func TestParseMCPResponse(t *testing.T) {
	data := []byte(`{
		"definitions": [
			{"file": "main.go", "name": "Run", "line": 10, "kind": "func", "scope": ""}
		],
		"edges": [
			{"src_file": "cmd.go", "src_symbol": "exec", "dst_file": "main.go", "dst_symbol": "Run"}
		],
		"files_scanned": 2,
		"edge_count": 1
	}`)

	defs, edges, err := ParseMCPResponse(data)
	if err != nil {
		t.Fatal(err)
	}
	if len(defs) != 1 || defs[0].Name != "Run" {
		t.Errorf("unexpected defs: %+v", defs)
	}
	if len(edges) != 1 || edges[0].Symbol != "Run" {
		t.Errorf("unexpected edges: %+v", edges)
	}
}
```

**Step 4: Run tests**

Run: `cd os/Skaffen && go test ./internal/repomap/ -v -count=1`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/repomap/mcp.go internal/repomap/mcp_test.go internal/repomap/element.go
git commit -m "feat(repomap): add MCP edge fetcher with graceful degradation to go/ast"
```

<verify>
- run: `cd /home/mk/projects/Demarch/os/Skaffen && go test ./internal/repomap/ -v -count=1`
  expect: exit 0
</verify>

---

## Task 6: Add conversation personalization (F5)

**Files:**
- Modify: `os/Skaffen/internal/repomap/element.go` (add personalization signals)
- Create: `os/Skaffen/internal/repomap/personalize.go`
- Create: `os/Skaffen/internal/repomap/personalize_test.go`

**Step 1: Write failing test for personalization vector**

```go
// internal/repomap/personalize_test.go
package repomap

import "testing"

func TestBuildPersonalization_ChatFilesBoost(t *testing.T) {
	fileIDs := map[string]uint32{"main.go": 0, "util.go": 1, "test.go": 2}
	chatFiles := []string{"main.go"}

	pers := BuildPersonalization(fileIDs, chatFiles, nil)

	if pers[0] <= pers[1] {
		t.Errorf("chat file should have higher weight: main.go=%f util.go=%f", pers[0], pers[1])
	}
}

func TestBuildPersonalization_GitDiffBoost(t *testing.T) {
	fileIDs := map[string]uint32{"main.go": 0, "util.go": 1, "test.go": 2}
	diffFiles := []string{"util.go"}

	pers := BuildPersonalization(fileIDs, nil, diffFiles)

	if pers[1] <= pers[2] {
		t.Errorf("diff file should have higher weight: util.go=%f test.go=%f", pers[1], pers[2])
	}
}
```

**Step 2: Implement BuildPersonalization**

```go
// internal/repomap/personalize.go
package repomap

// BuildPersonalization creates a PageRank personalization vector
// from conversation signals.
// chatFiles get weight 10.0, diffFiles get weight 5.0, others get 1.0.
func BuildPersonalization(fileIDs map[string]uint32, chatFiles, diffFiles []string) map[uint32]float64 {
	pers := make(map[uint32]float64, len(fileIDs))

	// Default weight
	for _, id := range fileIDs {
		pers[id] = 1.0
	}

	// Boost git-diff files
	for _, f := range diffFiles {
		if id, ok := fileIDs[f]; ok {
			pers[id] = 5.0
		}
	}

	// Boost chat/edited files (overrides diff if overlap)
	for _, f := range chatFiles {
		if id, ok := fileIDs[f]; ok {
			pers[id] = 10.0
		}
	}

	return pers
}
```

**Step 3: Run tests**

Run: `cd os/Skaffen && go test ./internal/repomap/ -v -count=1 -run Personalization`
Expected: PASS

**Step 4: Wire personalization into ContentFunc**

Update `contentFunc` in `element.go` to accept a function that provides chat files and diff files from the session/conversation context. Pass the personalization vector to `g.Rank()`.

**Step 5: Run full test suite**

Run: `cd os/Skaffen && go test ./... -count=1`
Expected: PASS

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/repomap/
git commit -m "feat(repomap): add conversation personalization (chat files ×10, git diff ×5)"
```

<verify>
- run: `cd /home/mk/projects/Demarch/os/Skaffen && go test ./internal/repomap/ -v -count=1`
  expect: exit 0
- run: `cd /home/mk/projects/Demarch/os/Skaffen && go test ./... -count=1`
  expect: exit 0
</verify>

---

## Task 7: Integration test and cleanup

**Files:**
- Modify: `os/Skaffen/internal/repomap/element_test.go` (add integration test)
- Verify: all existing tests pass

**Step 1: Add integration test that verifies end-to-end pipeline**

Write a test that creates a temp dir with multiple Go files, cross-file references, creates the priompt Element, renders it, and verifies:
- Output contains ranked symbols
- Token count is within budget
- Files with more incoming references rank higher

**Step 2: Run full Skaffen test suite**

Run: `cd os/Skaffen && go test ./... -count=1`
Expected: PASS

**Step 3: Build binary**

Run: `cd os/Skaffen && go build ./cmd/skaffen`
Expected: SUCCESS

**Step 4: Final commit**

```bash
cd os/Skaffen && git add -A
git commit -m "test(repomap): add integration test for PageRank pipeline"
```

<verify>
- run: `cd /home/mk/projects/Demarch/os/Skaffen && go test ./... -count=1`
  expect: exit 0
- run: `cd /home/mk/projects/Demarch/os/Skaffen && go vet ./...`
  expect: exit 0
- run: `cd /home/mk/projects/Demarch/os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
</verify>
