---
artifact_type: prd
bead: Sylveste-z5qg
stage: design
---
# PRD: Interflux Pipeline Optimization

## Problem

The flux-drive multi-agent review pipeline has scoring, slicing, latency, and budget issues that waste tokens, miss findings, and provide no cost feedback. Bonus inflation nullifies the triage scoring in mature projects, content slicing has safety gaps and a contract violation, the Stage 1→2 barrier wastes 3-6 minutes per review, and the entire budget system runs on fabricated defaults because token data is never recorded.

## Solution

16 targeted fixes across 6 groups: scoring discrimination, slicing precision, dispatch latency, budget accountability, dropout calibration, and supporting improvements. All changes are in SKILL.md files, config YAML, and one Python script — no Go code changes.

## Features

### F1: Widen fd-correctness pre-filter keywords
**What:** The data filter skips fd-correctness unless the document mentions databases/migrations/concurrency/async — too narrow.
**Bead:** Sylveste-6vkx
**Files:** `skills/flux-drive/SKILL.md` (pre-filter section)
**Acceptance criteria:**
- [ ] Pre-filter passes fd-correctness on additional keywords: `state`, `validation`, `invariant`, `algorithm`, `contract`, `schema`, `query`, `SQL`
- [ ] Alternatively: if detected domain has >=3 injection criteria for fd-correctness, always pass pre-filter

### F2: Make domain boost binary or add relevance annotation
**What:** All domain profiles have exactly 5 bullets per agent section, so the +1 tier (1-2 bullets) never triggers — boost is effectively binary +0/+2.
**Bead:** Sylveste-z5qg.1
**Files:** `skills/flux-drive/SKILL.md` (scoring section), `docs/spec/core/scoring.md`
**Acceptance criteria:**
- [ ] Domain boost simplified to binary: +0 (no section in domain profile) / +2 (section exists)
- [ ] Remove the dead +1 tier from scoring docs and spec
- [ ] Scoring examples updated to reflect binary boost

### F3: Remove generated_slots from ceiling formula
**What:** `generated_slots: +2` expands the total agent pool to 11/12 instead of making generated agents compete on score within existing slots.
**Bead:** Sylveste-z5qg.4
**Files:** `skills/flux-drive/SKILL.md` (dynamic slot allocation section)
**Acceptance criteria:**
- [ ] `generated_slots` removed from ceiling formula
- [ ] Generated agents compete on score within `base(4) + scope + domain` ceiling
- [ ] `hard_maximum` lowered from 12 to 10

### F4: Fix selection threshold for mature projects
**What:** Score>=2 provides zero discrimination after bonus inflation (+2 domain + +1 project = every agent exceeds 2).
**Bead:** Sylveste-z5qg.5
**Files:** `skills/flux-drive/SKILL.md` (selection rules section)
**Acceptance criteria:**
- [ ] Selection threshold applied to `base_score` only (not inflated final_score) — bonuses influence ranking but not inclusion
- [ ] Agents with base_score < 2 only included if slots remain after base_score >= 2 agents are placed

### F5: Add base_score=1 survival-rate tracking
**What:** No feedback loop tracks whether tangential agents (~40K tokens each) find anything useful.
**Bead:** Sylveste-z5qg.2
**Files:** `skills/flux-drive/phases/synthesize.md` (cost report section)
**Acceptance criteria:**
- [ ] Synthesis report includes per-agent `base_score` and `finding_count` in cost table
- [ ] Survival rate calculated: % of base_score=1 agents that produced P0/P1 findings
- [ ] If survival rate < 20% across session, note in report: "Consider raising selection threshold"

### F6: Replace zero-priority-skip with full-document fallback
**What:** Agents with zero priority sections after slicing are silently dropped despite user confirmation — contract violation.
**Bead:** Sylveste-gunp
**Files:** `skills/flux-drive/phases/slicing.md`
**Acceptance criteria:**
- [ ] Zero-priority agents receive full document instead of being dropped
- [ ] Warning logged: `"{agent} has zero priority sections despite passing pre-filter (score {N}). Sending full document as fallback."`
- [ ] Slicing report marks agent as `mode: full (zero-priority fallback)`

### F7: Expand fd-safety priority file patterns
**What:** Missing common auth/credential file paths in slicing patterns.
**Bead:** Sylveste-z5qg.6
**Files:** `skills/flux-drive/phases/slicing.md` (fd-safety patterns)
**Acceptance criteria:**
- [ ] Added patterns: `**/oauth/**`, `**/sso/**`, `**/saml/**`, `**/oidc/**`, `**/keys/**`, `**/pki/**`, `**/signing*`, `**/webhook*`, `**/token*`, `**/.npmrc`, `**/.pypirc`, `**/pip.conf`

### F8: Expand Method 2 heading keywords
**What:** Heading keywords for document slicing miss critical terms across all agents.
**Bead:** Sylveste-z5qg.7
**Files:** `skills/flux-drive/phases/slicing.md` (Method 2 keyword table)
**Acceptance criteria:**
- [ ] fd-safety: add `encryption`, `compliance`, `audit`, `vulnerability`, `threat`, `access control`, `privacy`
- [ ] fd-correctness: add `idempotency`, `retry`, `error`, `exception`, `validation`, `schema`, `queue`, `worker`, `lifecycle`
- [ ] fd-performance: add `database`, `query`, `connection`, `pool`, `startup`, `load`, `concurrency`, `profiling`, `benchmark`
- [ ] fd-user-product: add `design`, `workflow`, `navigation`, `feedback`, `notification`, `settings`

