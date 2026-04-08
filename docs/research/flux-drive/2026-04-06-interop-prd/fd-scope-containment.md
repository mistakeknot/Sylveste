### Findings Index
- P1 | SC-01 | "F3 — GitHub Adapter" | "Repo files: bidirectional sync of markdown files with Notion pages" pulls in two distinct sync axes (GitHub↔FS and FS↔Notion) that each require F5 and F4 to be complete — hidden cross-feature dependency
- P1 | SC-02 | "F7 — Migration" | F7 implicitly requires F2+F3+F4+F5 to be functionally complete before migration can be verified — listed last but architecturally must follow all adapters
- P2 | SC-03 | "F6 — MCP Server + Claude Code Plugin" | F6 bundles two distinct deliverables: MCP server (infra) and Claude Code plugin (UX) — different owners, different test surfaces, different failure modes
- P2 | SC-04 | "F4 — Notion Adapter" | "Port interkasten's Notion sync into Go adapter" implies porting 27 MCP handlers — actual porting scope is unstated; could be 1 week or 6 weeks
- P2 | SC-05 | "Architecture — EventBus" | Three-lane priority dispatch (express/urgent/routine) is an architectural commitment in F1 but has no acceptance criterion — implicit scope added to F1
- P2 | SC-06 | "F3 — GitHub" | GitHub App creation (App registration, webhook secret, app ID, private key) is listed as a dependency but creating/configuring the App itself is scope that has no feature or acceptance criterion
- P3 | SC-07 | "Non-goals" | Auraken adapter correctly excluded as day-2, but "interop can consume those via Intercore events later" implies an Intercore integration API that doesn't yet exist — future scope bleeds into present architecture
- P3 | SC-08 | "Open Questions #3" | Conflict resolution web UI deferred but "MCP tools suffice for agent-driven resolution" is an assumption about usage pattern that should be validated before F6 is finalized

Verdict: needs-attention

## Summary

The PRD is well-bounded at the macro level — Google Drive, Auraken, and real-time editing are correctly excluded as day-2. The scope containment issues are at the feature level: F3's "repo files bidirectional sync" is a silent 2-feature requirement (it needs F4 and F5 both complete), F7's position in the list implies it can be built in parallel with adapters but it can only be verified after all adapters work, and F6 bundles two deliverables with different risk profiles into a single feature that could stall on either independently. The most concrete risk is F4's unstated porting scope — "port 27 MCP handlers" could be a month of work hidden behind one bullet point.

## Issues Found

### P1 | SC-01 — F3 "repo files" sync requires F4 and F5 both complete

**Location**: PRD § F3, criterion 3: "Repo files: bidirectional sync of markdown files with Notion pages"

**Problem**: This criterion bridges GitHub ↔ local FS ↔ Notion. It requires F5 (fsnotify file watcher) to detect local file changes and F4 (Notion adapter) to push them to Notion pages. If F3 is developed before F4 and F5 are complete, this criterion cannot be verified — but the PRD lists F3 before F4 and F5 with no explicit ordering constraint. A team working features in document order will reach F3's criterion 3 and find it unimplementable until F4 and F5 are done.

**Failure scenario**: F3 is handed to a developer who implements GitHub webhook ingestion and issue sync (criteria 1, 2, 4, 5, 6, 7 — all verifiable without F4/F5), but criterion 3 ("repo files → Notion pages") blocks on F4 not being done. The criterion either gets marked incomplete (blocking F3 closure) or marked complete against a stub that doesn't actually route through F4 and F5.

**Fix**: Add explicit ordering note to F3: "Criterion 3 (repo files sync) requires F4 Notion adapter and F5 filesystem adapter to be functionally complete. F3 criteria 1, 2, 4-7 can be verified independently. F3 is fully closeable only after F4 and F5 are closed."

---

### P1 | SC-02 — F7 position implies parallelizability with adapters, but it requires all adapters complete

**Location**: PRD § F7 — listed after F6 with no prerequisite statement

**Problem**: F7 ("migrate interkasten's sync state into interop") requires interop's SyncJournal and AncestorStore (F1) and all four adapters (F2-F5) to be functionally complete before migration can be performed and verified. The PRD lists F7 after F6 but does not state this dependency explicitly. A team that starts F7 in parallel with F2-F5 will produce a migration tool that cannot be verified until all adapters are done, and the F7 verification criteria (criterion 4: "all tracked entities present in interop") requires all adapters to be running.

**Fix**: Add to F7: "Prerequisites: F1-F5 complete. F7 cannot be verified until all adapters are running and can receive migrated state. F6 (MCP) is not required."

---

### P2 | SC-03 — F6 bundles MCP server and Claude Code plugin

**Location**: PRD § F6: "MCP Server + Claude Code Plugin"

