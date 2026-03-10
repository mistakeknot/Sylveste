//! Application state types for the diagnostic server.
//!
//! CUSTOMIZE: Replace these placeholder types with your app's actual state.
//! The diagnostic server reads from this state to report health, diffs, and UI.

use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};

/// Shared application state — wrap your app's state in this struct.
/// The Arc<Mutex<>> pattern ensures thread-safe access from the diagnostic server.
///
/// CUSTOMIZE: Add your subsystem states here.
pub type SharedState = Arc<Mutex<AppState>>;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppState {
    // CUSTOMIZE: Add your subsystem states
    pub simulation: SimulationState,
    pub ui: UiState,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationState {
    pub tick: u64,
    pub entity_count: usize,
    pub running: bool,
    // CUSTOMIZE: Add your simulation fields
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UiState {
    pub active_view: String,
    pub panels: std::collections::HashMap<String, PanelState>,
    pub selections: std::collections::HashMap<String, serde_json::Value>,
    pub modal: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PanelState {
    pub visible: bool,
    pub content: Option<String>,
    pub selected_tab: Option<String>,
}

/// Health status for a subsystem.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum HealthStatus {
    Healthy,
    Degraded,
    Unhealthy,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubsystemHealth {
    pub status: HealthStatus,
    pub details: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthReport {
    pub status: HealthStatus,
    pub subsystems: std::collections::HashMap<String, SubsystemHealth>,
    pub timestamp: String,
}

impl AppState {
    /// CUSTOMIZE: Implement health checks for each subsystem.
    pub fn health(&self) -> HealthReport {
        let mut subsystems = std::collections::HashMap::new();

        // CUSTOMIZE: Add health checks per subsystem
        subsystems.insert(
            "simulation".to_string(),
            SubsystemHealth {
                status: if self.simulation.running {
                    HealthStatus::Healthy
                } else {
                    HealthStatus::Degraded
                },
                details: serde_json::json!({
                    "tick": self.simulation.tick,
                    "entities": self.simulation.entity_count,
                }),
            },
        );

        let overall = if subsystems.values().all(|s| matches!(s.status, HealthStatus::Healthy)) {
            HealthStatus::Healthy
        } else {
            HealthStatus::Degraded
        };

        HealthReport {
            status: overall,
            subsystems,
            // CUSTOMIZE: use chrono::Utc::now().to_rfc3339() for ISO 8601 timestamps
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs().to_string())
                .unwrap_or_else(|_| "0".to_string()),
        }
    }

    /// CUSTOMIZE: Return the semantic UI state.
    pub fn ui_state(&self) -> &UiState {
        &self.ui
    }
}
