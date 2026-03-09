# Diagnostic CLI Client Template

Thin CLI wrapper for the diagnostic HTTP server.

## Quick Start

1. Copy into your project: `cp -r templates/cli/ your-project/tools/app-diag/`
2. Rename the binary in `Cargo.toml`
3. Update `DEFAULT_BASE_URL` if your server uses a different port
4. Build: `cargo build --release`

## Commands

```
app-diag health              # Formatted health table
app-diag ui                  # JSON UI state
app-diag diff [--steps N]    # State diff
app-diag assert "<expr>"     # Assertion with PASS/FAIL
app-diag smoke-test          # Smoke test sequence
app-diag watch [--interval]  # Poll health
app-diag schema              # Available endpoints
```

## Customization

- Add project-specific subcommands as `Commands` variants
- Customize formatters for your state types
- Add `--format json|table|compact` output modes
