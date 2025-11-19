#!/usr/bin/env bash
# Update all package dependencies for gp-gui
#
# This script updates:
# - Nix flake inputs (flake.lock)
# - Cargo dependencies (Cargo.lock)
# - npm dependencies (package-lock.json)
#
# Usage: ./scripts/update-deps.sh [--all|--nix|--cargo|--npm]

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
  git diff --no-pager flake.lock | grep -E "^\+.*\"(narHash|rev)\"" | head -20 || true
}

update_cargo() {
  info "Updating Cargo dependencies..."

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

  # Update workspace dependencies
  info "Updating workspace Cargo.lock..."
  $CARGO_CMD update --workspace

  # Update Tauri-specific dependencies
  info "Updating gui/src-tauri dependencies..."
  (cd gui/src-tauri && $CARGO_CMD update)

  success "Cargo dependencies updated"

  # Show major version changes
  info "Checking for major version changes..."
  git diff --no-pager Cargo.lock gui/src-tauri/Cargo.lock | grep -E "^[\+\-]version = " | head -20 || true
}

update_npm() {
  info "Updating npm dependencies..."

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

  # Update npm dependencies
  info "Updating package-lock.json..."
  $NPM_CMD update

  # Check for outdated packages
  info "Checking for outdated packages..."
  $NPM_CMD outdated || true

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

  # Get current hash from packages/gp-gui/default.nix
  CURRENT_HASH=$(grep -oP 'hash = "\K[^"]+' packages/gp-gui/default.nix | head -1 || echo "")

  if [[ -z $CURRENT_HASH ]]; then
    warn "Could not find current npm hash in packages/gp-gui/default.nix"
    return 0
  fi

  # Try to build npm-deps and capture the hash mismatch error
  # The error will contain the expected hash
  info "Building npm-deps to get correct hash..."
  BUILD_OUTPUT=$(nix build .#gp-gui-deps 2>&1 || true)

  # Extract the "got:" hash from the error message
  NEW_HASH=$(echo "$BUILD_OUTPUT" | grep -oP 'got:\s+\K(sha256-[A-Za-z0-9+/=]+)' | head -1)

  if [[ -z $NEW_HASH ]]; then
    # If no hash mismatch, dependencies haven't changed
    info "npm dependencies hash unchanged"
    return 0
  fi

  if [[ $CURRENT_HASH != "$NEW_HASH" ]]; then
    info "npm hash changed:"
    info "  Old: $CURRENT_HASH"
    info "  New: $NEW_HASH"

    # Update the hash in default.nix
    if [[ -f "packages/gp-gui/default.nix" ]]; then
      sed -i "s|hash = \"$CURRENT_HASH\"|hash = \"$NEW_HASH\"|g" packages/gp-gui/default.nix
      success "Updated npm hash in packages/gp-gui/default.nix"

      # Verify the fix worked
      info "Verifying npm hash fix..."
      if nix build .#gp-gui-deps --no-link 2>&1 | grep -q "hash mismatch"; then
        error "Hash update failed - please check manually"
        return 1
      else
        success "npm hash verified successfully"
      fi
    fi
  else
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
    --help | -h)
      echo "Usage: $0 [--all|--nix|--cargo|--npm]"
      echo ""
      echo "Options:"
      echo "  --all     Update all dependencies (default)"
      echo "  --nix     Update only Nix flake inputs"
      echo "  --cargo   Update only Cargo dependencies"
      echo "  --npm     Update only npm dependencies"
      echo "  --help    Show this help message"
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

  # Execute updates based on flags
  if [[ $update_all == true ]]; then
    update_nix || warn "Nix update failed"
    echo ""
    update_cargo || warn "Cargo update failed"
    echo ""
    update_npm || warn "npm update failed"
  else
    [[ $update_nix_only == true ]] && update_nix
    [[ $update_cargo_only == true ]] && update_cargo
    [[ $update_npm_only == true ]] && update_npm
  fi

  echo ""
  verify_updates

  echo ""
  show_summary
}

# Run main function
main "$@"
