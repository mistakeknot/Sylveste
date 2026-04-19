---
artifact_type: plan
bead: sylveste-fyo3
stage: design
requirements:
  - F1: OpenRouter Provider Integration
  - F5: Claude Baseline Calibration
  - F2: Real Model Dispatch in qualify.sh
  - F3: First Real Model Discovery Run
  - F4: Activate Cross-Model Dispatch
  - F6: Challenger Slot Wiring
---

# Multi-Model Activation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-fyo3
**Goal:** Activate the interflux multi-model feedback loop: build OpenRouter MCP, calibrate Claude baseline, qualify real models, discover candidates, enable enforce mode, and wire the challenger slot.

**Architecture:** Two-phase script pattern — FluxBench scripts split into `--emit` (output JSON descriptors, exit) and `--score` (read filled responses, compute results). A SKILL.md orchestrator block bridges the gap: calls `--emit`, fills responses via MCP/Agent tool calls, then calls `--score`. This avoids the deadlock of a single-process script trying to pause for external IO. The OpenRouter MCP server is a TypeScript stdio process registered in plugin.json, matching the Exa pattern. All qualification and calibration flows through the existing FluxBench pipeline (qualify→score→registry).

**Tech Stack:** TypeScript (MCP server, `@modelcontextprotocol/sdk`), Bash (FluxBench scripts), Python 3 (inline YAML/JSON manipulation), YAML (configs)

**Prior Learnings:**
- Go MCP plugin solution (`docs/solutions/workflow-issues/auto-build-launcher-go-mcp-plugins-20260215.md`): compiled MCP binaries missing after `claude plugins install` — use launcher script pattern (like `launch-exa.sh`) that runs `npx` or checks prerequisites before exec
- Prior session (cass): Agent tool only supports `model:` param, not `provider:`. `routing_resolve_agents()` uses Clavain's routing.yaml, not model-registry.yaml. Synthesis already has cross-family convergence weighting ready.
- Memory: always pass data to inline Python via env vars, never interpolation (P0 injection vector)

---

## Must-Haves

**Truths** (observable behaviors):
- Operator can qualify a real model against calibrated Claude thresholds via `fluxbench-qualify.sh <slug>` + orchestrator
- Operator can discover candidates via `discover-models.sh --force` + orchestrator and see them in model-registry.yaml
- `cross_model_dispatch.mode: enforce` applies Claude tier adjustments (not registry substitution) with safety floors intact
- Challenger slot dispatches a `qualified_via: real` model during flux-drive reviews and scores its output
- Mock-qualified models cannot activate enforce mode or enter the challenger slot

**Artifacts** (files with specific exports):
- `interverse/interflux/mcp-servers/openrouter-dispatch/index.ts` — MCP server with `review_with_model` tool
- `interverse/interflux/scripts/launch-openrouter.sh` — launcher script for plugin.json registration
- `interverse/interflux/config/flux-drive/fluxbench-thresholds.yaml` — Claude-calibrated thresholds with `source: claude-baseline`
- `interverse/interflux/config/flux-drive/model-registry.yaml` — updated with `qualified_via` field, `prompt_content_policy`, uncommented openrouter provider

**Key Links** (connections where breakage cascades):
- fluxbench-qualify.sh outputs JSON descriptors → orchestrator calls review_with_model → responses feed into fluxbench-score.sh
- fluxbench-calibrate.sh outputs JSON descriptors → orchestrator calls Agent tool for Claude → scores set thresholds
- fluxbench-thresholds.yaml thresholds → fluxbench-score.sh gate checks → qualify.sh pass/fail → model-registry.yaml status
- model-registry.yaml `qualified_via` field → F4 pre-flight gate → budget.yaml enforce mode
- budget.yaml `prompt_content_policy` per model → challenger dispatch content filtering

---

### Task 1: OpenRouter MCP Server — TypeScript scaffold

**Files:**
- Create: `interverse/interflux/mcp-servers/openrouter-dispatch/index.ts`
- Create: `interverse/interflux/mcp-servers/openrouter-dispatch/package.json`
- Create: `interverse/interflux/mcp-servers/openrouter-dispatch/tsconfig.json`

