#!/usr/bin/env bash
# install-toolchain.sh — Verify and (with permission) install the full
# FrankenSQLite-class gauntlet toolchain. Idempotent. Per-tool report to stdout
# (human view) and JSON ledger to <workspace>/phase0_toolchain_inventory.json
# (machine view).
#
# USAGE:
#   install-toolchain.sh [--workspace <dir>] [--yes] [--dry-run]
#
# OUTPUTS:
#   stdout: human-readable green/yellow/red verdict per tool.
#   <workspace>/phase0_toolchain_inventory.json (if --workspace provided)
#
# EXIT CODES:
#   0 — no red blockers (yellow entries may remain as advisory/manual installs)
#   1 — at least one tool red (missing AND user declined / --dry-run)
#   2 — usage error
#
# IDEMPOTENT: skips installation when the tool is already present.

set -euo pipefail

WORKSPACE=""
ASSUME_YES=0
DRY_RUN=0

usage() {
  sed -n '2,16p' "$0"
  exit "${1:-2}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2;;
    --yes|-y)    ASSUME_YES=1; shift;;
    --dry-run)   DRY_RUN=1; shift;;
    -h|--help)   usage 0;;
    *) echo "Unknown arg: $1" >&2; usage;;
  esac
done

OUT_JSON=""
if [ -n "$WORKSPACE" ]; then
  mkdir -p "$WORKSPACE"
  OUT_JSON="$WORKSPACE/phase0_toolchain_inventory.json"
fi

declare -a TOOL_NAMES=()
declare -a TOOL_STATUS=()
declare -a TOOL_DETAIL=()

