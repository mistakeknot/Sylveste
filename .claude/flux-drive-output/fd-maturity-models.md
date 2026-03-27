# What Should v1.0.0 Mean for Sylveste?

## Cross-Domain Maturity Frameworks Applied to an Autonomous Software Agency

*Research synthesis: NASA TRL, DoD MRL, developmental biology, complex adaptive systems theory, reliability engineering, and system readiness levels — mapped onto Sylveste at v0.6.228.*

---

## 1. NASA Technology Readiness Levels (TRL 1-9) Mapped to Sylveste

### The Framework

NASA's TRL scale was designed for hardware technologies destined for space missions. Its core insight: maturity is defined by the *operating environment* in which something has been demonstrated to work, not by the completeness of its feature set.

| TRL | NASA Definition | Sylveste Analog |
|-----|----------------|----------------|
| 1 | Basic principles observed | Core bet articulated (PHILOSOPHY.md): infrastructure unlocks autonomy, review phases are leverage, flywheel compounds |
| 2 | Technology concept formulated | OODARC loop designed; 3-layer architecture (kernel/OS/apps) specified |
| 3 | Experimental proof of concept | Early prototyping: Clavain orchestrating single sprints with one model |
| 4 | Component validation in lab | Individual subsystems tested: Intercore runs/phases/gates, interflux review agents, routing tiers — all passing unit tests |
| 5 | Component validation in relevant environment | Subsystems tested under real conditions: Clavain building Clavain (self-building loop), real sprints producing real code |
| 6 | System/subsystem model or prototype in relevant environment | Full sprint lifecycle (brainstorm-to-ship) demonstrated with kernel-driven gates, multi-model routing, and multi-agent review on the platform's own codebase |
| 7 | System prototype in operational environment | Full stack deployed and operating daily: 785+ sessions, $2.93/landable change baseline, 57 plugins, 8/10 kernel epics shipped |
| 8 | System complete and qualified | All subsystems integrated, edge cases handled, reliability demonstrated across diverse workloads and projects |
| 9 | System proven through successful mission operations | Platform operated by external users on their own codebases with measured outcomes comparable to the developer's own usage |

### Current Assessment: TRL 6-7

Sylveste is firmly in the TRL 6-7 band. The full system prototype is operational in its intended environment (autonomous software development), but that environment is currently limited to the developer's own projects. The gap to TRL 8 is not about features — it is about *environmental diversity*. Has the system been qualified across enough different codebases, team sizes, programming languages, and failure modes that its behavior is predictable?

**Key evidence for TRL 7:**
- Self-building loop operational (the system builds itself with itself)
- 8/10 kernel epics shipped with test coverage
- Cost baseline established ($2.93/landable change, later $1.17)
- Autonomy Levels 0-2 shipped (Record, Enforce, React)
- Multi-model routing with static, complexity-aware, and override chains

**Evidence needed for TRL 8:**
- External user validation on non-Sylveste codebases
- Measured defect escape rates across diverse project types
- Recovery from novel failure modes (not just replay of known ones)
- Demonstration that the learning loop (Interspect) improves metrics on projects the developer did not configure

### The TRL Trap for Software

Here is where TRL misleads. NASA's TRL was designed for technologies with a fixed operational environment — space. A satellite communication system either works in orbit or it does not. Software platforms face a *variable operational environment*: every codebase, every team, every language is a different "orbit." TRL 9 for hardware means "proven in the mission environment." TRL 9 for a platform means "proven across the space of environments it claims to serve" — a fundamentally harder bar.

The most dangerous misapplication: declaring TRL 8-9 based on depth of testing in one environment (Sylveste building Sylveste) rather than breadth across many. Self-building is necessary but not sufficient. It is the equivalent of testing a satellite in a vacuum chamber that perfectly replicates one specific orbit.

---

## 2. DoD Manufacturing Readiness Levels (MRL 1-10) for Autonomous Dev Work

### The Framework

MRL was designed to answer a different question than TRL: not "does the technology work?" but "can we produce it reliably at scale?" The nine assessment threads (Technology/Industrial Base, Design, Cost/Funding, Materials, Process Capability, Quality, Workforce, Facilities, Manufacturing Management) translate surprisingly well to the "production of autonomous development work."

### Mapping MRL Threads to Sylveste

