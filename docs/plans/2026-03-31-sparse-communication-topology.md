---
bead: sylveste-rsj.11
date: 2026-03-31
type: plan
reviewed: true
review-method: flux-drive (2 agents: fd-architecture, fd-correctness)
review-verdict: needs-changes (4 P1 — all addressed in implementation)
---

# Sparse Communication Topology — Implementation Plan

## Overview

Add domain-aware sparse topology to the reaction round's peer findings assembly. 1 file to create, 1 to modify. Zero new dispatches. Fully backward-compatible — disabled mode reverts to current fully-connected behavior.

## Tasks

### Task 1: Create topology configuration

**File:** `interverse/interflux/config/flux-drive/discourse-topology.yaml`
**Action:** Create new file
**Description:**

```yaml
topology:
  enabled: true
  mode: domain-aware
  # Visibility levels
  #   full: complete peer findings (index + summary)
  #   summary: index lines only (severity + ID + title)
  #   none: no visibility
  domain_proximity:
    same_role: full
    adjacent_role: summary
    distant_role: none
  # Role adjacency derived from agent-roles.yaml role ordering:
  # planner ↔ reviewer ↔ editor ↔ checker
  adjacency:
    planner: [reviewer]
    reviewer: [planner, editor]
    editor: [reviewer, checker]
    checker: [editor]
  # Default role for agents not in agent-roles.yaml (e.g., project-specific fd-* agents)
  default_role: editor
```

Also register in reaction.yaml under `discourse:`:
```yaml
topology: discourse-topology.yaml
```

**Depends on:** Nothing

### Task 2: Modify peer findings assembly in reaction phase

**File:** `interverse/interflux/skills/flux-drive/phases/reaction.md`
**Action:** Modify Step 2.5.2
**Description:** Replace the single-pass peer findings assembly with topology-aware assembly.

Current behavior (fully-connected):
```
For each agent: peer_findings = ALL other agents' findings
```

New behavior (when topology enabled):

**Step 2.5.2: Collect Findings Indexes (topology-aware)**

1. Read topology config from `config/flux-drive/discourse-topology.yaml`. If file missing or `topology.enabled` is false, use fully-connected (current behavior — skip all topology logic).

2. Read agent role assignments from `config/flux-drive/agent-roles.yaml`. Build a map: `agent_name → role`. Agents not in the map get `default_role` from topology config.

3. For each reacting agent, determine **visibility** for every other agent:
   - Look up both agents' roles
   - If same role → `full` (include complete findings index + summary)
   - If roles are adjacent (per `adjacency` map) → `summary` (include only the index line: `- SEVERITY | ID | "Section" | Title`)
   - If roles are not adjacent → `none` (exclude entirely)

4. Build per-agent peer findings:
   - **Full visibility:** Include the complete Findings Index block (multi-line, with titles and any sub-descriptions)
   - **Summary visibility:** Include only the parsed index lines (one line per finding: `- SEVERITY | ID | Title`)
   - **None:** Exclude this peer's findings entirely

5. The combined `{peer_findings}` for each agent now contains only the findings they should see, at the appropriate detail level.

6. **Log topology:** After assembly, report:
   ```
   Topology: domain-aware ({N} agents, {full_edges} full, {summary_edges} summary, {none_edges} excluded)
   ```

**No changes to Steps 2.5.0, 2.5.2b, 2.5.3, 2.5.4, or 2.5.5** — the convergence gate, fixative, prompt building, dispatch, and report all work on the filtered peer findings. The convergence gate (Step 2.5.0) continues to use ALL findings for its overlap computation (it runs before topology filtering).

**Depends on:** Task 1

## Build Sequence

```
Task 1 (config + reaction.yaml) → Task 2 (reaction phase modification)
```

Sequential — Task 2 references the config from Task 1.

## Verification

1. `python3 -c "import yaml; yaml.safe_load(open('interverse/interflux/config/flux-drive/discourse-topology.yaml'))"` — YAML validity
2. Grep for `topology` in reaction.md — topology logic present
3. Grep for `discourse-topology` in reaction.yaml — registered in discourse section
4. Grep for `same_role.*full` in reaction.md — visibility levels implemented
5. Verify fully-connected fallback: grep for `topology.enabled.*false` or `file missing` handling
