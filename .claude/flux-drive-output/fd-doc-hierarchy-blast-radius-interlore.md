# fd-doc-hierarchy-blast-radius-interlore

Review of Task 1 (doc hierarchy migration) from `/home/mk/projects/Demarch/docs/plans/2026-03-21-interlore.md`.

---

## P0: MISSION.md in plugin-standard.md makes 48 plugins non-conformant

**File:** `/home/mk/projects/Demarch/docs/canon/plugin-standard.md` (line 118-145, AGENTS.md Standard Header)

**What the plan says:** Step 4 instructs "add MISSION.md alongside PHILOSOPHY.md in the canonical references" in the AGENTS.md Standard Header section of plugin-standard.md.

**What actually happens:** The AGENTS.md Standard Header (lines 120-145) is described as "identical across all plugins". 48 plugins currently implement this boilerplate. Adding `MISSION.md` to the boilerplate template means the canonical standard now requires a reference that zero plugins satisfy. No plugin has a local MISSION.md (confirmed: `ls interverse/*/MISSION.md` returns 0 files).

**The ../../MISSION.md path is also fragile.** Only 15/48 plugins currently use `../../PHILOSOPHY.md` paths. 12 use `./PHILOSOPHY.md` (pointing to their local copy). 21 use bare backtick references with no path. When plugins are used outside the monorepo (standalone clones), `../../MISSION.md` resolves to nothing. The `./PHILOSOPHY.md` pattern works because every plugin has its own local PHILOSOPHY.md (52/53 plugins). No equivalent local MISSION.md exists.

**Failure scenario:** After Task 1, plugin-standard.md says the AGENTS.md header should reference MISSION.md. Every `interdoc` or `interscribe` regen will either (a) inject a broken `../../MISSION.md` link into all 48 plugin AGENTS.md files, or (b) flag all 48 plugins as non-conformant. Either outcome creates immediate ecosystem churn.

**Recommended fix:** Do NOT add MISSION.md to the plugin-standard.md AGENTS.md boilerplate. Instead, add it only to the root-level AGENTS.md and to interlore's AGENTS.md (which lives in the monorepo and validly reaches `../../MISSION.md`). If MISSION.md reference is desired in the standard, add a conditional note: "For monorepo plugins, optionally reference `../../MISSION.md`."

---

## P1: PHILOSOPHY.md "trim" is underspecified -- duplication risk

**Files:** `/home/mk/projects/Demarch/PHILOSOPHY.md` (lines 1-5), `/home/mk/projects/Demarch/MISSION.md` (to be created)

**What the plan says:** Step 2 replaces PHILOSOPHY.md's opening with: "The design bets, tradeoffs, and principles that guide how we build. See MISSION.md for why this project exists."

**Current PHILOSOPHY.md opening (lines 1-5):**
```
# Demarch Philosophy
The design bets, tradeoffs, and convictions that inform everything else.
CLAUDE.md says *how to work here*. AGENTS.md says *what to build and how*. This document says *why these tradeoffs and not others*.
```

**Issue:** The current opening is navigational ("CLAUDE.md says X, AGENTS.md says Y, this doc says Z"). The proposed MISSION.md content ("Build the infrastructure that lets AI agents do real software engineering work autonomously, safely, and at scale...") overlaps with PHILOSOPHY.md's Core Bet section (line 17-26), specifically bet #1: "Infrastructure unlocks autonomy. The bottleneck for agent capability is infrastructure..." This is not trimming from the opening -- it is semantic overlap with the body.

**The verify block does not check for overlap.** The `<verify>` section (lines 121-128) only checks that MISSION.md exists and that doc-structure.md and plugin-standard.md reference it. There is no verification that PHILOSOPHY.md was actually trimmed or that the two documents are semantically non-overlapping.

**Recommended fix:** Add a verify step: `grep -c "why these tradeoffs" PHILOSOPHY.md` expecting 0 (confirming the old navigational text was removed). Consider also verifying that PHILOSOPHY.md line 1-5 does NOT contain "infrastructure" or "bottleneck" (to guard against accidental duplication with MISSION.md).

---

## P1: VISION.md is a dangling reference in the hierarchy diagram

**File:** `/home/mk/projects/Demarch/docs/canon/doc-structure.md` (proposed new content, plan lines 78-110)

**What the plan says:** The new hierarchy diagram (plan line 85) shows:
```
MISSION.md       -- why the project exists (rarely changes)
  +-> VISION.md   -- where it's going (existing: docs/demarch-vision.md)
  +-> PHILOSOPHY.md -- how we build (design bets, principles)
```

And the table (plan line 93) says: "VISION.md | Quarterly | Human, interpath drafts".

**Actual state:** There is no `VISION.md` at the project root. The existing document is at `/home/mk/projects/Demarch/docs/demarch-vision.md`. The parenthetical "(existing: docs/demarch-vision.md)" is documentation, not a task step. No step in Task 1 (or any other task) creates `VISION.md` or creates a symlink/alias from `VISION.md` to `docs/demarch-vision.md`.

