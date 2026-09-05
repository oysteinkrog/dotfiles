#!/usr/bin/env bash
# install-toolchain.sh — detect + install the UB-exorcist toolchain.
#
# Modes:
#   <workspace>                       — interactive: detect, print, ask per-tool
#   <workspace> --yes                 — non-interactive: install EVERY missing tool
#                                       (blanket-approval mode; suitable when the
#                                       user has already given you authorization
#                                       like "auto-install whatever's missing")
#   <workspace> --inventory-only      — non-interactive: detect + print + write JSON,
#                                       install nothing (agent-friendly; safe to run
#                                       without a TTY)
#
# After every install attempt the script runs a per-tool SMOKE TEST (e.g.,
# `cargo +nightly miri --version 2>/dev/null` for miri) and records the result
# in the inventory JSON under `smoke_test_passed`. If the smoke test fails the
# tool is reported as "installed but unhealthy" and the orchestrator can react.
#
# <workspace> must be inside the audited source repo as .ub-exorcism/<run-id>/.
# Writes <workspace>/phase0_toolchain_inventory.json with a structured record
# in all three modes.
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

WORKSPACE="${1:-}"
if [[ -z "$WORKSPACE" ]]; then
    echo "Usage: $0 <workspace-dir> [--yes | --inventory-only]"
    exit 64
fi

