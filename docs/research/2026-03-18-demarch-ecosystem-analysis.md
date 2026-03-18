# Demarch Ecosystem Analysis

**Date:** 2026-03-18
**Scope:** Full ecosystem audit — pillars, plugins, architectural maturity, strategic direction

---

## Executive Summary

Demarch is an ambitious autonomous software development agency platform built on a compelling thesis: **infrastructure unlocks autonomy, not model intelligence**. The architecture is philosophically coherent, the documentation is exceptional, and the design space is well-explored. But the ecosystem has a pronounced asymmetry: the *thinking* is far ahead of the *building*. Most pillars exist as exhaustive design artifacts with little or no running code. The path forward requires ruthless prioritization of the vertical slice that proves the flywheel turns.

---

## I. State of Each Pillar

### L1 Kernel — Intercore, Intermute, Interbase

**Status: Designed, not implemented.**

All three kernel modules are extensively documented — intercore's dispatch system, intermute's reservation protocol, interbase's cross-language SDK — but none have source code in the repository. The documentation references specific Go packages (`core/intercore/internal/dispatch`), test files, and benchmark harnesses that don't exist yet.

**Assessment:**
- The kernel is the load-bearing layer. Every L2 and L3 module declares a dependency on `ic` CLI or intermute coordination.
- Without L1, all downstream integration is mocked or simulated. This is the single biggest blocker.
- interbase (Python/Go/Bash SDK) is the least urgent — logging formatters can wait until there's something to log.

### L2 OS — Clavain

**Status: Design-complete, implementation in transition.**

Clavain has a Bash dispatcher (`clavain-cli`, ~1,360 lines) and a detailed 1,476-line plan for Go migration covering 28 commands. The vision has been rewritten from "self-improving multi-agent rig" to "autonomous software agency." 31 companion plugins are planned for domain extraction, but only 3 exist in Interverse today.

**Assessment:**
- Clavain is where the *opinions* live — phase gates, budget tracking, evidence recording, tool gating. These opinions ARE the product.
- The Bash→Go migration is correct but risks being a rewrite trap. The existing Bash CLI is the only code that exercises the sprint lifecycle today.
- 31 planned plugins vs. 3 shipped = 90% of the companion constellation is vapor.

### L2 OS — Skaffen

**Status: Planned, blocked on fork.**

Skaffen's architecture (OODARC loop, agentloop separation, GatedRegistry, multi-provider routing) is thoroughly designed across 15+ feature plans. But it depends on forking `pi_agent_rust` (Dicklesworthstone) into `os/Skaffen/`, and that fork hasn't happened.

**Assessment:**
- Skaffen is the sovereign agent runtime — the thing that actually *does work*. Without it, Demarch has workflow policy but no execution engine.
- The agentloop/agent separation (phase-agnostic loop vs. OODARC wrapper) is a strong architectural choice.
- 15 blocked feature plans suggest over-planning before any code exists. F1 (fork) must happen first; everything else is speculative.

### L3 Apps — Autarch

**Status: PRD-ready, blocked on Intercore wrapper.**

The TUI toolkit (Bigend, Gurgeh, Coldwine, Pollard) is well-designed with a clear first deliverable: `autarch status` — a read-only Bubble Tea dashboard rendering Intercore state. Blocked by the Go client wrapper (bead iv-cl86n), which itself is blocked by Intercore not existing.

**Assessment:**
- Autarch is the human interface. Without it, operator visibility is zero.
- The autonomy gap analysis correctly identifies that operator-mode TUI must evolve to executive-mode, but that's a v2 concern.
- The `masaq` TUI component library (2.3K lines of Go) is the one piece of L3 infrastructure that's actually built and working.

### L3 Apps — Intercom

**Status: Most mature module. H1 ~90% complete.**

Intercom is the furthest along: hybrid Node.js + Rust architecture, 7 of 8 read tools implemented, Telegram integration via Grammy, container orchestration for Claude/Gemini/Codex runtimes. H2 (write operations, gate approval buttons, Postgres LISTEN/NOTIFY) is planned in detail.

**Assessment:**
- This is the one module where code is ahead of documentation, not the other way around.
- The IPC bridge decision (Option B: through host) is correct for security boundaries.
- H1 completion (research tool + tests) and outbox stabilization are clear next steps.

### Interverse — Plugin Ecosystem

**Status: 3 plugins shipped out of 57 documented.**

| Plugin | Maturity | Domain |
|--------|----------|--------|
| interhelm (0.2.0) | Complete | Runtime diagnostics (4 skills, 1 agent, 3 hooks) |
| intersight (0.1.5) | Complete | UI/UX design token extraction (7-phase pipeline) |
| intership | Complete (minimal) | Whimsical Culture-series spinner verbs |

The remaining 54 plugins (interflux, interlock, interlab, interpeer, interwatch, interphase, etc.) are referenced in dependency chains and architecture docs but have no code.

**Assessment:**
- The 3 shipped plugins are genuinely good — interhelm's agent-as-operator pattern and intersight's extraction pipeline are well-crafted.
- But the gap between 3 real and 54 documented plugins is the ecosystem's credibility risk.
- Plugins like interlock (file coordination) and interphase (phase tracking) are load-bearing infrastructure that downstream modules assume exists.

---

## II. The Core Tension

Demarch has a **documentation-to-code ratio problem**. The ecosystem is defined by:

- **~50 design/plan documents** across `docs/plans/`, `docs/prds/`, `docs/research/`
- **~3 modules with working code** (Intercom, masaq, the 3 Interverse plugins)
- **~15 modules referenced but not started** (intercore, intermute, interbase, Skaffen, Clavain Go, Autarch, 50+ plugins)

