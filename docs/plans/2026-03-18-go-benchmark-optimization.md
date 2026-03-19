---
artifact_type: plan
bead: Demarch-0pvp
stage: design
requirements:
  - F1: classifyFailure optimization
  - F2: estimateMessageTokens caching
  - F3: trust.Evaluate pre-compiled patterns
  - F4: classifyComplexity regex elimination
  - F5: extractFileActivity pre-filter
  - F6: PageRank array pooling
  - F7: ScoreMessages min-heap
  - F8: composePlan fleet indexing
  - F9: parseFrontmatter caching
  - F10: scoring Assign pre-allocation
  - F11: TopologicalSort heap queue
  - F12: DiffSpecs map-based diff
  - F13: ReconcileProject mtime caching
  - F14: Hub.Broadcast snapshot pooling
  - F15: PatternsOverlap pre-normalization
  - F16: convertToolDefs caching
  - F17: AtomicWriteFile profiling
---

# Go Benchmark-Driven Optimization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-0pvp
**Goal:** Reduce ns/op and allocs/op across 17 hot-path Go functions in 5 pillars, gated by interlab harness benchmarks.

**Architecture:** Each task follows a strict benchmark→optimize→verify cycle. Write the benchmark first (`_bench_test.go`), record baseline, apply optimization, verify improvement, update interlab harness if needed. No API signature changes — all internal.

**Tech Stack:** Go 1.24 (Skaffen, Autarch, Intermute), Go 1.22 (Intercore, Clavain CLI). `go test -bench`. interlab go-bench-harness.sh.

**Prior Learnings:**
- `docs/solutions/patterns/bubble-tea-pointer-cache-safety-20260223.md` — Go pointer caching is safe without mutexes in single-goroutine architectures. Applies to Skaffen agentloop caching (F2, F16) since the loop is single-threaded per session.
- Past session on interlab optimization: pre-allocation and reduced allocs in string building are valid even if benchmark variance is noisy. Always use median of 5 runs.

---

## Must-Haves

**Truths** (observable behaviors):
- All existing unit tests pass after every optimization
- Interlab harness produces METRIC output for every new benchmark
- No function signature changes — all optimizations are internal
- Each optimization has a measurable ns/op or allocs/op improvement over baseline

**Artifacts** (files with specific exports):
- Each target gets a `*_bench_test.go` file with `Benchmark*` functions
- Each pillar's `interlab.sh` is updated if new primary metrics are added

**Key Links** (connections where breakage cascades):
- Skaffen agentloop functions are called sequentially per turn — no concurrency concerns for caching
- Intercore scoring.Assign is called by dispatch — output ordering must be deterministic
- Clavain composePlan output is JSON-serialized — field order changes would break downstream

---

## Wave 1: Per-Turn Hot Paths

### Task 1: F4 — Optimize classifyComplexity (Clavain CLI)

**Bead:** Demarch-0pvp.1
**Files:**
- Modify: `os/Clavain/cmd/clavain-cli/complexity.go`
- Test: `os/Clavain/cmd/clavain-cli/complexity_bench_test.go` (exists)

**Step 1: Record baseline**
Run: `cd os/Clavain/cmd/clavain-cli && go test -bench='BenchmarkClassifyComplexityModerate$' -benchmem -count=5 -run='^$' .`
Record: ns/op, B/op, allocs/op (expected ~24us, ~2.5KB, ~55 allocs)

**Step 2: Replace regex with single-pass scanner**
Replace `wordPattern.FindAllString(desc, -1)` with a hand-rolled word scanner that extracts `[a-zA-Z][a-zA-Z0-9-]*` tokens in a single pass. Pre-lowercase the entire input once with `strings.ToLower(desc)` before scanning, eliminating per-word `ToLower` calls in `countMatches`.

