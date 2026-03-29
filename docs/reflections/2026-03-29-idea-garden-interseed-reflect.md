---
artifact_type: reflection
bead: sylveste-e8n
stage: reflect
---

# Reflect: Idea Garden — interseed Plugin

## What Worked

- **Capture/enrich split** was the single most impactful architectural change from the plan review. Decoupling the fast DB write from the async Claude call means any surface (Telegram, MCP, CLI) gets sub-second response. This pattern should be reused in any plugin that sits on an interactive path.

- **Advisory locking via locked_at** is a lightweight alternative to file locks or process-level mutexes for SQLite-backed CLI tools. The 10-minute staleness threshold handles crash recovery without coordination.

- **Context hash idempotency** (SHA256 of gathered context) is more reliable than timestamp comparison across filesystems. The correctness review caught a real bug: mtime vs DB clock divergence would have caused missed enrichment signals.

- **4-agent plan review** caught 19 issues before a single line was written. The most valuable were: (1) synchronous LLM on Telegram path, (2) direct interject DB access bypassing MCP, (3) graduation atomicity gap. All three would have been hard to fix post-implementation.

## What to Improve

- **Garden Salon bridge deferred.** The cross-language TypeScript bridge adds real complexity. The right move is to wait for salon-core to expose an HTTP API rather than maintaining a Node.js shim inside a Python plugin.

- **Auraken /idea command** is separate-repo work and should be a follow-up bead. The interseed CLI contract (`plant --source auraken --json`) is stable and documented.

- **Confidence scoring** is opaque. The raw float from Claude is logged but not yet translated to human-readable status. The calibration loop (stage 3 of closed-loop pattern) is not yet implemented.

## Lessons

1. Always decouple capture from enrichment in user-facing flows
2. Use published APIs (MCP/CLI) to query other plugins, never direct DB file access
3. The PENDING sentinel pattern handles crash-safety for cross-system writes without 2PC
4. Plan reviews that run before implementation are dramatically more cost-effective than post-implementation code reviews
