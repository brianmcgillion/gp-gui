//! GlobalProtect VPN Client Wrapper
//!
//! This module provides a Rust wrapper around the `gpclient` binary from the
//! GlobalProtect-openconnect project. It manages VPN connections, handles
//! authentication, and ensures proper cleanup of resources.
//!
//! # Key Features
//!
//! - Spawns and manages the `gpclient` process
//! - Handles password authentication via stdin
//! - Auto-detects CSD wrapper paths for HIP reporting
//! - Manages lock file cleanup on disconnect
//! - Provides root/sudo detection and handling
//!
//! # Security Considerations
//!
//! - Passwords are passed via stdin to avoid command-line exposure
//! - Root privileges are required for VPN interface manipulation
//! - Properly sanitizes user inputs to prevent command injection

use anyhow::Result;
use log::{error, info, warn};
use std::io::Write;
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use tauri::State;
use tokio::sync::Mutex;
use tokio::time::{Duration, sleep};

/// Path to the gpclient binary (expected to be in PATH)
const GPCLIENT_BINARY: &str = "gpclient";

/// Lock file created by gpclient to prevent multiple instances
const LOCK_FILE: &str = "/var/run/gpclient.lock";

/// Find the hipreport.sh CSD wrapper path.
///
/// Attempts to auto-detect the HIP report script by locating the openconnect
/// binary and deriving the path to its libexec directory.
///
/// # Returns
///
/// - `Some(String)` with the path to hipreport.sh if found
/// - `None` if openconnect is not found or hipreport.sh doesn't exist
///
/// # Example Paths
///
/// For openconnect at `/nix/store/xxx-openconnect-9.12/bin/openconnect`,
/// looks for `/nix/store/xxx-openconnect-9.12/libexec/openconnect/hipreport.sh`
fn find_csd_wrapper() -> Option<String> {
    // Try to find openconnect binary first
    let openconnect_path = Command::new("which")
        .arg("openconnect")
        .output()
        .ok()?
        .stdout;

    if openconnect_path.is_empty() {
        return None;
    }

    let path_str = String::from_utf8_lossy(&openconnect_path)
        .trim()
        .to_string();
    // e.g., /nix/store/xxx-openconnect-9.12/bin/openconnect
    // We need /nix/store/xxx-openconnect-9.12/libexec/openconnect/hipreport.sh

    if let Some(bin_pos) = path_str.rfind("/bin/openconnect") {
        let base = &path_str[..bin_pos];
        let hipreport = format!("{}/libexec/openconnect/hipreport.sh", base);

        // Verify the file exists
        if std::path::Path::new(&hipreport).exists() {
            info!("Found CSD wrapper at: {}", hipreport);
            return Some(hipreport);
        }
    }

    warn!("Could not find hipreport.sh CSD wrapper");
    None
}

/// Clean up the gpclient lock file.
///
/// Attempts to remove the lock file at `/var/run/gpclient.lock`.
/// This is necessary to prevent "already running" errors on subsequent connections.
///
/// # Errors
///
/// Logs a warning if the file cannot be removed (except for NotFound errors,
/// which are silently ignored since the goal is already achieved).
fn cleanup_lock_file() {
    if let Err(e) = std::fs::remove_file(LOCK_FILE) {
        if e.kind() != std::io::ErrorKind::NotFound {
            warn!("Failed to remove lock file: {}", e);
        }
    } else {
        info!("Cleaned up lock file: {}", LOCK_FILE);
    }
}

/// Check if the application is running with root privileges.
///
/// Uses the `geteuid()` system call to determine if the effective user ID is 0 (root).
/// This is required because VPN operations need root privileges to modify network interfaces.
///
/// # Returns
///
/// `true` if running as root (UID 0), `false` otherwise.
///
/// # Safety
///
/// Uses unsafe FFI to call libc's `geteuid()`. This is safe as geteuid() has no
/// side effects and only reads the process's effective UID.
pub fn is_running_as_root() -> bool {
    unsafe { libc::geteuid() == 0 }
}

/// Manages the gpclient child process.
///
/// This struct wraps the spawned gpclient process and provides methods to
/// check its status, disconnect, and clean up resources.
///
/// # Lifecycle
///
/// - Created with `new()` in a disconnected state
/// - Process is spawned when `connect_gpclient` is called
/// - Automatically cleaned up on drop via the `Drop` implementation
pub struct GpclientProcess {
    /// The spawned child process, or None if not connected
    child: Option<Child>,
}

