# Orphan Plan & PRD Triage — 2026-04-10

Triaged all plans and PRDs in `docs/plans/` and `docs/prds/` whose bead IDs no longer exist in the tracker (lost during DB reinits). Skipped `sylveste-5qv9` (already recreated) and bead-less plans (`bead: none`).

---

## (a) RECREATE — Still relevant, needs a new bead

| Old Bead | Plan/PRD Path | Summary | Priority |
|----------|---------------|---------|----------|
| sylveste-rsj.4 | docs/plans/2026-03-30-domain-general-north-star.md | CPVO + DWSQ domain-general north star metrics (metrics.yaml exists but no bead) | P2 |
| sylveste-rsj.5 | docs/plans/2026-03-30-qdaif-diversity-archive.md | Diverse Perspectives section in synthesis (partially wired but config exists) | P2 |
| sylveste-rsj.6 | docs/plans/2026-03-30-sycophancy-detection.md | Runtime sycophancy detection in synthesis (config exists, scoring in place) | P2 |
| sylveste-l2j | docs/plans/2026-03-31-q3-gguf-download-extract.md | Download Q3 GGUF for Qwen3.5-397B — model not yet on disk | P2 |
| sylveste-fzt | docs/plans/2026-04-06-ockham-f7-health-bypass.md | Ockham health JSON + Tier 3 BYPASS — health cmd exists, bypass logic not wired | P1 |
| sylveste-s3z6 | docs/plans/2026-04-07-fluxbench-closed-loop-model-discovery.md, docs/prds/2026-04-07-fluxbench-closed-loop-model-discovery.md | FluxBench scoring engine + qualification pipeline (thresholds config exists, no engine) | P1 |
| sylveste-uais | docs/plans/2026-04-07-progressive-discrimination-curriculum.md, docs/prds/2026-04-06-progressive-discrimination-curriculum.md | Auraken DQ progressive curriculum — no curriculum data or tracker yet | P1 |
| sylveste-jrua | docs/plans/2026-04-07-ecosystem-simplify-phase2.md, docs/prds/2026-04-07-ecosystem-simplify.md | Ecosystem simplification Phase 2 — Phase 1 shipped (8676c2bb) but Phase 2 items remain | P2 |
| sylveste-sttz.3 | docs/plans/2026-04-05-forge-f3-artifact-pipeline.md | Forge F3 artifact pipeline — forge.py has StressTestLog but no log/staging dirs | P2 |
| sylveste-fbz | docs/plans/2026-04-05-gmail-purchase-import.md, docs/prds/2026-04-05-gmail-purchase-import.md | Gmail purchase import pipeline — code exists in apps/Auraken but may need bead for remaining work | P2 |
| sylveste-9lp.9 | docs/plans/2026-04-05-cross-model-dispatch.md, docs/prds/2026-04-05-cross-model-dispatch.md | Cross-model dispatch scoring + integration — no agent-roles.yaml yet | P2 |
| Sylveste-e1mi | docs/plans/2026-03-19-attp-interweave.md | ATTP attestation protocol for interweave — interweave exists but no attp/merkle code | P3 |
| Sylveste-lta9 | docs/plans/2026-03-19-sprint-v2-artifact-bus.md, docs/prds/2026-03-19-sprint-v2-lifecycle-redesign.md | Sprint v2 artifact bus + progress trackers — sprint system still v1 | P3 |
| Sylveste-ysxe | docs/plans/2026-03-20-ai-factory-wave1-foundation.md, docs/prds/2026-03-20-ai-factory-orchestration.md | AI Factory Wave 1 foundation — partially started, needs tracking | P2 |
| Sylveste-ysxe.3 | docs/plans/2026-03-20-self-dispatch-loop.md | Self-dispatch loop for AI factory — not yet wired | P2 |
| Sylveste-1ifn | docs/plans/2026-03-21-interrank-hardware-aware-recommendations.md, docs/prds/2026-03-21-interrank-hardware-aware-recommendations.md | Hardware-aware model recommendations (VRAM, GPU) in interrank | P3 |
| Sylveste-jpum | docs/plans/2026-03-21-meadowsyn-experiments.md, docs/prds/2026-03-21-meadowsyn-experiments.md | Meadowsyn experiment suite — experiments dir exists, ongoing work | P2 |
| Sylveste-enxv | docs/plans/2026-03-23-v1-roadmap-artifact.md, docs/prds/2026-03-23-v1-roadmap-milestone-path.md | v1.0 roadmap artifact publishing — roadmap file exists but may need refresh | P3 |
| Sylveste-0pvp | docs/plans/2026-03-18-go-benchmark-optimization.md, docs/prds/2026-03-18-go-benchmark-optimization.md | Go benchmark-driven optimization for Skaffen hot paths | P3 |
| Sylveste-dxzr | docs/plans/2026-03-17-interlab-observability-audit.md, docs/prds/2026-03-17-interlab-observability-audit.md | Observability audit — masaq METRIC wrappers, Go benchmarks | P3 |
| Sylveste-7xm8 | docs/plans/2026-03-14-meta-improvement-campaigns.md, docs/prds/2026-03-14-meta-improvement-campaigns.md | Meta-improvement campaigns — mutation store MCP tools for interlab | P3 |
| Sylveste-vd1 | docs/plans/2026-03-16-mutation-engine.md | Mutation engine — mutation types in campaign YAML for interlab | P3 |