```go
func classifyComplexity(desc string) int {
	if desc == "" {
		return 3
	}
	words := strings.Fields(desc)
	wordCount := len(words)
	if wordCount < 5 {
		return 3
	}

	lower := strings.ToLower(desc)
	// Single-pass keyword counting on pre-lowered input
	trivialCount := countMatchesLower(lower, trivialKeywords)
	researchCount := countMatchesLower(lower, researchKeywords)
	ambiguityCount := countMatchesLower(lower, ambiguitySignals)
	simplicityCount := countMatchesLower(lower, simplicitySignals)

	// ... rest unchanged
}

// countMatchesLower counts keyword occurrences in already-lowered text.
// Uses word boundary detection instead of regex.
func countMatchesLower(lower string, keywords map[string]bool) int {
	count := 0
	for kw := range keywords {
		idx := 0
		for {
			i := strings.Index(lower[idx:], kw)
			if i < 0 {
				break
			}
			pos := idx + i
			// Check word boundaries
			before := pos == 0 || !isWordChar(lower[pos-1])
			after := pos+len(kw) >= len(lower) || !isWordChar(lower[pos+len(kw)])
			if before && after {
				count++
			}
			idx = pos + len(kw)
		}
	}
	return count
}

func isWordChar(b byte) bool {
	return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9') || b == '-'
}
```

**Step 3: Run benchmark to verify improvement**
Run: `cd os/Clavain/cmd/clavain-cli && go test -bench='BenchmarkClassifyComplexity' -benchmem -count=5 -run='^$' .`
Expected: <8us, <500B, <10 allocs (>60% improvement)

**Step 4: Run existing tests**
Run: `cd os/Clavain/cmd/clavain-cli && go test -run='TestClassify|TestComplexity' -v .`
Expected: PASS

