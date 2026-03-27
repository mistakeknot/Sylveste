# OSS 1.0 Readiness Signals: What v1.0.0 Should Mean for Sylveste

Research into the empirical signals that major open-source projects actually used when declaring 1.0, and what those patterns imply for an autonomous software development agency platform currently at v0.6.228.

---

## 1. Rust 1.0 (May 15, 2015)

### What Was Promised

The Rust 1.0 announcement declared: "The 1.0 release marks the end of that churn." The commitment: code that compiles on stable Rust 1.0 will continue to compile on all future 1.x releases. Breaking changes were "largely out of scope" with "some minor caveats, such as compiler bugs."

The stability promise was *source-level only*. Binary compatibility between releases was never guaranteed. The Rust team reserved the right to fix compiler bugs and soundness holes even if doing so technically broke programs that depended on buggy behavior.

### What Was Explicitly Excluded

- **Nightly-only features**: Anything behind `#![feature(...)]` gates carried zero stability guarantees. The `unstable_features` lint was set to `forbid` on beta and stable channels, making it mechanically impossible to depend on unstable APIs from stable Rust.
- **Compiler internals**: Compiler plugins, internal APIs, and implementation details were excluded.
- **Performance**: No guarantees about compile times or runtime performance between releases.

### The Mechanism: Stability Without Stagnation

The innovation was the **release train model** (RFC 507): nightly -> beta -> stable on a six-week cadence. This allowed evolution on nightly while maintaining an ironclad stable channel. The key insight from the October 2014 "Stability as a Deliverable" blog post was that stability itself is a *feature* that must be engineered, not a byproduct of freezing the codebase.

Later, the **editions system** (2015, 2018, 2021, 2024) extended this further: backwards-incompatible syntax changes could be introduced in new editions while allowing crates from different editions to interoperate seamlessly. A 2021-edition crate can depend on a 2015-edition crate with no issues.

### What Triggered the Declaration

1. **API stabilization was mechanically complete**: All standard library APIs had been audited and marked `#[stable]` or `#[unstable]`. The stabilization deadline was March 9, 2015; beta shipped April 3; final release May 15.
2. **The ecosystem tooling existed**: Cargo and crates.io were operational. The post acknowledged "it's still early days" for the package count, but the infrastructure was in place.
3. **The governance model was established**: RFC process, subteams (lang, libs, tools, infra), and clear decision-making processes were all operational.
4. **A release pipeline existed**: The six-week train model was already running before 1.0 shipped, meaning the team had practiced the process.

### Lessons

Rust's 1.0 was primarily a **stability commitment with an escape hatch for evolution**. The feature set at 1.0 was incomplete (no async/await until 2019, no const generics until 2021), but the *stability mechanism* was complete. The declaration said: "we know how to add features without breaking you."

