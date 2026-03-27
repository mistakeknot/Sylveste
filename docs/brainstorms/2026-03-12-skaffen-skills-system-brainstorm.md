---
artifact_type: brainstorm
bead: Sylveste-6i0.19
stage: discover
---
# Skaffen Skills System (SKILL.md Discovery and Invocation)

## What We're Building

A skills system for Skaffen that discovers SKILL.md instruction files from a 4-tier directory hierarchy, injects them into the agent loop as user-role messages on demand, and supports both explicit slash-command invocation and implicit trigger-based activation.

Skills are instructional markdown documents — not executable code. When activated, the skill's body is injected into the agent's conversation context as an authoritative instruction. The agent interprets and follows the skill's instructions using its available tools.

## Why This Approach

### The competitive gap

All 5 major competitors ship a skills system: Claude Code (SKILL.md + frontmatter, 6 discovery paths), Codex CLI (SKILL.md, 6 paths, implicit invocation), Gemini CLI (SKILL.md), OpenCode (SKILL.md, 6 paths), Amp (SKILL.md + git install). Skaffen currently has TOML-based custom commands (templates + scripts) but no skill system.

### The injection decision

Deep research across all 5 competitors revealed a clear industry consensus:

| Approach | Token Efficiency | Activation Reliability | Cache Friendliness | Used By |
|----------|-----------------|----------------------|-------------------|---------|
| **System prompt prepend** | Poor — breaks Anthropic prompt caching | High (authoritative) | Bad — prompt changes per skill | Gemini (instructions only, not skills) |
| **User message injection** | Best — system prompt stays stable | High (deterministic injection) | Best — 90% cache discount preserved | **Claude Code** (production, 53+ plugins) |
| **Tool result injection** | Good — on-demand | Moderate — model must decide to call | Good | OpenCode, Amp |

**We chose user message injection** (Claude Code pattern) because:
1. **Preserves Anthropic prompt caching.** System prompt is stable; skill body is paid once per activation (~2-5K tok) then compacted away. Idle overhead is ~100 tok/skill in tool descriptions.
2. **Deterministic activation.** Explicit `/skill-name` and implicit trigger matching both deterministically inject the skill — no model decision required for the injection itself.
3. **Battle-tested.** Claude Code runs this at scale with 53+ Interverse plugins. Proven pattern.
4. **Fits Skaffen's architecture.** Agent loop already separates system prompt construction from per-turn message building. Skill injection slots into the per-turn pipeline.

### Token efficiency data

Benchmark data (42 skills, 1,000 conversations):
- Eager loading: 21,000 tokens/turn
- Lazy (metadata only): ~630 tokens idle + ~2-5K per activated skill
- Real-world activation rate: ~5.5% of skills per conversation
- **Savings: 95.8%** with lazy loading

## Key Decisions

### 1. Invocation model: explicit slash + implicit trigger detection

- **Explicit:** `/skill-name` or `/namespace:skill-name` (namespaced when duplicates exist across tiers)
- **Implicit:** User's message is matched against `triggers` frontmatter array using case-insensitive substring matching. Matching skills are injected alongside the user's message.
- **Pinning:** `/skill-name --pin` keeps the skill active across turns until `/skills unpin skill-name`. Pinned skill list stored in session metadata, survives compaction. Default: single-turn (no pinning).

### 2. Discovery: 4-tier plugin-aware hierarchy

Discovery paths, highest priority first (project overrides user-global on name collision):

```
.skaffen/skills/              # per-project skills
.skaffen/plugins/*/skills/    # per-project installed plugins
~/.skaffen/skills/            # user-global skills
~/.skaffen/plugins/*/skills/  # user-global installed plugins
```

Each skill lives in a directory: `<skill-dir>/SKILL.md`. Discovery is eager at startup (scan all dirs, parse frontmatter only). Body loading is lazy (read full file on first activation).

### 3. SKILL.md frontmatter schema (rich)

```yaml
---
name: commit-review
description: Review staged changes for quality issues
user_invocable: true          # true = user can call via /name; false = agent-only
triggers:                     # implicit activation keywords
  - review commit
  - check my changes
args: "[file_pattern]"        # argument hint for help display
model: opus                   # preferred model hint (optional)
---
```

Fields:
- `name` (required): Skill identifier, used as slash command name
- `description` (required): One-line description for help display and metadata injection (~100 tok budget)
- `user_invocable` (default: true): Whether user can invoke via `/name`
- `triggers` (optional): List of trigger phrases for implicit activation
- `args` (optional): Argument hint string for help display
- `model` (optional): Preferred model for this skill (hint, not enforced)

### 4. Injection mechanism: user-role messages

When a skill is activated (explicit or implicit):
1. Skill body is read from disk (lazy load, cached after first read)
2. Body is injected as a user-role message with skill metadata tags
3. Agent receives the skill instructions as authoritative context for this turn
4. After the turn completes, non-pinned skills are not re-injected
5. System prompt remains unchanged — preserves Anthropic prompt caching

### 5. Integration with existing command system

- Skills and TOML commands coexist. Commands handle templates/scripts; skills handle agent instructions.
- `/help` lists both: built-in commands, custom commands, and skills (grouped separately)
- Name collision resolution: built-in > commands > skills (built-in always wins)
- `/skills` management command: `list`, `pin <name>`, `unpin <name>`, `info <name>`

## Open Questions

1. **Trigger matching algorithm:** Simple substring matching vs fuzzy/semantic matching? Substring is fast and predictable but may miss paraphrases. Start with substring, upgrade later if needed.
2. **Skill argument passing:** When user types `/commit-review src/`, how does `src/` get passed to the skill? Likely: append as context after skill body injection. Need to define the interpolation pattern.
3. **Security boundary:** Skills from `.skaffen/plugins/*/` are third-party. Should they be treated as untrusted (sandboxed tool permissions)? Claude Code has this problem (36% of public skills contain prompt injection per Snyk). For now: display source tier in `/skills list`, warn on first activation of plugin skills.
4. **Skill size limits:** Should there be a max token budget per skill? Claude Code uses 15K char budget for all skill descriptions. We should cap individual skill body at ~5K tokens and total metadata at ~15K chars.
