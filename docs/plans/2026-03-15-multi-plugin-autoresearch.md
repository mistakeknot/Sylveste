---
artifact_type: plan
bead: Demarch-opc
stage: design
requirements:
  - F1: Plugin PQS scanner script
  - F2: Campaign spec generator for /autoresearch-multi
---
# Multi-Plugin Autoresearch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-opc
**Goal:** Create a script that scans all interverse plugins for quality scores, identifies the lowest-scoring ones, and generates campaign specs for `/autoresearch-multi` to improve them.

**Architecture:** A single bash script (`scripts/scan-plugin-quality.sh`) that runs `plugin-benchmark.sh` against each plugin, collects PQS scores, and outputs a ranked report + campaign spec JSON. The campaign spec feeds directly into `plan_campaigns` MCP tool. The mutation store (interlab v0.4.0) records provenance automatically via the wired `/autoresearch` integration.

**Tech Stack:** Bash, jq, existing `plugin-benchmark.sh`, existing `/autoresearch-multi` skill

---

## Must-Haves

**Truths:**
- Running `scan-plugin-quality.sh` produces a ranked list of all plugins with PQS scores
- The 5 lowest-scoring plugins are identified with their scores and failure reasons
- A campaign spec JSON is generated that `plan_campaigns` can consume directly
- Running `/autoresearch-multi` with the generated spec launches improvement campaigns

**Artifacts:**
- `interverse/interlab/scripts/scan-plugin-quality.sh` — scanner + report generator
- `interverse/interlab/scripts/generate-campaign-spec.sh` — campaign spec from scan results

---

### Task 1: Create plugin quality scanner script

**Files:**
- Create: `interverse/interlab/scripts/scan-plugin-quality.sh`

**Step 1: Write the scanner**

Create `interverse/interlab/scripts/scan-plugin-quality.sh`:

```bash
#!/usr/bin/env bash
# scan-plugin-quality.sh — Score all interverse plugins and rank by PQS.
#
# Usage: bash scripts/scan-plugin-quality.sh [--json] [--top=N]
#   --json    Output JSON instead of table
#   --top=N   Only show bottom N plugins (default: 5)
#
# Must be run from the monorepo root (or DEMARCH_ROOT must be set).
set -euo pipefail

DEMARCH_ROOT="${DEMARCH_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
BENCHMARK="$DEMARCH_ROOT/interverse/interlab/scripts/plugin-benchmark.sh"
PLUGIN_DIR="$DEMARCH_ROOT/interverse"

JSON_OUTPUT=false
TOP_N=5

for arg in "$@"; do
    case "$arg" in
        --json) JSON_OUTPUT=true ;;
        --top=*) TOP_N="${arg#--top=}" ;;
    esac
done

if [[ ! -f "$BENCHMARK" ]]; then
    echo "Error: plugin-benchmark.sh not found at $BENCHMARK" >&2
    exit 1
fi

# Collect results
results="[]"

for plugin_path in "$PLUGIN_DIR"/*/; do
    plugin_name=$(basename "$plugin_path")

    # Skip non-plugin directories (no plugin.json or .claude-plugin/)
    if [[ ! -f "$plugin_path/.claude-plugin/plugin.json" ]] && [[ ! -f "$plugin_path/plugin.json" ]]; then
        continue
    fi

    # Run benchmark, capture METRIC lines
    metrics=$(bash "$BENCHMARK" "$plugin_path" 2>/dev/null) || metrics=""

    pqs=$(echo "$metrics" | grep -oP 'plugin_quality_score=\K[\d.]+' || echo "0")
    audit_score=$(echo "$metrics" | grep -oP 'audit_score=\K[\d.]+' || echo "0")
    audit_max=$(echo "$metrics" | grep -oP 'audit_max=\K[\d.]+' || echo "19")
    struct_pass=$(echo "$metrics" | grep -oP 'structural_tests_pass=\K[\d.]+' || echo "0")
    struct_total=$(echo "$metrics" | grep -oP 'structural_tests_total=\K[\d.]+' || echo "0")
    build_passes=$(echo "$metrics" | grep -oP 'build_passes=\K[\d.]+' || echo "0")

    results=$(echo "$results" | jq --arg name "$plugin_name" \
        --arg path "$plugin_path" \
        --argjson pqs "${pqs:-0}" \
        --argjson audit "${audit_score:-0}" \
        --argjson audit_max "${audit_max:-19}" \
        --argjson struct_pass "${struct_pass:-0}" \
        --argjson struct_total "${struct_total:-0}" \
        --argjson build "${build_passes:-0}" \
        '. + [{
            name: $name,
            path: $path,
            pqs: $pqs,
            audit_score: $audit,
            audit_max: $audit_max,
            structural_pass: $struct_pass,
            structural_total: $struct_total,
            build_passes: $build
        }]')
done

# Sort by PQS ascending (worst first)
sorted=$(echo "$results" | jq 'sort_by(.pqs)')
bottom=$(echo "$sorted" | jq --argjson n "$TOP_N" '.[:$n]')
total=$(echo "$sorted" | jq 'length')
avg_pqs=$(echo "$sorted" | jq '[.[].pqs] | if length > 0 then add / length else 0 end')

if [[ "$JSON_OUTPUT" == true ]]; then
    echo "$sorted" | jq --argjson bottom "$bottom" --argjson total "$total" --argjson avg "$avg_pqs" '{
        total_plugins: $total,
        avg_pqs: $avg,
        bottom: $bottom,
        all: .
    }'
else
    echo "Plugin Quality Scan: $total plugins scored (avg PQS: $(printf '%.3f' "$avg_pqs"))"
    echo ""
    echo "Bottom $TOP_N (improvement targets):"
    echo "| Plugin | PQS | Audit | Build | Struct |"
    echo "|--------|-----|-------|-------|--------|"
    echo "$bottom" | jq -r '.[] | "| \(.name) | \(.pqs | tostring | .[0:5]) | \(.audit_score)/\(.audit_max) | \(.build_passes) | \(.structural_pass)/\(.structural_total) |"'
    echo ""
    echo "Full ranking:"
    echo "$sorted" | jq -r '.[] | "\(.pqs | tostring | .[0:5]) \(.name)"'
fi
```

