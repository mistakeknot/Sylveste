---
name: interpulse
description: "Session context monitoring — pressure tracking, token estimation, threshold warnings"
---
# Gemini Skill: interpulse

You have activated the interpulse capability.

## Base Instructions
# Interpulse

Session context monitoring — pressure tracking, token estimation, threshold warnings.

## Hooks

- `hooks/context-monitor.sh` — Tracks context pressure (call count + time decay + token estimate). Warns at Yellow/Orange/Red thresholds. Auto-checkpoints at Red.

## State

Session state stored at `/tmp/interpulse-${SESSION_ID}.json`. Contains call count, pressure score, estimated tokens, heavy call count.

## Skill

- `/interpulse:status` — Show current session pressure dashboard.

## Pressure Model

- Each tool call adds 1.0 (or 1.5 for Read/Grep/Task/WebFetch/WebSearch)
- Pressure decays 0.5 per 10 minutes of inactivity
- Token estimate: cumulative tool output length / 4
- Thresholds: Green < 60, Yellow 60+, Orange 90+, Red 120+ (or token equivalents at 150k/180k/200k)


