---
artifact_type: plan
bead: Sylveste-4wm
stage: design
requirements:
  - F1: Handoff note writer (PreCompact hook in agent-runner)
  - F2: Handoff note reader (session startup prompt injection)
  - F3: Ambient state reconstructor (crash fallback)
  - F4: Protocol extension (ContainerInput.previousContext)
---
# Conversation Resumption Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-4wm
**Goal:** Enable intercom container agents to resume conversations with structured context after session resets.

**Architecture:** The agent writes a `handoff.json` file during PreCompact (context overflow). On next session startup, agent-runner reads the handoff note and prepends it to the system prompt. If no handoff exists (crash), context is reconstructed from ambient state (beads, git, conversation archives). The Rust host also gets an optional `previousContext` field for future host-side reconstruction.

**Tech Stack:** TypeScript (agent-runner), Rust (intercomd), Claude Agent SDK

**Prior Learnings:**
- `docs/solutions/patterns/cross-hook-marker-file-coordination-20260308.md` — marker files must be consumed one-shot and TTL-cleaned; `additionalContext` on SessionStart is preferred for Claude Code but not applicable inside containers
- `docs/solutions/patterns/token-accounting-billing-vs-context-20260216.md` — effective context includes cache hits; use character count ÷4 for approximate token budgeting

**Review Findings Applied:** Plan updated after flux-drive review (correctness, quality, safety). Key fixes: one-shot consumption of handoff.json, correct import path, strict version check, newline sanitization in formatted output, `preCompact.session_id` over closure variable, `resumeContext` reset after first query, reader-side schema validation.

---

## Must-Haves

**Truths** (observable behaviors):
- When a container session overflows (>512 KiB), the next session receives a "Previous Session Context" block in its system prompt
- When a container crashes without writing a handoff note, the next session still receives ambient context (active beads, changed files)
- The handoff note is ≤500 tokens (~2000 chars) and follows a fixed schema
- Existing containers without `previousContext` continue to work (backward-compatible)

**Artifacts** (files with specific exports):
- `apps/intercom/container/agent-runner/src/index.ts` exports `writeHandoffNote`, `readHandoffNote`, `reconstructAmbientContext`, `formatResumeContext`
- `apps/intercom/container/shared/protocol.ts` exports `ContainerInput` with `previousContext?: string`
- `apps/intercom/rust/intercom-core/src/container.rs` exports `ContainerInput` with `previous_context: Option<String>`

**Key Links:**
- PreCompact hook calls `writeHandoffNote()` before returning `{}`
- `main()` calls `readHandoffNote()` || `reconstructAmbientContext()` before first `runQuery()`
- `runQuery()` appends the resume context to `globalClaudeMd` for the `systemPrompt.append` field

---

### Task 1: Add `previousContext` to ContainerInput protocol (F4)

**Files:**
- Modify: `apps/intercom/container/shared/protocol.ts:12-22`
- Modify: `apps/intercom/rust/intercom-core/src/container.rs:22-39`
- Modify: `apps/intercom/rust/intercomd/src/process_group.rs:209-219`

**Step 1: Add field to TypeScript interface**

In `apps/intercom/container/shared/protocol.ts`, add `previousContext` to `ContainerInput`:

```typescript
export interface ContainerInput {
  prompt: string;
  sessionId?: string;
  groupFolder: string;
  chatJid: string;
  isMain: boolean;
  isScheduledTask?: boolean;
  assistantName?: string;
  model?: string;
  secrets?: Record<string, string>;
  previousContext?: string;  // <-- add this
}
```

**Step 2: Add field to Rust struct**

In `apps/intercom/rust/intercom-core/src/container.rs`, add `previous_context` after `secrets`:

```rust
    #[serde(skip_serializing_if = "Option::is_none")]
    pub secrets: Option<HashMap<String, String>>,
    /// Optional context from previous session, injected by host.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub previous_context: Option<String>,
}
```

**Step 3: Set field to None in process_group.rs**

In `apps/intercom/rust/intercomd/src/process_group.rs`, add `previous_context: None` to the `ContainerInput` construction at line 219:

```rust
    let input = ContainerInput {
        prompt,
        session_id,
        group_folder: group.folder.clone(),
        chat_jid: chat_jid.to_string(),
        is_main,
        is_scheduled_task: None,
        assistant_name: Some(assistant_name.to_string()),
        model: group.model.clone(),
        secrets: None,
        previous_context: None,  // <-- add this
    };
```

