# Track C — Scriptoria Colophon Credibility

**Lens:** Benedictine armarius at Cluny, 1090. Every manuscript leaves the abbey with a colophon (scribe + date + exemplar + completion mark); a book without a colophon is a book without a reputation; textual reception travels on chains of named copyists, not on prose elegance.

## TL;DR

Sylveste's thesis is "evidence earns authority" — but **the evidence artifacts themselves carry no colophons that survive export**. Bead IDs (`iv-ho3`, `Sylveste-6i0`, `Demarch-a637`) are local shelf-marks only — they resolve in the monorepo Dolt database but not at any external URL. `docs/solutions/` carries the solution text but not the exemplar-stemma: 73 solution docs indexed, none of them record the source session, the agent hand that drafted them, or the upstream-doc they synthesized from. The three bead-ID prefixes (`iv-*`, `Sylveste-*`, `Demarch-*`) are three scriptorium hands visible on the same wall — the same codex appears to come from three different abbeys. **L2 (OS + Drivers) deserves Stage 2** because the 64 plugin READMEs are the largest artifact class where a colophon-discipline pass would be cheap and the citability ROI would be highest: each README becomes a DOI-equivalent with a version-pinned, dated, named-exemplar block.

## Findings

### P0 — Durable receipts have no external-citable shelf-marks (colophon chain breaks at the abbey wall)

`PHILOSOPHY.md:49` declares: "Every meaningful action produces a durable receipt... If it didn't produce a receipt, it didn't happen." The receipts exist — `.beads/` per project, `cass` session index (`~/.local/bin/cass`, 10K+ sessions, per memory file). But **no external researcher can cite a specific receipt**:

- Bead IDs (`iv-5ztam`, `Sylveste-6i0`) resolve in the local Dolt database and via `bd show <id>` — not at any public URL. There is no `https://sylveste.dev/beads/iv-5ztam` resolver.
- `cass` session IDs resolve only in the user's local index.
- `docs/solutions/INDEX.md:3` says "73 docs" — but the 73 solution docs are relative paths into the monorepo (`infra/agent-rig/docs/solutions/...`) with no canonical URL that will resolve in 2029 when the repo layout has changed.
- The "eventsource" git SHAs in commit messages (`9b14dbe4`, `849aad1d`) are the closest thing to a colophon — but GitHub SHAs break if the repo is renamed or archived.

The Cluny armarius mechanism requires: scribe name + date + exemplar source + shelf-mark, all traveling with the manuscript. Sylveste receipts travel with *date* (bead event timestamps) and *scribe* (git commit author) only. No exemplar-chain ("this solution was derived from session X which derived from plan Y"), no stable shelf-mark (a URL that resolves in three years).

**Failure scenario:** A 2029 academic paper cites "Sylveste's interspect canary monitoring as evidence that agent-behavior profilers can self-calibrate" and links to `bd show iv-5ztam`. The reader cannot resolve the citation. The "evidence earns authority" thesis becomes unverifiable outside the monorepo — which is the exact failure mode the armarius exists to prevent.

**Smallest viable fix:** Expose a read-only bead snapshot as a public static site under `github.com/mistakeknot/Sylveste/beads/<id>.md`, auto-generated from `bd show --json`, with frontmatter containing `bead_id`, `closed_at`, `closed_by`, `artifacts_sha`, `receipts_schema_version`. One CI job. Shelf-mark URL stays valid as long as the repo exists. (The memory file notes `.beads/backup/issues.jsonl` already exists — a static-site generator over that file is the minimum viable colophon.)

### P1 — Three bead-ID prefixes visible on the same wall (scriptorium rule of hands violated)

Bead IDs have three visible hands across the artifacts:
- `iv-*` (iv-ho3, iv-5ztam, iv-83du3) — inherited from the interverse-era
- `Sylveste-*` (Sylveste-6i0, Sylveste-9lx, Sylveste-ynh) — post-rename
- `Demarch-*` (Demarch-og7m, Demarch-jpum, Demarch-a637) — pre-rename, still visible in CLAUDE.md and `.beads/backup/`

PHILOSOPHY.md:209 admits the rename (Demarch → Sylveste in March 2026). CLAUDE.md does not show any Demarch IDs. But:
- `docs/sylveste-roadmap.md:10-50` freely mixes `iv-*` and `Sylveste-*` in the same paragraphs
- `apps/Meadowsyn/CLAUDE.md:10` says "Bead: Demarch-jpum (child of Demarch-jlp0)"
- Memory notes (pre-context) reference `Demarch-` prefix for beads tracker

The scriptorium rule mechanism says: a single regional hand ensures every copy is mutually legible. An outside reader hitting all three prefixes within 5 minutes cannot tell whether they are looking at three projects, two project-names, or a migration in progress. The *information* is in PHILOSOPHY.md:209 — but that is interior prose, not a rubricated incipit.

**Failure scenario:** Academic researcher cross-checks a roadmap claim against a commit, finds `Demarch-jpum` referenced in a 2026-04 file (Meadowsyn CLAUDE.md) despite the rename happening in March, and concludes the project is inconsistently maintained. The inconsistency is real (apps/Meadowsyn/CLAUDE.md:10 still uses the old prefix) — not a misreading.