| MRL Thread | Hardware Domain | Sylveste Domain | Current State |
|-----------|----------------|----------------|---------------|
| **Technology & Industrial Base** | Supplier maturity, material availability | Model provider stability (Anthropic, OpenAI, Google); API reliability; dependency health | Medium risk: multi-provider architecture mitigates single-provider risk, but model capabilities shift unpredictably with each provider release |
| **Design** | Producibility, tolerances | Sprint template design, phase definitions, gate calibration | Strong: 10-phase lifecycle tested through 785+ sessions |
| **Cost & Funding** | Unit cost, cost drivers | Token cost per landable change, model routing cost optimization | Strong: baseline established, routing optimization in progress |
| **Materials** | Raw material availability, quality | Input quality: issue descriptions, codebase state, context availability | Weak-medium: highly variable. Some "materials" (well-described issues in clean codebases) produce good output; others (vague requirements in legacy code) produce waste |
| **Process Capability & Control** | SPC, yield rates, defect rates | Sprint completion rate, gate pass rates, defect escape rate | Medium: gates enforce process, but statistical process control (SPC analog) is not yet applied to sprint outcomes |
| **Quality** | Inspection, quality systems | Review agent precision, finding actionability, false positive rates | Strong in mechanism, weak in measurement: review agents exist, but outcome attribution (did the finding prevent a real defect?) is still being hardened |
| **Workforce** | Skilled labor availability, training | Agent fleet capability, model selection accuracy | Strong: 12 review agents + 5 research agents, fleet registry, capability declarations |
| **Facilities** | Production equipment, tooling | Compute infrastructure, API access, development environments | Strong for single-user; untested for multi-user production |
| **Manufacturing Management** | Production planning, scheduling | Sprint orchestration, portfolio management, cost-aware scheduling | Strong: kernel-level portfolio orchestration, fair spawn scheduler, cost budgets |

### Current Assessment: MRL 6-7

The platform is at the equivalent of "capability to produce in a production-representative environment" (MRL 7). Sprints run end-to-end, produce real code, and are measured. But the equivalent of MRL 8 — pilot line production, quality processes proven and under statistical control — requires something Sylveste does not yet have: **statistical process control for sprint outcomes.**

### The MRL Insight: The "Valley of Death" is Real

The MRL framework's most important contribution is naming the gap between "it works" (TRL 7) and "we can reliably produce it" (MRL 8-9). In hardware, this is the transition from successful prototype to low-rate initial production. In Sylveste, this is the gap between "sprints can succeed" and "sprints reliably succeed at a predictable quality level and cost."

The evidence that this valley exists for Sylveste:
- Cost-per-landable-change variance is high (the baseline exists, but the distribution around it is wide)
- Sprint completion rate is not published as a tracked metric
- Gate pass-on-first-attempt rate is not yet surfaced
- The Interspect learning loop is designed but not yet fully closing (evidence collection shipped, adaptive routing not yet)

**The MRL framework says: v1.0.0 should not be declared until the process for producing autonomous dev work is under statistical control — meaning the variance in sprint outcomes is characterized, bounded, and trending downward.**

---

## 3. Biological Development Stage Models

### Waddington's Epigenetic Landscape

Waddington's central metaphor: a ball rolling downhill through a landscape of bifurcating valleys. Each fork is a commitment point. Each valley is a developmental fate. The ridges between valleys prevent reversal once a commitment is made.

The modern refinement is critical: **commitment to a cell fate corresponds to the disappearance of a valley, not the splitting of one valley into two.** It is a saddle-node bifurcation — the alternative ceases to exist, not merely becomes harder to reach. This is intrinsic irreversibility.

### Sylveste's Commitment Points

Mapping this to platform development reveals several irreversibility thresholds — points where architectural decisions eliminate future options:

| Commitment Point | Biological Analog | Status | Reversibility |
|-----------------|-------------------|--------|---------------|
| Kernel as Go CLI (no daemon) | Germ layer specification | Committed | Low — rewriting as a daemon would invalidate the "opens DB, does work, exits" contract that 57 plugins depend on |
| SQLite as kernel storage | Organ primordium | Committed | Medium — the abstraction layer exists, but migration would be a major effort |
| Claude Code as first host | Tissue differentiation | Partially committed | Designed for reversal (PHILOSOPHY.md: "the architecture is designed so the opinions survive even if the host platform doesn't"), but muscle memory and testing depth make switching costly |
| 10-phase sprint lifecycle | Body plan establishment | Flexible | Configurable per workflow. Not yet canalized. |
| Plugin ecosystem architecture | Segmentation | Committed | 57 plugins depend on the current plugin.json schema and hook interface |
| OODARC as cognitive model | CNS patterning | Committed at philosophy level | Could be revised, but the entire evidence pipeline, calibration pattern, and learning loop are organized around it |