**Step 4: Update existing Rust tests**

Any existing test that constructs `ContainerInput` via struct literal will fail to compile without the new field. Search for `ContainerInput {` in the Rust codebase and add `previous_context: None` to each construction site. The main one is the `container_input_serializes_camel_case` test in `container.rs`.

**Step 5: Build and verify**

Run: `cd apps/intercom && npm run rust:build:release 2>&1 | tail -5`
Expected: Build succeeds with no errors (including tests).

**Step 6: Commit**

```bash
git add apps/intercom/container/shared/protocol.ts apps/intercom/rust/intercom-core/src/container.rs apps/intercom/rust/intercomd/src/process_group.rs
git commit -m "feat(intercom): add previousContext field to ContainerInput protocol"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/intercom && npm run rust:build:release 2>&1 | tail -3`
  expect: exit 0
- run: `grep -c 'previousContext' /home/mk/projects/Sylveste/apps/intercom/container/shared/protocol.ts`
  expect: contains "1"
- run: `grep -c 'previous_context' /home/mk/projects/Sylveste/apps/intercom/rust/intercom-core/src/container.rs`
  expect: contains "2"
</verify>

---

### Task 2: Write handoff note schema and helpers (F1, F2, F3)

**Files:**
- Create: `apps/intercom/container/agent-runner/src/handoff.ts`
- Test: `apps/intercom/container/agent-runner/src/handoff.test.ts`

**Step 1: Write the failing tests**

Create `apps/intercom/container/agent-runner/src/handoff.test.ts`:

