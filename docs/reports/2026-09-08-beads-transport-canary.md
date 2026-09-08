# Beads transport canary

The reviewed transport repair is installed in the linked Mac checkout and
zklw. Source `01bf9f0e` and cleanup repair `f5e5c36a` passed independent review
and their exact required CI checks.

Native canary `Sylveste-fayz` was created and updated on the Mac. This report's
ordinary commit triggers the installed exporter. The planned journey is a
first ordinary zklw pull, a native update and close on zklw, and a first
ordinary return pull on the Mac.

Each leg must show the expected native content, exact Git ancestry, a durable
verified import verdict, no pending batch or retry, no unexpected native
changes, no import temporary files left behind, and a released transport lock.
Host-native snapshots remain private. Results will be recorded after execution.

Historical conflicts remain distinct from this fresh-record check. Neither
this prospective report nor a passing canary closes `sylveste-bkrh` while its
final reconciliation remains incomplete.

The Mac-to-zklw leg passed on its first ordinary pull (`f5e5c36a` to
`a3318c13`). Only the canary changed natively, its complete semantic content
matched the transport, and the import, pending-state, temporary-file and lock
checks passed. The canary has now been updated and closed natively on zklw;
the Mac return leg remains pending.
