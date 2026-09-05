#!/usr/bin/env bash
# cancel-correctness-audit.sh — find pub fns that perform blocking syscalls
# without a cancellation handle (cass-Q103 pattern). See
# CANCEL-CORRECTNESS.md for the methodology.
#
# Usage:
#   cancel-correctness-audit.sh <source-dir> [--cx-type <TypeName>] [--output <file>]
#
# Default cx-type is `Cx` (the cass-Q103 convention). Override with --cx-type
# if the audited project uses a different cancellation handle name (e.g.,
# `CancelToken`, `ShutdownSignal`).
#
# Exit codes:
#   0 — audit completed (zero or more candidates surfaced)
#   2 — usage error / source dir invalid / ast-grep or jq missing
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

require_dep() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "$1 not installed${2:+ — $2}" >&2
        exit 2
    fi
}

if [[ $# -lt 1 ]]; then
    echo "Usage: cancel-correctness-audit.sh <source-dir> [--cx-type <Type>] [--output <file>]" >&2
    exit 2
fi

SOURCE="$1"
shift

CX_TYPE="Cx"
OUTPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cx-type)
            shift
            [[ $# -gt 0 ]] || { echo "--cx-type requires a value" >&2; exit 2; }
            CX_TYPE="$1" ;;
        --cx-type=*)  CX_TYPE="${1#--cx-type=}" ;;
        --output)
            shift
            [[ $# -gt 0 ]] || { echo "--output requires a value" >&2; exit 2; }
            OUTPUT="$1" ;;
        --output=*)   OUTPUT="${1#--output=}" ;;
        *)            echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

if [[ ! -d "$SOURCE" ]]; then
    echo "Source dir not found: $SOURCE" >&2
    exit 2
fi
require_dep ast-grep "try: cargo install ast-grep"
require_dep jq "install via apt/brew/dnf"

# Blocking primitives we scan for. These are the patterns that UNAMBIGUOUSLY
# indicate a blocking syscall. Avoid noisy patterns like `.join(` (matches
# PathBuf::join, String::join) or `.recv(` (matches std::sync::mpsc::Receiver
# but also tokio::sync::mpsc — context-dependent). We optimize for low false-
# positive rate; the audit is meant to surface CANDIDATES for human review.
BLOCKING_CALLS=(
    'TcpStream::connect'
    'TcpStream::connect_timeout'
    'TcpListener::accept'
    'TcpListener::bind'
    'UdpSocket::recv'
    'UdpSocket::recv_from'
    'std::net::lookup_host'
    'std::fs::File::open'
    'std::fs::File::create'
    'std::fs::read_to_string'
    'std::fs::write'
    'std::thread::sleep'
    'std::thread::park'
    'std::sync::Mutex::lock'
    'std::sync::RwLock::read'
    'std::sync::RwLock::write'
    'JoinHandle::join'   # thread join, not PathBuf::join
    'Command::output'
    'Command::status'
    'Command::spawn'
)

# Match `pub fn $NAME($$$ARGS)` and inner $BODY containing the blocking call.
# ast-grep can't easily compose "X but NOT Y" so we fan out: first find pub
# fns containing the blocking call, then filter out ones whose ARGS contain
# `cx: &$CX_TYPE` or `cx: &mut $CX_TYPE`.

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TOTAL_HITS=0
declare -A SEEN=()

audit_one() {
    local call="$1"
    # Two visibility forms: `pub fn` and `pub($V) fn`. We use a permissive
    # ast-grep pattern that matches the fn header + body together. The body
    # filter uses $$$BEFORE/$$$AFTER to allow the blocking call anywhere inside.
    local out
    out="$TMP_DIR/hits_$(echo "$call" | tr -c 'a-zA-Z0-9' '_').json"
    {
        ast-grep run -l Rust --json \
            -p "pub fn \$NAME(\$\$\$ARGS) { \$\$\$BEFORE $call \$\$\$AFTER }" \
            "$SOURCE" 2>/dev/null || true
        ast-grep run -l Rust --json \
            -p "pub fn \$NAME(\$\$\$ARGS) -> \$RET { \$\$\$BEFORE $call \$\$\$AFTER }" \
            "$SOURCE" 2>/dev/null || true
    } > "$out"

    # Filter: keep only entries whose meta_variables.ARGS does NOT include "cx: &$CX_TYPE"
    local hits
    hits=$(jq -r --arg cx "cx: &${CX_TYPE}" '
        .[]? |
        select((.metaVariables.single.ARGS.text // "") | test($cx) | not) |
        "\(.file):\(.range.start.line) fn \(.metaVariables.single.NAME.text) // contains: " + "'"$call"'"
    ' "$out" 2>/dev/null || true)

    if [[ -n "$hits" ]]; then
        echo "── $call ──"
        # Process substitution keeps the while loop in the parent shell, so
        # mutations to SEEN[] and TOTAL_HITS survive across iterations.
        # Piping into `while read` runs it in a subshell and loses the state.
        while IFS= read -r line; do
            local key="${line%% //*}"
            if [[ -z "${SEEN[$key]:-}" ]]; then
                SEEN[$key]=1
                echo "$line"
                TOTAL_HITS=$((TOTAL_HITS+1))
            fi
        done < <(printf '%s\n' "$hits")
    fi
}

# Collect output to stdout AND optionally a file
{
    echo "=== cancel-correctness-audit — source=$SOURCE cx-type=$CX_TYPE ==="
    echo "Scanning ${#BLOCKING_CALLS[@]} blocking primitives for pub fns missing 'cx: &$CX_TYPE'..."
    echo

    for call in "${BLOCKING_CALLS[@]}"; do
        audit_one "$call"
    done

    echo
    echo "=== End of audit ==="
    echo "Review each candidate: a pub fn missing cx: &$CX_TYPE is a LIKELY cancel-correctness violation IF the project's archetype uses Cx-style cancellation."
    echo "Cross-reference with phase0_run.json's archetype field before treating as UB."
} | if [[ -n "$OUTPUT" ]]; then
        tee "$OUTPUT"
    else
        cat
    fi

exit 0
