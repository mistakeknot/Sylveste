# Clavain Peer-Coexistence — Flux-Drive Decision Review

**Review Scope:** Pressure-testing scope C′ (full rig manager: profiles, peers.yaml registry, per-skill priorities, lockfile, CLI surface, bridge skills) for premature commitment, optionality loss, anchoring bias, and reversibility under realistic conditions. The brainstorm reframes Clavain from "successor to superpowers/compound-engineering" to "rig manager," betting ~1.5–2 weeks on the hypothesis that "users actually multi-rig" without evidence cited.

**Context:** The C′ scope represents a ~3x expansion from B′ (rig-manager-lite). This decision was made on the basis of a speculative future ("likely-generalized future where every Claude Code user has multiple rigs") rather than current observed behavior. The betting pattern and reversibility claims warrant scrutiny.

---

## Findings Index

1. **P1: "Users actually multi-rig" is the bet, but evidence is deferred and may never arrive.** The C′ scope is justified by "aligns with the likely-generalized future where every Claude Code user has multiple rigs." This is framed as a design observation (future-inevitable), not a testable hypothesis. The brainstorm has zero citation of current adoption patterns (how many Sylveste users actually run superpowers + GSD + Clavain?), making the ~2-week commitment speculative.

2. **P1: The mod-manager analogy anchors the design space too tightly; simpler solutions (auto-detect + inform, no manager) are under-explored.** The entire architecture (profiles, peers.yaml, lockfile, per-skill priorities) is justified by "the modding industry settled on overlay-without-mutation 10+ years ago." This analogy is powerful and directionally correct, but it imports assumptions from a domain (game modding) where users deliberately install multiple mods to customize gameplay. In Clavain's case, peer-rig installation is accidental (user installs superpowers, later installs Clavain, discovers conflict). The use case is weaker. A simpler solution—auto-detect peers, inform the user, require explicit resolution per-session—goes unstated and uncompared.

3. **P1: Per-skill priority resolution assumes a knowledge gap (what users actually reach for) that won't be closed before ship.** The brainstorm admits: "Without telemetry, per-skill priorities are designed in the dark. Risk for C′. Mitigation: ship sane defaults, expose priority overrides as user-config, and instrument which using-* skill won the routing decision per session for later calibration." This is a post-hoc instrumentation strategy, not a validation path. Users will ship with defaults, create profiles around those defaults, and those profiles will accumulate in `~/.clavain/`. If the defaults are wrong, changing them later means either (a) breaking existing profiles, or (b) grandfathering old profiles into old defaults. Either way, the "reversibility" claim is weakened.

4. **P2: Lockfile schema versioning is claimed as sufficient, but no versioning strategy is documented.** The brainstorm states: "Lockfile schema becomes a contract — needs versioning from day one." But no versioning scheme is defined. Will it be a top-level `schema_version` field? How are old lockfiles migrated? What happens if a user tries to `clavain rig install <old-lockfile>` on a new Clavain version? The claim "reversiblity built in (profiles toggle; lockfile snapshots)" assumes this is solved, but it's not yet designed.

5. **P2: The credibility paradox is named but not resolved: "Clavain ships its own rig" while being a neutral manager.** The brainstorm states Clavain becomes "a rig manager for Claude Code, not a rig that competes with peers." Yet Clavain itself ships with 17 skills, 6 agents, 51 commands. In profiles, Clavain's `using-clavain` skill will compete with superpowers' `using-superpowers` for routing authority. This is addressable via per-skill priority overrides, but the psychological framing "Clavain is a manager, not a competitor" collides with the reality "Clavain is a large, opinionated rig trying not to step on other large, opinionated rigs." The asymmetry (Clavain gets default routing priority unless explicitly demoted?) is left implicit.

6. **P2: Profile granularity choice (proactivity vs. full rig snapshots) is deferred to design time with no criteria stated.** Open question 6 asks: "Should profiles cover only Clavain proactivity vs deference (3 modes), or also bundle peer-priorities, enabled bridges, and which skills load (more like MO2 profiles)?" The brainstorm "leans toward the bigger version" but gives no criteria for the choice. This is a load-bearing decision: full rig snapshots create more state to manage and test, but 3-mode profiles are undershoots if the user actually wants to toggle peer-priorities per-session. Without explicit criteria, this choice will drift during implementation.

---

## Verdict

