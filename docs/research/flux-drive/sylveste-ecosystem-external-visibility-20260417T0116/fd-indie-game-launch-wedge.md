---
agent: fd-indie-game-launch-wedge
tier: generated
category: project
model: sonnet
lens: indie-game launch strategist — first-contact capsule discipline
---

# Review — Indie-Game Launch Wedge

## Findings Index

- P0-LAUNCH-1: README above-the-fold leads with architecture prose, not the core verb
- P0-LAUNCH-2: No 10-second screencap/GIF of the self-building loop exists
- P1-LAUNCH-1: 55+ plugin inventory surfaced in the README "What you get" section
- P1-LAUNCH-2: Clavain + intercore + intercore-kernel + Sylveste naming collision inside first 3 paragraphs
- P2-LAUNCH-1: Two brands (Sylveste + Garden Salon + Meadowsyn) surfaced in MISSION.md before any is demoable
- P3-LAUNCH-1: Installation section occupies more vertical space than the one-line thesis

## Verdict

**Ship gated on a single GIF.** The capsule has no hook. The core verb is invisible. Fix the README's first screen and produce one 10-second loop before any HN post.

## Summary

Sylveste's README reads like a Steam page where the capsule art is a feature list, the trailer is a tech-tree slideshow, and the "play" button is a `curl | bash`. A serious ML practitioner hitting this page in 2026 — post-AutoGPT, post-Devin, post-every-agent-framework — will skim for 8 seconds and close the tab. The inventory is the enemy. The architecture table is the enemy. The two-brand framing is the enemy. None of them answer "what does it DO that my current stack doesn't."

The core verb candidate is buried: **"agent friction is the signal — Sylveste's own agents surface the tech-debt bead before the human notices."** That is a 30-second loop. That is a capsule. That is forwardable. It does not currently exist as footage.

## Issues Found

### P0-LAUNCH-1: README leads with architecture, not the verb

- **File:** `README.md:1-7`
- **What's stealing oxygen:** Line 3 opens with "A monorepo for building software with agents, where the review phases matter more than the building phases…" — this is a thesis statement, not a verb. It asks the reader to already care about "review phases." Line 5 then introduces Clavain, intercore kernel, Codex, and GPT-5.2 Pro before the reader has seen a single concrete action. By line 12 the reader is copy-pasting a curl command without knowing what they are installing.
- **Failure scenario:** A framework-builder lands on the README at 2pm on a weekday with three other tabs open. They have 8 seconds. They see "monorepo," "review phases matter more than building phases," "Clavain," "intercore," "Codex," "GPT-5.2 Pro" — and no concrete artifact to anchor on. They close the tab. First-contact conversion: zero.
- **Smallest viable fix:** Replace lines 1-7 with: one-sentence verb ("Sylveste's agents build Sylveste — and every friction they hit becomes a tracked ticket before a human sees it"), one number ("$2.93 per landed change, 785 sessions"), one GIF (the screencap below). Everything else goes below "## How it works."

### P0-LAUNCH-2: No screencap of the self-building loop

- **File:** `README.md` (absence)
- **What's stealing oxygen:** The self-building claim is stated in PHILOSOPHY.md as prose. The interchart/ diagram is static. There is no 10-second loop showing: agent hits friction → bead auto-created → reflection captured → future run calibrated. This is the irreducible differentiator — "agent-friction-as-signal" — and it lives only in words.
- **Failure scenario:** Without footage, the claim is indistinguishable from every other agent framework's marketing copy. Framework builders read "Sylveste builds Sylveste with its own tools" and mentally tag it as a vanity claim. With a 10-second asciicast — terminal splits: left side agent working, right side `bd list` updating live as friction surfaces — it becomes a concrete capability claim.
- **Smallest viable fix:** Record one asciicast or MP4 this week. Content: dispatch a Clavain sprint on a real bug, capture the moment an agent hits ambiguity and `bd create` fires with the friction signal. Loop 10s. Embed in README line 2. Nothing else ships before this.