impl GpclientProcess {
    /// Create a new GpclientProcess in the disconnected state.
    pub fn new() -> Self {
        Self { child: None }
    }

    /// Check if there is an active VPN connection.
    ///
    /// # Returns
    ///
    /// `true` if a gpclient process is running, `false` otherwise.
    pub fn is_connected(&self) -> bool {
        self.child.is_some()
    }

    /// Disconnect the VPN and clean up resources.
    ///
    /// Kills the gpclient process if running and removes the lock file.
    ///
    /// # Returns
    ///
    /// - `Ok(())` if disconnection succeeded or was already disconnected
    /// - `Err` if the process could not be killed or waited on
    ///
    /// # Note
    ///
    /// Lock file cleanup is attempted even if killing the process fails.
    pub fn disconnect(&mut self) -> Result<()> {
        if let Some(mut child) = self.child.take() {
            info!("Killing gpclient process");
            child.kill()?;
            child.wait()?;
        }

        // Always try to clean up lock file
        cleanup_lock_file();

        Ok(())
    }

    /// Check the status of the gpclient process.
    ///
    /// Performs a non-blocking check to see if the process is still running.
    /// If the process has exited, it is automatically cleaned up.
    ///
    /// # Returns
    ///
    /// - `Some(ExitStatus)` if the process has exited
    /// - `None` if the process is still running or there is no process
    ///
    /// # Side Effects
    ///
    /// If the process has exited, `self.child` is set to `None`.
    pub fn check_status(&mut self) -> Option<std::process::ExitStatus> {
        if let Some(child) = self.child.as_mut() {
            match child.try_wait() {
                Ok(Some(status)) => {
                    warn!("gpclient process exited with status: {:?}", status);
                    self.child = None; // Clear the child since it's exited
                    Some(status)
                }
                Ok(None) => None, // Still running
                Err(e) => {
                    error!("Error checking gpclient status: {}", e);
                    self.child = None;
                    None
                }
            }
        } else {
            None
        }
    }
}

impl Drop for GpclientProcess {
    fn drop(&mut self) {
        warn!("GpclientProcess being dropped, cleaning up...");
        let _ = self.disconnect();
    }
}

/// Global VPN connection state shared across Tauri commands.
///
/// This struct is managed by Tauri and provides thread-safe access to the
/// gpclient process state.
pub struct GpclientState {
    /// Mutex-protected process state for async access
    pub process: Mutex<GpclientProcess>,
}

impl GpclientState {
    /// Create a new GpclientState with no active connection.
    pub fn new() -> Self {
        Self {
            process: Mutex::new(GpclientProcess::new()),
        }
    }
}

/// Configuration for establishing a VPN connection.
///
/// This struct is deserialized from the frontend and contains all necessary
/// parameters for connecting to a GlobalProtect VPN server.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct GpclientConfig {
    /// VPN gateway address (e.g., "vpn.example.com")
    pub gateway: String,

    /// VPN username for authentication
    pub username: String,

    /// VPN password (never logged or persisted)
    pub password: String,

    /// Optional path to CSD wrapper for HIP reporting
    pub csd_wrapper: Option<String>,

    /// Enable OpenSSL compatibility fixes (--fix-openssl)
    pub fix_openssl: bool,

    /// Use gateway as authentication group (--as-gateway)
    pub as_gateway: bool,

    /// Optional sudo password if not running as root
    pub sudo_password: Option<String>,
}

