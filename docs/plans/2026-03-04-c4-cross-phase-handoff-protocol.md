# C4: Cross-Phase Handoff Protocol — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** iv-1vny
**Goal:** Build handoff contract validation into the Clavain sprint pipeline — define what each stage must produce, validate artifact content (not just existence), and wire into the gate system.

**Architecture:** New Go file `handoff.go` in `os/clavain/cmd/clavain-cli/`. New YAML config `config/handoff-contracts.yaml` defining per-artifact-type content contracts. The `validate-handoff` command parses YAML frontmatter from markdown artifacts, checks section headings and content patterns against contracts, and outputs structured JSON results. Wired into `enforce-gate` as a new `artifact_contract` gate type. Shadow mode by default (warn, don't block).

**Tech Stack:** Go 1.22, gopkg.in/yaml.v3 (already a dependency from C3), clavain-cli subcommand pattern, Go table-driven tests

**Prior Learnings:**
- **Go map iteration non-determinism** (docs/solutions/patterns/go-map-hash-determinism-20260223.md): Sort check results before JSON output for stable, reproducible validation results.
- **Silent API misuse** (docs/solutions/best-practices/silent-api-misuse-patterns-intercore-20260221.md): Use `errors.Is()` not `==` for sentinel errors in validation.

---

### Task 1: Create handoff-contracts.yaml config

**Files:**
- Create: `os/clavain/config/handoff-contracts.yaml`

**Step 1: Write the contracts config file**

Define contracts for all 5 artifact types. Each contract specifies:
- `produced_by` / `consumed_by` — cross-stage linkage
- `frontmatter.required_fields` — required YAML frontmatter keys
- `content.required_sections` — heading patterns to match (regex, h2 level)
- `content.optional_sections` — nice-to-have sections
- `content.min_total_words` — minimum word count threshold
- `content.required_patterns` — regex patterns that must appear in content (for non-markdown artifacts like verdicts)

```yaml
version: "1.0"

contracts:
  brainstorm:
    description: "Problem exploration with research and proposed approaches"
    produced_by: discover
    consumed_by: [design]
    frontmatter:
      required_fields: [artifact_type, bead, stage]
    content:
      required_sections:
        - id: problem_statement
          heading_pattern: "(?i)problem|problem.statement"
          min_words: 50
        - id: research
          heading_pattern: "(?i)research|analysis|current.state"
        - id: approaches
          heading_pattern: "(?i)approach|proposed|options|design"
      optional_sections:
        - id: tradeoffs
          heading_pattern: "(?i)tradeoff|trade.off|comparison"
        - id: open_questions
          heading_pattern: "(?i)open.question|tbd|unresolved"
      min_total_words: 200

  prd:
    description: "Product requirements with features and acceptance criteria"
    produced_by: design
    consumed_by: [design, build]
    frontmatter:
      required_fields: [artifact_type, bead, stage]
    content:
      required_sections:
        - id: summary
          heading_pattern: "(?i)summary|overview|goal|problem"
        - id: features
          heading_pattern: "(?i)feature|requirement|scope"
        - id: acceptance_criteria
          heading_pattern: "(?i)acceptance|criteria|done.when|definition.of.done"
      optional_sections:
        - id: non_goals
          heading_pattern: "(?i)non.?goal|out.of.scope|excluded"
      min_total_words: 300

  plan:
    description: "Implementation plan with tasks and file targets"
    produced_by: design
    consumed_by: [build]
    frontmatter:
      required_fields: [artifact_type, bead, stage]
    content:
      required_sections:
        - id: tasks
          heading_pattern: "(?i)task.\\d|step.\\d|phase.\\d"
          min_count: 1
      optional_sections:
        - id: prior_learnings
          heading_pattern: "(?i)prior.learn|learnings|context"
      required_patterns:
        - pattern: "[A-Za-z_/.-]+\\.[a-z]{1,4}"
          description: "Must reference at least one file path"

  verdict:
    description: "Review verdict from quality gates"
    produced_by: build
    consumed_by: [ship]
    frontmatter:
      required_fields: []
    content:
      required_patterns:
        - pattern: "^TYPE:\\s+(verdict|implementation)"
          description: "Must have TYPE header"
        - pattern: "^STATUS:\\s+(CLEAN|NEEDS_ATTENTION|BLOCKED|ERROR|COMPLETE|PARTIAL|FAILED)"
          description: "Must have STATUS line"
      optional_patterns:
        - pattern: "^MODEL:"
        - pattern: "^TOKENS_SPENT:"

  reflection:
    description: "Sprint learnings and retrospective"
    produced_by: reflect
    consumed_by: []
    frontmatter:
      required_fields: [artifact_type, bead]
    content:
      required_sections:
        - id: learnings
          heading_pattern: "(?i)learning|key.insight|what.learn"
      optional_sections:
        - id: went_well
          heading_pattern: "(?i)went.well|success|win"
        - id: improvements
          heading_pattern: "(?i)improve|next.time|could.better"
      min_total_words: 100
```

**Step 2: Verify YAML syntax**

```bash
cd /home/mk/projects/Sylveste && python3 -c "import yaml; yaml.safe_load(open('os/clavain/config/handoff-contracts.yaml'))"
```

**Step 3: Commit**

```
feat(clavain): add handoff contract definitions for 5 artifact types
```

---

### Task 2: Add handoff types and frontmatter parser to Go

**Files:**
- Create: `os/clavain/cmd/clavain-cli/handoff.go`
- Edit: `os/clavain/cmd/clavain-cli/main.go` (add validate-handoff command)

**Step 1: Write the failing test**

Create `os/clavain/cmd/clavain-cli/handoff_test.go` with tests for:
- `parseFrontmatter()` — extracts YAML frontmatter from markdown content
- `matchSections()` — finds h2 headings matching contract patterns
- `validateContract()` — runs full validation against a contract
- Edge cases: no frontmatter, malformed frontmatter, missing sections, word count below threshold

Test data: create `testdata/handoff-contracts.yaml` (minimal subset), `testdata/artifacts/valid-brainstorm.md`, `testdata/artifacts/invalid-brainstorm.md`, `testdata/artifacts/no-frontmatter.md`.

**Step 2: Implement handoff.go**

Types:

```go
// HandoffContracts is the top-level config/handoff-contracts.yaml.
type HandoffContracts struct {
    Version   string                      `yaml:"version"`
    Contracts map[string]ArtifactContract `yaml:"contracts"`
}

type ArtifactContract struct {
    Description string              `yaml:"description"`
    ProducedBy  string              `yaml:"produced_by"`
    ConsumedBy  []string            `yaml:"consumed_by"`
    Frontmatter FrontmatterContract `yaml:"frontmatter"`
    Content     ContentContract     `yaml:"content"`
}

type FrontmatterContract struct {
    RequiredFields []string `yaml:"required_fields"`
}

type ContentContract struct {
    RequiredSections []SectionContract `yaml:"required_sections"`
    OptionalSections []SectionContract `yaml:"optional_sections"`
    MinTotalWords    int               `yaml:"min_total_words"`
    RequiredPatterns []PatternContract `yaml:"required_patterns"`
    OptionalPatterns []PatternContract `yaml:"optional_patterns"`
}

type SectionContract struct {
    ID             string `yaml:"id"`
    HeadingPattern string `yaml:"heading_pattern"`
    MinWords       int    `yaml:"min_words"`
    MinCount       int    `yaml:"min_count"`
}

type PatternContract struct {
    Pattern     string `yaml:"pattern"`
    Description string `yaml:"description"`
}

// Frontmatter represents parsed YAML frontmatter from a markdown artifact.
type Frontmatter struct {
    ArtifactType string `yaml:"artifact_type"`
    Bead         string `yaml:"bead"`
    Stage        string `yaml:"stage"`
    // Additional fields stored as raw map for extensibility
    Extra map[string]interface{} `yaml:"-"`
}

// HandoffResult is the JSON output of validate-handoff.
type HandoffResult struct {
    ArtifactType    string          `json:"artifact_type"`
    ArtifactPath    string          `json:"artifact_path"`
    ContractVersion string          `json:"contract_version"`
    Result          string          `json:"result"` // "pass", "fail", "warn"
    Checks          []HandoffCheck  `json:"checks"`
    Warnings        []string        `json:"warnings"`
}

type HandoffCheck struct {
    Check    string `json:"check"`
    Result   string `json:"result"` // "pass", "fail", "skip"
    Heading  string `json:"heading,omitempty"`
    Line     int    `json:"line,omitempty"`
    Actual   int    `json:"actual,omitempty"`
    Required int    `json:"required,omitempty"`
    Detail   string `json:"detail,omitempty"`
}
```

Functions:

```go
// parseFrontmatter extracts YAML frontmatter delimited by "---" from markdown content.
// Returns the frontmatter as a raw map and the body (after second ---).
// Returns nil map and full content if no frontmatter found.
func parseFrontmatter(content []byte) (map[string]interface{}, []byte, error)

// countWords counts words in a string (split on whitespace).
func countWords(s string) int

// matchSections scans markdown body for h2 headings matching section contracts.
// Returns a map of section ID → matched heading line number.
func matchSections(body []byte, sections []SectionContract) map[string]int

// validateContract validates artifact content against a contract.
// Returns a HandoffResult with individual check results.
func validateContract(artifactPath string, content []byte, contract ArtifactContract, contractVersion string) HandoffResult

// loadHandoffContracts loads config/handoff-contracts.yaml using the same
// config directory resolution as loadAgencySpec (configDirs()).
func loadHandoffContracts() (*HandoffContracts, error)

// cmdValidateHandoff is the CLI entry point.
// Usage: validate-handoff <artifact_path> [--type=<artifact_type>]
// If --type not given, infers from frontmatter artifact_type field.
func cmdValidateHandoff(args []string) error
```

**Step 3: Register in main.go**

Add to the switch in `main()`:
```go
case "validate-handoff":
    err = cmdValidateHandoff(args)
```

Add to `printHelp()`:
```
Handoff:
  validate-handoff  <artifact_path> [--type=<type>]  Validate artifact against handoff contract
```

**Step 4: Run tests**

```bash
cd /home/mk/projects/Sylveste/os/clavain/cmd/clavain-cli && go test -run TestHandoff -v
```

**Step 5: Commit**

```
feat(clavain): add validate-handoff command with frontmatter parser and contract validation
```

---

### Task 3: Create test data fixtures

**Files:**
- Create: `os/clavain/cmd/clavain-cli/testdata/handoff-contracts.yaml`
- Create: `os/clavain/cmd/clavain-cli/testdata/artifacts/valid-brainstorm.md`
- Create: `os/clavain/cmd/clavain-cli/testdata/artifacts/invalid-brainstorm.md`
- Create: `os/clavain/cmd/clavain-cli/testdata/artifacts/no-frontmatter.md`
- Create: `os/clavain/cmd/clavain-cli/testdata/artifacts/valid-plan.md`
- Create: `os/clavain/cmd/clavain-cli/testdata/artifacts/valid-verdict.txt`

**Step 1: Create minimal test contracts**

A subset of the full contracts — just brainstorm, plan, and verdict — sufficient for unit testing.

**Step 2: Create valid brainstorm fixture**

Full frontmatter + required sections (problem, research, approaches) with enough words to pass min_total_words.

**Step 3: Create invalid brainstorm fixture**

Has frontmatter but missing the "approaches" section and under word count.

**Step 4: Create no-frontmatter fixture**

Valid markdown with correct sections but no YAML frontmatter block.

**Step 5: Create plan and verdict fixtures**

Plan with task headings and file paths. Verdict with TYPE/STATUS headers.

Note: Task 3 should be done together with Task 2 (tests reference these fixtures). Listed separately for clarity but implement alongside Task 2.

---

### Task 4: Wire into gate system

**Files:**
- Edit: `os/clavain/cmd/clavain-cli/phase.go` (enhance `cmdEnforceGate`)

**Step 1: Write the failing test**

In `handoff_test.go`, add `TestEnforceGateArtifactContract` — tests that when a gate of type `artifact_contract` is defined, `enforce-gate` calls `validate-handoff` logic and blocks on failure.

Since `enforce-gate` currently delegates to `ic gate check`, the artifact_contract gate type will be checked *locally* by clavain-cli before the ic call. This means the Go code checks handoff contracts first, then proceeds to ic gates.

**Step 2: Enhance enforce-gate**

Add a pre-check in `cmdEnforceGate` that:
1. Loads handoff contracts
2. Gets the current phase's artifacts from `ic run artifact list`
3. For each artifact, runs `validateContract`
4. In shadow mode (`gate_mode: shadow` from agency-spec defaults): log warnings, continue
5. In enforce mode: return error if any required validation fails

```go
func cmdEnforceGate(args []string) error {
    // ... existing skip-gate and fail-open logic ...

    // NEW: Handoff contract pre-check
    if os.Getenv("CLAVAIN_SKIP_HANDOFF") == "" {
        handoffResult := checkHandoffContracts(beadID, targetPhase)
        if handoffResult != nil {
            for _, r := range handoffResult {
                if r.Result == "fail" {
                    mode := getGateMode() // reads agency-spec defaults.gate_mode
                    if mode == "enforce" {
                        return fmt.Errorf("handoff contract failed for %s: %s", r.ArtifactType, summarizeFailures(r))
                    }
                    // Shadow mode: warn on stderr
                    fmt.Fprintf(os.Stderr, "handoff-contract: WARN: %s validation failed (shadow mode)\n", r.ArtifactType)
                }
            }
        }
    }

    // ... existing ic gate check ...
}
```

**Step 3: Run all tests**

```bash
cd /home/mk/projects/Sylveste/os/clavain/cmd/clavain-cli && go test -v
```

**Step 4: Commit**

```
feat(clavain): wire handoff contract validation into enforce-gate
```

---

### Task 5: Add cross-stage linkage validation

**Files:**
- Edit: `os/clavain/cmd/clavain-cli/handoff.go`

**Step 1: Write the failing test**

Test `validateLinkage()`:
- Valid linkage (all produced_by/consumed_by match agency spec stages) → pass
- Orphaned contract (type produced but never consumed) → warning
- Broken chain (consumed_by references non-existent stage) → fail

**Step 2: Implement validateLinkage**

```go
// validateLinkage checks that handoff contracts are consistent with agency spec stages.
// Returns warnings for orphaned types and errors for broken chains.
func validateLinkage(contracts *HandoffContracts, spec *AgencySpec) []HandoffCheck
```

This function:
1. Loads both `handoff-contracts.yaml` and `agency-spec.yaml`
2. For each contract, checks that `produced_by` is a valid stage name
3. For each contract, checks that each `consumed_by` is a valid stage name
4. Cross-references: the producing stage's `artifacts.produces[]` must include this type
5. Cross-references: each consuming stage's `artifacts.required[]` must include this type

**Step 3: Add `validate-linkage` CLI command**

```go
// cmdValidateLinkage checks contract-to-spec consistency.
// Usage: validate-linkage
func cmdValidateLinkage(args []string) error
```

Register in main.go.

**Step 4: Run tests**

```bash
cd /home/mk/projects/Sylveste/os/clavain/cmd/clavain-cli && go test -run TestLinkage -v
```

**Step 5: Commit**

```
feat(clavain): add cross-stage linkage validation for handoff contracts
```

---

### Task 6: Update skill templates to emit frontmatter

**Files:**
- Edit: `os/clavain/commands/brainstorm.md`
- Edit: `os/clavain/commands/strategy.md`
- Edit: `os/clavain/skills/writing-plans/SKILL.md`
- Edit: `os/clavain/commands/reflect.md`

**Step 1: Add frontmatter emission instructions to brainstorm.md**

In the brainstorm command's output template section, add instruction to emit YAML frontmatter at the top of the brainstorm document:

```markdown
**Document frontmatter:** Every brainstorm document MUST start with this YAML frontmatter block:

\```yaml
---
artifact_type: brainstorm
bead: <bead_id or "none">
stage: discover
---
\```
```

**Step 2: Add frontmatter to strategy.md**

PRD output template gets:
```yaml
---
artifact_type: prd
bead: <bead_id>
stage: design
---
```

**Step 3: Add frontmatter to writing-plans SKILL.md**

Update the "Plan Document Header" section to include frontmatter before the existing header format:
```yaml
---
artifact_type: plan
bead: <bead_id>
stage: design
---
```

**Step 4: Add frontmatter to reflect.md**

Reflection output gets:
```yaml
---
artifact_type: reflection
bead: <bead_id>
stage: reflect
---
```

**Step 5: Commit**

```
feat(clavain): add artifact frontmatter to brainstorm, strategy, plan, and reflect templates
```

---

### Task 7: Build script and integration test

**Files:**
- Edit: `os/clavain/scripts/build-clavain-cli.sh` (no changes needed — compose already added yaml.v3)
- Create: `os/clavain/cmd/clavain-cli/testdata/artifacts/` directory with fixtures (from Task 3)

**Step 1: Verify build succeeds**

```bash
cd /home/mk/projects/Sylveste && bash os/clavain/scripts/build-clavain-cli.sh
```

**Step 2: Run full test suite**

```bash
cd /home/mk/projects/Sylveste/os/clavain/cmd/clavain-cli && go test -v -count=1
```

**Step 3: Smoke test validate-handoff CLI**

```bash
# Test against the brainstorm we just wrote
os/clavain/bin/clavain-cli validate-handoff docs/brainstorms/2026-03-04-c4-cross-phase-handoff-protocol.md --type=brainstorm
```

Note: This brainstorm doesn't have frontmatter yet (it was written before the templates were updated). The validate-handoff command should handle this gracefully — frontmatter_present check fails, but content checks can still run.

**Step 4: Commit**

```
test(clavain): add integration tests and verify build for handoff validation
```

---

## Execution Manifest

Task dependency: Tasks 2+3 together → Task 4 → Task 5 → Task 6 → Task 7. Task 1 is independent (pure config, no Go compilation).

Estimated complexity: C3 (half day). 7 tasks, ~400 lines of new Go code, ~100 lines of YAML config, ~20 lines of template edits per skill.

## Out of Scope

- Kernel-native enforcement (Intercore changes) — future C4.1
- Automatic remediation suggestions
- Content quality scoring beyond word count
- Project-level contract overrides (`.clavain/handoff-contracts.yaml`) — trivial to add later using same merge pattern as agency-spec
