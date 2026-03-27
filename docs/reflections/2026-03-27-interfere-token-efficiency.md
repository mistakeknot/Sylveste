---
title: "Reflection: interfere Token Efficiency Sprint"
date: 2026-03-27
bead: sylveste-86r
type: reflection
---

# Reflection: interfere Token Efficiency Sprint

## What went well

1. **Deep research on computer-use models paid off.** The Qwen3-VL-30B-A3B recommendation was clean — same MoE family as the text models, same memory footprint (18GB), full MLX support. The dual-model memory budget (text + vision = 36GB on 128GB) is comfortable, which changes the architecture story for future sprints.

2. **Review agents caught real bugs.** The fd-correctness agent found that `PriorityRequestQueue` was dead code and concurrent requests would interleave token streams. This wasn't hypothetical — it would have hit immediately when the bridge and Clavain B5 enforce mode ran simultaneously. The threading.Lock fix was simple but the diagnosis required understanding the Metal subprocess architecture.

3. **"Zero marginal cost" insight reshaped the model tier strategy.** Using the 35B MoE (3B active params) instead of the 9B for Haiku-tier tasks is a free upgrade — the MoE only activates 3B parameters so speed is comparable, but quality is dramatically better. This was the key brainstorm insight.

## What could improve

1. **Plan review found bridge placement wrong.** I initially put the playtest bridge inside `interverse/interfere/scripts/` which would have coupled the inference server to Shadow Work's API. Should have caught this during planning — interfere serves inference, the bridge is a consumer.

2. **Task 2 (interstat shadow cost logging) was deferred.** The plan assumed it was a small task but it requires a new SQLite table and interstat schema changes. Should have recognized this during planning and either scoped it properly or excluded it from the start.

3. **The 122B model for playtest was the initial plan, but memory analysis showed it wouldn't work with the game running.** The performance review caught this — 35B + 122B + game + macOS = too tight. Should have done the memory math earlier.

## Key learnings

- **MoE models change the cost calculus for local inference.** When active params are 3B but total params are 35B, you get big-model routing intelligence at small-model speed. The "zero marginal cost" framing makes tier upgrades obvious.
- **Always check if existing code is actually wired.** PromptCacheManager and PriorityRequestQueue were both fully implemented but never connected to the server. This is a pattern to watch for in research codebases where features get built and benchmarked but not integrated.
- **Bridge scripts belong at the consumer level, not the service level.** An inference server should not know about its consumers' API contracts. This is basic separation of concerns but easy to violate when moving fast.
