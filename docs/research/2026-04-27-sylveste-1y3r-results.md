---
artifact_type: research
bead: sylveste-1y3r
parent_bead: sylveste-49kl
stage: complete
spawned_beads: sylveste-ulp8
produced_in_session: a0dcc11b-be39-44e4-bf34-8d1a192a1d4f
---

# sylveste-1y3r — clavain skill_listing trim pilot results

## Verdict

The trim pilot **uncovered a YAML regression** that hid the real signal. Clavain 0.6.245 shipped malformed frontmatter in `commands/repro-first-debugging.md` (unquoted colon), causing the harness to silently drop the **entire clavain plugin** from `skill_listing`. Patched in 0.6.247.

The 13 other trims in commit `9415156` parsed cleanly and remain in production. Their actual `skill_listing` byte savings cannot be measured from this session — the broken parse confounds the comparison. A fresh session running on 0.6.247 is required to obtain clean post-trim numbers.

## Measurements

### Session a0dcc11b (clavain 0.6.245, broken)

| slice                  | bytes  |
|-----------------------|-------:|
| skill_listing         | 18,719 |
| deferred_tools_delta  | 13,222 |
| sessionstart hooks    |  8,399 |
| mcp_instructions      |  1,136 |
| async hook responses  |  1,049 |
| **total preamble**    | **48,390** |

### Pre-pilot baseline (session ff08ad22, clavain 0.6.244, healthy)

| slice                  | bytes  |
|-----------------------|-------:|
| skill_listing         | 35,036 |
| total preamble        | 71,247 |

### Apparent vs actual delta

- Apparent skill_listing delta: −16,317 bytes (paper savings)
- Of which clavain bucket: 7,557 → 0 bytes (entire plugin disappeared, 68 → 0 entries)
- Other namespaces also dropped ~9K combined — likely a knock-on effect of how the harness lists when one plugin fails to load, or a separate listing-cap pressure relief
- Therefore: the 13 valid trims contributed somewhere between 0 and ~1,500 bytes of the listing delta. We cannot disambiguate from this session.

## Root cause

```
file:    commands/repro-first-debugging.md (clavain 0.6.245)
yaml:    description: Disciplined bug investigation: reproduce first, then diagnose. ...
parse:   yaml.YAMLError: mapping values are not allowed here (col 43)
result:  plugin.json's 17 skills + 49 commands all silently absent from skill_listing
```

The colon at `investigation:` makes YAML parse the value as a mapping. The harness skips the file (no description), and a chain reaction or short-circuit in the loader appears to drop the entire plugin from the listing rather than just that one entry.

## Fix shipped

- Clavain commit `ed76bca` — `description: ... investigation — reproduce first ...` (em-dash, both SKILL.md and `docs/catalog.json`)
- Clavain version bumped 0.6.245 → 0.6.246 in repo, then 0.6.247 via `ic publish` (0.6.246 skipped in marketplace because plugin.json was already at that version when the publish tool ran)
- Marketplace: clavain@interagency-marketplace synced to 0.6.247
- Local cache: `/home/mk/.claude/plugins/cache/interagency-marketplace/clavain/0.6.247/` populated

## Spawned bead

**sylveste-ulp8** (P1, bug, labels: clavain,release-process) — Pre-publish YAML frontmatter validation gate.

This regression should have been caught before publish. Fix the release path:
- Pre-publish hook in `ic publish` validation phase: `yaml.safe_load` every SKILL.md and command .md frontmatter; fail publish on any error
- Same check on commit (pre-commit hook) to catch even earlier
- Optionally extend to plugin.json + catalog.json schema validation

## Decision branch (re-routed)

The handoff procedure offered three branches based on observed clavain bucket delta. None of them apply because the observed delta was not the trim landing — it was the plugin failing to load. The valid follow-up is:

**Step 1 (this session):** patch the YAML, republish, file release-gate bead → DONE (clavain 0.6.247, sylveste-ulp8)

**Step 2 (next fresh session):** remeasure on 0.6.247 with all 13 valid trims active. That measurement determines:
- If clavain bucket dropped ≥800b: rollout to interspect/interbrowse/tldr-swinton/interflux/interpath/interfluence as originally proposed (option 3)
- If 250-800b: trim deeper to push remaining entries below the ~117ch truncation cliff (option 2)
- If <250b: investigate listing aggregation logic, the trim style isn't reaching the listing

## Trigger-word sniff check

The handoff asked whether trim retained routing. Cannot answer from this session — clavain skills weren't in this session's skill_listing at all so the harness couldn't have routed any of them. Defer to next fresh session.

## Files & artifacts

- Patch commit: `ed76bca` in `os/Clavain/`
- Publish commit: created by `ic publish 0.6.247`
- Pre-trim measurement: `docs/research/2026-04-21-sylveste-h1w1-results.md` (session ff08ad22)
- Post-fix measurement: deferred to next session
