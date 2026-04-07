### Findings Index
- P1 | ARCH-1 | "Write-Back Mechanism" | AgMoDB has no write API — entire design depends on unbuilt infrastructure
- P1 | ARCH-2 | "FluxBench Metrics" | Claude baseline as single reference creates tight coupling and circular dependency
- P1 | ARCH-3 | "Drift Detection" | No reconciliation between model-registry.yaml and AgMoDB as dual sources of truth
- P2 | ARCH-4 | "Write-Back Mechanism" | POST /api/fluxbench/report is interflux-specific — should be generic external benchmark ingest
- P2 | ARCH-5 | "Proactive Surfacing" | SessionStart hook creates runtime dependency on interrank MCP availability
- P2 | ARCH-6 | "Drift Detection" | Sample-based and trigger-based drift share no coordination — could double-qualify
Verdict: needs-changes

### Summary

The brainstorm describes a well-motivated closed feedback loop, but the architecture has three structural issues: (1) it depends on an AgMoDB write API that doesn't exist yet, making the entire design speculative without a feasibility check; (2) the local model-registry.yaml and AgMoDB become competing sources of truth with no reconciliation strategy; and (3) the API endpoint is designed specifically for interflux rather than as a generic external benchmark ingest, limiting reuse and creating unnecessary coupling between interflux and AgMoDB internals.

### Issues Found

1. **P1 — ARCH-1: AgMoDB write API doesn't exist**. The brainstorm acknowledges "AgMoDB currently has no public write API — needs to be built" in Open Questions, but the entire architecture — write-back, drift response, proactive surfacing — depends on this endpoint. This isn't an open question; it's a blocking prerequisite. The `externalBenchmarkScores` table exists for read (34+ scrapers write to it), but the ingest path for those scrapers is internal (git-committed JSONL files processed by AgMoDB's build pipeline, not a REST API). The brainstorm assumes a REST endpoint that would be a new capability for AgMoDB. Without confirming AgMoDB maintainers will accept external write access, this is architecture built on an unvalidated assumption.

2. **P1 — ARCH-2: Claude baseline creates circular dependency**. Three of four core metrics (finding-recall, severity-accuracy, persona-adherence) and one extended metric (disagreement-rate) use Claude as the reference baseline. This creates a tight coupling: if Claude's behavior changes (model update, system prompt change, safety filter adjustment), all FluxBench scores shift — not because candidates changed, but because the measuring stick moved. Worse, interflux already uses Claude as its primary review agent. The system that selects models is also the system that defines what "correct" means. This is a circular dependency that undermines the independence of the benchmark.

3. **P1 — ARCH-3: Dual source of truth — model-registry.yaml vs AgMoDB**. interflux currently maintains `model-registry.yaml` as the local source of truth for qualified models, their status, and configuration. FluxBench writes scores to AgMoDB. The brainstorm's weekly schedule (step 4) says "Update model-registry.yaml" but doesn't specify how AgMoDB scores and registry entries reconcile. Which is authoritative? If a model is qualified in AgMoDB but not in the registry, does it get used? If the registry says "qualifying" but AgMoDB has passing scores, what happens? This dual-write pattern is a classic consistency bug waiting to happen.

4. **P2 — ARCH-4: Endpoint should be generic, not interflux-specific**. `POST /api/fluxbench/report` is named for interflux's benchmark suite. But the brainstorm's own Open Questions asks "Should other tools beyond interflux be able to report FluxBench results?" The answer should be yes, and the API should reflect that: `POST /api/external-benchmarks/report` with `suite: "fluxbench"` as a field. This matches AgMoDB's existing `externalBenchmarkScores` model and avoids creating per-consumer endpoints.

5. **P2 — ARCH-5: SessionStart hook creates hard dependency on interrank**. The proactive surfacing hook queries interrank on every session start. If interrank's MCP server is slow or unavailable, this blocks session startup. The brainstorm says "zero-cost awareness (one MCP query)" but MCP queries have latency and failure modes. This should be a best-effort check with a hard timeout (e.g., 2 seconds) and silent degradation.

6. **P2 — ARCH-6: Dual drift detection lacks coordination**. Sample-based drift (1-in-10 reviews) and version-triggered drift run independently. A model could be flagged for requalification by the sample path while simultaneously being triggered by a version bump, resulting in two concurrent qualification runs for the same model. There's no deduplication or coordination mechanism described.

### Improvements

1. **IMP-1: Add a feasibility spike for AgMoDB write access** before committing to this architecture. Determine whether AgMoDB accepts external writes via API or only via its build pipeline. If API isn't feasible, design a JSONL-commit alternative.

2. **IMP-2: Define a single source of truth for model status**. Either model-registry.yaml is authoritative (and reads from AgMoDB on startup) or AgMoDB is authoritative (and model-registry.yaml becomes a cache). Document the ownership clearly.

3. **IMP-3: Add a "baseline version" field to FluxBench reports** so scores can be invalidated when the Claude baseline model changes. This decouples baseline drift from candidate drift.

4. **IMP-4: Add a qualification lock** — before starting a qualification run for a model, check if one is already in progress. This prevents the dual-drift coordination issue.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 6 (P0: 0, P1: 3, P2: 3)
SUMMARY: Architecture is well-motivated but depends on unbuilt AgMoDB infrastructure, creates a dual source of truth with model-registry.yaml, and has a circular dependency on Claude as both the review engine and the benchmark reference.
---
<!-- flux-drive:complete -->