**Failure scenario:** After Task 1, doc-structure.md declares VISION.md as part of the root hierarchy. Any agent reading the hierarchy and trying to `Read VISION.md` at the project root will get a file-not-found error. The conflict resolution rule (plan line 96: "MISSION.md takes precedence when VISION and PHILOSOPHY conflict") references a document that does not exist at the declared path.

**Recommended fix:** Either (a) add a step to Task 1 that creates a root-level `VISION.md` symlink or stub pointing to `docs/demarch-vision.md`, or (b) change the hierarchy diagram to use the actual path `docs/demarch-vision.md` instead of `VISION.md`. Option (b) is simpler and avoids creating yet another root file.

---

## P2: doc-structure.md line numbers are correct but replacement scope is ambiguous

**File:** `/home/mk/projects/Demarch/docs/canon/doc-structure.md`

**Current lines 76-87:**
```
76: ## docs/canon/
77: (blank)
78: Foundational docs that define project identity and standards...
...
85: ```
86: (blank)
87: Root keeps: CLAUDE.md, AGENTS.md (operational, auto-loaded)...
```

**What the plan says:** "Replace the `docs/canon/` section (lines 76-87) with the new hierarchy" -- but the replacement content (plan lines 78-110) is ~32 lines, far larger than the 12-line section being replaced. The new content adds the "Document Hierarchy" section, a table, a conflict resolution rule, AND a replacement `docs/canon/` section.

**Issue:** The instruction says "replace lines 76-87" but the new content is a major insertion that should probably replace from line 76 through end-of-file (line 87 is the last substantive line before the Enforcement section at line 89). The Enforcement section (lines 89-97) is not mentioned in the replacement -- is it kept, deleted, or moved?

**Recommended fix:** Clarify that the new content replaces lines 76-87 specifically, with the Enforcement section (lines 89-97) preserved below the new content. Or if the intent is to replace 76-EOF, state that explicitly.

---

## P2: interlore's AGENTS.md uses new boilerplate, not old

**File:** Plan lines 232-261 (interlore AGENTS.md template in Task 2)

**Finding:** interlore's proposed AGENTS.md uses a modified boilerplate that differs from the current plugin-standard.md standard header (lines 120-145):

| Current standard (plugin-standard.md) | interlore's proposed AGENTS.md |
|---|---|
| `# <plugin-name> -- Development Guide` | `# AGENTS.md -- interlore` |
| Canonical Ref 1: `PHILOSOPHY.md` only | Canonical Ref 1: `MISSION.md`, Ref 2: `PHILOSOPHY.md` |
| Full 6-item phase list for alignment protocol | Compressed single-line: "during intake, brainstorming, planning, execution, review, and handoff" |
| No "If a high-value change conflicts..." clause omission | Missing the "adjust the plan to align, or create follow-up work" clause |

This is intentional (interlore is the first plugin to use the new hierarchy). But it creates a chicken-and-egg problem: Task 1 updates plugin-standard.md, Task 2 creates interlore using the updated standard. If Task 2 runs before Task 1 (they are marked as parallel), the interlore AGENTS.md won't match the standard that doesn't exist yet. The plan notes (line 825) says they "can run in parallel" but Step 4 of Task 1 must complete before Task 2's AGENTS.md content is valid against the updated standard.

**Recommended fix:** Note the ordering dependency explicitly, or accept that interlore's AGENTS.md may need a post-Task-1 fixup pass.

---

## P3: Existing PHILOSOPHY.md reference inconsistency across plugins (pre-existing)

48 plugins reference PHILOSOPHY.md in their AGENTS.md, but with three different path patterns:
- 15 plugins: `../../PHILOSOPHY.md` (relative to monorepo root)
- 12 plugins: `./PHILOSOPHY.md` (local copy)
- 21 plugins: bare `` `PHILOSOPHY.md` `` (backtick, no link)

This pre-existing inconsistency means any MISSION.md addition will inherit the same fragmentation unless the standard specifies the exact path form. Task 1 does not address this. Not a blocker, but adding MISSION.md to the boilerplate without standardizing the path format will create 3 variants of MISSION.md references within weeks.

---

## Summary

| ID | Severity | Issue | Location |
|---|---|---|---|
| 1 | P0 | Adding MISSION.md to plugin-standard.md boilerplate makes 48 plugins non-conformant; no plugin has a local MISSION.md | plugin-standard.md lines 120-145 |
| 2 | P1 | Verify block does not check PHILOSOPHY.md was trimmed; semantic overlap with MISSION.md unguarded | Plan lines 121-128, PHILOSOPHY.md lines 1-5 vs 17-26 |
| 3 | P1 | VISION.md is referenced in hierarchy but does not exist at root; no task creates it | Plan lines 85, 93; actual file at docs/demarch-vision.md |
| 4 | P2 | Replacement scope for doc-structure.md lines 76-87 ambiguous (12 lines replaced by 32) | Plan line 76, doc-structure.md lines 76-97 |
| 5 | P2 | interlore AGENTS.md uses new boilerplate before plugin-standard.md is updated; parallel execution risk | Plan lines 232-261 vs plan line 825 |
| 6 | P3 | Pre-existing 3-way path inconsistency for PHILOSOPHY.md references will propagate to MISSION.md | 48 plugin AGENTS.md files |
