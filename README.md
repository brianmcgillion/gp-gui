# GlobalProtect VPN GUI

A graphical user interface for the GlobalProtect VPN client, built with Rust and Iced.

This project is derived from and builds upon the excellent work of the [GlobalProtect-openconnect](https://github.com/yuezk/GlobalProtect-openconnect) project by yuezk. It provides a modern GUI wrapper around the `gpclient` binary for easier VPN connection management.

## Features

- Simple, intuitive GUI for connecting to GlobalProtect VPN servers
- Support for HIP (Host Integrity Protection) reporting via CSD wrapper
- OpenSSL compatibility fixes for modern systems
- Automatic cleanup of lock files on exit
- Configuration persistence for VPN server and username
- Native Linux application with pure Rust implementation
- Responsive UI with proper connection state handling
- Error recovery and authentication failure handling

## Requirements

- Linux system with NixOS or Nix package manager
- Root/sudo access (required for VPN connections)
- `gpclient` binary (provided by `globalprotect-openconnect`)
- Wayland or X11 display server

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

- Rust toolchain with rust-analyzer
- cargo-edit for dependency management
- All Iced dependencies (Wayland, X11, Vulkan)
- gpclient and gpauth binaries
- Helper commands: `build-gui`, `cargo-test`, `cargo-run`

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
1. Click "Authenticate & Connect" or press Enter
1. Wait for connection to establish
1. Click "Disconnect" when you want to disconnect

## Architecture

- **UI Framework**: Iced (pure Rust, native performance)
- **VPN Client**: Wraps `gpclient` from `globalprotect-openconnect`
- **Build System**: Nix flakes with crane for Rust builds
- **State Management**: Async message-based architecture with proper error handling

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
1. The VPN server is unreachable
1. Network connectivity issues

The UI will return to the authentication screen, allowing you to correct credentials and retry.

### Lock file not cleaned up

The application automatically removes `/var/run/gpclient.lock` on:

- Normal exit
- Window close
- Disconnect
- Ctrl+C / SIGTERM

If the lock file persists, remove it manually:

```bash
sudo rm /var/run/gpclient.lock
```

## Development

### Updating Dependencies

To update all package dependencies (Nix, Cargo):

```bash
./scripts/update-deps.sh
```

Update specific package managers:

```bash
./scripts/update-deps.sh --nix     # Update Nix flake inputs only
./scripts/update-deps.sh --cargo   # Update Cargo dependencies only
./scripts/update-deps.sh --upgrade # Upgrade to latest versions
```

The script will:

- Update all lock files (flake.lock, Cargo.lock)
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

# Run with cargo (requires root)
sudo cargo run --release
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
