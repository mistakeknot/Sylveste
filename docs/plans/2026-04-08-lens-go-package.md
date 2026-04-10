---
artifact_type: plan
bead: sylveste-benl.1
prd: docs/prds/2026-04-08-lens-go-package.md
brainstorm: docs/brainstorms/2026-04-08-lens-go-package-brainstorm.md
stage: plan
requirements:
  - F0: Golden fixtures from Python Auraken
  - F1: Types + data loading
  - F2: Graph algorithms
  - F3: LLM selector
  - F4: Evolution tracker
  - F5: Stack orchestrator
---

# Lens Go Package Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-benl.1
**Goal:** Port Auraken's 4-module lens system to `os/Skaffen/pkg/lens/` as a single Go package with interface boundaries.

**Architecture:** Flat package at `pkg/lens/` with `Graph`, `Selector`, `Tracker` interfaces. Data embedded via `//go:embed`. Custom Louvain and Brandes algorithms (no gonum). LLM selection via Skaffen's existing `provider.Provider` + `StreamResponse.Collect()`. Persistence via `Store` interface (callers provide implementation).

**Tech Stack:** Go 1.24, `//go:embed`, `sync.Mutex`, `encoding/json`, `sort`, `math`, `math/rand`. Python 3.12 + uv for golden fixture capture.

---

## Must-Haves

**Truths** (observable behaviors):
- `Load()` returns 291 lenses, 1779 edges, 7 communities, 15 bridges — matching Python exactly
- `Select(ctx, msg, history)` returns 0-5 lens refs via LLM, with typed errors on failure
- `RecordEvent()` updates EMA scores using identical formula to Python (`max(floor, min(1.0, current + delta))`)
- `NextPhase()` advances stack state, returns `ErrStackExhausted` when done
- All graph algorithms produce deterministic output across runs (sorted-key iteration)

**Artifacts** (files with specific exports):
- [`pkg/lens/types.go`] exports `Lens`, `Edge`, `Community`, `LensRef`, `Phase`, `Scale`, `Tier`, `Confidence`, `EvidenceLevel`, `EdgeType`
- [`pkg/lens/loader.go`] exports `Load() error`, `Reset()`, `Lenses() []Lens`, `Edges() []Edge`
- [`pkg/lens/graph.go`] exports `Graph` interface, `NewGraph(lenses, edges) Graph`
- [`pkg/lens/selector.go`] exports `Selector` interface, `NewLLMSelector(provider, graph) Selector`
- [`pkg/lens/evolution.go`] exports `Tracker` interface, `Store` interface, `NewTracker(store) Tracker`
- [`pkg/lens/stacks.go`] exports `StackOrchestrator`, `NewOrchestrator(lenses, depth) *StackOrchestrator`

**Key Links:**
- `Selector` depends on `Graph` (community-aware diversity) and `provider.Provider` (LLM calls)
- `Tracker` depends on `Store` (persistence) — no compile-time dependency on Graph or Selector
- `StackOrchestrator` is standalone — depends only on `types.go`
- `Graph` depends on `loader.go` output (lenses + edges)

---

## Task 0: Capture Golden Fixtures from Python (F0)

**Bead:** sylveste-byaw
**Files:**
- Create: `os/Skaffen/pkg/lens/testdata/golden_communities.json`
- Create: `os/Skaffen/pkg/lens/testdata/golden_bridges.json`
- Create: `os/Skaffen/pkg/lens/testdata/golden_ema.json`
- Create: `os/Skaffen/pkg/lens/testdata/golden_stacks.json`
- Create: `os/Skaffen/pkg/lens/testdata/golden_meta.json`
- Create: `apps/Auraken/scripts/capture_golden.py`

