---
artifact_type: flux-drive-review
reviewer: fd-quality
source: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
revision: 3
date: 2026-04-02
status: needs-changes
findings: 8
---

# Quality & Style Review — Ockham Vision Brainstorm (rev 3)

## Scope

Brainstorm at `docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md` — 10 sections plus open
questions. This is a re-review of rev 3 (post 16-agent 4-track flux-review). Five previous
findings (Q-01 through Q-05) are verified first; new issues follow.

---

## Previous Findings — Verification

**Q-01: theme/lane collision — RESOLVED.**
Key Decision 2 explicitly defines: lane = intercore data model, theme = Ockham governance label,
`theme = bead.lane`. The terminology is now consistent and the mapping is unambiguous.

**Q-02: Intent YAML schema missing — RESOLVED (partially — see Q-07 below).**
Key Decision 4 provides a complete YAML schema with `version`, `themes` (budget, priority),
and `constraints` (freeze, focus). Validation behavior and atomic replacement semantics are
specified. The schema is present and actionable. A gap regarding expiry fields is raised as a
new finding (Q-07).

**Q-03: Bead-to-theme mapping blocker — RESOLVED.**
The `bd list --json | jq '.[] | {id, lane}'` call is stated. The unlaned-bead fallback to
the `open` theme is defined. No new data model is required.

**Q-04: "What Ockham Is NOT" missing — RESOLVED.**
Section 8 is present with six distinctions covering scheduler, audit log, UI, Clavain
replacement, quality arbiter, and Skaffen governor.

**Q-05: Implicit unknowns — PARTIALLY RESOLVED.**
Open Questions reduced from 5 to 2, and both remaining items are explicitly surfaced. However,
Open Question 2 (evidence gaming / promotion via bead self-selection) was rated P0 by 4-track
synthesis convergence while remaining deferred to Wave 3 — this priority mismatch is raised as
Q-08 below.

---

## Findings Index

- P1 | Q-01 | Key Decisions 7 | Self-promotion safety invariant remains behavioral (CLI-enforced only), not structural
- P1 | Q-02 | Key Decisions 5 | Tier 3 bypass channel: `factory-paused.json` still inside Clavain config — no Clavain-independent path specified
- P1 | Q-03 | Key Decisions 1 + 5 | CONSTRAIN precedence over intent weights is implicit, not specified in the scoring formula
- P1 | Q-04 | Key Decisions 3 + 6 | Starvation floor and idle-capacity release absent from brainstorm (present in plan Task 3 only)
- P2 | Q-05 | Key Decisions 10 | Intercept declared as Wave 1 dependency but absent from subsystem table allowed-deps column
- P2 | Q-06 | Key Decisions 6 | Ratchet promotion guard uses wall-clock confirmation window; synthesis F7 (3-track) recommended evidence-quantity replacement
- P2 | Q-07 | Key Decisions 4 | Intent YAML schema lacks expiry fields (`valid_until`, `until_bead_count`) despite F8 (3-track synthesis) recommending them
- P2 | Q-08 | Open Questions | Evidence gaming (promotion via bead self-selection) deferred to Wave 3 while ratchet also ships Wave 3 — P0-convergence finding ships unaddressed

Verdict: needs-changes

---

## Issues Found

### 1. P1 | Q-01 — Self-promotion invariant is behavioral, not structural

**Key Decisions 7, Safety Invariant 1**

The brainstorm states: "An agent calling `ockham` cannot pass its own ID as the granting actor."
This is enforced at the `ockham authority promote` CLI boundary via an `--actor` flag validation.
The 4-track synthesis (F1, highest-confidence finding, 8/16 agents) concluded that all five
safety invariants are behavioral — agents can bypass them by calling the underlying tools directly
rather than through Ockham's CLI. An agent with write access to beads state can call
`bd set-state autonomy_tier=3` directly; one with write access to interspect can write authority
grants without going through `ockham authority promote`.

The brainstorm does not add any structural guard at the execution path. The synthesis recommended:
"`bd set-state` rejects self-promotion writes. lib-dispatch.sh validates aggregate authority before
dispatch. Authority writes require signed tokens." None of these appear in the brainstorm. The
vision document that follows from this brainstorm will describe safety invariants that the factory
itself does not enforce.

