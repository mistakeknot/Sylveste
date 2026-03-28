---
bead: sylveste-rsj.1.2
type: reflection
date: 2026-03-28
---

# Reflection: Post-Merge Canary Gate (sylveste-rsj.1.2)

## What worked
- Canary is a function in lib-sprint.sh, not a hook — this means it's opt-in (landing skill calls it) rather than firing on every push
- Language detection is simple pattern matching (go.mod, Cargo.toml, package.json, pyproject.toml) — covers the project's actual stack without over-engineering
- The quality_failure event is automatically quarantined for 48h by rsj.1.4 — the two features compose correctly

## What we learned
- **Canary runs on the merged state, not the pre-merge state.** This is intentional — the landing skill already runs tests in Step 1 (pre-merge). The canary catches integration issues that only manifest after push (dependency version skew, merge conflicts resolved incorrectly).
- **The Interspect library discovery pattern (find in plugin cache) is fragile.** It works but depends on the cache directory structure. A better approach would be a `clavain-cli emit-event` command that abstracts the Interspect dependency.
- **The canary is synchronous.** It blocks the landing flow until build+test complete. For large projects this could add minutes. Acceptable for now, but if it becomes a bottleneck, consider `run_in_background` with a follow-up check.

## Risks to watch
- The canary runs `go test ./... -short` which skips long tests. If a silent failure only manifests in long tests, the canary won't catch it. The tradeoff is speed — a 10-minute canary would discourage use.
- `CLAVAIN_SKIP_CANARY=true` is a pressure release valve, but it needs monitoring. If agents learn to skip the canary, it defeats the purpose.