**Step 1: Write fixture capture script**
```python
# apps/Auraken/scripts/capture_golden.py
"""Capture behavioral baseline from Python Auraken for Go parity testing."""
import json, sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "src"))

from auraken.lenses import _load_library, reset_library
from auraken.lens_graph import build_graph, detect_communities, compute_bridge_scores, find_bridge_lenses, get_community_members
from auraken.lens_evolution import apply_effectiveness_update, compute_effectiveness_delta, classify_engagement
from auraken.lens_stacks import StackOrchestrator

OUTPUT = pathlib.Path(__file__).parent.parent.parent.parent / "os" / "Skaffen" / "pkg" / "lens" / "testdata"
OUTPUT.mkdir(parents=True, exist_ok=True)

# 1. Communities
lenses = _load_library()
g = build_graph()
communities = detect_communities(g)
members = get_community_members(communities)
json.dump({"lens_to_community": communities, "community_members": {str(k): v for k, v in members.items()}},
          (OUTPUT / "golden_communities.json").open("w"), indent=2)

# 2. Bridge lenses
scores = compute_bridge_scores(g)
bridges = find_bridge_lenses(g, communities, top_k=15)
bridge_data = [{"id": b, "score": scores.get(b, 0.0)} for b in bridges]
json.dump(bridge_data, (OUTPUT / "golden_bridges.json").open("w"), indent=2)

# 3. EMA trajectories
ema_sequences = {
    "engaged_5x": [("engaged", i) for i in range(5)],
    "ignored_5x": [("ignored", i) for i in range(5)],
    "pushed_back_5x": [("pushed_back", i) for i in range(5)],
    "mixed": [("engaged", 0), ("ignored", 1), ("pushed_back", 2), ("engaged", 3), ("ignored", 4)],
    "cold_start": [("engaged", 0), ("engaged", 1), ("engaged", 2), ("engaged", 3), ("engaged", 4)],
}
ema_results = {}
for name, events in ema_sequences.items():
    score = 0.5  # default start
    trajectory = [score]
    for event, usage in events:
        score = apply_effectiveness_update(score, event, usage)
        trajectory.append(score)
    ema_results[name] = trajectory
json.dump(ema_results, (OUTPUT / "golden_ema.json").open("w"), indent=2)

# 4. Stack transitions
stack_results = {}
for depth in ["deep_gold", "shallow_gold", "wax"]:
    orch = StackOrchestrator(
        lenses=["lens_A", "lens_B", "lens_C", "lens_D"],
        depth=depth,
    )
    phases = []
    for i in range(4):
        phase = orch.next_phase(f"user_input_{i}")
        phases.append(phase)
    stack_results[depth] = phases
json.dump(stack_results, (OUTPUT / "golden_stacks.json").open("w"), indent=2)

# 5. Metadata
import subprocess
sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=str(pathlib.Path(__file__).parent.parent)).decode().strip()
json.dump({"python_sha": sha, "lens_count": len(lenses), "edge_count": 1779, "community_count": 7, "bridge_count": 15},
          (OUTPUT / "golden_meta.json").open("w"), indent=2)

print(f"Golden fixtures written to {OUTPUT}")
```

**Step 2: Run capture script**
Run: `cd apps/Auraken && uv run python scripts/capture_golden.py`
Expected: "Golden fixtures written to .../testdata"

**Step 3: Verify fixture files**
Run: `ls os/Skaffen/pkg/lens/testdata/golden_*.json | wc -l`
Expected: 5

**Step 4: Commit**
```bash
git add apps/Auraken/scripts/capture_golden.py os/Skaffen/pkg/lens/testdata/golden_*.json
git commit -m "test(lens): capture golden fixtures from Python Auraken"
```

<verify>
- run: `ls os/Skaffen/pkg/lens/testdata/golden_communities.json`
  expect: exit 0
- run: `python3 -c "import json; d=json.load(open('os/Skaffen/pkg/lens/testdata/golden_communities.json')); print(len(d['lens_to_community']))"`
  expect: contains "291"
</verify>

---

## Task 1: Copy Lens Data Files + Scaffold Package (F1)

**Files:**
- Create: `os/Skaffen/pkg/lens/data/lens_library_v2.json`
- Create: `os/Skaffen/pkg/lens/data/lens_edges.json`
- Create: `os/Skaffen/pkg/lens/data/lens_communities.json`
- Create: `os/Skaffen/pkg/lens/doc.go`
**Depends:** Task 0

