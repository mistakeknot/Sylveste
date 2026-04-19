# fd-demo-artifact-authenticity — Review

## Findings Index
- P0: No Demo Exists — launch proceeds with zero reproducible artifact; any claim is unverifiable
- P0: Cost-Query DB is Local — the $2.93 centerpiece requires an interstat database no outsider can access
- P1: Interchart Temptation — the interactive diagram is the obvious "demo" and the wrong one
- P2: Interspect Routing Has a 30-Minute Gate — the most operationally mature system requires full platform install before the Tuesday test applies

## Verdict

**mixed** — the bead trail is a genuinely novel receipt that survives the Tuesday test if `.beads/backup/issues.jsonl` is pushed public; the cost claim must be restructured before it leads.

---

## Candidate Demos Ranked

| # | Demo Candidate | Capability Shown | Tuesday-Reproducible? | Non-Obviousness | Recommendation |
|---|---|---|---|---|---|
| 1 | Self-building bead trail | Sylveste tracks its own construction in an inspectable public JSONL | Yes — `git clone` + `bd stats` in 3 min | High — few agent projects publish their own task history as a receipt | **lead** |
| 2 | $2.93/landable live cost-query | Closed-loop cost calibration reading from actual sessions | No — `cost-query.sh` reads a local interstat DB the viewer cannot access | High — the number is credible and specific; the mechanism is elegant | **backup after DB is public or approximated** |
| 3 | Interspect routing canary | Evidence-driven routing override, the only M2+ operational system | No within 10 min — 30 min full install required | High — behavioral routing as infrastructure is rare | **sequence-later (v0.7 window)** |
| 4 | Interchart ecosystem diagram | 64-plugin topology | Yes — it is already live at mistakeknot.github.io/interchart/ | Low — every platform has a dependency graph | **reject** |
| 5 | OODARC Compound loop | Reflect+Compound extending Boyd's OODA | No — the loop has no runnable artifact today; it is a design claim | High conceptually, zero as a demo | **reject until `estimate-costs.sh` pipeline is the exhibit** |
| 6 | FluxBench benchmark | Standardized agent quality measurement | No — listed as planned, not operational | High if it ships | **reject for now** |
| 7 | estimate-costs.sh Closed-Loop pipeline | Hardcoded defaults → actuals → calibration → defaults-as-fallback | Partial — script is in public repo; DB is local | Medium — the 4-stage pattern is visible in the code even without live data | **backup receipt alongside bead trail** |

---

## Summary

The only Tuesday-reproducible artifact Sylveste has today is the bead trail — `.beads/backup/issues.jsonl` committed in the public repo, inspectable by anyone who clones. That is both the demo and the receipt: a skeptical viewer can clone, run `bd stats`, page through real bead IDs with real titles, and verify that the project was built using its own tracker. No other candidate survives the 10-minute test today. The $2.93 cost figure is the most credible external claim but it collapses the moment a viewer asks to run `cost-query.sh` and discovers it reads a local database. The interchart diagram tempts because it is already live, but showing a 64-node topology diagram is exactly the "platform slideware" the target audience is allergic to. Launch should be gated on recording the bead-trail demo — not because a missing video is fatal, but because the bead trail is the only artifact that earns the self-building claim and can be independently verified.

---

## The Chosen Demo: Shot List

- **Duration target:** 90 seconds
- **Opening frame (0–5s):** Terminal window, nothing running. Narrator: "Sylveste is built with Sylveste. Here is the evidence." Type: `git clone https://github.com/mistakeknot/Sylveste && cd Sylveste`
- **Capability moment (5–35s):** Run `bd stats` — output shows raw counts: open, closed, in-progress, total. Then: `bd list --status=closed | tail -30` — real bead IDs scroll past with real titles (no sanitization; show the boring ones like "fix conftest import" alongside the architectural ones). Point: this is what Wednesday looks like, not a demo scenario.
- **Visible failure-then-recovery (35–60s):** Run `bd show <a real bead ID that has a design note and a resolution note>`. Show a bead where the original plan changed — original description says one thing, notes say "pivot: approach X failed because Y, switched to Z." Do not cut this. This is the receipt that the tracker runs through real work, not showcase scenarios.
- **Reproduction command on-screen (60–80s):** Pause on: `bd list --status=closed | wc -l` — the raw count. Then: `cat .beads/backup/issues.jsonl | python3 -c "import sys,json; [print(json.loads(l)['title']) for l in sys.stdin]" | head -40` — every viewer can run this from the clone.
- **Receipt pointer (final frame):** Static frame: `github.com/mistakeknot/Sylveste` + the closed-bead count + `.beads/backup/issues.jsonl` path. Narrator: "Every task this platform was built with is in that file."