**Step 2: Make executable and test**

```bash
chmod +x interverse/interlab/scripts/scan-plugin-quality.sh
```

Run: `cd /home/mk/projects/Demarch && bash interverse/interlab/scripts/scan-plugin-quality.sh --top=3 2>/dev/null`
Expected: Table output with plugin names and PQS scores

**Step 3: Commit**

```bash
cd interverse/interlab && git add scripts/scan-plugin-quality.sh
git commit -m "feat: add plugin quality scanner (ranks all plugins by PQS)"
```

<verify>
- run: `cd /home/mk/projects/Demarch && bash interverse/interlab/scripts/scan-plugin-quality.sh --json --top=3 2>/dev/null | jq '.total_plugins'`
  expect: exit 0
</verify>

---

### Task 2: Create campaign spec generator

**Files:**
- Create: `interverse/interlab/scripts/generate-campaign-spec.sh`

**Step 1: Write the generator**

Create `interverse/interlab/scripts/generate-campaign-spec.sh`:

```bash
#!/usr/bin/env bash
# generate-campaign-spec.sh — Generate /autoresearch-multi campaign spec from scan results.
#
# Usage: bash scripts/generate-campaign-spec.sh [--top=N]
#   Reads scan results and outputs campaign spec JSON for plan_campaigns.
#
# Must be run from the monorepo root.
set -euo pipefail

DEMARCH_ROOT="${DEMARCH_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
SCANNER="$DEMARCH_ROOT/interverse/interlab/scripts/scan-plugin-quality.sh"
BENCHMARK="$DEMARCH_ROOT/interverse/interlab/scripts/plugin-benchmark.sh"

TOP_N=5
for arg in "$@"; do
    case "$arg" in
        --top=*) TOP_N="${arg#--top=}" ;;
    esac
done

# Get scan results
scan=$(bash "$SCANNER" --json --top="$TOP_N" 2>/dev/null)
bottom=$(echo "$scan" | jq '.bottom')
count=$(echo "$bottom" | jq 'length')

if [[ "$count" -eq 0 ]]; then
    echo "No plugins to improve." >&2
    exit 0
fi

# Generate campaign spec
echo "$bottom" | jq --arg benchmark "$BENCHMARK" '[
    .[] | {
        name: ("pqs-improve-" + .name),
        description: ("Improve plugin quality score for " + .name + " (current PQS: " + (.pqs | tostring) + ")"),
        metric_name: "plugin_quality_score",
        metric_unit: "score",
        direction: "higher_is_better",
        benchmark_command: ("bash " + $benchmark + " " + .path),
        working_directory: .path,
        task_type: "plugin-quality",
        files_in_scope: [
            (.path + "skills/"),
            (.path + ".claude-plugin/"),
            (.path + "hooks/"),
            (.path + "agents/")
        ]
    }
]'
```

