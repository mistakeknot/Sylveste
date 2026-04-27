---
artifact_type: architecture-review
method: flux-review
target: docs/prds/2026-04-27-clavain-peer-coexistence.md
bead: sylveste-4ct0
date: 2026-04-27
reviewer: fd-architecture
verdict: CONDITIONAL_APPROVE
---

# Architecture Review — Clavain Peer-Coexistence PRD (sylveste-4ct0)

## Severity Counts

| Severity | Count |
|---|---|
| P0 | 0 |
| P1 | 3 |
| P2 | 2 |
| P3 | 1 |
| **Total** | **6** |

**Tier 2 gate: CONDITIONAL_APPROVE.** No P0s. Three P1s require resolution before implementation begins — two are correctness issues the PRD underestimates, one is a schema breakage. P2s are clean-up items. P3 is informational.

---

## Findings, Ranked by Severity

---

### [P1-1] F1 schema change breaks three downstream consumers that are not mentioned in the PRD

**Finding:** The PRD states "no compatibility shim" for dropping `plugins.conflicts` and calls this safe because "peers are internal config." This is incorrect. Three files outside `modpack-install.sh` parse the `plugins.conflicts` key directly from `agent-rig.json`:

1. `/home/mk/projects/Sylveste/os/Clavain/scripts/verify-config.sh` line 48: `jq -r '[.plugins.conflicts[]?.source] | sort | .[]'`. This is invoked by `/clavain:setup` Step 6 and by `/clavain:doctor`. After the rename it will silently produce an empty conflicts list and report `0/0 disabled` — a false PASS.
2. `/home/mk/projects/Sylveste/os/Clavain/commands/doctor.md` section 4 ("Conflicting Plugins") contains a hardcoded Python list that includes `superpowers@superpowers-marketplace` and `compound-engineering@every-marketplace` — both proposed `peers` entries. This list is not derived from `agent-rig.json`; it is a duplicate. After the reclassification, doctor will still flag peers as WARN even after setup correctly leaves them enabled.
3. `/home/mk/projects/Sylveste/os/Clavain/commands/setup.md` Step 3 manual fallback block (lines 95–108) lists `superpowers` and `compound-engineering` under a `<!-- agent-rig:begin:disable-conflicts -->` fenced region and runs `claude plugin disable` against them. This block is the hardcoded fallback when `modpack-install.sh` is unavailable; it bypasses all of F2's detect-and-ask logic.

**Smallest fix:** The PRD's F1 acceptance criterion must be expanded to include: (a) update `verify-config.sh` to read both `plugins.hard_conflicts` and `plugins.peers` (treating peers as expected-present, not expected-disabled); (b) update the doctor Section 4 Python block to split the two lists; (c) remove peers entries from setup.md's manual disable fallback block. All three are in-scope for A scope — none requires additional abstraction.

---

### [P1-2] F2 `--apply` flag semantics conflict with the existing dry-run-by-default pattern

**Finding:** The current script has a single mode bit: `DRY_RUN=false` by default, flipped to `true` by `--dry-run` or `--check-only`. The PRD introduces `--apply` as the flag that permits mutation for `hard_conflicts`, while stating "default: dry-run report only." This inverts the current contract.

Today's behavior: no flag = live (mutates). `--dry-run` = no mutation. The PRD's proposed behavior: no flag = dry-run (no mutation). `--apply` = live (mutates for hard_conflicts). These two models are contradictory, and the PRD's F2 acceptance criterion makes it worse:

> "Running `modpack-install.sh` (no flags) without `--apply` does not call `claude plugin disable` for any peer."

That criterion is already satisfied by the existing script for the newly-created `peers` category, regardless of whether `--apply` exists. But the criterion's framing suggests the no-flag default for `hard_conflicts` also changes — which would be a **breaking change** to the behavior `/clavain:setup` Step 2 relies on. Setup Step 2 calls `$INSTALL_SCRIPT --quiet` (no flags) and expects conflicts to be disabled. The PRD Open Question 3 acknowledges this uncertainty but defers it.

**Smallest fix:** Do not introduce `--apply`. The correct minimal change is: add a `process_peers()` function that only reports (never calls `disable_plugin`), and leave `process_category("hard_conflicts")` calling `disable_plugin` exactly as `process_category("conflicts")` does today. The `--dry-run` flag continues to suppress mutation across all categories as it does now. This is a two-function split with no flag changes, consistent with the existing control flow.

---

### [P1-3] F2 JSON output schema change is backward-incompatible with setup.md's parser

**Finding:** setup.md Step 2 parses the JSON output with: `**installed** (list), **already_present** (count), **failed** (warn each), **disabled**, **optional_available**`. The `disabled` key is consumed by the summary line "Conflicts disabled: [X/8 disabled]" in Step 7.

F2 adds `peers_detected` and `peers_active` to the JSON output but does not mention what happens to the `disabled` and `would_disable` keys when peers are excluded from that list. The existing keys must be preserved exactly — `disabled` still refers to `hard_conflicts` entries that were actually disabled. If `peers` were previously counted in `disabled` (they would have been under the old `conflicts` category) and are now absent from `disabled`, the Step 7 count drops from `10/10` to `8/8`, which is behaviorally correct but the setup.md text "Conflicts disabled: [X/8 disabled]" becomes stale ("8 disabled" when there are now 8 hard_conflicts). This is a documentation drift issue, not a parse failure, but setup.md's hardcoded `8` count reference needs updating.

