#!/usr/bin/env bash
# Update all package dependencies for gp-gui
#
# This script updates:
# - Nix flake inputs (flake.lock)
# - Cargo dependencies (Cargo.lock)
# - npm dependencies (package-lock.json)
#
# Usage: ./scripts/update-deps.sh [OPTIONS]
#
# Options:
#   --all       Update all dependencies (default)
#   --nix       Update only Nix flake inputs
#   --cargo     Update only Cargo dependencies
#   --npm       Update only npm dependencies
#   --upgrade   Upgrade source dependencies (Cargo.toml, package.json) to latest versions
#   --help      Show this help message
#
# Examples:
#   ./scripts/update-deps.sh              # Update all lock files
#   ./scripts/update-deps.sh --upgrade    # Upgrade source dependencies + update lock files
#   ./scripts/update-deps.sh --cargo      # Update only Cargo.lock
#   ./scripts/update-deps.sh --cargo --upgrade  # Upgrade Cargo.toml versions + update lock

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the project root
if [[ ! -f "flake.nix" ]]; then
  error "Must be run from the project root directory"
  exit 1
fi

update_nix() {
  info "Updating Nix flake inputs..."

  if ! command -v nix &> /dev/null; then
    error "Nix is not installed"
    return 1
  fi

  # Update all flake inputs
  nix flake update

  success "Nix flake inputs updated"

  # Show what changed
  info "Flake input changes:"
  git --no-pager diff flake.lock | grep -E "^\+.*\"(narHash|rev)\"" | head -20 || true
}

update_cargo() {
  local upgrade_mode=${1:-false}

  if [[ $upgrade_mode == true ]]; then
    info "Upgrading Cargo dependencies (will update Cargo.toml versions)..."
  else
    info "Updating Cargo dependencies (lock files only)..."
  fi

  if ! command -v cargo &> /dev/null; then
    warn "Cargo not found in PATH, trying via nix develop..."
    if ! nix develop -c cargo --version &> /dev/null; then
      error "Cargo is not available"
      return 1
    fi
    CARGO_CMD="nix develop -c cargo"
  else
    CARGO_CMD="cargo"
  fi

  # If upgrade mode, use cargo-upgrade if available
  if [[ $upgrade_mode == true ]]; then
    if $CARGO_CMD upgrade --help &> /dev/null; then
      warn "⚠️  UPGRADE MODE: This will modify Cargo.toml files!"

      # cargo-upgrade doesn't support --workspace, run in each package directory
      info "Running cargo upgrade in gui/src-tauri..."
      (cd gui/src-tauri && $CARGO_CMD upgrade) || warn "gui/src-tauri cargo upgrade failed"

      success "Cargo.toml files upgraded"
    else
      warn "cargo-upgrade not available"
      warn "To enable version upgrades, install cargo-edit:"
      warn "  cargo install cargo-edit"
      warn "Falling back to lock file updates only"
    fi
  fi

  # Update workspace dependencies
  info "Updating workspace Cargo.lock..."
  $CARGO_CMD update --workspace

  success "Cargo dependencies updated"

  # Show major version changes
  info "Checking for major version changes..."
  git --no-pager diff Cargo.lock 2> /dev/null | grep -E "^[\+\-]version = " | head -20 || true
}

update_npm() {
  local upgrade_mode=${1:-false}

  if [[ $upgrade_mode == true ]]; then
    info "Upgrading npm dependencies (will update package.json versions)..."
  else
    info "Updating npm dependencies (lock file only)..."
  fi

  if [[ ! -d "gui" ]]; then
    error "gui directory not found"
    return 1
  fi

  if ! command -v npm &> /dev/null; then
    warn "npm not found in PATH, trying via nix develop..."
    if ! nix develop -c npm --version &> /dev/null; then
      error "npm is not available"
      return 1
    fi
    NPM_CMD="nix develop -c npm"
  else
    NPM_CMD="npm"
  fi

  cd gui

  if [[ $upgrade_mode == true ]]; then
    warn "⚠️  UPGRADE MODE: This will modify package.json!"
    info "Running npm upgrade (upgrades package.json to latest within semver ranges)..."
    $NPM_CMD upgrade

    # Show what packages have newer versions available
    info "Checking for packages with newer major versions available..."
    $NPM_CMD outdated || true
  else
    # Update npm dependencies (lock file only)
    info "Updating package-lock.json..."
    $NPM_CMD update

    # Check for outdated packages
    info "Checking for outdated packages..."
    $NPM_CMD outdated || true
  fi

  cd ..

  success "npm dependencies updated"

  # Update npm hash in Nix if needed
  info "Updating npm dependencies hash in Nix..."
  update_npm_hash
}