The brainstorm is **well-structured and thoughtful about failure modes, but commits to a 2-week scope based on a speculative future without a path to validate the bet.** The mod-manager analogy is powerful but anchors the design space more tightly than the use case justifies. Per-skill priorities are designed in the dark (admitted in the brainstorm), and reversibility claims on lockfiles and profiles are weakened by hidden design work (versioning, profile accumulation, default priority assumptions).

**The bet is hedged** (brainstorm explicitly notes "if users don't multi-rig, lockfile and profiles are still useful for team onboarding"), but the hedge is weak — team onboarding is a secondary use case, and the 2-week investment is mostly justified by the primary bet.

**Recommend:** Before committing to C′ scope, run a **discovery phase (3–5 days):**
1. Audit current Clavain user base: How many run Clavain + superpowers/GSD/compound simultaneously? (Query from interstat if available.)
2. Interview 3–5 power users: What happens when peer rigs conflict? Do they manually disable, or does the silent auto-disable surprise them?
3. Sketch the simplest viable solution (auto-detect, inform, require explicit session-level resolution) and compare scope/complexity to C′.

The result will either confirm the bet (go ahead with C′) or redirect to B′ (just fix the auto-disable and auto-inform). This is a **reversibility check**, not a blocker—C′ work is still valuable, but it should be informed by whether multi-rig coexistence is actually happening.

---

## Summary

The brainstorm identifies real failure modes (silent breakage, profile drift, masterlist staleness) drawn from 15+ years of modding ecosystem experience. The risk is not that the modes are wrong, but that:

1. **The multi-rig assumption has no evidence base.** C′ scope is justified by a speculative future without citing current adoption. This is a bet, not an observation. The bet is reasonable (agents will proliferate), but the commitment is premature without a discovery phase.

2. **The mod-manager analogy is powerful but imports domain assumptions.** Game modding is a use case where users deliberately install multiple mods to customize gameplay; Clavain peer conflicts arise accidentally. The analogy justifies the full architecture but may oversell the scope needed for accidental conflict management.

3. **Per-skill priorities are a high-uncertainty design with no validation path.** The brainstorm admits this is "designed in the dark" and relies on post-ship telemetry. User profiles will accumulate around defaults, making later changes costly. The reversibility claim is weakened.

4. **Lockfile versioning and profile accumulation are deferred design work.** The claim "reversibility built in" assumes these are solved, but they're not yet designed. This creates hidden implementation complexity.

5. **Profile granularity choice lacks decision criteria.** The "3-mode vs. full rig snapshot" decision is deferred to design time with no explicit tradeoffs. This will create scope creep or undershoots during implementation.

6. **Clavain's dual identity (neutral manager + opinionated rig) creates a credibility tension.** The framing "Clavain becomes a manager, not a competitor" is aspirational but collides with the reality of Clavain's large command/skill surface. Per-skill priority defaults will reveal which direction the product actually leans.

---

## Issues Found

### P1: Multi-Rig Assumption Is Speculative Without Evidence Path

**Location:** Brainstorm § "Key Decisions" (1): "aligns with the likely-generalized future where every Claude Code user has multiple rigs (superpowers, GSD, agent-os, claude-md-management, etc.)"

**Lens:** Assumption validation, Bet sizing, Evidence base

**Finding:**

The C′ scope justification is: "Higher payoff than B′ (rig-manager-lite) and aligns with the **likely-generalized future** where every Claude Code user has multiple rigs."

This is framed as an observation ("likely-generalized") rather than a testable hypothesis. But the brainstorm contains zero current-state data:
- How many Sylveste users currently run Clavain + superpowers/GSD/compound in parallel?
- Of those, how many experience conflicts that trigger the current auto-disable behavior?
- What is the severity of the conflict (annoyance vs. blocker)?

The bet on C′ is that multi-rig will be common enough to justify the 2-week investment. But the evidence path to validate this bet is deferred: "ship `peers.yaml` with sane defaults, expose priority overrides as user-config, and instrument which `using-*` skill won the routing decision per session for later calibration."

**Why this is P1, not P2:**

The 2-week scope is directly justified by this assumption. If multi-rig coexistence turns out to be rare (5% of users), the C′ investment is oversized. If it's common (50%+ of users), it's undersized. There's no validation before commit.

**Implication:**

Either (a) the discovery phase happens before scope commit, or (b) the scope is reduced to B′ (auto-detect, inform, require explicit resolution) pending evidence that multi-rig is common. The hedging statement ("if users don't multi-rig, lockfile and profiles are still useful for team onboarding") is weak—team onboarding is a secondary use case and doesn't justify 2 weeks.