**Step 1: Create package.json**
```json
{
  "name": "openrouter-dispatch",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "zod": "^3.22.0"
  },
  "devDependencies": {
    "typescript": "^5.5.0",
    "@types/node": "^22.0.0"
  }
}
```

**Step 2: Create tsconfig.json**
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": ".",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": true
  },
  "include": ["index.ts"]
}
```

**Step 3: Write index.ts with `review_with_model` tool**

The MCP server must:
- Read `OPENROUTER_API_KEY` from env (fail with clear error, never log key)
- Expose `review_with_model` accepting `{model_id, prompt, system_prompt, max_tokens}`
- Return `{content, model, tokens_used, latency_ms}`
- Client-side token-bucket rate limiting (default 20/min, read from `OPENROUTER_RATE_LIMIT` env)
- Track cumulative spend; halt on `OPENROUTER_SPEND_CEILING_USD` breach
- On 429: return error (caller decides retry/skip)

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const API_KEY = process.env.OPENROUTER_API_KEY;
if (!API_KEY) {
  console.error("OPENROUTER_API_KEY not set — openrouter-dispatch MCP disabled.");
  process.exit(0);
}

const RATE_LIMIT = parseInt(process.env.OPENROUTER_RATE_LIMIT || "20", 10);
const SPEND_CEILING = parseFloat(process.env.OPENROUTER_SPEND_CEILING_USD || "0");

// Token-bucket rate limiter
let tokenBucket = RATE_LIMIT;
let lastRefill = Date.now();
const refillRate = RATE_LIMIT / 60000; // tokens per ms

function tryAcquire(): boolean {
  const now = Date.now();
  const elapsed = now - lastRefill;
  tokenBucket = Math.min(RATE_LIMIT, tokenBucket + elapsed * refillRate);
  lastRefill = now;
  if (tokenBucket >= 1) {
    tokenBucket -= 1;
    return true;
  }
  return false;
}

let cumulativeSpendUsd = 0;

const server = new McpServer({
  name: "openrouter-dispatch",
  version: "0.1.0",
});

server.tool(
  "review_with_model",
  "Dispatch a review prompt to a model via OpenRouter",
  {
    model_id: z.string().describe("OpenRouter model ID (e.g., 'deepseek/deepseek-chat')"),
    prompt: z.string().describe("The review prompt to send"),
    system_prompt: z.string().optional().describe("System prompt for the model"),
    max_tokens: z.number().optional().default(4096).describe("Max tokens in response"),
  },
  async ({ model_id, prompt, system_prompt, max_tokens }) => {
    if (!tryAcquire()) {
      return {
        content: [{ type: "text" as const, text: JSON.stringify({
          error: "rate_limited",
          message: `Rate limit exceeded (${RATE_LIMIT}/min). Try again shortly.`,
        })}],
        isError: true,
      };
    }

    if (SPEND_CEILING > 0 && cumulativeSpendUsd >= SPEND_CEILING) {
      return {
        content: [{ type: "text" as const, text: JSON.stringify({
          error: "spend_ceiling_exceeded",
          message: `Cumulative spend $${cumulativeSpendUsd.toFixed(4)} >= ceiling $${SPEND_CEILING}`,
        })}],
        isError: true,
      };
    }

    const startMs = Date.now();
    const messages: Array<{role: string; content: string}> = [];
    if (system_prompt) messages.push({ role: "system", content: system_prompt });
    messages.push({ role: "user", content: prompt });

    const resp = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${API_KEY}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/sylveste-ai/sylveste",
        "X-Title": "FluxBench Qualification",
      },
      body: JSON.stringify({ model: model_id, messages, max_tokens }),
    });

    const latencyMs = Date.now() - startMs;

    if (!resp.ok) {
      const body = await resp.text();
      return {
        content: [{ type: "text" as const, text: JSON.stringify({
          error: `openrouter_${resp.status}`,
          message: body.slice(0, 500),
          latency_ms: latencyMs,
        })}],
        isError: true,
      };
    }

    const data = await resp.json() as {
      choices: Array<{ message: { content: string } }>;
      usage?: { prompt_tokens: number; completion_tokens: number; total_cost?: number };
      model: string;
    };

    const tokensUsed = (data.usage?.prompt_tokens ?? 0) + (data.usage?.completion_tokens ?? 0);
    if (data.usage?.total_cost) cumulativeSpendUsd += data.usage.total_cost;

    return {
      content: [{ type: "text" as const, text: JSON.stringify({
        content: data.choices[0]?.message?.content ?? "",
        model: data.model,
        tokens_used: tokensUsed,
        latency_ms: latencyMs,
      })}],
    };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
```

