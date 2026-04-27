# Clavain Peer-Coexistence: Systems Thinking Review

**Brainstorm:** `2026-04-27-clavain-peer-coexistence-brainstorm.md`  
**Scope:** C′ (full rig manager, ~1.5–2 weeks)  
**Review Date:** 2026-04-27

---

## Executive Summary

The brainstorm proposes sound architectural principles (detection-not-prescription, non-destructive layering, mod-manager patterns) but has **three high-leverage blind spots in systems dynamics** that could produce unintended outcomes at scale:

1. **Feedback loop absence (P1):** No mechanism exists to learn which peer rig "wins" in practice, nor to surface that data back to the model. Without telemetry, per-skill priorities are designed in a vacuum.
2. **Schelling-point brittleness (P1):** The entire system depends on plugin authors maintaining detection signals in `peers.yaml`. A single breaking change (skill rename, plugin repackaging) creates a cascading detection failure.
3. **Pace-layer misalignment (P2):** Plugin authors evolve skills daily; `peers.yaml` updates weekly via upstream-sync. Under this rhythm, the registry will drift faster than humans can correct it, creating a grow-stale-indefinitely loop.
4. **Lock-in via soft default (P2):** The lockfile is presented as "reproducible team onboarding" but creates a new form of lock-in: users pinned to peer versions until they actively break the lock. No clear exit strategy when a peer ships breaking changes.

The brainstorm correctly identifies the modding ecosystem's success pattern but underestimates **the continuous maintenance burden** when peer plugins are externally owned and evolving independently.

---

## Findings

### P1: Telemetry-Free Per-Skill Priority Design — Orphaned Feedback Loop

**Section:** "Open Questions #2" (p. 4)  
**Lenses:** Feedback Loops, Causal Chains, Compounding Loops  
**Risk:** Locally sound defaults that diverge from actual user behavior, evolving faster than documentation can keep up.

**The Issue:**

The brainstorm acknowledges this risk ("Without telemetry, per-skill priorities are designed in the dark") but files it as a mitigation, not a blocker:

> "Mitigation: ship `peers.yaml` with sane defaults, expose priority overrides as user-config (`~/.clavain/peer-priorities.yaml`), and **instrument which `using-*` skill won the routing decision per session for later calibration**."

This creates a **one-way causal chain with no feedback loop**:

```
Clavain ships per-skill defaults
  ↓
User encounters a scenario where superpowers' "write-plan" is faster/better
  ↓
User manually overrides ~/clavain/peer-priorities.yaml
  ↓
(no signal back to authors)
  ↓
Clavain's default remains unchanged for next user
  ↓
Next user makes same override
```

**Why This Matters:**

Modern systems succeed or fail on **learning loops**. A/B testing, observability pipelines, and steering mechanisms all close the feedback circuit. Here, the design:

1. **Ships defaults without evidence** — "sane defaults" is a guess, not measured.
2. **Assumes instrumentation will happen later** — famous last words. If it's not in scope, it won't happen for 6+ months.
3. **Creates distributed manual overrides** — Each user rediscovers the same tuning in isolation. Knowledge doesn't aggregate.

Modding managers (MO2, Vortex) avoid this because mod authors have **direct incentives** to fix user complaints (mod reviews, downloads tank if buggy). Here, incentive alignment is unclear: does superpowers' author know or care that users prefer Clavain's write-plan?

**Causal Risk:**

If "which skill wins" doesn't aggregate up, then:
- Clavain authors design in the dark (P1: fundamental information asymmetry).
- Per-skill priorities become a **local workaround ecosystem**, not a scalable pattern.
- At scale, 100 users tune 100 different `peer-priorities.yaml` files, but only superpowers' author learns from the first user to file an issue.

**Recommendation:**

Make instrumentation (recording which peer skill won) **part of scope C′**, not "later calibration." It costs ~50 lines of logging. Without it, the system has no self-correcting mechanism.

---

### P1: Detection-Signal Brittleness — Schelling Point at Risk

**Section:** "Open Questions #3 & #5" (p. 5); "Failure Modes: Masterlist staleness" (p. 4)  
**Lenses:** Schelling Traps, Causal Graphs, Hysteresis  
**Risk:** One plugin author's rename → cascading detection failure → users silent-downgrade to fallback behavior.

**The Issue:**

The system's entire peer-detection strategy depends on a **single shared convention**: plugin authors ship metadata (skill names, command patterns, or bundle IDs) that `peers.yaml` expects. This is a Schelling point—everyone coordinates on the same signal.

