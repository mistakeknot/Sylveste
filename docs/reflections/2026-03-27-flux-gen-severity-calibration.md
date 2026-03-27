---
bead: sylveste-pkx
title: "Reflect: flux-gen P0/P1 severity calibration fix"
date: 2026-03-27
type: reflection
---

# Reflection: Flux-Gen P0/P1 Severity Calibration

## What worked

- **Multi-agent plan review caught a critical architectural flaw**: All 4 review agents independently identified that domain profile injection doesn't reach generated agents (keyed on `### fd-{agent-name}`, generated agents have ephemeral names). This would have been a silent no-op if shipped as originally planned.
- **TDD approach**: Writing 4 failing tests first, then implementing to pass them, caught the version gating edge case (v5 emitted for stale specs) before it could become a production bug.
- **Structured severity_examples instead of free-form calibration**: fd-quality's insight that `decision_lens` already exists for prioritization guidance led to a better design — inject canonical definitions as fixed context and ask only for domain-specific exemplars.

## What surprised

- **The injection path gap was invisible from the spec**: protocol.md:201 says "Extract Review Criteria section" but the dispatch code in launch.md Step 2.1a never implemented that extraction. The spec and reality diverged silently. This is a documentation-reality drift pattern worth watching.
- **Generated agents had the right severity definitions all along**: The boilerplate "P0/P1: Issues that would cause failures" was present. The problem was judgment methodology, not definitions. The fix adds concrete scenarios and escalation instructions, not better definitions.

## What to do differently

- Before proposing changes to an injection/dispatch path, verify the path actually reads what you plan to write. Read the dispatch code, not just the spec.
- For prompt engineering changes, prefer structured objects (severity/scenario/condition) over free-form text fields. Structured fields produce consistent LLM output and verifiable template rendering.

## Deferred work

- Domain profile injection for generated agents (requires `## General Criteria` section or `domain:` frontmatter — separate bead)
- `_short_title()` truncation producing broken section titles ("No read", "Json")
- End-to-end validation: running `/flux-gen` + `/flux-drive` to confirm generated agents actually produce P0/P1 in practice (Task 4 of the plan, deferred to next session since it requires LLM interaction)
