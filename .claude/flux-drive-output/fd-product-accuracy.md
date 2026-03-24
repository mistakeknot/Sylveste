# fd-product-accuracy -- Findings

## Summary

The three core CUJs (first-install, running-a-sprint, code-review) contain 14 product-accuracy issues: incorrect CLI syntax for plugin installation, present-tense claims about features that are in shadow mode or not yet shipped, incorrect status value casing in bd assertions, and an actor label that contradicts the prerequisite reality. Several Interspect routing claims are stated as current behavior when they are Phase 2 or shadow-only.

## Findings

### [P1] first-install.md:25 -- `claude install clavain` is not the actual install command

**Issue:** The CUJ says `claude install clavain`. The actual command is `claude plugins install clavain@interagency-marketplace` (per install.sh, plugin-troubleshooting.md, and the first-stranger-experience PRD). The user must also first add the marketplace via `claude plugins marketplace add`. The shorthand `claude install` does not exist as a Claude Code CLI subcommand.

**Fix:** Replace `claude install clavain` with the actual two-step process, or reference the `curl` install script from the README (`curl -fsSL .../install.sh | bash`) which handles both steps. Update the success signals on lines 40-41 to match.

---

### [P1] first-install.md:25 -- "from the marketplace" implies a browsable plugin store

**Issue:** The phrase "install the Clavain plugin from the marketplace" suggests a discoverable storefront. The actual marketplace is a JSON file in a git repo (`core/marketplace/.claude-plugin/marketplace.json`). There is no browsable UI, no search, no ratings. The plugin-discovery-install CUJ (line 19) acknowledges this with `claude plugin list` marked as aspirational ("or the equivalent marketplace UI"), but first-install.md presents it as a seamless experience.

**Fix:** Replace "from the marketplace" with "from the Interverse plugin registry" or similar phrasing that doesn't imply a storefront. Add to Known Friction Points that plugin discovery currently requires knowing the plugin name.

---

### [P2] first-install.md:4 -- Actor label "stranger" contradicts Go prerequisite

**Issue:** The actor is "stranger (new platform user, no prior Demarch exposure)" and the journey aims for zero-config ("without requiring manual configuration"). But the README lists Go 1.22+ as a **required** prerequisite, and `bd` (beads CLI) requires `go install github.com/mistakeknot/beads/cmd/bd@latest`. A developer without Go installed hits a wall before reaching `/clavain:project-onboard`. The CUJ acknowledges this in Known Friction Points (line 53) but the journey prose doesn't reflect the friction -- it reads as though install is seamless.

**Fix:** Either (a) add a sentence in the journey prose acknowledging the Go prerequisite and its impact, or (b) update the actor label to "stranger (developer with Go toolchain)" to set expectations. The current disconnect between the narrative and reality will confuse readers who try to validate the journey.

---

### [P2] first-install.md:47 -- `bd show` reports status as lowercase, not CLOSED

**Issue:** Success signal says `bd show <bead-id>` reports status CLOSED (uppercase). Actual `bd show --json` output uses lowercase `"status": "closed"`. The human-readable output also uses lowercase.

**Fix:** Change "reports status CLOSED" to "reports status `closed`" (lowercase). Same fix needed in running-a-sprint.md:69.

---

### [P2] running-a-sprint.md:69 -- `bd show <id>` shows CLOSED status -- same casing error

**Issue:** Same as above. "shows CLOSED status, all state fields populated" uses wrong case.

**Fix:** Change to "shows `closed` status". Also: "all state fields populated" is vague -- bd does not have a fixed set of "state fields." Sprint state is stored in bd's key-value state store (`bd state`), not in the core issue fields. The assertion should specify which fields: status, close_reason, closed_at.

---

### [P1] running-a-sprint.md:31 -- Model routing per subtask is claimed as present-tense but is in shadow mode

**Issue:** "The agency uses the cheapest model that clears the quality bar for each subtask: Haiku for simple edits, Sonnet for moderate reasoning, Opus for complex logic, Codex for parallel implementation. Model selection is guided by the routing table, which Interspect adjusts based on outcome data." This is stated as current behavior. In reality: (1) complexity-based routing (`routing.yaml` complexity section) is `mode: shadow` -- it logs what would change but applies base routing; (2) calibration-based routing is also `mode: shadow`; (3) the base routing table does use different models per phase/category (haiku for research, sonnet for review), but per-subtask complexity routing is not enforced.

**Fix:** Add a caveat: "*(Complexity-aware model routing is active in shadow mode -- the system classifies tasks and logs recommended models, but base routing is applied. Enforced routing is planned.)*" Also clarify that the routing table currently operates at the phase/category level, not per individual subtask.

---

### [P2] running-a-sprint.md:38 -- "Interspect adjusts [routing] based on outcome data" -- no Phase 2 annotation

**Issue:** The reflect phase description says routing adjustments happen automatically. The Interspect calibration pipeline (`/interspect:calibrate`) exists and computes scores, but it writes to `routing-calibration.json` in `mode: shadow`. Automatic routing adjustment from reflect data is not enforced. This needs a caveat.