**Step 5: Commit**
```bash
cd os/Clavain && git add cmd/clavain-cli/complexity.go
git -c user.name="mistakeknot" -c user.email="mistakeknot@users.noreply.github.com" commit -m "perf(complexity): replace regex with single-pass scanner — target <5us/5 allocs"
git push
```

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && go test -run='TestClassify|TestComplexity' -v .`
  expect: exit 0
- run: `cd os/Clavain/cmd/clavain-cli && go test -bench='BenchmarkClassifyComplexityModerate$' -benchmem -count=1 -run='^$' .`
  expect: contains "ns/op"
</verify>

---

### Task 2: F1 — Benchmark + Optimize classifyFailure (Skaffen agentloop)

**Bead:** Demarch-0pvp.11
**Files:**
- Modify: `os/Skaffen/internal/agentloop/loop.go`
- Create: `os/Skaffen/internal/agentloop/loop_bench_test.go`

**Step 1: Read classifyFailure to understand current implementation**
Read: `os/Skaffen/internal/agentloop/loop.go` — find classifyFailure function, note pattern lists and search logic.

**Step 2: Write benchmark**
Create `os/Skaffen/internal/agentloop/loop_bench_test.go` with:
- `BenchmarkClassifyFailure1K` — 1K char input (short error)
- `BenchmarkClassifyFailure10K` — 10K char input (typical bash output)
- `BenchmarkClassifyFailure100K` — 100K char input (large test suite output)
Generate realistic test data with embedded error patterns at various positions.

**Step 3: Record baseline**
Run: `cd os/Skaffen && go test -bench='BenchmarkClassifyFailure' -benchmem -count=5 -run='^$' ./internal/agentloop/`

**Step 4: Optimize — pre-lowercase once, compiled pattern set**
- Call `strings.ToLower()` once on the full content
- Build a single `strings.Contains` check list instead of two separate loops
- Consider `strings.NewReplacer` or `bytes.Contains` for zero-alloc matching

**Step 5: Run benchmark to verify improvement**
Run: `cd os/Skaffen && go test -bench='BenchmarkClassifyFailure' -benchmem -count=5 -run='^$' ./internal/agentloop/`
Expected: >50% improvement on 10K input

**Step 6: Run existing tests**
Run: `cd os/Skaffen && go test ./internal/agentloop/ -v`
Expected: PASS

**Step 7: Commit**
```bash
cd os/Skaffen && git add internal/agentloop/loop.go internal/agentloop/loop_bench_test.go
git commit -m "perf(agentloop): optimize classifyFailure — pre-lowercase + single-pass patterns"
git push
```

<verify>
- run: `cd os/Skaffen && go test ./internal/agentloop/ -v`
  expect: exit 0
- run: `cd os/Skaffen && go test -bench='BenchmarkClassifyFailure10K$' -benchmem -count=1 -run='^$' ./internal/agentloop/`
  expect: contains "ns/op"
</verify>

---

### Task 3: F5 — Benchmark + Optimize extractFileActivity (Skaffen agentloop)

**Bead:** Demarch-0pvp.13
**Files:**
- Modify: `os/Skaffen/internal/agentloop/loop.go`
- Add to: `os/Skaffen/internal/agentloop/loop_bench_test.go`

**Step 1: Read extractFileActivity implementation**
Read the function to understand how it processes tool calls and which tools trigger JSON unmarshal.

**Step 2: Write benchmark**
Add to `loop_bench_test.go`:
- `BenchmarkExtractFileActivity50Calls` — 50 tool calls, 5% file ops
- `BenchmarkExtractFileActivity100Calls` — 100 tool calls, 5% file ops

**Step 3: Record baseline, optimize, verify**
Add tool name pre-filter check before `json.Unmarshal`. Only unmarshal when tool name is in `filePathTools` map.

**Step 4: Run tests + commit**

<verify>
- run: `cd os/Skaffen && go test ./internal/agentloop/ -v`
  expect: exit 0
- run: `cd os/Skaffen && go test -bench='BenchmarkExtractFileActivity' -benchmem -count=1 -run='^$' ./internal/agentloop/`
  expect: contains "ns/op"
</verify>

---

### Task 4: F3 — Benchmark + Optimize trust.Evaluator.Evaluate (Skaffen trust)

**Bead:** Demarch-0pvp.16
**Files:**
- Modify: `os/Skaffen/internal/trust/trust.go`
- Create: `os/Skaffen/internal/trust/trust_bench_test.go`

**Step 1: Read trust.go to understand Evaluate and Learn**
Note the override slice structure, filepath.Match usage, and lock patterns.

**Step 2: Write benchmark**
- `BenchmarkEvaluate5Overrides` — 5 learned overrides
- `BenchmarkEvaluate50Overrides` — 50 overrides
- `BenchmarkEvaluate500Overrides` — 500 overrides

**Step 3: Record baseline, then optimize**
Strategy: Pre-compile overrides into a map keyed by directory prefix (first path segment). On Evaluate, extract prefix from path, look up candidate overrides, only glob-match those. Falls from O(n) to O(k) where k = overrides in same directory.

Alternative: On `Learn()`, partition overrides into exact-match (no glob chars) and glob-match. Exact matches use map lookup O(1). Only glob patterns need linear scan.

**Step 4: Verify improvement, run tests, commit**

<verify>
- run: `cd os/Skaffen && go test ./internal/trust/ -v`
  expect: exit 0
- run: `cd os/Skaffen && go test -bench='BenchmarkEvaluate50Overrides$' -benchmem -count=1 -run='^$' ./internal/trust/`
  expect: contains "ns/op"
</verify>

---

### Task 5: F2 — Benchmark + Optimize estimateMessageTokens (Skaffen agentloop)

**Bead:** Demarch-0pvp.12
**Files:**
- Modify: `os/Skaffen/internal/agentloop/loop.go`
- Add to: `os/Skaffen/internal/agentloop/loop_bench_test.go`

**Step 1: Read estimateMessageTokens**
Note how it iterates messages and calls h.Count() per block.

**Step 2: Write benchmark**
- `BenchmarkEstimateTokens50Messages` — 50 messages
- `BenchmarkEstimateTokens200Messages` — 200 messages

**Step 3: Optimize with caching**
Add a `tokenCache map[*Message]int` field to the loop struct. On each call, only count tokens for messages not in cache. Since agentloop is single-threaded per session (per bubble-tea-pointer-cache-safety learning), no mutex needed.

Cache invalidation: clear entry when message content changes (track by pointer identity — new messages get new pointers in Go).

**Step 4: Verify >80% improvement on steady-state, run tests, commit**

<verify>
- run: `cd os/Skaffen && go test ./internal/agentloop/ -v`
  expect: exit 0
- run: `cd os/Skaffen && go test -bench='BenchmarkEstimateTokens' -benchmem -count=1 -run='^$' ./internal/agentloop/`
  expect: contains "ns/op"
</verify>

---

## Wave 2: Per-Session Paths

### Task 6: F8 — Optimize composePlan (Clavain CLI)

**Bead:** Demarch-0pvp.5
**Files:**
- Modify: `os/Clavain/cmd/clavain-cli/compose.go`
- Test: `os/Clavain/cmd/clavain-cli/compose_bench_test.go` (exists)

**Step 1: Record baseline**
Run: `cd os/Clavain/cmd/clavain-cli && go test -bench='BenchmarkComposePlan30Agents$' -benchmem -count=5 -run='^$' .`

**Step 2: Build role index at plan start**
```go
type roleIndex struct {
	byRole map[string][]matchedAgent
}