### P1-LAUNCH-1: The 55+ plugin inventory is capsule pollution

- **File:** `README.md:44` ("55+ companion plugins: multi-agent code review, phase tracking, doc freshness, semantic search, TUI testing (43 installed by default, 14 optional)")
- **What's stealing oxygen:** The plugin count is a tell. It reads as "we built a platform" — the exact phrase the technically serious reader is allergic to (per the target brief line 166). 64 modules listed by name in the target brief inventory (line 55) is worse: it reads as incontinence, not curation.
- **Failure scenario:** A senior practitioner sees "55+ plugins" and mentally files this as kitchen-sink-ware. They do not click through to discover that exactly one subsystem (Interspect) is operationally mature. The inventory hides the one polished thing.
- **Smallest viable fix:** Cut the plugin count from the README. Move the inventory to a catalog page linked from "How it works" — most readers will never open it, and that is correct. In the README, name exactly one subsystem (Interspect) and link to its receipt.

### P1-LAUNCH-2: Clavain/intercore/Sylveste naming collision

- **File:** `README.md:1-5`, `MISSION.md:5`
- **What's stealing oxygen:** First contact sees "Sylveste" (title), "Clavain" (line 5), "intercore kernel (`ic`)" (line 18), "`clavain-cli`" (line 18) inside a three-paragraph window. The reader cannot answer "which one IS this." Two-brand framing (MISSION.md line 5: Sylveste + Garden Salon + Meadowsyn) compounds this.
- **Failure scenario:** The reader closes the tab muttering "I'll come back when they figure out what they're shipping." This is the same killshot the seed-pitch-compression-coach flags as the `wait, which one IS this` problem, but manifesting at the capsule level.
- **Smallest viable fix:** README names "Sylveste" only. Clavain appears later as "the Claude Code plugin that ships today." Garden Salon and Meadowsyn deleted from MISSION.md entirely until each has a demo. One name, one verb, one receipt.

### P2-LAUNCH-1: Three brands surfaced before any ships a demo

- **File:** `MISSION.md:5`
- **What's stealing oxygen:** Garden Salon has no site. Meadowsyn has a registered domain and no content. Both appearing in the mission statement alongside Sylveste suggests a coordinated multi-product launch — which the reader knows is vaporware when no product is shipping.
- **Failure scenario:** Degradation over weeks — each additional mention of Garden Salon / Meadowsyn in public-facing docs increases the "slideware" read. Not a 3 AM wake-up, but a slow credibility leak.
- **Smallest viable fix:** Strip MISSION.md paragraph 2 entirely. Add Garden Salon / Meadowsyn only after each has a working demo.

### P3-LAUNCH-1: Install instructions occupy more space than thesis

- **File:** `README.md:7-39`
- **What's stealing oxygen:** Install (curl command + prereqs + update/uninstall + `/clavain:project-onboard`) runs ~30 lines before "What you get." The ratio is backwards for a project that has not yet earned the install.
- **Smallest viable fix:** Collapse install to 3 lines under a `<details>` block. Lift "How it works" and the proposed GIF above the install.

## Improvements

- Pin the GIF in the repo social preview image (GitHub OG card) — this is the Twitter capsule.
- Rename the "What you get" section to show the core verb in the heading, not the noun inventory.
- Hide `docs/cujs/`, `docs/canon/`, `docs/brainstorms/` from the top-level README nav; serious readers find them via the tree view, casual readers should not see them.

## The Single Hook

**"Agent friction becomes a tracked bead before a human notices."** 30-second loop. One receipt ($2.93/change). One curl install. That is the capsule.

Everything else — the three layers, the six pillars, the cross-cutting systems, the 12 distinctive claims, the 64-plugin inventory — belongs below the fold or on a catalog page most readers will never open.

<!-- flux-drive:complete -->