**Step 1: Copy data files**
```bash
mkdir -p os/Skaffen/pkg/lens/data
cp apps/Auraken/src/auraken/lens_library_v2.json os/Skaffen/pkg/lens/data/
cp apps/Auraken/src/auraken/lens_edges.json os/Skaffen/pkg/lens/data/
cp apps/Auraken/src/auraken/lens_communities.json os/Skaffen/pkg/lens/data/
```

**Step 2: Create package doc**
```go
// os/Skaffen/pkg/lens/doc.go
// Package lens provides the conceptual lens library — 291 lenses organized
// in a typed graph with community detection, LLM-based selection,
// effectiveness tracking, and sequential stack orchestration.
//
// Usage:
//
//	if err := lens.Load(); err != nil { ... }
//	graph := lens.NewGraph(lens.Lenses(), lens.Edges())
//	selector := lens.NewLLMSelector(myProvider, graph)
//	refs, err := selector.Select(ctx, "user message", nil)
package lens
```

**Step 3: Verify build**
Run: `cd os/Skaffen && go build ./pkg/lens/...`
Expected: exit 0

**Step 4: Commit**
```bash
git add os/Skaffen/pkg/lens/
git commit -m "feat(lens): scaffold pkg/lens with embedded data files"
```

<verify>
- run: `cd os/Skaffen && go build ./pkg/lens/...`
  expect: exit 0
</verify>

---

## Task 2: Define Types (F1)

**Files:**
- Create: `os/Skaffen/pkg/lens/types.go`
- Create: `os/Skaffen/pkg/lens/types_test.go`
**Depends:** Task 1

**Step 1: Write types**
```go
// os/Skaffen/pkg/lens/types.go
package lens

// Scale indicates the analytical scope of a lens.
type Scale string

const (
	ScaleMacro Scale = "macro"
	ScaleMeso  Scale = "meso"
	ScaleMicro Scale = "micro"
)

// Tier indicates the importance level of a lens.
type Tier string

const (
	TierCore     Tier = "core"
	TierExtended Tier = "extended"
)

// Confidence indicates the evidence strength behind a lens.
type Confidence string

const (
	ConfidenceEstablished  Confidence = "established"
	ConfidenceEmerging     Confidence = "emerging"
	ConfidenceSpeculative  Confidence = "speculative"
)

// EvidenceLevel indicates the type of evidence supporting a lens.
type EvidenceLevel string

const (
	EvidenceEmpirical    EvidenceLevel = "empirically_validated"
	EvidencePractitioner EvidenceLevel = "practitioner_established"
	EvidenceTheoretical  EvidenceLevel = "theoretical"
)

// EdgeType classifies the relationship between two lenses.
type EdgeType string

const (
	EdgeComplements EdgeType = "complements"
	EdgeContrasts   EdgeType = "contrasts"
	EdgeRefines     EdgeType = "refines"
	EdgeSequences   EdgeType = "sequences"
)

// LensRef is a lightweight cross-package reference to a lens.
type LensRef struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// Lens is the full conceptual framework entity.
type Lens struct {
	ID              string        `json:"id"`
	Name            string        `json:"name"`
	Definition      string        `json:"definition"`
	Scale           Scale         `json:"scale"`
	Tier            Tier          `json:"tier"`
	Context         string        `json:"context"`
	Forces          []string      `json:"forces"`
	Solution        string        `json:"solution"`
	Questions       []string      `json:"questions"`
	Examples        []string      `json:"examples"`
	Source          string        `json:"source"`
	Confidence      Confidence    `json:"confidence"`
	EvidenceLevel   EvidenceLevel `json:"evidence_level"`
	Discipline      string        `json:"discipline"`
	BridgeScore     float64       `json:"bridge_score"`
	CommunityID     int           `json:"community_id"`
	UsageCount      int           `json:"usage_count"`
	Effectiveness   float64       `json:"effectiveness_score"`
	Contraindications []string    `json:"contraindications,omitempty"`
	NearMissLenses    []string    `json:"near_miss_lenses,omitempty"`
	FailureSignatures []string    `json:"failure_signatures,omitempty"`
}

// Ref returns a lightweight reference to this lens.
func (l Lens) Ref() LensRef {
	return LensRef{ID: l.ID, Name: l.Name}
}

// Edge is a typed relationship between two lenses.
type Edge struct {
	SourceID   string   `json:"source_id"`
	TargetID   string   `json:"target_id"`
	Type       EdgeType `json:"type"`
	Confidence float64  `json:"confidence"`
	Rationale  string   `json:"rationale"`
	Provenance string   `json:"provenance"`
	Symmetric  bool     `json:"symmetric"`
}

// Community is a group of related lenses detected by Louvain.
type Community struct {
	ID      int      `json:"id"`
	Members []string `json:"members"`
}
```

