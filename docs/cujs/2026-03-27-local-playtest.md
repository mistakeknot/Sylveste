---
title: "Local Game Playtesting via interfer"
date: 2026-03-27
bead: sylveste-86r
---

# CUJ: Local Game Playtesting via interfer

## Persona
Developer working on Shadow Work who wants continuous emergence testing without API costs.

## Journey

1. **Start interfer** — `cd interverse/interfer && uv run python -m server.main` (port 8421)
2. **Start Shadow Work** — `cd ../shadow-work && pnpm dev:tauri` (debug server on 8790)
3. **Run local playtest** — `python scripts/playtest-bridge.py --campaign climate-cascade`
4. **Bridge loops:**
   - GET `localhost:8790/api/status` → game state JSON
   - POST `localhost:8421/v1/chat/completions` with game state as context + "what should I do next?" prompt
   - Parse model response → POST `localhost:8790/api/control` with action
   - Repeat every 2-3 seconds (or per game tick)
5. **Campaign completes** — Assertions checked against expected outcomes
6. **Review results** — Metrics logged: decisions made, assertion pass rate, tok/s, thermal state

## Success Criteria
- Campaign completes without manual intervention
- >80% assertion pass rate (comparable to cloud runs)
- Zero API token cost
- M5 Max stays below thermal throttle threshold