### Canalization: When Flexibility Becomes Rigidity

Waddington's canalization concept — the tendency of developmental pathways to become buffered against perturbation — maps directly to what happens as a platform accumulates users and integrations. Early in development, the sprint lifecycle could be reorganized freely. After 785+ sessions, 57 plugins, and an established cost baseline, certain architectural decisions become canalized: the system actively resists change because too many components depend on the current shape.

**The biological insight for v1.0.0:** A 1.0 release is an act of canalization. It declares that the current body plan is stable. The platform's "phenotype" (its observable behavior) becomes buffered against variation. Pre-1.0, instability is expected and even healthy (exploration of the fitness landscape). Post-1.0, instability is pathological (regression, breaking changes).

The question is whether Sylveste has reached a developmental stage where canalization serves it, or where it prematurely locks in decisions that should remain plastic. The 10-phase sprint lifecycle is still configurable. Model routing is still evolving. The Interspect learning loop has not yet closed. These are arguments that the "body plan" is not yet final — that v1.0.0 would be premature canalization.

### Holometabolous Metamorphosis: The Pupal Reorganization

Insect complete metamorphosis offers a more radical structural analog. In holometabolous development, the larva accumulates resources, then enters a pupal stage where 80% of its body is dissolved and rebuilt from imaginal discs — undifferentiated cell clusters that were present but dormant during larval life.

Sylveste's current state has a larval quality: it is accumulating capabilities (57 plugins, 49 commands, 17 skills, 6 agents, 8/10 kernel epics) at a rate that outpaces their integration. The PHILOSOPHY.md principle "Wired or it doesn't exist" is an explicit acknowledgment of this risk: capabilities that exist but are not wired into runtime paths are the developmental equivalent of imaginal discs — potential that has not yet been activated.

**The metamorphosis question:** Does Sylveste need a pupal phase — a period of consolidation where unintegrated capabilities are either wired in or removed — before declaring 1.0? The PHILOSOPHY.md already names this: "Before stabilization, debt is exploration cost; after, it's liability." The pupal phase is the period where exploration cost is converted into either structure or apoptosis (deliberate elimination).

---

## 4. Complex Adaptive Systems: Phase Transitions and Emergent Coordination

### The Percolation Threshold

In network science, a phase transition occurs when connectivity density crosses a critical threshold. Below the threshold, the system is a collection of disconnected clusters. Above it, a giant connected component emerges — a spanning structure that allows information to flow across the entire system.

Sylveste's architecture is explicitly a network of composed components: kernel primitives, OS policies, plugin capabilities, agent specializations, evidence streams, and calibration loops. The question is whether this network has crossed a percolation threshold — the point where the connections between components enable system-level behavior that no individual component could produce.

### Evidence of Pre-Percolation vs. Post-Percolation

| Signal | Pre-Percolation (Disconnected Clusters) | Post-Percolation (Giant Component) | Sylveste Status |
|--------|------------------------------------------|---------------------------------------|----------------|
| Information flow | Each subsystem operates on local state | Events from one subsystem trigger responses across the system | **Partial**: kernel events trigger phase transitions and agent dispatches, but Interspect's cross-system learning loop is not yet fully closed |
| Error recovery | Failures are local; each component handles its own errors | System-level recovery: one component's failure triggers compensating behavior in others | **Pre-percolation**: Auto-remediation (L3) is "Planned," not "Shipped" |
| Adaptation | Each component is tuned individually | System-level optimization: changing one parameter improves global behavior | **Pre-percolation**: Interspect proposes OS-level changes based on evidence, but the proposal-to-application-to-measurement cycle is not yet automated |
| Emergent behavior | Components do what they were programmed to do | System exhibits behaviors not explicitly programmed | **Ambiguous**: self-building is emergent in the sense that the system's output (code) modifies the system itself, but this is designed, not spontaneous |

### Kauffman's Autocatalytic Sets