---

## (b) SHIPPED — Work already landed, historical record only

| Old Bead | Plan/PRD Path | Evidence |
|----------|---------------|----------|
| sylveste-pkx | docs/plans/2026-03-27-flux-gen-severity-calibration-plan.md, docs/plans/2026-03-27-flux-gen-severity-calibration-prd.md | 10 severity_calibration matches in generate-agents.py |
| sylveste-86r | docs/plans/2026-03-27-interfer-token-efficiency.md, docs/prds/2026-03-27-interfer-token-efficiency.md | Commit b7a0f351 — interfer local model routing + playtest bridge shipped |
| sylveste-rsj.1 | docs/plans/2026-03-28-autonomous-epic-p0.md | Commit 408ce55e — close sylveste-rsj.1 (11/11 children) |
| sylveste-d39 | docs/plans/2026-03-28-autonomous-flux-explore-plan.md, docs/plans/2026-03-28-autonomous-flux-explore-prd.md | flux-explore command exists at interverse/interflux/commands/flux-explore.md |
| sylveste-2sr | docs/plans/2026-03-28-prometheus-metrics-plan.md, docs/plans/2026-03-28-prometheus-metrics-prd.md | interverse/interfer/server/prom.py exists, prometheus in pyproject.toml |
| sylveste-dui | docs/plans/2026-03-29-flux-gen-short-title-fix.md | Commit 12e9f247 — close sylveste-dui, fix at 847068a |
| sylveste-rsj.2 | docs/plans/2026-03-29-interflux-reaction-round.md | Commit 4c112f0f — close sylveste-rsj.2, reaction round shipped |
| sylveste-b49 | docs/plans/2026-03-29-reflect-compound-durable-changes.md, docs/prds/2026-03-29-reflect-compound-durable-changes.md | Compound autonomy guard shipped (26 matches in fleet-registry.yaml) |
| sylveste-feu | docs/plans/2026-03-29-severity-calibration-validation-plan.md, docs/prds/2026-03-29-severity-calibration-validation.md | Severity calibration validation completed (v5 agents generated) |
| sylveste-rsj.1.8 | docs/plans/2026-03-30-compound-autonomy-guard.md, docs/prds/2026-03-30-compound-autonomy-guard.md | capability_level in fleet-registry.yaml (26 matches), compound_autonomy in default-policy |
| sylveste-rsj.7 | docs/plans/2026-03-31-composable-discourse-protocols.md, docs/prds/2026-03-31-composable-discourse-protocols.md | discourse-topology.yaml + discourse-fixative.yaml exist |
| sylveste-rsj.9 | docs/plans/2026-03-31-discourse-fixative.md, docs/prds/2026-03-31-discourse-fixative.md | discourse-fixative.yaml exists |
| sylveste-rsj.12 | docs/plans/2026-03-31-hearsay-rule.md | hearsay detection in synthesize-review.md (2 matches) |
| sylveste-rsj.11 | docs/plans/2026-03-31-sparse-communication-topology.md, docs/prds/2026-03-31-sparse-communication-topology.md | discourse-topology.yaml with sparse topology config (2 matches) |
| sylveste-rsj.10 | docs/plans/2026-03-31-stemma-hallucination-tracing.md | stemma fields in synthesize-review.md (2 matches) |
| sylveste-g3b | docs/plans/2026-04-01-interflux-reaction-round-activation.md, docs/prds/2026-04-01-interflux-reaction-round-activation.md | Commit 67919052 — close sylveste-g3b |
| sylveste-18a.1 | docs/plans/2026-04-01-skaffen-tool-concurrency.md, docs/prds/2026-04-01-skaffen-tool-concurrency.md | ConcurrencyClass in os/Skaffen/internal/tool/tool.go |
| sylveste-8em | docs/plans/2026-04-03-ockham-vision.md, docs/prds/2026-04-03-ockham-vision.md, docs/prds/2026-04-04-ockham-wave1-foundation.md | os/Ockham/docs/vision.md exists, cmd + internal packages built |
| sylveste-0zr | docs/plans/2026-04-04-ockham-f1-f2-intent-scoring.md | os/Ockham/cmd/ockham/intent.go + internal/scoring/ exist |
| sylveste-32p | docs/plans/2026-04-04-ockham-f4-check-hook.md | os/Ockham/cmd/ockham/check.go + internal/signals/ exist |
| sylveste-18a.9 | docs/plans/2026-04-04-post-compact-context-restoration.md | PostCompactHook in os/Skaffen/internal/agentloop/autocompact.go (7 matches) |
| sylveste-sttz | docs/plans/2026-04-05-auraken-forge-mode.md | apps/Auraken/src/auraken/forge.py + docs/designs/forge-mode.md exist |
| sylveste-ape | docs/plans/2026-04-05-interweave-f1-type-families.md | interverse/interweave/src/interweave/families.py exists |
| sylveste-qo8 | docs/plans/2026-04-06-interweave-f3-connector-protocol.md | Connectors dir with beads.py, cass.py, tldr_code.py exist |
| iv-6ixw | docs/plans/2026-03-04-c5-self-building-loop.md, docs/prds/2026-03-04-c5-self-building-loop.md | sprint-compose/lib-compose.sh exists (27 matches) |
| iv-mtf12 | docs/plans/2026-03-05-data-driven-plugin-boundaries.md, docs/prds/2026-03-05-data-driven-plugin-boundaries.md | os/Clavain/config/tool-composition.yaml exists |
| iv-nh3d7 | docs/plans/2026-03-05-f4-consumer-wiring.md, docs/prds/2026-03-05-f4-consumer-wiring.md | os/Clavain/scripts/lib-compose.sh exists (27 matches) |
| iv-ojik9 | docs/plans/2026-03-05-intent-contract.md, docs/prds/2026-03-05-intent-contract.md | core/intercore/pkg/contract/ has intent.go, errors.go, intent_test.go |
| iv-fo0rx | docs/plans/2026-03-06-canonical-landed-change-entity.md | core/intercore/internal/landed/store.go + store_test.go exist |
| iv-godia | docs/plans/2026-03-06-routing-decisions-kernel-facts.md | core/intercore/internal/routing/decision.go exists |
| iv-30zy3 | docs/plans/2026-03-06-session-attribution-ledger.md | core/intercore/internal/session/store.go + store_test.go exist |
| iv-ey5wb | docs/plans/2026-03-06-vision-roadmap-alignment.md, docs/prds/2026-03-06-vision-roadmap-alignment.md | Commit 6cf4d7ed — core document audit, roadmap restructure |
| iv-f7gsz | docs/plans/2026-03-07-canary-cohort-scoping.md | stage: done in frontmatter, commit 9b4c5977 |
| iv-2s7k7 | docs/plans/2026-03-07-codex-first-routing-activation.md, docs/prds/2026-03-07-codex-first-routing-activation.md | Commit d821e9a6 — close iv-2s7k7 (already shipped) |
| iv-5ztam | docs/plans/2026-03-17-interspect-cross-project-overlays.md, docs/plans/2026-03-17-interspect-effectiveness.md, docs/prds/2026-03-17-interspect-cross-project-and-overlays.md, docs/prds/2026-03-17-interspect-effectiveness.md | interspect effectiveness command + cross-project overlays (105 matches in lib-interspect.sh) |
| Sylveste-7xs | docs/plans/2026-03-07-converge-interknow-compound-docs.md, docs/prds/2026-03-07-converge-interknow-compound-docs.md | CUJs exist as first-class artifacts in docs/cujs/ |
| Sylveste-ttf | docs/plans/2026-03-08-plans-as-prompts.md, docs/prds/2026-03-08-plans-as-prompts.md | os/Clavain/skills/executing-plans/ SKILL.md exists |
| Sylveste-csq | docs/plans/2026-03-09-diagnostic-maturation.md, docs/prds/2026-03-09-diagnostic-maturation.md | interverse/interhelm/skills/diagnostic-maturation/SKILL.md exists |
| Sylveste-ekh | docs/plans/2026-03-09-interhelm.md, docs/prds/2026-03-09-interhelm.md | interverse/interhelm/ exists with agents, hooks, skills |
| Sylveste-4wm | docs/plans/2026-03-10-conversation-resumption.md, docs/prds/2026-03-10-conversation-resumption.md | Post-compact context restoration in Skaffen autocompact.go |
| Sylveste-qsw | docs/plans/2026-03-11-priompt.md, docs/prds/2026-03-11-priompt.md | masaq/priompt/priompt.go + priompt_test.go exist |
| Sylveste-4hu | docs/plans/2026-03-11-skaffen-f1-provider.md | os/Skaffen/internal/provider/anthropic/ exists |
| Sylveste-hop | docs/plans/2026-03-11-skaffen-f2-tools.md | os/Skaffen/internal/tool/ exists with builtin tools |
| Sylveste-xe0 | docs/plans/2026-03-11-skaffen-f3-oodarc.md | os/Skaffen/internal/agent/agent.go exists |
| Sylveste-0pj | docs/plans/2026-03-11-skaffen-f4-model-routing.md, docs/prds/2026-03-11-skaffen-f4-model-routing.md | Skaffen model routing implemented |
| Sylveste-4xp | docs/prds/2026-03-11-skaffen-f4-model-routing.md | (PRD for same feature, see above) |
| Sylveste-2ic | docs/plans/2026-03-11-skaffen-f5-session.md | os/Skaffen/internal/session/ exists |
| Sylveste-c4c | docs/plans/2026-03-11-skaffen-f7-cli.md | os/Skaffen/cmd/skaffen/ exists |
| Sylveste-o5u | docs/plans/2026-03-11-skaffen-f7-mcp-client.md, docs/prds/2026-03-11-skaffen-f7-mcp-client.md | os/Skaffen/internal/mcp/ with client.go, config.go, tests |
| Sylveste-f18 | docs/plans/2026-03-11-skaffen-f8-tui-masaq.md | os/Skaffen/internal/tui/ fully built, masaq/ library exists |
| Sylveste-j2f | docs/plans/2026-03-11-skaffen-f9-intercore-bridge.md, docs/prds/2026-03-11-skaffen-f9-intercore-bridge.md | intercore integration in agent.go (2 matches) |
| Sylveste-92j | docs/prds/2026-03-11-skaffen-go-rewrite.md | Master PRD — Skaffen Go rewrite fully shipped at os/Skaffen/ |
| Sylveste-fqb | docs/plans/2026-03-12-interrank-power-up.md, docs/prds/2026-03-12-interrank-power-up.md | interverse/interrank/ exists with recommend_model tool |
| Sylveste-6qb.8 | docs/plans/2026-03-12-skaffen-agentloop-separation.md, docs/prds/2026-03-12-skaffen-agentloop-separation.md | os/Skaffen/internal/agentloop/ exists separately from agent |
| Sylveste-6qb | docs/plans/2026-03-12-skaffen-at-file-mentions.md | TUI file mention support in chat.go |
| Sylveste-s9jd | docs/plans/2026-03-12-skaffen-history-and-keyboard-help.md | os/Skaffen/internal/tui/history.go exists (20 history matches) |
| Sylveste-6i0.2 | docs/plans/2026-03-12-skaffen-hook-system.md, docs/prds/2026-03-12-skaffen-hook-system.md | os/Skaffen/internal/hooks/ with executor.go, loader_test.go |
| Sylveste-p23 | docs/plans/2026-03-12-skaffen-scoped-session.md | Session isolation in os/Skaffen/internal/session/ |
| Sylveste-6i0.19 | docs/plans/2026-03-12-skaffen-skills-system.md, docs/prds/2026-03-12-skaffen-skills-system.md | os/Skaffen/internal/skill/ with inject.go, pin.go, etc. |
| Sylveste-6i0.18 | docs/plans/2026-03-12-skaffen-subagent-system.md, docs/prds/2026-03-12-skaffen-subagent-system.md | os/Skaffen/internal/subagent/ with emitter.go, markdown.go |
| Sylveste-g3a | docs/plans/2026-03-13-interspect-calibration-pipeline.md, docs/prds/2026-03-13-interspect-calibration-pipeline.md | interspect calibrate command + tests exist |
| Sylveste-6i0.10 | docs/plans/2026-03-13-skaffen-sandbox.md, docs/prds/2026-03-13-skaffen-sandbox.md | os/Skaffen/internal/sandbox/ with bwrap.go, policy.go, tests |
| Sylveste-ome7 | docs/plans/2026-03-14-intermix-matrix-eval.md, docs/plans/2026-03-14-skaffen-stress-test.md, docs/prds/2026-03-14-skaffen-cross-repo-stress-test.md | interverse/intermix/ exists with campaigns, cmd |
| Sylveste-g4ja | docs/plans/2026-03-14-override-consumption.md | Override consumption in interspect + lib-routing.sh |
| Sylveste-6i0.12 | docs/plans/2026-03-14-skaffen-image-support.md | os/Skaffen/internal/provider/image_test.go + tui/image.go exist |
| projects-z6k | docs/plans/2026-03-13-interlab.md, docs/plans/2026-03-15-autoresearch-skaffen.md | interverse/interlab/ + os/Skaffen/internal/experiment/ both exist |
| Sylveste-4nl | docs/plans/2026-03-16-autarch-masaq-adoption.md | Autarch masaq integration exists |
| Sylveste-6qb.7 | docs/plans/2026-03-16-interverse-plugin-compat.md, docs/prds/2026-03-16-interverse-plugin-compat.md | Skaffen interverse plugin compatibility layer |
| Sylveste-6i0.17 | docs/plans/2026-03-16-repomap-pagerank.md, docs/prds/2026-03-16-repomap-pagerank.md | os/Skaffen/internal/repomap/ with element.go, extract.go |
| Sylveste-6i0 | docs/plans/2026-03-17-competitive-gaps-final.md, docs/prds/2026-03-17-competitive-gaps-final.md | Sidebar panel (sidebar_test.go) in Skaffen TUI |
| Sylveste-z5qg | docs/plans/2026-03-23-interflux-pipeline-optimization.md, docs/prds/2026-03-23-interflux-pipeline-optimization.md | stage: completed, commit 095374a4 — close epic + 16 children |
| Sylveste-0rgc | docs/plans/2026-03-24-gate-calibration.md, docs/prds/2026-03-24-gate-calibration.md | Commit c586e91c — close gate calibration epic |
| Sylveste-uboy | docs/plans/2026-03-24-interflux-pipeline-hardening.md | Commit 5d4fb609 — close uboy epic (10/10) |
| Sylveste-uboy.6 | docs/plans/2026-03-24-validate-speculative-expansion.md | Commit cfcd8393 — close uboy.6 |
| Sylveste-uboy.4 | docs/plans/2026-03-25-inotifywait-agent-completion.md | Part of uboy epic closure (5d4fb609) |
| Sylveste-py89 | docs/plans/2026-03-26-bd-doctor-auto-block.md | Commit 24de6680 — close py89 |
| Sylveste-og7m.2.1 | docs/plans/2026-03-26-event-envelope-v2.md | Commit 166f0e6d — close og7m.2.1 EventEnvelope v2 |
| Sylveste-og7m | docs/plans/2026-03-26-monorepo-consolidation-batch2.md, -batch3.md, -batch4.md, docs/prds/2026-03-24-monorepo-consolidation-batch2.md, -batch3.md, -batch4.md | Commits 994d2c89, 79733d4c — batch closures |
| Sylveste-4b7 | docs/plans/2026-03-26-reservoir-routing-autoresearch.md, docs/prds/2026-03-26-reservoir-routing-autoresearch.md | Commit 48d593a8 — close 4b7 |
| Sylveste-uboy.2 | docs/plans/2026-03-26-token-counting-from-jsonl.md | Commit c8a65c36 — close uboy.2 |
| Sylveste-ef08 | docs/plans/2026-03-22-ideagui-data-pipe.md, docs/prds/2026-03-22-ideagui-data-pipe.md | Commit 1c34c59f — IdeaGUI data pipe shipped |
| Sylveste-r24y | docs/plans/2026-03-22-split-flap-board.md | apps/Meadowsyn/experiments/split-flap/ exists with full Next.js app |
| Sylveste-p83z | docs/plans/2026-03-24-f9-sse-data-pipe.md | Commit 9a847060 — close p83z, SSE data pipe shipped |
| Sylveste-bncp | docs/plans/2026-03-21-interlore.md, docs/prds/2026-03-21-interlore.md | interverse/interlore/ exists with scan, review, status commands |
| Sylveste-xk68 | docs/plans/2026-03-20-khouri-domain-model.md, docs/prds/2026-03-20-khouri-domain-model.md | apps/Khouri/src/khouri/models.py exists with CLA layer provenance |
| Sylveste-0ztn | docs/plans/2026-03-22-sprint-flow-improvements.md, docs/prds/2026-03-22-sprint-flow-improvements.md | Commit e36f7311 — sprint flow improvements shipped |
| iv-4iy6g | docs/prds/2026-02-28-intertrace.md | interverse/intertrace/ exists with agents, AGENTS.md |
| iv-nnxzo | docs/prds/2026-03-07-memory-architecture-convergence.md | Commit 39fdb0dd — architecture convergence doc shipped |
| iv-g36hy | docs/prds/2026-03-09-cxdb-sprint-recording.md | os/Clavain/cmd/clavain-cli/cxdb.go exists (97 matches) |