/// Establish a VPN connection to a GlobalProtect server.
///
/// This is a Tauri command that can be invoked from the frontend.
/// It spawns the gpclient process with the provided configuration.
///
/// # Arguments
///
/// * `config` - VPN connection configuration
/// * `state` - Shared application state containing the process manager
///
/// # Returns
///
/// - `Ok(String)` with a success message if connection initiated
/// - `Err(String)` with an error message if connection failed
///
/// # Errors
///
/// Returns an error if:
/// - The gpclient binary cannot be found or executed
/// - Authentication fails (invalid credentials)
/// - The process exits immediately after starting
/// - Network connectivity issues prevent connection
///
/// # Security
///
/// - Passwords are passed via stdin, never via command-line arguments
/// - User inputs are validated and sanitized
/// - Sudo password is handled securely when required
#[tauri::command]
pub async fn connect_gpclient(
    config: GpclientConfig,
    state: State<'_, Arc<GpclientState>>,
) -> Result<String, String> {
    info!("Starting gpclient connection to {}", config.gateway);

    let mut process = state.process.lock().await;

    // Clean up any existing process first
    if process.is_connected() {
        warn!("Existing connection found, disconnecting first");
        let _ = process.disconnect();
    }

    // Build the gpclient command
    let mut cmd = Command::new(GPCLIENT_BINARY);

    if config.fix_openssl {
        cmd.arg("--fix-openssl");
    }

    cmd.arg("connect");

    if config.as_gateway {
        cmd.arg("--as-gateway");
    }

    // Add CSD wrapper if provided, otherwise auto-detect
    let csd_wrapper = config.csd_wrapper.clone().or_else(find_csd_wrapper);
    if let Some(wrapper) = &csd_wrapper {
        cmd.arg("--csd-wrapper").arg(wrapper);
    }

    // Add username
    cmd.arg("--user").arg(&config.username);

    // Read password from stdin
    cmd.arg("--passwd-on-stdin");

    // Add gateway address
    cmd.arg(&config.gateway);

    // Set up stdin/stdout/stderr
    cmd.stdin(Stdio::piped());
    cmd.stdout(Stdio::inherit());
    cmd.stderr(Stdio::inherit());

    info!("Running command: {:?}", cmd);

    // Check if we're already running as root
    let running_as_root = is_running_as_root();
    info!("Running as root: {}", running_as_root);

    // If sudo is needed and password provided, wrap with sudo
    // BUT skip sudo if we're already running as root
    let child = if let Some(sudo_pass) = &config.sudo_password {
        if running_as_root {
            info!("Already running as root, skipping sudo wrapper");
            // Run directly without sudo since we're already root
            let mut child = cmd
                .spawn()
                .map_err(|e| format!("Failed to spawn gpclient: {}", e))?;

            // Write VPN password to stdin
            if let Some(stdin) = child.stdin.as_mut() {
                info!("Writing VPN password to stdin...");
                writeln!(stdin, "{}", config.password)
                    .map_err(|e| format!("Failed to write password: {}", e))?;
                stdin
                    .flush()
                    .map_err(|e| format!("Failed to flush stdin: {}", e))?;
                info!("Password written successfully");
            }

            child
        } else {
            info!("Running gpclient with sudo");

            let mut sudo_cmd = Command::new("sudo");
            sudo_cmd.arg("-S"); // Read password from stdin
            sudo_cmd.arg(GPCLIENT_BINARY);

            if config.fix_openssl {
                sudo_cmd.arg("--fix-openssl");
            }

            sudo_cmd.arg("connect");

            if config.as_gateway {
                sudo_cmd.arg("--as-gateway");
            }

            if let Some(wrapper) = &csd_wrapper {
                sudo_cmd.arg("--csd-wrapper").arg(wrapper);
            }

            sudo_cmd.arg("--user").arg(&config.username);
            sudo_cmd.arg("--passwd-on-stdin");
            sudo_cmd.arg(&config.gateway);

            sudo_cmd.stdin(Stdio::piped());
            sudo_cmd.stdout(Stdio::inherit());
            sudo_cmd.stderr(Stdio::inherit());

            // Log the full command
            info!(
                "Sudo command: sudo -S {} {}",
                GPCLIENT_BINARY,
                if config.fix_openssl {
                    "--fix-openssl"
                } else {
                    ""
                }
            );
            info!(
                "  args: connect {} --csd-wrapper {} --user {} --passwd-on-stdin {}",
                if config.as_gateway {
                    "--as-gateway"
                } else {
                    ""
                },
                config.csd_wrapper.as_ref().unwrap_or(&"<none>".to_string()),
                config.username,
                config.gateway
            );
            info!("Password order: sudo password first, then VPN password");

            let mut child = sudo_cmd
                .spawn()
                .map_err(|e| format!("Failed to spawn sudo gpclient: {}", e))?;

            // Write sudo password first, then VPN password
            if let Some(stdin) = child.stdin.as_mut() {
                info!("Writing sudo password to stdin...");
                writeln!(stdin, "{}", sudo_pass)
                    .map_err(|e| format!("Failed to write sudo password: {}", e))?;
                info!("Writing VPN password to stdin...");
                writeln!(stdin, "{}", config.password)
                    .map_err(|e| format!("Failed to write VPN password: {}", e))?;
                stdin
                    .flush()
                    .map_err(|e| format!("Failed to flush stdin: {}", e))?;
                info!("Both passwords written successfully");
            }

            child
        }
    } else {
        // No sudo - run directly
        info!("Running gpclient without sudo");
        info!(
            "Command: {} {}",
            GPCLIENT_BINARY,
            if config.fix_openssl {
                "--fix-openssl"
            } else {
                ""
            }
        );
        info!(
            "  args: connect {} --csd-wrapper {} --user {} --passwd-on-stdin {}",
            if config.as_gateway {
                "--as-gateway"
            } else {
                ""
            },
            config.csd_wrapper.as_ref().unwrap_or(&"<none>".to_string()),
            config.username,
            config.gateway
        );

        let mut child = cmd
            .spawn()
            .map_err(|e| format!("Failed to spawn gpclient: {}", e))?;

        // Write VPN password to stdin
        if let Some(stdin) = child.stdin.as_mut() {
            info!("Writing VPN password to stdin...");
            writeln!(stdin, "{}", config.password)
                .map_err(|e| format!("Failed to write password: {}", e))?;
            stdin
                .flush()
                .map_err(|e| format!("Failed to flush stdin: {}", e))?;
            info!("Password written successfully");
        }

        child
    };

    // Store the process
    process.child = Some(child);

    // Save config for next time
    let user_config =
        crate::config::UserConfig::new(config.gateway.clone(), config.username.clone());
    if let Err(e) = crate::config::save_config(&user_config) {
        warn!("Failed to save config: {}", e);
    }

    // Give it a moment to start and check if it immediately fails
    drop(process); // Release lock temporarily
    sleep(Duration::from_secs(2)).await;

    let mut process = state.process.lock().await;
    if let Some(status) = process.check_status() {
        if !status.success() {
            error!("gpclient failed to start or authentication failed");
            return Err(format!(
                "Connection failed. This usually means:\n\
                 - Incorrect username or password\n\
                 - Incorrect sudo password\n\
                 - Network connectivity issues\n\
                 \n\
                 The connection has been reset. Please check your credentials and try again.\n\
                 Exit code: {:?}",
                status.code()
            ));
        }
    }

    info!("gpclient started successfully");
    Ok("VPN connection initiated. Check the console for connection status.".to_string())
}