---

## Issues Found

### [P0] No Demo Artifact Exists
**Target demo choice or framing:** any external post without a recorded artifact
**Verdict:** polish (record it; it is a 90-minute task)
**Why (your lens):** A Show HN post that says "Sylveste builds itself" with no inspectable receipt will be dismissed in the first three comments. The bead trail is sitting in the repo already committed. The work is recording the terminal session and cutting a 90s clip.
**Concrete action this week:** Record the bead-trail shot list above. Use `asciinema` or raw screen capture. Do not edit for aesthetics — leave the actual latencies.

---

### [P0] Cost-Query Claim is Not Outsider-Reproducible
**Target demo choice or framing:** "$2.93/landable change" as demo centerpiece or README lede
**Verdict:** sequence-later
**Why (your lens):** `interverse/interstat/scripts/cost-query.sh` is in the public repo. But it reads a local SQLite database that no viewer can access. The viewer sees a compelling number and tries to verify — and hits a dead end at the DB path. That dead end is worse than not citing the number at all, because it converts a credibility moment into a credibility hole. Fix: either publish a snapshot CSV of the interstat data alongside the script, or restructure the claim so the methodology (the script + schema) is the exhibit rather than the live output.
**Concrete action this week:** Add a `data/cost-baseline-2026-03.csv` export to the repo (300 rows, anonymized session IDs, model, tokens, cost, change flag). Now `cost-query.sh --csv data/cost-baseline-2026-03.csv` runs for anyone. The Tuesday test passes.

---

### [P1] Interchart Diagram as Lead Demo
**Target demo choice or framing:** mistakeknot.github.io/interchart/ featured in launch post or demo video
**Verdict:** hide (from lede; keep as supplementary link)
**Why (your lens):** An interactive graph of 64 plugins is exactly what technically serious readers have been trained to distrust. It communicates "we built a lot of things" rather than "we built the right thing." The Tuesday test fails in a different way: the viewer can reproduce it trivially (load a webpage) and learns nothing about whether any plugin is operationally sound. It is the architectural table in graph form. Do not lead with it.
**Concrete action this week:** Remove interchart from any top-of-README link. If it appears, it appears at the bottom as "ecosystem map for contributors."

---

### [P2] Interspect Routing Demo Requires Full Install
**Target demo choice or framing:** Interspect canary window as lead capability proof
**Verdict:** sequence-later
**Why (your lens):** Interspect is the most legitimate demo candidate after the bead trail — it is M2+ operational and shows evidence-driven routing, which is genuinely non-obvious infrastructure. But the Tuesday test requires a viewer to get there in 10 minutes. The brief says full platform install is 30 minutes. The install story needs a "fast path to Interspect" that works in under 10 minutes before this can lead.
**Concrete action this week:** Do not attempt to record the Interspect demo this week. Flag it as the v0.7 demo after install UX is tightened.

---

## What NOT to Record

- **Interchart ecosystem diagram** — tells viewers the project is large, not that it works. Every platform has one.
- **Architecture table from README** — static text, not a capability. A technically serious reader either reads the README or doesn't; a video of someone scrolling through a README is negative signal.
- **OODARC Compound loop as a slideware animation** — the concept is strong; an animated diagram of it without a runnable artifact is the "we're building the Linux of AI agents" register dressed in Boyd terminology. The loop must be demonstrated through the `estimate-costs.sh` pipeline showing actual calibration output, or not at all.
- **Full platform install walkthrough** — 30 minutes of install friction is not a demo. Never record your own setup as an exhibit.
- **Interspect canary before the fast-path install exists** — the capability is real but the friction gate means the Tuesday test fails by time, not by authenticity.

---

## Launch Gating Decision

The HN/Lobsters/X post can ship text-only if and only if it links to the inspectable bead trail and includes the raw `bd list --status=closed | wc -l` count in the post body. Text posts with a specific reproducible artifact (clone, run one command, see the receipt) do pass the Tuesday test for a technically serious audience. What the post cannot do is claim "Sylveste builds itself" without that artifact being verifiable in the body. If the 90-second screen recording is done first, the post is objectively stronger — the recording takes the claim from "you can verify this" to "here is what verification looks like." The recording is a 90-minute task. Gate on it unless there is a specific reason this week is the only launch window; there is not.

---

## Single Highest-Leverage Move

Record a 90-second `asciinema` of `git clone`, `bd stats`, and `cat .beads/backup/issues.jsonl | python3 -c ... | head -40` — the bead trail as a live receipt — and publish it alongside the first post.

<!-- flux-drive:complete -->
