---
artifact_type: plan
bead: Demarch-z5qg
stage: completed
---
# Plan: Interflux Pipeline Optimization

**PRD:** docs/prds/2026-03-23-interflux-pipeline-optimization.md
**Bead:** Demarch-z5qg
**Scope:** 16 features across 6 groups (all findings from 5-agent review)
**Build sequence:** Group A (scoring) → Group B (slicing) → Group C (latency) → Group D (budget) → Group E (dropout) → Group F (supporting)
**All files are in:** `interverse/interflux/` (interflux has its own git repo)

## Group A: Scoring Changes (F1-F5)

All scoring changes are in `skills/flux-drive/SKILL.md` lines 273-390 and `docs/spec/core/scoring.md`.

### Task A1: Widen fd-correctness pre-filter (F1, Demarch-6vkx)

**File:** `skills/flux-drive/SKILL.md` line 279
**Change:** Add keywords to the data filter:
```
Before: "databases, migrations, data models, concurrency, or async patterns"
After:  "databases, migrations, data models, concurrency, async patterns, state management, validation, invariants, algorithms, contracts, schemas, queries, or SQL"
```
Also add domain-aware bypass: "If detected domain has >=3 injection criteria for fd-correctness, always pass this filter."

### Task A2: Make domain boost binary (F2, Demarch-z5qg.1)

**File:** `skills/flux-drive/SKILL.md` lines 336-339
**Change:** Replace the 3-tier boost with binary:
```
Before:
  - Agent has injection criteria with >=3 bullets → +2
  - Agent has injection criteria (1-2 bullets) → +1
  - No injection criteria → +0

After:
  - Agent has injection criteria section in domain profile → +2
  - No injection criteria section → +0
```
**Also update:** `docs/spec/core/scoring.md` lines 49-58 to match.

### Task A3: Remove generated_slots from ceiling (F3, Demarch-z5qg.4)

**File:** `skills/flux-drive/SKILL.md` lines 368-373
**Change:**
1. Remove the `generated_slots` block entirely
2. Update formula: `total_ceiling = base + scope + domain`
3. Lower `hard_maximum` from 12 to 10
4. Update examples to reflect new ceilings (repo+2domains = 4+3+2 = 9 max instead of 11)

### Task A4: Fix selection threshold (F4, Demarch-z5qg.5)

**File:** `skills/flux-drive/SKILL.md` lines 345-351
**Change:** Selection rules become:
```
1. All agents with base_score >= 3 are included (core relevance)
2. Agents with base_score = 2 are included if slots remain (adjacent)
3. Agents with base_score = 1 are included only if slots remain AND their domain covers a thin section
4. Bonuses (domain_boost, project_bonus, domain_agent) affect RANKING within each tier, not inclusion
5. Dynamic slot ceiling (see above)
6. Deduplication: prefer Project Agent over Plugin Agent for same domain
```
Add note: "Inclusion is determined by base_score. Bonuses influence Stage 1 vs Stage 2 placement and tie-breaking only."

### Task A5: Add survival-rate tracking (F5, Demarch-z5qg.2)

**File:** `skills/flux-drive/phases/synthesize.md` (cost report section)
**Change:** In the cost/findings table template, add columns:
```
| Agent | Base Score | Findings (P0/P1/P2) | Est. Tokens | Status |
```
After the table, add:
```
Tangential agent survival rate: {N}% ({M}/{T} base_score=1 agents produced P0/P1 findings)
```
If survival rate < 20%: append "Consider raising selection threshold for this project type."

## Group B: Slicing Changes (F6-F9)

All slicing changes are in `skills/flux-drive/phases/slicing.md`.

### Task B1: Replace zero-priority-skip with fallback (F6, Demarch-gunp)

**File:** `skills/flux-drive/phases/slicing.md` line 199
**Change:** Replace:
```
Before: "7. **Zero priority skip** — If an agent has zero priority sections, do not dispatch that agent at all."

After:  "7. **Zero priority fallback** — If an agent has zero priority sections despite passing pre-filter, send the full document to that agent (same as cross-cutting behavior). Log: `WARNING: {agent} has zero priority sections (score {N}). Sending full document as fallback.` In the slicing report, mark the agent as `mode: full (zero-priority fallback)`."
```
Apply same change to Method 2 (no equivalent rule currently — add it).

### Task B2: Expand fd-safety patterns (F7, Demarch-z5qg.6)

**File:** `skills/flux-drive/phases/slicing.md` lines 24-34
**Change:** Add to fd-safety priority file patterns:
```
- `**/oauth/**`, `**/sso/**`, `**/saml/**`, `**/oidc/**`
- `**/keys/**`, `**/pki/**`, `**/signing*`
- `**/webhook*`
- `**/token*` (directory/file, not just hunk keyword)
- `**/.npmrc`, `**/.pypirc`, `**/pip.conf`
```

### Task B3: Expand heading keywords (F8, Demarch-z5qg.7)

