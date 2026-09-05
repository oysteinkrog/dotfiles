#!/usr/bin/env bash
# manifest-update.sh — atomic update of <workspace>/manifest.json.
#
# Usage: manifest-update.sh <workspace> --set <jq-path>=<value> [--set ...]
# Example: manifest-update.sh /path/to/ws --set .pass=2 --set .phases_completed[+]=4

set -euo pipefail
usage() {
    echo "usage: manifest-update.sh <workspace> (--set|--set-int|--set-json) <jq-path>=<value> [...]" >&2
}

workspace="${1:-}"
if [ -z "$workspace" ]; then
    usage
    exit 64
fi
shift

manifest="$workspace/manifest.json"
[ -f "$manifest" ] || { echo "no manifest at $manifest" >&2; exit 66; }

# Path validator — restricts the jq path component to alphanumerics, dots,
# brackets, and `+` (for `[+]` array-append). Rejects anything that could
# inject jq-filter syntax. Caught in round-53 triangulation: prior version
# interpolated $path unquoted into the jq filter string, so a malicious or
# malformed --set could break out of the assignment context (e.g., adding
# a function call, semicolon, or alternate filter).
validate_jq_path() {
    case "$1" in
        # Allow the canonical forms: .foo, .foo.bar, .foo[+], .foo[0], .foo[0].bar.
        # Disallow anything containing |, ;, (, ), $, `, ", ', \, whitespace, or
        # non-printables. The grep call below is the single chokepoint.
        '') return 1 ;;
    esac
    if printf '%s' "$1" | grep -qE '^\.[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+|\[[0-9]*\+?\])*$'; then
        return 0
    fi
    return 1
}

require_spec() {
    flag="$1"
    spec="${2:-}"
    if [ -z "$spec" ]; then
        echo "manifest-update: $flag requires .path=value" >&2
        exit 64
    fi
    case "$spec" in
        *=*) ;;
        *)
            echo "manifest-update: $flag requires .path=value" >&2
            exit 64
            ;;
    esac
}

validate_int_value() {
    value="$1"
    if ! printf '%s' "$value" | grep -qE '^-?[0-9]+$'; then
        echo "manifest-update: --set-int value must be an integer" >&2
        exit 64
    fi
}

validate_json_value() {
    value="$1"
    python3 -c 'import json,sys; json.loads(sys.argv[1])' "$value" 2>/dev/null \
        || { echo "manifest-update: --set-json value must be valid JSON" >&2; exit 64; }
}

# Acquire an advisory lock before reading the manifest. Without this, two
# concurrent --set invocations both read the original manifest, both modify
# their copy, and the second `mv` wins — silently losing the first's update.
# `flock -x -w 30` blocks up to 30s for the lock; longer than that suggests
# a hung writer, so we exit 5 (concurrency_lost in the canonical exit-code
# table) to surface the contention.
lockfile="$workspace/.manifest.lock"
exec 9>"$lockfile"
if ! flock -x -w 30 9; then
    echo "manifest-update: lock contention on $lockfile (waited 30s); aborting" >&2
    exit 5
fi

# Use 'prefix.XXXXXX' (no suffix after XXXXXX) — macOS BSD mktemp rejects
# templates with characters after XXXXXX. The .tmp.new sibling files used
# below don't need the .tmp suffix on the base name.
tmp="$(mktemp "$workspace/.manifest.XXXXXX")"
trap 'echo "manifest-update: temp files preserved at $tmp and $tmp.new (if present)" >&2; flock -u 9' EXIT

cp "$manifest" "$tmp"

while [ $# -gt 0 ]; do
    case "$1" in
        --set)
            require_spec "$1" "${2:-}"
            spec="$2"
            path="${spec%%=*}"
            value="${spec#*=}"
            validate_jq_path "$path" \
                || { echo "manifest-update: invalid jq path '$path'; allowed: .foo, .foo.bar, .foo[N], .foo[+]" >&2; exit 64; }
            # Strict integer / boolean detection — anything else (including
            # semver "0.4.7") is a string. Use --arg to avoid jq parsing
            # ambiguities; let jq always treat the value as a string unless
            # the caller explicitly used --set-json.
            jq --arg v "$value" "$path = \$v" "$tmp" > "$tmp.new"
            mv "$tmp.new" "$tmp"
            shift 2
            ;;
        --set-int)
            require_spec "$1" "${2:-}"
            spec="$2"
            path="${spec%%=*}"
            value="${spec#*=}"
            validate_int_value "$value"
            validate_jq_path "$path" \
                || { echo "manifest-update: invalid jq path '$path'" >&2; exit 64; }
            jq --argjson v "$value" "$path = \$v" "$tmp" > "$tmp.new"
            mv "$tmp.new" "$tmp"
            shift 2
            ;;
        --set-json)
            require_spec "$1" "${2:-}"
            spec="$2"
            path="${spec%%=*}"
            value="${spec#*=}"
            validate_json_value "$value"
            validate_jq_path "$path" \
                || { echo "manifest-update: invalid jq path '$path'" >&2; exit 64; }
            jq --argjson v "$value" "$path = \$v" "$tmp" > "$tmp.new"
            mv "$tmp.new" "$tmp"
            shift 2
            ;;
        *)
            echo "unknown arg: $1" >&2
            exit 64
            ;;
    esac
done

# Atomic rename within the same FS.
mv "$tmp" "$manifest"
trap - EXIT
flock -u 9
# Emit a JSON status to stdout so callers can programmatically assert success
# (round-53 triangulation flagged the prior version as silent on stdout —
# only a stderr "manifest updated" line, no contract for callers).
printf '{"updated":true,"manifest":%s}\n' "$(printf '%s' "$manifest" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')"
echo "manifest updated" >&2