---

## (c) OBSOLETE — Superseded, renamed, or deferred

| Old Bead | Plan/PRD Path | Reason |
|----------|---------------|--------|
| Sylveste-rp5 | docs/plans/2026-03-10-skaffen-v01-fork.md, docs/prds/2026-03-10-skaffen-v01-fork.md | Superseded by Skaffen Go clean-room rewrite (Sylveste-92j); Rust fork approach abandoned |
| Sylveste-a4c | docs/plans/2026-03-15-delta-sharing-interlock.md | Delta sharing via interlock — interlock coordination exists but delta sharing not pursued |
| Sylveste-opc | docs/plans/2026-03-15-multi-plugin-autoresearch.md | Multi-plugin autoresearch — interlab campaigns supersede this approach |
| iv-wie5i | docs/plans/2026-03-05-discovery-os-integration.md, docs/prds/2026-03-05-discovery-os-integration.md | Discovery OS integration — interject discovery path never wired to ic; superseded by direct bead creation |
| iv-zsio | docs/plans/2026-03-05-discovery-sprint-presentation.md, docs/prds/2026-03-05-discovery-sprint-presentation.md | Discovery sprint presentation — route.md doesn't have review_discovery; interject integration path changed |
| iv-t712t | docs/plans/2026-03-06-first-stranger-experience.md, docs/prds/2026-03-06-first-stranger-experience.md | First-stranger experience — README rewrites happened but under different approach |
| iv-w7bh | docs/plans/2026-03-09-intermap-v02-hardening.md, docs/prds/2026-03-09-intermap-v02-hardening.md | Intermap v0.2 hardening — intermap rewritten, old hardening plan no longer applies |
| none (plans) | docs/plans/2026-03-05-cujs-first-class-artifacts.md | CUJs shipped but bead was always `none` — no orphan to recreate |
| none (plans) | docs/plans/2026-03-08-cass-deep-integration.md | CASS integration shipped but bead was always `none` |
| none (plans) | docs/plans/2026-03-12-mycroft-fleet-orchestrator-v01.md | Mycroft never built — os/Mycroft doesn't exist; concept may have merged into Ockham/Clavain |
| none (plans) | docs/plans/2026-03-12-web-search-v2-improvements.md | Follow-on to shipped feature, bead: none |
| none (plans) | docs/plans/2026-03-23-interblog.md, docs/plans/2026-03-24-interblog-v2.md | interblog never built; no plugin directory exists |
| none (plans) | docs/plans/2026-03-26-interfer-local-inference.md | bead was `none` (Dolt down at time); interfer local inference partially built via other beads |

---

## Summary

| Category | Count |
|----------|-------|
| RECREATE | 22 |
| SHIPPED | 82 (plans) + 34 (PRDs) |
| OBSOLETE | 13 |

**Key findings:**
- The vast majority of orphaned plans (>70%) are for work that actually shipped. The beads were closed in the old tracker but lost during DB reinits.
- The Skaffen Go rewrite epic alone accounts for ~25 shipped orphans (Sylveste-6i0.* and Sylveste-6qb.* children).
- 22 plans still need new beads — mostly P2/P3 items. The P1 items (FluxBench, progressive discrimination curriculum, Ockham F7 health bypass) should be prioritized.
- Plans with `bead: none` were never tracked and don't need recreation.