func buildRoleIndex(fleet map[string]FleetAgent) roleIndex {
	idx := roleIndex{byRole: make(map[string][]matchedAgent)}
	for id, agent := range fleet {
		if agent.OrphanedAt != "" {
			continue
		}
		for _, r := range agent.Roles {
			idx.byRole[r] = append(idx.byRole[r], matchedAgent{id: id, agent: agent})
		}
	}
	// Pre-sort candidates by ColdStartTokens for each role
	for _, candidates := range idx.byRole {
		sort.Slice(candidates, func(i, j int) bool {
			if candidates[i].agent.ColdStartTokens == candidates[j].agent.ColdStartTokens {
				return candidates[i].id < candidates[j].id
			}
			return candidates[i].agent.ColdStartTokens < candidates[j].agent.ColdStartTokens
		})
	}
	return idx
}

func (ri roleIndex) matchRole(role AgentRole, excluded map[string]bool) (matchedAgent, bool) {
	candidates := ri.byRole[role.Role]
	for _, c := range candidates {
		if !excluded[c.id] {
			return c, true
		}
	}
	return matchedAgent{}, false
}
```

**Step 3: Verify improvement**
Expected: <40us, <20KB, <30 allocs at 30 agents

**Step 4: Run tests, commit, push**

<verify>
- run: `cd os/Clavain/cmd/clavain-cli && go test -run='TestCompose' -v .`
  expect: exit 0
- run: `cd os/Clavain/cmd/clavain-cli && go test -bench='BenchmarkComposePlan30Agents$' -benchmem -count=1 -run='^$' .`
  expect: contains "ns/op"
</verify>

---

### Task 7: F4 — Optimize classifyComplexity (already Task 1 — skip)

This is a duplicate of Task 1 (F4). Skip.

---

### Task 8: F9 — Optimize parseFrontmatter (Skaffen skill)

**Bead:** Demarch-0pvp.4
**Files:**
- Modify: `os/Skaffen/internal/skill/skill.go`
- Test: `os/Skaffen/internal/skill/skill_bench_test.go` (exists)

**Step 1: Record baseline**
Run: `cd os/Skaffen && go test -bench='BenchmarkParseFrontmatter$' -benchmem -count=5 -run='^$' ./internal/skill/`

**Step 2: Replace yaml.Unmarshal with targeted field extraction**
For the 6-field `frontmatter` struct, scan YAML line-by-line extracting known keys. Only fall back to `yaml.Unmarshal` for `triggers` (YAML list) which is harder to hand-parse.

```go
func parseFrontmatterFast(data []byte) (frontmatter, error) {
	// ... find YAML section between --- delimiters (same as before)
	var fm frontmatter
	scanner := bufio.NewScanner(bytes.NewReader(yamlBytes))
	for scanner.Scan() {
		line := scanner.Text()
		if k, v, ok := splitYAMLLine(line); ok {
			switch k {
			case "name":
				fm.Name = v
			case "description":
				fm.Description = v
			case "args":
				fm.Args = v
			case "model":
				fm.Model = v
			case "user_invocable":
				b := v == "true"
				fm.UserInvocable = &b
			}
		}
	}
	// For triggers, only unmarshal if "triggers:" found
	if bytes.Contains(yamlBytes, []byte("triggers:")) {
		yaml.Unmarshal(yamlBytes, &fm) // only for triggers field
	}
	return fm, nil
}
```

**Step 3: Verify improvement**
Expected: <8us without triggers, ~15us with triggers (vs 20us baseline)

**Step 4: Run tests, commit, push**

<verify>
- run: `cd os/Skaffen && go test ./internal/skill/ -v`
  expect: exit 0
- run: `cd os/Skaffen && go test -bench='BenchmarkParseFrontmatter$' -benchmem -count=1 -run='^$' ./internal/skill/`
  expect: contains "ns/op"
</verify>

---

### Task 9: F6 — Benchmark + Optimize Graph.Rank PageRank (Skaffen repomap)

**Bead:** Demarch-0pvp.14
**Files:**
- Modify: `os/Skaffen/internal/repomap/pagerank.go`
- Create: `os/Skaffen/internal/repomap/pagerank_bench_test.go`

**Step 1: Read pagerank.go, write benchmark**
Create benchmarks for 100, 500, 1000 node graphs with 5x edges.

**Step 2: Record baseline, then optimize**
- Pre-sort node list once (eliminate map iteration randomness)
- Pool rank/newRank float64 slices with sync.Pool
- Add early convergence: if max(|newRank[i] - rank[i]|) < 1e-6, break

**Step 3: Verify >30% improvement on 500 nodes, run tests, commit**

<verify>
- run: `cd os/Skaffen && go test ./internal/repomap/ -v`
  expect: exit 0
- run: `cd os/Skaffen && go test -bench='BenchmarkRank500$' -benchmem -count=1 -run='^$' ./internal/repomap/`
  expect: contains "ns/op"
</verify>

---

### Task 10: F7 — Benchmark + Optimize ScoreMessages + TopK (Skaffen session)

**Bead:** Demarch-0pvp.15
**Files:**
- Modify: `os/Skaffen/internal/session/scoring.go`
- Create: `os/Skaffen/internal/session/scoring_bench_test.go`

**Step 1: Read scoring.go, write benchmark**
Benchmarks for 50, 200, 1000 messages with K=50.

**Step 2: Optimize with container/heap**
Replace `sort.Slice` + slice truncation with `container/heap` min-heap of size K. Push all scores, pop when heap exceeds K. O(n log k) vs O(n log n).

**Step 3: Verify >40% improvement when K<<N, run tests, commit**

<verify>
- run: `cd os/Skaffen && go test ./internal/session/ -v`
  expect: exit 0
- run: `cd os/Skaffen && go test -bench='BenchmarkScoreMessages' -benchmem -count=1 -run='^$' ./internal/session/`
  expect: contains "ns/op"
</verify>

---

## Wave 3: Algorithmic Improvements

### Task 11: F10 — Reduce scoring Assign allocations (Intercore)

**Bead:** Demarch-0pvp.2
**Files:**
- Modify: `core/intercore/internal/scoring/scoring.go`
- Test: `core/intercore/internal/scoring/scoring_bench_test.go` (exists)

**Step 1: Record baseline**
Run: `cd core/intercore && go test -bench='BenchmarkAssign20x8$' -benchmem -count=5 -run='^$' ./internal/scoring/`

**Step 2: Optimize scoreAllPairs**
- Pre-allocate pairs slice to exact capacity `len(tasks) * len(agents)` (already done — verify)
- Pre-build reservations map once, pass by reference
- For selectAssignments: if strategy is Quality, use `container/heap` for top-N instead of full sort

**Step 3: Verify <70us/<15 allocs, run tests, commit**

<verify>
- run: `cd core/intercore && go test ./internal/scoring/ -v`
  expect: exit 0
- run: `cd core/intercore && go test -bench='BenchmarkAssign20x8$' -benchmem -count=1 -run='^$' ./internal/scoring/`
  expect: contains "ns/op"
</verify>

---

### Task 12: F11 — Optimize TopologicalSort (Intercore portfolio)

**Bead:** Demarch-0pvp.3
**Files:**
- Modify: `core/intercore/internal/portfolio/topo.go`
- Test: `core/intercore/internal/portfolio/topo_bench_test.go` (exists)

**Step 1: Record baseline**
Run: `cd core/intercore && go test -bench='BenchmarkTopologicalSort50$' -benchmem -count=5 -run='^$' ./internal/portfolio/`

**Step 2: Replace sort.Strings with heap**
Use `container/heap` for the ready queue. Insert nodes in sorted order. Pop min each iteration. Eliminates per-iteration `sort.Strings` call which dominates allocations.

```go
type stringHeap []string
func (h stringHeap) Len() int            { return len(h) }
func (h stringHeap) Less(i, j int) bool  { return h[i] < h[j] }
func (h stringHeap) Swap(i, j int)       { h[i], h[j] = h[j], h[i] }
func (h *stringHeap) Push(x any)         { *h = append(*h, x.(string)) }
func (h *stringHeap) Pop() any {
	old := *h
	n := len(old)
	x := old[n-1]
	*h = old[:n-1]
	return x
}
```

**Step 3: Verify deterministic output preserved**
Run existing tests to ensure output order matches exactly.

**Step 4: Verify <15us/<50 allocs, commit**

<verify>
- run: `cd core/intercore && go test ./internal/portfolio/ -v`
  expect: exit 0
- run: `cd core/intercore && go test -bench='BenchmarkTopologicalSort50$' -benchmem -count=1 -run='^$' ./internal/portfolio/`
  expect: contains "ns/op"
</verify>

---

### Task 13: F12 — Optimize DiffSpecs (Autarch gurgeh)

**Bead:** Demarch-0pvp.6
**Files:**
- Modify: `apps/Autarch/internal/gurgeh/diff/diff.go`
- Test: `apps/Autarch/internal/gurgeh/diff/diff_bench_test.go` (exists)

**Step 1: Record baseline**
Run: `cd apps/Autarch && go test -bench='BenchmarkDiffSpecs50$' -benchmem -count=5 -run='^$' ./internal/gurgeh/diff/`

**Step 2: Replace linear diffRequirements with map-based set diff**
Build `oldSet := map[string]bool{}` from old requirements. Iterate new requirements once: if in oldSet, mark seen; if not, it's added. Remaining unseen in oldSet are removed. O(n+m) vs O(n*m).

Apply same pattern to `diffAcceptanceCriteria` and `diffCUJs`.

**Step 3: Verify <20us/<80 allocs, run tests, commit**

<verify>
- run: `cd apps/Autarch && go test ./internal/gurgeh/diff/ -v`
  expect: exit 0
- run: `cd apps/Autarch && go test -bench='BenchmarkDiffSpecs50$' -benchmem -count=1 -run='^$' ./internal/gurgeh/diff/`
  expect: contains "ns/op"
</verify>

---

### Task 14: F13 — Benchmark ReconcileProject (Autarch events)

**Bead:** Demarch-0pvp.19
**Files:**
- Modify: `apps/Autarch/pkg/events/reconcile.go`
- Create: `apps/Autarch/pkg/events/reconcile_bench_test.go`

**Step 1: Read reconcile.go, write benchmark using temp directories with synthetic spec files**
Create benchmarks for 10, 100, 500 files. Use `testing.TempDir()` with pre-populated YAML files.

**Step 2: Add mtime-based skip**
Before computing SHA256, check file mtime against last-reconciled time. If unchanged, skip hash computation. Store last-reconciled mtimes in a `map[string]time.Time`.

**Step 3: Verify >90% reduction for no-change case, run tests, commit**

<verify>
- run: `cd apps/Autarch && go test ./pkg/events/ -v`
  expect: exit 0
- run: `cd apps/Autarch && go test -bench='BenchmarkReconcile' -benchmem -count=1 -run='^$' ./pkg/events/`
  expect: contains "ns/op"
</verify>

---

### Task 15: F14 — Benchmark Hub.Broadcast + snapshot (Intermute ws)

**Bead:** Demarch-0pvp.18
**Files:**
- Modify: `core/intermute/internal/ws/gateway.go`
- Create: `core/intermute/internal/ws/gateway_bench_test.go`

**Step 1: Read gateway.go, write benchmark**
Mock WebSocket connections (no actual network). Benchmark with 10, 100, 1000 registered connections.

**Step 2: Pool snapshot slices with sync.Pool**
```go
var snapshotPool = sync.Pool{
	New: func() any { return make([]connEntry, 0, 64) },
}
```
Get from pool, use, return after broadcast completes.

**Step 3: Verify >30% improvement at 100+, run tests, commit**

<verify>
- run: `cd core/intermute && go test ./internal/ws/ -v`
  expect: exit 0
- run: `cd core/intermute && go test -bench='BenchmarkBroadcast' -benchmem -count=1 -run='^$' ./internal/ws/`
  expect: contains "ns/op"
</verify>

---

## Wave 4: Low Priority

### Task 16: F15 — Optimize PatternsOverlap (Intermute glob)

**Bead:** Demarch-0pvp.7
**Files:**
- Modify: `core/intermute/internal/glob/overlap.go`
- Test: `core/intermute/internal/glob/overlap_bench_test.go` (exists)

**Step 1: Record baseline, then optimize**
Pre-normalize patterns (filepath.ToSlash + split) at registration time. Store normalized form alongside raw pattern. PatternsOverlap uses pre-normalized data.

**Step 2: Verify <1.5us/<5 allocs, run tests, commit**

<verify>
- run: `cd core/intermute && go test ./internal/glob/ -v`
  expect: exit 0
</verify>

---

### Task 17: F16 — Benchmark + Cache convertToolDefs (Skaffen agentloop)

**Bead:** Demarch-0pvp.17
**Files:**
- Modify: `os/Skaffen/internal/agentloop/loop.go`
- Add to: `os/Skaffen/internal/agentloop/loop_bench_test.go`

**Step 1: Write benchmark for 50, 100, 200 tool definitions**

**Step 2: Cache tool defs in loop struct**
Add `cachedToolDefs []ToolDef` field. Populate on first call, reuse on subsequent turns. Invalidate only if tool registry signals change (version counter or length check).

**Step 3: Verify cached path <100ns, run tests, commit**

<verify>
- run: `cd os/Skaffen && go test ./internal/agentloop/ -v`
  expect: exit 0
</verify>

---

### Task 18: F17 — Benchmark AtomicWriteFile (Autarch file)

**Bead:** Demarch-0pvp.20
**Files:**
- Create: `apps/Autarch/internal/file/atomic_bench_test.go`

**Step 1: Write benchmark for 1K, 10K, 100K, 1M file sizes**

**Step 2: Profile to identify dominant cost**
If directory fsync dominates (>50% of time), consider batching writes or making dir sync optional for non-critical paths.

**Step 3: Record baselines, optimize only if >10us overhead beyond raw write, commit**

<verify>
- run: `cd apps/Autarch && go test ./internal/file/ -v`
  expect: exit 0
</verify>