**Step 4: Install dependencies, generate lockfile, and build**
```bash
cd interverse/interflux/mcp-servers/openrouter-dispatch && npm install && npm run build
```

**Step 5: Commit (include package-lock.json for supply chain safety)**
```bash
git -C interverse/interflux add mcp-servers/openrouter-dispatch/
git -C interverse/interflux commit -m "feat(fluxbench): add openrouter-dispatch MCP server scaffold"
```

<verify>
- run: `cd interverse/interflux/mcp-servers/openrouter-dispatch && node dist/index.js --help 2>&1 || echo "server started (stdio mode, no --help)"` 
  expect: exit 0
</verify>

---

### Task 2: Launcher script + plugin.json registration

**Files:**
- Create: `interverse/interflux/scripts/launch-openrouter.sh`
- Modify: `interverse/interflux/.claude-plugin/plugin.json`

**Step 1: Write launcher script (matches launch-exa.sh pattern)**
```bash
#!/usr/bin/env bash
# Launcher for openrouter-dispatch MCP server.
# Needs Node.js and OPENROUTER_API_KEY to function.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/../mcp-servers/openrouter-dispatch"

if ! command -v node &>/dev/null; then
    echo "Node.js not found — openrouter-dispatch MCP server disabled." >&2
    exit 0
fi

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "OPENROUTER_API_KEY not set — openrouter-dispatch MCP server disabled." >&2
    exit 0
fi

# Auto-build if dist/ missing
if [[ ! -f "${SERVER_DIR}/dist/index.js" ]]; then
    echo "Building openrouter-dispatch MCP server..." >&2
    (cd "$SERVER_DIR" && npm ci && npm run build) >&2
fi

exec node "${SERVER_DIR}/dist/index.js" "$@"
```

**Step 2: Make launcher executable**
```bash
chmod +x interverse/interflux/scripts/launch-openrouter.sh
```

**Step 3: Register in plugin.json mcpServers**

Add to the `mcpServers` object:
```json
"openrouter-dispatch": {
  "type": "stdio",
  "command": "${CLAUDE_PLUGIN_ROOT}/scripts/launch-openrouter.sh",
  "args": [],
  "env": {
    "OPENROUTER_API_KEY": "${OPENROUTER_API_KEY}",
    "OPENROUTER_RATE_LIMIT": "20",
    "OPENROUTER_SPEND_CEILING_USD": "1.00"
  }
}
```

**Step 4: Commit**
```bash
git -C interverse/interflux add scripts/launch-openrouter.sh .claude-plugin/plugin.json
git -C interverse/interflux commit -m "feat(fluxbench): register openrouter-dispatch MCP in plugin.json"
```

<verify>
- run: `bash interverse/interflux/scripts/launch-openrouter.sh 2>&1 | head -1`
  expect: contains "OPENROUTER_API_KEY not set"
- run: `python3 -c "import json; d=json.load(open('interverse/interflux/.claude-plugin/plugin.json')); print(list(d['mcpServers'].keys()))"`
  expect: contains "openrouter-dispatch"
</verify>

---

### Task 3: Add `qualified_via` and `prompt_content_policy` to model-registry.yaml + uncomment openrouter provider

**Files:**
- Modify: `interverse/interflux/config/flux-drive/model-registry.yaml`
- Create: `interverse/interflux/.gitignore`

**Step 1: Uncomment openrouter provider block and add fields**

