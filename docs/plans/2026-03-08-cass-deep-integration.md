---
artifact_type: plan
bead: none
stage: design
---
# Deep cass Integration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** none
**Goal:** Integrate cass across Sylveste — shrink interstat, move session search to intersearch, wire cass into 4 downstream commands, add cross-agent analytics to galiana.

**Architecture:** cass becomes the session intelligence backend (search, timeline, context, export, analytics). interstat keeps its unique value: bead-correlated token metrics, failure classification, cost-per-landable-change. intersearch gets a new session-search skill wrapping all cass subcommands.

**Tech Stack:** bash (hooks, scripts), cass CLI (`--robot --json`), Python (galiana), markdown (skills, commands)

---

## Must-Haves

**Truths** (observable behaviors):
- `interstat:session-search` skill no longer exists; `intersearch:session-search` handles all session queries
- `cass search`, `cass timeline`, `cass context`, `cass export`, `cass analytics` are all accessible via the intersearch skill
- interstat's sessions.db is no longer created or referenced
- `/reflect` exports session transcripts (markdown + JSON) alongside learning artifacts
- `/compound` surfaces similar past sessions before documenting
- cass index stays fresh via conditional SessionStart hook

**Artifacts** (files that must exist):
- `interverse/intersearch/skills/session-search/SKILL.md` — new cass wrapper skill
- `interverse/interstat/hooks/session-start.sh` — updated with cass index check
- `os/clavain/commands/reflect.md` — updated with session export step
- `os/clavain/commands/compound.md` — updated with similar session discovery

**Key Links:**
- intersearch session-search skill delegates all queries to `cass` CLI
- interstat SessionStart hook checks `cass health` before `cass index`
- reflect command calls `cass export` after learning artifact is written

---

### Task 1: Remove session analytics from interstat

Remove sessions.db infrastructure. interstat no longer creates, indexes, or queries sessions.db.

**Files:**
- Delete: `interverse/interstat/scripts/session-index.py`
- Delete: `interverse/interstat/scripts/session-search.sh`
- Delete: `interverse/interstat/skills/session-search/SKILL.md`
- Modify: `interverse/interstat/CLAUDE.md`
- Modify: `interverse/interstat/AGENTS.md`
- Modify: `interverse/interstat/.claude-plugin/plugin.json` (remove skill registration)

**Step 1: Delete session-index.py**

```bash
rm interverse/interstat/scripts/session-index.py
```

**Step 2: Delete session-search.sh**

```bash
rm interverse/interstat/scripts/session-search.sh
```

**Step 3: Delete session-search skill directory**

```bash
rm -rf interverse/interstat/skills/session-search/
```

**Step 4: Update plugin.json to remove session-search skill**

Remove the `session-search` entry from the `skills` array in `.claude-plugin/plugin.json`.

**Step 5: Update CLAUDE.md**

Remove references to session-search.sh, session-index.py, sessions.db, and FTS5 from the Session Analytics section. Replace with a note that session search moved to intersearch.

Update the Session Analytics section to read:

```markdown
## Session Analytics

Session search has moved to the `intersearch` plugin (via cass). interstat retains token metrics and bead-aware analytics only.

For session search, timeline, context, and export: use `/intersearch:session-search`.
```

**Step 6: Update AGENTS.md**

Update the Session Search & Analytics section to reflect that search moved to intersearch. Keep the analytics commands that query metrics.db (cost-query.sh).

**Step 7: Commit**

```bash
cd interverse/interstat
git add -A scripts/session-index.py scripts/session-search.sh skills/session-search/ CLAUDE.md AGENTS.md .claude-plugin/plugin.json
git commit -m "refactor: remove session analytics — search moved to intersearch via cass"
```

<verify>
- run: `test ! -f interverse/interstat/scripts/session-index.py`
  expect: exit 0
- run: `test ! -f interverse/interstat/scripts/session-search.sh`
  expect: exit 0
- run: `test ! -d interverse/interstat/skills/session-search`
  expect: exit 0
- run: `python3 -c "import json; d=json.load(open('interverse/interstat/.claude-plugin/plugin.json')); skills=[s['name'] for s in d.get('skills',[])]; assert 'session-search' not in skills, f'still present: {skills}'"`
  expect: exit 0
</verify>

---

### Task 2: Create session-search skill in intersearch

New skill wrapping all cass capabilities: search, timeline, context, export, analytics.

**Files:**
- Create: `interverse/intersearch/skills/session-search/SKILL.md`
- Modify: `interverse/intersearch/.claude-plugin/plugin.json` (add skill registration)
- Modify: `interverse/intersearch/CLAUDE.md` (document new skill)

