VERDICT: PASS
CRITERION: none
RECEIPT: receipt-c960366179

BEYOND THE GAUGE:
- **Mixed line endings are silently homogenised.** The decoder picks CRLF if any CRLF byte pair exists anywhere in the file and re-encodes every line that way, and a lone CR inside a line becomes a line break. A mostly-LF file with one stray CRLF is rewritten wholly CRLF, changing bytes outside the named old_string and new_string. That is the same class of defect the brief set out to fix; the constraint only covers pure-CRLF and pure-LF files, so the replay never sees it. Probe results:

| input bytes | output bytes |
|---|---|
| `a\n b\r\n c\n` | `a\r\n b\r\n c\r\n` |
| `x = 'a\rb'\n` | `x = 'a\nb'\n` |

- **Passing verify steps now embed stdout in the receipt.** Every ok verify step's `detail` gains the last 20 lines of fence output. Keys are unchanged and text mode prints only messages, so this satisfies the "receipt shape unchanged" constraint literally, but any consumer that parses `detail` will now see arbitrary fence output.
- **An escaped descendant can still hang the applier.** After the SIGKILL sweep, the final unbounded `communicate()` blocks until the stdout pipe closes. A fence child that left the process group (via `setsid` or a daemonising server) and kept the pipe open blocks forever. Pre-existing and outside the brief, not a regression.
- **Criterion 1a's literal fence cannot pass under the contract's own options.** With `bash -e`, `read` at end-of-file returns 1 and aborts before the echo. The test wraps the fence in `set +e` and `set -e`, which is the only way to satisfy both the criterion and constraint 1. I confirmed all four new tests fail against the pre-fix script, so they are genuine regressions despite the wrapper.
- **Fence `$0` semantics changed.** Fences now see a temp file path in the system temp directory as `$0` and `BASH_SOURCE` instead of `bash`. A fence that locates the repo with `dirname "$0"` would break. The brief mandates the file approach, so this is an expected consequence rather than a defect.

`★ Insight ─────────────────────────────────────`
The mixed-endings issue comes from a common shortcut: detecting a file-wide line-ending convention with a single membership test, then normalising everything to it. A byte-faithful edit needs to preserve each line's own terminator, which usually means splitting with `keepends=True` and re-joining, or restricting the replacement to the matched span and leaving the rest of the buffer untouched.
`─────────────────────────────────────────────────`