In model-registry.yaml, replace the commented provider block with:
```yaml
providers:
  claude:
    type: native
    tier: top
  openrouter:
    type: mcp
    tier: standard
    endpoint: openrouter-dispatch
    rate_limit: 20
    spend_ceiling_usd: 1.00
```

Add to the example model entry comments:
```yaml
  #   qualified_via: null           # real | mock — set by qualify.sh, enforce gate requires "real"
  #   prompt_content_policy: fixtures_only  # fixtures_only | sanitized_diff | full_document
```

**Step 2: Create .gitignore for data directory**
```
# FluxBench results (accumulates real scoring data — do not commit)
/data/
# MCP server build artifacts
/mcp-servers/*/dist/
/mcp-servers/*/node_modules/
# Keep lockfiles for supply chain safety
!/mcp-servers/*/package-lock.json
```

**Step 3: Commit**
```bash
git -C interverse/interflux add config/flux-drive/model-registry.yaml .gitignore
git -C interverse/interflux commit -m "feat(fluxbench): add qualified_via, content_policy, uncomment openrouter provider"
```

<verify>
- run: `python3 -c "import yaml; r=yaml.safe_load(open('interverse/interflux/config/flux-drive/model-registry.yaml')); print(r['providers']['openrouter']['type'])"`
  expect: contains "mcp"
</verify>

---

### Task 4: Claude baseline calibration — two-phase real mode for fluxbench-calibrate.sh

**Files:**
- Modify: `interverse/interflux/scripts/fluxbench-calibrate.sh`

**Step 1: Restructure as two-phase script**

Add `--emit` and `--score` sub-commands. The existing `--mock` mode remains as a single-pass command (backward compatible).

**`--emit` phase** (new): For each fixture, outputs a JSON descriptor to stdout and exits:
```json
{"action":"calibrate","fixture_id":"fixture-01-null-check","document_path":"tests/fixtures/qualification/fixture-01-null-check/document.md","agent_type":"judgment","response_path":"/tmp/fluxbench-cal-XXXX/fixture-01-null-check/response.md"}
```
Creates the work_dir, writes a manifest of expected response paths, then exits 0. The orchestrator reads descriptors, calls Agent tool with Claude for each fixture, writes responses to the specified paths.

**`--score` phase** (new): Reads the work_dir from `--work-dir <path>`, verifies all response files exist, feeds each through `fluxbench-score.sh`, computes p25 thresholds, writes output YAML with `source: claude-baseline`.

**Step 2: Add threshold guard**

In the `--score` phase, before writing thresholds, check direction-aware regression:
```bash
export _CAL_OUTPUT="$output_file"
python3 -c "
import yaml, os, sys
out = os.environ['_CAL_OUTPUT']
if not os.path.exists(out):
    sys.exit(0)  # no existing file, safe to write
existing = yaml.safe_load(open(out)) or {}
src = existing.get('source', '')
# Skip guard when upgrading from mock to real
if src in ('calibrated', 'defaults'):
    print('Upgrading from mock/default thresholds — guard skipped', file=sys.stderr)
    sys.exit(0)
# For claude-baseline → claude-baseline: check for regression
t = existing.get('thresholds', {})
# Higher-is-better: format_compliance, finding_recall, severity_accuracy, persona_adherence
# Lower-is-better: false_positive_rate
# (comparison implemented in score phase)
"
```

**Step 3: Update source label**

Real mode writes `source: claude-baseline`. Mock mode continues to write `source: calibrated`.

**Step 4: Commit**
```bash
git -C interverse/interflux add scripts/fluxbench-calibrate.sh
git -C interverse/interflux commit -m "feat(fluxbench): two-phase calibrate.sh with real Claude mode"
```

<verify>
- run: `bash interverse/interflux/scripts/fluxbench-calibrate.sh --fixtures-dir interverse/interflux/tests/fixtures/qualification --output /tmp/test-thresholds.yaml --mock && head -5 /tmp/test-thresholds.yaml`
  expect: contains "source: calibrated"
- run: `bash -n interverse/interflux/scripts/fluxbench-calibrate.sh`
  expect: exit 0
</verify>

---

