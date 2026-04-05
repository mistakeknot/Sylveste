### Findings Index
- P1 | ERI-1 | "F2: Identity Crosswalk" | Transitive identity closure not addressed — A=B and B=C does not safely imply A=C
- P1 | ERI-2 | "F2: Identity Crosswalk" | Function-level identity via tree-sitter is brittle across language boundaries and refactoring patterns
- P0 | ERI-3 | "F2: Identity Crosswalk" | Body similarity heuristic (>80%) for rename detection will produce false positives at scale
- P2 | ERI-4 | "F2: Identity Crosswalk" | Granularity mismatch between subsystems creates noisy cross-links
- P1 | ERI-5 | "Open Questions" | Entity input parsing (OQ3) is harder than prefix-based routing suggests
- P2 | ERI-6 | "F4: Confidence Scoring + Link Provenance" | Confidence levels conflate match method with match quality
Verdict: needs-changes

## Summary

The identity crosswalk (F2) is the hardest problem in the PRD and the one most likely to determine whether interweave succeeds or fails. The PRD demonstrates awareness of the core challenges — file-level and function-level resolution, rename detection, incremental updates — but underestimates the failure modes that emerge at scale. Entity resolution in heterogeneous systems is the domain where "works in demos, breaks in production" is the norm. The PRD needs stronger guarantees around transitive closure safety, false positive rates for body similarity matching, and granularity mismatch handling.

## Issues Found

### 1. [P1] Transitive identity closure not addressed (ERI-1)

**File**: `docs/prds/2026-04-05-interweave.md`, F2, lines 37-44

The crosswalk maps `(subsystem, subsystem_id) -> canonical_entity_id`. When beads references `src/auth.py` and cass references `src/auth.py::validate_token`, the crosswalk must decide: are these the same entity (file contains function) or different entities (file vs. function)? The PRD specifies "file-level and function-level resolution" but not how containment relationships interact with identity.

More critically: if beads links entity A to entity B (via a bead dependency), and cass links entity B to entity C (via a session touching both), the crosswalk could infer A relates to C transitively. In entity resolution, transitive closure is the #1 source of false equivalences. The HL7 FHIR Master Patient Index explicitly prohibits automatic transitive closure for this reason.

**Failure scenario**: Bead "refactor auth" touches `src/auth.py`. Session S1 touches both `src/auth.py` and `src/db.py` (they were both open). Transitive closure: "refactor auth" relates to `src/db.py`. But the session was doing unrelated work — the auth file and db file were coincidentally in the same session. The "related work" query now returns noise.

**Recommendation**: Add to F2 acceptance criteria: "Identity links are NOT transitively closed by default. Cross-system relationships are established only through explicit evidence (shared identifiers, temporal co-occurrence above threshold, or structural containment). Transitive inference is opt-in and labeled as `confidence: speculative`."

### 2. [P1] Function-level identity via tree-sitter is brittle (ERI-2)

**File**: `docs/prds/2026-04-05-interweave.md`, F2, line 39

"Function-level resolution: tree-sitter AST fingerprinting (canonical signature = file_path + function_name + parameter_types + return_type)"

This signature breaks in several common scenarios:
- **Python**: No declared parameter types or return types in most codebases (duck typing). The signature degenerates to `file_path + function_name`, which is fragile.
- **JavaScript/TypeScript**: Arrow functions, destructured parameters, and overloaded signatures produce different AST shapes for semantically identical functions.
- **Refactoring**: Extract-method refactoring splits one function into two. The original function's signature changes (fewer parameters) and a new function appears. Neither matches the old identity.
- **Cross-file moves**: Moving a function between files changes `file_path`, breaking the signature.

The PRD acknowledges rename detection (line 40: "body similarity heuristic >80%") but the core signature itself is too fragile for the claimed resolution.

**Recommendation**: Use a layered identity strategy: (1) exact signature match (highest confidence), (2) same function name + same file (high confidence), (3) body fingerprint (content-addressed hash of normalized AST, ignoring comments and whitespace) for cross-file and cross-rename detection (medium confidence). The PRD should specify which identity method is used and at what confidence level, not a single canonical signature.

### 3. [P0] Body similarity heuristic >80% will produce false positives at scale (ERI-3)

**File**: `docs/prds/2026-04-05-interweave.md`, F2, line 40

"Function rename/move detection: body similarity heuristic (>80% match links identities)"

An 80% body similarity threshold is dangerously low for identity linking. In a codebase with 60+ plugins:
- Boilerplate functions (error handlers, logging wrappers, config loaders) will match each other at >80% even though they are distinct entities
- Generated code (protobuf stubs, ORM models) will have many near-identical functions
- Copy-paste-modify patterns (common in plugin ecosystems) produce functions with >80% similarity that are intentionally different

