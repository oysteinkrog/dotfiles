#!/usr/bin/env bash
# install.sh — install the flywheel tools the skill uses + delegate to
# install-toolchain.sh for Rust-side tooling.
#
# Usage:
#   install.sh [--workspace <ws>] [--yes] [--inventory-only] [--tools-only]
#              [--tool <name>] ...
#
# Flags:
#   --workspace <ws>      Optional. If provided, also runs install-toolchain.sh
#                         (Rust tools) against this workspace.
#   --yes                 Blanket approval: install every missing tool.
#   --inventory-only      Detect + print; install nothing.
#   --tools-only          Install flywheel tools only; skip install-toolchain.sh.
#   --tool <name>         Restrict to a specific tool (repeatable). Default: all.
#
# Output:
#   - Inventory table on stdout
#   - phase0_flywheel_inventory.json (if --workspace provided)
#   - Exit 0 unless --yes installer encountered a hard failure
#
# Catalog matches FLYWHEEL-TOOLS-INSTALL.md. Author-controlled curl-bash URLs
# (Dicklesworthstone/*). The script never runs them without explicit consent
# (either --yes or interactive y).
set -euo pipefail

WORKSPACE=""
ASSUME_YES=no
INVENTORY_ONLY=no
TOOLS_ONLY=no
WANTED_TOOLS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)      shift; WORKSPACE="$1" ;;
        --workspace=*)    WORKSPACE="${1#--workspace=}" ;;
        --yes)            ASSUME_YES=yes ;;
        --inventory-only) INVENTORY_ONLY=yes ;;
        --tools-only)     TOOLS_ONLY=yes ;;
        --tool)           shift; WANTED_TOOLS+=("$1") ;;
        --tool=*)         WANTED_TOOLS+=("${1#--tool=}") ;;
        -h|--help)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown flag: $1" >&2
            exit 2
            ;;
    esac
    shift
done

# Catalog — keep in sync with FLYWHEEL-TOOLS-INSTALL.md. Format:
#   tool|tier|version-cmd|install-one-liner
# tier: HARD | SOFT | REC
TOOLS=(
    'br|HARD|br --version|curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh?$(date +%s)" | bash'
    'bv|HARD|bv --version|curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh?$(date +%s)" | bash'
    'cass|SOFT|cass --version|curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh?$(date +%s)" | bash -s -- --easy-mode --verify'
    'ubs|SOFT|ubs --version|curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/main/install.sh?$(date +%s)" | bash -s -- --easy-mode'
    'rch|SOFT|rch --version|curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh?$(date +%s)" | bash -s -- --easy-mode'
    'jsm|SOFT|jsm --version|curl -fsSL "https://jeffreys-skills.md/install.sh?$(date +%s)" | bash'
    'ntm|SOFT|ntm version|curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh?$(date +%s)" | bash -s -- --easy-mode'
    'dcg|REC|dcg --version|curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/master/install.sh?$(date +%s)" | bash -s -- --easy-mode'
    'sbh|REC|sbh --version|curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/storage_ballast_helper/main/scripts/install.sh | bash'
    'dsr|REC|dsr --version|curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/doodlestein_self_releaser/main/install.sh?$(date +%s)" | bash'
    'slb|REC|slb --version|curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/slb/main/scripts/install.sh?$(date +%s)" | bash'
)

declare -A STATUS=()
declare -A VERSION=()
declare -A TIER=()
INSTALLED_THIS_RUN=()
BROKEN_POST_SMOKE=()

# Tier descriptions
tier_desc() {
    case "$1" in
        HARD) echo "blocks audit if absent" ;;
        SOFT) echo "skill degrades gracefully" ;;
        REC)  echo "recommended for safety" ;;
    esac
}

want_tool() {
    [[ "${#WANTED_TOOLS[@]}" -eq 0 ]] && return 0
    local t="$1"
    for w in "${WANTED_TOOLS[@]}"; do
        [[ "$w" == "$t" ]] && return 0
    done
    return 1
}

# Phase 1: inventory
echo "=== Flywheel tools inventory ==="
for entry in "${TOOLS[@]}"; do
    IFS='|' read -r tool tier vercmd installcmd <<< "$entry"
    if ! want_tool "$tool"; then continue; fi
    TIER[$tool]="$tier"

    if command -v "$tool" >/dev/null 2>&1; then
        # Get version (best-effort; some tools' --version errors are non-fatal)
        # Use a subshell with `set +e` around the eval so a tool whose
        # --version fails (e.g., wrong subcommand) doesn't abort our script.
        # Trailing `|| true` doesn't help here: under `set -o pipefail` the
        # whole pipeline fails if eval returns nonzero, regardless of the
        # final command's exit status.
        VERSION[$tool]="$( (set +e; eval "$vercmd" 2>&1; true) | head -1 )"
        STATUS[$tool]="installed"
        printf '  [✓] %s (%s)  %s\n' "$tool" "$tier" "${VERSION[$tool]}"
    else
        STATUS[$tool]="missing"
        printf '  [ ] %s (%s)  — missing\n' "$tool" "$tier"
    fi
done

# Phase 2: install (unless inventory-only)
if [[ "$INVENTORY_ONLY" == "yes" ]]; then
    echo
    echo "(--inventory-only — skipping installation)"