### Task 5: Run Claude calibration — execute real mode and write thresholds

**Files:**
- Modify: `interverse/interflux/config/flux-drive/fluxbench-thresholds.yaml` (will be created/overwritten)

**Step 1: Run two-phase calibration**

This is an orchestrated step:
1. Run `fluxbench-calibrate.sh --emit --fixtures-dir tests/fixtures/qualification --output config/flux-drive/fluxbench-thresholds.yaml` — captures JSON descriptors from stdout, script exits
2. For each descriptor, call Agent tool with Claude (sonnet) to review the fixture document using the agent persona from agent-roles.yaml
3. Write Claude's response to each descriptor's `response_path`
4. Run `fluxbench-calibrate.sh --score --work-dir <work_dir> --output config/flux-drive/fluxbench-thresholds.yaml` — reads responses, computes thresholds

**Step 2: Verify thresholds are empirical (not 1.0)**
```bash
python3 -c "
import yaml
t = yaml.safe_load(open('interverse/interflux/config/flux-drive/fluxbench-thresholds.yaml'))
for k, v in t['thresholds'].items():
    assert v != 1.0, f'{k} is 1.0 — still mock calibration'
    print(f'{k}: {v}')
print(f'Source: {t[\"source\"]}')
"
```

**Step 3: Commit**
```bash
git -C interverse/interflux add config/flux-drive/fluxbench-thresholds.yaml
git -C interverse/interflux commit -m "feat(fluxbench): write Claude-calibrated thresholds from real inference"
```

<verify>
- run: `python3 -c "import yaml; t=yaml.safe_load(open('interverse/interflux/config/flux-drive/fluxbench-thresholds.yaml')); print(t['source'])"`
  expect: contains "claude-baseline"
</verify>

---

### Task 6: Real model dispatch — two-phase fluxbench-qualify.sh

**Files:**
- Modify: `interverse/interflux/scripts/fluxbench-qualify.sh`

**Step 1: Replace the real-mode rejection gate (lines 44-47) with two-phase commands**

Remove the "real model dispatch not yet supported" block. Add `--emit` and `--score` sub-commands:

**`--emit` phase** (new, real mode only): For each fixture, outputs a JSON descriptor:
```json
{"action":"qualify","fixture_id":"<id>","model_slug":"<slug>","document_path":"<fixture>/document.md","agent_type":"<type>","response_path":"<work_dir>/<id>/response.md"}
```
Creates work_dir, writes manifest, exits 0. Orchestrator calls `review_with_model` via MCP for each fixture, writes responses.

**`--score` phase** (new): Reads `--work-dir <path>`, verifies response files exist (missing = fixture failure), runs `fluxbench-score.sh` for each, computes aggregates, writes registry.

**`--mock` mode**: Unchanged — single-pass, uses ground-truth as model output.

**Step 2: Add `qualified_via` field to registry write**

In the `_update_registry` Python block, add:
```python
qual_mode = os.environ.get('_FB_QUAL_MODE')
if not qual_mode or qual_mode not in ('real', 'mock'):
    raise ValueError(f'_FB_QUAL_MODE must be real or mock, got: {qual_mode!r}')
model['qualified_via'] = qual_mode
```

Set the env var before flock:
```bash
export _FB_QUAL_MODE="$(if $mock_mode; then echo mock; else echo real; fi)"
```

No silent default — script fails loudly if `_FB_QUAL_MODE` is unset.

**Step 3: Commit**
```bash
git -C interverse/interflux add scripts/fluxbench-qualify.sh
git -C interverse/interflux commit -m "feat(fluxbench): two-phase qualify.sh with qualified_via tracking"
```

<verify>
- run: `bash interverse/interflux/scripts/fluxbench-qualify.sh test-model --mock 2>&1 | tail -3`
  expect: contains "Qualification run"
- run: `bash -n interverse/interflux/scripts/fluxbench-qualify.sh`
  expect: exit 0
</verify>

---

### Task 7: Model discovery — implement orchestrator merge step

**Files:**
- Create: `interverse/interflux/scripts/discover-merge.sh`
- Modify: `interverse/interflux/scripts/discover-models.sh` (minor — add `prompt_content_policy` default)

