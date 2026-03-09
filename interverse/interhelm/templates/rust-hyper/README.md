# Rust/Hyper Diagnostic Server Template

Skeleton for a diagnostic HTTP server using hyper 1.x.

## Quick Start

1. Copy this directory into your project: `cp -r templates/rust-hyper/ your-project/tools/diag-server/`
2. Customize `src/state.rs` with your app's actual state types
3. Customize handlers in `src/handlers.rs`
4. Launch the server alongside your app (see `src/main.rs` for the pattern)

## Customization Points

Every file has `CUSTOMIZE:` comments marking where to adapt to your app.

### state.rs
- Replace `AppState` fields with your subsystem states
- Implement `health()` with real subsystem checks
- Add your state types with `#[derive(Clone, Serialize, Deserialize)]`

### handlers.rs
- Implement `handle_diff` with real snapshot/delta logic
- Implement `handle_assert` with an expression evaluator
- Add smoke test checks in `handle_smoke_test`
- Add control handlers for your app's specific actions

### main.rs
- Change `DIAG_PORT` if needed
- Gate with `#[cfg(debug_assertions)]` for dev-only
- Pass your app's actual `SharedState`

## Endpoints

| Endpoint | Method | Type |
|----------|--------|------|
| `/diag/health` | GET | Diagnostic |
| `/diag/schema` | GET | Diagnostic |
| `/diag/ui/state` | GET | Diagnostic |
| `/diag/diff` | POST | Diagnostic |
| `/diag/assert` | POST | Diagnostic |
| `/diag/smoke-test` | POST | Diagnostic |
| `/control/restart` | POST | Control |
| `/control/reset` | POST | Control |
| `/control/step` | POST | Control |
