---
artifact_type: plan
bead: Demarch-rp5
stage: design
requirements:
  - "F1: Fork + rebrand pi_agent_rust to skaffen"
  - "F2: Vendor custom dependencies"
  - "F3: OODARC coupling spike"
  - "F4: Benchmark baselines"
  - "F5: CI pipeline"
---
# Skaffen v0.1 Fork Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-rp5
**Goal:** Fork pi_agent_rust into the standalone Skaffen repo with all tests passing, custom deps vendored, and CI green.

**Architecture:** Copy pi_agent_rust source into the existing Skaffen GitHub repo (github.com/mistakeknot/Skaffen). Rename binary from `pi` to `skaffen`, strip branding, vendor 4 custom crate families as workspace members under `vendor/`. Add a no-op OODARC hook at the agent turn boundary behind a feature flag. Establish criterion benchmark baselines and a GitHub Actions CI pipeline.

**Tech Stack:** Rust 1.85+ (edition 2024), criterion benchmarks, GitHub Actions CI, charmed_rust TUI, asupersync async runtime, sqlmodel_rust ORM.

---

## Must-Haves

**Truths** (observable behaviors):
- `cargo build --release` produces a `skaffen` binary
- `cargo test` passes all existing tests (3857+ baseline)
- `grep -ri "pi_agent\|\"pi\"" src/` returns zero user-facing branding hits
- `cargo bench` runs criterion benchmarks and produces baseline numbers
- GitHub Actions CI passes on push to main

**Artifacts** (files that must exist):
- `Cargo.toml` with `[[bin]] name = "skaffen"` and `[patch.crates-io]` pointing to `vendor/`
- `vendor/asupersync/`, `vendor/charmed_rust/`, `vendor/rich_rust/`, `vendor/sqlmodel_rust/` — complete crate sources
- `src/oodarc.rs` exports `OodarcHook` trait + `NoopOodarcHook`
- `.github/workflows/ci.yml` with build+test+clippy+fmt jobs
- `docs/benchmarks.md` with baseline numbers

**Key Links** (where breakage causes cascading failures):
- `Cargo.toml` `[patch.crates-io]` must match exact vendored crate paths — wrong path = build failure for all 60+ deps
- `src/agent.rs` OODARC hook call must be inside the `skaffen-oodarc` feature gate — ungated = behavior change in default builds
- CI workflow must set `VCR_MODE=playback` — missing = tests try real API calls and fail

---

### Task 1: Clone pi_agent_rust source into Skaffen repo

**Files:**
- Modify: `os/Skaffen/` (the Skaffen repo root — this is a separate git repo)
- Source: `research/pi_agent_rust/`

**Context:** `os/Skaffen/` is a standalone git repo (remote: github.com/mistakeknot/Skaffen) currently containing only docs. We need to copy ALL source files from `research/pi_agent_rust/` into it, preserving directory structure. The existing docs in Skaffen stay.

**Step 1: Inventory the source repo**

```bash
cd os/Skaffen
ls -la  # Verify current state: docs only, .git present
```

**Step 2: Copy source tree from pi_agent_rust**

Copy everything except `.git/`, `target/`, and files that conflict with existing Skaffen docs:

```bash
# From Demarch root
rsync -av --exclude='.git' --exclude='target/' --exclude='README.md' \
  --exclude='LICENSE' --exclude='CLAUDE.md' --exclude='AGENTS.md' \
  research/pi_agent_rust/ os/Skaffen/
```

We keep Skaffen's existing README.md, LICENSE (MIT), CLAUDE.md, and AGENTS.md. Everything else (src/, tests/, benches/, Cargo.toml, Cargo.lock, .github/) comes from pi_agent_rust.

**Step 3: Verify the copy**

```bash
ls os/Skaffen/src/agent.rs     # Core agent loop
ls os/Skaffen/Cargo.toml       # Build config
ls os/Skaffen/tests/            # Test directory
ls os/Skaffen/benches/          # Benchmark directory
```

**Step 4: Commit the raw copy**

```bash
cd os/Skaffen
git add -A
git commit -m "chore: copy pi_agent_rust source (pre-rebrand)"
```