**Step 2: Write round-trip test**
```go
// os/Skaffen/pkg/lens/types_test.go
package lens

import (
	"encoding/json"
	"testing"
)

func TestLensJSONRoundTrip(t *testing.T) {
	original := Lens{
		ID: "test_lens", Name: "Test", Definition: "A test lens",
		Scale: ScaleMeso, Tier: TierCore, Forces: []string{"a", "b"},
		Confidence: ConfidenceEstablished, EvidenceLevel: EvidencePractitioner,
		BridgeScore: 0.42, CommunityID: 3, Effectiveness: 0.75,
	}
	data, err := json.Marshal(original)
	if err != nil {
		t.Fatal(err)
	}
	var decoded Lens
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded.ID != original.ID || decoded.BridgeScore != original.BridgeScore {
		t.Errorf("round-trip mismatch: got %+v", decoded)
	}
}

func TestEdgeJSONRoundTrip(t *testing.T) {
	original := Edge{
		SourceID: "a", TargetID: "b", Type: EdgeComplements,
		Confidence: 0.85, Symmetric: true,
	}
	data, err := json.Marshal(original)
	if err != nil {
		t.Fatal(err)
	}
	var decoded Edge
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded.Type != original.Type || decoded.Confidence != original.Confidence {
		t.Errorf("round-trip mismatch: got %+v", decoded)
	}
}

func TestLensRef(t *testing.T) {
	l := Lens{ID: "x", Name: "X Lens"}
	ref := l.Ref()
	if ref.ID != "x" || ref.Name != "X Lens" {
		t.Errorf("unexpected ref: %+v", ref)
	}
}
```

**Step 3: Run tests**
Run: `cd os/Skaffen && go test ./pkg/lens/... -v -count=1`
Expected: PASS

**Step 4: Commit**
```bash
git add os/Skaffen/pkg/lens/types.go os/Skaffen/pkg/lens/types_test.go
git commit -m "feat(lens): define Lens, Edge, LensRef, Community types"
```

<verify>
- run: `cd os/Skaffen && go test ./pkg/lens/... -v -count=1`
  expect: exit 0
</verify>

---

## Task 3: Data Loader with Retry-Capable Init (F1)

**Files:**
- Create: `os/Skaffen/pkg/lens/loader.go`
- Create: `os/Skaffen/pkg/lens/loader_test.go`
**Depends:** Task 2

