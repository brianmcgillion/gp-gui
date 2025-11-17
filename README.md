# GlobalProtect VPN GUI

A graphical user interface for the GlobalProtect VPN client, built with Tauri and React.

This project is derived from and builds upon the excellent work of the [GlobalProtect-openconnect](https://github.com/yuezk/GlobalProtect-openconnect) project by yuezk. It provides a modern GUI wrapper around the `gpclient` binary for easier VPN connection management.

## Features

- Simple, intuitive GUI for connecting to GlobalProtect VPN servers
- Support for HIP (Host Integrity Protection) reporting via CSD wrapper
- OpenSSL compatibility fixes for modern systems
- Automatic cleanup of lock files on exit
- Built-in test automation for connection validation
- Native Linux application with minimal dependencies

## Requirements

- Linux system with NixOS or Nix package manager
- Root/sudo access (required for VPN connections)
- `gpclient` binary (provided by `globalprotect-openconnect`)

## Installation

### With Nix Flakes

```bash
# Build the application
nix build .#gp-gui

# Run directly
sudo ./result/bin/gp-gui
```

### Development

```bash
# Enter development environment
nix develop

# Or use devenv
devenv up
```

## Usage

### Starting the Application

The application **must** be run as root to modify network interfaces:

```bash
sudo ./result/bin/gp-gui
```

### Connecting to VPN

1. Enter your VPN server (e.g., `access.tii.ae`)
1. Enter your username
1. Enter your password
1. (Optional) Configure advanced options:
   - CSD Wrapper path for HIP reporting
   - Authentication group/gateway
   - OpenSSL compatibility fixes
1. Click "Authenticate & Connect"

### Advanced Options

- **CSD Wrapper**: Path to HIP report script (default: `/nix/store/.../hipreport.sh`)
- **Gateway/Auth Group**: Specify authentication group for multi-gateway setups
- **Fix OpenSSL**: Enable compatibility mode for SSL issues
- **Ignore TLS Errors**: Skip certificate validation (not recommended)

### Test Automation

The application includes a test automation feature for validating connections:

1. Expand "Test Automation" section
1. Enter test credentials
1. Click "Run Test" to validate the connection

## Architecture

- **Frontend**: React + TypeScript + Material-UI
- **Backend**: Rust (Tauri framework)
- **VPN Client**: Wraps `gpclient` from `globalprotect-openconnect`
- **Build System**: Nix flakes with crane for Rust builds

## Configuration Files

- **Lock File**: `/var/run/gpclient.lock` (automatically cleaned up on exit)
- **VPN State**: Managed in-memory by the application

## Troubleshooting

### "Not running as root" warning

The application requires root privileges. Run with:

```bash
sudo ./result/bin/gp-gui
```

### Connection fails with "Invalid username or password"

This error can occur if:

1. Credentials are incorrect
1. The wrong authentication group is specified
1. CSD wrapper is required but not configured

### Lock file not cleaned up

The application automatically removes `/var/run/gpclient.lock` on:

- Normal exit
- Ctrl+C / SIGTERM
- Process termination

If the lock file persists, remove it manually:

```bash
sudo rm /var/run/gpclient.lock
```

## Development

### Building from Source

```bash
# Build the GUI
nix build .#gp-gui

# Build with local builds (no binary cache)
nix build .#gp-gui --fallback --option builders ""
```

### Running in Development Mode

```bash
# Enter development shell
nix develop

# Run the GUI
cd gui
cargo tauri dev
```

## License

GPL-3.0 - See LICENSE file for details

## Acknowledgments

This project is built upon [GlobalProtect-openconnect](https://github.com/yuezk/GlobalProtect-openconnect) by yuezk, which provides the core VPN client functionality (`gpclient`, `gpauth`, `gpservice`). We are grateful for their work in creating an open-source alternative to the official GlobalProtect client.

## Authors

TII UAE <opensource@tii.ae>

## Contributing

Contributions are welcome! Please ensure:

1. Code follows existing style conventions
1. Changes are tested with the test automation feature
1. Documentation is updated for user-facing changes