<verify>
- run: `ls os/Skaffen/src/agent.rs`
  expect: exit 0
- run: `ls os/Skaffen/Cargo.toml`
  expect: exit 0
- run: `find os/Skaffen/src -name "*.rs" | wc -l`
  expect: contains "7"
</verify>

---

### Task 2: Rename binary and strip pi branding

**Files:**
- Modify: `os/Skaffen/Cargo.toml` (binary name, package name, metadata)
- Modify: `os/Skaffen/src/main.rs` (version string, help text)
- Modify: `os/Skaffen/src/cli.rs` (clap app name, about text)
- Modify: `os/Skaffen/src/config.rs` (config directory name, app name)
- Modify: `os/Skaffen/src/version_check.rs` (GitHub release URL)
- Modify: `os/Skaffen/src/doctor.rs` (binary name in diagnostics)

**Context:** The pi_agent_rust binary is named `pi`. User-visible branding references "pi" in help text, config paths, error messages, and version checks. We rename to `skaffen` everywhere user-visible. Internal code identifiers (struct names, module names) stay as-is for now — mass renaming internal code risks breaking 3857+ tests.

**Step 1: Update Cargo.toml**

In `os/Skaffen/Cargo.toml`:
- Change `name = "pi"` → `name = "skaffen"` (under `[package]`)
- Change `[[bin]] name = "pi"` → `[[bin]] name = "skaffen"`
- Change `[lib] name = "pi"` → `[lib] name = "skaffen"`
- Update `repository` → `"https://github.com/mistakeknot/Skaffen"`
- Update `homepage` → `"https://github.com/mistakeknot/Skaffen"`
- Update `description` to reference Skaffen/Demarch

**Step 2: Update CLI help text**

In `src/cli.rs`, find the clap `App::new("pi")` or `#[command(name = "pi")]` and change to `"skaffen"`. Update the `about` text to describe Skaffen.

**Step 3: Update config directory**

In `src/config.rs`, find where the config directory is determined (likely `~/.pi/` or similar). Change to `~/.skaffen/`. Search for string literals containing "pi" that reference directories or file paths.

**Step 4: Update version check URL**

In `src/version_check.rs`, change the GitHub releases URL from the pi_agent_rust repo to `mistakeknot/Skaffen`.

**Step 5: Update doctor diagnostics**

In `src/doctor.rs`, change binary name references from "pi" to "skaffen" in diagnostic messages.

**Step 6: Grep verify — no user-facing pi branding remains**

```bash
cd os/Skaffen
# Check for "pi_agent" and standalone "pi" in user-facing contexts
grep -rn '"pi"' src/ --include="*.rs" | grep -v test | grep -v "// " | head -20
grep -rn 'pi_agent' src/ --include="*.rs" | grep -v test | head -20
```

Review each hit. Internal struct/function names are OK. User-visible strings (help text, error messages, file paths) must be changed.

**Step 7: Commit rebranding**

```bash
git add -A
git commit -m "feat: rebrand pi to skaffen (binary, CLI, config paths)"
```

<verify>
- run: `grep -c '[[bin]]' os/Skaffen/Cargo.toml`
  expect: exit 0
- run: `grep 'name = "skaffen"' os/Skaffen/Cargo.toml`
  expect: contains "skaffen"
</verify>

---

### Task 3: Vendor custom dependencies

**Files:**
- Create: `os/Skaffen/vendor/asupersync/` (clone from github.com/Dicklesworthstone/asupersync)
- Create: `os/Skaffen/vendor/charmed_rust/` (clone from github.com/Dicklesworthstone/charmed_rust — workspace with 4 crates)
- Create: `os/Skaffen/vendor/rich_rust/` (clone from github.com/Dicklesworthstone/rich_rust)
- Create: `os/Skaffen/vendor/sqlmodel_rust/` (clone from github.com/Dicklesworthstone/sqlmodel_rust — workspace with 2 crates)
- Modify: `os/Skaffen/Cargo.toml` (add `[patch.crates-io]` section)