Stuart Kauffman's work on the origin of life provides another lens. An autocatalytic set is a collection of molecules where each molecule's formation is catalyzed by at least one other member of the set. Above a critical complexity threshold, the probability of such a self-sustaining set emerging approaches 1.

Sylveste's flywheel (authority -> actions -> evidence -> authority) is an autocatalytic set by design: each component's output is another component's input. But the critical question is whether this set is *actually* self-sustaining or only *designed to be* self-sustaining.

**Test:** Remove any single component from the loop. Does the system continue to improve?
- Remove Interspect (the profiler): The system still runs sprints, but stops learning. Not self-sustaining.
- Remove the kernel (Intercore): Nothing coordinates. Catastrophic.
- Remove Clavain (the OS): The kernel has mechanism but no policy. No sprints run.
- Remove the review agents (interflux): Sprints produce unreviewed code. Quality degrades.

The autocatalytic set is not yet robust to single-component removal. This is characteristic of a system below the percolation threshold — the connected component exists but is fragile.

### Edge of Chaos

Complex adaptive systems exhibit maximum adaptive potential at the "edge of chaos" — a regime between excessive order (frozen, unable to adapt) and uncontrolled disorder (no coherent behavior). Pre-1.0 platforms operate near this edge naturally: enough structure to be useful, enough flexibility to evolve rapidly. A 1.0 release tends to push toward order (stability commitments, backward compatibility, API freezes).

**The CAS insight for v1.0.0:** Declaring 1.0 too early pushes the system away from the edge of chaos toward excessive order, freezing abstractions that should still be evolving. Declaring it too late risks disorder — users cannot depend on anything because everything might change.

The PHILOSOPHY.md already articulates this tension: "Pre-1.0 means no stability guarantees. Premature stability commitments freeze wrong abstractions." The CAS framework adds: the system should cross the percolation threshold *before* the 1.0 stability commitment, because post-percolation systems can absorb perturbation (backward-compatible changes) without losing coherence, while pre-percolation systems cannot.

---

## 5. Composite Maturity Rubric

Drawing the most predictive indicators from each domain, here is a three-level maturity rubric for Sylveste.

### Level A: Operational Prototype (v0.x — Current)

*Biological analog: Late embryonic / early fetal. Body plan established, organs forming, not yet viable outside the womb.*
*TRL analog: TRL 6-7. System prototype in relevant environment.*
*MRL analog: MRL 6-7. Demonstrated in production-representative environment.*
*CAS analog: Pre-percolation. Connected clusters, no spanning component.*

**Observable transition criteria (all must be met to exit this level):**

1. **Self-building demonstrated.** The platform builds itself with itself across at least 100 consecutive sessions without manual infrastructure intervention. *Status: MET (785+ sessions).*

2. **Sprint lifecycle end-to-end.** All phases from discovery through reflection execute kernel-driven with gate enforcement. *Status: MET (shipped Autonomy L0-L2).*

3. **Cost baseline established.** A repeatable, measured cost-per-landable-change exists with known variance. *Status: PARTIALLY MET (baseline exists, variance not yet characterized).*

4. **Plugin ecosystem functional.** At least 20 independently installable companion plugins operating without conflicts. *Status: MET (57 plugins).*

5. **Architecture committed.** Core architectural decisions (kernel/OS/apps layering, plugin interface, event schema) are stable enough that changing them would require migration, not just refactoring. *Status: MET (canalization has occurred).*

### Level B: Reliable Production (v1.0.0)

*Biological analog: Neonatal. Viable outside the womb. All organ systems functional. Vulnerable to environmental stress but capable of independent survival.*
*TRL analog: TRL 8. System complete and qualified.*
*MRL analog: MRL 8-9. Pilot line to low-rate initial production. Statistical process control.*
*CAS analog: At or above the percolation threshold. System-level behaviors emergent.*
*Reliability analog: Past the infant mortality phase of the bathtub curve.*

**Observable transition criteria (all must be met to declare v1.0.0):**

1. **Learning loop closed.** Interspect's full cycle — observe outcome, propose change, apply change, measure improvement — operates automatically. Not designed. Not planned. Operating. This is the percolation threshold: the system improves itself without human calibration of the improvement mechanism.
   - *Why this matters:* The PHILOSOPHY.md flywheel (authority -> actions -> evidence -> authority) is the core bet. If the flywheel does not actually turn autonomously, the system is a sophisticated build tool, not an autonomous agency. A 1.0 release of an autonomous agency where the autonomy loop is not closed is a category error.

