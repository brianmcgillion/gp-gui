# GlobalProtect VPN GUI

A graphical user interface for the GlobalProtect VPN client, built with Tauri and React.

This project is derived from and builds upon the excellent work of the [GlobalProtect-openconnect](https://github.com/yuezk/GlobalProtect-openconnect) project by yuezk. It provides a modern GUI wrapper around the `gpclient` binary for easier VPN connection management.

## Features

- Simple, intuitive GUI for connecting to GlobalProtect VPN servers
- Support for HIP (Host Integrity Protection) reporting via CSD wrapper
- OpenSSL compatibility fixes for modern systems
- Automatic cleanup of lock files on exit
- Configuration persistence for VPN server and username
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
```

The development shell provides:

- Rust toolchain (1.85.0) with rust-analyzer
- Node.js 22 and npm
- All Tauri dependencies (webkitgtk, gtk3, etc.)
- gpclient and gpauth binaries
- Helper commands: `build-gui`, `npm-install`, `cargo-test`

## Usage

### Starting the Application

The application **must** be run as root to modify network interfaces:

```bash
sudo ./result/bin/gp-gui
```

### Connecting to VPN

1. Enter your VPN server (e.g., `vpn.example.com`)
1. Enter your username
1. Enter your password
1. (Optional) Configure advanced options:
   - CSD Wrapper path for HIP reporting
   - Authentication group/gateway
   - OpenSSL compatibility fixes
1. Click "Authenticate & Connect"

### Advanced Options

- **CSD Wrapper**: Path to HIP report script (auto-detected or specify manually)
- **Gateway/Auth Group**: Specify authentication group for multi-gateway setups
- **Fix OpenSSL**: Enable compatibility mode for SSL issues

## Architecture

- **Frontend**: React + TypeScript + Material-UI
- **Backend**: Rust (Tauri framework)
- **VPN Client**: Wraps `gpclient` from `globalprotect-openconnect`
- **Build System**: Nix flakes with crane for Rust builds

## Configuration Files

- **User Config**: `~/.config/gp-gui/config.json` (stores VPN server and username)
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

### Updating Dependencies

To update all package dependencies (Nix, Cargo, npm):

```bash
./scripts/update-deps.sh
```

Update specific package managers:

```bash
./scripts/update-deps.sh --nix     # Update Nix flake inputs only
./scripts/update-deps.sh --cargo   # Update Cargo dependencies only
./scripts/update-deps.sh --npm     # Update npm dependencies only
```

The script will:

- Update all lock files (flake.lock, Cargo.lock, package-lock.json)
- Automatically update the npm hash in the Nix build
- Verify the build still works
- Show a summary of changes

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

This project is built upon [GlobalProtect-openconnect](https://github.com/yuezk/GlobalProtect-openconnect) by yuezk, which provides the core VPN client functionality (`gpclient` and `gpauth`). We are grateful for their work in creating an open-source alternative to the official GlobalProtect client.

## Contributing

Contributions are welcome! Please ensure:

1. Code follows existing style conventions (see `.github/copilot-instructions.md`)
1. All code is formatted with `nix develop -c treefmt`
1. Changes pass `nix flake check`
1. Documentation is updated for user-facing changes