confirm() {
  local prompt="$1"
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  if [ "$DRY_RUN" -eq 1 ]; then return 1; fi
  # Skip interactive prompt if stdin is not a TTY (CI, piped invocation, agent
  # dispatch). Default to NO; the operator can re-run with --yes to install
  # everything in one shot.
  if [ ! -t 0 ]; then
    printf "%s [skipped: non-interactive stdin; re-run with --yes to install]\n" "$prompt" >&2
    return 1
  fi
  printf "%s [y/N]: " "$prompt" >&2
  read -r reply
  case "$reply" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

record() {
  TOOL_NAMES+=("$1")
  TOOL_STATUS+=("$2")
  TOOL_DETAIL+=("${3:-}")
}

# ---- Probes ----------------------------------------------------------------
probe_cmd() {
  local name="$1" cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    local v
    v="$($cmd --version 2>&1 | head -1 || true)"
    record "$name" "green" "$v"
    return 0
  fi
  return 1
}

probe_rustup_component() {
  local comp="$1" toolchain="${2:-nightly}"
  if rustup component list --installed --toolchain "$toolchain" 2>/dev/null | grep -Eq "^${comp}($|-)"; then
    record "rustup:$comp" "green" "toolchain=$toolchain"
    return 0
  fi
  return 1
}

probe_cargo_subcmd() {
  local subcmd="$1"
  if cargo "$subcmd" --version >/dev/null 2>&1 || cargo "$subcmd" --help >/dev/null 2>&1; then
    record "cargo-$subcmd" "green" "$(cargo "$subcmd" --version 2>&1 | head -1 || echo present)"
    return 0
  fi
  return 1
}

# ---- rustup + nightly + components ----------------------------------------
if ! probe_cmd "rustup" "rustup"; then
  if confirm "Install rustup via https://sh.rustup.rs?"; then
    [ "$DRY_RUN" -eq 1 ] || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    record "rustup" "yellow" "installed (re-run shell to pick up PATH)"
  else
    record "rustup" "red" "missing"
  fi
fi

if command -v rustup >/dev/null 2>&1; then
  if ! rustup toolchain list 2>/dev/null | grep -q '^nightly'; then
    if confirm "Install nightly toolchain?"; then
      [ "$DRY_RUN" -eq 1 ] || rustup toolchain install nightly
    fi
  fi
  if rustup toolchain list 2>/dev/null | grep -q '^nightly'; then
    record "toolchain:nightly" "green" "$(rustup run nightly rustc --version 2>/dev/null || echo present)"
  else
    record "toolchain:nightly" "red" "missing"
  fi

  for comp in miri rust-src; do
    if ! probe_rustup_component "$comp" nightly; then
      if confirm "Add nightly component '$comp'?"; then
        [ "$DRY_RUN" -eq 1 ] || rustup component add "$comp" --toolchain nightly || true
      fi
      probe_rustup_component "$comp" nightly || record "rustup:$comp" "red" "missing"
    fi
  done
fi

# ---- cargo subcommands -----------------------------------------------------
CARGO_TOOLS=(
  cargo-criterion cargo-flamegraph cargo-show-asm cargo-fuzz cargo-afl
  cargo-llvm-cov cargo-geiger cargo-audit cargo-deny cargo-expand cargo-insta
)
for tool in "${CARGO_TOOLS[@]}"; do
  sub="${tool#cargo-}"
  if probe_cargo_subcmd "$sub"; then continue; fi
  if confirm "Install $tool via 'cargo install --locked $tool'?"; then
    [ "$DRY_RUN" -eq 1 ] || cargo install --locked "$tool" || record "$tool" "red" "install failed"
  fi
  probe_cargo_subcmd "$sub" || record "$tool" "red" "missing"
done

# ---- system tools ----------------------------------------------------------
for sys in hyperfine samply ast-grep heaptrack strace; do
  probe_cmd "$sys" "$sys" || record "$sys" "yellow" "missing — install via pkg manager"
done

# semgrep via pip
if ! probe_cmd "semgrep" "semgrep"; then
  if confirm "Install semgrep via 'pip install --user semgrep'?"; then
    [ "$DRY_RUN" -eq 1 ] || python3 -m pip install --user semgrep || record "semgrep" "red" "install failed"
  fi
  probe_cmd "semgrep" "semgrep" || record "semgrep" "yellow" "missing"
fi

# ---- dev-dep notes (informational, no install) ----------------------------
record "dev-dep:dhat-rs"  "yellow" "add to target Cargo.toml [dev-dependencies] dhat = \"0.3\""
record "dev-dep:loom"     "yellow" "add to target Cargo.toml [dev-dependencies] loom = \"0.7\""
record "dev-dep:shuttle"  "yellow" "add to target Cargo.toml [dev-dependencies] shuttle = \"0.7\""

# ---- emit human report -----------------------------------------------------
RED=0
echo
echo "================ Toolchain Inventory ================"
for i in "${!TOOL_NAMES[@]}"; do
  printf "  %-30s [%-6s] %s\n" "${TOOL_NAMES[$i]}" "${TOOL_STATUS[$i]}" "${TOOL_DETAIL[$i]}"
  [ "${TOOL_STATUS[$i]}" = "red" ] && RED=$((RED+1))
done
echo "====================================================="
echo "RED count: $RED"

# ---- emit machine JSON -----------------------------------------------------
if [ -n "$OUT_JSON" ]; then
  {
    printf '{\n'
    printf '  "schema_version": "gauntlet.phase0_toolchain_inventory.v1",\n'
    printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "red_count": %d,\n' "$RED"
    printf '  "tools": [\n'
    for i in "${!TOOL_NAMES[@]}"; do
      sep=","; [ "$i" -eq $((${#TOOL_NAMES[@]} - 1)) ] && sep=""
      # JSON-escape detail (best-effort): strip embedded quotes/backslashes
      detail_esc="$(printf '%s' "${TOOL_DETAIL[$i]}" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      printf '    {"name": "%s", "status": "%s", "detail": "%s"}%s\n' \
        "${TOOL_NAMES[$i]}" "${TOOL_STATUS[$i]}" "$detail_esc" "$sep"
    done
    printf '  ]\n'
    printf '}\n'
  } > "$OUT_JSON"
  echo "Wrote $OUT_JSON"
fi

[ "$RED" -eq 0 ] || exit 1
