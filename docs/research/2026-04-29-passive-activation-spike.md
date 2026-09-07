# Passive activation spike (F0 / sylveste-xofc)

Date: 2026-04-29
Bead: `sylveste-xofc`
Parent: `sylveste-8r5h` Activation-rate KPI

## Decision

**Ship passive v1. Defer explicit subsystem-event emits (`F1`–`F6`) until passive v1 misses a real activation gap.**

The F0 go/no-go threshold was `≥2/3` recall against the known shadow-mode / activation-sprint fixtures (`iv-zsio`, `iv-godia`, `iv-2s7k7`). The harness found **3/3** fixtures catchable from existing CASS traces + git history inside a 14-day post-anchor window.

This does **not** mean passive v1 gives perfect activation-rate telemetry. It means the historical last-mile failures were visible enough in already-captured operator traces and commits that the cheaper next move is a passive detector/report, not new kernel event plumbing.

## Harness

Prototype: `scripts/activation/passive_activation_spike.py`

Command run:

```bash
python3 scripts/activation/passive_activation_spike.py --format json
python3 scripts/activation/passive_activation_spike.py --format markdown
```

Detector shape:

1. Use a known shipped/activation anchor commit per fixture.
2. Search CASS lexical traces and git history in a 14-day post-anchor window.
3. Mark a fixture caught when generic activation-gap vocabulary appears in the scoped evidence stream:
   - `zombie`
   - `phase:done`
   - `already shipped`
   - `already committed`
   - `shadow to enforce` / `shadow-mode`
   - `off mode`
   - `cache was empty`
   - `never deployed`
   - `DISCOVERY_UNAVAILABLE`
   - `delegation.mode switched`
   - `enforce mode`
4. Report recall, first detection time, latency, positive hit count, and distinct positive CASS sessions.

The prototype intentionally stays historical and auditable. A passive-v1 production surface should generalize this over current Beads by deriving anchor commits and subsystem vocabulary from the bead/PRD/plan, then producing a report instead of hard-coding fixtures.

## Results

| Bead | Historical gap | Anchor | First detection | Latency | Distinct positive CASS sessions | Positive hits |
|---|---|---|---|---:|---:|---:|
| `iv-zsio` | Discovery/interphase hooks existed but were effectively unavailable (`DISCOVERY_UNAVAILABLE`, empty plugin cache, hooks never deployed) | `607329f3` | 2026-03-07T07:40:42Z | 0m | 28 | 44 |
| `iv-godia` | Routing-decisions/kernel-facts work had already landed but remained in zombie / closeout drift | `f9f038dd` | 2026-03-07T15:51:09Z | 7m | 20 | 54 |
| `iv-2s7k7` | Codex-first routing had been in shadow mode until activation sprint moved it to enforce | `5213e1be` | 2026-03-07T15:59:26Z | 0m | 7 | 24 |

Recall: **3/3**
Decision branch: **passive-v1**

## Interpretation

Passive signals worked because the failure mode is socio-technical, not purely runtime:

- The operator traces name zombies, shadow mode, stale claims, and `phase:done` drift.
- The git history contains high-signal commit messages for activation-sprint closeout.
- The same terms appear near Bead IDs, subsystem names, and concrete hook/function names.

That is enough for a first value-proof loop: a passive report can catch or at least sharply surface likely activation gaps without adding a new event API across Intercore/Clavain/interflux.

## Caveats

- `iv-godia` uses a plan-complete commit as its anchor because the old Demarch Beads database is no longer available locally. The CASS evidence is still strong, but latency should be treated as approximate.
- The fixture harness is not a production detector. It proves feasibility and recall on the historical examples; passive v1 still needs generalized anchor/vocabulary derivation.
- Passive v1 can classify likely activation gaps; it cannot yet compute a clean subsystem activation rate without either stronger hot-path inference or explicit emits.
- For current B2 routing work (`sylveste-2aqs`), this result supports a passive audit/report first. It does not by itself prove `quality-gates`, `flux-drive`, compose, and Codex dispatch are carrying B2 complexity/route signals in live user paths.

## Passive-v1 shape

Ship a report-oriented v1 before adding kernel events:

1. Inputs:
   - Bead ID.
   - Anchor commit or close timestamp.
   - Subsystem vocabulary from title/description/PRD/changed paths.
2. Evidence sources:
   - CASS lexical hits after anchor.
   - Git commits/messages after anchor.
   - Beads status/notes when available.
3. Output:
   - `activation_gap_likely`, `activated_likely`, or `insufficient_evidence`.
   - Evidence snippets and distinct CASS-session counts.
   - Detection latency and confidence.
4. First dogfood target:
   - `sylveste-2aqs` / B2 caller activation, specifically whether `quality-gates`, `flux-drive`, compose, Claude Code, and Codex paths show routed phase/model/complexity evidence after closeout.

## Closeout recommendation

Set:

- `passive_spike_recall=3/3`
- `next_phase=passive-v1`

Then close `sylveste-xofc` and keep `F1`–`F6` blocked/deferred unless passive v1 misses a confirmed activation gap.
