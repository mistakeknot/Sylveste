### Findings Index

- P0 | OVE-1 | "PHILOSOPHY.md Additions" | Authority ratchet risks ossifying into irrevocable founding condition — evidence thresholds become de facto vakfiye that downstream systems depend on
- P1 | OVE-2 | "What's Next" | No trust transfer mechanism (istibdal) for subsystem replacement — Auraken→Skaffen migration loses all earned trust
- P1 | OVE-3 | "Pitch" | Dead founder problem — the original designer's intent embedded in evidence thresholds may become canonical beyond any participant's authority to revise
- P2 | OVE-4 | "Flywheel" | Compounding evidence around obsolete configuration — evidence that compounds without purpose drift detection becomes an endowment serving a vanished market

Verdict: risky

---

## Detailed Findings

### OVE-1: Evidence thresholds risk becoming irrevocable founding conditions [P0]

**Section:** Key Decisions, Decision 5 / PHILOSOPHY.md Additions

The brainstorm proposes adding "Authority ratchet as mechanism" to PHILOSOPHY.md. This elevates a specific mechanism (evidence-gated authority promotion/demotion in Ockham) to a philosophy-level principle. The concern is not with the mechanism itself but with the elevation.

In the Ottoman vakif system, the vakfiye (founding document) specifies exact conditions for endowment governance: revenue allocation, beneficiary classes, succession rules. These conditions are legally irrevocable — they cannot be amended even when the founding purpose becomes obsolete. Revenue continues to compound even when the original market has moved elsewhere.

The analogous risk: once "authority ratchet" is codified in PHILOSOPHY.md, it becomes a founding condition. Downstream systems (Ockham, Interspect, future governance modules) build against this principle. Evidence thresholds — gate pass rate > 95%, override rate < 5%, whatever specific values are eventually chosen — become the operational expression of the principle.

As the system matures, these thresholds may need to evolve:
- Early-stage threshold: 90% gate pass rate over 10 sprints → reasonable for bootstrapping
- Mature-stage threshold: 95% gate pass rate over 100 sprints → reasonable for high trust
- Post-replatforming threshold: thresholds need recalibration for new system characteristics

But if the thresholds have been baked into multiple subsystems as implementation of the PHILOSOPHY.md principle, changing them becomes a cross-cutting migration. The threshold has ossified from "current best guess" into "founding condition."

**The nazir's istibdal insight:** In the vakif system, the only escape valve is istibdal (asset substitution): you can replace one endowed asset with another of equal or greater value while preserving the founder's stated purpose. The analogous mechanism would be: the evidence thresholds can be changed, but only by substituting a new set that demonstrably serves the same purpose (graduated trust through evidence) with equal or greater rigor. This prevents both threshold ossification (can't change) and threshold erosion (can change too easily).

**Recommendation:** The vision should distinguish between the principle (trust earned through evidence — permanent, philosophy-level) and the mechanism (specific ratchet implementation with specific thresholds — revisable, system-level). PHILOSOPHY.md should contain the principle; the mechanism should be explicitly documented as mutable implementation. Add a revisability clause: "The authority ratchet's evidence thresholds are calibration parameters, not founding conditions. They MUST be revisable when system characteristics change."

### OVE-2: Trust non-transferability across subsystem replacement [P1]

**Section:** What's Next, item 4

The brainstorm lists "Intelligence replatforming (Auraken→Skaffen + Hassease)" as P0. This is a subsystem replacement — the routing intelligence moves from one implementation to another. The capability mesh tracks trust per subsystem. But the brainstorm does not address what happens to earned trust during replacement.

In the vakif system, when an endowed building burns down, the replacement building cannot inherit the original's endowment status without a complex istibdal proceeding. The replacement building, though physically superior, starts with no endowment. This is legally correct (the endowment was for the specific building) but practically disastrous (the community loses institutional continuity).

The analogous risk: Auraken has (hypothetically) accumulated months of routing evidence — gate pass rates, model cost ratios, agent trust scores. When Skaffen replaces Auraken, does Skaffen inherit this evidence? Options:

1. **Full inheritance:** Skaffen gets all of Auraken's trust. Risk: Skaffen may behave differently, making inherited trust unreliable.
2. **Zero trust:** Skaffen starts from scratch. Risk: months of evidence are discarded; cold-start problem.
3. **Partial inheritance with verification (istibdal):** Skaffen inherits trust conditionally — it gets probationary access to Auraken's authority level, with a verification period where its actual behavior is compared to inherited evidence. If verification passes, trust transfers permanently. If not, trust reverts to zero.

The brainstorm should name this problem and at least identify which approach the vision takes.

### OVE-3: The dead founder problem [P1]

**Section:** Pitch + Capability Mesh

The "dead founder" is the original system designer whose intent is embedded in evidence thresholds, gate conditions, and routing rules. As the system matures and the original designer's involvement decreases, no living participant may have authority to change founding conditions that made sense at design time but no longer apply.

Concretely: the brainstorm's thesis is authored by a specific person at a specific time with specific assumptions about the system's trajectory. These assumptions will be encoded into Ockham's governance rules, Interspect's routing logic, and the capability mesh's evidence signals. Two years later, the system has evolved in unexpected directions — but the governance rules still reflect v5.0's worldview.

The question is: who has authority to revise the founding conditions when the founder's assumptions prove wrong?

- If the system treats its own accumulated evidence as canonical (per the evidence thesis), then the founding conditions self-reinforce through Goodhart dynamics: the system produces evidence that validates the conditions it was built on.
- If humans retain revision authority, the vision should say so explicitly — the evidence thesis has a human override that can trump accumulated evidence.

**Recommendation:** State explicitly that evidence thresholds, governance rules, and capability mesh definitions are revisable by human authority regardless of accumulated evidence to the contrary. The evidence thesis earns trust for autonomous operation, but the right to redefine the trust criteria remains with humans.

### OVE-4: Evidence compounding around obsolete configuration [P2]

**Section:** The Flywheel (Retained, Expanded)

The flywheel produces evidence that compounds over time. But evidence compounds around the system's current configuration. If the configuration becomes obsolete — a major architectural change, a model generation shift, a workflow redesign — the accumulated evidence describes a system that no longer exists.

In the vakif tradition, this is the endowment that generates revenue from a market that has moved: the caravanserai endowment continues to fund itself from traveler fees, but the trade route has shifted, and the caravanserai serves no travelers. The revenue compounds (the building is maintained, staff are paid) but the purpose has drifted.

The analogous scenario: the evidence pipeline accumulates routing evidence for a model mix (Claude Opus/Sonnet/Haiku). A new model generation arrives with fundamentally different characteristics. The accumulated evidence is technically accurate (it correctly describes past performance) but operationally misleading (it does not predict future performance under the new model mix).

The brainstorm should acknowledge that evidence compounding has a shelf life — accumulated evidence is valuable only as long as the configuration it describes remains operational. When configuration changes, the system needs a mechanism to distinguish "evidence about the current world" from "evidence about a world that no longer exists."
