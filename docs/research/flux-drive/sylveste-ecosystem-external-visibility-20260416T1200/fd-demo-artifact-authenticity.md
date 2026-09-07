# fd-demo-artifact-authenticity — Findings

Lens: senior engineer, 15 years recording and critiquing demo reels for AI-infra companies and labs. Tuesday-reproducibility discipline: given the exact public repo today, could a skeptical viewer reproduce the demo's claim in 10 minutes?

## Verdict

No demo exists. Without one, the launch is impossible. The most Tuesday-reproducible candidate is a 60-90 second recording of the Closed-Loop pipeline running on Sylveste's own bead workload, with the $2.93 baseline visible updating and the reproduction command on screen. Record this before anything else ships.

## Findings

### P0 — Launch proceeds with no recorded demo artifact
**Location:** target-brief §"No public artifacts currently" line 117.

The brief confirms: no video, no screencast, no benchmark. The target audience (technically serious readers evaluating AI-agent infrastructure) responds to "a working demo that shows a non-obvious capability" per the brief's own framing. Its absence blocks external attention entirely.

**Fix:** one demo must exist before any launch. Criteria below.

### P0 — If recorded, avoid the 64-plugin interchart diagram or architecture table as demo
**Location:** mistakeknot.github.io/interchart (target-brief line 114), README architecture table.

Breadth demos fail the Tuesday-reproducibility test. A viewer cannot reproduce any specific capability from the diagram — the diagram shows topology. "Look at all the pieces we have" is the allergen that technically-serious readers are specifically looking for.

**Fix:** the demo is NOT the interchart diagram. The demo is one capability, reproducibly, with the command visible.

### P1 — Demo must have reproduction command on screen
**Location:** N/A — criterion for the demo to be built.

Skeptical viewers downgrade unsupported demos to "cherry-picked." The single cheapest trust-building element is: put the exact command the viewer would type at the bottom of the screen throughout the demo. This is the discipline Docker, Redis, and k9s used in their early demos.

**Fix:** on-screen terminal shows every command. Final frame shows: `curl -fsSL sylveste.dev/install.sh | bash && sylveste cost-baseline`. The viewer copies, pastes, gets the same $2.93 number. Reproducibility confirmed.

### P1 — Demo should include one visible failure-then-recovery
**Location:** N/A — criterion.

Fake demos do not show failures. Real demos do. A demo that shows Clavain refusing to advance a bead because the evidence gate wasn't satisfied, then the user wiring the evidence, then the bead advancing — that narrative arc IS the claim "review phases matter more than building phases" made concrete. Without a visible failure, the demo is marketing.

**Fix:** scripting the demo, include one explicit "this failed because X, here's the wire-up, now it passes." Do not edit out the fail.

### P2 — Self-building claim needs the bead-trail to be publicly inspectable
**Location:** PHILOSOPHY.md claim #10, bead tracker `.beads/`.

The demo could show "Sylveste builds Sylveste" by opening the bead tracker and pointing to beads that were closed by the agent factory. But the bead trail is currently `.beads/` — inside the repo but not exposed as a public viewing-line. Cold viewer has no way to inspect without cloning.

**Fix:** expose `bd list --status=closed --json` as a public endpoint or as a scheduled export to `mistakeknot/sylveste-bead-trail` repo. Make the receipt inspectable without cloning.

### P2 — Cost baseline ($2.93) should be the demo centerpiece with live verification
**Location:** target-brief line 134.

The $2.93 number is the single most verifiable claim. The demo should end with: terminal running `sylveste cost-baseline`, output showing "$2.93/landable change across 785+ sessions." Viewer types the same command, gets the same number (updated to current session count). That is the most honest possible end-frame — a specific number that updates over time, verifiable by any viewer.

**Fix:** the cost baseline IS the demo's hero claim. Structure everything around it.

### P3 — Interchart diagram has a narrower demo role
**Location:** interchart.

Not the hero demo, but a useful secondary artifact for readers who want to understand scope AFTER they have bought the capability. Keep the interchart. Do not lead with it.

## The demo, specified

**Length:** 60-90 seconds. Hard cap.

**Arc:**
1. (0-15s) User starts a bead: `bd create "add X feature"`. Voice-over: "Sylveste runs the change through OODARC."
2. (15-45s) Clavain dispatches, the phase-gate refuses to advance to ship because evidence is unwired. User wires the evidence trigger. Bead advances to ship.
3. (45-70s) `sylveste cost-baseline` runs. Output: "$2.93 mean cost per landable change across 786 sessions [updates from 785]."
4. (70-90s) Close-frame: the reproduction command on screen. arXiv ID on screen. URL to factory page on screen.

**Tuesday-reproducibility:** viewer types the commands on their own Tuesday. Same output shape. Same baseline (updated).

**Failure-then-recovery:** step 2 explicitly shows Clavain blocking. The blocking IS the point.

**Hero claim:** $2.93/landable-change is verifiable; OODARC is named; wired-or-it-doesn't-exist is demonstrated.

Three claims compound into one artifact. This is the single most valuable unit of external signal the user can build this week.

<!-- flux-drive:complete -->
