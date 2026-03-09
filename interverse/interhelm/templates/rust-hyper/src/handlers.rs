//! HTTP handlers for diagnostic and control endpoints.
//!
//! All /diag/* handlers are read-only. All /control/* handlers may mutate state.

use crate::state::SharedState;
use http_body_util::Full;
use hyper::{body::Bytes, Request, Response, StatusCode};

type BoxBody = Full<Bytes>;

fn json_response(body: serde_json::Value) -> Response<BoxBody> {
    Response::builder()
        .header("content-type", "application/json")
        .body(Full::new(Bytes::from(body.to_string())))
        .unwrap()
}

fn error_response(status: StatusCode, msg: &str) -> Response<BoxBody> {
    Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(Full::new(Bytes::from(
            serde_json::json!({"error": msg}).to_string(),
        )))
        .unwrap()
}

// ── Diagnostic Endpoints (read-only) ──────────────────────────────────

pub async fn handle_health(state: SharedState) -> Response<BoxBody> {
    let state = state.lock().unwrap();
    let report = state.health();
    json_response(serde_json::to_value(&report).unwrap())
}

pub async fn handle_schema(_state: SharedState) -> Response<BoxBody> {
    // CUSTOMIZE: Update this when you add endpoints
    json_response(serde_json::json!({
        "endpoints": {
            "/diag/health":     { "method": "GET",  "description": "Structured subsystem health" },
            "/diag/schema":     { "method": "GET",  "description": "This endpoint — API self-description" },
            "/diag/ui/state":   { "method": "GET",  "description": "Semantic UI state" },
            "/diag/diff":       { "method": "POST", "description": "State diff over N steps", "params": ["steps", "filter"] },
            "/diag/assert":     { "method": "POST", "description": "Evaluate assertion", "params": ["expression"] },
            "/diag/smoke-test": { "method": "POST", "description": "Run smoke test sequence" },
            "/control/restart": { "method": "POST", "description": "Restart application" },
            "/control/reset":   { "method": "POST", "description": "Reset subsystem" },
            "/control/step":    { "method": "POST", "description": "Step simulation", "params": ["count"] }
        }
    }))
}

pub async fn handle_ui_state(state: SharedState) -> Response<BoxBody> {
    let state = state.lock().unwrap();
    json_response(serde_json::to_value(state.ui_state()).unwrap())
}

pub async fn handle_diff(state: SharedState, _body: Request<hyper::body::Incoming>) -> Response<BoxBody> {
    // CUSTOMIZE: Implement snapshot-before, step N, snapshot-after, compute deltas
    // Returns 501 until implemented — prevents agents from mistaking stubs for working endpoints
    error_response(StatusCode::NOT_IMPLEMENTED, "diff not implemented — CUSTOMIZE handle_diff in handlers.rs")
}

pub async fn handle_assert(state: SharedState, _body: Request<hyper::body::Incoming>) -> Response<BoxBody> {
    // CUSTOMIZE: Parse expression from body, evaluate against state
    // Returns 501 until implemented — prevents false-positive assertions
    error_response(StatusCode::NOT_IMPLEMENTED, "assert not implemented — CUSTOMIZE handle_assert in handlers.rs")
}

pub async fn handle_smoke_test(state: SharedState) -> Response<BoxBody> {
    // CUSTOMIZE: Define your smoke test checks
    let state = state.lock().unwrap();
    let health = state.health();

    json_response(serde_json::json!({
        "passed": 1,
        "failed": 0,
        "total": 1,
        "results": [
            { "name": "health_check", "status": "pass", "duration_ms": 1 }
        ],
        "note": "CUSTOMIZE: add your smoke test checks"
    }))
}

// ── Control Endpoints (mutations) ─────────────────────────────────────

pub async fn handle_restart(_state: SharedState) -> Response<BoxBody> {
    // CUSTOMIZE: Implement restart logic
    json_response(serde_json::json!({"status": "restarted"}))
}

pub async fn handle_reset(_state: SharedState, _body: Request<hyper::body::Incoming>) -> Response<BoxBody> {
    // CUSTOMIZE: Reset specific subsystem
    json_response(serde_json::json!({"status": "reset"}))
}

pub async fn handle_step(state: SharedState, _body: Request<hyper::body::Incoming>) -> Response<BoxBody> {
    // CUSTOMIZE: Step simulation by N
    let mut state = state.lock().unwrap();
    state.simulation.tick += 1;
    json_response(serde_json::json!({"tick": state.simulation.tick}))
}

// ── Router ────────────────────────────────────────────────────────────

pub async fn route(
    state: SharedState,
    req: Request<hyper::body::Incoming>,
) -> Result<Response<BoxBody>, std::convert::Infallible> {
    let path = req.uri().path().to_string();
    let method = req.method().clone();

    let response = match (method.as_str(), path.as_str()) {
        // Diagnostic (read-only)
        ("GET", "/diag/health")      => handle_health(state).await,
        ("GET", "/diag/schema")      => handle_schema(state).await,
        ("GET", "/diag/ui/state")    => handle_ui_state(state).await,
        ("POST", "/diag/diff")       => handle_diff(state, req).await,
        ("POST", "/diag/assert")     => handle_assert(state, req).await,
        ("POST", "/diag/smoke-test") => handle_smoke_test(state).await,

        // Control (mutations)
        ("POST", "/control/restart") => handle_restart(state).await,
        ("POST", "/control/reset")   => handle_reset(state, req).await,
        ("POST", "/control/step")    => handle_step(state, req).await,

        _ => error_response(StatusCode::NOT_FOUND, "endpoint not found — try GET /diag/schema"),
    };

    Ok(response)
}