2. **Statistical process control for sprint outcomes.** Sprint completion rate, gate pass-on-first-attempt rate, defect escape rate, and cost-per-landable-change are tracked with control charts (or their equivalent). The system detects when a metric is out of control and either remediates or alerts. This is the MRL insight: reliable production means bounded, characterized variance.
   - *Why this matters:* Without SPC, every sprint is an experiment. Users cannot predict outcomes. The platform is a tool for trying, not a tool for producing.

3. **External codebase validation.** At least 3 non-Sylveste codebases have been built or maintained using the platform with measured outcomes. Sprint completion rates, cost, and defect rates are comparable (within 2x) to self-building metrics.
   - *Why this matters:* TRL 8 requires qualification in the operational environment. The operational environment for a platform is "other people's code." Self-building is a vacuum chamber test.

4. **Auto-remediation operational (Autonomy L3).** The system retries failed gates, substitutes agents, and adjusts parameters without human intervention. This is the biological "viability" threshold — the neonatal organism that can maintain homeostasis without the womb.
   - *Why this matters:* A system that stops when it encounters an unexpected condition requires continuous human monitoring. That is an assisted tool, not an autonomous agency. L3 is the minimum for the "autonomous" claim.

5. **Infant mortality phase complete.** The failure rate for sprints on established (non-novel) workloads is stable or declining, not increasing. New failure modes are rare. Known failure modes have documented recovery paths. This is the bathtub curve signal from reliability engineering — a domain that does not appear in software maturity frameworks.
   - *Why this matters:* The bathtub curve's infant mortality phase is characterized by decreasing failure rates as manufacturing defects are discovered and eliminated. A platform still in infant mortality (each release introduces new failure modes at the same or higher rate) is not ready for production reliance. The transition to the "useful life" phase — where failures are random and rare rather than systematic — is the reliability engineer's definition of "ready to be relied upon."

6. **Backward compatibility contract.** Public interfaces (plugin.json schema, kernel CLI, event schema, gate protocol) have a documented stability policy. Breaking changes require migration paths and deprecation periods. This is the canalization commitment — the declaration that the body plan is final.
   - *Why this matters:* Without this, v1.0.0 is a label, not a contract. SemVer's v1.0.0 means "the public API is defined." If it can change without notice, the version number is decorative.

### Level C: Scaled Autonomy (v2.0+)

*Biological analog: Juvenile to adult. Growth continues, but the body plan is fixed. Adaptation occurs through learning, not structural reorganization.*
*TRL analog: TRL 9. System proven through successful mission operations.*
*MRL analog: MRL 10. Full-rate production with continuous improvement.*
*CAS analog: Self-organized criticality. The system maintains itself at the edge of chaos through its own feedback mechanisms.*

**Observable transition criteria:**

1. **Multi-operator governance.** Multiple human operators with scoped authority, explicit conflict resolution, and audit trails. The polycentric governance model from PHILOSOPHY.md is operational, not theoretical.

2. **Auto-ship operational (Autonomy L4).** The system merges and deploys when confidence thresholds are met. Humans approve policy, not individual changes.

3. **Cross-project learning.** Interspect transfers calibration knowledge from one codebase to another. Routing decisions learned on Project A improve outcomes on Project B. The learning loop is not project-local.

4. **Adaptation evidence.** Measured, sustained improvement in the north-star metric (cost-per-landable-change) driven by Interspect proposals, not manual tuning. The system demonstrably improves itself faster than a human could tune it.

---

## 6. Misapplication Warnings

### TRL Applied to Software: The Environment Problem

The foundational criticism of TRL applied to software (documented in Olechowski 2020, *Systems Engineering*) is that TRL assumes a fixed operational environment. Space is space. But software platforms face a combinatorial explosion of environments. TRL 9 for a satellite means "proven in orbit." TRL 9 for Sylveste would mean "proven across the space of all codebases, languages, team sizes, and CI configurations it claims to support." This is unbounded.

**Mitigation:** Do not claim TRL 9 equivalence. Instead, define specific "mission profiles" (codebase types, team configurations) and claim readiness for each independently. Sylveste at v1.0.0 should specify: "v1.0.0 for single-operator, monorepo, Go/Python/TypeScript projects with CI. Other configurations are supported but not qualified."

### CMMI Applied to Autonomous Systems: The Process Fallacy