canonicalize_workspace() {
    local workspace_real source_real
    workspace_real="$(realpath -m "$WORKSPACE")"
    case "$workspace_real" in
        */.ub-exorcism/*) ;;
        *)
            echo "Workspace must be inside the audited source repo: <source>/.ub-exorcism/<run-id>" >&2
            echo "Got: $workspace_real" >&2
            exit 64
            ;;
    esac
    source_real="${workspace_real%%/.ub-exorcism/*}"
    source_real="$(realpath -m "$source_real")"
    if [[ ! -f "$source_real/Cargo.toml" ]]; then
        echo "Workspace must be inside a Rust source repo: <source>/.ub-exorcism/<run-id>" >&2
        echo "Expected Cargo.toml at: $source_real/Cargo.toml" >&2
        echo "Got: $workspace_real" >&2
        exit 64
    fi
    case "$workspace_real/" in
        "$source_real"/.ub-exorcism/*) WORKSPACE="$workspace_real" ;;
        *)
            echo "Workspace must be inside the audited source repo: <source>/.ub-exorcism/<run-id>" >&2
            echo "Source: $source_real" >&2
            echo "Got:    $workspace_real" >&2
            exit 64
            ;;
    esac
}

canonicalize_workspace
mkdir -p "$WORKSPACE"
MODE="${2:-interactive}"
case "$MODE" in
    --yes)             ASSUME_YES=yes; INVENTORY_ONLY=no  ;;
    --inventory-only)  ASSUME_YES=no;  INVENTORY_ONLY=yes ;;
    interactive|"")    ASSUME_YES=no;  INVENTORY_ONLY=no  ;;
    *)
        echo "Unknown mode: $MODE (expected --yes or --inventory-only)" >&2
        exit 64
        ;;
esac

INVENTORY="$WORKSPACE/phase0_toolchain_inventory.json"

# ─────────────────────────────────────────────────────────────────────────────
# tool detection helpers
# ─────────────────────────────────────────────────────────────────────────────

declare -A STATUS=()
declare -A VERSION=()
declare -A INSTALL_HINT=()
declare -A SMOKE_OK=()         # "yes" / "no" / "skipped" / "untested"

have() { command -v "$1" >/dev/null 2>&1; }

# Per-tool smoke test. Returns 0 (ok) / 1 (broken) / 2 (no smoke defined).
# Add new smokes here as new tools land.
smoke_test() {
    local tool="$1"
    case "$tool" in
        rustup)
            rustup --version >/dev/null 2>&1
            ;;
        nightly)
            rustup run nightly rustc --version >/dev/null 2>&1
            ;;
        miri)
            # `cargo +nightly miri --version` must succeed; if `miri setup`
            # hasn't run, the first user invocation will trigger it lazily
            # but `--version` should still work.
            cargo +nightly miri --version >/dev/null 2>&1
            ;;
        rust_src)
            test -d "$(rustc +nightly --print sysroot)/lib/rustlib/src/rust/library/std" 2>/dev/null
            ;;
        cargo-fuzz)
            cargo +nightly fuzz --version >/dev/null 2>&1
            ;;
        cargo-afl)
            cargo afl --help >/dev/null 2>&1
            ;;
        cargo-geiger|cargo-audit|cargo-deny|cargo-expand)
            "$tool" --version >/dev/null 2>&1
            ;;
        ast-grep)
            ast-grep --version >/dev/null 2>&1
            ;;
        semgrep)
            semgrep --version >/dev/null 2>&1
            ;;
        br|bv|cass|ubs|rch|jsm|dcg|sbh|dsr|slb)
            "$tool" --version >/dev/null 2>&1
            ;;
        ntm)
            # ntm uses cobra; `--version` errors. Use `ntm version` subcommand.
            ntm version >/dev/null 2>&1
            ;;
        *)
            return 2
            ;;
    esac
}

record() {
    local key="$1" status="$2" version="${3:-}"
    STATUS["$key"]="$status"
    VERSION["$key"]="$version"
}

ask() {
    local prompt="$1"
    if [[ "$INVENTORY_ONLY" == "yes" ]]; then
        # Inventory-only mode: print what would be offered, never prompt.
        echo "  [inventory-only — skipping] $prompt"
        return 1
    fi
    if [[ "$ASSUME_YES" == "yes" ]]; then
        return 0
    fi
    # Interactive mode: read from /dev/tty so this works even if stdin is
    # redirected (e.g., `./install-toolchain.sh <workspace> < /dev/null` would
    # otherwise hang forever).
    if [[ ! -t 0 ]] && [[ ! -r /dev/tty ]]; then
        echo "  [no tty available — skipping] $prompt" >&2
        return 1
    fi
    read -r -p "$prompt [y/N] " ans </dev/tty
    [[ "$ans" =~ ^[Yy]$ ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# detect
# ─────────────────────────────────────────────────────────────────────────────

if have rustup; then
    record rustup ok "$(rustup --version 2>/dev/null | head -1)"
else
    record rustup missing ""
    INSTALL_HINT[rustup]="curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
fi

if rustup toolchain list 2>/dev/null | grep -q '^nightly'; then
    record nightly ok "$(rustup run nightly rustc --version 2>/dev/null || true)"
else
    record nightly missing ""
    INSTALL_HINT[nightly]="rustup toolchain install nightly"
fi

if rustup component list --toolchain nightly --installed 2>/dev/null | grep -q '^miri'; then
    record miri ok ""
else
    record miri missing ""
    INSTALL_HINT[miri]="rustup component add miri --toolchain nightly"
fi

if rustup component list --toolchain nightly --installed 2>/dev/null | grep -q '^rust-src'; then
    record rust_src ok ""
else
    record rust_src missing ""
    INSTALL_HINT[rust_src]="rustup component add rust-src --toolchain nightly"
fi

# optional tools — recommend but don't block
for crate in cargo-fuzz cargo-afl cargo-geiger cargo-audit cargo-deny cargo-expand ast-grep; do
    if have "$crate"; then
        record "$crate" ok "$($crate --version 2>/dev/null | head -1)"
    else
        record "$crate" missing ""
        INSTALL_HINT["$crate"]="cargo install $crate"
    fi
done

# semgrep is python-based
if have semgrep; then
    record semgrep ok "$(semgrep --version 2>/dev/null | head -1)"
else
    record semgrep missing ""
    INSTALL_HINT[semgrep]="pip install semgrep   # or: brew install semgrep"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Flywheel tools (author-controlled curl-bash one-liners)
#
# These tools are by Dicklesworthstone; one-liners come from
# https://github.com/Dicklesworthstone/curl_bash_one_liners_for_flywheel_tools
# Catalog mirrored in references/FLYWHEEL-TOOLS-INSTALL.md.
#
# Hard requirements: br, bv. Soft requirements: cass, ubs, rch, jsm, ntm.
# Recommended: dcg, sbh, dsr, slb.
# ─────────────────────────────────────────────────────────────────────────────

declare -A FLYWHEEL_HINT=(
    [br]='curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh?$(date +%s)" | bash'
    [bv]='curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh?$(date +%s)" | bash'
    [cass]='curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh?$(date +%s)" | bash -s -- --easy-mode --verify'
    [ubs]='curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/main/install.sh?$(date +%s)" | bash -s -- --easy-mode'
    [rch]='curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh?$(date +%s)" | bash -s -- --easy-mode'
    [jsm]='curl -fsSL "https://jeffreys-skills.md/install.sh?$(date +%s)" | bash'
    [ntm]='curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh?$(date +%s)" | bash -s -- --easy-mode'
    [dcg]='curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/master/install.sh?$(date +%s)" | bash -s -- --easy-mode'
    [sbh]='curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/storage_ballast_helper/main/scripts/install.sh | bash'
    [dsr]='curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/doodlestein_self_releaser/main/install.sh?$(date +%s)" | bash'
    [slb]='curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/slb/main/scripts/install.sh?$(date +%s)" | bash'
)

# Per-tool: HARD = blocks skill; SOFT = degrades gracefully; REC = recommended only.
declare -A FLYWHEEL_TIER=(
    [br]=HARD   [bv]=HARD
    [cass]=SOFT [ubs]=SOFT [rch]=SOFT [jsm]=SOFT [ntm]=SOFT
    [dcg]=REC   [sbh]=REC  [dsr]=REC  [slb]=REC
)

for fw in br bv cass ubs rch jsm ntm dcg sbh dsr slb; do
    if have "$fw"; then
        record "$fw" ok "$($fw --version 2>/dev/null | head -1)"
    else
        record "$fw" missing ""
        INSTALL_HINT["$fw"]="${FLYWHEEL_HINT[$fw]}"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# report + offer to install
# ─────────────────────────────────────────────────────────────────────────────

ALL_TOOLS=(rustup nightly miri rust_src cargo-fuzz cargo-afl cargo-geiger cargo-audit cargo-deny cargo-expand ast-grep semgrep
           br bv cass ubs rch jsm ntm dcg sbh dsr slb)

printf '\n=== Rust toolchain inventory ===\n'
for k in rustup nightly miri rust_src cargo-fuzz cargo-afl cargo-geiger cargo-audit cargo-deny cargo-expand ast-grep semgrep; do
    case "${STATUS[$k]}" in
        ok)      printf '  [✓] %-18s %s\n' "$k" "${VERSION[$k]}" ;;
        missing) printf '  [ ] %-18s (hint: %s)\n' "$k" "${INSTALL_HINT[$k]}" ;;
    esac
done

printf '\n=== Flywheel tools inventory ===\n'
for k in br bv cass ubs rch jsm ntm dcg sbh dsr slb; do
    tier="${FLYWHEEL_TIER[$k]}"
    case "${STATUS[$k]}" in
        ok)      printf '  [✓] %-6s (%s)  %s\n' "$k" "$tier" "${VERSION[$k]}" ;;
        missing) printf '  [ ] %-6s (%s)  curl-bash one-liner available\n' "$k" "$tier" ;;
    esac
done

# Check hard-requirements satisfied
missing_hard=()
for k in br bv; do
    [[ "${STATUS[$k]}" == "missing" ]] && missing_hard+=("$k")
done
if (( ${#missing_hard[@]} )); then
    printf '\n  ⚠ Missing HARD requirements: %s\n' "${missing_hard[*]}"
    printf '  The skill needs these before Phase 9 beads handoff can run.\n\n'
fi

printf '\n'

INSTALLED=()
# Note: `eval` is used so that hints containing pipelines (e.g. `curl ... | bash`)
# execute as a single shell command. The hints are author-controlled string
# literals defined just above, never user input, so eval is safe in this
# context. If you add a new hint, keep it author-controlled.

# Rust toolchain (essentials)
for k in nightly miri rust_src; do
    if [[ "${STATUS[$k]}" == "missing" ]]; then
        if ask "Install $k via: ${INSTALL_HINT[$k]} ?"; then
            if eval "${INSTALL_HINT[$k]}"; then
                STATUS[$k]=ok && INSTALLED+=("$k")
                # post-install smoke
                if smoke_test "$k"; then
                    SMOKE_OK[$k]="yes"
                    echo "  [✓] $k post-install smoke OK"
                else
                    SMOKE_OK[$k]="no"
                    echo "  [⚠] $k installed but smoke FAILED — investigate before proceeding"
                fi
            fi
        fi
    fi
done

# Rust toolchain (optional)
for k in cargo-fuzz cargo-afl cargo-geiger cargo-audit cargo-deny cargo-expand ast-grep; do
    if [[ "${STATUS[$k]}" == "missing" ]]; then
        if ask "Install optional $k via: ${INSTALL_HINT[$k]} ?"; then
            if eval "${INSTALL_HINT[$k]}"; then
                STATUS[$k]=ok && INSTALLED+=("$k")
                if smoke_test "$k"; then
                    SMOKE_OK[$k]="yes"
                    echo "  [✓] $k post-install smoke OK"
                else
                    SMOKE_OK[$k]="no"
                    echo "  [⚠] $k installed but smoke FAILED"
                fi
            fi
        fi
    fi
done

# Flywheel tools — hard requirements first
for k in br bv; do
    if [[ "${STATUS[$k]}" == "missing" ]]; then
        echo
        printf 'HARD requirement: %s\n' "$k"
        printf 'One-liner: %s\n' "${INSTALL_HINT[$k]}"
        if ask "Install $k ?"; then
            eval "${INSTALL_HINT[$k]}" && STATUS[$k]=ok && INSTALLED+=("$k")
        fi
    fi
done

# Flywheel tools — soft requirements
for k in cass ubs rch jsm ntm; do
    if [[ "${STATUS[$k]}" == "missing" ]]; then
        echo
        printf 'SOFT requirement: %s\n' "$k"
        printf 'One-liner: %s\n' "${INSTALL_HINT[$k]}"
        if ask "Install $k ?"; then
            eval "${INSTALL_HINT[$k]}" && STATUS[$k]=ok && INSTALLED+=("$k")
        fi
    fi
done

# Flywheel tools — recommended
for k in dcg sbh dsr slb; do
    if [[ "${STATUS[$k]}" == "missing" ]]; then
        echo
        printf 'Recommended: %s\n' "$k"
        printf 'One-liner: %s\n' "${INSTALL_HINT[$k]}"
        if ask "Install $k ?"; then
            eval "${INSTALL_HINT[$k]}" && STATUS[$k]=ok && INSTALLED+=("$k")
        fi
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# write inventory JSON
# ─────────────────────────────────────────────────────────────────────────────

# Run smoke tests on every present tool whose smoke wasn't already run by
# the install loop above. This catches "installed but broken" tools from
# earlier (e.g., rustup component partially registered).
for k in "${ALL_TOOLS[@]}"; do
    if [[ -z "${SMOKE_OK[$k]+set}" ]] && [[ "${STATUS[$k]:-missing}" == "ok" ]]; then
        if smoke_test "$k"; then
            SMOKE_OK[$k]="yes"
        else
            rc=$?
            if [[ $rc -eq 2 ]]; then
                SMOKE_OK[$k]="untested"
            else
                SMOKE_OK[$k]="no"
            fi
        fi
    fi
    : "${SMOKE_OK[$k]:=untested}"
done

# Report tools that are present but broken (smoke failed).
broken=()
for k in "${ALL_TOOLS[@]}"; do
    [[ "${STATUS[$k]:-missing}" == "ok" && "${SMOKE_OK[$k]}" == "no" ]] && broken+=("$k")
done
if (( ${#broken[@]} )); then
    echo
    echo "⚠ Tools present on PATH but smoke-test FAILED: ${broken[*]}"
    echo "  These tools cannot be used as-is. Investigate before relying on them."
    # Tool-aware recovery advice. Categories match the actual ALL_TOOLS catalog
    # above; lumping all broken tools under a single rustup hint was misleading
    # when the broken tool was e.g. `slb` (flywheel) or `semgrep` (pip).
    rustup_broken=()       # rustup component add ...
    cargo_broken=()        # cargo install ...
    semgrep_broken=()      # pip install ...
    flywheel_broken=()     # curl|bash one-liner from install.sh
    for t in "${broken[@]}"; do
        case "$t" in
            rustup|nightly|miri|rust_src)            rustup_broken+=("$t") ;;
            cargo-fuzz|cargo-afl|cargo-geiger|cargo-audit|cargo-deny|cargo-expand|ast-grep)
                                                      cargo_broken+=("$t") ;;
            semgrep)                                  semgrep_broken+=("$t") ;;
            br|bv|cass|ubs|rch|jsm|ntm|dcg|sbh|dsr|slb) flywheel_broken+=("$t") ;;
            *)                                        flywheel_broken+=("$t") ;;
        esac
    done
    if (( ${#rustup_broken[@]} )); then
        echo "  Rustup components: ${rustup_broken[*]}"
        echo "    rustup component add <component> --toolchain nightly"
        echo "    (or 'rustup toolchain install nightly' / re-run rustup-init for the root install)"
    fi
    if (( ${#cargo_broken[@]} )); then
        echo "  Cargo-installed subcommands: ${cargo_broken[*]}"
        echo "    cargo install <tool> --force"
    fi
    if (( ${#semgrep_broken[@]} )); then
        echo "  Python-installed: ${semgrep_broken[*]}"
        echo "    pip install --upgrade semgrep   # or: brew install semgrep"
    fi
    if (( ${#flywheel_broken[@]} )); then
        echo "  Flywheel tools (separately maintained CLIs): ${flywheel_broken[*]}"
        echo "    See scripts/install.sh — it has the canonical curl|bash one-liners."
        echo "    Quirk: some tools (e.g. \`slb\`) exit non-zero on \`--version\` even"
        echo "    when working. Run the tool's own --help before reinstalling."
    fi
fi

{
    printf '{\n'
    printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "tools": {\n'
    first=1
    for k in "${ALL_TOOLS[@]}"; do
        [[ $first -eq 1 ]] || printf ',\n'
        first=0
        # `set -u` requires defensive defaults — newly-installed tools have
        # STATUS=ok but VERSION may still be unset (we don't re-detect after install).
        ver="${VERSION[$k]:-}"
        ver="${ver//\"/\\\"}"
        printf '    "%s": {"status": "%s", "version": "%s", "smoke_test_passed": "%s"}' \
            "$k" "${STATUS[$k]:-missing}" "$ver" "${SMOKE_OK[$k]:-untested}"
    done
    printf '\n  },\n'
    printf '  "installed_this_run": ['
    first=1
    for k in "${INSTALLED[@]}"; do
        [[ $first -eq 1 ]] || printf ', '
        first=0
        printf '"%s"' "$k"
    done
    printf '],\n'
    printf '  "broken_post_smoke": ['
    first=1
    for k in "${broken[@]}"; do
        [[ $first -eq 1 ]] || printf ', '
        first=0
        printf '"%s"' "$k"
    done
    printf ']\n'
    printf '}\n'
} > "$INVENTORY"

echo
echo "Wrote inventory: $INVENTORY"
if (( ${#missing_hard[@]} )) && [[ "${STATUS[br]}" == "missing" || "${STATUS[bv]}" == "missing" ]]; then
    echo
    echo "⚠ Hard requirements still missing: ${missing_hard[*]}"
    echo "  Phase 9 beads handoff will fail without them."
    echo "  See references/FLYWHEEL-TOOLS-INSTALL.md."
fi
