---
artifact_type: plan
bead: Demarch-ef08
stage: design
requirements:
  - F1-prereq: Enrich factory-status.go
  - F1a: IdeaGUI Reader
  - F1b: Factory-Status Reader
  - F1c: Snapshot Generator
  - F1d: CLI Entry Point
---
# IdeaGUI Data Pipe (F1) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-ef08
**Goal:** Export two independent data readers (roster + factory-status) with an optional project-level join, for Meadowsyn experiments.

**Architecture:** Two independent readers — `readRoster()` (file-based, cached) and `readFactoryStatus()` (clavain-cli, polled). `generateSnapshot()` combines both layers, joining WIP to roster at project level using the `project` field emitted by factory-status.go. No global merge; experiments consume what they need.

**Tech Stack:** Go (factory-status.go prereq, ~5 LOC). Node.js >= 18, ES modules, `node:child_process` (execFileSync — no shell), `node:fs`. Zero npm dependencies.

**Prior Learnings:** 8-agent research review found per-agent matching impossible (no FK between CLAUDE_SESSION_ID and roster). Only F2+F4 need the join. F3/F6/F7 consume factory-status only. Bead prefix must be extracted at source (Go), not downstream (JS).

---

## Must-Haves

**Truths** (observable behaviors):
- `clavain-cli factory-status --json` WIP entries include a `"project"` field
- `import { generateSnapshot } from './index.js'` returns a snapshot with both layers
- `node cli.js` prints valid JSON to stdout
- `node cli.js --stream` emits one JSON line per 5s until SIGINT
- `node cli.js --factory-only` works without ideagui.json present
- Unmatched WIP beads are counted in meta, not silently dropped

**Artifacts** (files with specific exports):
- [`os/Clavain/cmd/clavain-cli/factory_status.go`] — modified: `wipEntry` has `Project` field
- [`apps/Meadowsyn/experiments/ideagui-pipe/index.js`] exports [`readRoster`, `readFactoryStatus`, `generateSnapshot`]
- [`apps/Meadowsyn/experiments/ideagui-pipe/cli.js`] — executable

---

### Task 1: Add project field to factory-status.go

**Files:**
- Modify: `os/Clavain/cmd/clavain-cli/factory_status.go`

**Step 1: Add Project field to wipEntry struct**

At line 41 (after `Agent`), add:
```go
Project string `json:"project"`
```

**Step 2: Set Project in gatherWIPBalance()**

At line 234 (the wipEntry literal), add:
```go
Project: strings.ToLower(strings.SplitN(b.ID, "-", 2)[0]),
```

Ensure `strings` is already imported (it is — used at line 226).

**Step 3: Verify**
Run: `clavain-cli factory-status --json | python3 -c "import json,sys; d=json.load(sys.stdin); [print(f'{w[\"bead_id\"]:20s} project:{w[\"project\"]}') for w in d['wip']]"`
Expected: Each WIP entry shows `project:demarch`, `project:iv`, etc.

**Step 4: Commit**
```bash
git add os/Clavain/cmd/clavain-cli/factory_status.go
git commit -m "feat(clavain-cli): add project field to factory-status WIP entries"
```

<verify>
- run: `clavain-cli factory-status --json | python3 -c "import json,sys; d=json.load(sys.stdin); assert all('project' in w for w in d['wip']), 'missing project field'; print('ok')"`
  expect: contains "ok"
</verify>

---

### Task 2: Scaffold module with roster reader

**Files:**
- Create: `apps/Meadowsyn/experiments/ideagui-pipe/package.json`
- Create: `apps/Meadowsyn/experiments/ideagui-pipe/index.js`
- Create: `apps/Meadowsyn/experiments/ideagui-pipe/index.test.js`

**Step 1: Create package.json**
```json
{
  "name": "@meadowsyn/ideagui-pipe",
  "version": "0.1.0",
  "type": "module",
  "exports": "./index.js",
  "bin": { "ideagui-pipe": "./cli.js" }
}
```

