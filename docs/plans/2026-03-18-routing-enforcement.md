# Plan: B2 Routing Enforcement + Cost Reduction Campaign

**Beads:** Sylveste-k2xf.5, Sylveste-1x9l.2
**Brainstorm:** docs/brainstorms/2026-03-18-routing-enforcement.md

## Task Breakdown

### Task 1: Shadow log aggregation script
**Files:** `os/Clavain/scripts/routing-shadow-report.sh` (new)
**Steps:**
1. Write a script that greps cass session logs for `[B2-shadow]` lines
2. Parse tier distribution: count C1-C5 classifications
3. Parse would-have-changed: count upgrade vs downgrade events per agent
4. Output a summary table: tier | count | would-change | direction
5. Include a "readiness verdict" — enforce if >80% of changes are downgrades to C1/C2
**Acceptance:** `bash os/Clavain/scripts/routing-shadow-report.sh` produces readable output (even if no shadow data exists yet)

### Task 2: Capture cost baseline
**Files:** none (data collection only)
**Steps:**
1. Run `cost-query.sh baseline` to capture current cost_per_landable_change
2. Record baseline in brainstorm doc as reference
**Acceptance:** Baseline number documented

### Task 3: Flip routing.yaml to enforce mode
**Files:** `os/Clavain/config/routing.yaml`
**Steps:**
1. Change `mode: shadow` → `mode: enforce` under `complexity:`
2. Update comment to reference this bead
3. Verify: source lib-routing.sh, call `routing_resolve_agents` with C2 signals, confirm haiku is returned
**Acceptance:** `routing_resolve_agents --phase executing --agents "fd-quality" --prompt-tokens 100` returns `haiku`

### Task 4: Verify safety floors still hold in enforce mode
**Files:** none (verification only)
**Steps:**
1. Call `routing_resolve_agents` with C1 signals for fd-safety → must return `sonnet` (not haiku)
2. Call `routing_resolve_agents` with C1 signals for fd-correctness → must return `sonnet` (not haiku)
3. Call `routing_resolve_agents` with C5 signals for any agent → must return `opus`
**Acceptance:** All three assertions pass

### Task 5: Also claim and close Sylveste-1x9l.2
**Steps:**
1. Claim Sylveste-1x9l.2
2. Document: enforcement is active, cost tracking via interstat/cost-query.sh
3. Close — the campaign metric (cost_per_landable_change) will be measured in future sessions
**Acceptance:** Both beads closed

## Verification
```bash
source os/Clavain/scripts/lib-routing.sh
# C2 task → haiku for non-safety agent
routing_resolve_agents --phase executing --agents "fd-quality" --prompt-tokens 100 --file-count 1 --reasoning-depth 1
# C1 task → haiku for non-safety, but sonnet for safety
routing_resolve_agents --phase executing --agents "fd-safety,fd-quality" --prompt-tokens 50 --file-count 1 --reasoning-depth 1
# C5 task → opus
routing_resolve_agents --phase executing --agents "fd-quality" --prompt-tokens 5000 --file-count 20 --reasoning-depth 5
```
