# SPDX-FileCopyrightText: 2025 gp-gui contributors
# SPDX-License-Identifier: GPL-3.0-only
{ inputs, ... }:
{
  imports = [ inputs.devshell.flakeModule ];

  perSystem =
    {
      pkgs,
      config,
      lib,
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
            pkgs.cargo-edit # Provides cargo-upgrade for version management

            # Build essentials
            pkgs.pkg-config

            # GlobalProtect client binaries
            pkgs.gpclient
            pkgs.gpauth

            # Iced dependencies - Wayland and X11 libraries
            pkgs.wayland
            pkgs.libxkbcommon
            pkgs.libGL
            pkgs.xorg.libXcursor
            pkgs.xorg.libXrandr
            pkgs.xorg.libXi
            pkgs.xorg.libX11
            pkgs.vulkan-loader

            # Additional tools
            pkgs.curl
            pkgs.wget
            pkgs.jq
          ]
          # Add pre-commit tools (includes treefmt wrapper)
          ++ config.pre-commit.settings.enabledPackages
          # Add treefmt programs except rustfmt (already in rustToolchain)
          ++ (lib.attrValues (removeAttrs config.treefmt.build.programs [ "rustfmt" ]));

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
            name = "cargo-test";
            help = "Run Rust tests";
            command = "cargo test";
          }
          {
            name = "cargo-run";
            help = "Run gp-gui (requires root)";
            command = "sudo cargo run --release";
          }
          {
            name = "update-deps";
            help = "Update all dependencies (Nix, Cargo)";
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
            name = "LD_LIBRARY_PATH";
            value = pkgs.lib.makeLibraryPath [
              pkgs.wayland
              pkgs.libxkbcommon
              pkgs.libGL
              pkgs.vulkan-loader
              pkgs.xorg.libXcursor
              pkgs.xorg.libXrandr
              pkgs.xorg.libXi
              pkgs.xorg.libX11
            ];
          }
        ];

        # Bash initialization
        bash.extra = ''
          echo "🚀 GlobalProtect VPN GUI Development Environment (Iced)"
          echo "========================================================"
          echo ""
          echo "📦 Packages installed:"
          echo "  - Rust $(rustc --version | cut -d' ' -f2)"
          echo "  - gpclient: $(which gpclient)"
          echo "  - gpauth: $(which gpauth)"
          echo ""
          echo "🔧 Available scripts:"
          echo "  build-gui         - Build gp-gui with Nix"
          echo "  cargo-test        - Run Rust tests"
          echo "  cargo-run         - Run gp-gui (requires root)"
          echo "  update-deps       - Update all dependencies (Nix, Cargo)"
          echo "  show-packages     - Show installed packages"
          echo ""
          echo "🚀 Development:"
          echo "  Run as root:         sudo ./result/bin/gp-gui"
          echo "  Cargo dev:           sudo cargo run --release"
          echo ""
          echo "📝 Format code:           nix fmt"
          echo "✓ Run checks:             nix flake check"
          echo ""
        '';
      };
    };
}