**Step 1: Write loader with state machine init**
```go
// os/Skaffen/pkg/lens/loader.go
package lens

import (
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
)

//go:embed data/lens_library_v2.json
var rawLenses []byte

//go:embed data/lens_edges.json
var rawEdges []byte

//go:embed data/lens_communities.json
var rawCommunities []byte

type loadState int

const (
	stateUnloaded loadState = iota
	stateLoaded
)

var (
	mu       sync.Mutex
	state    loadState
	lenses   []Lens
	edges    []Edge
	loadErr  error

	ErrNotLoaded      = errors.New("lens: library not loaded")
	ErrInvalidData    = errors.New("lens: embedded data failed validation")
)

// Load parses embedded JSON data and validates referential integrity.
// Safe for concurrent use. Retries on failure (not cached like sync.Once).
func Load() error {
	mu.Lock()
	defer mu.Unlock()

	if state == stateLoaded {
		return nil
	}

	if err := json.Unmarshal(rawLenses, &lenses); err != nil {
		loadErr = fmt.Errorf("lens: parse lenses: %w", err)
		return loadErr
	}
	if err := json.Unmarshal(rawEdges, &edges); err != nil {
		lenses = nil
		loadErr = fmt.Errorf("lens: parse edges: %w", err)
		return loadErr
	}

	// Validate counts
	if len(lenses) != 291 {
		loadErr = fmt.Errorf("%w: expected 291 lenses, got %d", ErrInvalidData, len(lenses))
		lenses, edges = nil, nil
		return loadErr
	}
	if len(edges) != 1779 {
		loadErr = fmt.Errorf("%w: expected 1779 edges, got %d", ErrInvalidData, len(edges))
		lenses, edges = nil, nil
		return loadErr
	}

	// Validate referential integrity: all edge IDs reference valid lenses
	lensMap := make(map[string]bool, len(lenses))
	for _, l := range lenses {
		lensMap[l.ID] = true
	}
	for i, e := range edges {
		if !lensMap[e.SourceID] {
			loadErr = fmt.Errorf("%w: edge %d references unknown source %q", ErrInvalidData, i, e.SourceID)
			lenses, edges = nil, nil
			return loadErr
		}
		if !lensMap[e.TargetID] {
			loadErr = fmt.Errorf("%w: edge %d references unknown target %q", ErrInvalidData, i, e.TargetID)
			lenses, edges = nil, nil
			return loadErr
		}
	}

	state = stateLoaded
	loadErr = nil
	return nil
}

// Reset clears all cached state. For testing only.
func Reset() {
	mu.Lock()
	defer mu.Unlock()
	state = stateUnloaded
	lenses = nil
	edges = nil
	loadErr = nil
}

// Lenses returns all loaded lenses. Must call Load() first.
func Lenses() []Lens {
	mu.Lock()
	defer mu.Unlock()
	return lenses
}

// Edges returns all loaded edges. Must call Load() first.
func Edges() []Edge {
	mu.Lock()
	defer mu.Unlock()
	return edges
}
```

**Step 2: Write loader tests**
```go
// os/Skaffen/pkg/lens/loader_test.go
package lens

import "testing"

func TestLoadAndReset(t *testing.T) {
	Reset()
	if err := Load(); err != nil {
		t.Fatalf("Load failed: %v", err)
	}
	if len(Lenses()) != 291 {
		t.Errorf("expected 291 lenses, got %d", len(Lenses()))
	}
	if len(Edges()) != 1779 {
		t.Errorf("expected 1779 edges, got %d", len(Edges()))
	}

	// Reset and verify cleared
	Reset()
	if Lenses() != nil {
		t.Error("expected nil lenses after Reset")
	}

	// Reload should work (retry capability)
	if err := Load(); err != nil {
		t.Fatalf("Load after Reset failed: %v", err)
	}
	if len(Lenses()) != 291 {
		t.Error("lenses not reloaded after Reset")
	}
}

func TestLoadIdempotent(t *testing.T) {
	Reset()
	if err := Load(); err != nil {
		t.Fatal(err)
	}
	if err := Load(); err != nil {
		t.Fatal("second Load should succeed:", err)
	}
}
```

**Step 3: Run tests**
Run: `cd os/Skaffen && go test ./pkg/lens/... -v -count=1`
Expected: PASS

**Step 4: Commit**
```bash
git add os/Skaffen/pkg/lens/loader.go os/Skaffen/pkg/lens/loader_test.go
git commit -m "feat(lens): retry-capable loader with referential integrity validation"
```

<verify>
- run: `cd os/Skaffen && go test ./pkg/lens/... -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./pkg/lens/... -run TestLoadAndReset -v`
  expect: contains "PASS"
