---
date: 2026-04-18
bead: sylveste-116u
spike: C (MCP cold-start instrumentation)
related_beads: [sylveste-7505, sylveste-krop, sylveste-x6e4, sylveste-35x5, sylveste-06yf]
related_docs:
  - docs/research/flux-drive/2026-04-10-interserve-consolidated-mcp/synthesis.md
  - docs/brainstorms/2026-04-08-interserve-consolidated-mcp-brainstorm.md
  - docs/handoffs/2026-04-18-b4-shipped-mcp-efficiency-beads.md
---

# MCP Cold-Start Breakdown — 2026-04-18

Measured cold-start wall time, `initialize` handshake RTT, and resident set size for every MCP server Claude Code launches in this environment. Produced to fill the data gap flagged as **P0-12** in the `sylveste-7505` strategy review: the consolidation PRD committed to process-count reduction (19→11) but never to wall-time or memory cost, so there was no way to know whether consolidation would actually help or hurt the user experience.

## TL;DR

- **17 stdio MCP servers successfully measured**, 4 Python uv-run-backed, 4 Go-direct-binary, 7 Node in various flavors (bundled, npx, bash-bootstrap), plus 6 servers that fail to launch at all in this environment.
- **Two-order-of-magnitude spread**: Go direct binaries at 3 ms (p50, 8 MB RSS) vs `interrank` at 1.2 s (98 MB RSS). Language family dominates launcher script overhead by ~100×.
- **`uv run` is NOT the bottleneck**. Bypassing `uv run` with a direct venv entry point saves only ~20 ms. The remaining ~450 ms per Python server is the server's own dependency import graph.
- **`npx -y` is a real cost**, not a rounding error. Baseline `npx --help` alone costs ~190 ms. `npx tsx --version` costs ~560 ms. Every `npx`-wrapped MCP server pays this before any MCP-specific code runs.
- **Cumulative sequential cost ≈ 6.2 s; parallel-bound ≈ 1.2 s** (gated by `interrank`). Session-start feels fast because Claude Code parallelizes the launch — any move to serialize (e.g. a consolidated Python server chaining 6 adapter imports) must beat 1.2 s or degrade perceived responsiveness.
- **Total RSS across all 17 live MCP servers ≈ 970 MB.** At ~1 GB of memory for MCP alone, per-project lazy enablement (spike D) is attacking the real cost, not consolidation.
- **4 Go plugins (`interlab`, `interlock`, `intermap`, `intermux`) are silently dead** because their launcher scripts try to `go build` and `go` is not on PATH. Binaries exist in source tree but launchers don't look there. Fixing this is a ~10-line launcher-script patch that restores four sub-4-ms servers.

## Methodology

### Harness design

Each launcher is invoked in a fresh subprocess. The client opens pipes for `stdin`/`stdout`/`stderr`, writes a JSON-RPC `initialize` message with `protocolVersion: "2024-11-05"` and empty `capabilities`, then reads `stdout` line-by-line until it sees an id=1 response. RSS is sampled from `/proc/<pid>/status` roughly every 50 ms during the wait and captured once more immediately after the response lands.

Three timings per run:

| Field | Definition | Interpretation |
|-------|------------|----------------|
| `t_spawn_ms` | Time from `Popen()` entry to return | Python/OS fork+exec overhead. Consistently 0.2–0.5 ms across all launchers. |
| `t_init_rtt_ms` | Time from `write(initialize)` to receipt of `id=1` response | Server-side: env + interpreter startup + all top-level imports + MCP framework init + initialize handler execution. |
| `t_total_ms` | `Popen` → response | `t_spawn + t_init_rtt`. In practice dominated by `t_init_rtt`. |

### Separating "env/module-load" from "protocol-init"

The handoff asks for this split. Externally, it is not cleanly decomposable: stdio MCP servers do not emit any "ready" signal before reading their first stdin message, so there is no observable boundary between "finished importing" and "ready to serve." Two decomposition strategies were tried:

