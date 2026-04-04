---
reviewed: 2026-04-02
reviewer: fd-correctness (Julik)
subject: interverse/interflux/skills/flux-drive/phases/reaction.md
reaction-to: fd-architecture (ARCH-01), fd-safety (REACT-02, REACT-08)
---

# Phase 2.5 Reaction Round — Correctness Reactions

### Reactions

- **Finding**: ARCH-01
  - **Stance**: missed-this
  - **Move Type**: new-assertion
  - **Independent Coverage**: no
  - **Rationale**: My RXN-06 flagged the absence of an outer timeout bound for parallel dispatch, but I did not extend the analysis to the missing `.partial` sentinel and flux-watch monitoring contract. `launch.md:293-295` establishes a concrete completion-wait model (flux-watch, `.partial`-only retry-once, error stubs on second failure) that Phase 2.5 never references. The gap is real and orthogonal to what I found: RXN-06 is about liveness of in-flight agents, ARCH-01 is about the collection barrier — both must be fixed and they do not subsume each other.
  - **Evidence**: `interverse/interflux/skills/flux-drive/phases/launch.md:293-295` (Phase 2 monitoring contract); `interverse/interflux/skills/flux-drive/phases/reaction.md:52` (reaction dispatch has no equivalent wait step)

- **Finding**: REACT-02
  - **Stance**: agree
  - **Move Type**: defense
  - **Independent Coverage**: partial
  - **Rationale**: My RXN-04 identified the awk normalisation stripping hyphens from finding titles, which is the same code path that feeds `{peer_findings}` into the reaction prompt — but I did not follow the injection vector to the LLM boundary. fd-safety correctly identifies that `_interspect_sanitize` (with its injection-pattern rejection at `lib-interspect.sh:2725-2731`) is only wired to the DB insertion path (`_interspect_insert_evidence:2778-2781`), not to the prompt-assembly path at `reaction.md:50`. The threat is concrete under the AGENTS.md trust boundary defined at `CLAUDE.md:49-54`: flux-gen agents are generated outputs, not hand-authored, and their Findings Index lines pass verbatim into `{peer_findings}`. My independent contribution is that the same awk loop (`findings-helper.sh:119`) that strips hyphens also preserves the title body verbatim after prefix removal — confirming that no sanitization occurs between file read and template fill.
  - **Evidence**: `interverse/interflux/scripts/findings-helper.sh:119` (title body preserved verbatim); `interverse/interspect/hooks/lib-interspect.sh:2706-2731` (_interspect_sanitize scope, DB only); `interverse/interflux/skills/flux-drive/phases/reaction.md:50` ({peer_findings} injected directly)

- **Finding**: REACT-08
  - **Stance**: agree
  - **Move Type**: defense
  - **Independent Coverage**: no
  - **Rationale**: My RXN-09 flagged that `convergence_before` records the post-discount value under a misleading field name, but I did not examine the `_interspect_insert_evidence` call site for truncation behaviour. `_interspect_sanitize` defaults to 500 chars (`lib-interspect.sh:2708`), and the call at `_interspect_insert_evidence:2781` passes `context_json` with no override argument, confirming the 500-char limit is active. The `_interspect_emit_reaction_dispatched` function assembles a 10-field JSON object (`lib-interspect.sh:2978-2993`) using jq, which produces compact JSON; a realistic `input_path` of `/home/user/projects/Sylveste/.flux-drive-output/2026-04-02T143000Z-reaction/` already consumes ~75 chars before any other field. The JSON silently becomes `{}` on truncation (the `|| context="{}"` fallback is at `lib-interspect.sh:2993`), making the evidence row useless without any error signal to the operator. This is a data-integrity finding, distinct from my labelling issue at RXN-09, and both must be fixed.
  - **Evidence**: `interverse/interspect/hooks/lib-interspect.sh:2708` (default 500-char limit); `interverse/interspect/hooks/lib-interspect.sh:2781` (no max_chars override at call site); `interverse/interspect/hooks/lib-interspect.sh:2993` (silent {} fallback)

## Reactive Additions Index

- P1 | RXN-12 | "Step 2.5.3-4" | Reaction agents have no completion-wait contract — flux-watch, .partial sentinel, and retry-once are absent (provenance: reactive, from ARCH-01)
- P1 | RXN-13 | "Step 2.5.3-4 / reaction-prompt.md" | Peer findings content injected into LLM prompt without sanitization — _interspect_sanitize is DB-scoped only (provenance: reactive, from REACT-02)
- P1 | RXN-14 | "Step 2.5.5 / lib-interspect.sh" | context_json for reaction-dispatched evidence silently truncated to 500 chars and collapsed to {} — loses all structured fields when input_path is long (provenance: reactive, from REACT-08)

### Verdict

adds-evidence