**Step 2: Write all tests upfront (consolidated imports)**
```js
// index.test.js
import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { execFileSync } from 'node:child_process';
import { writeFileSync, mkdtempSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { readRoster, readFactoryStatus, generateSnapshot } from './index.js';

// === Roster tests ===

test('readRoster parses valid ideagui.json', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'ideagui-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, 'ideagui.json');
  writeFileSync(path, JSON.stringify({
    meta: { total_sessions: 2 },
    summary: { by_project: { demo: 2 } },
    sessions: [
      { session: 'demo/main', project: 'demo', terminal: 'warp', agent: 'claude', domain: 'general', sync: 'bidirectional', pane: 'left' },
      { session: 'demo/sub', project: 'demo', terminal: 'rio', agent: 'codex', domain: 'aiml', sync: 'server-only', pane: 'right' },
    ],
  }));
  const result = readRoster(path);
  assert.equal(result.sessions.length, 2);
  assert.equal(result.meta.total_sessions, 2);
  assert.equal(result.sessions[0].project, 'demo');
});

test('readRoster throws on missing file', () => {
  assert.throws(() => readRoster('/tmp/nonexistent-ideagui.json'), /ENOENT/);
});

test('readRoster throws on malformed JSON', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'ideagui-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, 'ideagui.json');
  writeFileSync(path, 'not json');
  assert.throws(() => readRoster(path));
});

test('readRoster caches result by mtime', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'ideagui-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, 'ideagui.json');
  const data = { meta: { total_sessions: 1 }, summary: {}, sessions: [{ session: 'a', project: 'a', terminal: 'x', agent: 'claude', domain: 'g', sync: 'o', pane: null }] };
  writeFileSync(path, JSON.stringify(data));
  const r1 = readRoster(path);
  const r2 = readRoster(path);
  assert.equal(r1, r2, 'should return cached reference');
});

// === Factory-status tests (require clavain-cli) ===

const hasClavainCli = (() => {
  try { execFileSync('clavain-cli', ['--version'], { stdio: 'ignore' }); return true; }
  catch { return false; }
})();

test('readFactoryStatus returns parsed output with project field', { skip: !hasClavainCli }, () => {
  const result = readFactoryStatus();
  assert.ok(result.timestamp, 'has timestamp');
  assert.ok(result.fleet, 'has fleet');
  assert.ok(typeof result.fleet.total_agents === 'number');
  assert.ok(Array.isArray(result.wip));
  for (const w of result.wip) {
    assert.ok(typeof w.project === 'string', `WIP ${w.bead_id} has project field`);
  }
});

// === Integration test (require both sources) ===

test('generateSnapshot returns both layers with join metadata', { skip: !hasClavainCli }, () => {
  const snap = generateSnapshot();
  assert.ok(snap.roster.length > 0, 'has roster');
  assert.ok(snap.fleet.total_agents >= 0, 'has fleet');
  assert.ok(snap.timestamp, 'has timestamp');
  assert.ok(Object.keys(snap.by_project).length > 0, 'has by_project');
  assert.ok(typeof snap.meta.roster_total === 'number');
  assert.ok(typeof snap.meta.join_coverage === 'number');
  for (const s of snap.roster) {
    assert.ok(Array.isArray(s.active_beads), `${s.session} has active_beads`);
  }
});
```

**Step 3: Write index.js with readRoster (mtime-cached)**
```js
// index.js
import { readFileSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const IDEAGUI_PATH = process.env.IDEAGUI_PATH
  || '/home/mk/projects/transfer/ideagui/ideagui.json';

let _rosterCache = null;
let _rosterMtime = 0;

/**
 * Read IdeaGUI roster. Caches by file mtime.
 * @param {string} [path]
 * @returns {{ meta: object, summary: object, sessions: object[] }}
 */
export function readRoster(path = IDEAGUI_PATH) {
  const mtime = statSync(path).mtimeMs;
  if (_rosterCache && mtime === _rosterMtime && path === _rosterCache._path) {
    return _rosterCache;
  }
  const raw = readFileSync(path, 'utf-8');
  const data = JSON.parse(raw);
  if (!data.sessions || !Array.isArray(data.sessions)) {
    throw new Error('Invalid ideagui.json: missing sessions array');
  }
  data._path = path;
  _rosterCache = data;
  _rosterMtime = mtime;
  return data;
}
```