In the LEI (Legal Entity Identifier) system, a similar fuzzy matching threshold caused 3% of entities to be falsely merged, requiring manual review of 50,000+ records. At interweave's scale (thousands of functions across 60+ plugins), even a 1% false positive rate produces dozens of phantom identity links.

**Failure scenario**: `interweave/pluginA/src/handler.py::handle_request` and `interweave/pluginB/src/handler.py::handle_request` are 85% similar (same boilerplate, different business logic). The crosswalk links them as the same entity. Now every query about pluginA's handler returns pluginB's sessions and beads. Agent makes decisions based on wrong context.

**Recommendation**: Raise the threshold to >95% for automatic linking (confirmed confidence). Links in the 80-95% range should be `confidence: probable` and excluded from default queries (per F4's "default query filter excludes speculative links"). Add to F2: "Body similarity matches are never `confidence: confirmed` — they are `probable` at best. Only exact signature matches or explicit human confirmation earn `confirmed` status."

### 4. [P2] Granularity mismatch creates noisy cross-links (ERI-4)

**File**: `docs/prds/2026-04-05-interweave.md`, F2 + F3

Beads tracks work at epic/story level ("refactor auth module"). Cass tracks sessions ("session S1 touched files X, Y, Z"). Code entities exist at file/function/line level. The crosswalk must bridge these granularities, but the PRD doesn't specify how.

When bead "refactor auth module" mentions `src/auth/`, should the crosswalk link it to:
- The directory entity? (coarse)
- Every file in the directory? (noisy)
- Every function in every file? (explosion)

The F5 query `related-work <entity>` would return very different results depending on this choice.

**Recommendation**: Add a "containment hierarchy" concept to F1: Directory contains Files, Files contain Functions. Cross-granularity links traverse containment — a bead about `src/auth/` links to the directory entity, and queries can optionally expand to contained entities. This is an explicit design decision, not something to leave to implementation.

### 5. [P1] Entity input parsing harder than prefix-based routing (ERI-5)

**File**: `docs/prds/2026-04-05-interweave.md`, Open Question 3, lines 143

"Likely: prefix-based routing (paths contain `/`, beads contain `-`, sessions are hex strings)"

This heuristic breaks in common cases:
- `auth-middleware` — contains `-`, looks like a bead ID, but is a function name
- `a1b2c3d4` — is it a session ID or a git short SHA?
- `src/main.py::process` — is it a file path (contains `/`) or a qualified function name?
- Bead IDs in this project use the format `sylveste-XXXX` (e.g., `sylveste-46s`), which also matches kebab-case function names

**Recommendation**: Promote Open Question 3 to an acceptance criterion in F5: "Entity input parsing uses ordered probing: (1) exact match in crosswalk (O(1) lookup), (2) structural parsing (qualified names contain `::`, paths contain `/` and exist on disk, bead IDs match `[project]-[alphanum]` pattern), (3) ambiguous inputs return multiple candidates with type labels for agent selection." The `--type=` override should be the documented escape hatch, not the afterthought.

### 6. [P2] Confidence levels conflate method with quality (ERI-6)

**File**: `docs/prds/2026-04-05-interweave.md`, F4, lines 67-68

"Confidence levels: confirmed (deterministic match), probable (structural match), speculative (temporal/embedding)"

This maps confidence directly to method type: deterministic=confirmed, structural=probable, temporal=speculative. But a structural match can be highly confident (same file path + same function name across two systems) and a deterministic match can be wrong (beads and cass both reference `src/auth.py` but one means the old version and the other means the current version).

**Recommendation**: Separate method from confidence. A link has both a `method` (how it was established) and a `confidence` (how likely it is correct). Methods contribute to confidence but don't determine it. A structural match with 3 corroborating signals is more confident than a deterministic match with 1 signal. This avoids the anti-pattern where agents learn "ignore everything labeled speculative" and miss valid temporal correlations.

## Improvements

1. **Add a "crosswalk health" metric to F7.** Track: total entities, % with confirmed identity, % with only speculative links, % with zero cross-system links (orphans). This makes crosswalk quality visible and measurable.

2. **Specify the dedup detection algorithm (F2 line 44).** "Flag when two canonical entities likely refer to the same thing" — but by what criteria? Suggest: same file path with different function names (potential rename), same function name in different files (potential move), or high body similarity below the auto-link threshold.

3. **Consider a "link decay" mechanism.** Identity links established via temporal co-occurrence (speculative) should lose confidence over time if not re-confirmed. A session from 6 months ago touching two files is weaker evidence than a session from yesterday. The TTL in F4 (staleness detection) applies to relationships but not to the identity links themselves.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 6 (P0: 1, P1: 3, P2: 2)
SUMMARY: The identity crosswalk is the riskiest component — the 80% body similarity threshold will produce false positives at scale (P0), transitive closure is unaddressed, and function-level identity is more brittle than the PRD acknowledges.
---
<!-- flux-drive:complete -->
