# Dependency chains

The architecture doc records 17 key dependency chains (`A → B` means A depends on B):

```
Clavain (L2) → interlock → intermute (L1)    # file coordination
Clavain (L2) → interflux → intersearch        # multi-agent review
Clavain (L2) → interwatch → interpath/interdoc # doc freshness → generator dispatch
interject → intersearch                        # ambient discovery
interdeep → interject                          # deep research extraction + search
Clavain (L2) → intertrust                     # agent trust scoring
interpulse → interband → interline/intermem   # context pressure → statusline/memory
Clavain (L2) → interphase                     # phase tracking, gates, discovery
Skaffen (L2) → masaq                          # TUI components, themes
Skaffen (L2) → intercore (L1)                 # provider/tool system via Intercore bridge
Skaffen (L2) → Zaka (L2)                      # tmux agent steering
Skaffen (L2) → Alwe (L2)                      # CASS observation
Zaka (L2) + Alwe (L2) = Zakalwe               # two halves: steer + observe
Ockham (L2) → Clavain dispatch scoring          # intent → dispatch weights
Ockham (L2) → Alwe                              # anomaly detection queries
Meadowsyn (L3) → Ockham (L2)                   # UI → governor
interlab → interlock                           # delta sharing — mutation broadcast across sessions
```