**Smallest viable fix:** One sweep over `apps/Meadowsyn/CLAUDE.md:10` and any other Demarch-\* references outside `.beads/backup/` to use the current `sylveste-*` prefix (or explicitly mark the old prefix as "legacy ID, renamed from Demarch on 2026-03-XX"). Add a one-line note to CONTRIBUTING.md: "Bead IDs use the `sylveste-` prefix. Historical references to `Demarch-*` and `iv-*` are legacy identifiers pre-2026-03."

### P1 — Solution docs missing exemplar-source frontmatter (the user-provided quality bar example)

`docs/solutions/INDEX.md:3` tracks 73 solution docs across subprojects. Sampling the `clavain (18 docs)` section (INDEX.md:41-60) shows each entry has: title, type, severity, date, tags. What is **missing** from every entry:
- **Exemplar source** — what session / bead / brainstorm produced this solution?
- **Scribe** — which agent model / human drafted it?
- **Stemma pointer** — was this synthesized from a prior solution, and if so which?

The frontmatter convention documented at INDEX.md:9-13 defines `synthesized_into` (downstream target) but NOT the upstream exemplar — the arrow points the wrong way. The armarius needs both: "this manuscript was copied from Cluny MS 47" (upstream) and "this manuscript was then copied into York MS 12" (downstream). Sylveste has the downstream half.

The Cluny mechanism: each scribe recorded which manuscript they copied from, building a stemma that later philologists could reconstruct. Without the upstream pointer, Sylveste's "progressive trust ladder" cannot be reconstructed by an outsider — the rungs (prior evidence that each solution was derived from) are invisible.

**Failure scenario:** An AI-researcher doing a systematic review of agent-coding-lesson-propagation patterns tries to trace "over-planning before bug reproduction" (`INDEX.md:39` — solution in autarch) back through prior sessions to find the root cause. They cannot. The lesson is recorded but its derivation is not. The "evidence compounds" claim becomes asserted without its rungs visible — which is exactly the P1 scenario in the agent's severity calibration.

**Smallest viable fix:** Extend `docs/solutions/` frontmatter schema to include `exemplar_source: {session_id | bead_id | prior_doc}` and `scribe: {agent_name | human}`. Backfill is not required — just enforce going forward via `interscribe` (already cited in docs/canon/doc-structure.md:4 as the canon-enforcer). One schema change, linted on commit.

### P2 — Two brand registers lack rubrication distinctives for outside readers

PHILOSOPHY.md:224 enforces linguistic separation between Sylveste (SF register) and Garden Salon (organic register). But rubrication — the red-letter opening words that let readers navigate a codex — is not applied:

- No visual identifier on README.md distinguishes the SF codex
- No URL convention (e.g. `sylveste.dev` vs `gardensalon.org`) is visible on the landing page
- The vision doc (`docs/sylveste-vision.md`) is titled "Sylveste — Vision" but mentions Garden Salon extensively (lines 21-31, 344-348) without a typographic marker telling the reader "you are now crossing into the other codex"

The mechanism: red-letter incipits let medieval readers scan a codex without a table of contents. Sylveste's brand-register boundary is declared in prose but not rubricated. An outside reader citing "Sylveste's CRDT shared-state" will accidentally cite a Garden Salon claim — a category error that degrades both citations.

**Failure scenario:** Paper references "Sylveste's stigmergic coordination" (vision.md:249) not realizing that claim belongs to the Garden Salon aspirational subsystem, not the shipped Sylveste infrastructure. The correction, when published, damages both brand registers.

**Smallest viable fix:** Add a 2-column header to every vision-level doc: `Brand register: Sylveste | Status: M2 operational`. Make register an explicit metadata field. Link: `/home/mk/projects/Sylveste/docs/sylveste-vision.md:1` — add frontmatter block.

### P3 — No abbey-library catalog with stable shelf-marks

The Cluny mechanism: a library catalog lets visiting scholars request specific works by shelf-mark. Sylveste has `docs/solutions/INDEX.md` (73 docs) and `docs/sylveste-roadmap.md` (55-plugin table) — good internal catalogs. But neither has:
- A DOI-equivalent stable identifier
- A version-pinned freeze date
- A mechanism for a 2029 researcher to request "the 2026-04 snapshot of Sylveste's solution catalog"

Observation not urgent — the per-plugin README files (64) already function as a distributed catalog, and GitHub's commit-pinned URLs are good-enough shelf-marks for now. Upgrade when the first external citation lands.

## Colophon-Audit Table

For each externally-visible artifact class, mark whether it carries scribe / date / exemplar / shelf-mark.