**Sources**: [Announcing Rust 1.0](https://blog.rust-lang.org/2015/05/15/Rust-1.0/), [Stability as a Deliverable](https://blog.rust-lang.org/2014/10/30/Stability.html), [RFC 507: Release Channels](https://rust-lang.github.io/rfcs/0507-release-channels.html), [Final 1.0 Timeline](https://blog.rust-lang.org/2015/02/13/Final-1.0-timeline/), [Nightly Rust Appendix](https://doc.rust-lang.org/book/appendix-07-nightly-rust.html), [What Are Editions?](https://doc.rust-lang.org/edition-guide/editions/)

---

## 2. Go 1.0 (March 28, 2012)

### What Was Promised

The Go 1 compatibility promise is the strongest in the industry. The announcement stated: "People who write Go 1 programs can be confident that those programs will continue to compile and run without change, in many environments, on a time scale of years." The compatibility document formalized this: "Programs written to the Go 1 specification will continue to compile and run correctly, unchanged, over the lifetime of that specification."

This was *source-level* compatibility. Recompilation was required between releases, but no code changes.

### What Was Explicitly Excluded

The Go team was unusually precise about exclusions:

1. **Binary compatibility**: Not guaranteed between releases.
2. **The `syscall` package**: Frozen as of Go 1.4, then excluded entirely. "It is impossible to guarantee long-term compatibility with operating system interfaces, which are changed by outside parties."
3. **The `unsafe` package**: "Packages that import `unsafe` may depend on internal properties of the Go implementation. We reserve the right to make changes."
4. **Performance**: "No guarantee can be made about the performance of a given program between releases."
5. **Sub-repositories** (golang.org/x/*): Subject to looser compatibility requirements.
6. **The Go toolchain itself**: Compilers, linkers, and build tools were under active development with no stability guarantee.
7. **Unkeyed struct literals**: Adding fields to standard library structs would break positional struct initialization (`pkg.T{3, "x"}`), but not keyed initialization (`pkg.T{A: 3, B: "x"}`).

Additionally, seven specific categories of changes were reserved as potentially breaking: security fixes, unspecified behavior, specification errors, bug fixes, struct field additions, method additions on non-interface types, and dot imports.

### How the Promise Evolved

By 2023, the Go team reflected on eleven years of experience with the promise. Russ Cox's "Backward Compatibility, Go 1.21, and Go 2" blog post identified three categories of "compatible-but-breaking" changes that the original promise hadn't anticipated:

- **Output changes**: Sort algorithm changes in Go 1.6 produced different orderings for equal elements, breaking tests.
- **Input changes**: `ParseInt` in Go 1.13 started accepting underscores in numbers, breaking programs with fallback logic.
- **Protocol changes**: Automatic HTTP/2 support in Go 1.6 broke programs behind incompatible middleboxes.

The solution was the GODEBUG system (formalized in Go 1.21): each potentially breaking change gets a GODEBUG setting keyed to the `go` directive in `go.mod`, allowing programs to retain old behavior. The landmark decision: "There will not be a Go 2 that breaks Go 1 programs. Instead, we are going to double down on compatibility."

### What Triggered the Declaration

Go 1.0 was described as "Go as it is used today, not a major redesign." The triggers were:

1. **Language specification was complete and stable**: The spec had been through multiple iterations.
2. **Core libraries were audited**: The standard library was reorganized and finalized.
3. **The `go` command replaced Makefiles**: Tooling maturity was demonstrated by shipping a unified build tool.
4. **Internal Google production use**: Go was already running in production at Google, providing evidence of real-world adequacy.

### Lessons

Go's 1.0 was a **promise about the future**, not a declaration about the present. The language was deliberately described as sufficient, not complete. The extraordinary strength of the compatibility promise ("a time scale of years") forced the team to develop sophisticated mechanisms (GODEBUG, build tags, editions-like `go` directives) to evolve without breaking. The lesson: the stronger your stability promise, the more engineering you must invest in evolution mechanisms.

The Go team's explicit statement that "boring is stable" and "boring means being able to focus on your work, not on what's different about Go" is directly relevant to Sylveste's positioning.

**Sources**: [Go version 1 is released](https://go.dev/blog/go1), [Go 1 and the Future of Go Programs](https://go.dev/doc/go1compat), [Backward Compatibility, Go 1.21, and Go 2](https://go.dev/blog/compat)

---

## 3. Kubernetes 1.0 (July 21, 2015)

### What Was Promised

Kubernetes declared 1.0 as "production ready" at OSCON in Portland. The announcement cited: DNS, load balancing, scaling, health checking, service accounts, persistent volumes, pod-based container grouping with rollback, debugging tools, namespace-based partitioning, live cluster upgrades, and dynamic scaling.

Performance claims were specific: container scheduling averaging under 5 seconds, validated at 1000s of containers per cluster across 100s of nodes.

### What Was Explicitly Excluded (or rather, not yet stable)

Kubernetes 1.0 introduced the **API maturity graduation model** that became the industry standard:

- **Alpha APIs**: Experimental, not enabled by default, may be removed in any release without notice.
- **Beta APIs**: Well-tested, enabled by default, may change based on feedback. Deprecated no more than 9 months or 3 minor releases after introduction.
- **Stable (GA) APIs**: No breaking changes without changing the version number. Cannot be removed within a major version.

At 1.0, many APIs were still alpha or beta. The 1.0 declaration meant: the *core* APIs (Pods, Services, ReplicationControllers, Namespaces) were stable, and the *graduation process* for everything else was defined and operational.

### What Triggered the Declaration

1. **Production deployment evidence**: Six named customers (Box, eBay, Red Hat, Samsung SDS, Shippable, Zulily) provided testimonials. Shippable reported "more than one million containers per month." Zulily reported running Kubernetes "in production for a while."
2. **Contributor mass**: 14,000 commits from 400 contributors across Google, Red Hat, CoreOS, IBM, Intel, Microsoft, VMware, and others.
3. **Heritage credibility**: Kubernetes inherited design patterns from Google's Borg, which had run "hundreds of thousands of jobs" in production for over a decade. The 1.0 wasn't starting from zero -- it was a reimplementation of proven patterns.
4. **Institutional commitment**: The simultaneous formation of the CNCF provided governance and long-term stewardship.

### Lessons

Kubernetes 1.0 was the most *aggressive* declaration in this study. The project was barely one year old. Many APIs were still beta. The declaration was as much about **institutional commitment** (CNCF formation, multi-vendor governance) and **heritage credibility** (Borg) as it was about technical completeness. The API graduation model allowed the project to declare stability for core primitives while keeping everything else explicitly provisional.

This is the closest analog to Sylveste's situation: a platform where the *core orchestration primitives* may be stable while many subsystems are still maturing.

**Sources**: [Kubernetes V1 Released (Google Cloud Blog)](https://cloudplatform.googleblog.com/2015/07/Kubernetes-V1-Released.html), [Kubernetes 1.0 Launch Event at OSCON](https://kubernetes.io/blog/2015/07/kubernetes-10-launch-party-at-oscon/), [Kubernetes Deprecation Policy](https://kubernetes.io/docs/reference/using-api/deprecation-policy/), [Borg: The Predecessor to Kubernetes](https://kubernetes.io/blog/2015/04/borg-predecessor-to-kubernetes/)

---

## 4. Terraform 1.0 (June 8, 2021)

### What Was Promised

Terraform waited seven years (initial release August 2014) before declaring 1.0. The announcement stated: "There are no significant changes in the 1.0 release as compared to the previous 0.15.5 release." The entire point was that **1.0 was not a feature release -- it was a stability declaration**.

HashiCorp defined four key requirements for 1.0:
1. **Deployed broadly**: The project had massive adoption.
2. **Major use cases understood and supported**: Core workflows were well-defined.
3. **Well-defined user experience**: The CLI and configuration language were stable.
4. **Stable architecture**: The internal architecture would not require breaking changes.

### The Compatibility Promise (v1.x)

The Terraform v1.x compatibility promises document is the most granular of any project studied:

**Guaranteed stable:**
- Core language syntax and semantics (resource, data, module, provider, variable, output, locals blocks)
- Meta-arguments (`count`, `for_each`, `depends_on`, `provider`, `alias`)
- All expression operators and built-in functions
- Protected CLI commands (`init`, `validate`, `plan`, `apply`, `show`, `fmt`, `version`, `output`, `state list/pull/push/show`)
- Provider Plugin Protocol version 5
- Provider Registry Protocol version 1 and Module Registry Protocol version 1
- State file cross-compatibility across 0.14.x, 0.15.x, and 1.0.x
- `local` and `http` backends

**Explicitly excluded:**
- **Terraform Providers**: "Separate plugins which can change independently of Terraform Core and are therefore not subject to these compatibility promises."
- **External modules**: Not part of Terraform, not covered.
- **Experimental features**: "May change or may be removed entirely."
- **Natural language output**: "Not a stable interface and may change."
- **Non-protected CLI commands**: `destroy`, `console`, `get`, `graph`, `import`, `workspace` subcommands, etc.
- **Community-maintained backends**: `azurerm`, `consul`, `s3`, `kubernetes`, etc.
- **Performance characteristics**: Not guaranteed.

**Caveats**: Security fixes, external dependency changes, bug fixes in new features, and late-reported regressions were all reserved as potential breaking changes.

**Maintenance**: At least 18 months per 1.x release.

### What Triggered the Declaration

Mitchell Hashimoto (CTO) said v1.0 "mainly offers enterprises a bit of security, since it means that the days of breaking updates are over." The triggers were qualitative, not quantitative:

1. **Workflow stability**: "Starting with Terraform 0.15 and continuing through the lifecycle of 1.x, you can now upgrade to a new Terraform version and your workflows will continue to be operational."
2. **State format stability**: Cross-version state compatibility had been achieved.
3. **Provider protocol stability**: Protocol version 5 was mature and decoupled.
4. **No new features in 1.0**: The deliberate choice to add nothing new signaled that the existing surface was the commitment.

### Lessons

Terraform's 1.0 is the **most conservative** declaration in this study. The project waited until the surface area was thoroughly explored, the protocol boundaries were hardened, and the team could enumerate exactly what was and wasn't covered. The deliberate choice to ship zero new features in 1.0 compared to 0.15.5 is the clearest expression of "1.0 is a promise, not a milestone."

The provider/module exclusion is directly relevant to Sylveste: Terraform drew a sharp line between the *core engine* (covered by compatibility promises) and the *plugin ecosystem* (explicitly excluded).

**Sources**: [Announcing HashiCorp Terraform 1.0 General Availability](https://www.hashicorp.com/en/blog/announcing-hashicorp-terraform-1-0-general-availability), [Terraform v1.x Compatibility Promises](https://developer.hashicorp.com/terraform/language/v1-compatibility-promises), [Terraform 1.0 Release Adds Stability Guarantees (InfoQ)](https://www.infoq.com/news/2021/06/terraform-1-0/), [Terraform 1.0 Finally Lands (DevClass)](https://devclass.com/2021/06/08/internet-down-infrastructure-as-code-up-terraform-1-0-finally-lands/)

---

## 5. Nix/NixOS: The Counter-Example

### Current State

Nix has been in development since 2003 (Eelco Dolstra's PhD thesis). The Nix package manager is at version 2.x (2.32+ as of 2025). NixOS uses date-based versioning (25.11, etc.). Neither has ever declared a "1.0" in the semver sense. There is no formal stability promise for the Nix CLI or language.

### What Holds It Back

The most visible symptom is **Nix Flakes**, the project's most important user-facing feature, which has been marked "experimental" for 4.5+ years (since late 2020) despite massive production adoption.

The blockers are both technical and governance-related:

**Technical blockers:**
- fetchTree semantics remain unfinalized
- Copying entire flake source trees to the store creates scalability problems with large repos
- Flake registry produces different results depending on system state (impurity)
- Cross-compilation requires violating the output schema or using workarounds
- Error messages reference store paths rather than flake locations

**Governance blockers:**
- Flakes were implemented without going through the RFC process, bypassing community input
- Part of the community rejects flakes on principle
- The 2024 Steering Committee election treated flake stabilization as a contentious political issue
- Stabilization implies a "long term promise" including hash stability, which makes future fixes exponentially harder

### The Paradox

The situation produces a characteristic pathology: the experimental label creates a false impression of instability that deters newcomers, while actual widespread adoption makes breaking changes practically impossible. As one community member described it: "We are in a situation where breaking changes are a necessity, but impossible."

Determinate Systems (a commercial Nix company) unilaterally declared flakes "stable in practice" and enabled them by default in their distribution. The Lix fork (a community fork) similarly consolidated flakes as de facto stable. The result is ecosystem fragmentation along governance lines.

### Lessons

Nix demonstrates what happens when a project **fails to make a stability declaration at the right time**:

1. **De facto stability without formal stability creates governance crises**: When the community treats something as stable but the project won't declare it, third parties step in with their own declarations, fragmenting the ecosystem.
2. **The RFC process matters as much as the code**: Flakes' technical merits are largely accepted, but the bypass of governance process created lasting resentment that blocks stabilization years later.
3. **Delayed stabilization has compounding costs**: Each year of delay increases adoption of the experimental API, making any breaking changes more destructive, making stabilization more politically fraught, which causes further delay.
4. **The absence of a stability promise is itself a signal**: It tells users and contributors that the project's governance cannot make binding commitments, which undermines trust in any future promise.

**Sources**: [Why Are Flakes Still Experimental? (NixOS Discourse)](https://discourse.nixos.org/t/why-are-flakes-still-experimental/29317), [What Are Your Thoughts About Flake Stabilization? (SC Election 2024)](https://github.com/NixOS/SC-election-2024/issues/112), [Experimental Does Not Mean Unstable (Determinate Systems)](https://determinate.systems/blog/experimental-does-not-mean-unstable/)

---

## 6. Cross-Project Analysis: The Readiness Signal Pattern

### The Five Signals

Across all four successful 1.0 declarations (Rust, Go, Kubernetes, Terraform), the following signals were consistently present:

#### Signal 1: Stability Mechanism Before Stable Surface

Every project had a **working process for evolution** before declaring stability. Rust had the release train and feature gates. Go had the compatibility document and (later) GODEBUG. Kubernetes had the alpha/beta/stable API graduation model. Terraform had the provider protocol versioning and state format versioning.

The pattern: **1.0 declares the stability mechanism operational, not the feature set complete.** Rust had no async/await. Kubernetes had alpha APIs everywhere. Go's standard library was incomplete. But all four had a *credible process* for adding features without breaking existing users.

#### Signal 2: Enumerated Exclusions

Every project was explicit about what was *not* covered. Rust excluded nightly features. Go excluded `unsafe`, `syscall`, performance, and sub-repositories. Kubernetes excluded alpha and beta APIs. Terraform excluded providers, external modules, experimental features, and most CLI commands.

The pattern: **the exclusion list is as important as the inclusion list.** A 1.0 that claims to cover everything is not credible. A 1.0 that precisely enumerates what it doesn't cover demonstrates that the team has thought carefully about the boundary.

#### Signal 3: Production Deployment Evidence

Every project cited real-world production use. Go had Google's internal deployment. Kubernetes had six named production customers. Terraform had massive enterprise adoption. Rust had the growing crates.io ecosystem and Firefox's Servo engine.

The pattern: **somebody other than the maintainers is running this in production.** The evidence doesn't need to be massive -- Kubernetes had six customers at 1.0 -- but it needs to be real, named, and external.

#### Signal 4: Institutional Commitment to the Promise

Every project backed its stability promise with institutional structure. Rust had the foundation, RFC process, and subteams. Go had Google's backing and the compatibility document. Kubernetes formed the CNCF. Terraform had HashiCorp's commercial backing and 18-month maintenance windows.

The pattern: **somebody credible is committing resources to maintaining the promise.** A solo developer's 1.0 means something different from a foundation-backed 1.0. The institution doesn't have to be large, but it needs to be durable.

#### Signal 5: Upgrade Path From Pre-1.0

Every project either provided smooth upgrades from the last pre-1.0 release or explicitly documented the migration path. Terraform's 1.0 was identical to 0.15.5. Rust had automated migration via `cargo fix`. Go provided the `go fix` tool. Kubernetes maintained API backward compatibility from 0.x.

The pattern: **1.0 is not a cliff.** If upgrading from the last 0.x to 1.0 requires significant effort, the stability promise rings hollow because users experienced instability at the moment of the declaration.

### The Signal Structurally Inapplicable to Agentic Platforms

**Signal 3 (Production Deployment Evidence) operates differently for agentic platforms than for compilers, runtimes, or infrastructure tools.**

For Go, Rust, Kubernetes, and Terraform, "production deployment" means: the software runs unchanged in a production environment, processing real workloads, and the output is deterministic enough that users can verify correctness. A Kubernetes cluster either schedules pods or it doesn't. A Terraform plan either applies correctly or it doesn't.

For an agentic platform like Sylveste, the output is *stochastic*. The same sprint configuration with the same codebase and the same agent can produce different code, different review findings, different routing decisions. "Production deployment" for an agentic platform means something closer to: *the platform's orchestration, gating, and evidence-collection mechanisms behave predictably even though the agent outputs they orchestrate are inherently variable.*

This means production evidence for Sylveste must focus on the **infrastructure layer** (do sprints complete? do gates fire? do receipts persist? does routing converge?), not on **output quality** (does the agent write good code?). Output quality is a property of the models and prompts, which change independently of the platform version.

The implication: Sylveste's production evidence should demonstrate that the OODARC loop (observe, orient, decide, act, reflect, compound) completes reliably and that evidence accumulates correctly -- not that every sprint produces perfect code. The analog to "Kubernetes schedules pods correctly" is "Sylveste runs sprints to completion, fires gates at the right moments, persists evidence, and feeds calibration data back into routing."

---

## 7. Readiness Signal Checklist for Sylveste v1.0.0

Derived from the empirical patterns above, contextualized for an autonomous software development agency platform.

### Must-Have Signals (all four required)

- [ ] **Stability mechanism is operational and tested.** There is a working, documented process for evolving the platform (adding skills, commands, hooks, phases, agents) without breaking existing configurations. Existing sprint configurations from v0.6.x continue to work on v1.0.x. The mechanism has been exercised at least once (an evolution that used the mechanism rather than a breaking change). *Analog: Rust's release train, Go's compatibility document.*

- [ ] **Exclusion boundary is enumerated.** A published document specifies what is and is not covered by the stability promise. Candidates for exclusion: individual Interverse plugins (like Terraform excluding providers), model-specific prompt templates, experimental phase gates, natural language output formats, internal calibration data schemas, and anything behind a feature flag. The exclusion list must be precise enough that a user can determine whether a given behavior is covered. *Analog: Terraform v1.x Compatibility Promises, Go 1 Compatibility.*

- [ ] **The core loop completes reliably under independent observation.** At least one user/team outside the core maintainers has run Sylveste in a production or production-like context and reported that: sprints complete, phase gates fire, evidence is persisted, and routing decisions are traceable. The evidence must be named and specific, not hypothetical. *Analog: Kubernetes's six named production customers, Go's internal Google use.*

- [ ] **Institutional commitment to the promise exists.** The stability promise is backed by a maintenance commitment (minimum duration), a governance structure that can make binding decisions about breaking changes, and a documented process for handling security fixes and regressions. *Analog: Terraform's 18-month maintenance window, Kubernetes's CNCF, Rust's foundation.*

### Should-Have Signals (not blocking, but their absence weakens the declaration)

- [ ] **Upgrade path from last 0.x is trivial.** Upgrading from the final 0.6.x to 1.0.0 requires zero or near-zero manual changes to existing sprint configurations, bead state, and plugin configurations. Ideally, 1.0.0 differs from the final 0.x only in the version number and the stability promise. *Analog: Terraform 1.0 being identical to 0.15.5.*

- [ ] **API graduation model is defined.** Subsystems (skills, agents, review dimensions, phase gates) have explicit maturity levels (experimental / beta / stable) with documented graduation criteria and deprecation timelines. *Analog: Kubernetes alpha/beta/stable API graduation.*

- [ ] **Calibration data schema is versioned.** The closed-loop calibration data (routing overrides, phase cost estimates, agent accuracy scores) has a versioned schema with documented migration paths. This is unique to Sylveste -- no comparable concern exists in the reference projects -- but it is the most likely source of silent breakage in an agentic platform.

- [ ] **Self-hosting evidence exists.** Sylveste has been used to develop Sylveste itself for a sustained period (months, not days), and the evidence (beads, sprint receipts, cost data) demonstrates that the platform's own feedback loop works. This is the strongest form of production evidence for a self-building system. *Analog: Go compiler written in Go, Rust compiler written in Rust.*

### Anti-Patterns to Avoid

- **Do not wait for feature completeness.** Rust had no async/await at 1.0. Kubernetes had alpha APIs everywhere. Terraform excluded most CLI commands. Waiting for every skill, agent, and plugin to be "done" is the Nix pathology.

- **Do not make the promise too broad.** Terraform explicitly excluded providers. Go excluded performance, unsafe, and syscall. If Sylveste tries to stabilize the Interverse plugin ecosystem as part of 1.0, the promise becomes unmaintainable. The L1 kernel (Intercore + Intermute) and L2 OS (Clavain + Skaffen) are the stability surface; L3 apps and Interverse plugins are explicitly excluded.

- **Do not delay past de facto stability.** If users are running Sylveste in production and treating the current behavior as stable, the formal declaration is already overdue. The Nix case shows that the cost of delay compounds: each month of unlabeled stability makes future changes harder and governance decisions more fraught.

- **Do not conflate 1.0 with "done."** The PHILOSOPHY.md already states: "There is no 'done.' The flywheel doesn't converge -- it compounds." This is the right framing. 1.0 means: the stability mechanism works, the exclusion boundary is drawn, and the promise is backed by institutional commitment. It does not mean the feature set is complete.

---

## Appendix: Summary Table

| Project | Years to 1.0 | Stability Mechanism | Key Exclusions | Production Evidence | Promise Strength |
|---------|-------------|---------------------|----------------|---------------------|-----------------|
| **Go** | 3 (2009-2012) | Compatibility document, later GODEBUG | unsafe, syscall, performance, toolchain | Google internal use | Strongest (decades-scale, no Go 2) |
| **Rust** | 5 (2010-2015) | Release train + feature gates + editions | Nightly features, compiler internals, performance | Growing crates.io, Firefox/Servo | Strong (source-level, bug-fix caveats) |
| **Kubernetes** | 1 (2014-2015) | Alpha/beta/stable API graduation | Alpha & beta APIs, implementation details | 6 named customers, Borg heritage | Moderate (core APIs only, rapid iteration) |
| **Terraform** | 7 (2014-2021) | Protocol versioning, state format versioning | Providers, modules, most CLI, experimental features | Massive enterprise adoption | Very strong (enumerated, 18-month windows) |
| **Nix** | 23+ (2003-now) | None formal | N/A | Massive production use, no declaration | None (de facto stability, no promise) |

| Signal | Go | Rust | K8s | Terraform | Nix |
|--------|:--:|:----:|:---:|:---------:|:---:|
| Stability mechanism | Y | Y | Y | Y | N |
| Enumerated exclusions | Y | Y | Y | Y | N |
| Production evidence | Y | Y | Y | Y | Y (but unclaimed) |
| Institutional commitment | Y | Y | Y | Y | Contested |
| Smooth upgrade path | Y | Y | Y | Y | N/A |