**Question for author:**

Can you run a quick audit: How many Sylveste users run superpowers + Clavain? Of those, how many have experienced the auto-disable conflict in the last 30 days? This is a 1-hour query; the result informs whether C′ is right-sized or oversized.

---

### P1: Mod-Manager Analogy Anchors Design Space; Simpler Solutions Under-Explored

**Location:** Brainstorm § "Why This Approach (mod-manager analogy)" (full section) and § "Key Decisions" (3)

**Lens:** Anchoring bias, Analogy inference, Alternative generation

**Finding:**

The mod-manager analogy is powerful and well-executed: Mod Organizer 2, Vortex, LOOT, Wabbajack all solved the "multiple systems want the same surface" problem. The inference "Clavain should use the same pattern" is natural.

But the analogy imports assumptions from game modding:
- **Mod installation is deliberate:** Users install mods because they want customization. They curate their modlist carefully.
- **Conflicts are expected:** Mods *will* conflict; the question is how to manage them. The mod manager is expected from day one.

Clavain's case is different:
- **Peer-rig installation is accidental:** Users install superpowers for one reason, Clavain for another. The overlap is a surprise.
- **Single-rig was the model:** Clavain was designed as "the orchestration brain" for Sylveste. Peer rigs are an afterthought.
- **Conflict resolution is "nice-to-have," not essential:** If Clavain and superpowers both have `/write-plan`, the user can work around it (use one or the other). The current auto-disable is a problem, but it's not as critical as, say, two game mods both trying to write the same game file.

**What's not explored:**

- **Simplest viable fix:** Auto-detect peer rigs, display a warning at session start ("superpowers loaded; Clavain's `using-superpowers` skill is available as bridge"), require user to pick one via env var or interactive prompt. No profiles, no lockfile, no per-skill priorities. Scope: 3–5 days.
- **Middle ground (B′):** Auto-detect, inform, persist a single `~/.clavain/rig-choice` file (not a full profile system). Scope: 1 week.
- **Full rig manager (C′):** Full profile system, per-skill priorities, lockfile, peers.yaml. Scope: 2 weeks.

The brainstorm jumps from "the industry standard is full rig management" to "let's build full rig management" without comparing alternatives. This is anchoring bias: the analogy is so compelling that alternatives disappear.

**Why this matters:**

The mod-manager pattern assumes *users want to optimize rig composition across sessions.* In game modding, this is true (users maintain playstyles across dozens of playthroughs). In Clavain, it's unknown. If users are fine with picking a rig per-session (or per-project), B′ is sufficient and ships faster.

**Question for author:**

What would a "detection-not-prescription" approach look like for peer rigs, if not full rig management? E.g., "Clavain detects all installed rigs, shows them in `/clavain:peers`, and lets the user pick via `clavain rig use <name>` at session start—nothing more." How many weeks is that? What does it not solve?

---

### P1: Per-Skill Priorities Are Designed in the Dark With Weak Reversibility Claim

**Location:** Brainstorm § "Open Questions" (2): "Without telemetry, per-skill priorities are designed in the dark. Risk for C′. Mitigation: ship `peers.yaml` with sane defaults, expose priority overrides as user-config, and instrument which `using-*` skill won the routing decision per session for later calibration."

**Lens:** Decision under uncertainty, Hidden state, Post-hoc instrumentation, Profile accumulation

**Finding:**

Per-skill priority resolution is a core C′ component (decision 5: "Per-skill priority, not per-plugin. When superpowers and Clavain both ship `dispatching-parallel-agents`, the user should be able to say 'let superpowers' version win for that skill'").

But the brainstorm admits this is "designed in the dark"—no user research on which skills users prefer from which rigs, no guidance on sensible defaults, no validation of the decision structure.

The mitigation is post-hoc: ship sane defaults (guessed), collect telemetry (after ship), calibrate later. Users will:
1. Install Clavain with default per-skill priorities.
2. Create profiles that encode those defaults.
3. If defaults turn out to be wrong, either (a) change the defaults and break existing profiles, or (b) migrate profiles to new defaults (migration script + metadata update).

**The reversibility claim is weakened by profile accumulation:**

The brainstorm states "Reversibility built in (profiles toggle; lockfile snapshots; per-skill priorities are config-file, not code)." This is true in principle—per-skill priorities are a config file—but in practice:

- If a user has been running with "superpowers' `write-plan` wins" for 3 months and has created profiles around that choice, flipping the default to "Clavain's `write-plan` wins" is a breaking change.
- The `~/.clavain/peer-priorities.yaml` file is now part of the user's persistent state. Reverting to a previous priority set requires versioning the config file or maintaining a migration script.

**Why this is P1, not P2:**

Per-skill priorities are not a small feature; they're a design choice that affects the whole profile system. If the defaults are wrong, every profile created with those defaults becomes legacy state. This is a reversibility cost that's hidden in "config-file" framing.

**Question for author:**

Before shipping, sketch the default priorities for the first 3–5 contentious skills (e.g., `write-plan`, `executing-plans`, `using-*` routing). What's the reasoning for each? If you can't write down the reasoning without "users will tell us what they prefer," that's a signal to defer this feature to v1.1 (post-telemetry).

---

### P2: Lockfile Versioning Strategy Is Not Designed; Reversibility Claim Is Premature

**Location:** Brainstorm § "Conflict / Risk": "Lockfile schema becomes a contract — needs versioning from day one."

**Lens:** Schema evolution, Contract stability, Reversibility

**Finding:**

The brainstorm correctly identifies that lockfile schema is a contract that will need versioning. But then leaves it unresolved.

No versioning scheme is documented. Open questions:
- Is there a top-level `schema_version` field?
- How do old lockfiles migrate to new versions?
- What does `clavain rig install <old-lockfile>` do if the lockfile is from Clavain v0.2 and the user has v1.0? Does it upgrade gracefully, warn, or fail?

The claim "Reversibility built in (lockfile snapshots)" assumes this is solved, but it's not. This is deferred to implementation time.

**Why this matters for reversibility:**

