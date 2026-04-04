---
reviewed: 2026-04-02
reviewer: fd-safety
subject: interverse/interflux/skills/flux-drive/phases/reaction.md
reaction-to: fd-correctness, fd-quality, fd-architecture
---

# Phase 2.5 Reaction Round — fd-safety Reactions

### Reactions

- **Finding**: RXN-01 (fd-correctness P0 — N=0 agent_count silent false-proceed)
  - **Stance**: missed-this
  - **Move Type**: new-assertion
  - **Independent Coverage**: no
  - **Rationale**: My REACT-01 focused on timestamp manipulation in peer-findings.jsonl as the integrity risk for the convergence gate; I did not inspect the degenerate N=0 path. The fd-correctness analysis is correct at `findings-helper.sh` line 96 (`printf '0.0\t0\t0\t0\n'`) and `reaction.md` line 11 (the effective_threshold formula): with agent_count=0 the formula yields 0.0, the strict `>` comparison returns false, and the spec says to proceed — making a total Phase 2 failure indistinguishable from a successful zero-reaction round. This is a security-relevant gap as well as a correctness one: synthesis receives an empty reaction directory with no error signal, and the interspect evidence record shows `agents_dispatched: 0` identically to a legitimate full-convergence skip. An operator cannot distinguish the two states from the evidence record alone, which makes post-hoc audit of failed runs unreliable.
  - **Evidence**: interverse/interflux/scripts/findings-helper.sh:96 (empty-raw branch); interverse/interflux/skills/flux-drive/phases/reaction.md:11 (effective_threshold formula); interverse/interflux/skills/flux-drive/phases/reaction.md:15 (skip event emitted with agents_dispatched:0, no error discriminator)

- **Finding**: RXN-04 (fd-correctness P1 — awk hyphen-stripping causes finding collisions)
  - **Stance**: partially-agree
  - **Move Type**: distinction
  - **Independent Coverage**: partial
  - **Rationale**: My REACT-03 flagged title normalization as bypassable by intentional rewording (semantic variation), but I characterized this as requiring agent intent. The fd-correctness analysis identifies a more concrete and passive failure: `gsub(/[^a-zA-Z0-9 ]/, "", title)` at `findings-helper.sh` line 119 strips hyphens mechanically, so "off-by-one" and "off by one" produce identical keys without any agent intent required. I accept the P1 classification. The distinction worth drawing is that REACT-03 and RXN-04 are two separate failure modes in the same normalization step — hyphen-stripping produces false positives (unrelated findings collapse to one key, inflating overlap), while semantic rewording produces false negatives (same issue registered under different keys, deflating overlap). Both degrade convergence gate accuracy in opposite directions and both originate at line 119.
  - **Evidence**: interverse/interflux/scripts/findings-helper.sh:119 (`gsub(/[^a-zA-Z0-9 ]/, "", title)`); REACT-03 (fd-safety initial findings)

- **Finding**: Q-10 (fd-quality P2 — partially-agree maps to distinction in Move Type table but prompt body implies defense)
  - **Stance**: agree
  - **Move Type**: defense
  - **Independent Coverage**: no
  - **Rationale**: I did not flag this contradiction; it is squarely in fd-quality's domain. The fd-quality analysis is correct at `reaction-prompt.md` lines 44 and 72: the output format block lists `attack | defense | new-assertion | concession` as the Move Type enumeration (no `distinction`), while the Move Type Assignment section at line 72 maps `partially-agree → distinction`. An agent reading the output format block first and stopping there will never use `distinction` as a move type, producing outputs that the synthesis agent must reclassify. This is a trust-boundary concern as well: the hearsay detection rule (reaction-prompt.md line 88) depends on move type being `defense` with independent Evidence to escape hearsay weighting. If `partially-agree` agents emit `defense` because the output format block doesn't list `distinction`, confirmations with partial evidence will be incorrectly weighted as full independent coverage in convergence scoring, defeating the hearsay discount. The fd-quality severity of P2 may be understated.
  - **Evidence**: interverse/interflux/config/flux-drive/reaction-prompt.md:44 (Move Type enumeration in output format block, no `distinction`); interverse/interflux/config/flux-drive/reaction-prompt.md:72 (`partially-agree → distinction` in Move Type Assignment); interverse/interflux/config/flux-drive/reaction-prompt.md:88 (hearsay rule depends on move type + Evidence field)

## Reactive Additions Index

- P1 | REACT-09 | "reaction-prompt.md:44,72" | `distinction` move type absent from output format enumeration, inflating hearsay-immune confirmations in convergence scoring (provenance: reactive)

### Verdict

adds-evidence
