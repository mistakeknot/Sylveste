# Closed-loop cost-calibration live template

Bead: `sylveste-oyrf.1`

This page is the `/live/closed-loop.md` source template for the public closed-loop cost-calibration view. It is intentionally safe to render on `sylvst.com/live`: it links only to the repository/public CSV and never exposes private Interstat session logs, local databases, prompts, Beads state, or credentials.

## Public data contract

- Data file: [`/data/cost-trajectory.csv`](../../data/cost-trajectory.csv)
- Repository path: `data/cost-trajectory.csv`
- Refresh path: `.github/workflows/oyrf-cost-calibration.yml` runs `bash estimate-costs.sh` every six hours.
- Safe-empty behavior: if Interstat metrics are unavailable, the exporter appends an `interstat-empty` row so the public graph remains structurally valid.

## Closed-loop readout

The live page should render these fields from the newest rows in `cost-trajectory.csv`:

| Field | Meaning |
| --- | --- |
| `captured_at` | UTC timestamp for the estimator sample. |
| `window_days` | Lookback window used for the Interstat baseline query. |
| `session_count` | Number of sessions included in the window. |
| `total_tokens` | Input plus output tokens counted by Interstat. |
| `total_cost_usd` | Estimated API-equivalent spend for the window. |
| `cost_per_session_usd` | Normalized cost pressure for session-cadence decisions. |
| `source` | `interstat`, `interstat-empty`, or `dry-run-fixture`. |

## Operator notes

- Treat the public chart as a feedback loop, not as accounting truth.
- Use sustained slope changes to decide whether agent-routing, review, or session-cadence policy needs adjustment.
- If `source=interstat-empty` persists for more than one day, repair the Interstat collection path before using the chart for public calibration decisions.
- Link this template from the `sylvst.com/live` index as the closed-loop cost-calibration panel once the site renderer consumes `docs/live/*.md`.