**File:** `skills/flux-drive/phases/slicing.md` lines 219-227
**Change:** Expand the heading keywords table:
```
| fd-safety | security, auth, credential, deploy, rollback, trust, permissions, secrets, certificates, encryption, compliance, audit, vulnerability, threat, access control, privacy |
| fd-correctness | data, transaction, migration, concurrency, async, race, state, consistency, integrity, idempotency, retry, error, exception, validation, schema, queue, worker, lifecycle |
| fd-performance | performance, scaling, cache, bottleneck, latency, throughput, memory, rendering, optimization, database, query, connection, pool, startup, load, concurrency, profiling, benchmark |
| fd-user-product | user, UX, flow, onboarding, CLI, interface, experience, accessibility, error handling, design, workflow, navigation, feedback, notification, settings |
```

### Task B4: Extend body sampling (F9, Demarch-z5qg.8)

**File:** `skills/flux-drive/phases/slicing.md` line 215
**Change:**
```
Before: "The section body contains any of the agent's keywords (sampled — first 50 lines)"
After:  "The section body contains any of the agent's keywords (sampled — first 50 lines + last 20 lines; for sections <= 70 lines, read entire body)"
```

## Group C: Latency Changes (F10-F11)

### Task C1: Incremental Stage 2 dispatch (F10, Demarch-z5qg.10)

**File:** `skills/flux-drive/phases/launch.md` lines 348-360, 488-540
**Change:** After Step 2.2a (Stage 1 dispatch), modify the completion monitoring to support incremental expansion:

1. When a Stage 1 agent completes, immediately compute its contribution to expansion scores for Stage 2 candidates
2. If any Stage 2 candidate reaches expansion_score >= 3 from partial results, launch it as a speculative Stage 2 agent without waiting for full Stage 1 completion
3. Cap speculative launches at 2 agents
4. At full Stage 1 completion, the expansion decision (Step 2.2b) only handles agents not yet speculatively launched
5. Mark speculative launches in triage report: `[speculative — launched after {agent} completed]`

Add between Step 2.2a and Step 2.3:
```markdown
#### Step 2.2a.6: Incremental expansion (during Stage 1)

As each Stage 1 agent completes (.md file appears):
1. Read its Findings Index
2. For each Stage 2 / expansion pool candidate, compute partial expansion score using only the completed agent's findings
3. If any candidate reaches expansion_score >= 3: launch immediately (max 2 speculative launches)
4. Log: `[speculative Stage 2] Launching {agent} based on {trigger_agent}'s P{severity} finding in {domain}`

Speculative launches do NOT count against the slot ceiling — they are bonus agents justified by Stage 1 evidence.
```

### Task C2: Reduce polling to 5s (F11, Demarch-z5qg.11)

**File:** `skills/flux-drive/phases/shared-contracts.md` line 107
**Change:**
```
Before: "Check `{OUTPUT_DIR}/` for `.md` files every 30 seconds"
After:  "Check `{OUTPUT_DIR}/` for `.md` files every 5 seconds (ls on <15 files is negligible cost)"
```

## Group D: Budget Fixes (F12-F13)

### Task D1: Fix token data recording (F12, Demarch-ozox)

**File:** `skills/flux-drive/phases/synthesize.md` (Step 3.4b cost report)
**Change:** After synthesis completes and all agent outputs are collected, add a token recording step:

```markdown
#### Step 3.4c: Record token estimates to interstat

For each dispatched agent, write an estimate to interstat:
\`\`\`bash
# Approximate tokens from output file size (1 token ≈ 4 chars)
for agent_file in "${OUTPUT_DIR}"/*.md; do
    agent_name=$(basename "$agent_file" .md)
    file_chars=$(wc -c < "$agent_file")
    est_output_tokens=$((file_chars / 4))
    # Record to interstat (agent_runs table)
    # The input tokens are harder to estimate; use the review file size as proxy
    review_chars=$(wc -c < "${REVIEW_FILE:-/dev/null}" 2>/dev/null || echo "0")
    est_input_tokens=$((review_chars / 4))
    est_total=$((est_input_tokens + est_output_tokens))
    sqlite3 "${INTERSTAT_DB:-$HOME/.claude/interstat/metrics.db}" \
        "UPDATE agent_runs SET total_tokens=$est_total, input_tokens=$est_input_tokens, output_tokens=$est_output_tokens WHERE agent_name='interflux:$agent_name' AND total_tokens IS NULL ORDER BY created_at DESC LIMIT 1;" 2>/dev/null || true
done
\`\`\`
```

Note: This is an approximation (chars/4). More accurate token counting requires session JSONL parsing, which is a future improvement. The approximation is sufficient to unblock calibration and identify which defaults in budget.yaml are significantly wrong.

### Task D2: Fix namespace mismatch (F13, Demarch-8v79)

