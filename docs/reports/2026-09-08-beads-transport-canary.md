# Beads transport canary

The native Mac → zklw → Mac journey passed on the first ordinary pull in each
direction. Independent GPT-5.6 Sol review accepted this bounded result.
`sylveste-bkrh` remains open: historical record conflicts still prevent full
reconciliation, so Remontoire reprioritization remains disabled.

The repair is installed in `/Users/sma/projects/Sylveste-beads-transport` and
the zklw main checkout. Source `01bf9f0e` and cleanup repair `f5e5c36a` passed
independent review and exact required CI checks. Other Mac worktrees retain
their previous hooks and are excluded consumers; unrelated dirty work remains.

| Native leg | Ordinary pull | Expected database changes | Result |
|---|---|---|---|
| Mac → zklw | `f5e5c36a` → `a3318c13` | Created/updated `Sylveste-fayz`, in progress | Passed |
| zklw → Mac | `a3318c13` → `d19e1cef` | Updated/closed `Sylveste-fayz`; received existing `sylveste-7jj5` | Passed |

Both legs verified complete native record content against the committed
transport, exact Git ancestry, a durable verified import verdict, no pending
batch, and no unexpected native changes. Neither leg used a retry or manual
import. Import temporary files were absent and the transport lock was released.
Full native snapshots remain private on their respective hosts.

The outbound and return commits each passed the required Generator and parity
checkers before normal main publication: [outbound CI](https://github.com/mistakeknot/Sylveste/actions/runs/34233474869/job/102085155054)
and [return CI](https://github.com/mistakeknot/Sylveste/actions/runs/34234619353/job/102089023748).

The initial reconciliation import preceded the canary and exposed an EXIT-trap
cleanup error (`TMP: unbound variable`). Its data arrived, but that run did not
earn cleanup or canary acceptance. Sonnet 5 implemented the bounded repair;
34 import regressions and independent Sol review passed before installation
and the two subsequent native canary legs.

Separate backup evidence is complete. The existing zklw signed Dolt push gate
returned success under confirmed authorization `73ae2ec9cad0d9fa23d0ced18a592ada`.
Its signature and legacy anchor verified under fingerprint `3d1c3001d533c5a9`.
Earlier withheld attempts remain recorded. The configured native backup also
synced; no signing policy, delegation level, or backup remote was changed.

Final record reconciliation covered 3,921 records on each host with no missing
IDs or malformed records. The Mac retains two equal-time content conflicts
(`Sylveste-fuwn`, `sylveste-bkrh`); zklw retains fourteen historical content
conflicts. These records require reviewed provenance and supported native resolution. A passing
fresh-record canary does not establish convergence of those histories.

All 14 deterministic roadmap consumer checks passed against Interpath
`9a32cff9535667b509beb3a03da7afee38aaa4ec`, the installed zklw producer.
A private projection of the frozen Mac snapshot contains all 527 nonclosed
records exactly once, including 18 deferred records and the recovered
Remontoire task. It excludes the closed canary. Two consecutive generations
produced identical bytes. This validates the consumer on that host's snapshot;
the projection was not published as a converged cross-host roadmap.

Task-local routing now uses Sonnet 5 for bounded implementation, Opus 5 for
harder implementation, and Opus 5 / GPT-5.6 Sol for first-pass plan and QA
review. Fable 5.1 handles consequential unresolved review escalations. No
global defaults changed, and no measured token-savings claim is made.
