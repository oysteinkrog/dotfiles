#!/usr/bin/env bash
# install-toolchain.sh — audit + propose install one-liners for toolchain
#
# Usage:
#   ./install-toolchain.sh --check <audit-dir>
#       Detect installed/missing tools; write phase0_toolchain.json. No prompts.
#
#   ./install-toolchain.sh <audit-dir>
#       Detect, then if any tools are missing, interactively prompt
#       "Install missing tools now? [y/N]" on a TTY.
#
#   ./install-toolchain.sh --install-confirmed <audit-dir>
#       Detect, then install all missing tools without prompting. Logs each
#       install to <audit-dir>/phase0/installs.log. Use ONLY when the caller
#       (typically a coding agent) has already obtained per-tool user
#       confirmation through its normal user-input mechanism.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

CHECK_ONLY=false
INSTALL_CONFIRMED=false
while [ $# -gt 0 ]; do
  case "$1" in
    --check)
      CHECK_ONLY=true
      shift
      ;;
    --install-confirmed)
      # Bypass the interactive prompt. Use ONLY when the caller (typically a
      # coding agent) has already obtained per-tool user confirmation through
      # its normal user-input mechanism. Each install is still logged. Don't
      # combine with --check.
      INSTALL_CONFIRMED=true
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "error: unknown flag: $1" >&2
      echo "usage: install-toolchain.sh [--check | --install-confirmed] <audit-dir>" >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if $CHECK_ONLY && $INSTALL_CONFIRMED; then
  echo "error: --check and --install-confirmed are mutually exclusive" >&2
  exit 2
fi

AUDIT_DIR="${1:-.}"
AUDIT_DIR=$(audit_realpath "$AUDIT_DIR")
PROJECT_ROOT=$(audit_project_root_from_dir "$AUDIT_DIR")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT_ROOT")
mkdir -p "$AUDIT_DIR"

OUT="$AUDIT_DIR/phase0_toolchain.json"

check_tool() {
  local name="$1"
  local cmd="$2"
  local install_oneliner="$3"
  local installed=false
  local version=""

  if eval "$cmd" >/dev/null 2>&1; then
    installed=true
    version=$(eval "$cmd" 2>&1 | head -1 | tr -d '\r' || true)
  fi

  # Use jq to construct the row — it handles quote/backslash/control-char escaping.
  if $installed; then
    jq -nc --arg name "$name" --arg version "$version" \
      '{name: $name, installed: true, version: $version}' \
      | sed 's/^/    /'
  else
    jq -nc --arg name "$name" --arg install_cmd "$install_oneliner" \
      '{name: $name, installed: false, install_cmd: $install_cmd}' \
      | sed 's/^/    /'
  fi
}

# Header — use jq for safe escaping
{
  printf '{\n'
  jq -nc --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         --arg rustc_version "$(rustc --version 2>/dev/null || echo 'not-installed')" \
         --arg rustc_nightly_version "$(rustc +nightly --version 2>/dev/null || echo 'not-installed')" \
         '{checked_at: $checked_at, rustc_version: $rustc_version, rustc_nightly_version: $rustc_nightly_version}' \
    | jq -r 'to_entries[] | "  \"\(.key)\": \(.value | @json),"'
  printf '  "tools": [\n'
} > "$OUT"

# Inline list. Indent + comma handled below.
TOOLS=$(cat <<'EOF'
ast-grep|ast-grep --version|cargo install ast-grep --locked
cargo-geiger|cargo +nightly geiger --version|cargo +nightly install --locked cargo-geiger
cargo-careful|cargo +nightly careful --version|cargo +nightly install cargo-careful
cargo-expand|cargo expand --version|cargo install cargo-expand --locked
cargo-fuzz|cargo +nightly fuzz --version|cargo install cargo-fuzz --locked
cargo-mutants|cargo mutants --version|cargo install --locked cargo-mutants
cargo-flamegraph|flamegraph --version|cargo install flamegraph --locked
hyperfine|hyperfine --version|cargo install --locked hyperfine
miri|cargo +nightly miri --version|rustup +nightly component add miri rust-src
nightly-toolchain|rustup +nightly --version|rustup toolchain install nightly
jq|jq --version|sudo apt install jq  # or brew install jq
EOF
)

n=$(echo "$TOOLS" | wc -l | tr -d ' ')
i=0
while IFS='|' read -r name cmd install; do
  i=$((i+1))
  check_tool "$name" "$cmd" "$install" >> "$OUT"
  if [ "$i" -lt "$n" ]; then printf ',\n' >> "$OUT"; else printf '\n' >> "$OUT"; fi
done <<< "$TOOLS"

printf '  ]\n' >> "$OUT"
printf '}\n' >> "$OUT"

echo "Toolchain inventory written to $OUT"
echo
jq -r '.tools[] | select(.installed == false) | "[MISSING] \(.name) — install: \(.install_cmd)"' "$OUT" || true

if $CHECK_ONLY; then
  exit 0
fi

# Propose installs (interactive or pre-authorized)
MISSING_COUNT=$(jq -r '[.tools[] | select(.installed == false)] | length' "$OUT")
if [ "$MISSING_COUNT" -gt 0 ]; then
  echo

  # If pre-authorized via --install-confirmed (typically by a coding agent that
  # already obtained per-tool user confirmation), skip the prompt.
  if $INSTALL_CONFIRMED; then
    ANS="y"
    echo "Running installs (--install-confirmed; caller asserts user authorization)..."
  else
    if [ -t 0 ]; then
      if ! read -r -p "Install missing tools now? [y/N] " ANS; then
        echo "Skipping install. Run again with --check to refresh status."
        exit 0
      fi
    elif { true </dev/tty; } 2>/dev/null; then
      if ! read -r -p "Install missing tools now? [y/N] " ANS </dev/tty; then
        echo "Skipping install. Run again with --check to refresh status."
        exit 0
      fi
    else
      echo "No interactive tty available. Skipping install; run with --install-confirmed"
      echo "(after obtaining user authorization) to perform installs non-interactively."
      exit 0
    fi
  fi

  case "$ANS" in
    y|Y|yes|Yes)
      LOG_DIR="$AUDIT_DIR/phase0"
      mkdir -p "$LOG_DIR"
      INSTALL_LOG="$LOG_DIR/installs.log"
      printf '%s install run started at %s\n' "===" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$INSTALL_LOG"
      jq -r '.tools[] | select(.installed == false) | .install_cmd' "$OUT" | while read -r cmd; do
        echo "==> $cmd"
        printf '\n==> %s\n' "$cmd" >> "$INSTALL_LOG"
        if eval "$cmd" 2>&1 | tee -a "$INSTALL_LOG"; then
          printf '    [OK]\n' >> "$INSTALL_LOG"
        else
          rc=$?
          printf '    [FAILED exit=%s]\n' "$rc" >> "$INSTALL_LOG"
          echo "failed: $cmd"
        fi
      done
      printf '%s install run finished at %s\n' "===" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$INSTALL_LOG"
      "$0" --check "$AUDIT_DIR"
      ;;
    *) echo "Skipping install. Run again with --check to refresh status." ;;
  esac
fi
