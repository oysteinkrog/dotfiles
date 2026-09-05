#!/bin/bash
# Check dependencies for video-obs-youtube-music skill

set -euo pipefail

errors=0

install_cmd() {
    if command -v apt-get >/dev/null 2>&1; then
        printf 'sudo apt-get install'
    elif command -v brew >/dev/null 2>&1; then
        printf 'brew install'
    elif command -v dnf >/dev/null 2>&1; then
        printf 'sudo dnf install'
    else
        printf '[your package manager] install'
    fi
}

check_cmd() {
    local version
    local version_output
    if ! command -v "$1" &>/dev/null; then
        echo "❌ Missing: $1"
        errors=$((errors + 1))
    else
        version_output=$("$1" --version 2>&1 || true)
        version=$(printf '%s\n' "$version_output" | sed -n '1p')
        echo "✓ $1: $version"
    fi
}

echo "=== video-obs-youtube-music dependencies ==="
echo
check_cmd ffmpeg
check_cmd ffprobe
check_cmd yt-dlp

# Check playwright (optional, for card generation)
echo
echo "=== Optional (for song credit cards) ==="

# Check node (optional - don't increment errors)
if command -v node &>/dev/null; then
    version=$(node --version 2>&1)
    echo "✓ node: $version"

    # Playwright may be available via npx even when require() fails outside a project directory.
    if node -e "require.resolve('playwright/package.json')" 2>/dev/null \
        || npx --no-install playwright --version >/dev/null 2>&1; then
        echo "✓ playwright: installed"
    else
        echo "⚠ playwright: not installed (optional)"
        echo "  Install: npm install playwright && npx playwright install chromium"
    fi
else
    echo "⚠ node: not installed (optional)"
    echo "  Install: $(install_cmd) node"
    echo "  Then: npm install playwright && npx playwright install chromium"
fi

echo
if [ $errors -eq 0 ]; then
    echo "✓ All core dependencies installed"
    exit 0
else
    echo "❌ Missing $errors core dependencies"
    echo "Install: $(install_cmd) ffmpeg yt-dlp"
    exit 1
fi
