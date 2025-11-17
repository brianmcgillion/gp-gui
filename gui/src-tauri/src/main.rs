//! GlobalProtect VPN GUI - Main Application Entry Point
//!
//! This is the main entry point for the gp-gui Tauri application.
//! It initializes the application, sets up signal handlers for graceful cleanup,
//! and configures the Tauri runtime with all necessary plugins and command handlers.
//!
//! # Architecture
//!
//! - Uses Tauri for the desktop application framework
//! - Manages VPN connections via the `gpclient` binary
//! - Provides a React-based UI for user interaction
//! - Handles root privilege requirements for VPN operations
//!
//! # Signal Handling
//!
//! The application registers cleanup handlers for SIGINT and SIGTERM to ensure
//! the VPN connection is properly terminated and lock files are removed when
//! the application exits.

// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod config;
mod gpclient_wrapper;

use log::{info, warn};
use std::sync::Arc;

/// Main application entry point.
///
/// Initializes logging, creates the global VPN state, registers cleanup handlers,
/// and starts the Tauri application runtime.
///
/// # Panics
///
/// Panics if:
/// - The Ctrl-C handler cannot be registered
/// - The Tauri application fails to initialize or run
#[cfg_attr(mobile, tauri::mobile_entry_point)]
fn main() {
    env_logger::init();
    info!("Starting GlobalProtect VPN GUI");

    let gpclient_state = Arc::new(gpclient_wrapper::GpclientState::new());
    let cleanup_state = gpclient_state.clone();

    // Register cleanup handler for SIGINT, SIGTERM, etc.
    ctrlc::set_handler(move || {
        warn!("Received termination signal, cleaning up gpclient...");
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let mut process = cleanup_state.process.lock().await;
            if let Err(e) = process.disconnect() {
                warn!("Error during cleanup: {}", e);
            }
        });
        info!("Cleanup complete, exiting");
        std::process::exit(0);
    })
    .expect("Error setting Ctrl-C handler");

    tauri::Builder::default()
        .manage(gpclient_state)
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            gpclient_wrapper::connect_gpclient,
            gpclient_wrapper::disconnect_gpclient,
            gpclient_wrapper::gpclient_status,
            gpclient_wrapper::check_running_as_root,
            config::load_user_config,
            config::save_user_config,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
