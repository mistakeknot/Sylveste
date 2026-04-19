### Findings Index
- P2 | Q1 | "phases/ directory filenames" | Mixed naming style: `launch.md` vs `launch-codex.md` vs `shared-contracts.md` — no stated convention
- P2 | Q2 | "SKILL.md L8 HTML comment" | Orchestration-critical instruction embedded in an HTML comment; comments are usually presentational, not dispatch-critical
- P2 | Q3 | "phases/synthesize.md Step 3.4 vs Step 3.4a vs 3.4b vs 3.4c vs 3.4d" | Step numbering scheme has grown to 5 subdivisions without a clear structural rationale — cluttered
- P2 | Q4 | "references/ vs phases/ directory split" | The split between reference-material and phase-instructions is soft; scoring-examples.md is referenced by phase logic, not just lookup
- P2 | Q5 | "SKILL.md and SKILL-compact.md markdown style drift" | Heading nesting differs between the two files for the same sections (e.g., "Agent Roster" is H2 in main and H2 in compact but has different nesting of subsections)
- P3 | Q6 | "config references" | Paths use both `${CLAUDE_PLUGIN_ROOT}` and relative paths (e.g., `interverse/interflux/config/...`) — inconsistent
- P3 | Q7 | "error handling idioms" | Mix of `|| true`, `|| echo error`, `2>/dev/null` — no single convention for "error is acceptable here"
Verdict: needs-changes

### Summary

The skill is readable and well-commented. Markdown structure is mostly consistent. Issues are minor: filename conventions drift within the phases/ directory, step numbering has become over-subdivided in synthesize.md, and the references/ vs phases/ split is conceptually unclear (scoring-examples is a reference but drives phase scoring logic). A few places use HTML comments to carry dispatch-critical instructions, which is unconventional. None of these block the skill's operation, but they accumulate cognitive load for maintainers.

### Issues Found

1. Q1. P2: Filename style drift. `phases/launch.md`, `phases/launch-codex.md`, `phases/shared-contracts.md`, `phases/cross-ai.md`, `phases/expansion.md`. Mix of hyphens and plain names. The pattern "noun.md" (launch, expansion, reaction, slicing, synthesize) vs "noun-modifier.md" (launch-codex, shared-contracts, cross-ai) reflects the files' roles: some are phase logic, some are variant implementations, some are shared contracts. Fix: document the convention — e.g., "phase/<phase-name>.md for phase logic; phase/<phase-name>-<variant>.md for variants; phases/_shared-<topic>.md for contracts (underscore prefix sorts them together)".

2. Q2. P2: Orchestration instruction in HTML comment. SKILL.md L8: `<!-- compact: SKILL-compact.md — if it exists in this directory, load it instead... -->`. HTML comments in markdown are usually editor annotations. Here it's a load directive that the orchestrator must obey. Fix: promote to visible prose at the top of SKILL.md, or to a frontmatter key (`compact_variant: SKILL-compact.md`).

3. Q3. P2: Over-subdivided step numbers. synthesize.md has 3.0, 3.1, 3.2, 3.3, 3.4, 3.4a, 3.4b, 3.4c, 3.4d, 3.5, 3.5-research, 3.6, 3.7. Launch.md has 2.0, 2.0.4, 2.0.5, 2.1, 2.1-research, 2.1a, 2.1b, 2.1c, 2.1d, 2.1e, 2.2, 2.2-challenger, 2.2a, 2.2a.5, 2.2a.6, 2.2b, 2.2c. A 4-level hierarchy (2.2a.5) suggests a spec sprawling beyond a simple sequence. Fix: flatten — either rename to 2.1, 2.2, ..., 2.15 (flat sequence) or factor sub-steps into their own phase files.

4. Q4. P2: phases/ vs references/ distinction is soft. `phases/slicing.md` is read during dispatch (launch.md Step 2.1c) and contains algorithmic logic. `references/scoring-examples.md` is also read during triage (SKILL.md Step 1.2b via scoring-examples link). Both are "lookup during orchestration" — the distinction "phases = instructions, references = lookup" fails. Fix: consolidate under `phases/` (everything the orchestrator reads during execution) and reserve `references/` for human-authoring lookups (e.g., how to add a new agent). Or flip: rename `references/` to `lookups/` and document the criteria.

5. Q5. P2: Style drift between SKILL.md and SKILL-compact.md. Section "Agent Roster": in SKILL.md (L234-251) the roster is described in prose with "[review mode]: Read `references/agent-roster.md`..." whereas in SKILL-compact.md (L235-270) it's a single tabular listing. Intent divergence — one file redirects to a reference, the other inlines. Not wrong, but signals the two files have drifted stylistically. Fix: pick a convention — either both redirect, or both inline. Given the files should converge (see fd-architecture A1), this resolves itself.

6. Q6. P3: Mixed path idioms. Good: `${CLAUDE_PLUGIN_ROOT}/scripts/findings-helper.sh`. Bad: `interverse/interflux/config/flux-drive/discourse-lorenzen.yaml` (relative to cwd, assumes monorepo). Fix: always use `${CLAUDE_PLUGIN_ROOT}` for plugin-owned paths.

7. Q7. P3: Error handling idiom drift. `sqlite3 ... 2>/dev/null || true` (synthesize.md L325), `$(intercept decide ...) || ...` (reaction.md L30), `2>/dev/null` alone elsewhere. Each is "fail silently" but with different semantics. Fix: a `bash_style.md` in the plugin root, or inline a one-line helper `soft_fail() { "$@" 2>/dev/null || true; }` that all soft-fail paths use.

### Improvements

1. IMP-1. A short `STYLE.md` in the skill root documenting: filename conventions, step-number hierarchy rules (max 3 levels), HTML-comment policy, shell error-handling idiom, `${CLAUDE_PLUGIN_ROOT}` usage. Prevents drift as the skill evolves.

2. IMP-2. A markdownlint or vale config to catch style drift automatically. Heading levels, trailing whitespace, line length.

3. IMP-3. Consider a flat section numbering (2.1 through 2.20) with meaningful subheadings within each step, rather than nesting 2.2a.5. Easier to cite in commits and beads.

<!-- flux-drive:complete -->
