/**
 * GlobalProtect VPN GUI Application
 *
 * Main React component that provides the user interface for connecting to
 * GlobalProtect VPN servers. Handles authentication, connection management,
 * and displays connection status.
 *
 * @module App
 */

// GlobalProtect VPN GUI - Simplified single-page version
import { useState, useEffect } from "react";
import {
  Box,
  Button,
  TextField,
  Typography,
  Paper,
  Alert,
  CircularProgress,
  FormControlLabel,
  Checkbox,
  Chip,
  Divider,
  IconButton,
  Collapse,
} from "@mui/material";
import {
  VpnLock,
  VpnLockOutlined,
  Settings,
  ExpandMore,
  ExpandLess,
  Refresh,
} from "@mui/icons-material";
import { invoke } from "@tauri-apps/api/core";

/**
 * VPN connection statistics displayed after successful connection.
 */
interface ConnectionStats {
  /** VPN gateway address */
  gateway: string;
  /** VPN portal/server address */
  portal: string;
  /** Authenticated username */
  username: string;
  /** Timestamp when connection was established */
  connectedAt: string;
}

/**
 * Main application component for GlobalProtect VPN GUI.
 *
 * Provides a user interface for:
 * - Connecting to GlobalProtect VPN servers
 * - Managing authentication credentials
 * - Configuring advanced options (CSD wrapper, OpenSSL fixes, etc.)
 * - Displaying connection status and statistics
 *
 * @returns The rendered VPN GUI application
 */