else
    echo
    for entry in "${TOOLS[@]}"; do
        IFS='|' read -r tool tier vercmd installcmd <<< "$entry"
        if ! want_tool "$tool"; then continue; fi
        if [[ "${STATUS[$tool]}" != "missing" ]]; then continue; fi

        # Decide whether to install
        do_install=no
        if [[ "$ASSUME_YES" == "yes" ]]; then
            do_install=yes
        else
            if [[ ! -t 0 ]]; then
                echo "  [skip] $tool — non-interactive shell + no --yes; pass --yes to install" >&2
                continue
            fi
            echo "Install $tool ($(tier_desc "$tier"))?"
            echo "  One-liner: $installcmd"
            read -r -p "  Proceed? [y/N] " ans
            [[ "$ans" =~ ^[Yy] ]] && do_install=yes
        fi

        if [[ "$do_install" == "yes" ]]; then
            echo "── Installing $tool ──"
            if eval "$installcmd"; then
                INSTALLED_THIS_RUN+=("$tool")
                # Re-check + smoke test
                if command -v "$tool" >/dev/null 2>&1; then
                    # Subshell + `set +e; ...; true` defeats pipefail (see Phase-1
                    # comment above for the full reasoning).
                    VERSION[$tool]="$( (set +e; eval "$vercmd" 2>&1; true) | head -1 )"
                    STATUS[$tool]="installed"
                    printf '  [✓] %s installed (%s)\n' "$tool" "${VERSION[$tool]}"
                else
                    STATUS[$tool]="broken-post-install"
                    BROKEN_POST_SMOKE+=("$tool")
                    printf '  [✗] %s installer ran but `command -v %s` still fails\n' "$tool" "$tool" >&2
                fi
            else
                STATUS[$tool]="install-failed"
                BROKEN_POST_SMOKE+=("$tool")
                printf '  [✗] %s installer failed\n' "$tool" >&2
            fi
        fi
    done
fi

# Phase 3: write inventory JSON if workspace provided
if [[ -n "$WORKSPACE" ]]; then
    WORKSPACE_REAL="$(realpath -m "$WORKSPACE")"
    case "$WORKSPACE_REAL" in
        */.ub-exorcism/*)
            mkdir -p "$WORKSPACE_REAL"
            INVENTORY_FILE="$WORKSPACE_REAL/phase0_flywheel_inventory.json"
            {
                echo '{'
                echo '  "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",'
                echo '  "tools": {'
                first=1
                for tool in "${!STATUS[@]}"; do
                    [[ $first -eq 1 ]] || echo ','
                    first=0
                    printf '    "%s": {"status":"%s","tier":"%s","version":"%s"}' \
                        "$tool" "${STATUS[$tool]}" "${TIER[$tool]:-?}" "${VERSION[$tool]//\"/\\\"}"
                done
                echo
                echo '  },'
                printf '  "installed_this_run": ['
                for i in "${!INSTALLED_THIS_RUN[@]}"; do
                    [[ $i -gt 0 ]] && printf ','
                    printf '"%s"' "${INSTALLED_THIS_RUN[$i]}"
                done
                echo '],'
                printf '  "broken_post_smoke": ['
                for i in "${!BROKEN_POST_SMOKE[@]}"; do
                    [[ $i -gt 0 ]] && printf ','
                    printf '"%s"' "${BROKEN_POST_SMOKE[$i]}"
                done
                echo ']'
                echo '}'
            } > "$INVENTORY_FILE"
            echo
            echo "Wrote $INVENTORY_FILE"
            ;;
        *)
            echo "Workspace $WORKSPACE_REAL is not under <source>/.ub-exorcism/<run-id> — skipping inventory write" >&2
            ;;
    esac
fi

# Phase 4: delegate to install-toolchain.sh for Rust-side tools
if [[ "$TOOLS_ONLY" != "yes" && -n "$WORKSPACE" ]]; then
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    TC_SCRIPT="$SCRIPT_DIR/install-toolchain.sh"
    if [[ -x "$TC_SCRIPT" ]]; then
        echo
        echo "═══ Delegating to install-toolchain.sh for Rust-side tooling ═══"
        tc_flags=()
        [[ "$ASSUME_YES" == "yes" ]] && tc_flags+=(--yes)
        [[ "$INVENTORY_ONLY" == "yes" ]] && tc_flags+=(--inventory-only)
        # NOT `"${tc_flags[@]:-}"` — that form passes an empty string as one
        # argument when the array is empty, which install-toolchain.sh would
        # parse as a stray positional. Bash 4.4+ expands an empty array under
        # `set -u` to zero words, which is what we want.
        if [[ "${#tc_flags[@]}" -gt 0 ]]; then
            "$TC_SCRIPT" "$WORKSPACE_REAL" "${tc_flags[@]}"
        else
            "$TC_SCRIPT" "$WORKSPACE_REAL"
        fi
    else
        echo "install-toolchain.sh not found at $TC_SCRIPT — skipping Rust-tools install" >&2
    fi
fi

# Report
if [[ "${#BROKEN_POST_SMOKE[@]}" -gt 0 ]]; then
    echo
    echo "⚠ Tools installed but smoke FAILED: ${BROKEN_POST_SMOKE[*]}"
    echo "  Investigate before relying on them in audit phases."
fi

exit 0
