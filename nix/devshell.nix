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

            # Tauri dependencies - GTK3 and related libraries
            # Note: gdk-pixbuf is provided transitively by gtk3
            # librsvg is only needed in the build, not in devshell
            pkgs.gtk3
            pkgs.gtk3.dev
            pkgs.webkitgtk_4_1
            pkgs.cairo
            pkgs.glib
            pkgs.pango
            pkgs.atk
            pkgs.dbus
            pkgs.openssl

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
              pkgs.harfbuzz.dev # Required by pango
              pkgs.pango.dev
              pkgs.atk.dev
              pkgs.gdk-pixbuf.dev # Needed for pkgconfig, runtime comes from gtk3
              pkgs.cairo.dev
              pkgs.webkitgtk_4_1.dev
              pkgs.libsoup_3.dev
            ];
          }
          {
            name = "LD_LIBRARY_PATH";
            value = pkgs.lib.makeLibraryPath [
              pkgs.gtk3 # Includes gdk-pixbuf transitively
              pkgs.cairo
              pkgs.glib
              pkgs.pango
              pkgs.atk
              pkgs.webkitgtk_4_1
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
          echo "  test-workflows    - Test GitHub Actions workflows locally"
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