| Artifact class | Scribe | Date | Exemplar source | Shelf-mark (external URL) |
|---|---|---|---|---|
| Plugin README (×64) | (git author) | (mtime only) | absent | github.com/mistakeknot/<name> — ok |
| Bead receipt (`bd show <id>`) | absent (claimed_by=unknown) | present | absent | absent |
| docs/solutions/\*.md (×73) | absent | present | absent (P1 above) | relative path only |
| docs/handoffs/\*.md | absent | present (in filename) | absent | relative path only |
| docs/brainstorms/\*.md | absent | present (in filename) | absent | relative path only |
| docs/plans/\*.md | absent | present (in filename) | absent | relative path only |
| PHILOSOPHY.md | absent | absent (no modification history shown) | absent | github raw URL — ok |
| docs/sylveste-vision.md | absent | v5.0 2026-04-11 present | v4.0 reference present (line 120) | github raw URL — ok |
| docs/sylveste-roadmap.md | absent | 2026-03-27 present | absent | github raw URL — ok |
| Commit messages | present (git author) | present | present (commit parents) | github SHA — ok |

**Observation:** The only artifact class that fully satisfies colophon discipline is the git commit log. Every other externally-visible artifact class is missing at least one of the four marks.

## Top-Three Artifact Classes to Colophonize This Quarter

Ranked by external-citation leverage:

1. **docs/solutions/\*.md (×73)** — highest leverage because these are the "evidence" in "evidence earns authority." Each already has date + title; adding `scribe` + `exemplar_source` frontmatter is a one-line schema change enforced by `interscribe`. Once colophonized, each solution becomes a citable object with a verifiable derivation chain. Effort: schema change + lint. Citation leverage: these are the artifacts an academic paper would cite.

2. **Plugin READMEs (×64)** — second-highest leverage because plugins are the atoms of composition and each has its own git repo. Add a frontmatter block with `version`, `shipped_date`, `depends_on`, `provided_entrypoints`, `status (M0-M4)`. The portolan agent wants these for legibility; the armarius wants them for citability — the same diff fixes both. Effort: one sweep over 64 READMEs + CI enforcement. Citation leverage: these become the citable-units of an "I used Sylveste's interflux plugin" sentence.

3. **Bead receipts** — most-visible internal artifact with no external shelf-mark. Auto-generate `github.com/mistakeknot/Sylveste/beads/<id>.md` from `.beads/backup/issues.jsonl` on every close. One CI job. Turns every bead-close into a citable-receipt with an exemplar chain (parent bead → children). Effort: ~4 hours for the generator. Citation leverage: unlocks "the full trust-ladder lineage is externally reconstructable" as a verifiable claim.

## Stage-2 Layer Recommendation

**Layer for Stage 2: L2 (OS + Drivers — specifically the 64 Interverse plugins).**

Two questions, both answered by L2:

- **Which layer's artifacts are most copyable-and-citable today?** L1 (Intercore) — single repo, single binary, clean docs, one clear shelf-mark. Not the bottleneck.
- **Which layer is the deepest hole in the abbey catalog?** L2 — 64 plugin repos with inconsistent README hands (per the portolan agent's coast audit), no enforced colophon frontmatter, no stable catalog entry, three-way bead-ID drift (`iv-*` / `Sylveste-*` / `Demarch-*`) visible inside plugin docs.

L2 is the continent with 64 unsigned manuscripts. A colophon-discipline pass here would convert the "evidence earns authority" thesis from an internal claim into an externally-verifiable proposition, which is the armarius's entire job description.

**Justification in one sentence:** L2 houses 64 manuscripts whose colophons are currently absent-or-inconsistent, and the same one-time schema change (interscribe-enforced frontmatter with scribe, date, exemplar, version, status) fixes citability + consistency + stemma-reconstructibility — a single-diff intervention with the highest external-reception leverage in the ecosystem.

## Concrete Actions

1. **Extend `docs/solutions/` frontmatter schema** (INDEX.md:9-13) to require `exemplar_source` (upstream bead/session/doc pointer) and `scribe` (agent/human identifier). Enforce via `interscribe` (per `docs/canon/doc-structure.md:4`). Backfill is optional; enforce going forward. (Effort: 1 hour. File: `docs/canon/doc-structure.md` schema section + `interverse/interscribe/` linter rules.)

2. **Add `colophon:` block to every plugin README** (64 files) with fields `version`, `shipped_date`, `status_maturity (M0-M4)`, `depends_on`, `provided_entrypoints`. Generate the block from `plugin.json` + `docs/sylveste-vision.md:159-170` (Current Mesh State). One CI job enforces presence. (Effort: 3 hours for generator + CI. Owner: `scripts/` directory, analogous to existing `bump-version.sh`.)

3. **Publish static bead pages** — CI job runs on bead-close events, generates `beads/<id>.md` under `github.com/mistakeknot/Sylveste/tree/main/beads/`, with frontmatter: `closed_at`, `closed_by_session`, `parent_bead`, `children_beads`, `artifacts_sha`. Shelf-mark becomes `github.com/mistakeknot/Sylveste/blob/main/beads/<id>.md`. Stable as long as the repo exists. (Effort: 4 hours. Depends on: `.beads/backup/issues.jsonl` — exists. Depends on: CI write permissions — already in place per AGENTS.md:43.)