**Step 4: Run roster tests**
Run: `cd apps/Meadowsyn/experiments/ideagui-pipe && node --test index.test.js 2>&1 | head -20`
Expected: 4 roster tests pass, factory-status/integration tests skip or pass

**Step 5: Commit**
```bash
git add apps/Meadowsyn/experiments/ideagui-pipe/
git commit -m "feat(meadowsyn): scaffold ideagui-pipe with mtime-cached roster reader"
```

<verify>
- run: `cd apps/Meadowsyn/experiments/ideagui-pipe && node --test index.test.js 2>&1 | grep -E '(pass|fail|skip)'`
  expect: contains "pass"
</verify>

---

### Task 3: Factory-status reader and snapshot generator

**Files:**
- Modify: `apps/Meadowsyn/experiments/ideagui-pipe/index.js`

**Step 1: Add readFactoryStatus()**
```js
/**
 * Read live factory status from clavain-cli.
 * Uses execFileSync (no shell) to avoid command injection.
 */
export function readFactoryStatus() {
  const raw = execFileSync('clavain-cli', ['factory-status', '--json'], {
    encoding: 'utf-8',
    timeout: 10_000,
  });
  const data = JSON.parse(raw);
  if (!data.timestamp || !data.fleet) {
    throw new Error('Invalid factory-status: missing timestamp or fleet');
  }
  return data;
}
```

**Step 2: Add generateSnapshot()**
```js
/**
 * Generate a snapshot with both layers and project-level join.
 * @param {object} [options]
 * @param {string} [options.ideaguiPath] - Path to ideagui.json
 * @param {boolean} [options.factoryOnly] - Skip roster, emit ops only
 */
export function generateSnapshot({ ideaguiPath, factoryOnly = false } = {}) {
  const ops = readFactoryStatus();

  if (factoryOnly) {
    return {
      timestamp: ops.timestamp,
      fleet: ops.fleet,
      queue: ops.queue,
      wip: ops.wip,
      dispatches: ops.dispatches || [],
      watchdog: ops.watchdog,
      factory_paused: ops.factory_paused,
      roster: [],
      by_project: {},
      meta: { roster_total: 0, join_coverage: 0 },
    };
  }

  const roster = readRoster(ideaguiPath);

  // Index WIP by project (using factory-status project field)
  const wipByProject = new Map();
  for (const w of ops.wip) {
    const proj = w.project || '';
    if (!wipByProject.has(proj)) wipByProject.set(proj, []);
    wipByProject.get(proj).push(w);
  }

  // Enrich roster with active_beads (project-level, shared per project)
  const projectBeadArrays = new Map();
  const enrichedRoster = roster.sessions.map(s => {
    const key = s.project.toLowerCase();
    if (!projectBeadArrays.has(key)) {
      projectBeadArrays.set(key, wipByProject.get(key) || []);
    }
    return { ...s, active_beads: projectBeadArrays.get(key) };
  });

  // by_project rollup
  const byProject = {};
  for (const s of enrichedRoster) {
    const key = s.project.toLowerCase();
    if (!byProject[key]) {
      byProject[key] = {
        sessions: 0,
        active_beads: projectBeadArrays.get(key) || [],
        terminals: new Set(),
        agent_types: new Set(),
      };
    }
    byProject[key].sessions++;
    if (s.terminal) byProject[key].terminals.add(s.terminal);
    if (s.agent) byProject[key].agent_types.add(s.agent);
  }
  // Convert Sets to arrays
  for (const v of Object.values(byProject)) {
    v.terminals = [...v.terminals];
    v.agent_types = [...v.agent_types];
  }

  // Join coverage: % of WIP beads that matched a roster project
  const matchedCount = ops.wip.filter(w => {
    const proj = (w.project || '').toLowerCase();
    return roster.sessions.some(s => s.project.toLowerCase() === proj);
  }).length;
  const joinCoverage = ops.wip.length > 0 ? matchedCount / ops.wip.length : 1;

  return {
    timestamp: ops.timestamp,
    fleet: ops.fleet,
    queue: ops.queue,
    wip: ops.wip,
    dispatches: ops.dispatches || [],
    watchdog: ops.watchdog,
    factory_paused: ops.factory_paused,
    roster: enrichedRoster,
    by_project: byProject,
    meta: {
      roster_total: roster.sessions.length,
      join_coverage: Math.round(joinCoverage * 100),
    },
  };
}
```

