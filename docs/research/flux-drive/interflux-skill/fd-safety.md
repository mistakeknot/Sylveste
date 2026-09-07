### Findings Index
- P0 | S1 | "phases/reaction.md Step 2.5.3 / phases/shared-contracts.md Retrieved Content Trust Boundary" | Trust boundary sanitizer is incomplete against Unicode tag-spoofing and shellcode encoding
- P1 | S2 | "phases/launch.md Step 2.2-challenger" | openrouter-dispatch MCP dispatches arbitrary models with `prompt_content_policy: full_document` including proprietary content — no logging of what was sent
- P1 | S3 | "phases/synthesize.md compounding agent" | Compounding agent writes to interknow/config/knowledge with attacker-controllable finding text, sanitization is prose-specified
- P1 | S4 | "phases/launch.md Step 2.1d / progressive-enhancements.md Step 2.1d" | Overlay loading's 500-token cap is per agent — 5 agents × 500 tokens = 2500 tokens of untrusted content injected per review with no central budget
- P1 | S5 | "phases/launch-codex.md" | `CLAVAIN_DISPATCH_PROFILE=clavain bash "$DISPATCH"` passes AGENT_IDENTITY (full system prompt) through shell; system prompt is trimmed but file contents are not sanitized beyond trim
- P2 | S6 | "phases/reaction.md Step 2.5.4" | Reaction prompts quote peer findings verbatim; even after Step 2.5.3 sanitization, unicode homoglyphs of instruction keywords pass through
- P2 | S7 | "phases/synthesize.md Step 3.2 / Lorenzen config injection" | `python3 -c "import yaml, json; ..."` with yaml.safe_load of a project-controllable config — hostile repo shipping a billion-laughs YAML can hang the subprocess
- P2 | S8 | "phases/launch.md Step 2.0 + shared-contracts Retrieved Content Trust Boundary" | Retrieved Content policy applies to content inside prompts, but not to file paths agents Read — an agent told to Read `/tmp/flux-drive-*` has no boundary check
- P2 | S9 | "phases/reaction.md trust boundary / phases/shared-contracts.md" | Sanitization strips lines containing instruction-override keywords — matches false positives in legitimate findings discussing "ignore errors"
- P2 | S10 | "references/progressive-enhancements.md Step 2.1e + phases/launch.md Step 2.1e" | Trust multiplier math applies intertrust scores but doesn't authenticate where the score came from
Verdict: needs-changes

### Summary

The skill has explicit trust-boundary thinking in `shared-contracts.md` (Retrieved Content Trust Boundary) and implements sanitization in `phases/reaction.md` Step 2.5.3. That's more than most skills do. But the boundary is porous: unicode look-alike attacks bypass the keyword filter; yaml.safe_load on untrusted project configs has known DoS vectors; the openrouter-dispatch shadow path sends full_document content to arbitrary OpenRouter models without an audit trail; and compounding writes knowledge entries whose sanitization is a prose checklist rather than a tested function. The biggest practical risk is the combination of (a) flux-gen-created agents with author-supplied prompts and (b) reaction-round peer findings being injected into subsequent dispatches — a hostile flux-gen agent can write crafted findings that bypass sanitizer and steer peer agents.

### Issues Found

1. S1. P0: Sanitization bypass via Unicode and encoding. `phases/reaction.md` Step 2.5.3 strips:
   - XML-style tags: `<system>`, `<human>`, etc. (ASCII only)
   - Lines matching override-keywords (case-insensitive grep semantics)
   - Embedded code fences with `bash|sh|zsh` language tags
   
   Bypasses: (a) zero-width space inside the tag; (b) fullwidth Latin letters (U+FF21..U+FF3A); (c) Python code fences not in the blocklist; (d) base64-encoded payload wrapped in a plain markdown list; (e) HTML-entity encoded angle brackets. The trust boundary is declared in `shared-contracts.md` as covering peer findings, knowledge context, domain injection, and overlays — and all of them share this sanitizer, meaning this bypass amplifies across the pipeline. Fix: use a canonical Unicode normalization (NFKC) before matching, expand the language-tag blocklist to include python, ruby, perl, javascript, node, powershell, ps1, cmd, and strip entity-decoded angle brackets. A small set of fuzz cases covering the above bypasses should be added.

2. S2. P1: Challenger shadow sends full_document to arbitrary models. `phases/launch.md` Step 2.2-challenger dispatches via `openrouter-dispatch` MCP with three content policies: `fixtures_only`, `sanitized_diff`, `full_document`. `full_document` sends the review content to an OpenRouter model — ANY model in the registry, including external commercial providers. There's no default redaction of secrets within the full document, and no audit trail of what content left the local session. For a user reviewing a diff that contains `.env` contents or API keys, this is an exfiltration vector. Fix: when `prompt_content_policy: full_document` is used, require explicit user consent (auto-proceed default violates least-privilege) and log the exact bytes sent to `{OUTPUT_DIR}/challenger-sent.log` for audit.

3. S3. P1: Compounding writes untrusted content to knowledge base. `phases/synthesize.md` "Post-Synthesis: Silent Compounding" (L513-594) launches a background Task that writes markdown files to `{PROJECT_ROOT}/interverse/interknow/config/knowledge/`. The content comes from agent findings — including flux-gen agents whose prompts are author-controllable. The prose "Sanitization Rules" list is not backed by a function, and the agent is instructed to "sanitize before writing" — an LLM is not a reliable sanitizer. A hostile finding could embed a prompt-injection payload that future reviews' agents will read as Knowledge Context. Fix: route all knowledge writes through a dedicated script that runs the same reaction-round sanitizer (plus the fixes from S1) and rejects entries that still contain prompt-injection signatures.

