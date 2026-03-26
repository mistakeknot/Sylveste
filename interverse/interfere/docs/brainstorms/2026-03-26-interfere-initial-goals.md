---
artifact_type: brainstorm
bead: none
stage: discover
---

# interfere — Initial Goals (March-April 2026)

## Goal 1: Ship the Server End-to-End
Wire the Metal worker subprocess to the inference engine. Serve a real model (Qwen3-30B Q4_K_M). Verify Clavain can route to it in Track B5 shadow mode. Measure baseline tok/s and quality on Clavain's actual task distribution.

**Success criteria:**
- `curl localhost:8421/v1/chat/completions` returns streaming completions from Qwen3-30B
- Clavain routing logs show shadow-mode decisions for C1/C2 tasks
- Baseline benchmark: tok/s, TTFT, quality score on 100 representative coding tasks

## Goal 2: Run First Experiments
Enable early exit and speculative decoding experiments on real workloads. Measure speedup vs baseline. Publish interlab campaign results.

**Success criteria:**
- Early exit experiment shows measurable tok/s improvement (target: 1.3x) without quality regression
- Speculative decoding with 3B draft model shows 1.8x+ speedup with 65%+ acceptance rate
- interlab campaign dashboards showing before/after metrics

## Goal 3: Full Clavain Integration
Enable Track B5 enforce mode. Confidence cascade working (local-first, cloud fallback). Privacy routing classifying tasks as public/internal/sensitive. Cost tracking showing savings vs cloud.

**Success criteria:**
- 60%+ of C1/C2 tasks route locally in enforce mode
- Privacy classification correctly routes .env-adjacent code locally
- Cost dashboard shows $/task comparison: local vs cloud for each complexity tier
- No quality regression on interspect evidence (>95% match rate vs cloud baseline)

## Timeline
- Week 1: Goal 1 (server E2E + first model serving)
- Week 2: Goal 2 (experiments) — can overlap with Goal 1 tail
- Week 3-4: Goal 3 (Clavain integration + cost tracking)
