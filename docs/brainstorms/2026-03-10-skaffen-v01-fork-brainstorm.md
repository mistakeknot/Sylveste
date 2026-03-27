---
artifact_type: brainstorm
bead: Sylveste-rp5
stage: discover
status: superseded
superseded_by: docs/brainstorms/2026-03-11-skaffen-go-rewrite-brainstorm.md
---

# Skaffen v0.1: Fork pi_agent_rust, Rebrand, CI Green

**Bead:** Sylveste-rp5
**Parent epic:** Sylveste-6qb (Skaffen sovereign agent runtime)
**Epic brainstorm:** docs/brainstorms/2026-03-10-skaffen-sovereign-agent-brainstorm.md (D11)

## What We're Building

Fork pi_agent_rust into the standalone Skaffen GitHub repo. Strip pi branding, rename the binary to `skaffen`, vendor critical custom dependencies, add a minimal OODARC coupling spike, establish benchmark baselines, and get CI green with all tests passing.

## Why This Approach

D11 from the epic brainstorm decided on a hard fork with per-release-tag upstream review. v0.1 is the mechanical foundation — get the code compiling and tested under the Skaffen name before any architectural changes in v0.2+.

Vendoring custom deps (asupersync, charmed_rust, rich_rust, sqlmodel_rust) gives us control over the dependency chain from day one. These crates are not on crates.io and are tightly coupled to the author's ecosystem. Vendoring avoids upstream breakage and lets us patch freely.

## Key Decisions

### D1: Repo layout — Standalone Skaffen repo
The Skaffen GitHub repo (`github.com/mistakeknot/Skaffen`) gets all Rust source. `os/Skaffen/` in the Sylveste monorepo remains a docs-only anchor, matching the Clavain pattern. No git submodules.

### D2: Dependencies — Vendor critical deps
Copy asupersync, charmed_rust, rich_rust, and sqlmodel_rust into the Skaffen repo as vendored workspace crates (e.g., `vendor/asupersync/`). Keeps all original deps functional but under our control. Replace with standard crates (tokio, ratatui, etc.) incrementally in later versions.

### D3: OODARC spike — Minimal trait + no-op
Define an `OodarcHook` trait with phase lifecycle methods (`on_observe`, `on_orient`, `on_decide`, `on_act`, `on_reflect`, `on_compound`). Wire a no-op implementation at the turn boundary behind a `skaffen-oodarc` feature flag. Proves the insertion point works without changing behavior. Data for v0.2.

## Acceptance Criteria

1. `cargo build` passes (debug + release)
2. `cargo test` passes — all existing tests green
3. Binary is named `skaffen`, not `claude` or `pi`
4. All pi/claude branding stripped from user-visible strings
5. Custom deps vendored as workspace crates
6. `OodarcHook` trait defined, no-op wired behind feature flag
7. Benchmark baselines recorded (memory usage, session load time)
8. CI pipeline running in GitHub Actions (build, test, clippy, fmt)

## Open Questions

- **Test count verification:** Research doc says 279 test files / 3857+ tests. Need to verify exact count after fork — some tests may reference pi-specific infrastructure.
- **CI matrix:** Which Rust versions and platforms to target? Minimum: stable + nightly on Linux x86_64. macOS and Windows can come later.
- **License:** pi_agent_rust's license terms for forking. Need to check before publishing.
- **Benchmark tooling:** Use `criterion` (standard) or pi's existing bench setup? Criterion is more portable.