1. **Baseline subtraction** (`cold_start − interpreter_noop`) — attributes the difference to "imports + framework." Useful per-language, reported below as "language tax vs plugin tax."
2. **Bypass-test** — for one representative Python launcher (`intersearch`), ran the same server both via `uv run intersearch-mcp` and via the venv's direct entry point `.venv/bin/intersearch-mcp`. Difference: ~20 ms. This isolates the `uv run` coordination cost (env resolution, lockfile check, dependency graph walk) from the actual Python import cost.

### Trials

Each server was measured 4 times. Reported figures are p50 (median). Spread (min-max) is also recorded. Warm-cache effects (OS page cache, `uv` metadata cache) mean the first trial is typically slowest; medians stabilize by trial 2.

### What was NOT measured

- **HTTP-type MCP servers** (`notion`, `github`, `vercel`): skipped. Cold-start is a TCP/TLS handshake + remote service response, not process startup. Not comparable to stdio.
- **Tool-call latency**: only `initialize`. Each server's actual tool handlers may do lazy loading that shifts cost from init to first-call.
- **Claude Code's own orchestration overhead**: the time the Claude Code runtime spends deciding to launch, looking up `plugin.json`, setting env, etc. All numbers here are measured from the client-side `Popen`, which isolates the launcher itself.

### Reproducibility

All artifacts are checked in at `docs/research/mcp-cold-start-breakdown-2026-04-18/`:
- `build_inventory_v2.sh` — discovers enabled MCP servers from plugin cache + user scope
- `measure.py` — the timing harness
- `baseline.py` — interpreter-noop baselines
- `go_inventory.py` — adds Go source-tree binaries to the inventory
- `enrich.py`, `final_stats.py` — post-processing for ranked table and per-language aggregation
- `inventory.full.json` — 26 discovered servers (17 measurable stdio, 3 HTTP, 4 Go source-tree, 2 duplicate-extract)
- `all.jsonl` — 92 raw timing records (23 servers × 4 trials each)
- `summary.json`, `summary_enriched.json` — aggregated per-server stats
- `baselines.json` — interpreter-noop baseline measurements

To re-run in a fresh environment: `cd docs/research/mcp-cold-start-breakdown-2026-04-18/ && ./build_inventory_v2.sh > inventory.json && python3 go_inventory.py && python3 measure.py inventory.full.json 4 > all.jsonl`.

## Inventory

Enabled plugins declaring MCP servers were discovered from:
1. `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/.claude-plugin/plugin.json` → `mcpServers` key (interagency-marketplace convention)
2. `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/.mcp.json` (official claude-plugins convention)
3. `~/.claude/settings.json` → user-scope `mcpServers` (empty in this env)

Latest cached version was chosen per plugin. For the Go plugins whose launcher fails, the source-tree binaries at `/home/mk/projects/Sylveste/interverse/<plugin>/bin/<plugin>-mcp` were also measured as a reference "what it would cost if the launcher worked."