**Context:** pi_agent_rust depends on 4 custom crate families by `Dicklesworthstone`, published on crates.io. The Cargo.toml already has a commented-out `[patch.crates-io]` section (lines 220-230) showing the expected local paths. We clone these repos into `vendor/` and uncomment/adjust the patch section.

**Step 1: Clone custom deps (shallow, no .git)**

```bash
cd os/Skaffen
mkdir -p vendor

# Clone each dep (depth=1 for space, remove .git after)
git clone --depth=1 https://github.com/Dicklesworthstone/asupersync vendor/asupersync
rm -rf vendor/asupersync/.git

git clone --depth=1 https://github.com/Dicklesworthstone/charmed_rust vendor/charmed_rust
rm -rf vendor/charmed_rust/.git

git clone --depth=1 https://github.com/Dicklesworthstone/rich_rust vendor/rich_rust
rm -rf vendor/rich_rust/.git

git clone --depth=1 https://github.com/Dicklesworthstone/sqlmodel_rust vendor/sqlmodel_rust
rm -rf vendor/sqlmodel_rust/.git
```

**Step 2: Verify vendored crate structure**

```bash
# asupersync: single crate
ls vendor/asupersync/Cargo.toml

# charmed_rust: workspace with 4 crates
ls vendor/charmed_rust/crates/bubbletea/Cargo.toml
ls vendor/charmed_rust/crates/lipgloss/Cargo.toml
ls vendor/charmed_rust/crates/bubbles/Cargo.toml
ls vendor/charmed_rust/crates/glamour/Cargo.toml

# rich_rust: single crate
ls vendor/rich_rust/Cargo.toml

# sqlmodel_rust: workspace with 2 crates
ls vendor/sqlmodel_rust/crates/sqlmodel-core/Cargo.toml
ls vendor/sqlmodel_rust/crates/sqlmodel-sqlite/Cargo.toml
```

**Step 3: Update Cargo.toml with [patch.crates-io]**

Uncomment and adjust the existing `[patch.crates-io]` section in Cargo.toml:

```toml
[patch.crates-io]
asupersync = { path = "vendor/asupersync" }
rich_rust = { path = "vendor/rich_rust" }
charmed-bubbletea = { path = "vendor/charmed_rust/crates/bubbletea" }
charmed-lipgloss = { path = "vendor/charmed_rust/crates/lipgloss" }
charmed-bubbles = { path = "vendor/charmed_rust/crates/bubbles" }
charmed-glamour = { path = "vendor/charmed_rust/crates/glamour" }
sqlmodel-core = { path = "vendor/sqlmodel_rust/crates/sqlmodel-core" }
sqlmodel-sqlite = { path = "vendor/sqlmodel_rust/crates/sqlmodel-sqlite" }
```

**Step 4: Test the build**

```bash
cd os/Skaffen
cargo check 2>&1 | tail -20
```

If there are version mismatches between the crates.io versions in `[dependencies]` and the vendored source, adjust the vendored Cargo.toml versions to match what the main Cargo.toml expects.

**Step 5: Commit vendored deps**

```bash
git add -A
git commit -m "chore: vendor asupersync, charmed_rust, rich_rust, sqlmodel_rust"
```

<verify>
- run: `ls os/Skaffen/vendor/asupersync/Cargo.toml`
  expect: exit 0
- run: `ls os/Skaffen/vendor/charmed_rust/crates/bubbletea/Cargo.toml`
  expect: exit 0
- run: `grep 'patch.crates-io' os/Skaffen/Cargo.toml`
  expect: contains "patch.crates-io"
</verify>

---

### Task 4: Get cargo build passing

**Files:**
- Modify: Various `os/Skaffen/src/*.rs` (fix any compilation errors from rename)
- Modify: `os/Skaffen/Cargo.toml` (fix any dep issues)

**Context:** After renaming the package and vendoring deps, there will likely be compilation errors. This task is about iterating until `cargo build` passes. Common issues: `use pi::` imports need to become `use skaffen::`, crate name references in macros, build scripts referencing the old name.

**Step 1: Attempt a build**

```bash
cd os/Skaffen
cargo build 2>&1 | head -50
```

**Step 2: Fix `use pi::` imports**

The lib is renamed from `pi` to `skaffen`, so any `use pi::` or `extern crate pi` references need updating:

```bash
grep -rn 'use pi::' src/ tests/ benches/ | head -20
grep -rn 'extern crate pi' src/ tests/ benches/ | head -20
```

Replace all with `use skaffen::` / `extern crate skaffen`.

**Step 3: Fix any other compilation errors**

Iterate: `cargo build`, read errors, fix, repeat. Common patterns:
- String references to crate name in `env!("CARGO_PKG_NAME")`  — these auto-update
- Build script (`build.rs`) references
- Test fixtures that import the library crate

**Step 4: Verify clean build**

```bash
cargo build 2>&1 | tail -5          # Debug
cargo build --release 2>&1 | tail -5  # Release
```

**Step 5: Commit build fixes**

```bash
git add -A
git commit -m "fix: resolve compilation errors from pi→skaffen rename"
```

<verify>
- run: `cd os/Skaffen && cargo build 2>&1 | tail -1`
  expect: contains "Finished"
- run: `ls os/Skaffen/target/debug/skaffen`
  expect: exit 0
</verify>

---

### Task 5: Get cargo test passing

**Files:**
- Modify: Various `os/Skaffen/tests/*.rs` (fix test imports, binary name refs)
- Modify: Various `os/Skaffen/src/*.rs` (fix inline tests)

**Context:** Tests reference the old crate name (`pi`) and may have hardcoded binary paths. VCR tests need `VCR_MODE=playback` to avoid real API calls.

**Step 1: Run tests and capture failures**

```bash
cd os/Skaffen
VCR_MODE=playback cargo test 2>&1 | tail -30
```

**Step 2: Fix test imports**

```bash
grep -rn 'use pi::' tests/ | head -20
```

Replace `use pi::` with `use skaffen::` in all test files.

**Step 3: Fix binary name references in tests**

Some integration tests may invoke the binary by name:

```bash
grep -rn '"pi"' tests/ | grep -v "api\|model\|anthropic" | head -20
```

Replace binary name references from `"pi"` to `"skaffen"` where they refer to the CLI binary.

**Step 4: Iterate until green**

```bash
VCR_MODE=playback cargo test 2>&1 | tail -30
```

Repeat fix cycles. Record the final test count:

```bash
VCR_MODE=playback cargo test 2>&1 | grep "test result"
```

**Step 5: Commit test fixes**

```bash
git add -A
git commit -m "fix: update test imports and binary refs for skaffen"
```

<verify>
- run: `cd os/Skaffen && VCR_MODE=playback cargo test 2>&1 | grep "test result"`
  expect: contains "passed"
</verify>

---

### Task 6: Add OODARC coupling spike

**Files:**
- Create: `os/Skaffen/src/oodarc.rs`
- Modify: `os/Skaffen/src/lib.rs` (add `mod oodarc`)
- Modify: `os/Skaffen/src/agent.rs` (wire hook at turn boundary)
- Modify: `os/Skaffen/Cargo.toml` (add `skaffen-oodarc` feature flag)

**Context:** The OODARC (Observe→Orient→Decide→Act→Reflect→Compound) loop is Skaffen's core architectural primitive. v0.1 just proves the insertion point works with a no-op hook behind a feature flag. The agent loop in `src/agent.rs` has clear turn boundaries at `TurnStart` (line ~734) and `TurnEnd` (line ~867) events. We hook between them.

**Step 1: Define the OodarcHook trait**

Create `os/Skaffen/src/oodarc.rs`:

```rust
//! OODARC coupling spike — v0.1 no-op hook.
//!
//! Defines the OodarcHook trait with phase lifecycle methods.
//! v0.1 wires a NoopOodarcHook at the agent turn boundary to
//! prove the insertion point works. v0.2 replaces with the
//! full OODARC state machine.
//!
//! Gated behind the `skaffen-oodarc` feature flag.

/// OODARC phase lifecycle hook.
///
/// Called at the agent turn boundary to allow phase-aware
/// processing. Each method corresponds to one OODARC phase.
pub trait OodarcHook: Send + Sync {
    fn on_observe(&self) {}
    fn on_orient(&self) {}
    fn on_decide(&self) {}
    fn on_act(&self) {}
    fn on_reflect(&self) {}
    fn on_compound(&self) {}
}

/// No-op implementation for v0.1 coupling spike.
pub struct NoopOodarcHook;

impl OodarcHook for NoopOodarcHook {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn noop_hook_compiles_and_runs() {
        let hook = NoopOodarcHook;
        hook.on_observe();
        hook.on_orient();
        hook.on_decide();
        hook.on_act();
        hook.on_reflect();
        hook.on_compound();
    }
}
```

