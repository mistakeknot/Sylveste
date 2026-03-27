---
artifact_type: reflection
bead: Sylveste-4b7
stage: reflect
---

# Reflection: Reservoir Routing MLP Autoresearch Campaign

## What went well

- **Plan review caught real bugs**: The 3-agent review (correctness, performance, quality) identified 5 critical issues before any code was written. Most impactful: `cache=[None]*N` would have crashed on Qwen3.5 production models, and missing `mx.eval()` barriers would have caused graph bleed into `stream_generate`. These would have been painful to debug at runtime.
- **Synthetic feature cluster center bug found during testing**: Train/test sets were getting different cluster centers (different seeds), causing the model to memorize training clusters but fail on test. Fixed by sharing centers between splits. The test caught this — the 90% accuracy threshold was the right choice over the original 60%.
- **Template-based training data generator is extensible**: The template pool approach produces diverse prompts without external LLM calls, making the autoresearch campaign fast to iterate.

## Key learnings

1. **MLX `make_prompt_cache()` is required for partial forward passes** — passing `None` cache entries works on some model families but crashes on others that dereference `cache.offset` unconditionally. Always use `make_prompt_cache()` for any standalone forward pass outside `stream_generate`.

2. **Synthetic feature generation must share cluster centers between train/test** — this is obvious in hindsight but easy to miss when `_generate_synthetic_features` takes a `seed` parameter that resets the entire RNG state including the center generation. The fix was to extract `_make_cluster_centers` as a separate step with a fixed seed.

3. **`nn.Module.save_weights`/`load_weights` already exist in MLX** — no need to write custom wrappers. The plan review caught this before implementation. Use a metadata sidecar (JSON) alongside the weights file for hyperparameter validation on load.

4. **Double-prefill overhead is acceptable for diagnostic hooks** — the partial forward pass adds ~37.5% to time-to-first-token, but for an autoresearch campaign measuring architecture quality, this is fine. The forward-hook approach (zero overhead) is a known follow-up for when routing becomes a pre-flight gate.

## Follow-ups

- Forward-hook hidden state extraction for zero-overhead routing (when routing becomes a pre-flight gate)
- Real-data evaluation: extract actual hidden states from production prompts to validate synthetic-to-real transfer
- Integrate with interlab campaign dispatch: `init_experiment` + mutation space encoding