**Fix:** Add a note to Safety Invariant 1 that CLI-boundary validation is insufficient on its own.
Identify which layer owns the structural backstop (intercore state layer, interspect write
validation, or a dedicated write-token scheme) so the vision document can name the enforcement
mechanism, not just the policy.

---

### 2. P1 | Q-02 — Tier 3 bypass channel has no Clavain-independent path

**Key Decisions 5, "What already works" Section 9**

The Tier 3 halt mechanism is: write `factory-paused.json` to `~/.clavain/factory-paused.json`,
then notify. The synthesis (F4, 3-track P0, 6/16 agents) identified that if Clavain is hung or
crashed, it never reads this file, and the halt signal goes unheard. The SRE-track agent added
a second failure mode: cascading failure produces O(agents × domains) simultaneous signals,
flooding the channel.

The brainstorm's restart sequence (Key Decision 5, R-04) and the "write-before-notify ordering"
rule both assume a functioning Clavain. Section 9 ("what already works") lists only existing
Clavain mechanisms — no independent channel is named. The plan (Task 6) lists "Clavain-independent
notification path" as something to write into the vision document, which means the plan intends
to add content not yet present in the brainstorm. That is appropriate for a plan, but the
brainstorm is still the architectural source of truth — if it doesn't name the independent path,
the vision document will be inventing a design that was never validated in the brainstorm phase.

**Fix:** Before the brainstorm is used to drive the vision document, name at least one
Clavain-independent halt notification channel. Candidates from the synthesis: a separate process
that monitors `factory-paused.json` (not Clavain), a direct write to the Alwe observation
layer, or an OS-level signal to a supervisor process. The vision document should name the
mechanism, not discover it.

---

### 3. P1 | Q-03 — CONSTRAIN/BYPASS precedence over intent weights is unspecified

**Key Decisions 1 (Scoring subsystem), Key Decisions 5 (Anomaly/algedonic)**

The final_score formula is `raw_score + ockham_offset` (Key Decision 3). The Scoring subsystem
"receives typed input structs (`IntentVector`, `AuthorityState`, `AnomalyState`)" and synthesizes
a weight vector. The brainstorm does not specify evaluation order or override semantics when
`AnomalyState` indicates a CONSTRAIN or BYPASS condition.