update_npm_hash() {
  if ! command -v nix &> /dev/null; then
    warn "Nix not available, skipping npm hash update"
    return 0
  fi

  info "Computing new npm dependencies hash..."

  # Path to the Nix file containing the npmDeps hash
  NIX_FILE="packages/gp-gui/default.nix"

  if [[ ! -f $NIX_FILE ]]; then
    error "Cannot find $NIX_FILE"
    return 1
  fi

  # Get current hash from packages/gp-gui/default.nix
  CURRENT_HASH=$(grep -oP 'hash = "\K[^"]+' "$NIX_FILE" | head -1 || echo "")

  if [[ -z $CURRENT_HASH ]]; then
    warn "Could not find current npm hash in $NIX_FILE"
    return 0
  fi

  info "Current npm hash: $CURRENT_HASH"

  # Set a fake hash to force a rebuild
  FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
  sed -i "s|hash = \"$CURRENT_HASH\"|hash = \"$FAKE_HASH\"|g" "$NIX_FILE"

  # Try to build and capture the hash mismatch error
  info "Building to determine correct hash..."
  BUILD_OUTPUT=$(nix build .#gp-gui --no-link 2>&1 || true)

  # Extract the "got:" hash from the error message
  NEW_HASH=$(echo "$BUILD_OUTPUT" | grep -oP 'got:\s+\K(sha256-[A-Za-z0-9+/=]+)' | head -1)

  if [[ -z $NEW_HASH ]]; then
    # Restore original hash if we couldn't determine the new one
    warn "Could not determine new hash, restoring original"
    sed -i "s|hash = \"$FAKE_HASH\"|hash = \"$CURRENT_HASH\"|g" "$NIX_FILE"
    return 0
  fi

  if [[ $CURRENT_HASH != "$NEW_HASH" ]]; then
    info "npm hash changed:"
    info "  Old: $CURRENT_HASH"
    info "  New: $NEW_HASH"

    # Update to the correct hash
    sed -i "s|hash = \"$FAKE_HASH\"|hash = \"$NEW_HASH\"|g" "$NIX_FILE"
    success "Updated npm hash in $NIX_FILE"

    # Verify the fix worked
    info "Verifying npm hash fix..."
    if nix build .#gp-gui --no-link 2>&1 | grep -q "hash mismatch\|ERROR: npmDepsHash"; then
      error "Hash update failed - manual intervention required"
      return 1
    else
      success "npm hash verified successfully"
    fi
  else
    # Hash unchanged, restore it
    sed -i "s|hash = \"$FAKE_HASH\"|hash = \"$CURRENT_HASH\"|g" "$NIX_FILE"
    info "npm hash unchanged"
  fi
}

verify_updates() {
  info "Verifying updates..."

  # Check if nix build still works
  if command -v nix &> /dev/null; then
    info "Testing Nix build..."
    if nix build .#gp-gui --dry-run 2>&1 | grep -q "error:"; then
      warn "Nix build dry-run reported errors"
    else
      success "Nix build verification passed"
    fi
  fi

  # Run flake checks
  if command -v nix &> /dev/null; then
    info "Running flake checks..."
    if nix flake check --no-build 2>&1 | grep -q "error:"; then
      warn "Flake check reported errors"
    else
      success "Flake check passed"
    fi
  fi
}

show_summary() {
  echo ""
  info "Update Summary:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Show git status
  if git diff --quiet; then
    info "No changes detected"
  else
    info "Changed files:"
    git status --short | grep -E "^\s*M\s+" | awk '{print "  - " $2}'
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  info "Next steps:"
  echo "  1. Review changes: git diff"
  echo "  2. Test build: nix build .#gp-gui"
  echo "  3. Run checks: nix flake check"
  echo "  4. Commit: git add -A && git commit -m 'chore: update dependencies'"
}

main() {
  local update_all=true
  local update_nix_only=false
  local update_cargo_only=false
  local update_npm_only=false
  local upgrade_mode=false

  # Parse arguments
  for arg in "$@"; do
    case $arg in
    --all)
      update_all=true
      ;;
    --nix)
      update_all=false
      update_nix_only=true
      ;;
    --cargo)
      update_all=false
      update_cargo_only=true
      ;;
    --npm)
      update_all=false
      update_npm_only=true
      ;;
    --upgrade)
      upgrade_mode=true
      ;;
    --help | -h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Update gp-gui dependencies"
      echo ""
      echo "Options:"
      echo "  --all       Update all dependencies (default)"
      echo "  --nix       Update only Nix flake inputs"
      echo "  --cargo     Update only Cargo dependencies"
      echo "  --npm       Update only npm dependencies"
      echo "  --upgrade   Upgrade source dependencies (Cargo.toml, package.json)"
      echo "              to latest compatible versions (potentially breaking)"
      echo "  --help      Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                    # Update all lock files"
      echo "  $0 --upgrade          # Upgrade source dependencies + update locks"
      echo "  $0 --cargo            # Update only Cargo.lock"
      echo "  $0 --cargo --upgrade  # Upgrade Cargo.toml + update Cargo.lock"
      echo ""
      echo "Notes:"
      echo "  - Without --upgrade: Only updates lock files (safe, no breaking changes)"
      echo "  - With --upgrade: Updates version constraints in source files"
      echo "    (may introduce breaking changes, requires testing)"
      exit 0
      ;;
    *)
      error "Unknown option: $arg"
      echo "Use --help for usage information"
      exit 1
      ;;
    esac
  done

  echo ""
  echo "╔════════════════════════════════════════════════════╗"
  echo "║        gp-gui Dependency Update Script           ║"
  echo "╚════════════════════════════════════════════════════╝"
  echo ""

  if [[ $upgrade_mode == true ]]; then
    warn "⚠️  UPGRADE MODE ENABLED"
    warn "This will modify source files (Cargo.toml, package.json)"
    warn "and may introduce breaking changes!"
    warn "Please review all changes and test thoroughly before committing."
    echo ""
  fi

  # Execute updates based on flags
  if [[ $update_all == true ]]; then
    update_nix || warn "Nix update failed"
    echo ""
    update_cargo "$upgrade_mode" || warn "Cargo update failed"
    echo ""
    update_npm "$upgrade_mode" || warn "npm update failed"
  else
    [[ $update_nix_only == true ]] && update_nix
    [[ $update_cargo_only == true ]] && update_cargo "$upgrade_mode"
    [[ $update_npm_only == true ]] && update_npm "$upgrade_mode"
  fi

  echo ""
  verify_updates

  echo ""
  show_summary

  if [[ $upgrade_mode == true ]]; then
    echo ""
    warn "⚠️  REMINDER: UPGRADE MODE was used"
    warn "Please carefully review ALL changes and run full test suite!"
  fi
}

# Run main function
main "$@"
