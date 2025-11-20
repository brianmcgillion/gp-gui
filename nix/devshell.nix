# SPDX-FileCopyrightText: 2025 gp-gui contributors
# SPDX-License-Identifier: GPL-3.0-only
{ inputs, ... }:
{
  imports = [ inputs.devshell.flakeModule ];

  perSystem =
    {
      pkgs,
      config,
      ...
    }:
    let
      # Use the same Rust toolchain as the build (from rust-toolchain.toml or rust-overlay)
      rustToolchain = pkgs.rust-bin.stable.latest.default.override {
        extensions = [
          "rust-src"
          "clippy"
          "rustfmt"
        ];
      };
    in
    {
      devshells.default = {

        devshell = {
          name = "gp-gui";

          # Packages available in the development shell
          packages = [
            # Rust development tools
            rustToolchain
            pkgs.rust-analyzer

            # Build essentials
            pkgs.pkg-config
            pkgs.openssl.dev

            # Node.js and npm for frontend
            pkgs.nodejs_22

            # GlobalProtect client binaries
            pkgs.gpclient
            pkgs.gpauth

            # Tauri dependencies
            pkgs.webkitgtk_4_1
            pkgs.gtk3
            pkgs.cairo
            pkgs.glib
            pkgs.pango
            pkgs.atk
            pkgs.dbus
            pkgs.openssl
            pkgs.librsvg

            # Additional tools
            pkgs.curl
            pkgs.wget
            pkgs.jq
          ]
          # Add pre-commit tools (includes treefmt wrapper)
          ++ config.pre-commit.settings.enabledPackages;

          # Install pre-commit hooks for local development
          startup.hook.text = config.pre-commit.installationScript;
        };
        # Development commands
        commands = [
          {
            name = "build-gui";
            help = "Build gp-gui";
            command = "nix build .#gp-gui";
          }
          {
            name = "npm-install";
            help = "Install frontend dependencies";
            command = "cd gui && npm install";
          }
          {
            name = "cargo-test";
            help = "Run Rust tests";
            command = "cd gui/src-tauri && cargo test";
          }
          {
            name = "update-deps";
            help = "Update all dependencies (Nix, Cargo, npm)";
            command = "./scripts/update-deps.sh";
          }
          {
            name = "show-packages";
            help = "Show installed packages";
            command = "echo 'Run: nix-store -q --references $(which bash) | sort'";
          }
        ];

        # Environment variables
        env = [
          {
            name = "RUST_SRC_PATH";
            value = "${rustToolchain}/lib/rustlib/src/rust/library";
          }
          {
            name = "PKG_CONFIG_PATH";
            value = pkgs.lib.makeSearchPath "lib/pkgconfig" [
              pkgs.openssl.dev
              pkgs.glib.dev
              pkgs.gtk3.dev
              pkgs.pango.dev
              pkgs.atk.dev
              pkgs.cairo.dev
              pkgs.webkitgtk_4_1.dev
              pkgs.librsvg.dev
            ];
          }
        ];

        # Bash initialization
        bash.extra = ''
          echo "🚀 GlobalProtect VPN GUI Development Environment"
          echo "=================================================="
          echo ""
          echo "📦 Packages installed:"
          echo "  - Rust $(rustc --version | cut -d' ' -f2)"
          echo "  - Node $(node --version)"
          echo "  - gpclient: $(which gpclient)"
          echo "  - gpauth: $(which gpauth)"
          echo ""
          echo "🔧 Available scripts:"
          echo "  build-gui         - Build gp-gui"
          echo "  npm-install       - Install frontend dependencies"
          echo "  cargo-test        - Run Rust tests"
          echo "  update-deps       - Update all dependencies (Nix, Cargo, npm)"
          echo "  show-packages     - Show installed packages"
          echo ""
          echo "🚀 Development:"
          echo "  Run as root:         sudo ./result/bin/gp-gui"
          echo "  Tauri dev (manual):  cd gui && npm exec tauri dev"
          echo ""
          echo "📝 Format code:           nix fmt"
          echo "✓ Run checks:             nix flake check"
          echo ""
        '';
      };
    };
}