</verify>

---

## Task 4: Graph Interface + Adjacency List (F2)

**Files:**
- Create: `os/Skaffen/pkg/lens/graph.go`
- Create: `os/Skaffen/pkg/lens/graph_test.go`
**Depends:** Task 3

**Step 1: Write Graph interface and implementation**
```go
// os/Skaffen/pkg/lens/graph.go
package lens

import "sort"

// Graph provides read-only access to the lens relationship graph.
type Graph interface {
	Communities() []Community
	BridgeLenses() []LensRef
	Neighbors(lensID string, edgeType EdgeType) []LensRef
	CommunityOf(lensID string) (int, bool)
	BridgeScore(lensID string) float64
}

// adjacencyEntry stores the neighbors of a single lens, grouped by edge type.
type adjacencyEntry struct {
	byType map[EdgeType][]string
}

type graph struct {
	adj          map[string]*adjacencyEntry
	communities  []Community
	communityOf  map[string]int
	bridgeLenses []LensRef
	bridgeScores map[string]float64
	lensMap      map[string]Lens
}

// NewGraph builds a graph from loaded lenses and edges. Communities and
// bridge scores are populated by RunLouvain() and RunBetweenness().
func NewGraph(lenses []Lens, edges []Edge) *graph {
	g := &graph{
		adj:          make(map[string]*adjacencyEntry, len(lenses)),
		communityOf:  make(map[string]int, len(lenses)),
		bridgeScores: make(map[string]float64, len(lenses)),
		lensMap:      make(map[string]Lens, len(lenses)),
	}
	for _, l := range lenses {
		g.adj[l.ID] = &adjacencyEntry{byType: make(map[EdgeType][]string)}
		g.lensMap[l.ID] = l
	}
	for _, e := range edges {
		if entry, ok := g.adj[e.SourceID]; ok {
			entry.byType[e.Type] = append(entry.byType[e.Type], e.TargetID)
		}
		if e.Symmetric {
			if entry, ok := g.adj[e.TargetID]; ok {
				entry.byType[e.Type] = append(entry.byType[e.Type], e.SourceID)
			}
		}
	}
	return g
}

func (g *graph) Communities() []Community       { return g.communities }
func (g *graph) BridgeLenses() []LensRef        { return g.bridgeLenses }
func (g *graph) BridgeScore(id string) float64  { return g.bridgeScores[id] }

func (g *graph) CommunityOf(id string) (int, bool) {
	c, ok := g.communityOf[id]
	return c, ok
}

func (g *graph) Neighbors(id string, edgeType EdgeType) []LensRef {
	entry, ok := g.adj[id]
	if !ok {
		return nil
	}
	ids := entry.byType[edgeType]
	refs := make([]LensRef, 0, len(ids))
	for _, nid := range ids {
		if l, ok := g.lensMap[nid]; ok {
			refs = append(refs, l.Ref())
		}
	}
	sort.Slice(refs, func(i, j int) bool { return refs[i].ID < refs[j].ID })
	return refs
}

// AllNeighborIDs returns all neighbor IDs regardless of edge type, sorted.
// Used internally by graph algorithms.
func (g *graph) AllNeighborIDs(id string) []string {
	entry, ok := g.adj[id]
	if !ok {
		return nil
	}
	seen := make(map[string]bool)
	for _, ids := range entry.byType {
		for _, nid := range ids {
			seen[nid] = true
		}
	}
	result := make([]string, 0, len(seen))
	for nid := range seen {
		result = append(result, nid)
	}
	sort.Strings(result)
	return result
}

// SortedNodeIDs returns all node IDs sorted lexicographically.
// Used by Louvain and Betweenness to ensure deterministic iteration.
func (g *graph) SortedNodeIDs() []string {
	ids := make([]string, 0, len(g.adj))
	for id := range g.adj {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}
```

**Step 2: Write graph tests using golden fixtures**
Test that graph builds correctly, neighbors are sorted, CommunityOf works after Louvain populates it. (Louvain in Task 5.)