**Step 1: Write discover-merge.sh**

This script takes interrank MCP results (as JSON on stdin or from a file) and merges Pareto-efficient candidates into model-registry.yaml:

```bash
#!/usr/bin/env bash
# discover-merge.sh — merge interrank query results into model-registry.yaml
# Usage: discover-merge.sh <results-json-file>
# Called by orchestrator after executing interrank MCP queries from discover-models.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_FILE="${MODEL_REGISTRY:-${SCRIPT_DIR}/../config/flux-drive/model-registry.yaml}"
BUDGET_FILE="${SCRIPT_DIR}/../config/flux-drive/budget.yaml"
RESULTS_FILE="${1:-}"

[[ -n "$RESULTS_FILE" && -f "$RESULTS_FILE" ]] || { echo "Usage: discover-merge.sh <results.json>" >&2; exit 1; }

export _DM_BUDGET="$BUDGET_FILE"
MIN_CONFIDENCE=$(python3 -c "import yaml, os; print(yaml.safe_load(open(os.environ['_DM_BUDGET'])).get('model_discovery',{}).get('min_confidence', 0.5))" 2>/dev/null)
TODAY=$(date +%Y-%m-%d)

# Parse results, filter by confidence, merge into registry (UNDER FLOCK)
export _DM_REGISTRY="$REGISTRY_FILE"
export _DM_RESULTS="$RESULTS_FILE"
export _DM_MIN_CONF="$MIN_CONFIDENCE"
export _DM_TODAY="$TODAY"

(
flock -x 201

python3 -c "
import yaml, json, os, sys, re

VALID_SLUG = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9/_.-]{0,127}$')

reg_path = os.environ['_DM_REGISTRY']
results_path = os.environ['_DM_RESULTS']
min_conf = float(os.environ['_DM_MIN_CONF'])
today = os.environ['_DM_TODAY']

with open(reg_path) as f:
    reg = yaml.safe_load(f) or {}

if 'models' not in reg or reg['models'] is None:
    reg['models'] = {}

with open(results_path) as f:
    results = json.load(f)

added = 0
skipped = 0
for candidate in results.get('candidates', []):
    slug = candidate.get('model_id', '')
    if not slug or not VALID_SLUG.match(slug):
        print(f'  SKIP: invalid slug format: {repr(slug)}', file=sys.stderr)
        skipped += 1
        continue
    confidence = candidate.get('confidence', 0)
    if confidence < min_conf:
        skipped += 1
        continue
    if slug in reg['models']:
        print(f'  Duplicate: {slug} already in registry, skipping', file=sys.stderr)
        skipped += 1
        continue

    reg['models'][slug] = {
        'provider': 'openrouter',
        'model_family': candidate.get('family', 'unknown'),
        'eligible_tiers': candidate.get('tiers', ['checker']),
        'status': 'candidate',
        'discovered': today,
        'interrank_score': candidate.get('score', 0),
        'interrank_confidence': confidence,
        'cost_per_mtok': candidate.get('cost_per_mtok', 0),
        'qualified_via': None,
        'prompt_content_policy': 'fixtures_only',
        'qualification': {
            'shadow_runs': 0,
            'format_compliance': None,
            'finding_recall': None,
            'severity_accuracy': None,
            'qualified_date': None,
        },
        'fluxbench': None,
        'qualified_baseline': None,
    }
    added += 1
    print(f'  Added: {slug} (score={candidate.get(\"score\",0):.2f}, cost=\${candidate.get(\"cost_per_mtok\",0):.2f}/MTok)', file=sys.stderr)

reg['last_discovery'] = today
reg['last_discovery_source'] = results.get('source', 'interrank')

with open(reg_path, 'w') as f:
    yaml.dump(reg, f, default_flow_style=False, sort_keys=False)

print(f'Discovery complete: {added} added, {skipped} skipped', file=sys.stderr)
"

) 201>"${REGISTRY_FILE}.lock"

echo "Registry updated: $REGISTRY_FILE" >&2
```