The brainstorm calls out one risk:

> "**GSD detection.** GSD ships as `jnuyens/gsd-plugin` (Claude Code packaging) and as `gsd-build/get-shit-done` (raw upstream). Detection rule needs to handle both."

But there are **at least four failure modes** where the Schelling point breaks:

1. **Skill rename:** Superpowers renames `/superpowers:write-plan` to `/superpowers:roadmap`. The detection rule in `peers.yaml` expects the old name. Clavain can no longer detect superpowers. Users still have superpowers installed, but the routing system thinks it's absent.

2. **Plugin repackaging:** A user installs superpowers as a local clone (not via the registry). The detection rule looks for an npm-sourced bundle ID; it misses the local one. Silent misdetection.

3. **Upstream-sync lag:** Plugin author ships a breaking change. `peers.yaml` carries a stale detection rule. Users upgrade the plugin but `peers.yaml` is out of sync. The rule fires on old skill names that no longer exist.

4. **Convention drift:** A new peer enters the ecosystem (Compound-Engineering, future rigs). Its author doesn't know what detection signals Clavain expects. They ship their own metadata format. Clavain's rigid rules don't match. Silent misdetection.

**Why This Is a Trap:**

When a Schelling point breaks, **locally rational decisions produce globally bad outcomes**:

- User installs superpowers v2.0 (which renamed skills).
- Clavain's detection rule fails silently (no loud error).
- User thinks both rigs are installed and working.
- They route a request to superpowers' old skill name.
- The skill doesn't exist; Clavain's fallback fires instead.
- User sees the wrong behavior but blames superpowers or their config.
- The actual cause (detection signal mismatch) is invisible.

This is **hysteresis**: once the system is in the "misdetected" state, it doesn't snap back when upstream changes. Users would have to manually run `/clavain:doctor` or know to re-run `/clavain:setup`.

**Recommendation:**

Make detection signal failures **loud and observable**:

- When a detection rule matches but the expected skills are not found, log a **diagnostic warning** with explicit remediation.
- Provide a `/clavain:verify-peers` command that re-runs all detection rules and reports drift.
- In `peers.yaml`, version the detection schema itself. If a plugin ships v2 detection rules, the old v1 rules degrade gracefully (advisory, not blocking).

---

### P2: Pace-Layer Mismatch — Registry Drift Loop

**Section:** "Failure Modes: Masterlist staleness" (p. 4); Upstream-sync mechanism  
**Lenses:** Pace Layers, Bullwhip Effect, Hysteresis  
**Risk:** Plugin author pace (daily) vs. registry update pace (weekly) → permanent staleness.

**The Issue:**

The brainstorm proposes:

> "Mitigation: `peers.yaml` carries a `last-updated` timestamp; `/clavain:doctor` warns if stale >30 days."

This is **observability without control**. It tells users the registry is stale, but the underlying rhythm mismatch remains:

- **Peer plugin authors evolve daily:** Superpowers adds a new skill, renames an internal function, ships a breaking change.
- **`peers.yaml` updates weekly via upstream-sync:** An upstream PR is cut, reviewed, merged, then pulled back via weekly sync.
- **By definition, there's a 1-week+ lag.** In a fast-moving ecosystem, this lag compounds.

**The Bullwhip Effect in Peer Resolution:**

A concrete failure scenario:

1. **Day 1:** Superpowers ships `write-plan` v2 (renamed internally).
2. **Day 7:** `peers.yaml` gets a PR with the new detection rule. Users still don't have it.
3. **Day 14:** Upstream-sync runs. Users' `peers.yaml` updates.
4. **Meanwhile:** Any user who installed superpowers between Day 1 and Day 14 has detection rules that don't match their installed version.

This creates a **cohort of misdetected users** for 1–2 weeks after every plugin change.

**Recommendation:**

Consider **decoupling detection from a centralized registry**:

- Embed detection rules **in the peer plugin itself** (as optional metadata in plugin.json or a `peer-signature.json` file).
- Have Clavain **ask the peer plugin** "what signals should detect you?" at runtime (when the plugin is installed, run a lightweight introspection).
- `peers.yaml` becomes a *fallback* for offline detection and a *curation layer* for bridge skills and known sharp edges, not the source of truth for "is this plugin installed?"

This shifts the ownership back to plugin authors (who control the pace) and removes the weekly lag.

---

### P2: Lock-in via Soft Default — Peer Version Pinning Without Clear Exit

