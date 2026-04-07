---
agent: fd-broadcast-signal-routing
tier: project
model: sonnet
input: interflux-insight-efficiency-openrouter/input.md
track: b (operational parallel disciplines)
---

# fd-broadcast-signal-routing — Findings

## Findings Index

| Severity | ID | Section | Title |
|----------|-----|---------|-------|
| P0 | BSR-01 | Quality Monitoring | No signal quality monitoring: degraded cheap-model output passes through without detection |
| P1 | BSR-02 | Failover | Provider failover is manual: requires config change, not automatic switching |
| P2 | BSR-03 | Format Normalization | Format conversion artifacts: findings format mismatch between Claude and OpenRouter outputs |
| P2 | BSR-04 | Aggregation | Multi-feed aggregation missing: no mechanism to combine findings from different model families for robustness |
| P3 | BSR-05 | Architecture | Contribution vs distribution quality tiers not defined: synthesis quality requirement unspecified |

---

## Detailed Findings

### P0 — BSR-01: No Signal Quality Monitoring — Degraded Output Passes to Air

**Broadcast parallel:** The cardinal sin in live broadcast is letting a degraded feed reach air without detection. Signal quality monitoring exists precisely because degradation is rarely catastrophic and immediate — it's subtle: pixelation, audio dropout, sync drift. By the time you notice visually, you've been on-air with bad signal for minutes.

**Interflux parallel:** The proposed architecture routes some agents to cheap models via OpenRouter. The current synthesis step validates output *format* (completion signal, findings index structure), but there is no mechanism to score *quality* of cheap-model output before it enters synthesis. Specifically:

1. **Finding density:** A cheap model may produce 1-2 findings where Claude would produce 5-8, not because fewer issues exist but because the model is shallower. Low finding density looks like a clean review.
2. **Severity miscalibration:** A cheap model may rate a P0 finding as P2 (or vice versa) due to different training data emphasis. Synthesis averages severity — a miscalibrated cheap agent drags down severity scores.
3. **Hallucinated findings:** A cheap model may produce confident-sounding P1 findings about code sections it didn't read carefully. These pass format validation and enter synthesis.

**Failure scenario:** `fd-quality` routes to Qwen 2.5. Qwen produces 2 findings (format-valid) where Claude would produce 7. Synthesis computes `convergence: 2/4 agents flagged style issues` (below threshold). The quality section appears clean. A style regression ships. The shallow review was indistinguishable from a thorough one.

**Critical distinction from SCM-01:** This P0 is different from the supply chain fallback P0. That was about provider outage (absence). This is about quality degradation while the provider is *up* — signal quality monitoring during normal operation.

**Fix:** Add a findings density check in synthesis: if a cheap-model agent's finding count is >50% below the median for that agent type across historical runs (interstat data), flag it as `low_signal_confidence` and weight its findings lower in convergence scoring. One additional computation in `phases/synthesize.md`.

---

### P1 — BSR-02: Provider Failover is Manual — No Automatic Switching

**Broadcast parallel:** In live broadcast, automatic failover is a hard requirement. When primary satellite feed degrades, the backup fiber feed switches in under 100ms — no operator action required. Manual failover takes 30-60 seconds minimum; on live TV, that's a dead air incident.

**Interflux parallel:** The input document correctly identifies that OpenRouter integration requires fallback to Claude-only when OpenRouter is unavailable. But the proposed architecture has no mechanism for automatic failover. If OpenRouter returns a 429 (rate limit) or 503 (outage):

- The Bash tool call fails
- The orchestrator receives an error
- The agent's `.partial` file is never renamed to `.md`
- Synthesis either (a) times out waiting, (b) proceeds with missing agent, or (c) errors

None of these outcomes trigger automatic re-dispatch to Claude. The orchestrator has no circuit-breaker that says "OpenRouter agent X failed → re-dispatch to Claude haiku."

**Failure scenario:** A flux-drive run starts during a brief OpenRouter rate-limit window (common during peak hours). Two OpenRouter agents fail silently. Synthesis proceeds with partial coverage. User receives a findings report missing two agent perspectives with no indication of the gap.

**Fix:** In the HTTP dispatch wrapper for OpenRouter calls, add retry-with-escalation logic: (1) retry with exponential backoff (2 attempts), (2) if still failing, re-dispatch the agent task to Claude haiku, (3) mark the finding with `provider_fallback: true`. This is 15-20 lines of bash in the dispatch wrapper — the pattern already exists in broadcast engineering as "primary/backup/emergency chain."

---

### P2 — BSR-03: Format Conversion Artifacts — Findings Format Mismatch

