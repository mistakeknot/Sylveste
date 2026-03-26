# Film/VFX Revision Pipelines: Patterns for AI Agent Output Disposition

**Research type:** Flux-drive domain transfer analysis
**Domain source:** Film/VFX dailies review workflows (ShotGrid/Flow Production Tracking, ftrack, Netflix partner specs)
**Target domain:** AI agent output review, rework, and disposition

---

## 1. The VFX Status State Machine

VFX production tracks every deliverable (shot, asset, version) through a well-defined state machine. The canonical status progression from CAVE Academy / ShotGrid convention:

### Prep statuses
- **Bid** -- work scoped but not started (equivalent: task queued, cost estimated)
- **Omit** -- editorial has cut this shot from the show; work stops immediately
- **On Hold** -- supervisor or client paused work; may resume later

### WIP statuses
- **Ready to Start** -- upstream dependencies met, artist can begin
- **In Progress** -- actively being worked
- **Pending Internal Review** -- version submitted to internal dailies

### Version statuses (per-revision, not per-shot)
- **Pending Review** -- submitted to dailies playlist
- **In Review** -- supervisor actively looking at it
- **Revise** -- rejected with notes; goes back to WIP
- **Approved** -- passed internal review
- **CBB (Could Be Better)** -- approved but on the improvement list if time permits

### Tech check statuses (QC gate after creative approval)
- **Pending Tech Check** -- awaiting automated/manual QC
- **Tech Check Failed** -- creative is fine but technical specs wrong (colorspace, resolution, edge quality)
- **Tech Check Passed** -- cleared for delivery

### Finaling statuses
- **Pending Client Review** -- submitted to client via review system
- **Client Revise** -- client rejected with notes
- **Client Approved** -- client accepted
- **Proposed Final** -- submitted as final candidate
- **Final** -- locked, delivered to editorial, no further work

### Key insight for AI agents
This is not a simple pass/fail. There are at minimum **four distinct rejection types** (internal revise, tech fail, client revise, omit) and **two approval tiers** (approved-good-enough vs. approved-could-be-better). An AI rework model that only has "pass" and "fail" is missing the resolution that makes VFX pipelines work at scale.

---

## 2. Conditional Approval: The CBB Pattern

CBB ("Could Be Better") originated at ILM during the original Star Wars trilogy. It represents a shot that is **approved for use in the cut** but remains on a list for improvement if schedule and budget permit.

### How CBB works in practice
1. Supervisor reviews version in dailies
2. Shot meets the bar for the sequence -- it won't break immersion
3. But there are known improvements (edge quality, lighting match, subtle animation)
4. Shot gets status `CBB` rather than `Approved`
5. CBB list is maintained separately; artists pull from it when primary work is done
6. As deadline approaches, remaining CBBs are bulk-promoted to `Final`

### Translation to AI agent output

| VFX concept | Agent equivalent |
|---|---|
| CBB shot | Output that passes validation but has known quality debt |
| CBB list | Backlog of "polish if budget remains" tasks |
| Bulk CBB promotion at deadline | Accept-all-remaining when iteration budget exhausted |
| CBB with specific notes | Structured improvement hints attached to accepted output |

This gives a middle path between hard-reject-and-rework and unconditional-accept. The agent system can accept an output for downstream use while tracking that it could be improved, and only revisit if resources are available.

---

## 3. Two-Tier Review: Internal Dailies vs. Client Review

VFX uses a **two-tier review architecture** where work must pass internal review before external stakeholders ever see it.

### Internal dailies (Tier 1)
- Daily or near-daily sessions
- VFX supervisor + lead artists review all submitted versions
- High-frequency, low-ceremony
- Focus: creative direction, technical approach, consistency within sequence
- Rejection here is cheap -- artist gets notes same day, iterates

