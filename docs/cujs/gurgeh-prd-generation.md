---
artifact_type: cuj
journey: gurgeh-prd-generation
actor: regular user (developer or product manager defining features)
criticality: p2
bead: Demarch-2c7
---

# Gurgeh PRD Generation and Validation

## Why This Journey Matters

Feature work starts with clarity about what to build. Without a structured spec, developers oscillate between "just build something" (scope creep, rework) and "plan everything" (analysis paralysis, stale docs). Gurgeh sits in the middle — a TUI-first tool that helps the developer articulate requirements, validate them against the codebase, and produce a spec that downstream tools (Coldwine, Clavain) can consume.

The spec is the contract between intent and implementation. If Gurgeh makes spec creation feel like overhead, developers skip it and the rest of the pipeline (task decomposition, agent dispatch, drift detection) has nothing to anchor on. If it makes spec creation feel like thinking — structured, quick, clarifying — developers use it voluntarily.

## The Journey

The developer has an idea for a new feature. They open Gurgeh via the Autarch TUI (`./dev autarch tui --tool=gurgeh`) or directly (`go run ./cmd/gurgeh`). The TUI presents their existing specs, filterable by status (draft, active, shipped).

They create a new spec. Gurgeh prompts for the basics: title, target module, problem statement. The developer types a few sentences. Gurgeh's codebase scan runs in the background — checking the target module for existing patterns, similar features, and relevant test files. The scan results appear as context suggestions: "Found similar pattern in internal/scheduler/selector.go" or "Module has 45 tests, coverage at 78%."

The developer adds user stories, acceptance criteria, and success metrics. Gurgeh validates as they type — flagging missing acceptance criteria, suggesting CUJ links, warning if the spec references modules that don't exist. The spec is stored locally in `.gurgeh/specs/` as structured YAML.

When the spec is ready, the developer exports it: `go run ./cmd/gurgeh export PRD-001`. This generates a brief doc that Clavain's `/write-plan` can consume. The export includes the codebase context Gurgeh found, so the planner doesn't need to re-scan.

Over time, the developer uses `go run ./cmd/gurgeh history PRD-001` to see how a spec evolved, `go run ./cmd/gurgeh diff PRD-001 v1 v2` to compare versions, and `go run ./cmd/gurgeh prioritize PRD-001` for agent-powered feature ranking within a spec.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| New spec created in under 5 minutes for simple features | measurable | Time from `create` to first save ≤ 5 min |
| Codebase scan surfaces relevant patterns | observable | Scan results reference files in the target module |
| Exported briefs are consumed by `/write-plan` without manual editing | measurable | Plan generation succeeds from Gurgeh export |
| Spec validation catches missing acceptance criteria | measurable | Validation warns on specs without AC |
| Version history tracks all changes | measurable | `history` shows ≥1 entry per save |
| Developer prefers Gurgeh over ad-hoc brainstorm docs | qualitative | Adoption metric — specs created via Gurgeh vs raw markdown |

## Known Friction Points

- **TUI-only for creation** — no CLI-only spec creation flow. Developers in headless environments must use the raw YAML format.
- **Codebase scan latency** — large repos may slow the scan. Should be async with progressive results.
- **No integration with beads** — specs and beads are separate systems. Linking a spec to a bead is manual.
- **Export format is one-way** — changes to the exported brief don't flow back to the spec.
