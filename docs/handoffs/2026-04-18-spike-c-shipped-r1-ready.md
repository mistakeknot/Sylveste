---
date: 2026-04-18
session: eaf714b9
topic: spike C shipped, R1 Go-launcher-fix ready
beads: [sylveste-116u, sylveste-9mix, sylveste-mb72, sylveste-qhnb, sylveste-jum2, sylveste-ttwz, sylveste-pexq, sylveste-jp1l, sylveste-ung7]
---

## Session Handoff — 2026-04-18 spike C shipped + R1 Go-launcher-fix ready

### Directive
> Your job is to execute **R1 (`sylveste-9mix`, P1)** — patch the launcher script at `bin/launch-mcp.sh` in four Go MCP plugins (`interlab`, `interlock`, `intermap`, `intermux`) to probe known binary paths before attempting `go build`. Start by reading the current launcher at `/home/mk/projects/Sylveste/interverse/interlock/bin/launch-mcp.sh` (it is the template the others copy from). Verify with `cd /home/mk/projects/Sylveste/docs/research/mcp-cold-start-breakdown-2026-04-18 && python3 measure.py inventory.full.json 3` — after the patch, all 4 `<plugin>::<plugin>` entries (non-`-mcp-src` variants) should succeed at sub-20ms cold-start instead of dying with "go not found".
- Beads: `sylveste-9mix` open P1, unclaimed — claim with `bd update sylveste-9mix --claim` then set `claimed_by`/`claimed_at` via `bd set-state`.
- Scope target: ~10 line diff per plugin × 4 plugins. Candidate paths to probe in order: cache-local binary (`${SCRIPT_DIR}/<plugin>-mcp`), source-tree binary (`/home/mk/projects/Sylveste/interverse/<plugin>/bin/<plugin>-mcp`), user-local (`${HOME}/.local/bin/<plugin>-mcp`). Only fall through to `go build` if none exist.
- **Publish path** (critical): each interverse plugin has its own git repo. After editing `/home/mk/projects/Sylveste/interverse/<plugin>/bin/launch-mcp.sh`, `cd` into that plugin dir and commit/publish there, not from the monorepo root. Then `ic publish --patch` per plugin to update marketplace cache. See memory: `feedback_interverse_git.md` and `feedback_publish_after_push.md`.
- Fallback if R1 blocked: pick up **R2 (`sylveste-mb72`, P1)** — lazy-load interrank agmodb snapshot. Requires touching interrank TS source which this session did not explore.

### Dead Ends
- **Initial harness parser accumulated stdout lines across `readline()` calls** — broke interrank (emits npm banners on stdout before JSON-RPC response). Fixed by parsing each line as a standalone JSON attempt, appending non-JSON lines to a discard buffer. Do not reintroduce line accumulation. See `measure.py:140-155`.
- **Attempted to isolate `uv run` overhead as the Python cold-start bottleneck** — it isn't. Direct venv entrypoint (`.venv/bin/intersearch-mcp`) vs `uv run --directory` differs by only ~20ms. The ~450ms Python overhead is the server's own top-level import graph, not uv coordination. Revising R6/R7 scope accordingly: lazy imports or native compile, not launcher optimization.

### Context
- **`docs/research/*/` is gitignored** — research subdirs need `git add -f`. Spike C harness was force-added to `docs/research/mcp-cold-start-breakdown-2026-04-18/`. Precedent: `docs/research/darwinian_evolver/` is also tracked under the same rule.
- **`go` binary exists at `/usr/local/go/bin/go`** but is not on PATH in the MCP server process environment. `command -v go` fails. Four Go plugins die silently because of this. R1 sidesteps by preferring pre-built binaries (which exist at `/home/mk/projects/Sylveste/interverse/<plugin>/bin/<plugin>-mcp`, measured 3-16ms / 8-10MB RSS) over attempting build.
- **Measured cold-start baselines** (p50, checked into `docs/research/mcp-cold-start-breakdown-2026-04-18/all.jsonl`): Go-direct 3ms, Node-bundle 97ms, Python-uv-run 516ms, npx-bare 700ms, npx-tsx 1190ms. Parallel-bound = 1.2s (gated by interrank). Sum-sequential = 6.2s. Total RSS across 17 live servers = 970MB.
- **`sylveste-7505` revival is now formally gated** on shipping R1+R2+`sylveste-krop` first (filed as `sylveste-ung7`). P0-12 data gap from the strategy synthesis is filled; any 7505 revive must commit to parallel-bound ≤1200ms with adapter-level import budgets or it's a cold-start regression.
- **6 MCP servers disconnected mid-session again** (context7, intercache, interdeep, interrank, intersearch, tldr-swinton) — consistent with prior session. The harness captured their cold-start before the disconnect. This is live evidence the ~40% in-session failure rate is reproducing.
- **MEMORY.md was just tidied** (181→112 lines, under 120 budget). Two sections extracted to topic files: `beads-workflow.md`, `universal-gotchas.md`. Plugin count corrected 58→63. Don't re-extract the same sections.
- **Interkasten is a singleton** — fails second-instance launches by design. Not a cold-start problem, not an R-bead.
- **Interjawn is dead from a Prisma ESM bug** (`sylveste-jp1l`, filed). Unrelated to MCP cold-start but surfaced by the harness.
- **Key paths**: spike C doc `/home/mk/projects/Sylveste/docs/research/mcp-cold-start-breakdown-2026-04-18.md`; harness + raw data `/home/mk/projects/Sylveste/docs/research/mcp-cold-start-breakdown-2026-04-18/`; R1 target launchers `/home/mk/projects/Sylveste/interverse/{interlab,interlock,intermap,intermux}/bin/launch-mcp.sh`; 7505 synthesis `/home/mk/projects/Sylveste/docs/research/flux-drive/2026-04-10-interserve-consolidated-mcp/synthesis.md`.