### Client review (Tier 2)
- Scheduled sessions (weekly or per-milestone)
- Director, producer, studio review approved versions
- Low-frequency, high-ceremony
- Focus: story, editorial fit, overall quality bar
- Rejection here is expensive -- may invalidate approach, not just execution

### Parallel quality streams
Studios often maintain parallel quality levels:
- **Proxy/WIP playblasts** for internal review (fast, low-cost to produce)
- **Full-quality renders** for client review (expensive to produce)
- An artist doesn't render at final quality until internal dailies approve the creative direction

### Translation to AI agents

| VFX tier | Agent equivalent |
|---|---|
| Internal dailies | Automated validation + self-review before human exposure |
| Client review | Human review of pre-validated outputs |
| Proxy playblast | Lightweight/draft output for fast iteration |
| Full render | Final-quality output only after direction confirmed |
| Two-tier cost model | Don't spend expensive tokens on outputs that would fail cheap checks |

This maps directly to a "gate before gate" pattern: run cheap automated checks (linting, test execution, format validation) before requesting expensive human review. Never waste human attention on outputs that would fail automated checks.

---

## 4. Version Numbering and Rework Identity

VFX enforces strict version identity: every submission is a new version (`v001`, `v002`, `v003`...) of the same shot. Old versions are never overwritten.

### Netflix naming convention
```
<show>_<sequence>_<shot>_<department>_v<NNN>
```
Example: `SHOW_010_0100_comp_v003`

### Properties of this system
- **Immutable versions:** v001 is v001 forever. If rejected, you create v002.
- **Full history:** Supervisor can scrub through all versions to see progression
- **Regression detection:** If v003 looks worse than v002, it's immediately visible
- **Notes attached per-version:** Each version carries its own review notes
- **No in-place mutation:** You never "fix v002"; you create v003 with the fix

### Translation to AI agents

| VFX concept | Agent equivalent |
|---|---|
| Immutable versions | Every agent attempt is a distinct, preserved artifact |
| Version scrubbing | Ability to compare attempt N with attempt N-1 |
| Regression detection | Automated check that new attempt doesn't break what previous attempt got right |
| Per-version notes | Structured feedback attached to each attempt, not just "try again" |
| No in-place mutation | Never silently overwrite a previous output; always create a new versioned attempt |

---

## 5. Omit/Cut as Scrap Equivalent

In VFX, shots are **omitted** when editorial decides they are no longer needed in the cut. This is distinct from rejection (shot attempted but quality insufficient).

### Omit lifecycle
1. Shot exists in the cut, work is assigned
2. Editorial re-cuts the scene; shot is no longer needed
3. Shot status changes to `Omit`; all in-progress work stops immediately
4. If the cut changes again and the shot returns, it can be **reinstated**
5. ShotGrid's Import Cut app automates this: compares incoming EDL against current shot list, flags omits and reinstates
6. On reinstate, shot reverts to its **previous status** (not back to "Ready to Start")

### Key design properties
- **Immediate stop:** Omit halts work instantly -- no "finish what you started"
- **Reversible:** Omit is not delete. The shot, all versions, and all notes are preserved.
- **Status memory:** When reinstated, the system remembers where the shot was in the pipeline
- **Distinct from failure:** An omitted shot wasn't bad -- it became unnecessary

### Translation to AI agents

| VFX concept | Agent equivalent |
|---|---|
| Omit | Task cancelled because requirements changed (not because output was bad) |
| Immediate stop | Kill in-flight work when task is no longer relevant |
| Reversible omit | Preserve all work products; task may become relevant again |
| Status memory on reinstate | Resume from where work stopped, don't restart from scratch |
| Omit vs. reject distinction | "No longer needed" is fundamentally different from "not good enough" |

---

## 6. Escalation Paths for Consistently Failing Shots

VFX has well-established patterns for shots that refuse to converge:

### Escalation ladder
1. **Artist self-review** -- artist checks against reference before submitting
2. **Lead review** -- department lead reviews before dailies (informal pre-filter)
3. **Dailies rejection + specific notes** -- supervisor explains what's wrong
4. **Reassignment** -- if artist can't crack it after N attempts, shot moves to a different artist
5. **Supervisor takeover** -- senior artist or supervisor does a paint-over or direct correction
6. **Approach change** -- if the technique isn't working, switch approaches (e.g., CG to practical, 3D to 2.5D)
7. **Creative redirect** -- go back to the director: "This shot as designed can't be achieved in budget. Here are alternatives."
8. **Omit/simplify** -- if nothing works, the shot is simplified or cut from the film

### Budget awareness at each level
- Each escalation level costs more (senior artist time > junior artist time)
- Studios track **cost per shot** and flag outliers
- A shot that has consumed 3x its bid is escalated automatically regardless of quality
- The VFX producer maintains a "hot list" of shots that are over-budget or over-revision-count

### Translation to AI agents

| VFX escalation | Agent equivalent |
|---|---|
| Artist self-review | Agent self-validation before submission |
| Lead pre-filter | Lightweight automated check |
| Dailies notes | Structured feedback with specific failure reasons |
| Reassignment | Try a different model, prompt strategy, or agent configuration |
| Supervisor takeover | Escalate to more capable (expensive) model |
| Approach change | Fundamentally change the solution strategy |
| Creative redirect | Report back: "This task as specified may not be achievable within constraints" |
| Omit/simplify | Reduce scope or mark task as not cost-effective to automate |
| Cost-based auto-escalation | Trigger escalation when token spend exceeds N * estimate |

---

## 7. Event-Driven Status Automation

ShotGrid's **Event Daemon** watches the event stream and triggers automated status transitions. This is the backbone of pipeline automation.

### Common trigger patterns
- Version status -> `Approved` triggers Task status -> `Final` (if last version in pipeline step)
- Task `Layout` -> `Final` triggers downstream Task `Animation` -> `Ready to Start`
- All tasks on a Shot -> `Final` triggers Shot status -> `Final`
- Version fails tech check -> Task reverts to `In Progress`
- Shot status -> `Omit` triggers cancellation of all downstream tasks

### Properties
- **Declarative rules:** Triggers are configured as "when X status changes to Y, set Z to W"
- **Cascade-aware:** One status change can trigger a chain of downstream changes
- **Idempotent:** Setting a status that's already set is a no-op
- **Audited:** Every status change (manual or automated) is logged with timestamp and actor

### Translation to AI agents
This maps directly to an event-driven disposition system:
- Output accepted -> unlock dependent tasks
- Output rejected -> re-queue with feedback context
- All subtasks complete -> mark parent task final
- Budget exceeded -> auto-escalate
- Requirements changed -> cascade-omit downstream work

---

## 8. Synthesis: VFX Disposition Model for Agent Outputs

Combining the patterns above into a unified disposition model:

### Status set (minimum viable)
```
queued           -- ready to be worked, dependencies met
in_progress      -- agent actively working
pending_review   -- output submitted, awaiting evaluation
approved         -- output accepted for use
cbb              -- accepted but improvable if budget permits
revise           -- rejected with structured feedback, rework required
tech_fail        -- creative direction OK but technical validation failed
omit             -- task no longer needed (requirements changed)
on_hold          -- paused, may resume
final            -- locked, delivered, no further changes
```

### Review tiers
1. **Automated validation** (tech check equivalent) -- runs first, cheapest
2. **Self-review / lightweight model review** (internal dailies equivalent) -- pre-filters before human
3. **Human review** (client review equivalent) -- expensive, only sees pre-validated work

### Rework loop design
- Each rework attempt creates a new immutable version
- Feedback from review is attached to the version, not the task
- Agent receives previous version + feedback as context for next attempt
- Maximum revision count is configurable per task type
- Exceeding max revisions triggers escalation (model upgrade, strategy change, or omit)