### F9: Extend body keyword sampling to include tail
**What:** Body sampling only checks first 50 lines, missing conclusions and summaries in long sections.
**Bead:** Sylveste-z5qg.8
**Files:** `skills/flux-drive/phases/slicing.md` (Method 2 body sampling)
**Acceptance criteria:**
- [ ] Body sampling changed from "first 50 lines" to "first 50 + last 20 lines"
- [ ] For sections <= 70 lines, read entire body (no sampling)

### F10: Implement incremental Stage 2 dispatch
**What:** Stage 2 agents wait 3-6 minutes for all Stage 1 agents to complete before expansion scoring begins.
**Bead:** Sylveste-z5qg.10
**Files:** `skills/flux-drive/phases/launch.md` (Steps 2.2, 2.2b, 2.2c)
**Acceptance criteria:**
- [ ] As each Stage 1 agent completes, compute its contribution to expansion scores
- [ ] When any Stage 2 candidate reaches score >= 3 from partial results, launch as speculative Stage 2
- [ ] Full expansion decision at Stage 1 completion only handles agents not yet speculatively launched
- [ ] Speculative launches flagged in triage report

### F11: Reduce polling interval from 30s to 5s
**What:** Up to 30 seconds of dead time between agent completion and orchestrator noticing, accumulating 1-2.5 minutes across a review.
**Bead:** Sylveste-z5qg.11
**Files:** `skills/flux-drive/phases/shared-contracts.md` (monitoring contract)
**Acceptance criteria:**
- [ ] Polling interval changed from 30s to 5s
- [ ] Comment noting `ls` on <15 files is negligible cost at 5s interval

### F12: Fix token data recording
**What:** All 106 agent runs in interstat have NULL token columns — budget estimation is permanently stuck on cold-start defaults.
**Bead:** Sylveste-ozox
**Files:** `scripts/estimate-costs.sh`, interstat hook or SessionEnd processing
**Acceptance criteria:**
- [ ] Token data populated for flux-drive agent runs after each review
- [ ] Mechanism: parse session JSONL at review completion to extract per-agent token usage, or have synthesis step write token counts to interstat
- [ ] At least `total_tokens` column populated; `input_tokens`/`output_tokens` if available

### F13: Fix agent name namespace mismatch
**What:** estimate-costs.sh looks up `fd-architecture` but interstat stores `interflux:fd-architecture` — lookups always miss.
**Bead:** Sylveste-8v79
**Files:** `scripts/estimate-costs.sh` (classify_agent function, query)
**Acceptance criteria:**
- [ ] Query normalizes agent names: `REPLACE(agent_name, 'interflux:', '')` in SQL
- [ ] Or: lookup key includes prefix to match DB storage
- [ ] Fix verified: query returns non-NULL rows for agents with >= 3 runs (once F12 populates data)

### F14: Validate dropout threshold and fix spec drift
**What:** Threshold lowered 0.7→0.6 without recall-loss measurement; staging.md still says 0.7.
**Bead:** Sylveste-z5qg.12
**Files:** `docs/spec/core/staging.md`, `AGENTS.md`, `config/flux-drive/budget.yaml`
**Acceptance criteria:**
- [ ] staging.md updated to say 0.6 (matching budget.yaml and launch.md)
- [ ] AGENTS.md references updated from 0.7 to 0.6
- [ ] Rationale paragraph in staging.md updated for 0.6 threshold
- [ ] Comment added noting recall validation is pending (needs F12 data first)

### F15: Add Project Agent adjacency resolution
**What:** Project/flux-gen agents are absent from the adjacency map — invisible to both dropout and expansion scoring.
**Bead:** Sylveste-z5qg.13
**Files:** `skills/flux-drive/phases/launch.md` (adjacency map, redundancy scoring, expansion scoring)
**Acceptance criteria:**
- [ ] Domain-mode agents: derive adjacency from `domain:` frontmatter field, mapping to closest plugin agent(s)
- [ ] Prompt-mode agents: infer domain from `focus` and `review_areas` fields via keyword matching against domain keywords table
- [ ] Adjacency map documented as extensible (new agents get adjacency via frontmatter)
- [ ] Cognitive agents documented as intentionally excluded (different analytical axis)

### F16: Add document abstract for 200-499 line docs
**What:** Documents 200-499 lines get slicing but no Pyramid Summary — agents have no document-level orientation.
**Bead:** Sylveste-z5qg.9
**Files:** `skills/flux-drive/phases/slicing.md` (document size thresholds)
**Acceptance criteria:**
- [ ] For 200-499 line documents, generate 2-3 sentence document abstract
- [ ] Prepend abstract to all sliced agent content
- [ ] Cost: ~50 tokens per agent, justified by improved orientation

## Non-goals
- Changing the core agent roster (adding/removing fd-* agents)
- Rewriting the Python scripts (detect-domains.py, generate-agents.py) beyond the namespace fix
- Building a full cost dashboard (F12 enables data collection; visualization is future work)
- Changing the Agent tool API (token reporting depends on what Claude Code exposes)

## Dependencies
- F4 (threshold fix) and F3 (ceiling fix) should land together — both address bonus inflation
- F5 (survival tracking) benefits from F12 (token data) but works independently with finding counts
- F13 (namespace fix) is only useful after F12 (token recording) populates data
- F15 (adjacency) improves dropout (F14) accuracy but is independently valuable

## Open Questions
1. **F12 mechanism:** Session JSONL parsing vs synthesis-step token counting? JSONL is more accurate but requires post-processing pipeline. Synthesis-step is immediate but approximate.
2. **F4 threshold:** Apply to base_score only (recommended) or raise to score>=3? Former is more surgical.
3. **F10 speculative dispatch:** How many speculative Stage 2 agents before hitting diminishing returns? Cap at 2?