**Step 2: Register the module**

In `src/lib.rs`, add:

```rust
#[cfg(feature = "skaffen-oodarc")]
pub mod oodarc;
```

**Step 3: Add feature flag to Cargo.toml**

In `os/Skaffen/Cargo.toml`, in the `[features]` section:

```toml
skaffen-oodarc = []
```

Do NOT add it to `default` — the spike is opt-in.

**Step 4: Wire the hook in agent.rs**

In `src/agent.rs`, near the TurnStart event dispatch (around line 734), add the OODARC hook call. Find the `AgentEvent::TurnStart` block and add after it:

```rust
#[cfg(feature = "skaffen-oodarc")]
{
    use crate::oodarc::{OodarcHook, NoopOodarcHook};
    let hook = NoopOodarcHook;
    hook.on_observe();
}
```

This is intentionally minimal — just proves the insertion point compiles and doesn't break the turn flow.

**Step 5: Test with feature flag enabled**

```bash
cd os/Skaffen
# Without flag — existing tests still pass
VCR_MODE=playback cargo test 2>&1 | grep "test result"

# With flag — new test + existing tests pass
VCR_MODE=playback cargo test --features skaffen-oodarc 2>&1 | grep "test result"
```

**Step 6: Commit OODARC spike**

```bash
git add -A
git commit -m "feat: add OODARC coupling spike (no-op hook behind feature flag)"
```

<verify>
- run: `cd os/Skaffen && VCR_MODE=playback cargo test --features skaffen-oodarc 2>&1 | grep "test result"`
  expect: contains "passed"
- run: `grep "skaffen-oodarc" os/Skaffen/Cargo.toml`
  expect: contains "skaffen-oodarc"
</verify>

---

### Task 7: Establish benchmark baselines

**Files:**
- Modify: `os/Skaffen/benches/` (existing benchmarks from pi_agent_rust — verify they run)
- Create: `os/Skaffen/docs/benchmarks.md` (recorded baselines)

**Context:** pi_agent_rust ships with 4 criterion benchmarks (tools.rs, extensions.rs, system.rs, tui_perf.rs). We need to verify they run under the renamed crate and record baseline numbers.

**Step 1: Fix benchmark imports**

```bash
cd os/Skaffen
grep -rn 'use pi::' benches/ | head -10
```

Replace `use pi::` with `use skaffen::` in all bench files.

**Step 2: Run benchmarks**

```bash
cargo bench 2>&1 | tail -40
```

If benchmarks fail, fix imports and retry. Some benchmarks may need the `skaffen-oodarc` feature or specific test fixtures.

**Step 3: Record baseline numbers**

Create `os/Skaffen/docs/benchmarks.md`:

```markdown
# Skaffen Benchmark Baselines

**Date:** 2026-03-10
**Rust:** 1.85 (stable)
**Platform:** Linux x86_64

## Baselines (from pi_agent_rust fork)

| Benchmark | Metric | Value | Notes |
|-----------|--------|-------|-------|
| system/cold_start | RSS | XX MB | Target: <67 MB (pi_agent_rust baseline) |
| system/startup | Time | XX ms | Target: <100 ms |
| tools/* | Various | XX | See criterion HTML report |
| extensions/* | Various | XX | See criterion HTML report |
| tui_perf/* | Various | XX | See criterion HTML report |

## How to Run

\`\`\`bash
cargo bench
# HTML reports: target/criterion/report/index.html
\`\`\`
```

Fill in actual numbers from the benchmark run.

**Step 4: Commit baselines**

```bash
git add -A
git commit -m "docs: record benchmark baselines from pi_agent_rust fork"
```