**Step 3: Run all tests**
Run: `cd apps/Meadowsyn/experiments/ideagui-pipe && node --test index.test.js`
Expected: All tests pass (factory-status tests pass if clavain-cli available, skip otherwise)

**Step 4: Commit**
```bash
git add apps/Meadowsyn/experiments/ideagui-pipe/index.js
git commit -m "feat(meadowsyn): add factory-status reader and snapshot generator with project-level join"
```

<verify>
- run: `cd apps/Meadowsyn/experiments/ideagui-pipe && node --test index.test.js 2>&1 | grep -cE '# (pass|skip)'`
  expect: exit 0
</verify>

---

### Task 4: CLI with --stream and --factory-only

**Files:**
- Create: `apps/Meadowsyn/experiments/ideagui-pipe/cli.js`

**Step 1: Write cli.js**
```js
#!/usr/bin/env node
import { generateSnapshot } from './index.js';

const args = process.argv.slice(2);
const streamMode = args.includes('--stream');
const factoryOnly = args.includes('--factory-only');
const intervalIdx = args.indexOf('--interval');
const rawInterval = intervalIdx !== -1 ? parseInt(args[intervalIdx + 1], 10) : 5;
const interval = Number.isFinite(rawInterval) ? Math.max(1, rawInterval) : 5;
const pathIdx = args.indexOf('--ideagui-path');
const ideaguiPath = pathIdx !== -1 ? args[pathIdx + 1] : undefined;

function emit() {
  try {
    const snapshot = generateSnapshot({ ideaguiPath, factoryOnly });
    process.stdout.write(JSON.stringify(snapshot) + '\n');
  } catch (err) {
    if (!streamMode) throw err;
    process.stderr.write(`[ideagui-pipe] ${err.message}\n`);
  }
}

if (streamMode) {
  emit();
  const timer = setInterval(emit, interval * 1000);
  const shutdown = () => { clearInterval(timer); process.exit(0); };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
} else {
  emit();
}
```

**Step 2: Make executable and test**
```bash
chmod +x apps/Meadowsyn/experiments/ideagui-pipe/cli.js
```

Run: `node apps/Meadowsyn/experiments/ideagui-pipe/cli.js | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'roster:{len(d[\"roster\"])} coverage:{d[\"meta\"][\"join_coverage\"]}%')"`
Expected: `roster:85 coverage:NN%` (coverage varies by active WIP)

Run: `node apps/Meadowsyn/experiments/ideagui-pipe/cli.js --factory-only | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'roster:{len(d[\"roster\"])} fleet:{d[\"fleet\"][\"total_agents\"]}')"`
Expected: `roster:0 fleet:60` (roster empty in factory-only mode)

**Step 3: Commit**
```bash
git add apps/Meadowsyn/experiments/ideagui-pipe/cli.js
git commit -m "feat(meadowsyn): add CLI with --stream and --factory-only modes"
```

<verify>
- run: `node apps/Meadowsyn/experiments/ideagui-pipe/cli.js --factory-only | python3 -c "import json,sys; d=json.load(sys.stdin); print('ok' if d['meta']['roster_total']==0 and 'fleet' in d else 'fail')"`
  expect: contains "ok"
</verify>
