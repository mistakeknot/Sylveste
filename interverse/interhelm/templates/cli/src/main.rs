//! Diagnostic CLI client — thin wrapper around the diagnostic HTTP server.
//!
//! CUSTOMIZE: Rename the binary, add project-specific subcommands.
//!
//! Usage:
//!   app-diag health              # Show subsystem health
//!   app-diag ui                  # Show UI state
//!   app-diag diff [--steps N]    # Run state diff
//!   app-diag assert "<expr>"     # Evaluate assertion
//!   app-diag smoke-test          # Run smoke test
//!   app-diag watch [--interval]  # Poll health
//!   app-diag schema              # Show available endpoints

use clap::{Parser, Subcommand};
use colored::*;
use serde_json::Value;

/// CUSTOMIZE: Change the default port to match your diagnostic server.
const DEFAULT_BASE_URL: &str = "http://127.0.0.1:9876";

#[derive(Parser)]
#[command(name = "app-diag", about = "Diagnostic CLI for your application")]
struct Cli {
    /// Base URL of the diagnostic server
    #[arg(long, default_value = DEFAULT_BASE_URL)]
    url: String,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Show subsystem health status
    Health,
    /// Show semantic UI state
    Ui,
    /// Run state diff (snapshot before, step N, snapshot after)
    Diff {
        /// Number of steps to advance
        #[arg(default_value = "1")]
        steps: u64,
    },
    /// Evaluate an assertion expression against current state
    Assert {
        /// Expression to evaluate (e.g., "simulation.tick > 0")
        expression: String,
    },
    /// Run smoke test sequence
    SmokeTest,
    /// Poll health endpoint at interval
    Watch {
        /// Poll interval in seconds
        #[arg(long, default_value = "5")]
        interval: u64,
    },
    /// Show available endpoints
    Schema,
}

fn get(url: &str, path: &str) -> Result<Value, Box<dyn std::error::Error>> {
    let resp = reqwest::blocking::get(format!("{url}{path}"))?;
    Ok(resp.json()?)
}

fn post(url: &str, path: &str, body: Value) -> Result<Value, Box<dyn std::error::Error>> {
    let client = reqwest::blocking::Client::new();
    let resp = client.post(format!("{url}{path}")).json(&body).send()?;
    Ok(resp.json()?)
}

fn check_connectivity(url: &str) -> bool {
    reqwest::blocking::get(format!("{url}/diag/health")).is_ok()
}

fn print_health(data: &Value) {
    let status = data["status"].as_str().unwrap_or("unknown");
    let status_colored = match status {
        "healthy" => status.green().bold(),
        "degraded" => status.yellow().bold(),
        "unhealthy" => status.red().bold(),
        _ => status.dimmed(),
    };
    println!("Overall: {status_colored}");

    if let Some(subsystems) = data["subsystems"].as_object() {
        for (name, info) in subsystems {
            let sub_status = info["status"].as_str().unwrap_or("unknown");
            let sub_colored = match sub_status {
                "healthy" => "✓".green(),
                "degraded" => "⚠".yellow(),
                "unhealthy" => "✗".red(),
                _ => "?".dimmed(),
            };
            println!("  {sub_colored} {name}: {sub_status}");
            if let Some(details) = info["details"].as_object() {
                for (k, v) in details {
                    println!("      {k}: {v}");
                }
            }
        }
    }
}

fn print_smoke_test(data: &Value) {
    let passed = data["passed"].as_u64().unwrap_or(0);
    let failed = data["failed"].as_u64().unwrap_or(0);
    let total = data["total"].as_u64().unwrap_or(0);

    println!(
        "Smoke Test: {}/{} passed",
        if failed == 0 {
            passed.to_string().green().bold()
        } else {
            passed.to_string().yellow().bold()
        },
        total
    );

    if let Some(results) = data["results"].as_array() {
        for r in results {
            let name = r["name"].as_str().unwrap_or("?");
            let status = r["status"].as_str().unwrap_or("?");
            let ms = r["duration_ms"].as_u64().unwrap_or(0);
            let icon = if status == "pass" {
                "✓".green()
            } else {
                "✗".red()
            };
            print!("  {icon} {name} ({ms}ms)");
            if status != "pass" {
                if let Some(detail) = r["detail"].as_str() {
                    print!(" — {}", detail.red());
                }
            }
            println!();
        }
    }
}

fn main() {
    let cli = Cli::parse();

    if !check_connectivity(&cli.url) {
        eprintln!(
            "{} Cannot reach diagnostic server at {}",
            "Error:".red().bold(),
            cli.url
        );
        eprintln!("Is the application running with the diagnostic server enabled?");
        std::process::exit(1);
    }

    match cli.command {
        Commands::Health => match get(&cli.url, "/diag/health") {
            Ok(data) => print_health(&data),
            Err(e) => eprintln!("Error: {e}"),
        },
        Commands::Ui => match get(&cli.url, "/diag/ui/state") {
            Ok(data) => println!("{}", serde_json::to_string_pretty(&data).unwrap()),
            Err(e) => eprintln!("Error: {e}"),
        },
        Commands::Diff { steps } => {
            match post(&cli.url, "/diag/diff", serde_json::json!({"steps": steps})) {
                Ok(data) => println!("{}", serde_json::to_string_pretty(&data).unwrap()),
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        Commands::Assert { expression } => {
            match post(
                &cli.url,
                "/diag/assert",
                serde_json::json!({"expression": expression}),
            ) {
                Ok(data) => {
                    let result = data["result"].as_bool().unwrap_or(false);
                    if result {
                        println!("{} {}", "PASS".green().bold(), expression);
                    } else {
                        println!("{} {}", "FAIL".red().bold(), expression);
                    }
                    if let Some(values) = data["values"].as_object() {
                        for (k, v) in values {
                            println!("  {k} = {v}");
                        }
                    }
                }
                Err(e) => eprintln!("Error: {e}"),
            }
        }
        Commands::SmokeTest => match post(&cli.url, "/diag/smoke-test", serde_json::json!({})) {
            Ok(data) => print_smoke_test(&data),
            Err(e) => eprintln!("Error: {e}"),
        },
        Commands::Watch { interval } => {
            println!("Watching health every {interval}s (Ctrl+C to stop)...\n");
            loop {
                match get(&cli.url, "/diag/health") {
                    Ok(data) => {
                        print!("\x1B[2J\x1B[H"); // clear screen
                        print_health(&data);
                    }
                    Err(e) => eprintln!("Error: {e}"),
                }
                std::thread::sleep(std::time::Duration::from_secs(interval));
            }
        }
        Commands::Schema => match get(&cli.url, "/diag/schema") {
            Ok(data) => println!("{}", serde_json::to_string_pretty(&data).unwrap()),
            Err(e) => eprintln!("Error: {e}"),
        },
    }
}
