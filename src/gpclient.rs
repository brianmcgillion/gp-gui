//! GlobalProtect VPN client wrapper for Iced

use anyhow::{Context, Result};
use log::{info, warn};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::io::AsyncWriteExt;
use tokio::process::{Child, Command};
use tokio::sync::Mutex;
use tokio::time::{Duration, sleep};

const GPCLIENT_BINARY: &str = "gpclient";
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
            csd_wrapper: Some("/nix/store/x5kmyljwqdyr2jjhnk76m5py33ynjgbd-openconnect-9.12-unstable-2025-01-14/libexec/openconnect/hipreport.sh".to_string()),
        }
    }
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

    let mut process = state.lock().await;

    if process.is_connected() {
        process.disconnect().await?;
    }

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

    if let Some(ref csd_wrapper) = config.csd_wrapper
        && !csd_wrapper.is_empty()
    {
        cmd.arg("--csd-wrapper").arg(csd_wrapper);
    }

    cmd.arg("--user")
        .arg(&config.username)
        .arg("--passwd-on-stdin")
        .arg(&config.gateway);

    let mut child = cmd.spawn().context("Failed to spawn gpclient")?;

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

    process.child = Some(child);

    let user_config =
        crate::config::UserConfig::new(config.gateway.clone(), config.username.clone());
    let _ = crate::config::save_config(&user_config);

    drop(process);

    // Wait for connection to establish or fail
    // Poll for up to 60 seconds (allow time for slow networks)
    for i in 0..120 {
        sleep(Duration::from_millis(500)).await;

        // Check if process has exited (indicates failure)
        let mut process = state.lock().await;
        if let Some(ref mut child) = process.child
            && let Ok(Some(status)) = child.try_wait()
        {
            drop(process);

            let error_msg = match status.code() {
                Some(256) => "Authentication failed: Invalid username or password".to_string(),
                Some(1) => "Connection failed: Unable to reach VPN server".to_string(),
                _ => format!("Connection failed with exit code: {:?}", status.code()),
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

pub fn check_running_as_root() -> bool {
    nix::unistd::Uid::effective().is_root()
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