function App() {
  const [portal, setPortal] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [connected, setConnected] = useState(false);
  const [stats, setStats] = useState<ConnectionStats | null>(null);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [isRoot, setIsRoot] = useState(false);

  // Advanced options
  const [enableCsdWrapper, setEnableCsdWrapper] = useState(true);
  const [csdWrapperPath, setCsdWrapperPath] = useState(
    "/nix/store/x5kmyljwqdyr2jjhnk76m5py33ynjgbd-openconnect-9.12-unstable-2025-01-14/libexec/openconnect/hipreport.sh",
  );
  const [authgroup, setAuthgroup] = useState("");
  const [fixOpenssl, setFixOpenssl] = useState(true);
  const [ignoreTlsErrors, setIgnoreTlsErrors] = useState(false);

  useEffect(() => {
    checkRootStatus();
    loadSavedConfig();
  }, []);

  /**
   * Load previously saved VPN configuration from disk.
   *
   * Invokes the Tauri backend to retrieve saved server address and username.
   * Credentials (passwords) are never persisted.
   */
  const loadSavedConfig = async () => {
    try {
      const config = await invoke<{
        vpn_server: string;
        username: string;
      } | null>("load_user_config");
      if (config) {
        setPortal(config.vpn_server);
        setUsername(config.username);
        setAuthgroup(config.vpn_server);
        console.log("Loaded saved config:", config);
      }
    } catch (err) {
      console.error("Failed to load config:", err);
    }
  };

  /**
   * Check if the application is running with root privileges.
   *
   * VPN operations require root access to modify network interfaces.
   * Updates the UI to show a warning if not running as root.
   */
  const checkRootStatus = async () => {
    try {
      const root = await invoke<boolean>("check_running_as_root");
      setIsRoot(root);
    } catch (err) {
      console.error("Failed to check root status:", err);
    }
  };

  /**
   * Initiate VPN connection with the configured parameters.
   *
   * Validates required fields, invokes the backend to spawn gpclient,
   * and updates the UI based on connection success or failure.
   *
   * @throws {Error} If connection fails due to invalid credentials or network issues
   */
  const handleConnect = async () => {
    if (!portal.trim() || !username.trim() || !password.trim()) {
      setError("Please fill in all required fields");
      return;
    }

    try {
      setLoading(true);
      setError(null);

      await invoke("connect_gpclient", {
        config: {
          gateway: portal.trim(),
          username: username.trim(),
          password: password.trim(),
          csd_wrapper: enableCsdWrapper ? csdWrapperPath : null,
          fix_openssl: fixOpenssl,
          as_gateway: authgroup.trim() === portal.trim(),
          sudo_password: null,
        },
      });

      setConnected(true);
      setStats({
        gateway: portal,
        portal: portal,
        username: username,
        connectedAt: new Date().toLocaleString(),
      });
      setError(null);
    } catch (err) {
      setError(`Connection failed: ${err}`);
      setConnected(false);
    } finally {
      setLoading(false);
    }
  };

  /**
   * Disconnect from the VPN.
   *
   * Terminates the gpclient process and cleans up resources.
   */
  const handleDisconnect = async () => {
    try {
      setLoading(true);
      setError(null);
      await invoke("disconnect_gpclient");
      setConnected(false);
      setStats(null);
    } catch (err) {
      setError(`Disconnect failed: ${err}`);
    } finally {
      setLoading(false);
    }
  };

  /**
   * Refresh the root privilege status.
   *
   * Re-checks if the application is running as root and updates the UI.
   */
  const handleRefresh = async () => {
    await checkRootStatus();
  };

  return (
    <Box sx={{ p: 3, maxWidth: 800, margin: "0 auto" }}>
      <Paper elevation={3} sx={{ p: 3 }}>
        <Box display="flex" alignItems="center" justifyContent="space-between" mb={3}>
          <Box display="flex" alignItems="center" gap={2}>
            {connected ? (
              <VpnLock color="success" sx={{ fontSize: 40 }} />
            ) : (
              <VpnLockOutlined color="disabled" sx={{ fontSize: 40 }} />
            )}
            <Box>
              <Typography variant="h5">GlobalProtect VPN</Typography>
              <Chip
                label={connected ? "Connected" : "Disconnected"}
                color={connected ? "success" : "error"}
                size="small"
              />
            </Box>
          </Box>
          <IconButton onClick={handleRefresh} disabled={loading}>
            <Refresh />
          </IconButton>
        </Box>

        {!isRoot && (
          <Alert severity="warning" sx={{ mb: 2 }}>
            Not running as root. Run with: sudo gp-gui
          </Alert>
        )}

        {error && (
          <Alert severity="error" onClose={() => setError(null)} sx={{ mb: 2 }}>
            {error}
          </Alert>
        )}

        {!connected ? (
          <Box>
            <TextField
              fullWidth
              label="VPN Server"
              value={portal}
              onChange={(e) => setPortal(e.target.value)}
              placeholder="vpn.example.com"
              disabled={loading}
              sx={{ mb: 2 }}
            />

            <TextField
              fullWidth
              label="Username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="Enter username"
              disabled={loading}
              sx={{ mb: 2 }}
            />

            <TextField
              fullWidth
              label="Password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter password"
              disabled={loading}
              sx={{ mb: 2 }}
              onKeyPress={(e) => e.key === "Enter" && handleConnect()}
            />

            <Box sx={{ mb: 2 }}>
              <Button
                onClick={() => setShowAdvanced(!showAdvanced)}
                startIcon={showAdvanced ? <ExpandLess /> : <ExpandMore />}
                endIcon={<Settings />}
                size="small"
              >
                Advanced Options
              </Button>
              <Collapse in={showAdvanced}>
                <Box sx={{ mt: 2, pl: 2, borderLeft: 2, borderColor: "divider" }}>
                  <TextField
                    fullWidth
                    label="Gateway/Auth Group"
                    value={authgroup}
                    onChange={(e) => setAuthgroup(e.target.value)}
                    placeholder="vpn.example.com"
                    helperText="Authentication group (--authgroup, --as-gateway)"
                    sx={{ mb: 2 }}
                  />

                  <FormControlLabel
                    control={
                      <Checkbox
                        checked={enableCsdWrapper}
                        onChange={(e) => setEnableCsdWrapper(e.target.checked)}
                      />
                    }
                    label="Enable CSD Wrapper (HIP Report)"
                    sx={{ mb: 1 }}
                  />

                  {enableCsdWrapper && (
                    <TextField
                      fullWidth
                      label="CSD Wrapper Path"
                      value={csdWrapperPath}
                      onChange={(e) => setCsdWrapperPath(e.target.value)}
                      placeholder="/path/to/hipreport.sh"
                      helperText="Path to CSD wrapper script (--csd-wrapper)"
                      sx={{ mb: 2, ml: 4 }}
                    />
                  )}

                  <FormControlLabel
                    control={
                      <Checkbox
                        checked={fixOpenssl}
                        onChange={(e) => setFixOpenssl(e.target.checked)}
                      />
                    }
                    label="Fix OpenSSL compatibility (--fix-openssl)"
                  />

                  <FormControlLabel
                    control={
                      <Checkbox
                        checked={ignoreTlsErrors}
                        onChange={(e) => setIgnoreTlsErrors(e.target.checked)}
                      />
                    }
                    label="Ignore TLS Errors"
                  />
                </Box>
              </Collapse>
            </Box>

            <Button
              fullWidth
              variant="contained"
              onClick={handleConnect}
              disabled={loading || !portal.trim() || !username.trim() || !password.trim()}
              startIcon={loading ? <CircularProgress size={20} /> : null}
            >
              {loading ? "Connecting..." : "Authenticate & Connect"}
            </Button>
          </Box>
        ) : (
          <Box>
            {stats && (
              <Box sx={{ mb: 2 }}>
                <Typography variant="body2">
                  <strong>Gateway:</strong> {stats.gateway}
                </Typography>
                <Typography variant="body2">
                  <strong>Username:</strong> {stats.username}
                </Typography>
                <Typography variant="body2">
                  <strong>Connected At:</strong> {stats.connectedAt}
                </Typography>
              </Box>
            )}

            <Button
              fullWidth
              variant="contained"
              onClick={handleDisconnect}
              disabled={loading}
              startIcon={loading ? <CircularProgress size={20} /> : null}
              color="error"
            >
              {loading ? "Disconnecting..." : "Disconnect"}
            </Button>
          </Box>
        )}
      </Paper>
    </Box>
  );
}

export default App;