**Section:** "Lockfile dovetails..." (p. 3); "Lockfile rot" mitigation (p. 4)  
**Lenses:** Lock-in Dynamics, Hysteresis, Over-Adaptation  
**Risk:** Users pinned to peer versions until they notice breakage; no frictionless upgrade path.

**The Issue:**

The brainstorm frames the lockfile as **reproducibility**:

> "`agent-rig.lock.json` lockfile — pins the exact set of plugins + versions + active profile + peer-priorities for reproducible team onboarding."

This is true for **reproducible team onboarding**, but it also creates a **one-way lock-in**:

1. User (or team) installs rigs and accepts the lockfile's peer versions.
2. Superpowers ships a major version with breaking changes.
3. The lockfile still pins the old version.
4. User is now pinned to a legacy peer version unless they:
   - Manually edit `agent-rig.lock.json` (risky, undocumented).
   - Run `clavain rig export` to refresh the lockfile (discovery burden).
   - Understand that lockfile updates are even an option.

**Why This Is Lock-in:**

In modding (Wabbajack), lockfiles are time-bound snapshots for a specific playthrough. Once you start a game with a modlist, you don't expect the mods to auto-update mid-playthrough. That's appropriate **because games are single-session entities**.

But Clavain is a **persistent dev environment**. A user returns to work 6 months later. The lockfile was created 6 months ago. Do they:

- Update the lockfile (changes the reproducible state)?
- Keep it pinned (miss security patches and features in peers)?
- Have both versions (increases complexity)?

The brainstorm mitigates this with:

> "Mitigation: lockfile carries checksums; `clavain rig install <lockfile>` fails loud on missing/changed plugins with a 'rehydrate' hint."

But a "rehydrate hint" is **guidance, not automation**. It assumes users will read it and act. In practice:

- Teams pin lockfiles in version control (best practice for reproducibility).
- 3 months later, superpowers has shipped v2 and dropped v1 support.
- `clavain rig install <lockfile>` fails with "rehydrate hint."
- Non-expert users are now blocked; expert users manually edit the file (fragile, error-prone).

**Hysteresis:** Once the lockfile is pinned, it's hard to unpin without risk.

**Recommendation:**

Make lockfile updates **explicit and auditable**:

- Provide a `clavain rig rehydrate <lockfile>` command that upgrades peer versions to latest-compatible, shows a diff of what changed, and asks for confirmation before writing the new lock file.
- Ship a complementary `clavain rig check-updates` command that runs without modifying state (pure read).
- Document the **lifecycle of a lockfile**: when to refresh it, how to balance reproducibility with freshness, and how teams should version it (e.g., `lockfile-2026-Q1.json` for quarterly snapshots).

---

### P3: Competing `using-*` SKILL.md Headers — Non-Determinism Risk

**Section:** "Key Decisions #3" (p. 2)  
**Lenses:** Emergence, Non-Determinism, Simple Rules Producing Complex Behavior  
**Risk:** Model behavior depends on which `using-*` skill loads first; no deterministic ordering.

**The Issue:**

The brainstorm notes:

> "**the real failure modes** are: (A) `/clavain:setup` silently disabling peer plugins, (B) competing `using-*` SKILL.md headers both demanding 'Proactive skill invocation,' (C) methodology vocab mismatch."

And proposes:

> "`using-clavain` SKILL.md becomes peer-aware: when a peer's `using-*` skill is loaded, demote 'Proactive skill invocation is required' to advisory."

But this creates a **non-determinism**: which `using-*` skill loads first?

**Claude Code's skill loading order** is not documented in the brainstorm. If it's alphabetical, filesystem order, or some other heuristic, then:

- Session A: Clavain's `using-clavain` loads first → demotes to advisory → superpowers doesn't fire.
- Session B: Superpowers' `using-superpowers` loads first → still says "Proactive invocation required" → superpowers fires.
- Same two plugins installed, different outcomes.

This is an **emergent behavior from simple rules** (load all `using-*` skills, whichever fires last wins). It's not explicitly coded, but the ordering is implicit in the system.

**Why This Matters:**

Users will observe different behavior in different sessions and blame randomness or their config, when the real cause is **skill load ordering**, which is invisible.

**Recommendation:**

Make `using-*` skill priority **explicit**:

- Define a `skill_priority` field in SKILL.md metadata: `using-clavain: priority=100`, `using-superpowers: priority=50`.
- Clavain's setup process chooses the highest-priority `using-*` skill at install time.
- Document that only one `using-*` skill is active per session.
- Provide a `/clavain:which-using` command that reports which `using-*` skill is active and why.