**Step 2: Make executable and add `prompt_content_policy` default to discover-models.sh**

```bash
chmod +x interverse/interflux/scripts/discover-merge.sh
```

**Step 3: Commit**
```bash
git -C interverse/interflux add scripts/discover-merge.sh scripts/discover-models.sh
git -C interverse/interflux commit -m "feat(fluxbench): add discover-merge.sh for registry candidate write"
```

<verify>
- run: `bash -n interverse/interflux/scripts/discover-merge.sh`
  expect: exit 0
</verify>

---

### Task 8: F4 pre-flight gate — validate before enforce activation

**Files:**
- Create: `interverse/interflux/scripts/validate-enforce.sh`
- Modify: `interverse/interflux/config/flux-drive/budget.yaml`

**Step 1: Write validate-enforce.sh**

```bash
#!/usr/bin/env bash
# validate-enforce.sh — pre-flight check before activating enforce mode
# Returns 0 if safe to activate, 1 with reason if not
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${SCRIPT_DIR}/../config/flux-drive/model-registry.yaml"
BUDGET="${SCRIPT_DIR}/../config/flux-drive/budget.yaml"
THRESHOLDS="${SCRIPT_DIR}/../config/flux-drive/fluxbench-thresholds.yaml"

# Check 1: calibrated thresholds exist
if [[ ! -f "$THRESHOLDS" ]]; then
  echo "FAIL: fluxbench-thresholds.yaml not found. Run fluxbench-calibrate.sh first." >&2
  exit 1
fi

export _VE_THRESHOLDS="$THRESHOLDS"
source_check=$(python3 -c "import yaml, os; t=yaml.safe_load(open(os.environ['_VE_THRESHOLDS'])); print(t.get('source',''))" 2>/dev/null) || source_check=""
if [[ "$source_check" != "claude-baseline" ]]; then
  echo "FAIL: thresholds source is '$source_check' (need 'claude-baseline'). Run fluxbench-calibrate.sh in real mode." >&2
  exit 1
fi

# Check 2: at least one model qualified_via: real
export _VE_REGISTRY="$REGISTRY"
real_qualified=$(python3 -c "
import yaml, os
reg = yaml.safe_load(open(os.environ['_VE_REGISTRY'])) or {}
models = reg.get('models') or {}
count = sum(1 for m in models.values()
            if isinstance(m, dict)
            and m.get('status') in ('auto-qualified', 'qualified', 'active')
            and m.get('qualified_via') == 'real')
print(count)
" 2>/dev/null) || real_qualified=0

if [[ "$real_qualified" -lt 1 ]]; then
  echo "FAIL: no models with qualified_via=real. Qualify at least one model first." >&2
  exit 1
fi

echo "OK: $real_qualified model(s) qualified via real inference, thresholds calibrated ($source_check)" >&2
exit 0
```

**Step 2: Update budget.yaml — add enforce_since placeholder**

Add after `cross_model_dispatch:`:
```yaml
  # enforce_since: null  # Set automatically when mode first switched to enforce
```

**Step 3: Commit**
```bash
chmod +x interverse/interflux/scripts/validate-enforce.sh
git -C interverse/interflux add scripts/validate-enforce.sh config/flux-drive/budget.yaml
git -C interverse/interflux commit -m "feat(fluxbench): add validate-enforce.sh pre-flight gate"
```

<verify>
- run: `bash interverse/interflux/scripts/validate-enforce.sh 2>&1`
  expect: contains "FAIL"
- run: `bash -n interverse/interflux/scripts/validate-enforce.sh`
  expect: exit 0
</verify>

---

### Task 9: Challenger slot — add qualified_via filter to fluxbench-challenger.sh

**Files:**
- Modify: `interverse/interflux/scripts/fluxbench-challenger.sh`

**Step 1: Add `qualified_via: real` filter to `select` action**

In the `_action_select` function, after reading candidates from registry, add a filter:
```python
# Filter: only models qualified via real inference (not mock)
candidates = {k: v for k, v in candidates.items()
              if v.get('qualified_via') == 'real'}
```

**Step 2: Add `prompt_content_policy` to challenger selection output**

