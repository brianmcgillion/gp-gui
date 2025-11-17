# SPDX-FileCopyrightText: 2025 TII (SSRC) and the gp-gui contributors
# SPDX-License-Identifier: GPL-3.0-only
{ inputs, ... }:
{
  imports = [
    inputs.flake-root.flakeModule
    inputs.treefmt-nix.flakeModule
  ];

  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      treefmt = {
        inherit (config.flake-root) projectRootFile;

        programs = {
          # Nix
          # Standard Nix formatter according to RFC 166
          nixfmt.enable = true;
          nixfmt.package = pkgs.nixfmt-rfc-style;

          # Remove dead Nix code
          deadnix.enable = true;

          # Prevent use of Nix anti-patterns
          statix.enable = true;

          # Rust
          # Format Rust code
          rustfmt.enable = true;

          # JavaScript/TypeScript
          # Prettier for JS, TS, TSX, JSON, HTML, CSS, Markdown
          prettier.enable = true;
          prettier.includes = [
            "*.js"
            "*.ts"
            "*.tsx"
            "*.jsx"
            "*.json"
            "*.html"
            "*.css"
            "*.md"
          ];

          # Bash
          # Lint shell scripts
          shellcheck.enable = true;
          shfmt.enable = true;

          # TOML
          taplo.enable = true;

          # Markdown
          mdformat.enable = true;

          # Keep imports and other lists sorted
          keep-sorted.enable = true;
        };

        settings = {
          global.excludes = [
            # Direnv file (not a regular shell script)
            ".envrc"

            # Build artifacts
            "*.lock"
            "target/**"
            "result"
            "result-*"
            "node_modules/**"
            "dist/**"
            ".next/**"

            # Binary and media files
            "*.png"
            "*.jpg"
            "*.jpeg"
            "*.gif"
            "*.ico"
            "*.icns"
            "*.svg"
            "*.woff"
            "*.woff2"
            "*.ttf"
            "*.eot"

            # Archives and binaries
            "*.zip"
            "*.tar"
            "*.gz"
            "*.bz2"
            "*.xz"
            "*.rpm"
            "*.deb"

            # Secrets and certificates
            "*.key"
            "*.pem"
            "*.crt"
            "*.cer"
            "*.pfx"
            "*.p12"

            # Generated files
            "gui/src-tauri/gen/**"
            "gui/src-tauri/target/**"

            # Patches
            "*.patch"
            "*.diff"

            # IDE and editor files
            ".vscode/**"
            ".idea/**"
            "*.swp"
            "*.swo"
            "*~"
          ];

          formatter = {
            prettier = {
              options = [
                "--tab-width"
                "2"
                "--print-width"
                "100"
              ];
            };

            shfmt = {
              includes = [ "*.sh" ];
              options = [
                "-i"
                "2" # indent with 2 spaces
                "-s" # simplify the code
                "-sr" # redirect operators will be followed by a space
              ];
            };

            nixfmt = {
              includes = [ "*.nix" ];
            };

            statix = {
              includes = [ "*.nix" ];
            };

            deadnix = {
              includes = [ "*.nix" ];
            };
          };
        };
      };

      # Make treefmt available as a formatter
      formatter = config.treefmt.build.wrapper;
    };
}
