---
artifact_type: reflection
bead: sylveste-0zr
stage: reflect
---

# Ockham F1+F2: Intent CLI + Scoring Package — Reflection

## What happened

Built the first real code in Ockham: 6 Go packages (halt, intent, authority, anomaly, scoring, governor), a cobra CLI with 5 subcommands, and 24 tests with 100% scoring coverage. The work covered two beads (sylveste-0zr, sylveste-qd1) in a single sprint. Total review surface: 5 agents across 2 passes (3 plan review + 2 quality gates).

## Key learnings

### 1. Stub packages should live in their destination from day one

The plan originally placed `AuthorityState` and `AnomalyState` stubs in `scoring/types.go`. The architecture review caught that this would invert the dependency direction when Wave 2-3 fills in real behavior — scoring would need to import authority, breaking the "scoring imports nothing" invariant. Moving stubs to `internal/authority/` and `internal/anomaly/` as their own packages means the import graph is correct before any behavior is added. Cost to fix now: 5 minutes. Cost to fix after Wave 2 callers accumulate: much higher.

### 2. Plan reviews catch structural errors; QG catches implementation bugs

The plan review found 6 P1s — all structural (error handling contracts, dependency direction, API design). The QG review found 4 P1s — all implementation-level (nil map guard ordering, missing validate-before-save, silent error discard, stale go.mod). Neither review type subsumes the other. Both passes were necessary and caught genuinely different categories of error.

### 3. `errors.Join` (Go 1.20+) replaces the `[]error` anti-pattern

The plan originally had `Validate` returning `[]error`, forcing every caller to loop over the slice. Three reviewers independently flagged this. `errors.Join` produces a single error with newline-separated messages, and callers just check `err != nil`. This is now the project standard for multi-error validation.

### 4. Validate-before-save must be on every write path, not just some

The `--freeze` path called `Validate()` before `Save()`, but the `--theme` path did not. The QG correctness review caught this: a user could set `budget=1.5` and persist an invalid file. The fix was adding `Validate` to the theme path too. Lesson: when a validation guard exists on one write path, audit all write paths.

### 5. Go CLI at this scale is straightforward

Go 1.24 + cobra + yaml.v3 is a clean stack for a headless CLI governor. The entire implementation (6 packages, 5 commands, 24 tests) was written and reviewed in one session. The dependency graph (halt → intent/authority/anomaly → scoring → governor) enforces clean layering naturally through Go's import rules.

## What worked well

- Skipping brainstorm/strategy (parent bead already did them) saved significant time
- TDD-style task structure (test → implement → verify) caught issues early
- The "expanding cone" dependency graph made each package independently testable
- Atomic file write with `os.CreateTemp` + `os.Rename` is a clean pattern

## What to do differently

- Run `go mod tidy` as part of the module setup task, not as a post-hoc fix
- Include validate-before-save as a plan-level invariant (add to Must-Haves section)
- For Wave 2-3: the `Governor.New()` positional args pattern will need a config struct when authority and anomaly stores are added
