# SPDX-FileCopyrightText: 2025 gp-gui contributors
# SPDX-License-Identifier: GPL-3.0-only
{ inputs, ... }:
{
  imports = [ inputs.git-hooks-nix.flakeModule ];

  perSystem =
    {
      config,
      pkgs,
      self',
      ...
    }:
    {
      # Checks are automatically provided by git-hooks-nix.flakeModule:
      # - checks.${system}.pre-commit: runs all pre-commit hooks (treefmt, etc.)
      #
      # Developer workflow:
      # - Pre-commit hooks are installed via config.pre-commit.installationScript
      # - Hooks run automatically on `git commit` for staged files only
      #
      # CI workflow:
      # - checks.${system}.pre-commit runs all hooks on all tracked files
      # - Used by CI to enforce code standards

      checks = {
        # Check that all packages build successfully
        inherit (self'.packages) gp-gui;

        # Verify all runtime dependencies are available and built in correct order
        gp-gui-deps =
          pkgs.runCommand "verify-gp-gui-dependencies"
            {
              buildInputs = with pkgs; [
                gpauth
                gpclient
                openconnect
              ];
            }
            ''
              # Verify all required binaries exist
              for cmd in gpauth gpclient openconnect; do
                if ! command -v $cmd >/dev/null 2>&1; then
                  echo "ERROR: Required command '$cmd' not found in PATH"
                  exit 1
                fi
              done

              # Verify gp-gui package has correct passthru
              ${pkgs.lib.optionalString (self'.packages.gp-gui ? passthru.runtimeDeps) ''
                echo "✓ Runtime dependencies verified in passthru"
              ''}

              touch $out
            '';

        # Verify the overlay is valid and exports gp-gui correctly
        overlay-check =
          let
            # Apply the overlay to a test nixpkgs instance
            testPkgs = pkgs.extend inputs.self.overlays.default;
          in
          pkgs.runCommand "verify-overlay" { } ''
            # Verify the overlay exports gp-gui
            ${
              if testPkgs ? gp-gui then
                ''echo "✓ Overlay exports gp-gui attribute"''
              else
                ''
                  echo "ERROR: Overlay does not export gp-gui attribute"
                  exit 1
                ''
            }

            # Verify gp-gui derivation is valid
            ${
              if testPkgs.gp-gui ? outPath then
                ''echo "✓ gp-gui derivation is valid"''
              else
                ''
                  echo "ERROR: gp-gui derivation is invalid"
                  exit 1
                ''
            }

            echo "✓ Overlay validation complete"
            touch $out
          '';

        # Verify the setuid wrapper package structure
        gp-gui-wrapper-check =
          let
            wrapper = self'.packages.gp-gui-wrapper;
          in
          pkgs.runCommand "verify-gp-gui-wrapper" { buildInputs = [ pkgs.binutils ]; } ''
            # Verify wrapper has expected structure
            if [ ! -d "${wrapper}/bin" ]; then
              echo "ERROR: Wrapper does not have bin directory"
              exit 1
            fi

            if [ ! -f "${wrapper}/bin/gp-gui-wrapper" ]; then
              echo "ERROR: Wrapper does not contain gp-gui-wrapper binary"
              exit 1
            fi

            echo "✓ Wrapper package has correct structure"

            # Verify wrapper is executable
            if [ ! -x "${wrapper}/bin/gp-gui-wrapper" ]; then
              echo "ERROR: Wrapper binary is not executable"
              exit 1
            fi

            echo "✓ Wrapper binary is executable"

            # Verify wrapper references the actual gp-gui package
            if ! strings "${wrapper}/bin/gp-gui-wrapper" | grep -q "${self'.packages.gp-gui}"; then
              echo "ERROR: Wrapper does not reference gp-gui package"
              exit 1
            fi

            echo "✓ Wrapper references gp-gui package correctly"
            echo "✓ Setuid wrapper validation complete"
            touch $out
          '';

        # NixOS VM test for the gp-gui module
        # Verifies that the module correctly sets up the setuid wrapper
        nixos-module-test = import ../nix/tests/nixos-module.nix {
          inherit pkgs;
          inherit (inputs) self;
        };

        # Rust tests disabled - requires network in nix build
        # Run tests with: nix develop -c cargo test
      };

      pre-commit = {
        check.enable = true;
        settings = {
          hooks = {
            # === FORMATTING (via treefmt) ===
            # treefmt handles ALL formatting: Nix, Rust, JS/TS, Shell, Markdown, TOML, Prettier
            # For CI: uses --fail-on-change to verify formatting without modifying files
            # For local: auto-formats files before commit
            treefmt = {
              enable = true;
              package = config.treefmt.build.wrapper;
              stages = [ "pre-commit" ];
              pass_filenames = false;
              # Use --fail-on-change for CI checks to prevent file modifications
              entry = "${config.treefmt.build.wrapper}/bin/treefmt --ci";
            };

            # === VALIDATION HOOKS (not handled by treefmt) ===

            # File consistency checks
            end-of-file-fixer = {
              enable = true;
              stages = [ "pre-commit" ];
              excludes = [
                ".*\\.patch$"
                ".*\\.diff$"
                ".*\\.lock$"
              ];
            };

            trim-trailing-whitespace = {
              enable = true;
              stages = [ "pre-commit" ];
              excludes = [
                ".*\\.patch$"
                ".*\\.diff$"
                ".*\\.lock$"
              ];
            };

            # Git checks
            check-merge-conflicts = {
              enable = true;
              stages = [ "pre-commit" ];
            };

            # Syntax validation
            check-json = {
              enable = true;
              stages = [ "pre-commit" ];
            };

            check-toml = {
              enable = true;
              stages = [ "pre-commit" ];
            };

            check-yaml = {
              enable = true;
              stages = [ "pre-commit" ];
            };

            # Security checks
            detect-private-keys = {
              enable = true;
              stages = [ "pre-commit" ];
            };

            # Rust compilation/linting (beyond formatting)
            cargo-check = {
              enable = false; # Disabled: requires network access in Nix sandbox
              stages = [ "pre-commit" ];
              entry = "${pkgs.cargo}/bin/cargo check --workspace";
              files = "\\.(rs|toml)$";
              pass_filenames = false;
            };

            # Clippy for Rust linting (optional, can be strict)
            clippy = {
              enable = false; # Enable if you want strict linting
              stages = [ "pre-commit" ];
              entry = "${pkgs.cargo}/bin/cargo clippy --workspace -- -D warnings";
              files = "\\.(rs|toml)$";
              pass_filenames = false;
            };

            # Shell script checks
            shellcheck = {
              enable = true;
              stages = [ "pre-commit" ];
              excludes = [ ".envrc" ];
            };

            # Note: shfmt is handled by treefmt, don't enable separately to avoid timing conflicts
            shfmt = {
              enable = false;
              stages = [ "pre-commit" ];
            };
          };
        };
      };
    };
}
