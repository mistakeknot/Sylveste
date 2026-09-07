# Challenger (DeepSeek V3) — shadow review

**Model**: `deepseek/deepseek-chat-v3` via openrouter-dispatch MCP (v0.2.59 challenger track)
**Prompt budget**: ~4000 input tokens (summary-only, no full file content)
**Latency**: 320ms
**Verdict**: Shadow reference only. Not merged into synthesis.

The challenger produced 9 findings. After cross-checking against actual file contents, the challenger:

- **2 findings cited plausible line numbers but the code at those lines does not contain the described issue**. Example: ID-02 claims "drift.sh uses bc for float comparison" — bc is not used anywhere in fluxbench-drift.sh (Python handles the math). Example: ID-05 cites discover-models.sh:56 claiming a VALID_SLUG regex, but line 56 is a yq call and VALID_SLUG lives in discover-merge.sh:30.
- **3 findings are true but already covered** by primary reviewers or Phase 1 findings.
- **2 findings are plausible new directions** worth flagging: ID-01 (Hungarian algorithm cardinality assertion) and ID-06 (empty name segments in `_infer_domains`). Both are P3 at most.

Raw output preserved below for audit.

---

## Raw challenger findings

- **P1** | ID-01 | "fluxbench-score.sh:123" — Hungarian algorithm implementation assumes bijection but doesn't validate input cardinality, risking silent failure on asymmetric matrices. Add assertion or error handling for mismatched row/column counts.
- **P2** | ID-02 | "fluxbench-drift.sh:87" — Drift detection uses `bc` for float comparison with '-1 < 0' fallback, which may mask unintended comparisons against negative values. Refactor to explicit float comparison with error handling. **[incorrect — bc is not used in drift.sh]**
- **P1** | ID-03 | "fluxbench-qualify.sh:412" — Model registry flock only protects the YAML write but not the preceding directory creation, risking race conditions. Move flock earlier to include directory ops. **[partially correct — flock should include mkdir, but line 412 is response-file reading, not flock setup]**
- **P2** | ID-04 | "findings-helper.sh:89" — Awk key extraction assumes section:title format but doesn't escape colons in titles, potentially causing key collisions. Add regex escaping for colons in titles. **[related but overlaps with COR-08 from fd-correctness]**
- **P1** | ID-05 | "discover-models.sh:56" — VALID_SLUG regex allows trailing dashes, which could create invalid MCP queries. Update regex to `^[a-z0-9]+(-[a-z0-9]+)*$`. **[wrong file — VALID_SLUG is in discover-merge.sh]**
- **P2** | ID-06 | "flux-agent.py:312" — Domain inference from name uses split('-') but doesn't handle empty segments after split, potentially inferring incorrect domains. Add validation for empty segments. **[wrong line — actual _infer_domains is at line 194–224; a leading 'fd-' followed by '-something' would produce empty segments; worth checking]**
- **P1** | ID-07 | "token-count.py:42" — Fallback to chars/4 assumes 4 chars per token, which may underestimate usage for non-English text. Add language-specific tokenization logic. **[outside scope — 4 chars/token is a widely-accepted heuristic]**
- **P2** | ID-08 | "flux-watch.sh:67" — Polling fallback uses fixed 5s delay, potentially missing quick bursts of agent completions. Consider exponential backoff with a ceiling. **[covered by PER-04]**
- **P1** | ID-09 | "update-domain-profiles.py:127" — AGENT_ENRICHMENTS dict keys aren't validated against safe character set, risking path traversal in YAML output. Add key sanitization before edit. **[keys are hardcoded strings — no untrusted input at line 127]**

## Conclusion

Shadow review is consistent with the v0.2.59 challenger framework's documented behavior: provides external-model perspective without affecting the review verdict. The low precision of the findings (about 2/9 usefully new) reflects the summary-only prompt budget, not model capability.