CMMI (Capability Maturity Model Integration) measures process maturity — the consistency and reproducibility of organizational processes. Its core assumption is that consistent processes produce consistent outcomes. This assumption breaks for autonomous systems where the "workforce" (AI agents) changes capabilities with each model release, where the "raw materials" (codebases, requirements) have unbounded variation, and where the system's own learning loop changes its behavior over time.

**Mitigation:** Do not use process consistency as a proxy for outcome quality. Instead, measure outcome distributions directly. A sprint with a novel approach that succeeds is more valuable evidence than ten sprints that follow the same process.

### The Bathtub Curve: A Signal Missing from Software Frameworks

Reliability engineering's bathtub curve — with its infant mortality, useful life, and wear-out phases — does not appear in any standard software maturity model (TRL, MRL, CMMI, or SemVer). Yet it is arguably the most predictive signal for "readiness to be relied upon."

The infant mortality phase for a software platform is the period after each major release when newly introduced code paths fail at a higher rate than the baseline. The useful life phase is the period where failure is random, not systematic. The wear-out phase is when accumulated technical debt, deprecated dependencies, and model API changes cause increasing failure rates.

**This is the maturity signal that only appears in non-software frameworks:** A platform is ready to be relied upon when its failure rate curve has transitioned from decreasing (infant mortality — still finding systematic issues) to flat (useful life — failures are random and rare). This transition is observable: plot sprint failure rate per release. If each release introduces a spike followed by a decay, the system is still in infant mortality at the release level. When a release lands without a failure rate spike, the system has entered useful life.

### "Readiness to Deploy" vs. "Readiness to Be Relied Upon"

These are distinct thresholds, and confusing them is the most common maturity assessment error across all domains:

| | Readiness to Deploy | Readiness to Be Relied Upon |
|---|---|---|
| **TRL analog** | TRL 7 (prototype in operational environment) | TRL 8-9 (qualified and proven) |
| **MRL analog** | MRL 7 (production-representative) | MRL 9-10 (low-rate to full-rate production under SPC) |
| **Biological analog** | Viable fetus (could survive premature birth with support) | Neonatal (survives independently) |
| **Reliability analog** | Deployed hardware (may be in infant mortality) | Past infant mortality into useful life |
| **CAS analog** | Components connected | Percolation threshold crossed; system exhibits emergent self-correction |
| **Sylveste status** | **Yes** — the system can be deployed and produces useful output | **Not yet** — the learning loop is not closed, SPC is absent, external validation is pending |

**Sylveste at v0.6.228 is ready to deploy. It is not yet ready to be relied upon.**

The gap is not a feature gap. It is an evidence gap. The system may well be reliable. But the evidence that it is reliable — closed learning loops, characterized variance, external validation, declining failure rates — has not yet been produced.

---

## 7. Specific Recommendations

### What v1.0.0 Should Mean

v1.0.0 should mean: **"The autonomous development flywheel turns without manual cranking, and we can prove it."**

Concretely, all six Level B criteria must be met:
1. Interspect learning loop closed and operating
2. Sprint outcome metrics under statistical process control
3. External codebase validation (3+ projects)
4. Auto-remediation operational (Autonomy L3)
5. Failure rate curve past infant mortality
6. Public API stability contract published

### What v1.0.0 Should Not Mean

- Feature completeness (the plugin count, command count, and agent count are irrelevant to the maturity question)
- Autonomy L4 (auto-ship is a v2.0 capability)
- Multi-operator support (that is Level C)
- Zero defects (the MRL framework is explicit: production readiness means bounded variance, not zero variance)

### The Path from v0.6 to v1.0

The MRL framework suggests organizing remaining work by the manufacturing readiness threads:

1. **Process Capability (highest priority):** Close the Interspect learning loop. This is simultaneously the percolation threshold (CAS), the autocatalytic closure (Kauffman), and the transition from "tool" to "agency." Without it, the other criteria are accessories.

2. **Quality Management:** Implement sprint-level SPC. Track control charts for the north-star metric and supporting metrics. Detect out-of-control conditions automatically.

3. **Design Maturity:** Ship Autonomy L3 (auto-remediation). This is the "viability" threshold from developmental biology — the organism that can maintain homeostasis without continuous external support.

4. **Validation:** Run the platform on 3+ external codebases. Measure outcomes. Publish results.

