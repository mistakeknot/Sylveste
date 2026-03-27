---
artifact_type: prd
bead: Sylveste-rp5
stage: design
status: superseded
note: "Rust fork completed (Sylveste-rp5 CLOSED) but superseded by Go rewrite due to license contamination"
---
# PRD: Skaffen v0.1 — Fork pi_agent_rust, Rebrand, CI Green

## Problem
Sylveste needs a sovereign agent runtime (Skaffen) where OODARC, evidence pipelines, and phase gates are architectural primitives. pi_agent_rust is the best fork base (Rust, 67MB memory, 3857+ tests, Elm TUI, capability-gated extensions) but ships with pi/claude branding and depends on unpublished custom crates we don't control.

## Solution
Hard-fork pi_agent_rust into the standalone Skaffen repo. Strip branding, vendor custom deps, add a minimal OODARC insertion point, establish performance baselines, and get CI green. This is the mechanical foundation for v0.2+ architectural changes.

## Features

### F1: Fork + Rebrand
**What:** Copy pi_agent_rust source into the Skaffen repo, rename the binary to `skaffen`, strip all pi/claude branding from user-visible strings.
**Acceptance criteria:**
- [ ] All source files copied from research/pi_agent_rust/ to the Skaffen repo
- [ ] Binary name is `skaffen` in Cargo.toml `[[bin]]` section
- [ ] `cargo build` produces a `skaffen` binary (debug + release)
- [ ] No user-visible strings contain "pi", "claude", or "anthropic" (grep verify)
- [ ] README.md updated with Skaffen identity and Sylveste context
- [ ] License file preserved/updated per upstream terms

### F2: Vendor Custom Dependencies
**What:** Copy asupersync, charmed_rust, rich_rust, and sqlmodel_rust into `vendor/` as workspace crates, update Cargo.toml path dependencies.
**Acceptance criteria:**
- [ ] `vendor/asupersync/`, `vendor/charmed_rust/`, `vendor/rich_rust/`, `vendor/sqlmodel_rust/` directories exist with full source
- [ ] Root Cargo.toml declares workspace members for vendored crates
- [ ] All `[dependencies]` pointing to these crates use `path = "vendor/<name>"` instead of git/registry
- [ ] `cargo build` resolves all vendored deps without network access
- [ ] No git submodules or external git refs for vendored crates

### F3: OODARC Coupling Spike
**What:** Define an `OodarcHook` trait with OODARC phase lifecycle methods and wire a no-op implementation at the agent turn boundary, behind a `skaffen-oodarc` feature flag.
**Acceptance criteria:**
- [ ] `src/oodarc.rs` (or similar) defines `OodarcHook` trait with methods: `on_observe`, `on_orient`, `on_decide`, `on_act`, `on_reflect`, `on_compound`
- [ ] `NoopOodarcHook` struct implements the trait with empty bodies
- [ ] Hook is called at the turn boundary in the agent loop (identified insertion point)
- [ ] Entire feature gated behind `skaffen-oodarc` Cargo feature flag
- [ ] With flag disabled: zero behavioral change, all existing tests pass
- [ ] With flag enabled: no-op hook runs, all existing tests still pass
- [ ] Brief doc comment explaining the spike's purpose and v0.2 intent

### F4: Benchmark Baselines
**What:** Establish performance baselines for memory usage and session load time using criterion benchmarks.
**Acceptance criteria:**
- [ ] `benches/` directory with criterion benchmark harness
- [ ] Benchmark: cold start memory usage (RSS after init, before first turn)
- [ ] Benchmark: session load time (JSONL parse + SQLite index for a sample session)
- [ ] Baseline numbers recorded in `docs/benchmarks.md` or similar
- [ ] `cargo bench` runs without errors
- [ ] Numbers comparable to pi_agent_rust research doc (67MB memory, sub-100ms startup)

### F5: CI Pipeline
**What:** GitHub Actions workflow for build, test, clippy, and fmt checks.
**Acceptance criteria:**
- [ ] `.github/workflows/ci.yml` with jobs: build, test, clippy, rustfmt
- [ ] Targets: stable Rust on Linux x86_64 (minimum viable matrix)
- [ ] `cargo test` runs all tests (verify count matches pi_agent_rust baseline)
- [ ] `cargo clippy -- -D warnings` passes
- [ ] `cargo fmt --check` passes
- [ ] CI triggers on push to main and PRs
- [ ] Badge in README.md showing CI status

## Non-goals
- No OODARC behavioral changes (v0.2)
- No phase-aware tool gating (v0.2)
- No Intercore/Interspect integration (v0.3)
- No provider changes or ClaudeCodeProvider (v0.1 keeps existing providers)
- No TUI modifications
- No macOS/Windows CI (Linux-first)
- No crates.io publishing

## Dependencies
- **pi_agent_rust source:** Available at `research/pi_agent_rust/` in the Sylveste monorepo
- **Custom crate sources:** asupersync, charmed_rust, rich_rust, sqlmodel_rust (need to locate source repos or extract from pi_agent_rust's Cargo.lock)
- **Skaffen GitHub repo:** `github.com/mistakeknot/Skaffen` (exists, currently docs-only)
- **Rust toolchain:** 1.85+ (matching pi_agent_rust's edition 2024)

## Open Questions
- **License terms:** Need to verify pi_agent_rust's license allows forking. Check before any public push.
- **Custom crate sources:** Where are asupersync/charmed_rust/etc. hosted? If only in pi_agent_rust's Cargo.lock as git deps, we need to clone those repos separately.
- **Test infrastructure deps:** Some tests may depend on pi-specific test fixtures or external services. Need to audit after fork.
- **Nightly Rust:** Some pi_agent_rust features may require nightly. Assess during F1.