**File:** `scripts/estimate-costs.sh` lines 85-101
**Change:** Normalize agent names in the SQL query by stripping the `interflux:` prefix:
```sql
SELECT REPLACE(agent_name, 'interflux:', '') as agent_name,
       CAST(ROUND(AVG(total_tokens)) AS INTEGER) as est_tokens,
       COUNT(*) as sample_size
FROM agent_runs
WHERE (model = '${MODEL}' OR model IS NULL)
  AND total_tokens IS NOT NULL
GROUP BY REPLACE(agent_name, 'interflux:', '')
HAVING COUNT(*) >= 3
ORDER BY agent_name;
```

Also fix the case-sensitivity issue on line 119:
```
Before: "$script_dir/../../../os/clavain/scripts/lib-fleet.sh"
After:  "$script_dir/../../../os/Clavain/scripts/lib-fleet.sh"
```

## Group E: Dropout/Expansion (F14-F15)

### Task E1: Fix dropout spec drift (F14, Demarch-z5qg.12)

**Files:**
- `docs/spec/core/staging.md` line 182: change "Default 0.7" → "Default 0.6"
- `docs/spec/core/staging.md` line 195: update rationale for 0.6
- `AGENTS.md` lines 210, 297: change "0.7" → "0.6"
- `config/flux-drive/budget.yaml` line 44-47: add comment "Recall validation pending — needs token data (F12) to measure finding recall at different thresholds"

### Task E2: Add Project Agent adjacency (F15, Demarch-z5qg.13)

**File:** `skills/flux-drive/phases/launch.md` lines 495-503 (adjacency map)
**Change:** After the hardcoded adjacency map, add a dynamic resolution rule:
```markdown
**Project Agent adjacency (dynamic):**

For Project Agents (generated by /flux-gen):
1. **Domain-mode agents** (frontmatter has `domain:` field): Map to the plugin agent(s) whose adjacency domain overlaps. E.g., a `domain: web-api` agent is adjacent to fd-safety, fd-correctness, fd-performance.
2. **Prompt-mode agents** (frontmatter has `generated_by: flux-gen-prompt`): Infer domain from `focus` and `review_areas` fields by keyword matching against the domain keywords table (launch.md lines 139-148). Use the top-matching domain for adjacency.
3. **No match**: Agent has no adjacency entries — retained by default during dropout (conservative), excluded from adjacency-based expansion scoring.

**Cognitive agents** are intentionally excluded from the adjacency map — they operate on a different analytical axis and are retained by default when pre-filter passes.
```

Also document in the expansion scoring section that Project Agents without adjacency can only reach expansion_score = 1 (from domain criteria alone).

## Group F: Supporting (F16)

### Task F1: Add document abstract for 200-499 line docs (F16, Demarch-z5qg.9)

**File:** `skills/flux-drive/phases/slicing.md` lines 259-265
**Change:** Replace:
```
Before: "For documents 200-500 lines, skip summaries — classify sections only"

After:  "For documents 200-500 lines, generate a 2-3 sentence document abstract (NOT per-section summaries). Prepend the abstract to all sliced agent content as orientation context. Cost: ~50 tokens per agent. This ensures domain-specific agents receiving sliced content can understand how their priority sections fit into the larger document."
```

## Build Sequence

Execute in this order (groups can be parallelized within, but groups should be sequential to avoid merge conflicts in shared files):

1. **Group A** (F1-F5): SKILL.md scoring section + scoring.md spec + synthesize.md. ~30 min.
2. **Group B** (F6-F9): slicing.md only. ~15 min.
3. **Group C** (F10-F11): launch.md + shared-contracts.md. ~20 min.
4. **Group D** (F12-F13): synthesize.md + estimate-costs.sh. ~15 min.
5. **Group E** (F14-F15): staging.md + AGENTS.md + budget.yaml + launch.md. ~15 min.
6. **Group F** (F16): slicing.md. ~5 min.

**No Go code changes.** No compilation needed. Test by running `/interflux:flux-drive` on a sample document and verifying triage output.

## Verification

After all groups:
- [ ] SKILL.md pre-filter has expanded keyword set for fd-correctness
- [ ] SKILL.md domain boost is binary (+0/+2 only)
- [ ] SKILL.md ceiling formula has no `generated_slots`; hard_max = 10
- [ ] SKILL.md selection rules use base_score for inclusion, bonuses for ranking
- [ ] synthesize.md cost table includes base_score and survival rate
- [ ] slicing.md zero-priority rule sends full document instead of dropping agent
- [ ] slicing.md fd-safety has oauth/sso/webhook/token/keys patterns
- [ ] slicing.md heading keywords expanded for all 4 domain agents
- [ ] slicing.md body sampling includes last 20 lines
- [ ] launch.md has incremental expansion step (2.2a.6)
- [ ] shared-contracts.md polling is 5s
- [ ] synthesize.md has token recording step (3.4c)
- [ ] estimate-costs.sh strips `interflux:` prefix and fixes Clavain casing
- [ ] staging.md and AGENTS.md say 0.6 (not 0.7) for dropout threshold
- [ ] launch.md has Project Agent adjacency resolution rules
- [ ] slicing.md has document abstract for 200-499 line docs
- [ ] `/interflux:flux-drive docs/prds/2026-03-23-interflux-pipeline-optimization.md` produces correct triage output