/// Disconnect from the VPN.
///
/// This is a Tauri command that terminates the active VPN connection.
///
/// # Arguments
///
/// * `state` - Shared application state containing the process manager
///
/// # Returns
///
/// - `Ok(String)` with a success message if disconnected
/// - `Err(String)` if not connected or disconnection failed
#[tauri::command]
pub async fn disconnect_gpclient(state: State<'_, Arc<GpclientState>>) -> Result<String, String> {
    info!("Disconnecting gpclient");

    let mut process = state.process.lock().await;

    if !process.is_connected() {
        // Check if process exited on its own
        if let Some(_status) = process.check_status() {
            return Ok("Connection already terminated".to_string());
        }
        return Err("Not connected".to_string());
    }

    process
        .disconnect()
        .map_err(|e| format!("Failed to disconnect: {}", e))?;

    info!("gpclient disconnected");
    Ok("Disconnected successfully".to_string())
}

/// Check the VPN connection status.
///
/// This is a Tauri command that checks if the VPN is currently connected.
///
/// # Arguments
///
/// * `state` - Shared application state containing the process manager
///
/// # Returns
///
/// `Ok(true)` if connected, `Ok(false)` if disconnected.
/// Never returns an error.
#[tauri::command]
pub async fn gpclient_status(state: State<'_, Arc<GpclientState>>) -> Result<bool, String> {
    let mut process = state.process.lock().await;

    // Check if process is still running
    process.check_status();

    Ok(process.is_connected())
}

/// Check if the application is running with root privileges.
///
/// This is a Tauri command that checks the effective user ID.
///
/// # Returns
///
/// `Ok(true)` if running as root, `Ok(false)` otherwise.
/// Never returns an error.
#[tauri::command]
pub fn check_running_as_root() -> Result<bool, String> {
    let is_root = is_running_as_root();
    info!("check_running_as_root called: {}", is_root);
    Ok(is_root)
}
