# SPDX-FileCopyrightText: 2025 gp-gui contributors
# SPDX-License-Identifier: GPL-3.0-only
{ inputs, ... }:
{
  imports = [ inputs.devenv.flakeModule ];

  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      devenv.shells.default = {
        name = "gp-gui";

        # Disable containers - we don't use them
        containers = pkgs.lib.mkForce { };

        # Devenv root directory - use the special devenv-root input
        devenv.root =
          let
            devenvRootFileContent = builtins.readFile inputs.devenv-root.outPath;
          in
          pkgs.lib.mkIf (devenvRootFileContent != "") devenvRootFileContent;

        # Import devenv modules
        imports = [ ];

        # Packages available in the environment
        packages =
          let
            # Rust toolchain with rust-src extension
            rustToolchain = pkgs.rust-bin.stable."1.85.0".default.override {
              extensions = [ "rust-src" ];
            };
          in
          [
            # Rust development tools
            rustToolchain
            pkgs.rust-analyzer

            # Build essentials
            pkgs.pkg-config
            pkgs.openssl.dev

            # Node.js for frontend
            pkgs.nodejs

            # GTK and Tauri dependencies
            pkgs.gtk3
            pkgs.webkitgtk_4_1
            pkgs.libsoup_3
            pkgs.glib
            pkgs.cairo
            pkgs.pango
            pkgs.atk
            pkgs.gdk-pixbuf
            pkgs.libappindicator-gtk3

            # VPN tools
            pkgs.openconnect
            pkgs.vpnc-scripts
            pkgs.gpclient
            pkgs.gpauth
          ];

        # Environment variables
        env = {
          PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
          OPENSSL_DIR = "${pkgs.openssl.dev}";
          OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
          OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
        };

        # Scripts - like devshell commands but simpler
        scripts = {
          # Build commands
          build-gui.exec = "nix build .#gp-gui";

          # Development commands
          npm-install.exec = "cd gui && npm install";
          cargo-build.exec = "cd gui/src-tauri && cargo build --release";
          cargo-test.exec = "cd gui/src-tauri && cargo test";

          # Info commands
          show-packages.exec = ''
            echo "Available packages:"
            echo "  gpclient: $(which gpclient)"
            echo "  gpauth: $(which gpauth)"
            echo ""
            echo "Rust version: $(rustc --version)"
            echo "Node version: $(node --version)"
            echo ""
          '';
        };

        # Process management disabled - we use gpclient directly now
        # processes = {};

        # Shell hook - runs when entering the shell
        enterShell = ''
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

        # Git hooks integration (replaces pre-commit.hooks)
        git-hooks.hooks = {
          treefmt.enable = true;
          treefmt.package = config.treefmt.build.wrapper;

          nixfmt.enable = true;
          nixfmt.package = pkgs.nixfmt-rfc-style;

          statix.enable = true;
          deadnix.enable = true;

          rustfmt.enable = true;
          prettier.enable = true;
          shellcheck.enable = true;
          shfmt.enable = true;

          end-of-file-fixer.enable = true;
          trim-trailing-whitespace.enable = true;
          check-merge-conflicts.enable = true;
          check-json.enable = true;
          check-toml.enable = true;
          check-yaml.enable = true;
          detect-private-keys.enable = true;
        };
      };
    };
}