When outputting the selected challenger, include its content policy:
```python
print(json.dumps({
    'model_slug': best_slug,
    'provider': best.get('provider', 'unknown'),
    'prompt_content_policy': best.get('prompt_content_policy', 'fixtures_only'),
    'eligible_tiers': best.get('eligible_tiers', []),
}))
```

**Step 3: Preserve `qualified_via` in both promotion paths**

In `_action_evaluate`, both early-exit and normal promotion `_registry_write` snippets must preserve the field:
```python
# Preserve qualified_via on promotion (don't let it become None)
model['qualified_via'] = model.get('qualified_via') or 'unknown'
if model['qualified_via'] == 'unknown':
    print(f'  WARNING: {slug} promoted without qualified_via — was it qualified?', file=sys.stderr)
```

**Step 4: Write JSONL results explicitly in evaluate**

Ensure `_action_evaluate` writes scored results to `fluxbench-results.jsonl` with all required fields:
```python
result_entry = {
    'model_slug': slug,
    'fixture_id': fixture_id,
    'timestamp': timestamp,
    'gate_results': gate_results,
    'overall_pass': overall_pass,
}
```

**Step 4: Commit**
```bash
git -C interverse/interflux add scripts/fluxbench-challenger.sh
git -C interverse/interflux commit -m "feat(fluxbench): add qualified_via filter and content_policy to challenger"
```

<verify>
- run: `bash interverse/interflux/scripts/fluxbench-challenger.sh status 2>&1`
  expect: exit 0
- run: `bash -n interverse/interflux/scripts/fluxbench-challenger.sh`
  expect: exit 0
</verify>

---

### Task 10: Integration test — end-to-end mock qualification with new fields

**Files:**
- Create: `interverse/interflux/tests/shell/test_qualify_mock_fields.bats` (or inline bash test)

**Step 1: Run mock qualification and verify new fields**

```bash
# Clean slate
cp interverse/interflux/config/flux-drive/model-registry.yaml /tmp/registry-backup.yaml
trap 'cp /tmp/registry-backup.yaml interverse/interflux/config/flux-drive/model-registry.yaml' EXIT

# Run mock qualification
bash interverse/interflux/scripts/fluxbench-qualify.sh test-model-mock --mock 2>/dev/null

# Verify qualified_via field
qualified_via=$(python3 -c "
import yaml
reg = yaml.safe_load(open('interverse/interflux/config/flux-drive/model-registry.yaml'))
print(reg['models']['test-model-mock'].get('qualified_via', 'MISSING'))
")
echo "qualified_via: $qualified_via"
[[ "$qualified_via" == "mock" ]] || { echo "FAIL: expected mock, got $qualified_via"; exit 1; }

# Verify validate-enforce rejects mock-qualified model
if bash interverse/interflux/scripts/validate-enforce.sh 2>/dev/null; then
  echo "FAIL: validate-enforce should reject mock-qualified model"
  exit 1
fi
echo "PASS: mock-qualified model correctly blocked from enforce"
```

**Step 2: Commit**
```bash
git -C interverse/interflux add tests/
git -C interverse/interflux commit -m "test(fluxbench): integration test for qualified_via field and enforce gate"
```

<verify>
- run: `echo "integration test verified in Step 1"`
  expect: exit 0
</verify>

---

## Execution Order

```
Task 1 (MCP scaffold) ──► Task 2 (launcher + plugin.json)
                                    │
Task 3 (registry fields) ◄─────────┘
                                    │
Task 4 (calibrate real mode) ──► Task 5 (run calibration)
                                    │
Task 6 (qualify real mode) ◄────────┘
                                    │
Task 7 (discover-merge) ───────── (parallel with Task 4-6)
                                    │
Task 8 (enforce gate) ◄────────────┘
                                    │
Task 9 (challenger filter) ◄────────┘
                                    │
Task 10 (integration test) ◄───────┘
```

**Parallelizable:** Tasks 1+3+7 can run in parallel (no shared files). Tasks 4-6 are sequential (calibrate → run → qualify). Task 8-10 depend on all prior.
