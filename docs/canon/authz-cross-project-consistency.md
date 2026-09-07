---
artifact_type: canon
---

# Cross-project consistency for authz operations

## Scope

Cross-project behavior applies to the authz gate operations that can span one or more
repo-local `--cross-project-id` contexts. The contract is canonical for
`clavain-cli policy` and gate wrapper orchestration.

## Operations and consistency mode

| Op | Consistency rule |
|---|---|
| `ic-publish-patch` | **Strict-all-or-nothing** |
| `bead-close` | **Best-effort** |
| `git-push-main` | **Best-effort** |
| `bd-push-dolt` | **Best-effort** |

## `ic-publish-patch`: strict mode

`ic-publish-patch` is treated as an atomic publishing op:

- Run checks/writes across all target projects associated with the workflow.
- If **any** project evaluation fails, the operation is considered failed overall.
- No partial success is reported, and **no per-project authz row should be written** when a member fails.
- A successful `ic-publish-patch` may write rows for all involved projects and the same `cross_project_id`.

This guarantees that publish authorization decisions are not fragmented across repo
boundaries and keeps `.publish-approved` and authz record semantics aligned.

## Best-effort ops (`bead-close`, `git-push-main`, `bd-push-dolt`)

For these ops, each project target is executed independently:

- A failure for one project may still allow other projects to proceed.
- Authz records are written for successful project branches.
- Gaps are expected if one target fails (partial records).

The canonical repair surface is `policy audit --verify`, which must expose incomplete
cross-project sets when `cross_project_id` is present.

## `policy audit --verify`

When `policy audit --verify` is run, grouped cross-project rows (`cross_project_id`)
are checked for expected completeness.

- Missing rows are treated as **gaps** and surfaced in audit output.
- Gaps are non-fatal at check time but are required evidence for follow-up and SRE triage.
- Audit should distinguish strict-all-or-nothing vs best-effort operations when summarizing gaps.

## Success/failure rubric

### Strict op (`ic-publish-patch`)

- `pass all projects` + `all rows written` → overall success.
- `any project fails` or `any row missing` in the same `cross_project_id` → overall failure.

### Best-effort ops

- each row is evaluated and reported independently.
- missing rows are expected and represented in `--verify` output.

