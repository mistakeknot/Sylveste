//! Diagnostic HTTP server — run alongside your application.
//!
//! CUSTOMIZE:
//! 1. Replace AppState with your actual state type
//! 2. Pass your app's shared state to the server
//! 3. Gate behind #[cfg(debug_assertions)] or a feature flag
//!
//! Usage: Launch this server on a separate tokio task alongside your main app.

mod handlers;
mod state;

use hyper_util::rt::TokioIo;
use state::{AppState, SharedState, SimulationState, UiState};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use tokio::net::TcpListener;

/// Default diagnostic server port. CUSTOMIZE as needed.
const DIAG_PORT: u16 = 9876;

/// Start the diagnostic server. Call this from your app's main function.
///
/// ```rust
/// // In your app's main():
/// let state = Arc::new(Mutex::new(app_state));
/// tokio::spawn(start_diag_server(state.clone()));
/// ```
pub async fn start_diag_server(state: SharedState) {
    let addr = SocketAddr::from(([127, 0, 0, 1], DIAG_PORT));
    let listener = TcpListener::bind(addr).await.expect("Failed to bind diagnostic server");
    eprintln!("Diagnostic server listening on http://{addr}");

    loop {
        let (stream, _) = listener.accept().await.expect("Failed to accept connection");
        let state = state.clone();
        tokio::spawn(async move {
            let io = TokioIo::new(stream);
            let service = hyper::service::service_fn(move |req| {
                handlers::route(state.clone(), req)
            });
            if let Err(err) = hyper::server::conn::http1::Builder::new()
                .serve_connection(io, service)
                .await
            {
                eprintln!("Diagnostic server error: {err}");
            }
        });
    }
}

// Example: standalone server for testing the template
#[tokio::main]
async fn main() {
    // CUSTOMIZE: Replace with your actual app state
    let state: SharedState = Arc::new(Mutex::new(AppState {
        simulation: SimulationState {
            tick: 0,
            entity_count: 0,
            running: true,
        },
        ui: UiState {
            active_view: "dashboard".to_string(),
            panels: HashMap::new(),
            selections: HashMap::new(),
            modal: None,
        },
    }));

    start_diag_server(state).await;
}