This is not necessarily bad — good design prevents costly rework. But there's a risk of **analysis paralysis**: plans referencing plans that depend on other plans, all waiting on a kernel that doesn't exist. The flywheel can't compound if it never starts turning.

---

## III. What's Working

1. **Philosophical coherence.** The three principles (evidence → authority → composition) are applied consistently across every design document. This isn't hand-waving; it's a real architectural constraint.

2. **Layer separation.** L1 mechanism / L2 policy / L3 rendering is a sound decomposition. The rule that apps submit intents to the OS (never call kernel primitives directly) prevents coupling.

3. **Evidence-first design.** The receipts pattern (predict → observe → calibrate → default-as-fallback) is genuinely novel for agent systems and solves the "nothing survives" problem.

4. **Intercom momentum.** Having one module with real code and real users (Telegram bot with multi-provider container runtime) proves the architecture can be built, not just designed.

5. **masaq as foundation.** A working Bubble Tea component library means TUI work can start immediately once upstream dependencies land.

---

## IV. What's Not Working

1. **No kernel.** Everything depends on Intercore. Nothing can integrate until `ic` exists. This is a 6-month-old blocker based on documentation timestamps.

2. **Over-specification.** 15 feature plans for Skaffen before a single line of Go is written. Detailed benchmark harness designs for kernel modules that don't have a `go.mod`. The level of pre-specification suggests premature optimization of the design process itself.

3. **Plugin count inflation.** Referencing 57 plugins in the README when 3 exist sets expectations that the codebase can't meet. Each referenced-but-unbuilt plugin is a promise to maintain.

4. **Research dependency.** Skaffen is blocked on forking a Rust project (pi_agent_rust) into Go. This is a language rewrite, not a fork. The 4 vendored crates (asupersync, charmed_rust, rich_rust, sqlmodel_rust) suggest deep Rust coupling that won't survive Go translation.

5. **Self-building paradox.** "Clavain must build Demarch with its own tools" is a beautiful constraint, but Clavain's tools don't exist yet. The bootstrap problem is real.

---

## V. Strategic Recommendations

### 1. Ship Intercore in 2 weeks, not 2 months

The kernel doesn't need all features. It needs:
- `ic run create/status/list/advance` (SQLite-backed, ~500 lines of Go)
- `ic events tail` (append-only event log)
- `ic dispatch spawn/wait` (subprocess tracking)
- JSON output for every command (`--json`)

This unblocks Autarch (Go wrapper), Clavain (CLI migration), and Intercom (read tools). Ship the minimal kernel, then iterate.

### 2. Kill the Skaffen fork plan. Start fresh in Go.

Porting a Rust codebase (pi_agent_rust + 4 custom crates) to Go is harder than writing Go from scratch with the OODARC design in hand. The feature plans (F1-F9) are already Go-native in their API signatures. Abandon the fork artifact; keep the design documents.

### 3. Freeze the plugin count at what exists

Stop referencing unbuilt plugins in architecture docs. The 3 shipped plugins are good. Build the next 3-5 based on what Intercore and Clavain actually need at integration time (interlock, interphase, interlab). Let demand pull plugins into existence rather than supply-pushing 54 specs.

### 4. Complete Intercom H1, then H2

Intercom is the only module with real users and real code. Completing H1 (research tool + integration tests) and shipping H2 (write operations + gate approval) would make Intercom the first end-to-end demonstration that the architecture works: human sends Telegram message → Intercom routes to container → agent queries kernel → result surfaces in chat.

### 5. Define the "first sprint" end-to-end

The north star metric is "what does it cost to ship a reviewed, tested change?" To measure that, Demarch needs to run one sprint through the full lifecycle:

```
Intercore creates run → Clavain gates phases → Skaffen executes work →
Autarch shows progress → Intercom delivers notifications → Interspect measures cost
```

Define the minimal version of each pillar needed for this single sprint. Cut everything else.

### 6. Resolve the bootstrap: build Demarch with existing tools first

The self-building constraint (Clavain builds Demarch) is aspirational. The pragmatic path: build Intercore and Skaffen with Claude Code directly, then migrate to self-hosting once the tools exist. Trying to bootstrap from nothing produces the current stall.

---

## VI. The Vision Is Sound

Demarch's bet — that infrastructure compounds and the system that runs the most sprints learns fastest — is a good bet. The three-principle framework (evidence, earned authority, scoped composition) is more rigorous than any competing agent platform. The problem isn't vision; it's velocity.

The ecosystem needs to transition from **designing the machine** to **turning the crank**. One working sprint through the full stack is worth more than 50 design documents. The flywheel can't compound in a docs/ directory.

---

## VII. Priority Stack

| Priority | Action | Unblocks | Effort |
|----------|--------|----------|--------|
| P0 | Ship minimal Intercore (`ic` CLI) | Everything | ~2 weeks |
| P0 | Complete Intercom H1 | First real integration | ~3 days |
| P1 | Start Skaffen from scratch in Go | Agent execution | ~3 weeks for MVP |
| P1 | Clavain Go CLI (phase gates + budget) | Sprint lifecycle | ~2 weeks |
| P1 | Autarch status tool | Human visibility | ~1 week (after Intercore) |
| P2 | Intercom H2 (write ops + gate approval) | Bidirectional agency | ~3 weeks |
| P2 | interlock + interphase plugins | File coordination + phase tracking | ~1 week each |
| P3 | Interspect profiler | Flywheel measurement | After first sprint completes |
| P3 | Remaining Interverse plugins | Domain capabilities | Pull-based, not push-based |
