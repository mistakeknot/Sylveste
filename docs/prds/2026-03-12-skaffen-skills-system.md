---
artifact_type: prd
bead: Demarch-6i0.19
stage: design
---
# PRD: Skaffen Skills System (SKILL.md Discovery and Invocation)

## Problem

Skaffen lacks a skills system — all 5 competitors (Claude Code, Codex, Gemini CLI, OpenCode, Amp) ship SKILL.md-based instruction discovery and invocation. Users cannot extend Skaffen's behavior with reusable instructional documents. The existing TOML command system handles templates and scripts but not agent-level behavioral instructions.

## Solution

Add a skills system to Skaffen that discovers SKILL.md files from a 4-tier directory hierarchy, parses rich YAML frontmatter, and injects skill content as user-role messages into the agent loop on demand. Support explicit slash-command invocation, implicit trigger-based activation, and session-scoped pinning for workflow skills.

## Features

### F1: Skill Loader Package (`internal/skill/`)
**What:** Go package that discovers, parses, and caches SKILL.md files from the 4-tier directory hierarchy.

**Acceptance criteria:**
- [ ] Discovers skills from all 4 tiers: `.skaffen/skills/`, `.skaffen/plugins/*/skills/`, `~/.skaffen/skills/`, `~/.skaffen/plugins/*/skills/`
- [ ] Parses YAML frontmatter: name, description, user_invocable, triggers, args, model
- [ ] Validates required fields (name, description) and returns errors for malformed skills
- [ ] Eagerly scans directories and parses frontmatter at startup (metadata only)
- [ ] Lazily loads skill body on first activation (cached after first read)
- [ ] Higher-priority tiers shadow lower-priority tiers on name collision
- [ ] Handles missing directories gracefully (no error if `.skaffen/skills/` doesn't exist)
- [ ] `_test.go` with table-driven tests for discovery, parsing, shadowing, and error cases

### F2: Skill Injector (`internal/skill/inject.go`)
**What:** Formats skill content as user-role messages for injection into the agent conversation.

**Acceptance criteria:**
- [ ] Produces a user-role message containing the full SKILL.md body wrapped in skill metadata tags
- [ ] Appends user arguments after the skill body when provided (e.g., `/commit-review src/`)
- [ ] Enforces a per-skill body size cap (5K tokens / ~15K chars)
- [ ] Returns an error (not a panic) if skill body exceeds the cap
- [ ] `_test.go` covering injection formatting, argument appending, and size limit enforcement

### F3: Implicit Trigger Matching (`internal/skill/trigger.go`)
**What:** Matches user input against skill trigger phrases to auto-activate relevant skills.

**Acceptance criteria:**
- [ ] Case-insensitive substring matching of user message against each skill's `triggers` array
- [ ] Returns a list of matched skills (may match multiple)
- [ ] Does not match skills where `user_invocable` is false
- [ ] Returns empty list when no triggers match
- [ ] Matching is O(skills × triggers) — acceptable for <100 skills; document the bound
- [ ] `_test.go` with cases: single match, multi-match, no match, case insensitivity, user_invocable=false filtering

### F4: Skill Pinning (`internal/skill/pin.go`)
**What:** Session-scoped persistence for workflow skills that should stay active across turns.

**Acceptance criteria:**
- [ ] `Pin(name)` adds a skill to the pinned set; `Unpin(name)` removes it
- [ ] `Pinned()` returns the list of currently pinned skill names
- [ ] Pinned skills are re-injected as user-role messages on every turn
- [ ] Pinned skill list is stored in session metadata (survives context compaction)
- [ ] Attempting to pin a non-existent skill returns an error
- [ ] `_test.go` covering pin, unpin, list, duplicate pin, and non-existent skill cases

### F5: TUI Integration — Slash Command Invocation
**What:** Wire skill invocation into the TUI command dispatcher so `/skill-name` activates skills.

**Acceptance criteria:**
- [ ] `/skill-name` invokes a discovered skill by name (case-insensitive lookup)
- [ ] `/skill-name args` passes `args` to the skill injector
- [ ] `/skill-name --pin` activates the skill AND pins it for the session
- [ ] Namespaced invocation `/namespace:skill-name` resolves to the correct tier when duplicates exist
- [ ] Name collision resolution: built-in commands > custom TOML commands > skills
- [ ] Unknown skill name returns a helpful error message listing similar skill names
- [ ] Skills appear in the tab-completion system (`cmdcomplete.go`)

### F6: TUI Integration — `/skills` Management Command
**What:** A built-in `/skills` command for listing, inspecting, and managing skills.

**Acceptance criteria:**
- [ ] `/skills` or `/skills list` shows all discovered skills grouped by source tier, with name + description
- [ ] `/skills info <name>` shows full metadata: name, description, triggers, args, model, source path, body preview (first 3 lines)
- [ ] `/skills pin <name>` pins a skill for the session
- [ ] `/skills unpin <name>` unpins a skill
- [ ] `/skills pinned` shows currently pinned skills
- [ ] Output uses `theme.Current().Semantic()` colors (no hardcoded colors)

### F7: TUI Integration — `/help` and Implicit Activation
**What:** Skills appear in `/help` output and implicit triggers fire during normal chat.

**Acceptance criteria:**
- [ ] `/help` lists skills in a separate "Skills" section below built-in and custom commands
- [ ] Each skill entry shows: name, description, source tier indicator
- [ ] Implicit trigger matching runs on every user message before sending to the agent
- [ ] When triggers match, matched skills are injected alongside the user's message
- [ ] A brief indicator shows which skills were auto-activated (e.g., `[skill: commit-review]`)

### F8: Agent Loop Integration
**What:** Wire the skill injector into Skaffen's agent message pipeline so injected skills reach the model.

**Acceptance criteria:**
- [ ] Skill messages are inserted as user-role messages in the conversation (not system prompt)
- [ ] System prompt remains unchanged when skills are activated (preserves Anthropic prompt caching)
- [ ] Pinned skills are re-injected on each turn
- [ ] Non-pinned skills are injected only for the activating turn
- [ ] Skill metadata (name + description, ~100 tok/skill) is included in the agent's tool description for discoverability
- [ ] Total skill metadata budget capped at 15K chars

## Non-goals

- **Skill marketplace or registry** — no remote skill installation (`skaffen skills install <url>`). Users copy SKILL.md files manually for now.
- **Skill execution** — skills are instructional documents, not executable code. The existing TOML command system handles script execution.
- **Semantic trigger matching** — start with substring matching. Fuzzy/embedding-based matching is a future upgrade.
- **Permission scoping per skill** — Claude Code's `contextModifier` for tool permissions is deferred. All skills get the same tool access as the session.
- **Skill versioning** — no version field in frontmatter. Skills are files on disk; version control handles history.

## Dependencies

- Existing `internal/command/` package (for coexistence and name collision resolution)
- Existing `internal/config/` package (for discovery path resolution via `cfg.SkillDirs()`)
- Existing `internal/tui/commands.go` (for slash command dispatch)
- `gopkg.in/yaml.v3` (already in go.mod for TOML config parsing — actually need to verify)
- No new external dependencies expected (YAML parsing may already be available via existing deps)

## Open Questions

1. **YAML parser:** Is `gopkg.in/yaml.v3` already in Skaffen's go.mod? If not, we need to add it for frontmatter parsing. Alternative: use a lightweight frontmatter parser that handles `---` delimiters without a full YAML library.
2. **Trigger debouncing:** If a user's message matches 5 skills, do we inject all 5? Probably yes with a warning if total injection exceeds the budget. Define behavior for >3 simultaneous trigger matches.
3. **Plugin skill trust:** Should skills from `.skaffen/plugins/*/` show a trust warning on first activation? Defer to a follow-up — note the risk but don't block shipping.
