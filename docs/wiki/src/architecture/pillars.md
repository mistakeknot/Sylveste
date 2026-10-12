# Pillars and layers

Sylveste has 6 pillars:

| Pillar | Layer | Role |
|--------|-------|------|
| Intercore | L1 | Orchestration kernel (Go CLI `ic`) |
| Clavain | L2 | Autonomous software agency (OS layer) |
| Skaffen | L2 | Sovereign agent runtime, peer of Clavain |
| Interverse | L2 | Companion plugins (drivers) that extend Clavain |
| Autarch | L3 | TUI and multi-runtime application interfaces |
| Interspect | cross-cutting | Adaptive profiler: reads kernel events, proposes configuration changes |

"Pillar" is an organizational term. "Layer" (L1, L2, L3) is the architectural
dependency level; Interspect belongs to no layer.