The `peers_detected` and `peers_active` keys are purely additive and do not break existing JSON consumers — that part of the schema change is safe. The backward-compatibility concern is narrowed to: setup.md must update its conflict count reference from 10 to 8 (or make the count dynamic), and Step 3's manual fallback must remove the two peer entries.

**Smallest fix:** Add `peers_detected`/`peers_active` as documented (additive, safe). Update setup.md Step 3 and Step 7 to reflect the narrowed conflict list. Mark this explicitly in F2 acceptance criteria.

---

### [P2-1] F4 "works in both Claude Code and Codex CLI runtimes" acceptance criterion is undeliverable as written

**Finding:** Slash commands (`commands/peers.md`) are Claude Code-specific. The Codex runtime uses a separate skill loading path (`~/.agents/skills/clavain`) via `install-codex-interverse.sh`, which copies skills but not commands. The PRD itself acknowledges this in the Non-goals section: "Codex CLI side of the install flow... F4 should degrade cleanly on Codex." The acceptance criterion and the non-goal contradict each other.

Additionally, doctor.md establishes the conventions for read-only commands in this codebase. Its contract is: "Read-only diagnostic. Never makes changes (exception: zombie bead auto-close)." F4 duplicates this intent but for peers. There is no convention marker (e.g., a frontmatter field like `mutates: false`) enforcing read-only intent — the convention is prose-only in the command description. This is consistent with doctor.md's own approach, so F4 does not need to invent a new enforcement mechanism; it should mirror doctor.md's prose convention exactly.

**Smallest fix:** Change the F4 acceptance criterion from "works in both... runtimes" to "works in Claude Code; degrades with a clear `[Codex: /clavain:peers is Claude Code only — run modpack-install.sh --dry-run for peer status]` message when invoked outside Claude Code." The Codex-parity surface, if needed, is a separate skill or a `--peers` flag on the existing Codex doctor script — both are out of scope for A scope.

---

### [P2-2] F3 bridge skills unconditionally consume context tokens for users without the relevant peers

**Finding:** The PRD acceptance criterion requires bridge skill `description` fields to use the "Use when..." trigger pattern so the model auto-loads them when peer commands are mentioned. The SessionStart hook in Clavain injects `using-clavain` skill content via `additionalContext`. Bridge skills would be loaded only on-demand (not at session start), so they do not incur unconditional per-session token cost — this is less severe than the question prompt implied.

However, there is a residual issue: both bridge skills (`interop-with-superpowers`, `interop-with-gsd`) will appear in the plugin's registered skill list and will be offered by `/clavain:help`. For users who have neither peer, these two skills add noise to the skill listing and may be accidentally invoked. The PRD does not specify whether these skills should be conditionally registered or always registered.

This is a minor discoverability trade-off, not a token cost problem. The existing codebase has no pattern for conditional skill registration based on installed peers, and adding one would exceed A scope.

**Smallest fix:** Accept unconditional skill listing as a known trade-off. Add a one-line note to each bridge skill's `description`: "If [peer] is not installed, this skill is informational only." No architecture change required.

---

### [P3-1] `process_category()` requires refactoring beyond what the PRD's complexity estimate accounts for

**Finding:** The PRD states F2 "adds a new `process_peers()` path" as if it is a straightforward addition. The current `process_category()` function uses a `case` statement where the category name directly maps to both the JSON key and the behavior. Adding `hard_conflicts` and `peers` requires:

1. Renaming the `conflicts` case to `hard_conflicts` in the case statement.
2. Adding a `peers` case that calls a new `process_peers()` function.
3. Updating the `CATEGORY="all"` main block to call `process_category "hard_conflicts"` and `process_category "peers"` instead of `process_category "conflicts"`.
4. Updating the `--category=` validation allowlist (line 234) to accept `hard_conflicts` and `peers` and reject the legacy `conflicts`.
5. Updating result accumulator arrays: adding `peers_detected=()` and `peers_active=()`.
6. Updating the JSON output blocks at lines 272–289 to emit the new keys.

That is six distinct edit sites in the script, none individually complex, but the PRD's inline description ("adds a new `process_peers()` path") understates this as a single addition. An implementer reading the PRD would be surprised by the breadth of changes. This does not block implementation — the changes are mechanical — but the plan phase should enumerate all six sites to avoid partial edits.

**Smallest fix:** No architecture change required. The plan document for this bead should enumerate the six edit sites explicitly.

---

## Summary for Tier 2 Gate

No P0s. The three P1 findings are all correctness issues that are resolvable within A scope:

- P1-1 requires explicitly expanding F1 acceptance criteria to cover `verify-config.sh`, the doctor's Python block, and setup.md's manual fallback. All three files are already in-scope as companions to `agent-rig.json`.
- P1-2 recommends discarding the `--apply` flag entirely in favor of a simpler two-function split with no flag changes, eliminating the ambiguity entirely.
- P1-3 is a documentation update (setup.md conflict count) plus the same fallback block edit as P1-1.

P1-1 and P1-3 share the same fix target (setup.md Step 3 + doctor.md Section 4). Resolving P1-1 covers the critical part of P1-3 as a side effect.

**Recommended disposition:** Revise PRD acceptance criteria for F1 and F2 to incorporate the three downstream consumers identified in P1-1, adopt the simplified flag semantics in P1-2, and proceed. No blocking architectural issues.
