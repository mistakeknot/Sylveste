# fd-scenario-validation: Factory Substrate Scenario Bank Review

**Reviewer:** fd-scenario-validation (test infrastructure, evaluation harnesses, dataset contamination)
**Date:** 2026-03-05
**Target:** `docs/prds/2026-03-05-factory-substrate.md`, `docs/brainstorms/2026-03-05-factory-substrate-brainstorm.md`
**Scope:** Scenario bank design (F3, F6), schema adequacy, dev/holdout separation, scenario gaming

---

## 1. Dev/Holdout Separation Is Convention-Only, Not Mechanically Enforced

**Priority: P0**
**Evidence:** PRD F6 states "Implementation agents blocked from reading `.clavain/scenarios/holdout/` during Build phase" and brainstorm says "Enforcement via clavain-cli policy (not filesystem permissions -- agents can read anything)." The enforcement mechanism is `policy-check`, a CLI command that "gates tool dispatch."

### Finding

The separation relies on `clavain-cli policy-check` intercepting tool dispatch, but agents in this system are Claude Code sessions with direct filesystem access via Read, Bash, and cat. `policy-check` can gate `clavain-cli scenario-run` and `clavain-cli scenario-list --holdout`, but it cannot prevent an agent from running `cat .clavain/scenarios/holdout/*.yaml` or using the Read tool directly. The brainstorm explicitly acknowledges this: "not filesystem permissions -- agents can read anything."

This makes holdout separation a cooperative convention, not a mechanical guarantee. An agent that follows instructions will respect it; an agent that drifts, hallucinates a tool call, or is prompt-injected will not. More critically, any agent that has seen the holdout directory structure in a previous session's context (e.g., via glob output or error messages) has already been contaminated even if it never intentionally reads the files.

The PRD also lacks clarity on when holdout scenarios are authored. If implementation and validation run in the same sprint, and the same human or agent authors both dev and holdout scenarios, the holdout set is not truly independent -- it shares the same specification interpretation as the dev set.

### Recommendation

1. Use filesystem permissions or containerized execution for mechanical enforcement. Run implementation agents under a UID/GID that lacks read access to `holdout/`. This is the standard approach in ML eval harnesses (e.g., SWE-bench uses Docker isolation).
2. If filesystem isolation is impractical, at minimum encrypt holdout scenario files at rest with a key only injected into validation agent sessions. Decryption happens in-memory during `scenario-run`.
3. Document that holdout authoring must be temporally separated from sprint dev work -- ideally holdout scenarios are authored by a different agent or human, in a session that never touches implementation.
4. Add a contamination audit: log every file access during Build phase and flag any touch of `holdout/` as a policy violation, even if the content was not used. This at least detects breaches.

---

## 2. YAML Schema Lacks Expressiveness for Non-Trivial Correctness Types

**Priority: P1**
**Evidence:** Brainstorm scenario schema (lines 113-135) defines `steps` as `action`/`expect` string pairs, and `rubric` as `criterion`/`weight` string/float pairs.

### Finding

The schema supports exactly one correctness mode: natural-language expectations evaluated by an LLM judge. This works for behavioral/satisfaction scenarios but is inadequate for the full range of correctness types a factory substrate needs:

- **Exact match:** "Output file contains exactly this JSON." No schema field for a literal expected value or a comparator type.
- **Structural equivalence:** "AST of generated code matches reference AST." No way to specify a comparison function or reference artifact.
- **Behavioral properties / invariants:** "For all inputs in this class, the output satisfies P(x)." The `expect` field is a single string, not a property specification with quantifiers or generators.
- **Negative constraints:** "Must NOT contain SQL injection vectors." There is no `must_not` or `deny` field. A rubric criterion like "No SQL injection" works for LLM judges but not for deterministic checkers.
- **Deterministic assertions:** "Exit code is 0" or "File exists at path X." The schema has no way to distinguish LLM-judged expectations from machine-checkable assertions. Routing everything through LLM judges is expensive and noisy for properties that are trivially verifiable.

The `rubric` field is also flat -- all criteria are weighted equally in structure. There is no support for hard requirements (must-pass gates) vs. soft quality signals.

### Recommendation