If the lockfile schema needs a major version bump (e.g., v1→v2 due to profile rework), old lockfiles become one of:
- **Automatically upgraded:** Requires a migration strategy that may lose data (e.g., old profile format doesn't map to new format).
- **Deprecated:** Users can't use old lockfiles; they're forced to regenerate. This breaks the "reproducible team onboarding" promise.
- **Dual-supported:** The code supports both v1 and v2 schemas indefinitely, increasing maintenance burden.

The brainstorm doesn't discuss these tradeoffs.

**Question for author:**

Sketch the lockfile format (even rough). Include at least one field you think might change in the next 6 months (e.g., how peer-priorities are serialized, or profile structure). How would you handle a schema migration if that field changes?

---

### P2: Clavain's Dual Identity (Neutral Manager + Opinionated Rig) Creates Credibility Paradox

**Location:** Brainstorm § "Why This Approach" (final paragraph): "Clavain becomes a rig manager for Claude Code, not a rig that competes with peers."

**Lens:** Identity coherence, Default authority, Asymmetric competition

**Finding:**

The reframe positions Clavain as a neutral manager: "don't rebuild superpowers; manage it alongside Clavain."

But Clavain itself is a large, opinionated rig:
- 17 skills, 6 agents, 51 commands (from CLAUDE.md)
- `using-clavain` skill will ship with per-skill routing rules (decision 5)
- Profiles will include "which Clavain commands are active" and "which superpowers commands are active"

In practice, when a user creates a profile and then adds per-skill priority overrides, the question arises: **Does Clavain get default authority unless explicitly demoted, or are all rigs equal?**

If Clavain is the "orchestration brain," there's an implication that Clavain coordinates *other* rigs. That's an asymmetric authority structure: Clavain decides routing, other rigs contribute skills.

If all rigs are truly equal, then per-skill priorities should have no implicit defaults—they should all be explicitly configured. This is more work for users and contradicts "ship sane defaults."

**The tension:**

- **Option A (Clavain leads):** Clavain's default per-skill priorities win unless overridden. This makes Clavain a coordinator, not a peer. Positioning as "neutral manager" is misleading.
- **Option B (All equal):** All rigs have equal default priority; users must explicitly choose. Sane defaults are harder to define, and the UX is more complex.

The brainstorm doesn't address this asymmetry.

**Why this is P2, not P1:**

You can resolve this at design time (pick one of the two options and document it). But it affects the credibility of the "rig manager, not competitor" framing. If Clavain leads, that's fine—just be explicit about it.

**Question for author:**

When superpowers and Clavain both ship a `write-plan` skill, and a user hasn't set an explicit priority, which one wins? If Clavain wins by default, why is Clavain a "neutral manager"? If superpowers wins, how do you define "sane defaults"?

---

### P2: Profile Granularity (3 Modes vs. Full Rig Snapshots) Lacks Decision Criteria

**Location:** Brainstorm § "Open Questions" (6): "Should profiles cover only 'Clavain proactivity vs deference' (3 modes), or also bundle peer-priorities, enabled bridges, and which skills load (more like MO2 profiles)? Lean toward the bigger version — profiles as full rig snapshots — to maximize the lockfile/onboarding payoff."

**Lens:** Scope clarity, Design tradeoffs, Decision criteria

**Finding:**

The brainstorm identifies the key tradeoff but doesn't evaluate it:

**3-mode profiles (minimal):**
- Cover only Clavain's proactivity: `companion`, `primary`, `off`
- Smaller state surface, easier to test
- Doesn't capture "which peer-rig skills are enabled" or "per-skill priority overrides"
- Undershoots if users want to toggle peer rigs per-session

**Full rig snapshots (maximal):**
- Capture everything: peer-priorities, enabled bridges, enabled skills from each rig
- Bigger state surface, more complexity
- Maximizes lockfile/onboarding value
- Overshoots if users don't actually care about snapshots

The brainstorm "leans toward the bigger version" but gives no criteria for the choice. This is a load-bearing decision:
- Implementation complexity: full snapshots require tracking enabled skills per-rig, which is new state.
- Testing surface: more profiles to test, more failure modes (e.g., "profile X disables superpowers' `write-plan` but user still tries to call `/superpowers:write-plan`").
- User UX: full snapshots are more powerful but also more confusing (what does "save profile" actually save?).

**Why this matters:**

If the team starts implementing and realizes mid-sprint that 3-mode profiles are insufficient, the scope expands. If the team ships full snapshots and users never care about snapshot-based workflows, the complexity was unnecessary.

**The implicit reasoning seems to be:** "MO2 profiles are full snapshots; mod managers are successful; therefore, full snapshots for Clavain." This is the mod-manager analogy at work again, without evaluating whether the use cases match.

**Question for author:**

What is the user story that *requires* full rig snapshots and wouldn't be served by 3-mode profiles? E.g., "I want to switch between [research mode: superpowers only] and [shipping mode: Clavain only] per-project." If you can't articulate a compelling story, start with 3-mode profiles and expand later if needed.

---

## Improvements

### For Next Iteration

1. **Run a discovery phase before scope commit.** Query current Clavain user base: How many run multi-rig setups? How often do conflicts occur? This is a 3–5 day phase that informs whether C′ is right-sized or should reduce to B′.

2. **Compare C′ to simpler alternatives explicitly.** Sketch the 3–5 day minimal fix (auto-detect, inform, pick at session start) and the 1-week B′ (single persistent choice). Document what each solves and doesn't solve. This removes anchoring bias and makes the C′ choice explicit rather than inevitable.

3. **Design per-skill priority defaults before scope commit.** Write down the reasoning for the first 3–5 contentious skills (why does superpowers' `write-plan` win or lose to Clavain's?). If you can't write the reasoning, defer this feature to v1.1 post-telemetry.

4. **Design lockfile versioning strategy now, not at implementation time.** Sketch the lockfile schema (rough is fine). Identify one field that might change. Document migration strategy for that change. This surface hidden implementation work early.

5. **Clarify Clavain's authority model.** When peer rigs conflict, does Clavain lead (asymmetric), or are all rigs equal (symmetric)? This affects the credibility of "neutral manager" framing and should be decided before profiles and priorities are designed.

6. **Define profile granularity criteria explicitly.** What user story *requires* full rig snapshots vs. 3-mode profiles? If the story is weak, start minimal and expand post-launch. This prevents scope creep.

---

## Cross-Module Notes

**Intersection with fd-architecture:** The mod-manager analogy is a powerful framing, but it glosses over domain differences between game modding (deliberate, curated) and Clavain peer-rig adoption (accidental, opportunistic). An architecture review of how peers are discovered, registered, and versioned would surface these differences.

**Intersection with fd-systems:** The feedback loops between rig composition decisions and Clavain's long-term positioning (is it an orchestrator or a peer?) deserve modeling. If Clavain becomes a neutral manager of multiple rigs, does that weaken its ability to enforce "orchestration brain" discipline across the system?

**Intersection with fd-people:** Team onboarding and user profiles create consent/privacy questions around profile sharing (open question 5 partially addresses this). A dedicated trust review on "who owns a profile" and "what happens if a profile breaks the user's workflow" would inform scope.

<!-- flux-drive:complete -->