---

### P3: Absent Data-Driven Tuning Cycle — Per-Skill Defaults Without Evidence

**Section:** "Open Questions #2" (p. 4)  
**Lenses:** Feedback Loops, Compounding Loops, Over-Adaptation  
**Risk:** System adapts to the author's assumptions, not user reality.

**The Issue:**

Closely related to Finding #1, but with a focus on **per-skill priority defaults specifically**.

The brainstorm says:

> "Per-skill priority resolution via `~/.clavain/peer-priorities.yaml` — per-skill, not per-plugin."

This is granular (good). But then:

> "Risk for C′. Mitigation: ship `peers.yaml` with sane defaults..."

What are "sane defaults"? The brainstorm doesn't say. Presumably:

- Clavain's skills have priority 100.
- Superpowers' skills have priority 50.
- GSD's skills have priority 40.
- (Entirely invented numbers.)

But there's **no justification** for these numbers. Are they based on:

- User votes?
- Feature completeness?
- Speed benchmarks?
- Author preferences?

In the modding ecosystem, defaults are set by the masterlist curator (human judgment + community feedback). Here, there's no curation role identified. So defaults will be **author-selected**, which introduces bias.

**The Feedback Problem:**

If 80% of users override the default for skill X, that's a signal that the default is wrong. But without telemetry, that signal is invisible. The system doesn't **learn from divergence**.

**Recommendation:**

Budget 1–2 sprints for **telemetry and tuning after C′ ships**:

- Log which skill won for each request (tie-breaking decision).
- Aggregate at session and weekly granularity.
- Flag "skills with >50% user overrides" as candidates for re-tuning.
- Re-run this analysis quarterly; update `peers.yaml` defaults when evidence is clear.

---

## Severity Summary

| Severity | Count | Finding |
|----------|-------|---------|
| **P0**   | 0     | (none — no immediate concrete failures) |
| **P1**   | 2     | Telemetry-free defaults; Schelling-point brittleness |
| **P2**   | 2     | Pace-layer mismatch; lock-in without exit strategy |
| **P3**   | 2     | Non-deterministic skill loading; missing tuning cycle |

---

## Highest-Leverage Risk: The Feedback-Loop Absence

**Rank #1 (P1):** Telemetry absence is the **structural bottleneck**.

If the system ships without instrumentation, then:

- Per-skill priorities remain opaque (can't tune).
- Schelling-point drift (detection signal mismatches) is invisible until catastrophic.
- Pace-layer misalignment (registry staleness) is reported but not actionable.
- Lock-in dynamics (peer version pinning) are unexamined until users hit breakage.

**All of the other P2s and P3s are mitigations for missing feedback.** Better observability would catch detection failures early, surface registry lag before it harms users, and reveal lock-in pain quickly.

**Recommended Action:** Instrument per-session skill resolution as a **prerequisite** for scope C′. This is ~50–100 lines of logging, adds no runtime cost, and unblocks all downstream learning.

---

## Alignment with Clavain's PHILOSOPHY

The Clavain PHILOSOPHY emphasizes:

> "Does this reduce ambiguity for future sessions?"

The peer-coexistence design **improves ambiguity** (explicit resolution beats silent disable). But it introduces **new ambiguity** around:

- Which peer skill won (requires telemetry to disambiguate).
- Whether detection signals are stale (requires louder diagnostics).
- When the lockfile is safe to upgrade (requires a rehydrate workflow).

These are addressable within the C′ scope and don't require a reframe. They're tightening of the design, not re-architecting.

---

## Conclusion

The mod-manager analogy is sound, and the non-destructive approach is the right direction. However, **the design assumes sufficient information flow to support peer management**. Without telemetry, shared detection signals, pace alignment, and clear upgrade paths, the system risks becoming a **silent-failure machine** where users experience unintended outcomes (wrong skill winning, stale detection) without visibility into why.

The fixes are feasible:

1. **Add instrumentation (P1)** — Log which skill won for each request.
2. **Emit detection-signal errors loud (P1)** — Fail obviously when a detection rule matches but skills are missing.
3. **Embed detection in plugins (P2)** — Let peer plugins declare their own detection signals; `peers.yaml` falls back.
4. **Implement rehydrate workflow (P2)** — Clear path for users to upgrade peer versions without breaking lockfiles.
5. **Explicit skill priorities (P3)** — Name which `using-*` skill is active and why.

None of these are scope-expanding; all fit within 1.5–2 weeks and improve **system observability and user agency**.
