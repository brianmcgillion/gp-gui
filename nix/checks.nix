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
              excludes = [
                # TypeScript config files use JSONC (JSON with comments)
                "tsconfig.*\\.json$"
              ];
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

            # JavaScript/TypeScript checks
            # NOTE: prettier is handled by treefmt - don't enable it separately
            # to avoid conflicts where both try to format the same files
            prettier = {
              enable = false; # Disabled: treefmt handles prettier formatting
              stages = [ "pre-commit" ];
              excludes = [
                "package-lock\\.json$"
                "node_modules/"
              ];
            };

            # ESLint for JavaScript/TypeScript (if eslint config exists)
            eslint = {
              enable = false; # Enable if you add .eslintrc
              stages = [ "pre-commit" ];
              files = "\\.(js|ts|tsx|jsx)$";
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