<verify>
- run: `ls os/Skaffen/docs/benchmarks.md`
  expect: exit 0
- run: `cd os/Skaffen && cargo bench --bench system 2>&1 | tail -5`
  expect: exit 0
</verify>

---

### Task 8: Set up CI pipeline

**Files:**
- Create: `os/Skaffen/.github/workflows/ci.yml`
- Modify: `os/Skaffen/README.md` (add CI badge)

**Context:** pi_agent_rust has an 80KB ci.yml with a full matrix (3 OS × 2 Rust versions). For v0.1 we start minimal: stable Rust on Linux x86_64 only. We expand to nightly and macOS/Windows later.

**Step 1: Write minimal CI workflow**

Create `os/Skaffen/.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  CARGO_TERM_COLOR: always
  VCR_MODE: playback
  RUST_BACKTRACE: 1

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy, rustfmt
      - uses: Swatinem/rust-cache@v2

      - name: Build
        run: cargo build --release

      - name: Test
        run: cargo test

      - name: Test (with OODARC feature)
        run: cargo test --features skaffen-oodarc

      - name: Clippy
        run: cargo clippy -- -D warnings

      - name: Format check
        run: cargo fmt --check
```

**Step 2: Remove pi_agent_rust's old CI files**

The rsync from Task 1 copied pi_agent_rust's `.github/workflows/`. Remove the old ones and keep only our new ci.yml:

```bash
cd os/Skaffen
rm -f .github/workflows/bench.yml
rm -f .github/workflows/conformance.yml
rm -f .github/workflows/fuzz.yml
rm -f .github/workflows/publish.yml
rm -f .github/workflows/release.yml
# Keep only our new ci.yml
```

**Step 3: Add CI badge to README**

At the top of `os/Skaffen/README.md`, add:

```markdown
[![CI](https://github.com/mistakeknot/Skaffen/actions/workflows/ci.yml/badge.svg)](https://github.com/mistakeknot/Skaffen/actions/workflows/ci.yml)
```

**Step 4: Commit CI setup**

```bash
git add -A
git commit -m "ci: add GitHub Actions pipeline (build, test, clippy, fmt)"
```

<verify>
- run: `ls os/Skaffen/.github/workflows/ci.yml`
  expect: exit 0
- run: `grep "skaffen-oodarc" os/Skaffen/.github/workflows/ci.yml`
  expect: contains "skaffen-oodarc"
</verify>

---

### Task 9: Final verification and push

**Files:**
- Modify: `os/Skaffen/CLAUDE.md` (update with build/test commands)
- Modify: `os/Skaffen/AGENTS.md` (update architecture notes)

**Step 1: Full build + test cycle**

```bash
cd os/Skaffen
cargo build --release 2>&1 | tail -3
VCR_MODE=playback cargo test 2>&1 | grep "test result"
VCR_MODE=playback cargo test --features skaffen-oodarc 2>&1 | grep "test result"
cargo clippy -- -D warnings 2>&1 | tail -3
cargo fmt --check 2>&1
cargo bench --bench system 2>&1 | tail -5
```

**Step 2: Update CLAUDE.md with development commands**

Add to the Development section of `os/Skaffen/CLAUDE.md`:

```markdown
## Development Commands

- Build: `cargo build` (debug) / `cargo build --release`
- Test: `VCR_MODE=playback cargo test`
- Test with OODARC: `VCR_MODE=playback cargo test --features skaffen-oodarc`
- Bench: `cargo bench`
- Lint: `cargo clippy -- -D warnings`
- Format: `cargo fmt --check` (check) / `cargo fmt` (fix)
```

**Step 3: Push to Skaffen repo**

```bash
cd os/Skaffen
git push origin main
```

**Step 4: Verify CI passes on GitHub**

```bash
gh -R mistakeknot/Skaffen run list --limit 1
```

Wait for CI to complete. If it fails, read the logs and fix.

<verify>
- run: `cd os/Skaffen && cargo build --release 2>&1 | tail -1`
  expect: contains "Finished"
- run: `cd os/Skaffen && VCR_MODE=playback cargo test 2>&1 | grep "test result"`
  expect: contains "passed"
</verify>
