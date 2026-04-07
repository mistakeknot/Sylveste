### Findings Index
- P0 | PP-1 | "Constraints" | Findings Index format compliance will fail on DeepSeek R1 — reasoning models produce chain-of-thought preamble before structured output, breaking first-line parsing
- P1 | PP-2 | "Current Architecture" | XML tag handling differs across model families — Claude treats XML tags as semantic structure, DeepSeek/Qwen treat them as literal text
- P1 | PP-3 | "Constraints" | System prompt vs user prompt split — OpenRouter models have inconsistent system prompt support, some ignore system messages entirely
- P2 | PP-4 | "Question" | Refusal surface differs — Chinese models refuse geopolitical content, Claude refuses harm content; security review agents may hit unexpected refusals
- P2 | PP-5 | "Current Architecture" | Persona instruction fidelity degrades on cheaper models — agent identity becomes flavor text rather than behavioral constraint
Verdict: risky

### Summary

The current prompt template (`references/prompt-template.md`) was designed for Claude and relies on multiple Claude-specific behaviors that will break silently on other model families. The three critical failures are: (1) DeepSeek R1's reasoning traces appearing before structured output, breaking Findings Index first-line parsing in Step 3.1; (2) XML tags used throughout interflux prompts (`<example>`, `<commentary>`, semantic delimiters) being treated as literal strings rather than structural markers by non-Claude models; (3) inconsistent system prompt handling causing review instructions to be deprioritized or ignored. These are not theoretical — they are well-documented behaviors of these model families that will cause synthesis failures on first deployment.

### Issues Found

PP-1. **P0: DeepSeek R1 reasoning trace breaks Findings Index parsing.** DeepSeek R1 (the reasoning model variant) produces a `<think>...</think>` reasoning trace before its response content. The interflux synthesis validation in Step 3.1 checks "first non-empty line starts with `### Findings Index`". If the response starts with a reasoning trace (which can be thousands of tokens), the parser classifies the output as "Malformed" and falls back to prose-based reading — losing structured finding data. DeepSeek V3 (the non-reasoning variant) does not have this issue, but OpenRouter routing may substitute R1 for V3 during capacity constraints unless the model ID is pinned exactly.

**Concrete scenario:** Orchestrator dispatches fd-perception to `deepseek/deepseek-r1` via OpenRouter. The response begins with 2000 tokens of reasoning trace wrapped in `<think>` tags, followed by a correctly-formatted Findings Index. Step 3.1 validation fails on the first line, classifies as malformed, and falls back to prose reading — losing all structured finding data including severity ratings. Synthesis proceeds with degraded data quality.

**Smallest fix:** For OpenRouter dispatch, strip `<think>...</think>` blocks from the response before writing to `.md.partial`. Pin model IDs exactly (e.g., `deepseek/deepseek-chat` for V3, never `deepseek/deepseek-reasoner` for R1) in the provider config to avoid unintended reasoning model substitution.

PP-2. **P1: XML tag semantics differ across model families.** Interflux prompts use XML-style tags for structure: `<example>`, `<commentary>`, the prompt trimming rules strip `<example>...</example>` blocks. Claude treats these as semantic delimiters that influence attention and context windowing. DeepSeek and Qwen models treat XML tags as literal text strings — they have no special handling. This means: (a) `<example>` blocks won't be understood as examples to emulate, (b) XML delimiters in peer findings won't create clean separation, (c) the sanitization in Step 2.5.3 that strips `<system>` tags assumes models respect these as boundaries, which non-Claude models don't.

**Smallest fix:** For non-Claude dispatch, convert XML-style delimiters to markdown equivalents. `<example>` → `**Example:**`, `<commentary>` → `*Commentary:*`, structural delimiters → markdown headers or horizontal rules. This is a prompt variant, not a prompt rewrite — maintain a `prompt_format: claude | generic` flag per dispatch.

PP-3. **P1: System prompt handling is inconsistent.** OpenRouter passes system messages through to models, but models handle them differently. Some Qwen variants deprioritize system messages relative to user messages. Some DeepSeek variants concatenate system and user into a single context without role separation. The interflux prompt template puts the output format instructions and review task in what becomes the user message, but project context and agent persona are in what would be the system message. If the system message is deprioritized, agents lose their persona and project grounding.

**Smallest fix:** For OpenRouter dispatch, concatenate system + user messages into a single user message with clear markdown delimiters. This sacrifices Claude's system prompt optimization but ensures consistent behavior across all models. The prompt template already has all necessary sections — they just need to be flattened.

PP-4. **P2: Refusal surface differs by model family.** Claude's refusal training focuses on harmful content generation, violence, and illegal activities. Chinese model families (DeepSeek, Qwen, Yi) have additional refusal surfaces around geopolitical content, some government/military references, and certain IP-sensitive patterns. An fd-safety agent reviewing code that handles government data or contains geopolitical references might get unexpected refusals from a Chinese model — producing an error stub instead of findings. This is particularly relevant for the safety review agent, which by definition examines sensitive code patterns.

PP-5. **P2: Persona instruction fidelity.** The agent system prompts define specific personas ("You are a Flux-drive Systems Thinking Reviewer") with detailed behavioral constraints. Claude follows persona instructions with high fidelity, treating them as behavioral constraints that shape analysis depth and focus. Cheaper models tend to treat persona sections as flavor text — producing generic analysis regardless of persona. The domain-specific review criteria injected in Step 2.1a (from `config/flux-drive/domains/`) may be ignored entirely, reducing agent output to generic code review rather than lens-specific analysis.

### Improvements

PP-I1. Create a `prompt_variants/` directory with per-model-family prompt templates. The core content stays the same; only formatting (XML → markdown), message structure (system+user → user-only), and explicit format examples (few-shot for non-Claude) differ.

PP-I2. Add a format validation step between OpenRouter response receipt and `.md.partial` write: check for reasoning traces, strip them, validate Findings Index format, retry once with a more explicit format instruction if validation fails.

PP-I3. Build an empirical test matrix: run the 5 cheapest OpenRouter models against 3 reference documents with known findings, score format compliance and finding recall. This provides the calibration data to decide which models are viable for which agent types.

--- VERDICT ---
STATUS: fail
FILES: 0 changed
FINDINGS: 5 (P0: 1, P1: 2, P2: 2)
SUMMARY: The prompt template will break on non-Claude models in three specific ways: reasoning trace preambles break Findings Index parsing (P0), XML semantic tags lose their meaning (P1), and system prompt deprioritization drops agent personas (P1). Per-model-family prompt variants and response validation are prerequisites for any OpenRouter dispatch.
---
<!-- flux-drive:complete -->