4. S4. P1: Overlay token budget is per-agent, not per-review. `progressive-enhancements.md` Step 2.1d L53-56: "Budget: `_interspect_count_overlay_tokens "$content"` — cap 500 tokens per agent". For a 5-agent review, 2500 tokens of overlay content (untrusted-by-contract per Retrieved Content Trust Boundary) enter the dispatch plane. No central cap. If an attacker compromises the overlays directory, they can smuggle 2.5K tokens of injection into every review. Fix: add a per-review cap (e.g., 1000 tokens total across all agents) and deny when exceeded.

5. S5. P1: AGENT_IDENTITY prompt trimming scope is incomplete. `phases/launch-codex.md` L82: "Prompt trimming for `AGENT_IDENTITY` uses the shared contract in `phases/shared-contracts.md`." `shared-contracts.md` L86-94 defines prompt trimming: strip `<example>` blocks, Output Format sections, style/personality sections. But Codex receives the full file content via `$FLUX_TMPDIR/{agent-name}.md` as a `--prompt-file`. If an fd-safety agent's markdown contains nested commentary within example blocks and the trimmer uses a non-greedy regex, content can leak. The current contract doesn't specify regex, just "strip example blocks (including nested commentary)". Fix: provide a reference implementation script `scripts/trim-prompt.py` that all dispatchers use, rather than in-line trimming.

6. S6. P2: Unicode homoglyph slip-through. Related to S1 but more targeted: ASCII case-insensitive matching will miss Cyrillic-alike or fullwidth variants of override keywords. Fix as part of S1 (NFKC normalization).

7. S7. P2: Lorenzen config YAML DoS. `phases/synthesize.md` Step 3.2 L77-86 shells out to Python with `yaml.safe_load(open(...))`. PyYAML's safe_load is safe against arbitrary object construction, but a YAML file with deeply-nested anchors (billion-laughs pattern) can still cause exponential memory. Fix: add a size check before the Python invocation, or wrap with `timeout 10`.

8. S8. P2: Trust boundary not applied to Read-tool paths. `shared-contracts.md` Retrieved Content Trust Boundary lists: knowledge context, domain injection, research findings, overlays. It doesn't mention per-agent temp files (`/tmp/flux-drive-*`) which are written by the orchestrator. That's correct for trust (the orchestrator is trusted), but the boundary doesn't extend to Read paths that agents receive in their prompts. An agent whose prompt says "Read `/tmp/flux-drive-...`" will Read whatever that path contains — and if the orchestrator is compromised or misconfigured (wrong TS variable), the agent can Read arbitrary filesystem content. Fix: have the orchestrator only permit Reads under a canonical `/tmp/flux-drive-${TS}/` subdirectory, and sanity-check the path is under that prefix before building the prompt.

9. S9. P2: Sanitizer false positives on legitimate findings. The line-level filter deletes content matching override-keywords as substrings. A legitimate finding like "This error handler will silently skip downstream errors" contains such a keyword and would be stripped. That distorts peer findings and the reaction-round discussion. Fix: use word-boundary regex and anchor on instruction context, not substring match. Better: replace the pattern with explicit "NEW INSTRUCTIONS:" anchored matches, or "(IGNORE|OVERRIDE) (PREVIOUS|ABOVE)" patterns.

10. S10. P2: Trust multiplier has no provenance. `progressive-enhancements.md` Step 2.1e L63-78 sources `lib-trust.sh` from intertrust plugin cache and applies `_trust_scores_batch "$PROJECT"`. The trust score can upweight or downweight any agent's score. There's no signature or integrity check — whatever the DB returns is trusted. If a malicious plugin ships a compromised `lib-trust.sh`, it can force-promote any agent or demote fd-safety to be deferred. Fix: pin `lib-trust.sh` by sha256 in a reference config, or at least warn when the script's hash has changed since last run.

### Improvements

1. IMP-1. Publish a threat model as `config/flux-drive/threat-model.md`. Existing trust-boundary prose scatters across 4+ files. A single diagram with source to sink mappings for each untrusted channel (peer findings, knowledge, domain profiles, overlays, Oracle output, research agent output, openrouter-dispatch responses) would make gaps visible.

2. IMP-2. Add a sanitizer reference impl at `scripts/sanitize-untrusted.py` with a fuzz test suite at `tests/sanitizer_fuzz.py`. The 5-or-so declared sanitization patterns deserve tests; the LLM-subagent "sanitize and write" pattern is not a reliable substitute.

3. IMP-3. Default `prompt_content_policy: fixtures_only` for openrouter-dispatch. Require opt-in for `sanitized_diff` and `full_document`, with per-invocation logging. The current Step 2.2-challenger picks the policy based on the registry entry — which is untrusted config.

4. IMP-4. When flux-gen-created agents are dispatched, compute a hash of the agent .md file and log it with each invocation. Makes post-hoc forensics possible when a crafted agent causes bad findings.

5. IMP-5. Consider moving compounding writes to a two-phase review: the compounding agent proposes entries to a staging directory, and a separate human-gated promotion command moves them to the active knowledge directory. This matches the "Irreversible actions — always ask" doctrine in the project's CLAUDE.md.

<!-- flux-drive:complete -->