```typescript
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import fs from 'fs';
import path from 'path';
import os from 'os';
import {
  writeHandoffNote,
  readHandoffNote,
  reconstructAmbientContext,
  formatResumeContext,
  HandoffNote,
  HANDOFF_MAX_CHARS,
} from './handoff.js';

describe('handoff', () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'handoff-test-'));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  describe('writeHandoffNote', () => {
    it('writes valid handoff.json atomically', () => {
      const note: HandoffNote = {
        version: 1,
        created_at: new Date().toISOString(),
        source: 'agent',
        session_id: 'test-session',
        task: { summary: 'Testing handoff' },
        decisions: ['Decision 1'],
        pending: ['Next step 1'],
        gotchas: ['Watch out for X'],
      };
      writeHandoffNote(tmpDir, note);

      const written = JSON.parse(fs.readFileSync(path.join(tmpDir, 'handoff.json'), 'utf-8'));
      expect(written.version).toBe(1);
      expect(written.source).toBe('agent');
      expect(written.task.summary).toBe('Testing handoff');
    });

    it('truncates oversized notes', () => {
      const note: HandoffNote = {
        version: 1,
        created_at: new Date().toISOString(),
        source: 'agent',
        session_id: 'test-session',
        task: { summary: 'Testing' },
        decisions: Array.from({ length: 50 }, (_, i) => `Decision ${i}: ${'x'.repeat(100)}`),
        pending: ['Step 1'],
        gotchas: [],
      };
      writeHandoffNote(tmpDir, note);

      const content = fs.readFileSync(path.join(tmpDir, 'handoff.json'), 'utf-8');
      expect(content.length).toBeLessThanOrEqual(HANDOFF_MAX_CHARS);
    });
  });

  describe('readHandoffNote', () => {
    it('returns parsed note when file exists', () => {
      const note: HandoffNote = {
        version: 1,
        created_at: new Date().toISOString(),
        source: 'agent',
        session_id: 'test-session',
        task: { summary: 'Testing' },
        decisions: [],
        pending: [],
        gotchas: [],
      };
      fs.writeFileSync(path.join(tmpDir, 'handoff.json'), JSON.stringify(note));

      const result = readHandoffNote(tmpDir);
      expect(result).not.toBeNull();
      expect(result!.task.summary).toBe('Testing');
    });

    it('consumes file after successful read (one-shot)', () => {
      const note: HandoffNote = {
        version: 1,
        created_at: new Date().toISOString(),
        source: 'agent',
        session_id: 'test-session',
        task: { summary: 'Testing' },
        decisions: [],
        pending: [],
        gotchas: [],
      };
      fs.writeFileSync(path.join(tmpDir, 'handoff.json'), JSON.stringify(note));

      readHandoffNote(tmpDir);
      // File should be renamed to .consumed
      expect(fs.existsSync(path.join(tmpDir, 'handoff.json'))).toBe(false);
      expect(fs.existsSync(path.join(tmpDir, 'handoff.json.consumed'))).toBe(true);
      // Second read returns null
      expect(readHandoffNote(tmpDir)).toBeNull();
    });

    it('returns null when file is missing', () => {
      expect(readHandoffNote(tmpDir)).toBeNull();
    });

    it('returns null for malformed JSON', () => {
      fs.writeFileSync(path.join(tmpDir, 'handoff.json'), '{bad json');
      expect(readHandoffNote(tmpDir)).toBeNull();
    });

    it('returns null for wrong version', () => {
      fs.writeFileSync(path.join(tmpDir, 'handoff.json'), JSON.stringify({
        version: 2, task: { summary: 'test' }, decisions: [], pending: [], gotchas: [],
      }));
      expect(readHandoffNote(tmpDir)).toBeNull();
    });

    it('returns null when decisions is not an array', () => {
      fs.writeFileSync(path.join(tmpDir, 'handoff.json'), JSON.stringify({
        version: 1, task: { summary: 'test' }, decisions: 'not array', pending: [], gotchas: [],
      }));
      expect(readHandoffNote(tmpDir)).toBeNull();
    });
  });

  describe('reconstructAmbientContext', () => {
    it('builds context from conversations directory', () => {
      const convDir = path.join(tmpDir, 'conversations');
      fs.mkdirSync(convDir);
      fs.writeFileSync(path.join(convDir, '2026-03-10-debugging-auth.md'), 'test');

      const ctx = reconstructAmbientContext(tmpDir);
      expect(ctx).toContain('debugging-auth');
    });

    it('returns minimal context when nothing is available', () => {
      const ctx = reconstructAmbientContext(tmpDir);
      expect(ctx).toContain('reconstructed');
    });
  });

  describe('formatResumeContext', () => {
    it('formats agent-authored note as markdown', () => {
      const note: HandoffNote = {
        version: 1,
        created_at: '2026-03-10T14:30:00Z',
        source: 'agent',
        session_id: 'abc',
        task: { bead_id: 'Sylveste-4wm', summary: 'Building resumption' },
        decisions: ['Use system prompt prepend'],
        pending: ['Implement F2'],
        gotchas: ['Avoid full replay'],
      };
      const result = formatResumeContext(note);
      expect(result).toContain('Previous Session Context');
      expect(result).toContain('Building resumption');
      expect(result).toContain('Use system prompt prepend');
      expect(result).toContain('Implement F2');
      expect(result).toContain('Avoid full replay');
    });
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `cd apps/intercom/container/agent-runner && npx vitest run src/handoff.test.ts 2>&1 | tail -10`
Expected: FAIL — module `./handoff.js` not found.

**Step 3: Implement handoff.ts**

Create `apps/intercom/container/agent-runner/src/handoff.ts`:

```typescript
import fs from 'fs';
import path from 'path';
import { log } from '../../shared/protocol.js';

export const HANDOFF_MAX_CHARS = 2000; // ~500 tokens
const MAX_ELEMENT_LENGTH = 300;
const MAX_TOPIC_LENGTH = 100;

export interface HandoffNote {
  version: 1;
  created_at: string;
  source: 'agent' | 'reconstructed';
  session_id: string;
  task: {
    bead_id?: string;
    summary: string;
  };
  decisions: string[];
  pending: string[];
  gotchas: string[];
}