**Fix:** Add: "*(Calibration data is collected; automatic routing enforcement is planned. Currently operates in shadow mode -- see [Interspect Agent Learning](interspect-agent-learning.md).)*"

---

### [P2] running-a-sprint.md:81 -- "write-behind protocol" presented as shipped infrastructure

**Issue:** "The write-behind protocol (raw output to kernel, summaries to context) mitigates this" -- there is no implemented protocol called "write-behind" in Clavain. The concept appears in a brainstorm doc (`2026-02-16-subagent-context-flooding-brainstorm.md`) as a proposal. The sprint command does write artifacts to disk and read from files (behavioral rule #2), but there is no kernel-level write-behind protocol. This Known Friction Point cites non-existent infrastructure as a mitigation.

**Fix:** Replace with: "The convention of writing agent output to files and reading summaries into context mitigates this, but very long sprints may still hit quality degradation in later phases." Remove the term "write-behind protocol" which implies a formal subsystem.

---

### [P2] running-a-sprint.md:47 -- "the kernel has recorded every phase transition" overstates kernel coverage

**Issue:** "the kernel has recorded every phase transition, every artifact, every dispatch" implies Intercore records all sprint events. In practice, sprint state is managed by Clavain's `clavain-cli` (checkpoint-write, sprint-read-state) and stored in beads state (`bd state`), not in the Intercore kernel's event system. Intercore's event pipeline (E2) exists but the sprint lifecycle is primarily tracked by Clavain's own state management.

**Fix:** Replace "the kernel has recorded" with "Clavain has recorded" or "the sprint state machine has recorded". Reserve "kernel" for Intercore-specific operations.

---

### [P1] code-review.md:52 -- Success signal claims Interspect adjusts routing, no Phase 2 annotation

**Issue:** "Interspect adjusts routing based on review outcomes" is listed as an observable success signal with no caveat. The code-review journey prose correctly annotates two Phase 2 items (lines 25 and 33), but this success signal presents the same capability as shipped. The evidence collection pipeline is active (disagreement events are recorded), but the path from evidence to routing adjustment requires manual steps (`/interspect:propose` then `/interspect:approve`). Automated adjustment is Phase 2.

**Fix:** Add annotation: "Interspect adjusts routing based on review outcomes *(manual via `/interspect:propose` + `/interspect:approve`; automated adjustment is Phase 2)*"

---

### [P2] code-review.md:38 -- "the review gets better" implies automatic improvement

**Issue:** "Over time, the review gets better. Agents that produce noise get downweighted or excluded." This implies automatic, closed-loop improvement. The actual mechanism requires manual correction recording (`/interspect:correction`), then manual proposal (`/interspect:propose`), then manual approval (`/interspect:approve`), then a canary period. The improvement is real but manual, not automatic.

**Fix:** Add a sentence: "This improvement currently requires explicit feedback -- the developer records corrections and approves routing proposals. Fully automated adjustment from dismissal patterns is planned."

---

### [P3] code-review.md:25 -- "override chain is active" annotation may overstate

**Issue:** The parenthetical says "the override chain is active, but automated feedback from review dismissals to routing adjustments is Phase 2." The override chain is active in the sense that `routing-overrides.json` is read by flux-drive if it exists, and the propose/approve commands can write to it. But this phrasing could imply that routing overrides are being actively applied from real evidence data. In most fresh installs, no overrides exist.

**Fix:** Minor: consider rephrasing to "the manual override pipeline is functional (propose/approve/canary), but automated feedback from review dismissals to routing adjustments is Phase 2."

---

### [P3] running-a-sprint.md:53 -- "context from the previous session is gone" is accurate but incomplete

**Issue:** The CUJ correctly notes that context windows don't survive sessions. However, it then says "the agency re-reads the plan and the relevant code, orients on where it left off" -- this implies automatic context reconstruction. In practice, the checkpoint tells the sprint command which steps are completed, and it re-reads artifacts, but there is no mechanism to automatically re-read "the relevant code." The agent starts fresh and relies on the plan document to know what files to read.

**Fix:** Clarify: "The agency re-reads the plan document and picks up from the first incomplete step. Code context is rebuilt as the agent works through remaining steps, not pre-loaded at resume time."

---

### [P3] first-install.md:27 -- `/clavain:project-onboard` described as creating .beads/ but Go is required

**Issue:** The journey says project-onboard "initializes beads tracking" as part of its flow. But `bd init` (which project-onboard calls) requires the `bd` binary, which requires Go to install. If the user doesn't have Go, project-onboard will silently skip beads initialization or error. The CUJ doesn't note this dependency chain.

**Fix:** Add to Known Friction Points: "Beads initialization requires the `bd` CLI (Go binary). Project-onboard will skip beads setup if `bd` is not installed, leaving the sprint lifecycle without work tracking."