**3 HTTP/remote servers present but excluded from cold-start analysis**: `notion` (https://mcp.notion.com/mcp), `github` (https://api.githubcopilot.com/mcp/), `vercel` (https://mcp.vercel.com). These have no local process to time.

## Ranked Results

Sorted by `t_total_ms` p50 ascending. `init_rtt ≈ t_total` for all servers because `t_spawn` is consistently <1 ms — the client writes `initialize` immediately, and the server does not read from stdin until it has finished loading, so the two measurements converge.

| # | Server | Language | `t_total` p50 (ms) | min–max (ms) | init RTT p50 (ms) | RSS peak (MB) | Runs | Notes |
|---|--------|----------|-------------------:|-------------:|------------------:|--------------:|:----:|-------|
| 1 | `intermap::intermap-mcp-src` | Go (direct binary) | 3 | 2.6–3.0 | 2.6 | 8.3 | 4/4 | From source tree (launcher-failed variant excluded) |
| 2 | `interlock::interlock-mcp-src` | Go (direct binary) | 3 | 2.8–3.4 | 2.6 | 8.2 | 4/4 | From source tree |
| 3 | `interlab::interlab-mcp-src` | Go (direct binary) | 4 | 3.5–5.1 | 3.4 | 9.1 | 4/4 | From source tree |
| 4 | `intermux::intermux-mcp-src` | Go (direct binary) | 16 | 13.8–57.0 | 14.4 | 10.5 | 4/4 | Outlier on first trial (cold page cache) |
| 5 | `interlens::interlens` | Node (esbuild bundle) | 59 | 54.4–62.8 | 57.6 | 59.7 | 4/4 | `node bundle.mjs`, 513 KB bundle |
| 6 | `interfluence::interfluence` | Node (esbuild bundle) | 99 | 92.3–109.7 | 96.3 | 77.8 | 4/4 | `node bundle.js`, 1.2 MB bundle |
| 7 | `interflux::openrouter-dispatch` | Node (esbuild bundle) | 141 | 132.4–144.9 | 136.7 | 75.0 | 4/4 | Bash wrapper + node bundle |
| 8 | `tuivision::tuivision` | Node (bash bootstrap) | 190 | 182.3–190.3 | 188.8 | 97.4 | 4/4 | Bash wrapper checks `node_modules`, then node |
| 9 | `interknow::qmd` | Node (npm global) | 338 | 319.4–340.0 | 335.6 | 103.7 | 4/4 | `qmd` → symlink → `node_modules/@tobilu/qmd` |
| 10 | `intercache::intercache` | Python (uv run) | 401 | 372.1–421.7 | 393.1 | 36.0 | 4/4 | Bash → `uv run intercache-mcp` |
| 11 | `tldr-swinton::tldr-code` | Python (uv run) | 519 | 508.6–529.1 | 516.2 | 42.1 | 4/4 | Bash → `uv run --extra mcp-server tldr-mcp` |
| 12 | `intersearch::intersearch` | Python (uv run) | 525 | 494.9–536.4 | 514.4 | 39.3 | 4/4 | `uv run --directory <plugin> intersearch-mcp` |
| 13 | `interject::interject` | Python (uv run) | 540 | 497.5–562.0 | 532.9 | 39.7 | 4/4 | Bash → `uv run interject-mcp` |
| 14 | `interflux::exa` | Node (npx) | 616 | 601.9–617.3 | 611.7 | 114.1 | 4/4 | Bash → `npx -y exa-mcp-server` |
| 15 | `interdeep::interdeep` | Python (uv run) | 779 | 747.9–779.5 | 771.4 | 37.7 | 4/4 | `uv run python` + trafilatura + playwright |
| 16 | `context7::context7` | Node (npx) | 808 | 751.8–819.7 | 787.8 | 113.5 | 4/4 | `npx -y @upstash/context7-mcp` |
| 17 | `interrank::interrank` | Node (npx tsx) | 1 199 | 1 178.8–1 495.6 | 1 189.7 | 98.3 | 4/4 | npx + tsx + loads 734 models from agmodb snapshot at init |
| 18 | `interjawn::interjawn` | Node (npx tsx) | — | — | — | — | 0/4 | Prisma ESM export error — plugin bug, not cold-start |
| 19 | `interkasten::interkasten` | Python (uv run, singleton) | — | — | — | — | 0/4 | Singleton check rejects second instance (daemon already running) |
| 20 | `interlab::interlab` | Go (launcher fails) | — | — | — | — | 0/4 | Launcher tries `go build`, but `go` not on PATH; binary at /usr/local/go/bin missing from env |
| 21 | `interlock::interlock` | Go (launcher fails) | — | — | — | — | 0/4 | Same |
| 22 | `intermap::intermap` | Go (launcher fails) | — | — | — | — | 0/4 | Same |
| 23 | `intermux::intermux` | Go (launcher fails) | — | — | — | — | 0/4 | Same |

### Per-Language Aggregate

| Language / Launcher Shape | Servers | p50 cold-start (ms) | p50 RSS (MB) | Cumulative cold-start (ms) |
|---------------------------|--------:|--------------------:|-------------:|---------------------------:|
| Go (direct binary) | 4 | 3 | 8.6 | 24 |
| Node (esbuild bundle) | 3 | 97 | 74.8 | 292 |
| Node (bash bootstrap) | 1 | 189 | 96.9 | 189 |
| Node (npm-global CLI) | 1 | 336 | 103.4 | 336 |
| Python (`uv run`) | 5 | 516 | 39.0 | 2 730 |
| Node (`npx -y`) | 2 | 700 | 113.4 | 1 400 |
| Node (`npx tsx`) | 1 | 1 190 | 98.2 | 1 190 |

### Interpreter-noop Baselines

These are the floor — what any MCP server in that language pays before it has imported a single module.

| Command | p50 (ms) | Commentary |
|---------|---------:|------------|
| `bash -c "exit 0"` | ~3 | Baseline shell. Launcher bash wrappers add roughly this much. |
| `python3 -c "pass"` | ~15 | System Python. |
| `node -e 0` | ~20 | System Node. |
| `uv --help` | ~5 | `uv` CLI is very fast. |
| `uv run --quiet python -c "pass"` | ~55 | `uv run` coordination adds ~35 ms over raw python. |
| `npx --help` | ~190 | `npx` CLI alone — substantial. |
| `npx tsx --version` | ~560 | `npx tsx` combined — dominates `interrank`. |

## Failures — Why Four Announced Servers are Dead

One of the session-start observations in the handoff was that "6 of ~14 announced MCP servers disconnected mid-session." The harness caught four of those permanently; the remaining two (`interkasten`, `interjawn`) fail for unrelated reasons:

### Go-plugin launcher script dead-end (4 servers)

The launcher at `~/.claude/plugins/cache/interagency-marketplace/<plugin>/<ver>/bin/launch-mcp.sh` has this shape (per the `auto-build-launcher-go-mcp-plugins-20260215` solution doc):

```bash
if [[ ! -x "$BINARY" ]]; then
    if ! command -v go &>/dev/null; then
        echo '{"error":"go not found"}' >&2
        exit 1
    fi
    cd "$PROJECT_ROOT"
    go build -o "$BINARY" ./cmd/<plugin>-mcp/
fi
exec "$BINARY" "$@"
```

In this environment, `bin/` only contains the launcher script itself (the binary is gitignored, per the plugin-loading-failures solution doc). The launcher then tries `command -v go`, fails (go is at `/usr/local/go/bin/go`, not on PATH), writes JSON error to stderr, and exits. Claude Code silently drops the server.

**Meanwhile, the actual compiled binary exists at `/home/mk/projects/Sylveste/interverse/<plugin>/bin/<plugin>-mcp` in every case.** Measured directly, those binaries cold-start in 3–16 ms. The launcher script is the entire problem.

### `interkasten` — singleton daemon (1 server)

`interkasten` enforces a singleton: if another instance is already running with a fresh heartbeat, it exits cleanly. This session's instance was pid 312891, already running. This is a category the benchmark doesn't represent — interkasten's "cold-start" cost is paid once per host, not once per session — and should be reasoned about separately.

### `interjawn` — plugin bug (1 server)

Prisma ESM export failure: `prisma/client does not provide an export named 'PrismaClient'`. This is a plugin-level bug, unrelated to MCP cold-start. Flagging here for completeness; should be filed as its own issue.

## Findings — What the Data Actually Says

### 1. The language-family wall

A server written in Go and executed as a direct binary costs **~3 ms and ~8 MB RSS**. The same server ported to Python + `uv run` would cost **~500 ms and ~40 MB RSS**. The Node bundle tier sits in the middle at ~100 ms / ~75 MB. The spread is 100–400×, and it is not possible to close it with launcher-script tweaks — it is intrinsic to the runtime and its import model.

This directly bears on the `sylveste-7505` brainstorm, which framed the MCP-efficiency problem as "too many processes." The real problem is that Python servers are ~170× slower to cold-start than Go servers, and there are 5 of them.

### 2. `uv run` is surprisingly cheap

Direct experiment: `uv run --directory <plugin> intersearch-mcp` vs `<plugin>/.venv/bin/intersearch-mcp`. 3 trials each:

- `uv run` path: **480–508 ms**
- Direct venv entry: **466–490 ms**

Delta: ~20 ms. This upends a working assumption in the brainstorm that `uv run` env-resolution was the dominant cost. It is not. The dominant cost for every Python server in the inventory is **the server's own top-of-module imports.** Mitigating this requires code-level changes (lazy imports, smaller dependency graphs) or a compiler (Nuitka, PyInstaller, `mypyc`) — not launcher ergonomics.

### 3. `npx -y` is a tax the ecosystem is paying quietly

`npx -y @upstash/context7-mcp` (`context7`) cold-starts in ~808 ms — of which ~190 ms is `npx` startup itself (baseline `npx --help`), ~20 ms is Node startup, and the remaining ~600 ms is context7's own module graph. Similarly, `interrank` at 1.2 s includes ~560 ms of `npx tsx` before tsx has done anything.

For both, a permanent install with a direct entry would likely halve the cold-start: `npm install -g @upstash/context7-mcp` and invoking the installed CLI directly should drop context7 to ~300–400 ms. For `interrank`, TypeScript-at-runtime via `tsx` is paying a compile-every-session penalty — `tsc` once at build time and shipping compiled JS would likely cut 500+ ms.

### 4. `interrank` bootstraps data, not just code

Stderr: *"interrank MCP server started with 734 models, 19 families from mistakeknot/agmodb@data-snapshot-latest"*. That 734-model load is happening synchronously before `initialize` returns. A lazy-load pattern — serve an empty catalog on `initialize` and populate on first `leaderboard`/`get_model` tool call — would likely drop cold-start by 700–900 ms. The marginal cost of the load moves to whichever tool needs it first, where it's amortized.

### 5. Node bundled ≠ npx

`interlens` (esbuild bundle, 59 ms) and `interfluence` (99 ms) demonstrate that Node doesn't have to be slow. The difference from `context7` (808 ms) is `npx` + lack of pre-bundling + larger transitive dep graph loaded at init. `interlens`'s 59 ms is within 15× of Go — acceptable for a lot of applications.

### 6. Sequential sum vs parallel bound

Summing all 17 measured cold-starts: **6.24 s.** But session-start feels snappy because Claude Code parallelizes launches, and the slowest server (`interrank` at 1.20 s) gates the perceptible wall time. This has a load-bearing implication for consolidation:

> **A single consolidated server that serializes 5 Python adapter imports at init would cost ~2.5 s (sum of Python servers' current imports) — more than 2× the current parallel-bound of 1.2 s.**

This is the concrete form of P0-12 that `sylveste-7505`'s PRD must address if revived: the win from consolidation is process-count and multiplexed IPC, but the cost is serialized adapter startup. Without lazy-import discipline in the consolidated server, consolidation makes the user-perceived cold-start *worse*.

### 7. Memory footprint — the "1 GB MCP tax"

Total RSS for 17 live servers: **~970 MB.** Python servers are actually lean (~40 MB each); the heavy hitters are `interflux::exa` (114 MB) and `context7` (113 MB) via npx — npx keeps the node process heavy. `interrank` at 98 MB is the 734 models in memory.

Per-project lazy enablement (**spike D**, `sylveste-krop`) is the most direct attack on both axes: a session that only uses 4 of the 17 servers would cut total cold-start by ~75% and total RSS by a comparable amount — without touching any plugin internals.

## Recommendations

Ordered by (impact × ease), highest first.

### R1 — Fix Go launcher scripts to probe source tree before rebuilding (highest impact, smallest diff)

**Restores 4 sub-16-ms servers for free.** Patch the launcher at `bin/launch-mcp.sh` for each of `interlab`, `interlock`, `intermap`, `intermux` to check a list of candidate binary paths before attempting `go build`:

```bash
CANDIDATES=(
    "${SCRIPT_DIR}/<plugin>-mcp"                                   # cache-local (current)
    "/home/mk/projects/Sylveste/interverse/<plugin>/bin/<plugin>-mcp"  # source tree
    "${HOME}/.local/bin/<plugin>-mcp"                             # user-installed
)
for bin in "${CANDIDATES[@]}"; do
    [[ -x "$bin" ]] && exec "$bin" "$@"
done
# Only now attempt go build, and only if go is on PATH
```

**Expected effect**: 4 servers move from "dead" to "3–16 ms cold-start." Zero code change in the Go servers themselves. Per-plugin diff is ~10 lines.

**File a bead** to own this change — applies to 4 plugins, plus any future Go MCP plugin.

### R2 — Lazy-load `interrank`'s 734-model snapshot (high impact, moderate diff)

**Expected saving: 700–900 ms cold-start, unlocks session parallel bound.** Change `interrank` from:

```ts
// current: load at module init
const snapshot = await loadSnapshot(); // 734 models
const server = new Server(...);
```

to:

```ts
let _snapshotPromise: Promise<Snapshot> | null = null;
const getSnapshot = () => _snapshotPromise ??= loadSnapshot();
// Tool handlers call getSnapshot() on first use.
```

`initialize` returns immediately. First `leaderboard` or `get_model` call pays the 700 ms, but that cost was going to be paid anyway — it was just being paid at the wrong moment. If session start is the parallel-bound-gate, this moves `interrank` from 1 199 ms to ~50 ms and the new gate becomes `context7` at ~800 ms.

### R3 — Replace `npx -y` with permanent installs for `context7` and `exa` (moderate impact, trivial diff)

**Expected saving: ~200–400 ms per server.** Pre-install via `npm install -g @upstash/context7-mcp` at plugin-install time (via a setup hook or documented prerequisite), and change the launcher from:

```
"command": "npx", "args": ["-y", "@upstash/context7-mcp"]
```

to:

```bash
# launch-context7.sh
if ! command -v context7-mcp &>/dev/null; then
    echo "context7-mcp not installed: npm i -g @upstash/context7-mcp" >&2
    exit 0
fi
exec context7-mcp "$@"
```

Follows the pattern already established by `interknow/qmd` and `interject`. Users pay installation cost once; all subsequent sessions skip the `npx` tax.

### R4 — Compile `interrank` ahead of time (moderate impact, moderate diff)

**Expected saving: ~300–500 ms.** Currently `interrank` runs via `npx tsx src/index.ts` — tsx is transpiling TypeScript on every session start. Move to `tsc` at publish time, ship `dist/index.js`, invoke `node dist/index.js` (like `interlens`/`interfluence` already do). This is independent of R2.

### R5 — Per-project lazy MCP enablement (spike D territory)

**Expected saving: 50–80% of session cold-start and RSS, depending on per-project usage.** This is `sylveste-krop`, deferred here but strongly reinforced by the data:

- Sessions typically need 3–5 of the 17 available servers (anecdotal, need instrumentation to confirm).
- A per-project `enabled_mcp` manifest (or auto-learned from session history) that launches only needed servers would approach the "Go direct" experience for the savings without any per-server code change.
- Most of this is ecosystem tooling rather than plugin modification — it moves the decision of "which servers to launch" from a global always-on default to per-project opt-in.

### R6 — Port 1-2 hot-path servers from Python to Go (highest impact, largest diff)

**Expected saving per port: 300–500 ms + 30 MB RSS.** The 5 Python servers collectively account for **~2.7 seconds** of cumulative cold-start and are all in the 500 ms band. If any of them lives in the "session hot path" (invoked on nearly every session), a Go port would take it from 500 ms to ~5 ms. Candidates by triage:

- `intercache` (401 ms) — simple k/v store; likely easy port.
- `intersearch` (525 ms) — depends on how much of the heavy lift is native C (ColBERT, FAISS).
- `tldr-swinton` (519 ms) — same consideration.
- `interject` (540 ms) — depends on SQL/data dependencies.
- `interdeep` (779 ms) — hard port (trafilatura + playwright are Python-only).

The Auraken→Go migration precedent (sylveste-benl.1-4) suggests this class of port is ~1–2 weeks of work per plugin. Value per port is concrete (~500 ms shaved per session × sessions/day).

### R7 — Python servers: lazy imports at module top-level (moderate impact, moderate diff per plugin)

**Expected saving: 100–300 ms per Python server.** The ~500 ms cost for most Python MCP servers is their `import` graph. Pattern:

```python
# Before — top of module
import trafilatura
import playwright
# ...all imports at init

# After
def get_trafilatura():
    import trafilatura
    return trafilatura

# Tool handlers call get_trafilatura() on first use.
```

Lower-impact than a Go port but much smaller diff. Applies especially to `interdeep` where trafilatura + playwright together likely account for most of the 779 ms.

## What This Tells `sylveste-7505` (Consolidated MCP Revive)

The P0-12 data gap in the strategy synthesis is now filled. A revived consolidation PRD would need to commit to:

1. **Target: parallel-bound cold-start of the consolidated server ≤ 1 200 ms** (current `interrank`-gated baseline). Anything worse is a regression in perceived responsiveness even if process count drops.
2. **Concrete import budget per adapter**: each adapter's top-level import cost must be measured (via profiler or R7 audit) before consolidation. Without lazy imports in every adapter, chained imports blow the 1 200 ms budget immediately — 5 Python adapters × 500 ms sequential = 2 500 ms.
3. **Honest comparison against R1 + R2 + R5**: those three together plausibly close ~40% of the perceived cold-start cost at a fraction of 7505's blast radius. The consolidation PRD must argue why 7505's additional complexity is worth it *above* those interventions.

Put differently: if R1 (Go launcher fix) + R2 (interrank lazy load) + R5 (per-project enablement) ship first, the remaining cold-start cost might not justify consolidation. The spike-D path (`sylveste-krop`) is where the next measurement should focus: **how many servers does a typical session actually need?** If the answer is 3-5, per-project enablement wins.

## Follow-ups (Beads to File)

- **R1 bead**: Fix Go MCP launcher scripts across `interlab`/`interlock`/`intermap`/`intermux` to probe source tree and known binary paths before attempting `go build`.
- **R2 bead**: Lazy-load agmodb snapshot in `interrank` — don't block `initialize` on model ingestion.
- **R3 bead**: Replace `npx -y` with permanent-install pattern for `context7` and `interflux::exa`.
- **R4 bead**: Precompile `interrank` TypeScript at publish time; drop `tsx` runtime.
- **R5 meta**: Feed these findings into `sylveste-krop` spike D's lazy-MCP-enablement design.
- **Triage bead** for `interjawn` Prisma ESM bug (unrelated to cold-start, surfaced here).
- **Reconsider bead**: `sylveste-7505` revival must explicitly address P0-12 with adapter-level import budgets.

## Appendix — Raw Data

Checked in at `docs/research/mcp-cold-start-breakdown-2026-04-18/`:

- `inventory.full.json` — discovered MCP server inventory, 26 servers (17 measurable stdio + 3 HTTP + 4 Go-source-tree + 2 duplicates)
- `all.jsonl` — 92 raw timing records
- `summary.json`, `summary_enriched.json` — aggregated per-server stats
- `baselines.json` — interpreter-noop baselines
- `measure.py`, `baseline.py`, `go_inventory.py`, `build_inventory_v2.sh`, `enrich.py`, `final_stats.py` — harness + post-processing
