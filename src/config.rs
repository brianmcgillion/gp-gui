//! User Configuration Management
//!
//! This module handles loading and saving user preferences for the VPN client.
//! Configuration is stored in the user's XDG config directory as JSON.
//!
//! # Storage Location
//!
//! - Linux: `$XDG_CONFIG_HOME/gp-gui/config.json` or `~/.config/gp-gui/config.json`
//! - Configuration includes VPN server and username (password is never saved)
//!
//! # Security
//!
//! Passwords are never persisted to disk. Only non-sensitive configuration
//! (server address and username) is saved for user convenience.

use anyhow::Result;
use log::{info, warn};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

/// User configuration stored on disk.
///
/// Contains only non-sensitive information that can be safely persisted.
/// Passwords are never included to prevent credential exposure.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserConfig {
    /// VPN server address (e.g., "vpn.example.com")
    pub vpn_server: String,

    /// Username for VPN authentication
    pub username: String,
}

impl UserConfig {
    /// Create a new user configuration.
    ///
    /// # Arguments
    ///
    /// * `vpn_server` - The VPN gateway address
    /// * `username` - The user's VPN username
    pub fn new(vpn_server: String, username: String) -> Self {
        Self {
            vpn_server,
            username,
        }
    }
}

/// Get the path to the configuration file.
///
/// Determines the config directory using XDG Base Directory specification,
/// falling back to platform defaults if XDG_CONFIG_HOME is not set.
///
/// # Returns
///
/// - `Ok(PathBuf)` with the full path to config.json
/// - `Err` if the config directory cannot be determined or created
///
/// # File Location
///
/// - First tries `$XDG_CONFIG_HOME/gp-gui/config.json`
/// - Falls back to `~/.config/gp-gui/config.json` on Linux
///
/// The directory is created if it doesn't exist.
pub fn get_config_path() -> Result<PathBuf> {
    let config_dir = if let Ok(xdg_config) = std::env::var("XDG_CONFIG_HOME") {
        PathBuf::from(xdg_config)
    } else if let Some(home) = directories::BaseDirs::new() {
        home.config_dir().to_path_buf()
    } else {
        return Err(anyhow::anyhow!("Could not determine config directory"));
    };

    let app_config_dir = config_dir.join("gp-gui");
    if !app_config_dir.exists() {
        fs::create_dir_all(&app_config_dir)?;
        info!("Created config directory: {:?}", app_config_dir);
    }

    Ok(app_config_dir.join("config.json"))
}

/// Load the user configuration from disk.
///
/// # Returns
///
/// - `Some(UserConfig)` if the config file exists and is valid
/// - `None` if the file doesn't exist, cannot be read, or is invalid JSON
///
/// # Errors
///
/// Errors are logged but not returned. This function is designed to degrade
/// gracefully - if config cannot be loaded, the app still functions.
pub fn load_config() -> Option<UserConfig> {
    match get_config_path() {
        Ok(path) => {
            if path.exists() {
                match fs::read_to_string(&path) {
                    Ok(content) => match serde_json::from_str(&content) {
                        Ok(config) => {
                            info!("Loaded config from {:?}", path);
                            Some(config)
                        }
                        Err(e) => {
                            warn!("Failed to parse config: {}", e);
                            None
                        }
                    },
                    Err(e) => {
                        warn!("Failed to read config: {}", e);
                        None
                    }
                }
            } else {
                info!("No config file found at {:?}", path);
                None
            }
        }
        Err(e) => {
            warn!("Failed to get config path: {}", e);
            None
        }
    }
}

/// Save the user configuration to disk.
///
/// Serializes the configuration to JSON and writes it to the config file.
///
/// # Arguments
///
/// * `config` - The configuration to save
///
/// # Returns
///
/// - `Ok(())` if saved successfully
/// - `Err` if the file cannot be written or JSON serialization fails
///
/// # Errors
///
/// Returns an error if:
/// - The config directory cannot be determined
/// - The config file cannot be created or written
/// - JSON serialization fails
pub fn save_config(config: &UserConfig) -> Result<()> {
    let path = get_config_path()?;
    let content = serde_json::to_string_pretty(config)?;
    fs::write(&path, content)?;
    info!("Saved config to {:?}", path);
    Ok(())
}