1. Add a `type` field to `expect` entries: `{type: exact_match, value: "..."}`, `{type: llm_judge, description: "..."}`, `{type: assertion, command: "test -f output.json"}`, `{type: regex, pattern: "..."}`, `{type: negation, description: "Must not..."}`.
2. Add a `gate` boolean to rubric criteria distinguishing hard gates (fail = scenario fail) from soft signals (contribute to satisfaction score).
3. Add an optional `reference_artifact` field for structural comparison scenarios, pointing to a file in CAS or filesystem.
4. Consider a `properties` section for invariant-style checks that run across multiple inputs (property-based testing pattern).

---

## 3. No Schema Versioning Strategy

**Priority: P1**
**Evidence:** The schema is defined inline in the brainstorm with no version field. The PRD mentions `clavain-cli scenario-validate` for schema validation but no versioning mechanism.

### Finding

Schema evolution is inevitable. The current schema will need new fields (per recommendation above, or as usage reveals gaps). Without versioning:

- Old scenarios will fail validation after schema changes.
- Historical satisfaction results will reference scenarios whose schema has changed, making longitudinal comparisons unreliable.
- Agents that cache or remember scenario structure from previous sessions will generate invalid YAML.
- CXDB records `clavain.scenario.v1` turns, but the `.v1` suffix on the CXDB type is not the same as the YAML schema version -- a `scenario.v1` turn could contain YAML from schema v1.0, v1.1, or v2.0.

The CXDB type registry has its own versioning (type bundles with projections), but the scenario YAML schema sits outside CXDB and has no equivalent.

### Recommendation

1. Add `schema_version: "1.0"` as a required field in every scenario YAML file.
2. `scenario-validate` should accept `--schema-version` and default to latest. Old scenarios validate against their declared version.
3. Maintain schema files (JSON Schema or equivalent) at `.clavain/scenarios/schema/v1.0.yaml`, `.clavain/scenarios/schema/v1.1.yaml`, etc.
4. Satisfaction results in CXDB should record both the CXDB type version and the scenario schema version used.
5. Define a migration command: `clavain-cli scenario-migrate --to=v1.1` that updates YAML files forward.

---

## 4. Scenario Authoring Is Not Truly Externalized

**Priority: P2**
**Evidence:** PRD open question 4: "Agent-authored + human-curated? Need `/scenario:generate`?" Brainstorm says "Who writes scenarios -- the human, the agent, or both?"

### Finding

The PRD claims scenarios externalize correctness definitions, but the YAML schema as designed requires understanding of the system under test at a level that presumes developer knowledge. The `setup` field contains free-text preconditions ("Application running with test database"), `steps` contain domain-specific actions ("Navigate to cart"), and `rubric` criteria reference implementation details ("Order persisted in database", "Inventory decremented").

A product owner or QA engineer could plausibly author the `intent` and high-level `steps`, but the `rubric` criteria and `setup` preconditions require knowledge of the system's internals. This limits the scenario bank to developer-authored artifacts, which undermines the externalization goal -- if only developers write scenarios, the correctness definitions embed the same assumptions as the code.

The `scenario-create` command scaffolds YAML but does not provide guidance, templates, or validation of whether the scenario is well-formed beyond schema compliance.

### Recommendation

1. Split scenarios into two layers: a **specification** layer (intent, user-visible steps, acceptance criteria in plain language) and an **implementation** layer (setup commands, assertion types, rubric with weights). Non-developers author the spec; developers or agents fill in the implementation.
2. Provide scenario templates per domain (web app, CLI tool, library, infrastructure) with commented examples.
3. Add a `scenario-lint` command that warns about common issues: empty rubric, missing risk tags, steps without expects, criteria that reference code internals.
4. Consider a `/scenario:interview` flow that asks a product owner structured questions and generates the spec layer from answers.

---

## 5. No Scenario Tagging or Selection Strategy for Sprints

**Priority: P2**
**Evidence:** PRD F3: `scenario-run <pattern>` runs "matching scenarios." No specification of what `<pattern>` matches against.

### Finding

The `scenario-run <pattern>` command implies glob or regex matching on scenario filenames, but there is no structured tagging system for selecting which scenarios apply to a given sprint. `risk_tags` exists but is described only as metadata, not as a selection mechanism.

Without structured selection:
- Every sprint runs all scenarios (expensive, slow, noisy).
- Or scenarios are manually specified per sprint (defeats automation).
- There is no way to say "run all scenarios tagged `payment` because this sprint touches `payment/`" -- change-impact-driven scenario selection is missing.

