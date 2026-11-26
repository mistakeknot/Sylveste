# CanonGraph retirement → the estate index

> Status: IN PROGRESS (2026-11-26). The replacement is built and tested; nothing
> has been cut over. CanonGraph is still the live graph lane, and `memory-lanes.md`
> and `recall-lanes.md` stay as they are until step 5.

## Why

- **2026-09-01, mk:** CanonGraph works, but it is a colleague's system. mk wants
  "a version from the ground-up that is informed by Sylveste's philosophy and is
  native to Sylveste/Clavain/Intercore/the Interverse/Autarch/Garden Salon/Meadowsyn".
- **2026-09-03:** the nativity thesis (Ultan) recorded nine rulings on what that
  graph must model. Source: `Autarch/docs/research/2026-09-03-ultan-nativity-thesis.md`.
- **2026-09-24:** no new build. Lattice (`interverse/lattice`, remote
  `mistakeknot/interweave`) grows to meet the thesis. Estate-level canon lives in
  a private **Uqbar** repo. CanonGraph retires at parity. Source:
  `Autarch/docs/brainstorms/2026-09-24-one-place-in-aleph-brainstorm.md`,
  decisions 11, 12 and 16.
- That ruling makes Lattice step 3 of the Home build order. Steps 0 (`autarch serve`)
  and 1 (decisions on beads) have shipped, so it is now next.

## What exists now

The estate index in Lattice (`src/lattice/estate/`; design and formats in
Lattice `docs/estate-index.md`):

- an Uqbar loader, plus signature-gated ruled/proposed state (`ssh-keygen -Y`);
- CanonGraph's ten named queries from `sylveste-topology.yaml`, with the same ids,
  parameters and columns, plus the native queries `decision_lineage`,
  `proposed_facts`, `theme_reach`, `overdue_tending` and a lexical `search`;
- runs read from intercore, using the attribution rule of `canongraph-run-bridge.py`;
- `export_canongraph`: a copy of `log.sqlite` → Uqbar files;
- `parity`: a diff of all ten queries against live CanonGraph over MCP;
- an `estate` stdio MCP server whose `query`/`resolve`/`search` tools return
  CanonGraph's shapes, plus a CLI for hooks.

**Not built:** delivery classes on edge kinds (thesis ruling 5) and salon sittings.
The sittings' file home is still an open question on autarch-03.

## Runbook (thesis ruling 7)

Every step below is on zklw or devhost, or is mk's own act.

0. **Create the Uqbar.** Make a private repo (mk's choice of owner), then
   `python -m lattice.estate.uqbar init ~/projects/uqbar`. Put mk's public key in
   `.uqbar/allowed_signers` with the principal `mk`.
1. **Freeze.** Stop writes to the `sylveste` profile: no capture-skill ingests,
   and leave `canongraph-run-bridge.py` unregistered (see `mk-7c70`). Recall can
   keep reading.
2. **Export.** Restore `log.sqlite` from B2 (tag `canongraph`; see
   `ops/backup-restore-runbook.md` §4) into a scratch path, never beside the live
   Kùzu store. Then:
   ```
   python -m lattice.estate.export_canongraph --log <copy>/log.sqlite --inspect
   python -m lattice.estate.export_canongraph --log <copy>/log.sqlite \
     --topology ~/projects/Sylveste/ops/canongraph/sylveste-topology.yaml \
     --out ~/projects/uqbar
   ```
   `--inspect` comes first, because the exporter detects the log's columns rather
   than knowing them. Check `migrated/report.json`. Expect about 316 entities, 335
   relationships and 40 documents across 765 events (the last verified restore).
   Every line of `migrated/unparsed.jsonl` needs a decision.
3. **Review and sign.** Read the diff, commit, then mk signs:
   `python -m lattice.estate.uqbar sign ~/projects/uqbar --key ~/.ssh/<key>`.
   Until then every migrated fact reads as proposed. That is correct, because only
   mk moves a fact to ruled.
4. **Parity.** `LATTICE_UQBAR_ROOT=~/projects/uqbar python -m lattice.estate.parity --uqbar ~/projects/uqbar`
   from a machine that can reach CanonGraph. Exit 0 meets the floor.
   `runs_for_project` passes when CanonGraph's rows are a subset, because intercore
   holds runs the bridge never saw.
5. **Cut over.**
   - Point the SessionStart recall step at `python -m lattice.estate resolve|query|search`,
     or at the `estate` MCP server.
   - Replace the CanonGraph capture skill with "add a file under `proposals/`".
   - Repoint Autarch's graph source.
   - Repoint `estate-drift.py`'s graph client at the estate index.
   - Set `LATTICE_UQBAR_ROOT` on each machine.
   - Stop `canongraph.service` on devhost.
   - Rename the graph lane in `memory-lanes.md` and rewrite row 1 of `recall-lanes.md`.
   - Keep the B2 `canongraph` backups as the rollback.
6. **Supersede.** Write the Uqbar ruling that supersedes "Adopt CanonGraph as
   tracked upstream" and points at it. The courtesy PR watch on
   `jvattimo1/canongraph` can continue.

## Rollback

Until step 5's service stop, rollback means doing nothing: CanonGraph is
untouched. After it, restart `canongraph.service` and revert the consumer edits.
The event log and its B2 snapshots are never modified by any step.
