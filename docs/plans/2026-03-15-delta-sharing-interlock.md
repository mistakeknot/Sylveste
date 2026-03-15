---
artifact_type: plan
bead: Demarch-a4c
stage: design
---
# Delta Sharing via Interlock Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-a4c
**Goal:** When a campaign records a mutation, broadcast it via interlock so parallel sessions can discover and build on each other's approaches.

**Architecture:** Purely skill-level integration — update `/autoresearch` SKILL.md to broadcast mutations after recording them, and query interlock inbox at campaign start alongside `mutation_query`. No new Go code needed. The interlock `broadcast_message` tool already exists with topic-based fan-out to all agents in the project.

**Tech Stack:** SKILL.md updates only. Uses existing MCP tools: `mutation_record`, `broadcast_message`, `list_topic_messages`, `fetch_inbox`.

---

## Must-Haves

**Truths:**
- After each `mutation_record`, the agent broadcasts the mutation via `broadcast_message` with topic `"mutation"`
- At campaign start, the agent checks `list_topic_messages` for topic `"mutation"` to discover cross-session approaches
- Broadcasting is best-effort — failure does not stop the campaign
- The broadcast body is structured JSON matching the mutation record format

---

### Task 1: Add mutation broadcast to /autoresearch after mutation_record

**Files:**
- Modify: `interverse/interlab/skills/autoresearch/SKILL.md`

**Step 1: Read the current SKILL.md**

Read `interverse/interlab/skills/autoresearch/SKILL.md` to find the "5b. Record Mutation" section added in the mutation store integration.

**Step 2: Add broadcast after mutation_record**

After the `mutation_record` call in section "5b. Record Mutation", add:

```markdown
#### 5c. Broadcast Mutation (if interlock available)

After recording the mutation, broadcast it so parallel sessions can discover this approach:

1. Call `broadcast_message` with:
   - `topic`: `"mutation"`
   - `subject`: `"[<campaign_name>] <keep|discard|crash>: <hypothesis summary>"`
   - `body`: JSON string with: `{"task_type": "<type>", "hypothesis": "<description>", "quality_signal": <value>, "is_new_best": <bool>, "campaign_id": "<name>", "session_id": "<id>"}`

2. If `broadcast_message` fails or is unavailable (interlock not loaded): continue silently. Broadcasting is best-effort.
```

**Step 3: Commit**

```bash
cd interverse/interlab && git add skills/autoresearch/SKILL.md
git commit -m "feat: broadcast mutations via interlock after recording"
```

<verify>
- run: `grep -c "broadcast_message" /home/mk/projects/Demarch/interverse/interlab/skills/autoresearch/SKILL.md`
  expect: contains "1"
</verify>

---

### Task 2: Add cross-session mutation discovery at campaign start

**Files:**
- Modify: `interverse/interlab/skills/autoresearch/SKILL.md`

**Step 1: Add interlock query to Step 6 (Query Prior Mutations)**

In the existing "Step 6: Query Prior Mutations" section, after the `mutation_query` call, add:

```markdown
#### Cross-Session Discovery (if interlock available)

In addition to the local mutation store, check for broadcasts from parallel sessions:

1. Call `list_topic_messages` with `topic: "mutation"` to get recent mutation broadcasts from other agents.

2. For each broadcast message:
   - Parse the JSON body to extract task_type, hypothesis, quality_signal, is_new_best
   - If `task_type` matches the current campaign's task type, add to the "Prior Approaches" section
   - Mark these as "cross-session" to distinguish from local mutation store results

3. If `list_topic_messages` fails or is unavailable: continue with local mutation store only.

This enables compound learning: Agent A's discovery feeds Agent B's hypothesis generation, even when they're running in different sessions.
```

**Step 2: Commit**

```bash
cd interverse/interlab && git add skills/autoresearch/SKILL.md
git commit -m "feat: query interlock for cross-session mutation discoveries at campaign start"
```

<verify>
- run: `grep -c "list_topic_messages" /home/mk/projects/Demarch/interverse/interlab/skills/autoresearch/SKILL.md`
  expect: contains "1"
</verify>

---

### Task 3: Add broadcast to /autoresearch-multi campaign synthesis

**Files:**
- Modify: `interverse/interlab/skills/autoresearch-multi/SKILL.md`

**Step 1: Read the current SKILL.md**

Read `interverse/interlab/skills/autoresearch-multi/SKILL.md` to find the synthesis phase.

**Step 2: Add cross-campaign broadcast in synthesis**

In the synthesis phase (Phase 4 or equivalent), add a section for broadcasting the aggregate results:

```markdown
#### Broadcast Aggregate Results

After synthesis completes, broadcast the campaign results so future sessions benefit:

1. For each campaign that improved its metric, call `broadcast_message` with:
   - `topic`: `"mutation"`
   - `subject`: `"[multi:<parent_bead>] <campaign_name> improved <metric> by <delta>%"`
   - `body`: JSON with the best approach for each campaign (task_type, hypothesis, quality_signal, campaign_id)

2. This is best-effort — failure does not block synthesis completion.
```

**Step 3: Commit**

```bash
cd interverse/interlab && git add skills/autoresearch-multi/SKILL.md
git commit -m "feat: broadcast aggregate results from multi-campaign synthesis via interlock"
```

<verify>
- run: `grep -c "broadcast_message" /home/mk/projects/Demarch/interverse/interlab/skills/autoresearch-multi/SKILL.md`
  expect: contains "1"
</verify>

---

### Task 4: Version bump and push

**Files:**
- Modify: `interverse/interlab/.claude-plugin/plugin.json`

**Step 1: Bump version**

Update from `0.4.1` to `0.4.2` (skill integration, no API change).

**Step 2: Commit and push**

```bash
cd interverse/interlab && git add .claude-plugin/plugin.json
git commit -m "chore: bump interlab to v0.4.2 (delta sharing via interlock)"
git push
```

<verify>
- run: `grep '"version"' /home/mk/projects/Demarch/interverse/interlab/.claude-plugin/plugin.json`
  expect: contains "0.4.2"
</verify>