**Problem**: The MCP server (Go HTTP server exposing tools) and the Claude Code plugin (`.claude-plugin/plugin.json`, skills, commands) are distinct deliverables. The MCP server is infrastructure with API contracts. The Claude Code plugin is a UX layer with discovery and collision constraints (documented in Sylveste's CLAUDE.md plugin collision rules). They can fail independently: the MCP server can be complete while the plugin fails to load due to a naming collision, or vice versa.

**Risk**: If F6 is blocked by a plugin naming collision (easy to hit given the monorepo autodiscovery noted in CLAUDE.md), the MCP server's acceptance criteria are also blocked, even though the server itself is complete.

**Fix**: Split F6 into F6a (MCP Server) and F6b (Claude Code Plugin), each with independent acceptance criteria and closure conditions. F6b depends on F6a.

---

### P2 | SC-04 — F4 Notion porting scope is unstated

**Location**: PRD § F4: "Port interkasten's Notion sync into Go adapter"

**Problem**: The PRD's Problem section notes "interkasten owns Notion sync (TypeScript, 27 MCP handlers)". Porting 27 handlers to Go is significant scope. The F4 acceptance criteria do not specify which handlers are in scope for day-1. If the assumption is "all 27", F4 is the largest single feature in the PRD. If the assumption is "the subset needed for pages↔markdown and databases↔beads", the scope is much smaller — but that subset is not defined.

**Failure scenario**: F4 is estimated as 2 weeks. The actual scope is 6 weeks because "port interkasten" was interpreted as "port all 27 handlers." The feature misses the sprint. F7 (migration) is blocked behind F4.

**Fix**: Add to F4: "In-scope for day-1: page↔markdown sync, database↔beads sync, webhook receiver, three-way merge. Out-of-scope for day-1: [list of interkasten handlers not needed for the core F4 criteria]. interkasten's remaining handlers can continue running until a future feature ports them."

---

### P2 | SC-05 — Three-lane priority dispatch is implicit F1 scope

**Location**: PRD § Architecture: "three-lane priority dispatch (express/urgent/routine)"

**Problem**: Three-lane priority dispatch is specified in the Architecture section as a component of EventBus but does not appear in F1's acceptance criteria. It is a non-trivial implementation (priority queues, per-lane goroutine pools, starvation prevention). If it's required for F1, it should be in the criteria. If it's an optimization that can be added later, it should be noted as day-2 in non-goals.

**Fix**: Either add to F1 criteria: "EventBus supports three priority lanes (express/urgent/routine); express-lane events are dispatched before routine-lane events of the same entity" — or add to Non-goals: "Three-lane priority dispatch is day-2; F1 uses single-lane dispatch."

---

### P2 | SC-06 — GitHub App creation has no owning feature

**Location**: PRD § Dependencies: "GitHub App credentials (webhook secret, app ID, private key)"

**Problem**: Creating and configuring a GitHub App is scope that involves external system configuration (GitHub App registration, webhook URL registration, permission grants). It's listed as a dependency but has no owning feature. F3 assumes the App exists, but who creates it? Is there a setup script? A one-time manual step? If it's manual, the F3 acceptance criteria for webhook verification cannot be run in CI without a pre-configured App.

**Fix**: Add a "Setup" section to F3 or a standalone F0 for infrastructure setup: "GitHub App created and configured with webhook URL pointing to interop's Caddy endpoint. App credentials stored in interop's config. HMAC webhook secret rotatable without restarting the daemon."

---

### P3 | SC-07 — Auraken non-goal implies a future Intercore integration API

**Location**: PRD § Non-goals: "interop can consume those via Intercore events later"

**Problem**: "Intercore events" as an interop input source implies an Intercore→interop integration path that doesn't exist today. If this future architecture shapes current Event type design (e.g., an Intercore event type enum value is reserved), it adds latent complexity to F1. If it doesn't, the statement is harmless flavor text.

**Fix**: Clarify: either "this statement is architectural flavor — no current design decisions are driven by it" or "Intercore event consumption is a day-2 adapter; the Event type includes a `SourceAdapter: intercore` reserved value."

---

### P3 | SC-08 — MCP-tools-only conflict resolution is an unvalidated assumption

**Location**: PRD § Open Questions #3: "MCP tools suffice for agent-driven resolution. Do we need a web UI for human conflict review? Probably day-2."

**Problem**: "MCP tools suffice" assumes that all conflict resolution will be agent-driven. If interop is used in a context where the human operator isn't in a Claude Code session (e.g., reviewing conflicts at midnight on mobile), MCP tools are inaccessible. The assumption should be validated before F6 is finalized — even a simple `interop conflicts list` CLI output would close this gap.

**Fix**: Add to F6 acceptance criteria: "`interop conflicts list` CLI command outputs pending conflicts in human-readable format without requiring a Claude Code session."

## Improvements

1. **Add a feature ordering table to the PRD** — explicitly list F1→F2/F3/F4/F5→F6a/F7 as the dependency graph. This prevents teams from starting F7 before adapters are complete and prevents F3 criterion 3 from blocking in isolation.

2. **Define "port interkasten" more precisely** — list the interkasten handlers in scope for F4 day-1 vs deferred. This converts an open-ended porting task into a bounded implementation target.

3. **Split F6 now** — F6a (MCP server) and F6b (plugin) have different risk profiles and different completion dates. Keeping them as one feature creates unnecessary blocking.

<!-- flux-drive:complete -->
