# Nix Configuration Directory

This directory contains Nix configuration modules and utilities for the gp-gui project.

## Contents

### treefmt.nix

Unified code formatting configuration using [treefmt](https://github.com/numtide/treefmt).

#### Supported Languages and Tools

| Language/Type             | Formatter        | Linter          | Purpose                                       |
| ------------------------- | ---------------- | --------------- | --------------------------------------------- |
| **Nix**                   | nixfmt-rfc-style | deadnix, statix | Format, remove dead code, check anti-patterns |
| **Rust**                  | rustfmt          | -               | Format Rust source code                       |
| **JavaScript/TypeScript** | prettier         | -               | Format JS, TS, TSX, JSON, HTML, CSS           |
| **Bash**                  | shfmt            | shellcheck      | Format and lint shell scripts                 |
| **TOML**                  | taplo            | -               | Format TOML files                             |
| **Markdown**              | mdformat         | -               | Format Markdown documentation                 |
| **General**               | keep-sorted      | -               | Keep lists and imports sorted                 |

#### Usage

```bash
# Format all files in the project
nix fmt

# Check formatting (CI)
nix flake check
```

#### Configuration

The treefmt configuration:

- Excludes build artifacts (`target/`, `node_modules/`, `result`)
- Excludes binary and media files
- Excludes secrets and certificates
- Uses 2-space indentation for most files
- 100-character line width for prettier

#### Customization

To exclude additional files, add patterns to `settings.global.excludes` in `treefmt.nix`.

To add new formatters, add them to `programs` section and configure in `settings.formatter`.

### checks.nix

Automated checks and pre-commit hooks using [git-hooks.nix](https://github.com/cachix/git-hooks.nix).

#### Available Checks

| Check        | Description                           |
| ------------ | ------------------------------------- |
| `gp-gui`     | Verify gp-gui builds successfully     |
| `rust-tests` | Run Rust test suite for Tauri backend |
| `pre-commit` | Run all pre-commit hooks              |
| `treefmt`    | Check code formatting                 |

#### Pre-commit Hooks

Automatically enabled hooks (run on `git commit`):

- **treefmt** - Format all code
- **nixfmt** - Format Nix code
- **statix** - Check for Nix anti-patterns
- **deadnix** - Remove dead Nix code
- **rustfmt** - Format Rust code
- **cargo-check** - Verify Rust code compiles
- **prettier** - Format JS/TS/JSON/HTML/CSS
- **shellcheck** - Lint shell scripts
- **shfmt** - Format shell scripts
- **end-of-file-fixer** - Ensure files end with newline
- **trim-trailing-whitespace** - Remove trailing whitespace
- **check-merge-conflicts** - Detect merge conflict markers
- **check-json** - Validate JSON syntax
- **check-toml** - Validate TOML syntax
- **check-yaml** - Validate YAML syntax
- **detect-private-keys** - Prevent committing private keys

Optional hooks (disabled, can enable in `checks.nix`):

- **clippy** - Strict Rust linting
- **eslint** - JavaScript/TypeScript linting

#### Usage

```bash
# Run all checks
nix flake check

# Run specific check
nix build .#checks.x86_64-linux.pre-commit
nix build .#checks.x86_64-linux.rust-tests

# Pre-commit hooks are automatically installed when entering dev shell
nix develop

# Manually run pre-commit on all files
nix build .#checks.x86_64-linux.pre-commit
```

#### Developer Workflow

1. Enter dev shell: `nix develop`
   - Pre-commit hooks are automatically installed
1. Make changes to code
1. Commit changes: `git commit`
   - Hooks run automatically on staged files
   - If hooks fail, commit is rejected
1. Fix issues and try again

#### CI Workflow

In CI, run `nix flake check` to:

- Build all packages
- Run all tests
- Check formatting on all files
- Verify code quality

## Adding New Modules

Place new flake-parts modules in this directory and import them in `flake.nix`:

```nix
flake-parts.lib.mkFlake { inherit inputs; } {
  imports = [
    ./nix/treefmt.nix
    ./nix/your-new-module.nix
  ];
  # ...
};
```
