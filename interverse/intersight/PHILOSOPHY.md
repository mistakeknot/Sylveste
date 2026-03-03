# intersight Philosophy

## Core Principle: Composition Over Capability

intersight does not build browser automation, caching, or token extraction engines. It composes existing tools (Playwright MCP, intercache, Dembrandt, Claude vision) into a coherent pipeline via SKILL.md orchestration.

## Design Bets

1. **External tools: adopt, don't rebuild** — Dembrandt handles 80-95% of token extraction. Playwright MCP handles all browser automation. We orchestrate, we don't re-implement.

2. **Scripts over prompts** — Extraction logic lives in deterministic JS scripts, not in Claude's prompt-based reasoning. Scripts produce consistent output; prompts produce variable output.

3. **Fail gracefully, report completely** — Each phase can fail independently. The pipeline continues and the output documents what succeeded and what didn't via `intersight:meta.phases_completed`.

4. **Accuracy over completeness** — Wrong tokens are worse than missing tokens. When in doubt, omit rather than guess.

5. **Ethics compliance is mandatory** — robots.txt is checked before any extraction. Fail-closed on parse errors.