The synthesis (F6, 3-track) found: "intent weight 1.4 × authority penalty 0.7 = 0.98 (near-neutral),
meaning a CONSTRAIN freeze is silently violated by arithmetic balance." The brainstorm's fix for
this was the conversion from multipliers to additive offsets (Key Decision 3, "revised from
multipliers"), but the additive formula does not itself resolve the precedence question: an intent
offset of +12 applied to a CONSTRAIN-frozen bead still produces a nonzero score, which
lib-dispatch.sh would treat as dispatchable.

The plan (Task 3) names the fix as "Gate-before-arithmetic contract: CONSTRAIN/BYPASS as
eligibility gates, not weights." This is a design decision not present in the brainstorm. The
brainstorm describes CONSTRAIN as setting `ic lane update --metadata="paused:true"` and
`autonomy_tier=supervised`, but does not state that these produce a dispatch-eligibility flag
rather than a weight input to the scoring formula.

**Fix:** Add one sentence to Key Decision 3 specifying evaluation order: "CONSTRAIN and BYPASS
states produce dispatch eligibility gates evaluated before the additive offset formula. A frozen
bead receives an eligibility=false flag; the `+ockham_offset` formula is never applied."

---

### 4. P1 | Q-04 — Starvation floor and idle-capacity release are absent from the brainstorm

**Key Decisions 3 (dispatch integration), implicitly Key Decisions 1 (Scoring)**

The synthesis (F3, 4-track, all 16 agents' tracks represented) found that low-budget themes can
be permanently starved: when a high-budget theme exhausts its queue, capacity sits idle rather
than being released to lower-budget themes.

The brainstorm's dispatch integration (Key Decision 3) describes only the additive offset formula
(`raw_score + ockham_offset`, bounded ±12) and the `ockham_offset` write mechanism. It does not
specify a weight floor, starvation detection, minimum dispatch cadence, or idle-capacity release.
The plan (Task 3) lists all four of these as items to write into the vision document: "weight
floor and starvation detection," "idle capacity release." As with Q-02, this means the plan will
introduce design content without a brainstorm-phase basis for it.

The additive offset approach (±12 bounded) only nudges scores — it does not prevent a high-budget
theme from consuming all dispatchable capacity when its beads happen to have higher raw scores.
Without a floor or idle-release mechanism, the starvation scenario described in F3 remains valid
even after the multiplier → additive revision.

**Fix:** Add a starvation guard to Key Decision 3. Minimum: define the weight floor principle
(e.g., "a theme below its budget target receives a floor offset that guarantees minimum cadence")
and state that idle capacity from an exhausted high-budget theme is released to the global pool.
Exact thresholds are spec-phase detail; the principle should be in the brainstorm.

---

### 5. P2 | Q-05 — Intercept is a Wave 1 dependency not declared in the subsystem table

**Key Decisions 10 (weight-outcome feedback loop)**

Key Decision 10 states: "distills a local model after 50+ evaluations" and explicitly marks the
weight-drift detection loop as shipping "in Wave 1 alongside Tier 1 INFORM." The mechanism
requires Intercept (the local model distillation layer).

The subsystem table (Key Decision 1) lists four subsystems — Intent, Authority, Anomaly, Scoring
— with their allowed-deps columns. Intercept appears in none of these columns. The dependency
direction diagram (implicitly described in Key Decision 1) does not include Intercept. If the
weight-outcome feedback loop ships in Wave 1 and requires Intercept, Intercept is a Wave 1
dependency that is invisible in the formal subsystem model.

**Fix:** Either add Intercept to the allowed-deps column of the subsystem (Anomaly is the most
natural owner of weight-drift detection), or downgrade the intercept integration to Wave 2 to
match the wave assignment of Authority, which is where higher-complexity feedback loops belong.
The current state leaves an implementor reading the subsystem table unable to determine the
correct Wave 1 dependency set.

---

### 6. P2 | Q-06 — Ratchet promotion guard retains wall-clock confirmation window

**Key Decisions 6 (autonomy ratchet)**

The transition table shows promotion from shadow → supervised requires `hit_rate >= 0.80 AND
sessions >= 10 AND confidence >= 0.7`. The confirmation mechanism in Key Decision 5 ("Signal
persists past multi-window confirmation — short 1h AND long 24h must both breach simultaneously")
uses wall-clock windows.

The synthesis (F7, 3-track convergence, Track C: tabot custody) concluded that wall-clock windows
measure not-yet-failing, not competence. The tabot custody agent's specific formulation: "a
demonstration of absence-of-failure, not a demonstration of competence against the full difficulty
distribution." Track C also recommended replacing wall-clock windows with evidence-quantity
requirements (minimum evaluated beads, not minimum elapsed time).

The brainstorm's ratchet has a `sessions >= 10` guard, which is an evidence-quantity component.
But the multi-window confirmation for algedonic signals (short 1h / long 24h) is wall-clock only.
The promotion guard for the ratchet itself does not specify a time floor or an evidence-quantity
alternative — the `sessions >= 10` count could be accumulated over one day or one year with
equivalent promotion eligibility.

**Fix:** Add a minimum confirmation period to the ratchet promotion guard that is evidence-driven
rather than wall-clock-driven. For example: "Promotion eligibility requires the hit_rate guard to
hold across two disjoint evidence windows of >= N beads each (not the same N beads in two
windows)." This prevents promotion on a lucky short streak.

---

### 7. P2 | Q-07 — Intent YAML schema lacks expiry fields

**Key Decisions 4 (Intent YAML schema)**

The brainstorm schema includes `version`, `themes` (budget, priority), and `constraints`
(freeze, focus). The synthesis (F8, 3-track: central-bank, balinese-subak-irrigation,
carolingian-missi) recommended adding `valid_until` (ISO 8601 date) and `until_bead_count`
(integer) fields so that strategic intent expires rather than persisting indefinitely.

The plan (Task 2) explicitly lists "expiry fields (valid_until, until_bead_count)" as items to
include in the vision document's intent.yaml schema. This creates a direct contradiction: the
brainstorm schema (the authoritative source) does not include these fields, but the plan derived
from the brainstorm adds them. A vision document written from the plan will have a schema that
does not match the brainstorm, and the brainstorm will appear to be the wrong source for the
schema.

**Fix:** Add expiry fields to the Key Decision 4 schema. Minimum additions:

```yaml
  auth:
    budget: 0.40
    priority: high
    valid_until: null        # ISO 8601 date string; null = no expiry
    until_bead_count: null   # integer; null = no expiry
```

And add one line to the Validation section: "Expired directives revert to neutral weight (budget
= 1/N, priority = normal). `ockham status` warns on intents within 24h of expiry."

---

### 8. P2 | Q-08 — Evidence gaming deferred to Wave 3 while ratchet also ships Wave 3

**Open Questions 2, Key Decisions 6**

Open Question 2 states: "Agents influence their own `first_attempt_pass_rate` through bead
granularity choices. Use gate results at review time as canonical evidence, not bead closure
events? (Resolve during authority package design, Wave 3.)"

The autonomy ratchet (Key Decision 6) is assigned to Authority, which ships in Wave 3 (from the
subsystem table). The synthesis rated promotion gaming (F2) as P0 — the highest-severity finding
in the entire 16-agent review (4-track convergence, 6/16 agents). Deferring the resolution of
the evidence gaming surface to the same wave in which the ratchet ships means the ratchet
launches with a known P0-severity attack surface. There is no interim mitigation defined for the
Wave 3 launch window.

The brainstorm's wording — "Resolve during authority package design, Wave 3" — implies the fix
will be designed and implemented before the authority package ships. If that's the intent, the
open question should say so explicitly. If the intent is to ship the ratchet first and add gaming
resistance in a subsequent patch, that is a P0-severity known issue that should be acknowledged
as a deliberate risk acceptance, not left as an implicit open question.

**Fix:** Restate Open Question 2 to clarify one of two intents:
- "Resolve before Wave 3 authority package ships. Block Wave 3 launch if unresolved." (preferred, closes the P0 gap)
- "Accepted risk: Wave 3 ships without difficulty normalization. Mitigated by X (name the mitigation). Tracked in bead Y."

The current phrasing implies resolution without committing to a blocking gate or a named
mitigation.

---

## Summary

Rev 3 resolves all five previous findings. The lane/theme terminology split (Q-01), the full
Intent YAML schema (Q-02), the bead-to-theme mapping path (Q-03), the "What Ockham Is Not"
section (Q-04), and the open questions reduction (Q-05) are all present and correct.

Eight new issues were found. Four are P1 and reflect gaps between what the 16-agent synthesis
recommended and what rev 3 actually incorporated. The self-promotion invariant (Q-01) and the
CONSTRAIN precedence rule (Q-03) are specification-level omissions: the brainstorm states what
should happen without specifying the mechanism, which means the downstream vision document will
need to invent design content rather than transcribe validated content. The Tier 3 bypass channel
(Q-02) and the starvation floor (Q-04) are design elements listed in the plan but not in the
brainstorm — the plan is ahead of its source document.

The four P2 findings are structural: the Intercept dependency is invisible in the subsystem model
(Q-05), the promotion guard's wall-clock component was called out by a 3-track convergence (Q-06),
the expiry fields are missing from the schema (Q-07), and the evidence gaming deferral has no
blocking gate (Q-08). None of these prevent starting vision document authorship, but each will
produce a correctness gap if the vision is written without resolving them.

--- VERDICT ---
STATUS: needs-changes
FILES: 0 changed
FINDINGS: 8 (P0: 0, P1: 4, P2: 4)
SUMMARY: Rev 3 resolves all 5 prior findings cleanly. 8 new issues found: 4 P1 gaps where brainstorm states policy without specifying enforcement mechanism or leaves plan-level fixes undeclared at the brainstorm level (self-promotion structural guard, Tier 3 independent channel, CONSTRAIN precedence rule, starvation floor). 4 P2 gaps where synthesis recommendations were partially accepted (Intercept dependency undeclared, wall-clock promotion guard, missing expiry fields, P0-convergence gaming finding deferred without blocking gate). Safe to begin vision document authorship after resolving P1 items; P2 items can be addressed in the first Task 2-3 pass.
---