**Step 3: Run tests**
Run: `cd os/Skaffen && go test ./pkg/lens/... -v -count=1`
Expected: PASS

**Step 4: Commit**
```bash
git add os/Skaffen/pkg/lens/graph.go os/Skaffen/pkg/lens/graph_test.go
git commit -m "feat(lens): Graph interface with typed-edge adjacency list"
```

<verify>
- run: `cd os/Skaffen && go test ./pkg/lens/... -v -count=1`
  expect: exit 0
</verify>

---

## Task 5: Louvain Community Detection (F2)

**Files:**
- Create: `os/Skaffen/pkg/lens/louvain.go`
- Create: `os/Skaffen/pkg/lens/louvain_test.go`
**Depends:** Task 4

**Step 1: Implement Louvain with sorted-key iteration**
Custom Louvain matching networkx: resolution=1.0, deterministic via sorted node IDs at every iteration point. Uses `math/rand` with `rand.NewSource(42)` for tie-breaking only (not for node visit order — that is always sorted).

**Step 2: Write parity test against golden fixtures**
Load `testdata/golden_communities.json`, run Louvain on real data, assert exact per-lens community membership match.

**Step 3: Write 10-run determinism test**
Run Louvain 10 times, assert identical community assignments each time.

**Step 4: Commit**

<verify>
- run: `cd os/Skaffen && go test ./pkg/lens/... -run TestLouvain -v -count=1`
  expect: exit 0
</verify>

---

## Task 6: Brandes Betweenness Centrality (F2)

**Files:**
- Create: `os/Skaffen/pkg/lens/betweenness.go`
- Create: `os/Skaffen/pkg/lens/betweenness_test.go`
**Depends:** Task 5

**Step 1: Implement Brandes algorithm**
Sorted-key iteration. Unweighted (matching Python behavior — edge confidence is NOT used in centrality). Normalize for undirected graph.

**Step 2: Write parity test against golden fixtures**
Load `testdata/golden_bridges.json`, run betweenness on real data, assert exact bridge lens set and scores within tolerance (1e-10).

**Step 3: Commit**

<verify>
- run: `cd os/Skaffen && go test ./pkg/lens/... -run TestBetweenness -v -count=1`
  expect: exit 0
</verify>

---

## Task 7: LLM Selector (F3)

**Files:**
- Create: `os/Skaffen/pkg/lens/selector.go`
- Create: `os/Skaffen/pkg/lens/selector_test.go`
**Depends:** Task 4

**Step 1: Define Selector interface and errors**
```go
type Selector interface {
    Select(ctx context.Context, message string, history []string) ([]LensRef, error)
}

var (
    ErrSelectionTimeout    = errors.New("lens: selection timed out")
    ErrProviderUnavailable = errors.New("lens: provider unavailable")
    ErrInvalidResponse     = errors.New("lens: invalid LLM response")
)
```

**Step 2: Implement LLMSelector**
- Build 1-indexed lens index matching Python format: `[macro] 1. Lens Name`
- Construct system prompt matching `apps/Auraken/src/auraken/lenses.py:300-330`
- Call `provider.Stream()` then `Collect()` to get full text
- Parse JSON array from response: handle markdown fences, wrapped objects, extra text
- Validate indices: 1 ≤ idx ≤ len(lenses), skip invalid with log
- 15-second context timeout via `context.WithTimeout`
- Return typed errors on failure, `([]LensRef{}, nil)` only for genuine empty selection

**Step 3: Write tests with mock provider**
Use `provider.Mock` from `os/Skaffen/internal/provider/mock.go` to return canned responses matching golden fixture format.

**Step 4: Commit**

<verify>
- run: `cd os/Skaffen && go test ./pkg/lens/... -run TestSelector -v -count=1`
  expect: exit 0
</verify>

---

## Task 8: Evolution Tracker (F4)

**Files:**
- Create: `os/Skaffen/pkg/lens/evolution.go`
- Create: `os/Skaffen/pkg/lens/evolution_test.go`
**Depends:** Task 2