### Cost controls
- Track cumulative cost per task across all revision attempts
- Auto-escalate when cost exceeds N * original estimate
- CBB promotion: when iteration budget is exhausted, accept all CBB-status outputs as final
- Omit calculation: if estimated remaining cost > value of completion, recommend omit

### Key differences from naive retry
| Naive retry | VFX-informed rework |
|---|---|
| Same prompt, try again | Structured feedback from review informs next attempt |
| Binary pass/fail | Multi-level disposition (approved, CBB, revise, tech fail, omit) |
| Unlimited retries | Budget-aware with escalation ladder |
| No history | Full version history with regression detection |
| Single reviewer | Tiered review (auto -> lightweight -> human) |
| Failure = discard | Omit != failure; reinstate is possible |

---

## Sources

- [CAVE Academy: Production Statuses](https://caveacademy.com/wiki/production/production-statuses/)
- [CAVE Academy: VFX Pipeline](https://caveacademy.com/wiki/pipeline/vfx-pipeline/)
- [Autodesk: ShotGrid Status Tracking for Client-Side Productions](https://help.autodesk.com/cloudhelp/ENU/SG-Tutorials/files/SG_Tutorials_tu_tracking_statuses_html.html)
- [ShotGrid Community: Auto-Update Task Status on Version Status Change](https://community.shotgridsoftware.com/t/automatically-update-task-status-when-you-change-version-status/3749)
- [ShotGrid Developer: Writing Event-Driven Triggers](https://developers.shotgridsoftware.com/0d8a11d9/)
- [ShotGrid Events: version_status_update_task_status.py](https://github.com/shotgunsoftware/shotgunEvents/blob/master/src/examplePlugins/version_status_update_task_status.py)
- [Autodesk: Updating Shot Information (Omit/Reinstate)](https://knowledge.autodesk.com/support/shotgrid/learn-explore/caas/CloudHelp/cloudhelp/ENU/SG-Editorial/files/SG-Editorial-ed-update-shots-html-html.html)
- [Netflix Partner Help: Status Reporting Instructions](https://partnerhelp.netflixstudios.com/hc/en-us/articles/360062320974-Status-Reporting-Instructions)
- [Netflix Partner Help: VFX Shot and Version Naming](https://partnerhelp.netflixstudios.com/hc/en-us/articles/360057627473-VFX-Shot-and-Version-Naming-Recommendations)
- [Netflix Partner Help: VFX Best Practices](https://partnerhelp.netflixstudios.com/hc/en-us/articles/360000611467-VFX-Best-Practices)
- [Netflix Partner Help: VFX Media Review Delivery Specs](https://partnerhelp.netflixstudios.com/hc/en-us/articles/360057627253-VFX-Media-Review-Delivery-Specifications)
- [Escape Studios: What Are CBBs?](https://escapestudiosanimation.blogspot.com/2020/05/what-are-cbbs-could-be-better.html)
- [befores & afters: Optical Dogs, Dailies, and the Origins of CBB](https://beforesandafters.com/2023/05/26/optical-dogs-dailies-and-the-origins-of-cbb-40-years-of-jedi/)
- [Evan Schiff: Feature Turnover Guide - VFX](https://www.evanschiff.com/articles/feature-turnover-guide-vfx/)
- [Loco VFX Pipeline: Client Review System](https://lvfx-pipeline.readthedocs.io/en/latest/client-review.html)
- [Silver Monkey Studio: Async Dailies in VFX](https://silvermonkey.studio/async-dailies-in-vfx-moving-reviews-out-of-the-meeting-room/)
- [Compositioning Pro: How to Tech Check Your Shot in Nuke](https://www.compositingpro.com/tech-check-compositing-shot-in-nuke/)
- [ShotGrid Community: Version Status Options](https://community.shotgridsoftware.com/t/version-status-options/8420)

<!-- flux-research:complete -->
