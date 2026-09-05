#!/usr/bin/env bash
# Build optimized ripgrep with PCRE2 support
# Usage: ./build-optimized-rg.sh [install-path]
#
# Default install: ~/.cargo/bin/rg
# Requires: git, cargo (nightly), libpcre2-dev, pkg-config

set -euo pipefail

INSTALL_PATH="${1:-$HOME/.cargo/bin/rg}"
BUILD_DIR=$(mktemp -d /tmp/rg-build.XXXXXX)

info() { echo -e "\033[1;34m==>\033[0m $1"; }
success() { echo -e "\033[1;32m==>\033[0m $1"; }
error() { echo -e "\033[1;31m==>\033[0m $1" >&2; exit 1; }

cleanup() {
    if [[ -d "$BUILD_DIR" ]]; then
        info "Build directory retained for diagnosis: $BUILD_DIR"
    fi
}
trap cleanup EXIT

# Check prerequisites
info "Checking prerequisites..."

command -v git >/dev/null 2>&1 || error "git not found"
command -v cargo >/dev/null 2>&1 || error "cargo not found"
command -v pkg-config >/dev/null 2>&1 || error "pkg-config not found (install: apt-get install pkg-config)"

# Check for PCRE2
if ! pkg-config --exists libpcre2-8 2>/dev/null; then
    error "libpcre2-dev not found. Install with:
    Ubuntu/Debian: sudo apt-get install libpcre2-dev
    Fedora/RHEL:   sudo dnf install pcre2-devel
    macOS:         brew install pcre2"
fi

# Check for nightly Rust
if ! rustc +nightly --version >/dev/null 2>&1; then
    info "Installing nightly Rust..."
    rustup install nightly
fi

RUST_VERSION=$(rustc +nightly --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
info "Using Rust nightly $RUST_VERSION"

# Clone ripgrep
info "Cloning ripgrep master branch..."
git clone --depth 1 https://github.com/BurntSushi/ripgrep.git "$BUILD_DIR"
cd "$BUILD_DIR"

# Build
info "Building with PCRE2 and LTO optimizations..."
info "  Profile: release-lto"
info "  Features: pcre2"
info "  RUSTFLAGS: -C target-cpu=native"

RUSTFLAGS="-C target-cpu=native" cargo +nightly build --profile release-lto --features pcre2

# Find binary
TARGET_DIR=$(cargo metadata --format-version 1 | grep -o '"target_directory":"[^"]*"' | cut -d'"' -f4)
RG_BIN="$TARGET_DIR/release-lto/rg"

if [[ ! -f "$RG_BIN" ]]; then
    error "Build succeeded but binary not found at: $RG_BIN"
fi

# Install
info "Installing to $INSTALL_PATH..."
mkdir -p "$(dirname "$INSTALL_PATH")"

staged_install=$(mktemp "$(dirname "$INSTALL_PATH")/.rg-install.XXXXXX")
cp "$RG_BIN" "$staged_install"
# mktemp creates 0600 files. Set an explicit installed-binary mode so shared
# locations such as /usr/local/bin do not end up with a private 0700 rg.
chmod 755 "$staged_install"

# Preserve the prior binary before swapping in the staged build. This avoids
# deleting a working rg if the install path is busy or the final move fails.
backup_path=""
if [[ -f "$INSTALL_PATH" ]]; then
    backup_path="${INSTALL_PATH}.old.$(date -u +%Y%m%dT%H%M%SZ)"
    info "Preserving existing binary at $backup_path"
    mv "$INSTALL_PATH" "$backup_path" || error "could not move existing binary to backup: $backup_path"
fi

if ! mv "$staged_install" "$INSTALL_PATH"; then
    if [[ -n "$backup_path" && -f "$backup_path" && ! -e "$INSTALL_PATH" ]]; then
        mv "$backup_path" "$INSTALL_PATH" || true
    fi
    error "could not install staged binary to: $INSTALL_PATH"
fi

# Verify
info "Verifying installation..."
version_out=$("$INSTALL_PATH" --version)
printf '%s\n' "$version_out"

# Check PCRE2
if grep -q "features:+pcre2" <<<"$version_out"; then
    success "PCRE2 support verified!"
else
    error "PCRE2 support not enabled in build"
fi

# Test PCRE2 functionality
# shellcheck disable=SC2016
if echo '$100' | "$INSTALL_PATH" -Po '(?<=\$)\d+' | grep -q '100'; then
    success "PCRE2 lookbehind test passed!"
else
    error "PCRE2 functionality test failed"
fi

success "Optimized ripgrep installed successfully to: $INSTALL_PATH"
echo
info "Binary size: $(du -h "$INSTALL_PATH" | cut -f1)"
echo
info "Test it with: $INSTALL_PATH -P '(?<=pattern)text' file.txt"