**Step 1: Define Store and Tracker interfaces**
```go
type Store interface {
    Load(ctx context.Context) error
    RecordEvent(ctx context.Context, lensID, userID, event string) error
    UsageCount(ctx context.Context, lensID string) (int, error)
    Effectiveness(ctx context.Context, lensID string) (float64, error)
    Flush(ctx context.Context) error
}

type Tracker interface {
    RecordEvent(lensID, userID, event string) error
    Effectiveness(lensID string) float64
}
```

**Step 2: Implement EMA with exact Python formula**
```go
const (
    engagedDelta   = 0.1
    ignoredDelta   = -0.05
    pushedBackDelta = -0.1
    confidenceFloor = 0.1
    explorationBonus = 0.15
    explorationThreshold = 3
)

func applyEffectivenessUpdate(current float64, event string, usageCount int) float64 {
    delta := computeDelta(event)
    if usageCount < explorationThreshold {
        delta += explorationBonus
    }
    newScore := current + delta
    if newScore < confidenceFloor {
        return confidenceFloor
    }
    if newScore > 1.0 {
        return 1.0
    }
    return newScore
}
```

**Step 3: Implement engagement classification**
Port `classify_engagement()` from `lens_evolution.py:97-127` with byte-identical phrase lists.

**Step 4: Write parity tests against golden EMA trajectories**
Load `testdata/golden_ema.json`, run the same event sequences, assert identical score trajectories.

**Step 5: Write concurrent safety test with -race**

**Step 6: Commit**

<verify>
- run: `cd os/Skaffen && go test ./pkg/lens/... -run TestEvolution -v -count=1 -race`
  expect: exit 0
</verify>

---

## Task 9: Stack Orchestrator (F5)

**Files:**
- Create: `os/Skaffen/pkg/lens/stacks.go`
- Create: `os/Skaffen/pkg/lens/stacks_test.go`
**Depends:** Task 2

**Step 1: Define Phase enum and errors**
```go
type Phase int

const (
    PhaseBase Phase = iota
    PhaseMid
    PhaseDeep
    PhaseFinal
)

var ErrStackExhausted = errors.New("lens: stack exhausted")
```

**Step 2: Implement StackOrchestrator**
- `sync.Mutex` protecting all state
- `NextPhase(userInput string) (PhaseResult, error)` — returns ErrStackExhausted when done
- Transition templates as constants matching Python's `lens_stacks.py:75-88`
- `ToJSON() / FromJSON()` with all fields exported

**Step 3: Write parity tests against golden stack transitions**
Load `testdata/golden_stacks.json`, run identical sequences, assert matching transition text.

**Step 4: Write JSON round-trip test**

**Step 5: Commit**

<verify>
- run: `cd os/Skaffen && go test ./pkg/lens/... -run TestStack -v -count=1`
  expect: exit 0
</verify>

---

## Task 10: Integration Test + Final Verification

**Files:**
- Create: `os/Skaffen/pkg/lens/integration_test.go`
**Depends:** Tasks 5, 6, 7, 8, 9

**Step 1: Write integration test**
Full pipeline: `Load()` → `NewGraph()` → `RunLouvain()` → `RunBetweenness()` → verify communities + bridges against golden fixtures → create Tracker with in-memory Store → record events → verify EMA → create Stack → advance all phases.

**Step 2: Run full test suite**
Run: `cd os/Skaffen && go test ./pkg/lens/... -v -count=1 -race`
Expected: all PASS

**Step 3: Run vet**
Run: `cd os/Skaffen && go vet ./pkg/lens/...`
Expected: exit 0

**Step 4: Final commit**
```bash
git add os/Skaffen/pkg/lens/
git commit -m "feat(lens): complete lens Go package — types, loader, graph, selector, evolution, stacks"
```

<verify>
- run: `cd os/Skaffen && go test ./pkg/lens/... -v -count=1 -race`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./pkg/lens/...`
  expect: exit 0
</verify>