**Step 1: Create skills directory**

```bash
mkdir -p interverse/intersearch/skills/session-search
```

**Step 2: Write SKILL.md**

Create `interverse/intersearch/skills/session-search/SKILL.md` with:

```markdown
---
name: session-search
description: Search past agent sessions, view timelines, find sessions by file, export transcripts, and analyze token/tool/model usage. Delegates to cass (Rust-native, sub-60ms, 15 agent providers). Use when the user asks "what did I work on?", "find sessions about X", "show session stats", "what sessions touched this file?", "export this session", or "show token analytics".
user_invocable: true
---

# Session Search & Analytics

Search and analyze past coding agent sessions across all providers (Claude Code, Codex, Gemini, Cursor, etc.). Powered by [cass](https://github.com/Dicklesworthstone/coding_agent_session_search).

**Requires:** cass >= 0.2.0 (`~/.local/bin/cass`)

**Announce at start:** "I'm using the session-search skill to query your session history."

## Step 0: Pre-flight Check

```bash
if ! command -v cass > /dev/null 2>&1; then
    echo "cass not installed. Install: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh | bash"
    exit 1
fi
# Version check
CASS_VERSION=$(cass --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
echo "cass version: $CASS_VERSION"
```

If cass is missing, tell the user to install it and stop. If version is below 0.2.0, warn but continue.

## Step 1: Ensure Index is Fresh

```bash
STALE=$(cass health --json 2>/dev/null | python3 -c "import sys,json; h=json.load(sys.stdin); print(h['state']['index']['stale'])" 2>/dev/null || echo "True")
if [ "$STALE" = "True" ] || [ "$STALE" = "true" ]; then
    cass index --full 2>/dev/null
fi
```

## Step 2: Route by Intent

### "Find sessions about X" / "Search for X"
```bash
cass search "<query>" --robot --limit 10 --mode hybrid
```
Modes: `hybrid` (default, best), `lexical` (keyword-only BM25), `semantic` (embedding similarity).
Filters: `--workspace <path>`, `--agent <slug>`, `--since <date>`, `--until <date>`.

### "What did I work on [this week/recently]?" / "Show timeline"
```bash
cass timeline --today --json
cass timeline --since 7d --json --group-by day
cass timeline --since 2026-03-01 --until 2026-03-07 --json
```
Filters: `--agent <slug>`, `--source local|remote`.

### "What sessions touched this file?" / "Who worked on X?"
```bash
cass context <path/to/file> --json --limit 5
```
Returns sessions that reference the given source path.

### "Export this session" / "Save session transcript"
```bash
cass export <session_file_path> --format markdown -o <output_path>
cass export <session_file_path> --format json -o <output_path>
```
Formats: `markdown`, `text`, `json`, `html`. Use `--include-tools` for tool call details.

### "Show token analytics" / "How many tokens this week?"
```bash
cass analytics tokens --days 7 --json
cass analytics tokens --workspace /home/mk/projects/Sylveste --json --group-by day
```
Also available: `cass analytics tools --json`, `cass analytics models --json`.

### "Show session stats"
```bash
cass stats --json
```

## Step 3: Present Results

Format output as a readable table or summary. Highlight:
- Number of sessions/messages found
- Project distribution (for stats/timeline)
- Key message excerpts (for search results)
- File relationships (for context results)
- Token breakdowns by agent/model (for analytics)

## Dependencies

- **cass** >= 0.2.0 — session search engine. Install: `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh" | bash`
- Index location: `~/.local/share/coding-agent-search/`
```

**Step 3: Update plugin.json to register the skill**

Add the session-search skill to intersearch's `.claude-plugin/plugin.json` skills array.

**Step 4: Update CLAUDE.md**

Add a section to intersearch's CLAUDE.md documenting the session-search skill.

**Step 5: Commit**

```bash
cd interverse/intersearch
git add skills/session-search/SKILL.md .claude-plugin/plugin.json CLAUDE.md
git commit -m "feat: add session-search skill — cass-powered session intelligence"
```

<verify>
- run: `test -f interverse/intersearch/skills/session-search/SKILL.md`
  expect: exit 0
- run: `python3 -c "import json; d=json.load(open('interverse/intersearch/.claude-plugin/plugin.json')); skills=[s['name'] for s in d.get('skills',[])]; assert 'session-search' in skills, f'missing: {skills}'"`
  expect: exit 0
</verify>

---

### Task 3: Add cass index freshness check to interstat SessionStart hook

Piggyback on interstat's existing SessionStart hook to keep cass's index fresh. Conditional: only index if stale >1 hour.

**Files:**
- Modify: `interverse/interstat/hooks/session-start.sh`

**Step 1: Add cass freshness check at the end of session-start.sh**

After the existing bead context logic (line 48, before `exit 0`), add:

```bash
# Keep cass index fresh (conditional — only if stale >1 hour)
if command -v cass &>/dev/null; then
    age=$(cass health --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['state']['index']['age_seconds'])" 2>/dev/null || echo "0")
    if [[ "$age" -gt 3600 ]]; then
        cass index --full &>/dev/null &
    fi
fi
```

Note: runs `cass index` in background (`&`) to avoid blocking session start. The `&>/dev/null` suppresses output.

**Step 2: Commit**

```bash
cd interverse/interstat
git add hooks/session-start.sh
git commit -m "feat: conditional cass index refresh on SessionStart (>1hr stale)"
```

<verify>
- run: `grep -q "cass index" interverse/interstat/hooks/session-start.sh`
  expect: exit 0
- run: `bash -n interverse/interstat/hooks/session-start.sh`
  expect: exit 0
</verify>

---

### Task 4: Add session transcript export to /reflect

After the learning artifact is written and registered, export the session transcript in both markdown and JSON formats.

**Files:**
- Modify: `os/clavain/commands/reflect.md`

**Step 1: Add session export step after step 4 (register artifact), before step 5 (advance)**

Insert a new step 4b between the existing steps 4 and 5:

```markdown
4b. **Export session transcript (non-blocking).** Archive the sprint session as a durable receipt:
   ```bash
   session_file=$(ls -t ~/.claude/projects/*/$(cat /tmp/interstat-session-id 2>/dev/null || echo "unknown")*.jsonl 2>/dev/null | head -1)
   if [[ -n "$session_file" ]] && command -v cass &>/dev/null; then
       transcript_dir="docs/sprints"
       mkdir -p "$transcript_dir"
       cass export "$session_file" --format markdown -o "${transcript_dir}/<sprint_id>-transcript.md" 2>/dev/null || true
       cass export "$session_file" --format json -o "${transcript_dir}/<sprint_id>-transcript.json" 2>/dev/null || true
   fi
   ```
   Silent on failure — transcript export is supplementary, not gate-enforced.
```

**Step 2: Commit**

```bash
cd os/clavain
git add commands/reflect.md
git commit -m "feat: /reflect exports session transcripts via cass (markdown + JSON)"
```

<verify>
- run: `grep -q "cass export" os/clavain/commands/reflect.md`
  expect: exit 0
</verify>

---

### Task 5: Add similar session discovery to /compound

Before invoking engineering-docs, search for past sessions with similar problems to surface documentation gaps.

**Files:**
- Modify: `os/clavain/commands/compound.md`

**Step 1: Add similar session discovery before the engineering-docs invocation**

Update the Execution section to include a cass search step:

```markdown
## Execution

### Step 1: Surface similar past sessions (non-blocking)

If cass is available, search for past sessions where similar problems may have been encountered:

```bash
if command -v cass &>/dev/null; then
    cass search "<problem description keywords>" --robot --limit 5 --mode hybrid --fields minimal 2>/dev/null
fi
```

If results are found, briefly note: "Found N past sessions touching similar topics — this documentation will help future sessions avoid re-discovery." This provides motivation but does not block the workflow.

### Step 2: Capture the solution

Use the `clavain:engineering-docs` skill to capture this solution. The skill provides the full 7-step documentation workflow including YAML validation, category classification, and cross-referencing.

If no context argument was provided, the skill will extract context from the recent conversation history.
```

**Step 2: Commit**

```bash
cd os/clavain
git add commands/compound.md
git commit -m "feat: /compound surfaces similar past sessions via cass before documenting"
```

<verify>
- run: `grep -q "cass search" os/clavain/commands/compound.md`
  expect: exit 0
</verify>

---

### Task 6: Add cass analytics tools to tool-time

Add cass as a supplementary data source for cross-agent tool usage analytics.

**Files:**
- Modify: `interverse/tool-time/skills/tool-time/SKILL.md`

**Step 1: Add cass analytics as a supplementary data source in Step 1**

After the existing analysis scripts, add an optional cass query:

```markdown
### Cross-Agent Tool Analytics (if cass available)

```bash
if command -v cass > /dev/null 2>&1; then
    cass analytics tools --days 7 --json 2>/dev/null > ~/.claude/tool-time/cass-tools.json || true
    cass analytics models --days 7 --json 2>/dev/null > ~/.claude/tool-time/cass-models.json || true
fi
```

If cass data is available, include in your analysis:
- Per-tool invocation counts across ALL agents (not just Claude Code)
- Model distribution across agents
- Compare tool usage patterns between agents (e.g., Codex uses different tools than Claude Code)
```

**Step 2: Commit**

```bash
cd interverse/tool-time
git add skills/tool-time/SKILL.md
git commit -m "feat: tool-time uses cass analytics for cross-agent tool/model data"
```

<verify>
- run: `grep -q "cass analytics tools" interverse/tool-time/skills/tool-time/SKILL.md`
  expect: exit 0
</verify>

---

### Task 7: Add cass context to internext next-work

Use `cass context` to show recent sessions that touched files related to candidate work items.

**Files:**
- Modify: `interverse/internext/skills/next-work/SKILL.md`

**Step 1: Add file context to the Gather Phase**

Add a new step 8 to the Gather Phase:

```markdown
8. **Recent file activity (if cass available)** — For the top 2-3 candidate beads, check what recent sessions touched related files:
   ```bash
   if command -v cass > /dev/null 2>&1; then
       cass context <primary_file_path> --json --limit 3 2>/dev/null
   fi
   ```
   This surfaces which beads have recent session momentum (another agent was just working on related files) vs which are cold starts. Factor into effort estimates — warm context = lower switching cost.
```

**Step 2: Commit**

```bash
cd interverse/internext
git add skills/next-work/SKILL.md
git commit -m "feat: next-work uses cass context for file activity awareness"
```

<verify>
- run: `grep -q "cass context" interverse/internext/skills/next-work/SKILL.md`
  expect: exit 0
</verify>

---

### Task 8: Add cass analytics to galiana

Add cass as a supplementary data source for cross-agent token views in galiana's analyze.py.

**Files:**
- Modify: `os/clavain/galiana/analyze.py`

**Step 1: Add a function to query cass analytics**

Add a new function `_query_cass_analytics()` near the existing `_query_interstat_tokens()` function. It should:

```python
def _query_cass_analytics(workspace: str | None = None, days: int = 30) -> dict[str, Any] | None:
    """Query cross-agent token analytics from cass (supplementary view)."""
    import shutil
    if not shutil.which("cass"):
        return None
    try:
        cmd = ["cass", "analytics", "tokens", f"--days={days}", "--json"]
        if workspace:
            cmd.extend(["--workspace", workspace])
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            return None
        return json.loads(result.stdout)
    except Exception:
        return None
```

**Step 2: Wire into the main analysis flow**

In the main analysis function, after calling `_query_interstat_tokens()`, also call `_query_cass_analytics()`. Include the cass data as a separate "cross_agent_analytics" key in the output — supplementary, not merged.

**Step 3: Commit**

```bash
cd os/clavain
git add galiana/analyze.py
git commit -m "feat: galiana queries cass analytics for cross-agent token views"
```

<verify>
- run: `grep -q "_query_cass_analytics" os/clavain/galiana/analyze.py`
  expect: exit 0
- run: `python3 -c "import ast; ast.parse(open('os/clavain/galiana/analyze.py').read())"`
  expect: exit 0
</verify>

---

### Task 9: Update documentation and publish

Update CLAUDE.md/AGENTS.md across affected modules, publish updated plugins.

**Files:**
- Modify: `interverse/interstat/CLAUDE.md`
- Modify: `interverse/intersearch/CLAUDE.md`
- Modify: `interverse/intersearch/AGENTS.md`

**Step 1: Final CLAUDE.md updates**

Ensure interstat's CLAUDE.md no longer references sessions.db or session-search. Ensure intersearch's CLAUDE.md documents the new session-search skill.

**Step 2: Publish interstat**

```bash
cd interverse/interstat && ic publish --patch
```

**Step 3: Publish intersearch**

```bash
cd interverse/intersearch && ic publish --patch
```

**Step 4: Publish clavain**

```bash
cd os/clavain && ic publish --patch
```

**Step 5: Publish tool-time**

```bash
cd interverse/tool-time && ic publish --patch
```

**Step 6: Publish internext**

```bash
cd interverse/internext && ic publish --patch
```

**Step 7: Push all repos**

```bash
cd /home/mk/projects/Sylveste
git push
cd interverse/interstat && git push
cd ../intersearch && git push
cd ../tool-time && git push
cd ../internext && git push
cd ../../os/clavain && git push
```

<verify>
- run: `test -f interverse/intersearch/skills/session-search/SKILL.md`
  expect: exit 0
- run: `test ! -f interverse/interstat/skills/session-search/SKILL.md`
  expect: exit 0
- run: `grep -q "cass" os/clavain/commands/reflect.md`
  expect: exit 0
- run: `grep -q "cass" os/clavain/commands/compound.md`
  expect: exit 0
</verify>
