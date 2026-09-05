#!/usr/bin/env bash
# detect-mode.sh — auto-detect Mode Router heuristic
# Usage: ./detect-mode.sh <project-path>
# Emits a recommended mode + reasoning to stdout.

set -euo pipefail
PROJECT="${1:?usage: detect-mode.sh <project-path>}"

cd "$PROJECT"

REASONING=()
MODE=""

# Check for explicit signals

# forbid(unsafe_code) at crate root → forbid-soundness mode
FORBID_DETECTED=false
for f in src/lib.rs src/main.rs */src/lib.rs */src/main.rs; do
  if [ -f "$f" ] && grep -qE '^[[:space:]]*#!\[forbid\(unsafe_code\)\]' "$f" 2>/dev/null; then
    FORBID_DETECTED=true
    break
  fi
done
if $FORBID_DETECTED; then
  MODE="forbid-soundness"
  REASONING+=("Top-level #![forbid(unsafe_code)] detected — audit shifts to dep-side + forbid-consistency")
fi

if git log --oneline -20 2>/dev/null | grep -iE 'CVE|incident|security advisory|emergency fix' >/dev/null; then
  # incident overrides forbid-soundness if recent
  MODE="harden-incident"
  REASONING+=("Recent commits reference incident/CVE")
fi

safe_only_cfg_present() {
  local f
  while IFS= read -r -d '' f; do
    if grep -qE '#\[cfg\(feature.*safe-only' "$f"; then
      return 0
    fi
  done < <(find . \
    -path './.git' -prune -o \
    -path './.unsafe-audit*' -prune -o \
    -path './.ub-exorcism' -prune -o \
    -path './target' -prune -o \
    -path '*/src/*.rs' -type f -print0)
  return 1
}

if grep -qE 'safe-only|no-unsafe|no_unsafe' Cargo.toml ./*/Cargo.toml 2>/dev/null; then
  # Already has the feature — check if it's complete
  if safe_only_cfg_present; then
    MODE="${MODE:-verify-only}"
    REASONING+=("safe-only feature already exists; assume prior audit ratified")
  else
    MODE="${MODE:-dual-feature-migration}"
    REASONING+=("safe-only feature declared but not used; migration incomplete")
  fi
fi

# Library vs binary
if grep -qE '^[[:space:]]*\[lib\][[:space:]]*(#.*)?$' Cargo.toml 2>/dev/null || [ -f src/lib.rs ]; then
  IS_LIB=true
else
  IS_LIB=false
fi

# Geiger count (if available). Normalize "null"/empty to 0 so arithmetic comparisons work.
GEIGER_COUNT=0
if command -v cargo-geiger >/dev/null 2>&1; then
  raw=$(cargo +nightly geiger --output-format Json 2>/dev/null | \
        jq '[.packages[]?.package.metrics.counters | objects | .[] | numbers] | add // 0' \
        2>/dev/null || echo 0)
  case "$raw" in
    ''|null) GEIGER_COUNT=0 ;;
    *)       GEIGER_COUNT=$raw ;;
  esac
fi

# Heavy deps? (grep -c always outputs a number; use `|| true` so non-match exit-1 doesn't poison the value)
HEAVY_DEPS=$(cargo tree --depth 1 2>/dev/null | grep -cE 'libc|nix|rustix|windows-sys|bindgen|core-foundation' || true)
HEAVY_DEPS=${HEAVY_DEPS:-0}
GIT_AVAILABLE=false
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_AVAILABLE=true
fi
FIRST_GIT_TAG=$(git tag -l 2>/dev/null | head -1 || true)

# Decision tree
if [ -z "$MODE" ]; then
  if $IS_LIB && [ -z "$FIRST_GIT_TAG" ]; then
    MODE="audit-only"
    if $GIT_AVAILABLE; then
      REASONING+=("Library crate; no Git release tags detected")
    else
      REASONING+=("Library crate; Git release-tag status unavailable")
    fi
  elif $IS_LIB && [ -n "$FIRST_GIT_TAG" ]; then
    MODE="audit-only"
    REASONING+=("Library crate with Git release tags — consider pre-release-soundness-gate before next release")
  elif [ "$HEAVY_DEPS" -gt 2 ]; then
    MODE="dependency-soundness"
    REASONING+=("$HEAVY_DEPS FFI-heavy deps in cargo tree depth 1")
  elif [ "$GEIGER_COUNT" -gt 100 ]; then
    MODE="audit-only"
    REASONING+=("Geiger count = $GEIGER_COUNT — substantial unsafe surface")
  else
    MODE="audit-only"
    REASONING+=("Default")
  fi
fi

# Emit
echo "Recommended mode: $MODE"
echo
echo "Reasoning:"
for r in "${REASONING[@]}"; do
  echo "  - $r"
done
echo
echo "Stats:"
echo "  - Library crate: $IS_LIB"
echo "  - Geiger count: $GEIGER_COUNT"
echo "  - FFI-heavy deps: $HEAVY_DEPS"
RECENT_GIT=$(git log --oneline -3 2>/dev/null | head -3 || true)
if [ -n "$RECENT_GIT" ]; then
  echo "  - Recent git:"
  while IFS= read -r line; do
    echo "      $line"
  done <<< "$RECENT_GIT"
else
  echo "  - Recent git: unavailable"
fi
