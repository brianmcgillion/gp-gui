//! GlobalProtect VPN client wrapper for Iced

use anyhow::{Context, Result};
use log::{info, warn};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::io::AsyncWriteExt;
use tokio::process::{Child, Command};
use tokio::sync::Mutex;
use tokio::time::{Duration, sleep};

const GPCLIENT_BINARY: &str = "/run/wrappers/bin/gpclient";
const LOCK_FILE: &str = "/var/run/gpclient.lock";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VpnConfig {
    pub gateway: String,
    pub username: String,
    pub password: String,
    pub authgroup: Option<String>,
    pub as_gateway: bool,
    pub fix_openssl: bool,
    pub csd_wrapper: Option<String>,
}

impl Default for VpnConfig {
    fn default() -> Self {
        Self {
            gateway: String::new(),
            username: String::new(),
            password: String::new(),
            authgroup: None,
            as_gateway: true,
            fix_openssl: true,
            csd_wrapper: None,
        }
    }
}

/// Dynamically find the CSD wrapper (hipreport.sh) by locating openconnect
fn find_csd_wrapper() -> Option<String> {
    // Try to find openconnect binary first
    let openconnect_path = std::process::Command::new("which")
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

pub struct GpclientProcess {
    child: Option<Child>,
}

impl GpclientProcess {
    pub fn new() -> Self {
        Self { child: None }
    }

    pub fn is_connected(&self) -> bool {
        self.child.is_some()
    }

    pub async fn disconnect(&mut self) -> Result<()> {
        if let Some(mut child) = self.child.take() {
            info!("Killing gpclient process");

            if let Err(e) = child.kill().await {
                warn!("Failed to kill gpclient process: {}", e);
            } else {
                info!("Sent SIGKILL to gpclient process");
            }

            let _ = Command::new("pkill")
                .arg("-9")
                .arg("gpclient")
                .output()
                .await;
        }

        cleanup_lock_file();
        Ok(())
    }
}

impl Drop for GpclientProcess {
    fn drop(&mut self) {
        if let Some(mut child) = self.child.take() {
            info!("Drop: Cleaning up gpclient process");

            // Attempt synchronous kill
            if let Err(e) = child.start_kill() {
                warn!("Drop: Failed to kill gpclient process: {}", e);
            } else {
                info!("Drop: Sent SIGKILL to gpclient process");
            }

            // Fallback: pkill synchronously
            let _ = std::process::Command::new("pkill")
                .arg("-9")
                .arg("gpclient")
                .output();
        }

        // Always try to cleanup lock file
        cleanup_lock_file();
    }
}

fn cleanup_lock_file() {
    match std::fs::remove_file(LOCK_FILE) {
        Ok(_) => info!("Successfully removed lock file"),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
        Err(e) => warn!("Failed to remove lock file: {}", e),
    }
}

pub type VpnState = Arc<Mutex<GpclientProcess>>;

pub fn create_vpn_state() -> VpnState {
    Arc::new(Mutex::new(GpclientProcess::new()))
}

pub async fn connect_vpn(state: VpnState, config: VpnConfig) -> Result<String> {
    info!("Starting VPN connection to {}", config.gateway);

    // Check if already connected and disconnect if needed
    {
        let mut process = state.lock().await;
        if process.is_connected() {
            process.disconnect().await?;
        }
    } // Drop lock here

    // Build command outside the lock
    let mut cmd = Command::new(GPCLIENT_BINARY);
    cmd.stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::inherit())
        .stderr(std::process::Stdio::inherit());

    if config.fix_openssl {
        cmd.arg("--fix-openssl");
    }

    cmd.arg("connect");

    if config.as_gateway {
        cmd.arg("--as-gateway");
    }

    // Use config csd_wrapper if provided, otherwise try to find it dynamically
    let csd_wrapper = config.csd_wrapper.clone().or_else(find_csd_wrapper);
    if let Some(ref wrapper) = csd_wrapper
        && !wrapper.is_empty()
    {
        cmd.arg("--csd-wrapper").arg(wrapper);
    }

    cmd.arg("--user")
        .arg(&config.username)
        .arg("--passwd-on-stdin")
        .arg(&config.gateway);

    // Spawn child outside the lock
    let mut child = cmd.spawn().context("Failed to spawn gpclient")?;

    // Write password outside the lock
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(config.password.as_bytes())
            .await
            .context("Failed to write password")?;
        stdin.write_all(b"\n").await?;
        stdin.flush().await?;
        drop(stdin);
        info!("Stdin closed");
    }

    // Only acquire lock to store the child process
    {
        let mut process = state.lock().await;
        process.child = Some(child);
    } // Drop lock immediately

    // Save config without holding the lock
    let user_config =
        crate::config::UserConfig::new(config.gateway.clone(), config.username.clone());
    if let Err(e) = crate::config::save_config(&user_config) {
        warn!("Failed to save VPN config: {}", e);
    }

    // Wait for connection to establish or fail
    // Poll for up to 60 seconds (allow time for slow networks)
    for i in 0..120 {
        sleep(Duration::from_millis(500)).await;

        // Check if process has exited (indicates failure)
        let mut process = state.lock().await;
        if let Some(ref mut child) = process.child
            && let Ok(Some(status)) = child.try_wait()
        {
            // Clear the child process from state before dropping the lock
            process.child = None;
            drop(process);

            // Map gpclient exit codes to user-friendly messages
            // gpclient only returns 0 (success) or 1 (failure)
            let error_msg = match status.code() {
                Some(1) => "Connection failed: Unable to reach VPN server or authentication failed"
                    .to_string(),
                Some(code) => format!("Connection failed with exit code: {}", code),
                None => "Connection failed: Process terminated by signal".to_string(),
            };

            cleanup_lock_file();
            return Err(anyhow::anyhow!("{}", error_msg));
        }
        drop(process);

        // Check if lock file exists (indicates success)
        if std::path::Path::new(LOCK_FILE).exists() {
            info!(
                "Lock file detected, VPN connected successfully (attempt {})",
                i + 1
            );
            return Ok("VPN connection established successfully".to_string());
        }
    }

    // Timeout - kill the process and fail
    let mut process = state.lock().await;
    process.disconnect().await?;
    drop(process);

    Err(anyhow::anyhow!(
        "Connection timeout: VPN did not establish within 60 seconds"
    ))
}

pub async fn disconnect_vpn(state: VpnState) -> Result<String> {
    info!("Disconnecting VPN");

    let mut process = state.lock().await;

    if !process.is_connected() {
        cleanup_lock_file();
        return Ok("Already disconnected".to_string());
    }

    process.disconnect().await?;

    Ok("Disconnected successfully".to_string())
}

/// Cleanup function to call on application exit
pub fn cleanup_on_exit() {
    info!("Performing cleanup on exit");

    // Kill any running gpclient processes
    let _ = std::process::Command::new("pkill")
        .arg("-9")
        .arg("gpclient")
        .output();

    // Clean up lock file
    cleanup_lock_file();

    info!("Cleanup complete");
}
