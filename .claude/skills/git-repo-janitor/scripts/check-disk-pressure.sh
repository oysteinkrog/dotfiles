#!/usr/bin/env bash
# Pre-flight: check disk pressure before any large cleanup, especially batch mode.
# Halts (exit 1) if any /tmp bucket >5GB OR any mount point >85% full.
# Usage: check-disk-pressure.sh [--threshold-gb=5] [--threshold-pct=85]
set -euo pipefail

threshold_gb=5
threshold_pct=85
for arg in "$@"; do
    case "$arg" in
        --threshold-gb=*) threshold_gb="${arg#*=}" ;;
        --threshold-pct=*) threshold_pct="${arg#*=}" ;;
    esac
done

threshold_kb=$((threshold_gb * 1024 * 1024))
problems=0

echo "=== Mount point usage ==="
df -h / /tmp /var/tmp /home 2>/dev/null | awk 'NR==1 || /\/(tmp|var\/tmp|home)?$/ || $1 ~ /^\/dev/'

# Use `df -P` for POSIX single-line-per-FS output so wrapped filesystem names
# don't break the awk column references.
while IFS= read -r line; do
    mp=$(echo "$line" | awk '{print $6}')
    pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    [[ -z "$mp" ]] && continue
    [[ "$mp" == "Mounted" ]] && continue   # skip header
    [[ "$pct" =~ ^[0-9]+$ ]] || continue
    if (( pct > threshold_pct )); then
        echo "WARN: $mp at ${pct}% (threshold ${threshold_pct}%)"
        problems=$((problems + 1))
    fi
done < <(df -P / /tmp /var/tmp /home 2>/dev/null | tail -n +2)

echo ""
echo "=== Cache directory sizes ==="
caches=(
    /tmp/rch
    /tmp/cargo
    /tmp/cargo-target
    /tmp/sccache
    /tmp/uv-cache
    /tmp/.cargo-target
    "$HOME/.cargo/registry"
    "$HOME/.cargo/git"
    "$HOME/.cache/pip"
    "$HOME/.cache/yarn"
    "$HOME/.cache/pnpm"
    "$HOME/.cache/Cypress"
    "$HOME/.cache/puppeteer"
    "$HOME/.cache/playwright"
    "$HOME/.npm"
)

for cache in "${caches[@]}"; do
    if [[ -d "$cache" ]]; then
        size_kb=$(du -sk "$cache" 2>/dev/null | awk '{print $1}')
        size_human=$(du -sh "$cache" 2>/dev/null | awk '{print $1}')
        if [[ "$size_kb" -gt "$threshold_kb" ]]; then
            echo "WARN: $cache: $size_human (>$threshold_gb GB)"
            problems=$((problems + 1))
        else
            echo "OK:   $cache: $size_human"
        fi
    fi
done

echo ""
echo "=== /tmp largest entries ==="
du -sh /tmp/* 2>/dev/null | sort -rh | head -10

if [[ "$problems" -gt 0 ]]; then
	    echo ""
	    echo "$problems pressure issue(s) detected. Recommend cleanup before running batch cleanup."
	    echo "Common cleanups:"
	    echo "  Ask the user before removing any cache directory; do not run recursive deletes as an agent."
	    echo "  cargo cache --autoclean"
	    echo "  pip cache purge"
	    echo "  yarn cache clean"
    exit 1
fi

echo ""
echo "Disk pressure: PASS"