**Broadcast parallel:** Converting between signal formats (SDI→IP, MPEG2→H.264) introduces artifacts that accumulate through the processing chain. Every transcoding step degrades signal. Professional broadcast chains minimize conversions and validate signal integrity at each conversion point.

**Interflux parallel:** Claude agents write structured findings in the Findings Index format defined in `phases/shared-contracts.md`. OpenRouter agents dispatched via Bash receive a prompt asking them to use the same format, but:

1. Different model families have different instruction-following strengths. DeepSeek R1 may add chain-of-thought before the findings index; Qwen 2.5 may use slightly different severity labels.
2. The findings format parsing in synthesis (which extracts severity, ID, section, title) may fail silently on format variants.
3. Section attribution (which part of the document a finding refers to) may differ in granularity between model families.

**Failure scenario:** DeepSeek V3 consistently uses `CRITICAL` instead of `P0` in its findings (reasonable — it has different training data). The findings parser misses these findings entirely (looking for `P0`). DeepSeek's perspective is silently excluded from synthesis. Model diversity (the stated insight quality goal) is negated by format incompatibility.

**Fix:** Normalize findings format in a post-processing step before synthesis ingestion. A 20-line parser that maps common severity label variants (`CRITICAL→P0`, `HIGH→P1`, `MEDIUM→P2`, `LOW→P3`) to the canonical format. Log normalization events for debugging. This is the broadcast equivalent of a standards converter — one dedicated conversion point, not silent absorption.

---

### P2 — BSR-04: Multi-Feed Aggregation Missing — No Cross-Provider Robustness

**Broadcast parallel:** Modern broadcast systems use multi-feed aggregation for critical content: satellite + fiber + IP feeds all carry the same signal. If any feed is clean, the output is clean. The feeds are continuously compared — divergence between feeds is a quality alert.

**Interflux parallel:** The input document identifies "model diversity as a signal" — disagreements between Claude and DeepSeek on the same finding are more meaningful than agreement between two Claude agents. This is the correct insight. But the current architecture doesn't have a mechanism to *compare* findings across model families — it has convergence scoring, but convergence treats all agents equally regardless of model family.

**What's missing:** Cross-family convergence bonus. When Claude and DeepSeek both flag the same finding independently, that's a qualitatively stronger signal than when two Claude agents converge. The current convergence scoring in `phases/synthesize.md` doesn't distinguish intra-family from inter-family agreement.

**Fix:** Add a `provider_family` field to each finding. In convergence scoring, weight cross-family agreement higher (e.g., 1.5x convergence score for findings where Claude + non-Claude both flag). This is a 5-line change to the convergence computation — but requires the `provider_family` field to be populated at dispatch time.

---

### P3 — BSR-05: Contribution vs Distribution Quality Tiers Undefined

**Broadcast parallel:** Broadcast engineers distinguish *contribution quality* (the feed going into the production chain — highest quality required) from *distribution quality* (the feed going to viewers — compressed, lossy acceptable). The same content travels at different quality levels to different destinations.

**Interflux parallel:** Agents write findings that enter synthesis (contribution quality requirement) and synthesis produces the user-facing report (distribution quality). Currently both steps use the same quality standard. But with heterogeneous model dispatch:

- **Synthesis input quality** needs to meet a minimum bar: parseable, structured, severity-calibrated. This is the contribution quality requirement.
- **User-facing output quality** is synthesis's job — it deduplicates, normalizes, and presents. This is distribution quality.

The design document doesn't articulate this distinction. As a result, the quality requirement for synthesis input is unspecified. Should cheap-model findings be held to the same quality bar as Claude findings before entering synthesis? The answer is yes — but this needs to be explicit.

**Fix (documentation only):** Add a "synthesis input contract" section to `phases/shared-contracts.md` that explicitly states minimum quality requirements for findings entering synthesis, regardless of source model. This is not a code change — it's a design clarification that prevents future ambiguity.

---

## Verdict

**needs-changes**

The broadcast engineering lens surfaces one P0 that the other agents missed: **quality degradation during normal operation** (as opposed to provider outage). A cheap model that's *up* but *shallow* produces findings that look complete but aren't — this is harder to detect than an outage and more insidious.

The core broadcast lesson for interflux: **the signal chain is only as reliable as its worst monitoring point**. Broadcast engineers put quality monitors at every conversion point in the chain. Interflux needs quality monitors at the OpenRouter response ingestion point — before findings enter synthesis, not after.

The multi-feed aggregation insight (cross-family convergence as a stronger signal than intra-family) is the most direct translation of broadcast engineering value to interflux's insight quality goal. It's a small implementation change with disproportionate insight quality impact.

<!-- flux-drive:complete -->