The brainstorm maps sprint runs to CXDB contexts but does not describe how scenarios are associated with sprint scope.

### Recommendation

1. Add `tags` (distinct from `risk_tags`) as a first-class field for categorization: `tags: [payment, checkout, happy-path]`.
2. Support tag-based selection: `scenario-run --tags=payment` runs all scenarios with that tag.
3. Add `applies_to` field with file path patterns: `applies_to: ["apps/checkout/**", "core/payment/**"]`. Wire into change-impact analysis so modified files auto-select relevant scenarios.
4. Define a `scenario-select <sprint-id>` command that uses change impact + tags to propose a scenario set, which the orchestrator can approve or modify.

---

## 6. Scenario Gaming Is Unaddressed

**Priority: P1**
**Evidence:** No mention of anti-gaming measures in PRD or brainstorm. Dev scenarios are explicitly visible to implementation agents.

### Finding

Dev scenarios are visible to implementation agents by design. This creates a classic teaching-to-the-test problem: agents can optimize for known dev scenarios while producing brittle solutions that fail on holdout or real-world inputs. Specific risks:

- **Overfitting to dev expectations:** An agent reads `expect: "Cart shows 2 items"` and hardcodes item count display rather than implementing proper cart logic.
- **Scenario memorization across sessions:** If agents see the same dev scenarios across multiple sprints, they learn to pattern-match scenario structure rather than solve the underlying problem.
- **Holdout leakage via scoring feedback:** When holdout scores are reported (pass/fail + aggregate satisfaction), agents in subsequent sprints can infer holdout scenario characteristics from the pattern of failures. Over time, this degrades holdout independence.
- **Dev/holdout correlation:** If dev and holdout scenarios are authored from the same spec, they test the same properties. Passing dev reliably predicts passing holdout, which means holdout adds cost without adding signal.

### Recommendation

1. **Rotate dev scenarios:** Periodically promote dev scenarios to holdout and generate new dev scenarios. This prevents memorization.
2. **Holdout score opacity:** Report only aggregate holdout satisfaction (pass/fail + score), never per-scenario results, to implementation agents. Only validation agents and humans see per-scenario holdout breakdowns.
3. **Diversity requirements:** Require that holdout scenarios test different properties or edge cases than dev scenarios, not just the same properties with different inputs.
4. **Canary scenarios:** Include a small number of "canary" scenarios in dev that are intentionally tricky. If an agent passes all canaries perfectly while failing holdout, it suggests overfitting.
5. **Temporal separation:** Holdout scenarios for sprint N should be authored before sprint N begins, not during or after, to prevent contamination from implementation decisions.

---

## Summary

| # | Finding | Priority | Category |
|---|---------|----------|----------|
| 1 | Dev/holdout separation is convention-only, not mechanically enforced | P0 | Integrity |
| 2 | YAML schema lacks support for exact match, structural, negative, and deterministic correctness types | P1 | Expressiveness |
| 3 | No schema versioning strategy for scenario definitions | P1 | Evolution |
| 4 | Scenario authoring requires developer knowledge, not truly externalized | P2 | Usability |
| 5 | No structured tagging or change-impact-driven scenario selection | P2 | Automation |
| 6 | No anti-gaming measures for dev scenario visibility | P1 | Integrity |

## Verdict: SHIP_WITH_FIXES

The scenario bank concept is sound and correctly identified as the keystone for L3 autonomy. The CXDB integration, filesystem layout, and satisfaction scoring design are well-reasoned. However, three issues need resolution before implementation:

**Must fix (blocks ship):**
- P0 #1: Dev/holdout separation needs at least one mechanical enforcement layer (filesystem permissions, encryption, or containerized execution). Convention-only separation in a system designed for autonomous agents is a correctness hole, not a style preference.

**Should fix (fix before holdout scores are used for gating):**
- P1 #2: Add `type` discriminator to expect/rubric entries so deterministic checks bypass LLM judges. Without this, the system will be too expensive and too noisy for production gating.
- P1 #6: Define holdout score opacity rules and dev scenario rotation policy. Without these, holdout independence degrades over time and the validation signal becomes meaningless.

**Can defer to Phase 2+:**
- P1 #3 (schema versioning), P2 #4 (authoring externalization), P2 #5 (tagging/selection) are real gaps but won't block initial implementation.