/** Sanitize a string for safe markdown list rendering. */
function sanitize(s: string): string {
  return s.replace(/[\n\r`]/g, ' ').slice(0, MAX_ELEMENT_LENGTH);
}

/**
 * Write a handoff note atomically to the group directory.
 * Truncates oversized notes by removing oldest decisions first.
 */
export function writeHandoffNote(groupDir: string, note: HandoffNote): void {
  const truncated = truncateNote(note);
  const json = JSON.stringify(truncated, null, 2);
  const filePath = path.join(groupDir, 'handoff.json');
  const tmpPath = `${filePath}.tmp`;

  fs.writeFileSync(tmpPath, json, 'utf-8');
  fs.renameSync(tmpPath, filePath);
}

/**
 * Read a handoff note from the group directory.
 * Consumes the file after successful read (renames to .consumed) to prevent
 * stale replay on subsequent restarts without an intervening PreCompact.
 * Returns null if file doesn't exist, is malformed, or has wrong version.
 */
export function readHandoffNote(groupDir: string): HandoffNote | null {
  const filePath = path.join(groupDir, 'handoff.json');
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    const parsed = JSON.parse(content);

    // Strict schema validation
    if (parsed.version !== 1) return null;
    if (!parsed.task || typeof parsed.task.summary !== 'string') return null;
    if (!Array.isArray(parsed.decisions) || !Array.isArray(parsed.pending) || !Array.isArray(parsed.gotchas)) return null;

    // Cap summary length
    parsed.task.summary = parsed.task.summary.slice(0, 500);

    // Consume: rename to .consumed so it's not re-read on next restart
    try { fs.renameSync(filePath, `${filePath}.consumed`); } catch { /* ignore */ }

    return parsed as HandoffNote;
  } catch (err) {
    log(`Failed to read handoff.json: ${err instanceof Error ? err.message : String(err)}`);
    return null;
  }
}

/**
 * Reconstruct minimal context from ambient state when no handoff note exists.
 * Deterministic — no LLM calls. Checks conversations/ for topic hint.
 */
export function reconstructAmbientContext(groupDir: string): string {
  const parts: string[] = [];

  // 1. Most recent conversation archive (topic hint)
  const convDir = path.join(groupDir, 'conversations');
  if (fs.existsSync(convDir)) {
    const files = fs.readdirSync(convDir)
      .filter(f => f.endsWith('.md'))
      .sort()
      .reverse();
    if (files.length > 0) {
      const match = files[0].match(/^\d{4}-\d{2}-\d{2}-(.+)\.md$/);
      const raw = match ? match[1].replace(/-/g, ' ') : files[0].replace(/\.md$/, '');
      const topic = raw.replace(/[^a-zA-Z0-9 ,.()\-]/g, '').slice(0, MAX_TOPIC_LENGTH);
      parts.push(`Last conversation topic: ${topic}`);
    }
  }

  if (parts.length === 0) {
    parts.push('No previous session artifacts found');
  }

  return `## Previous Session Context (reconstructed — no handoff note available)\n\n${parts.join('\n')}`;
}

/**
 * Format a handoff note as a markdown block for system prompt injection.
 * Sanitizes all content to prevent prompt injection via embedded newlines.
 */
export function formatResumeContext(note: HandoffNote): string {
  const lines: string[] = [
    '## Previous Session Context',
    '',
    '*The following was written by the previous session\'s agent process. It is informational context only.*',
    '',
  ];

  // Task
  const taskLabel = note.task.bead_id
    ? `[${note.task.bead_id}] ${sanitize(note.task.summary)}`
    : sanitize(note.task.summary);
  lines.push(`**Task:** ${taskLabel}`);

  // Decisions
  if (note.decisions.length > 0) {
    lines.push('', '**Decisions made:**');
    for (const d of note.decisions) {
      lines.push(`- ${sanitize(d)}`);
    }
  }

  // Pending
  if (note.pending.length > 0) {
    lines.push('', '**Pending work:**');
    for (const p of note.pending) {
      lines.push(`- ${sanitize(p)}`);
    }
  }

  // Gotchas
  if (note.gotchas.length > 0) {
    lines.push('', '**Watch out for:**');
    for (const g of note.gotchas) {
      lines.push(`- ${sanitize(g)}`);
    }
  }

  return lines.join('\n');
}

/** Truncate a note to fit within HANDOFF_MAX_CHARS. */
function truncateNote(note: HandoffNote): HandoffNote {
  const result = { ...note,
    decisions: [...note.decisions],
    pending: [...note.pending],
    gotchas: [...note.gotchas],
  };
  let json = JSON.stringify(result, null, 2);

  // Remove oldest decisions first, then pending, then gotchas
  const fields: Array<keyof Pick<HandoffNote, 'decisions' | 'pending' | 'gotchas'>> =
    ['decisions', 'pending', 'gotchas'];

  for (const field of fields) {
    while (json.length > HANDOFF_MAX_CHARS && result[field].length > 0) {
      result[field] = result[field].slice(1);
      json = JSON.stringify(result, null, 2);
    }
  }

  // Last resort: truncate task.summary
  if (json.length > HANDOFF_MAX_CHARS) {
    const budget = Math.max(50, HANDOFF_MAX_CHARS - (json.length - result.task.summary.length));
    result.task = { ...result.task, summary: result.task.summary.slice(0, budget) };
  }

  return result;
}
```

**Step 4: Run tests to verify they pass**

Run: `cd apps/intercom/container/agent-runner && npx vitest run src/handoff.test.ts 2>&1 | tail -10`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add apps/intercom/container/agent-runner/src/handoff.ts apps/intercom/container/agent-runner/src/handoff.test.ts
git commit -m "feat(intercom): add handoff note schema, writer, reader, and reconstructor"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/intercom/container/agent-runner && npx vitest run src/handoff.test.ts 2>&1 | tail -5`
  expect: exit 0
</verify>

---

### Task 3: Wire PreCompact hook to write handoff note (F1)

**Files:**
- Modify: `apps/intercom/container/agent-runner/src/index.ts:127-167`

**Step 1: Import handoff helpers**

At the top of `index.ts`, add:

```typescript
import { writeHandoffNote, HandoffNote } from './handoff.js';
```

**Step 2: Extend PreCompact hook to write handoff note**

In `createPreCompactHook()`, after the transcript archive (after line 160 `log('Archived conversation...')`), add handoff note writing. The hook receives the transcript which we can use to extract a summary:

```typescript
    // Write handoff note for session resumption
    try {
      const handoffNote: HandoffNote = {
        version: 1,
        created_at: new Date().toISOString(),
        source: 'agent',
        session_id: preCompact.session_id || 'unknown',
        task: {
          summary: summary || 'Session compacted — no summary available',
        },
        decisions: [],
        pending: [],
        gotchas: [],
      };

      // Extract last few assistant messages as context
      const assistantMessages = messages
        .filter(m => m.role === 'assistant')
        .slice(-3)
        .map(m => {
          const text = typeof m.content === 'string' ? m.content : '';
          return text.slice(0, 200);
        })
        .filter(t => t.length > 0);

      if (assistantMessages.length > 0) {
        handoffNote.pending = [`Recent context: ${assistantMessages[assistantMessages.length - 1]}`];
      }

      writeHandoffNote('/workspace/group', handoffNote);
      log('Wrote handoff note for session resumption');
    } catch (handoffErr) {
      log(`Failed to write handoff note: ${handoffErr instanceof Error ? handoffErr.message : String(handoffErr)}`);
    }
```

**Step 3: Verify build**

Run: `cd apps/intercom/container && bash build.sh latest claude 2>&1 | tail -5`
Expected: Container builds successfully.

**Step 4: Commit**

```bash
git add apps/intercom/container/agent-runner/src/index.ts
git commit -m "feat(intercom): write handoff note in PreCompact hook"
```

<verify>
- run: `grep -c 'writeHandoffNote' /home/mk/projects/Sylveste/apps/intercom/container/agent-runner/src/index.ts`
  expect: contains "1"
- run: `grep -c 'import.*handoff' /home/mk/projects/Sylveste/apps/intercom/container/agent-runner/src/index.ts`
  expect: contains "1"
</verify>

---

### Task 4: Wire session startup to read handoff note and inject context (F2, F3)

**Files:**
- Modify: `apps/intercom/container/agent-runner/src/index.ts:537-566` (main function, prompt construction)
- Modify: `apps/intercom/container/agent-runner/src/index.ts:381-414` (runQuery, system prompt)

**Step 1: Import additional handoff helpers**

Update the import in `index.ts`:

```typescript
import { writeHandoffNote, readHandoffNote, reconstructAmbientContext, formatResumeContext, HandoffNote } from './handoff.js';
```

**Step 2: Read handoff context in main() before first query**

In `main()`, after the prompt construction block (after line 555 `prompt += '\n' + pending.join('\n');`) and before line 558 (`writeOutput`), add:

```typescript
  // Read previous session context for resumption.
  // Gate on handoff note existence, not sessionId — a host-resumed session
  // (with sessionId set) still needs context about what the previous session decided.
  let resumeContext: string | undefined;
  if (containerInput.previousContext) {
    // Host-provided context takes priority
    resumeContext = containerInput.previousContext;
    log('Using host-provided previousContext');
  } else {
    const handoff = readHandoffNote('/workspace/group');
    if (handoff) {
      resumeContext = formatResumeContext(handoff);
      log('Using handoff note for session resumption');
    } else if (!sessionId) {
      // Only reconstruct from ambient state for truly new sessions (no SDK resume).
      // Resumed sessions already have conversation history.
      resumeContext = reconstructAmbientContext('/workspace/group');
      log('Using reconstructed ambient context (no handoff note)');
    }
  }
```

**Step 3: Pass resume context to runQuery**

Add `resumeContext` as a parameter to `runQuery()`. In the function signature (around line 370), add it:

```typescript
async function runQuery(
  prompt: string | AsyncIterable<string>,
  sessionId: string | undefined,
  mcpServerPath: string,
  containerInput: ContainerInput,
  sdkEnv: Record<string, string>,
  resumeAt?: string,
  resumeContext?: string,  // <-- add this
): Promise<QueryResult> {
```

Update the call site at line 566. Pass `resumeContext` and then reset it to `undefined` so it's only injected on the first query:

```typescript
      const queryResult = await runQuery(prompt, sessionId, mcpServerPath, containerInput, sdkEnv, resumeAt, resumeContext);
      resumeContext = undefined; // consumed — only inject on the first query
```

**Step 4: Inject resume context into system prompt**

In `runQuery()`, modify the system prompt construction (lines 381-414). After loading `globalClaudeMd` (line 386), append the resume context:

```typescript
  // Append resume context from previous session
  if (resumeContext) {
    globalClaudeMd = globalClaudeMd
      ? `${globalClaudeMd}\n\n${resumeContext}`
      : resumeContext;
  }
```

This ensures the resume context appears in the system prompt after CLAUDE.md but as part of the same `append` block. For `isMain` groups (where `globalClaudeMd` was undefined), it creates a new append block with just the resume context.

**Step 5: Verify build**

Run: `cd apps/intercom/container && bash build.sh latest claude 2>&1 | tail -5`
Expected: Container builds successfully.

**Step 6: Commit**

```bash
git add apps/intercom/container/agent-runner/src/index.ts
git commit -m "feat(intercom): read handoff note on startup, inject into system prompt"
```

<verify>
- run: `grep -c 'readHandoffNote' /home/mk/projects/Sylveste/apps/intercom/container/agent-runner/src/index.ts`
  expect: contains "1"
- run: `grep -c 'reconstructAmbientContext' /home/mk/projects/Sylveste/apps/intercom/container/agent-runner/src/index.ts`
  expect: contains "1"
- run: `grep -c 'resumeContext' /home/mk/projects/Sylveste/apps/intercom/container/agent-runner/src/index.ts`
  expect: contains "4"
</verify>

---

### Task 5: Rust build verification and integration test

**Files:**
- Test: `apps/intercom/rust/intercomd/src/process_group.rs` (build verification)

**Step 1: Build the full Rust crate**

Run: `cd apps/intercom && npm run rust:build:release 2>&1 | tail -5`
Expected: Build succeeds — the new `previous_context` field is properly handled by serde.

**Step 2: Run existing Rust tests**

Run: `cd apps/intercom && npm run rust:test 2>&1 | tail -20`
Expected: All existing tests pass. The new field is `Option<String>` with `skip_serializing_if`, so it's backward-compatible — existing tests that construct `ContainerInput` without `previous_context` will use `Default` (None).

**Step 3: Verify JSON serialization round-trip**

Run: `cd apps/intercom/rust && cargo test --lib -- container 2>&1 | tail -10`
Expected: PASS — serde correctly handles the new field as `previousContext` in JSON (camelCase) and `previous_context` in Rust (snake_case).

Note: If no existing test covers the new field's round-trip, add assertions to the existing `container_input_serializes_camel_case` test:
1. When `previous_context: None`, serialized JSON must NOT contain `"previousContext"`.
2. When `previous_context: Some("ctx".into())`, serialized JSON must contain `"previousContext":"ctx"`.
3. A JSON payload with `"previousContext":"test"` must deserialize to `previous_context: Some("test".into())`.

**Step 4: Build container image**

Run: `cd apps/intercom/container && bash build.sh latest claude 2>&1 | tail -5`
Expected: Container image builds successfully with the new handoff.ts module.

**Step 5: Commit (if any fixes were needed)**

Only commit if fixes were required. Otherwise, all code is already committed from previous tasks.

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/intercom && npm run rust:build:release 2>&1 | tail -3`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/apps/intercom && npm run rust:test 2>&1 | tail -3`
  expect: exit 0
</verify>