**Step 2: Make executable and test**

```bash
chmod +x interverse/interlab/scripts/generate-campaign-spec.sh
```

Run: `cd /home/mk/projects/Demarch && bash interverse/interlab/scripts/generate-campaign-spec.sh --top=2 2>/dev/null | jq '.[0].name'`
Expected: Output like `"pqs-improve-<plugin-name>"`

**Step 3: Commit**

```bash
cd interverse/interlab && git add scripts/generate-campaign-spec.sh
git commit -m "feat: add campaign spec generator for multi-plugin autoresearch"
```

<verify>
- run: `cd /home/mk/projects/Demarch && bash interverse/interlab/scripts/generate-campaign-spec.sh --top=2 2>/dev/null | jq 'length'`
  expect: contains "2"
</verify>

---

### Task 3: Update campaigns/README.md with usage instructions

**Files:**
- Modify: `interverse/interlab/campaigns/README.md`

**Step 1: Read existing README**

Read `interverse/interlab/campaigns/README.md` to understand current format.

**Step 2: Add multi-plugin section**

Append a section documenting how to run multi-plugin improvement:

```markdown
## Multi-Plugin Improvement

Scan all plugins, find the lowest-scoring, and run parallel improvement campaigns:

```bash
# 1. Scan all plugins for quality scores
cd /home/mk/projects/Demarch
bash interverse/interlab/scripts/scan-plugin-quality.sh

# 2. Generate campaign spec for bottom 5
bash interverse/interlab/scripts/generate-campaign-spec.sh --top=5 > /tmp/campaigns.json

# 3. Launch via /autoresearch-multi
# Use the generated spec with plan_campaigns MCP tool
```
```

**Step 3: Commit**

```bash
cd interverse/interlab && git add campaigns/README.md
git commit -m "docs: add multi-plugin improvement usage to campaigns README"
```

<verify>
- run: `grep -c "Multi-Plugin" /home/mk/projects/Demarch/interverse/interlab/campaigns/README.md`
  expect: contains "1"
</verify>

---

### Task 4: Run the scanner end-to-end and verify

**Files:**
- No new files

**Step 1: Run full scan**

Run: `cd /home/mk/projects/Demarch && bash interverse/interlab/scripts/scan-plugin-quality.sh 2>/dev/null`
Expected: Table showing all plugins ranked by PQS

**Step 2: Generate campaign spec**

Run: `cd /home/mk/projects/Demarch && bash interverse/interlab/scripts/generate-campaign-spec.sh --top=3 2>/dev/null | jq .`
Expected: JSON array with 3 campaign specs

**Step 3: Verify mutation store integration**

The campaign spec includes `task_type: "plugin-quality"` which means when `/autoresearch` runs these campaigns, mutations will be automatically recorded with this task type. Verify the field is present:

Run: `cd /home/mk/projects/Demarch && bash interverse/interlab/scripts/generate-campaign-spec.sh --top=1 2>/dev/null | jq '.[0].task_type'`
Expected: `"plugin-quality"`

**Step 4: Version bump**

Update interlab from `0.4.0` to `0.4.1` (new scripts, no API change).

```bash
cd interverse/interlab && git add .claude-plugin/plugin.json
git commit -m "chore: bump interlab to v0.4.1 (multi-plugin quality scanner)"
```

<verify>
- run: `cd /home/mk/projects/Demarch && bash interverse/interlab/scripts/scan-plugin-quality.sh --json --top=1 2>/dev/null | jq '.total_plugins > 0'`
  expect: contains "true"
</verify>
