# fd-oss-seed-capture — Review

## Findings Index
- P0: Architecture Table Before Capability Moment — reader bounces before seeing anything run
- P1: No "Here's What You Get" Preview Artifact — 30-min install cliff with no finish-line signal
- P2: interchart as First Interactive Surface — 64-plugin hairball as opening impression

## Verdict

**polish** — the tech and claims are strong enough for a credible seed post, but the current README first-screen kills conversion before the reader gets to any of them.

---

## The Funnel (as currently configured)

1. **Tweet / HN title:** Nothing exists. Zero social surface. Cold reader has no entry point.
2. **README first screen:** Install command → what-you-get bullet list → **architecture table (three layers, six pillars)** → philosophy pointer. The table appears before any capability moment.
3. **Install moment:** curl-to-bash exists. Prereqs: jq, Go 1.22+, git. "~2 min power-user install, ~30 min full platform." No description of what runs at minute two or what output appears.
4. **First value moment:** Unknown. `ic` is described as mechanism-not-policy — opens SQLite DB, does work, exits — but there is no artifact showing what "does work" looks like to a first-timer.
5. **Bounce risk:** Step 2 for most readers (architecture table complexity signal). Step 3 for survivors (Go prereq + invisible finish line).

**Specific friction points:**
- The phrase "monorepo for building software with agents" in the tagline competes directly with six other projects the reader already has bookmarked. No differentiating hook.
- "~30 min full platform" is a conversion-killer sentence. It appears in the install story with no preview of what the 30 minutes buys.
- No screenshot, no GIF, no asciinema, no "here's what your terminal looks like after install" anywhere in any public artifact.
- interchart is the only interactive artifact — and it shows 64 nodes.

---

## Summary

Sylveste has three or four genuinely sharp claims (OODARC Compound step, "wired or it doesn't exist," progressive trust ladder, self-building receipt) that technically serious readers would find non-obvious. None of them are legible from the current public surface because the README's first screen is an architecture taxonomy, not a capability demonstration. The install story has a 30-minute ceiling with no visible floor. The only interactive artifact is a complexity graph. The seed window is open — but the conversion path doesn't exist yet. The fix is almost entirely subtractive: hide the table, hide interchart as the lead surface, record one terminal session, write one sharp post around the one claim that has a working receipt.

---

## Issues Found

### [P0] Architecture Table Leads the README First Screen

**Target funnel step:** 2 — README first screen  
**Verdict:** polish  
**Why:** A cold HN reader has 45 seconds and a skepticism prior. The current README first screen shows them three layers, six pillars, and 64 inter-* plugins before they've seen the system do a single thing. This is a complexity signal, not a capability signal. The reader's mental model: "another framework that explains itself architecturally because it can't show itself running." Back button. It doesn't matter that the architecture is coherent — the table is in the wrong position.  
**Concrete action this week:** Move the architecture table below a `## Architecture` fold. Above the fold: one `asciinema` recording (or a 3-screenshot sequence) showing `ic` executing a real task from start to terminal output. The 45-second first-screen should answer "what does this produce?" not "how is this organized?"

---

### [P1] No Preview Artifact for the 30-Minute Install

**Target funnel step:** 3 — Install moment  
**Verdict:** polish  
**Why:** "~30 min full platform" with no finish-line artifact is the second conversion cliff. The reader who survives the README and reaches the install section needs to see what success looks like before committing 30 minutes. Without a screenshot, a GIF, or an asciinema showing a Clavain session running a real brainstorm → plan → execute loop, the motivated reader is betting 30 minutes on a description. The "2-min power-user path" is not the right story either — "power user" implies prior context the target reader doesn't have.  
**Concrete action this week:** Record one `asciinema` or QuickTime terminal session (no audio needed) showing: `ic` init → Clavain running a brainstorm phase on a real task → the output artifact. Embed it in README between the install command and the prereqs list. The recording's purpose is not to explain — it's to show the finish line.

---

### [P2] interchart as First Interactive Surface

**Target funnel step:** 2 / cross-cutting  
**Verdict:** hide (from lead position)  
**Why:** mistakeknot.github.io/interchart/ is currently the only interactive artifact a cold reader can click. It shows 64 plugins in a force-directed graph. The technically serious reader's reaction: "this is a hairball" and then they close the tab. interchart is a useful internal navigation tool and a reasonable late-funnel artifact for someone already committed. It is not a lead magnet. Surfacing 64-plugin scope to a reader who hasn't yet seen one plugin run is a trust-destroying first impression.  
**Concrete action this week:** Remove or de-emphasize interchart from the README and any primary nav. If it stays linked anywhere, it should be under a "Plugin Ecosystem" section that a committed reader reaches after seeing the system run.

---

## Improvements

- P3: The tagline ("A monorepo for building software with agents, where the review phases matter more than the building phases...") is accurate but loses the cold reader. Consider a two-line swap: a sharp one-liner hook ("Agent infrastructure where every subsystem earns its authority before it gets it") followed by the current tagline as elaboration.
- P3: PHILOSOPHY.md is the right place for the 12 distinctive claims — do not surface it to cold readers. It rewards committed readers. Keep the link but don't lead with it.
- P3: "Wired or it doesn't exist" and "OODARC Compound step" are the two claims sharp enough to be post titles. Neither appears above the fold in any current artifact.

---

## The Seed Sequence (your tactical recommendation)

Given one post, one demo, one polish budget this month:

- **Week 1 polish target:** README first screen. Collapse the architecture table. Record one 90-second `asciinema` of `ic` + Clavain running a task (use the self-building receipt — Sylveste building a bead, emitting evidence, closing the loop). Place it above the fold. This is the only action that unblocks every downstream step.

- **Week 2 demo to record:** Clavain's brainstorm → strategy → plan → execute → review cycle on a real feature, using the self-building angle. Not a polished screencast — a real terminal session with commentary in the commit messages visible. The artifact should end with a merged PR and a visible bead close. This is the "wired or it doesn't exist" receipt.

- **Week 3 blog post:** **"OODARC: why Boyd's OODA loop has a missing step for agent systems."** Teaches something the reader didn't know. Introduces the Reflect + Compound extension. Uses `estimate-costs.sh` → interstat calibration loop as the concrete existence proof. Does not mention 64 plugins anywhere. Links to one repo: intercore or Clavain.

- **Week 4 HN/Lobsters/X post:** Title: **"Show HN: We built an agent rig that builds itself — OODARC loop, graduated authority, self-building receipt (OSS, MIT)"**. Body: three sentences + link to the Week 2 demo + link to the Week 3 blog post. The README has been fixed by this point. Do not post before Week 1 polish lands.

---

## Single Highest-Leverage Move

Fix the README first screen this week — move the architecture table below the fold and put a working terminal recording above it — because every other seed-window action (demo, blog, HN post) points there and currently converts to a bounce.

<!-- flux-drive:complete -->