5. **Reliability Characterization:** Track failure rates per release. Demonstrate the transition from infant mortality to useful life.

6. **Interface Stability:** Publish the backward compatibility contract for plugin.json, kernel CLI, event schema, and gate protocol.

### Version Semantics Suggestion

- **v0.7:** Interspect learning loop closed (criterion 1)
- **v0.8:** Sprint SPC + auto-remediation (criteria 2, 4)
- **v0.9:** External validation + reliability characterization (criteria 3, 5)
- **v1.0.0:** Stability contract published. All six criteria met. The flywheel turns.

---

## Sources

### NASA TRL
- [NASA Technology Readiness Levels](https://www.nasa.gov/directorates/somd/space-communications-navigation-program/technology-readiness-levels/)
- [TRL Definitions (PDF)](https://www.nasa.gov/wp-content/uploads/2017/12/458490main_trl_definitions.pdf)
- [Technology Readiness Level - Wikipedia](https://en.wikipedia.org/wiki/Technology_readiness_level)
- [TRL Shortcomings and Improvement Opportunities (Olechowski 2020)](https://incose.onlinelibrary.wiley.com/doi/10.1002/sys.21533)
- [Applying TRL to Software: New Thoughts and Examples](https://web.mst.edu/lib-circ/files/Special%20Collections/INCOSE2010/Applying%20Technical%20Readiness%20Levels%20to%20Software%20New%20Thoughts%20and%20Examples.pdf)

### DoD MRL
- [Manufacturing Readiness Level - Wikipedia](https://en.wikipedia.org/wiki/Manufacturing_readiness_level)
- [MRL Deskbook 2025 (PDF)](https://www.dodmrl.com/MRL_Deskbook_2025.pdf)
- [MRL Definitions (DoD)](https://at.dod.mil/Portals/129/Atch%202_MRL_TRL_Definitions.pdf)
- [Technology Readiness Levels, the Valley of Death and Scaling Up (Springer)](https://link.springer.com/chapter/10.1007/978-981-16-0155-2_7)

### System/Integration Readiness
- [From TRL to SRL: System Readiness Levels (SEBoK)](https://sebokwiki.org/wiki/From_TRL_to_SRL:_The_Concept_of_System_Readiness_Levels)
- [14 Readiness Level Frameworks (ITONICS)](https://www.itonics-innovation.com/blog/14-readiness-level-frameworks)

### Developmental Biology
- [Bistability, Bifurcations, and Waddington's Epigenetic Landscape (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC3372930/)
- [Cell Fate Commitment and the Waddington Landscape (Proteintech)](https://www.ptglab.com/news/blog/cell-fate-commitment-and-the-waddington-landscape-model/)
- [Complete Metamorphosis of Insects (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC6711294/)
- [Metamorphosis: Hormonal Reactivation of Development (NCBI)](https://www.ncbi.nlm.nih.gov/books/NBK9986/)

### Complex Adaptive Systems
- [Complex Adaptive System - Wikipedia](https://en.wikipedia.org/wiki/Complex_adaptive_system)
- [Dual-Phase Evolution in Complex Adaptive Systems (Royal Society)](https://royalsocietypublishing.org/doi/10.1098/rsif.2010.0719)
- [Self-Organized Criticality - Wikipedia](https://en.wikipedia.org/wiki/Self-organized_criticality)
- [Kauffman: The Origins of Order (Google Books)](https://books.google.com/books/about/The_Origins_of_Order.html?id=lZcSpRJz0dgC)
- [Collectively Autocatalytic Sets (Cell Reports)](https://www.cell.com/cell-reports-physical-science/fulltext/S2666-3864(23)00402-2)
- [Percolation Threshold - Wikipedia](https://en.wikipedia.org/wiki/Percolation_threshold)

### Reliability Engineering
- [Bathtub Curve - Wikipedia](https://en.wikipedia.org/wiki/Bathtub_curve)
- [NIST Bathtub Curve Reference](https://www.itl.nist.gov/div898/handbook/apr/section1/apr124.htm)

### Software Maturity Critique
- [CMMI - Wikipedia](https://en.wikipedia.org/wiki/Capability_Maturity_Model_Integration)
- [The Immaturity of CMM (Satisfice)](https://www.satisfice.com/blog/archives/6208)
- [Survey of Maturity Models from Nolan to DevOps (arXiv)](https://arxiv.org/pdf/1907.01878)
