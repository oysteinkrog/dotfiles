#!/usr/bin/env bash
# preflight-check.sh — verify external tool dependencies before Phase 1.
#
# Cold-prober finding #10 (round 53): the skill assumes jq, git, jsm, cass,
# br, bv, agent-mail, etc. are installed without an upfront check. Result:
# Phase 1 archaeologists hit opaque "command not found" errors mid-pass.
#
# Usage: preflight-check.sh <workspace>
# Output:
#   <workspace>/preflight.json — {tool: present|missing|version} per tool
#   stderr: human-readable summary
#   exit 0 if all REQUIRED tools present; exit 1 if any required tool missing.
#
# Required tools (block Phase 1):
#   jq, git, python3, awk, sed
# Optional tools (warn-only; skill has fallbacks):
#   jsm, cass, br, bv, mcp-agent-mail-client (or `am`), gh, codex, gemini

set -euo pipefail

usage() {
    echo "usage: preflight-check.sh <workspace>" >&2
}

workspace="${1:-}"
case "$workspace" in
    -h|--help)
        usage
        exit 0
        ;;
esac
if [ -z "$workspace" ]; then
    usage; exit 64
fi

mkdir -p "$workspace" \
    || { echo "preflight-check: cant_create $workspace" >&2; exit 73; }

REQUIRED=(jq git python3 awk sed)
OPTIONAL=(jsm cass br bv am gh codex gemini)

# Detect a tool's version with a best-effort one-liner per tool.
detect_version() {
    local tool="$1"
    case "$tool" in
        jq)        jq --version 2>/dev/null | head -1 ;;
        git)       git --version 2>/dev/null | head -1 ;;
        python3)   python3 --version 2>/dev/null | head -1 ;;
        awk|sed)   "$tool" --version 2>/dev/null | head -1 || echo "(version unknown)" ;;
        jsm)       jsm --version 2>/dev/null | head -1 || echo "(version unknown)" ;;
        cass)      cass --version 2>/dev/null | head -1 || echo "(version unknown)" ;;
        br)        br --version 2>/dev/null | head -1 || echo "(version unknown)" ;;
        bv)        bv --robot-triage 2>/dev/null > /dev/null && echo "(present)" || echo "(present)" ;;
        am)        am --version 2>/dev/null | head -1 || echo "(version unknown)" ;;
        gh)        gh --version 2>/dev/null | head -1 ;;
        codex|gemini) "$tool" --version 2>/dev/null | head -1 || echo "(version unknown)" ;;
        *)         echo "(version unknown)" ;;
    esac
}

declare -A status
declare -A version
all_required_ok=1

check_one() {
    local tool="$1"
    if command -v "$tool" >/dev/null 2>&1; then
        status[$tool]="present"
        # `|| true` defends against the SIGPIPE-141 case where a tool's first
        # version line happens to exceed 80 bytes: head -c 80 closes stdin
        # early, tr SIGPIPEs, pipefail propagates 141 to the assignment, and
        # set -e aborts the preflight before downstream checks run.
        version[$tool]="$(detect_version "$tool" 2>/dev/null | tr -d '\n' | head -c 80 || true)"
    else
        status[$tool]="missing"
        version[$tool]=""
    fi
}

for t in "${REQUIRED[@]}" "${OPTIONAL[@]}"; do
    check_one "$t"
done

# Build JSON output. Use python3 to ensure proper escaping.
{
    python3 - <<PYEOF
import json
required = """${REQUIRED[@]}""".split()
optional = """${OPTIONAL[@]}""".split()
data = {"required": {}, "optional": {}, "all_required_present": True}
PYEOF
} >/dev/null 2>&1 || true

# Simpler: emit JSON manually, escape via python.
esc() {
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

json="{\n  \"schema_version\": \"1.0\",\n  \"required\": {"
first=1
for t in "${REQUIRED[@]}"; do
    [ "$first" -eq 0 ] && json+=","
    first=0
    s="${status[$t]}"
    v="${version[$t]:-}"
    json+="\n    \"$t\": {\"status\": $(esc "$s"), \"version\": $(esc "$v")}"
    if [ "$s" = "missing" ]; then
        all_required_ok=0
    fi
done
json+="\n  },\n  \"optional\": {"
first=1
for t in "${OPTIONAL[@]}"; do
    [ "$first" -eq 0 ] && json+=","
    first=0
    s="${status[$t]}"
    v="${version[$t]:-}"
    json+="\n    \"$t\": {\"status\": $(esc "$s"), \"version\": $(esc "$v")}"
done
json+="\n  },\n  \"all_required_present\": $([ "$all_required_ok" -eq 1 ] && echo true || echo false)\n}"

printf '%b\n' "$json" > "$workspace/preflight.json"

# Human-readable summary on stderr.
echo "preflight-check: required tools:" >&2
for t in "${REQUIRED[@]}"; do
    s="${status[$t]}"
    v="${version[$t]:-}"
    if [ "$s" = "present" ]; then
        echo "  ✓ $t  $v" >&2
    else
        echo "  ✗ $t  MISSING (required)" >&2
    fi
done
echo "preflight-check: optional tools:" >&2
for t in "${OPTIONAL[@]}"; do
    s="${status[$t]}"
    v="${version[$t]:-}"
    if [ "$s" = "present" ]; then
        echo "  ✓ $t  $v" >&2
    else
        echo "  - $t  not found (optional; skill has fallbacks)" >&2
    fi
done

if [ "$all_required_ok" -ne 1 ]; then
    echo "preflight-check: at least one REQUIRED tool is missing; install before proceeding" >&2
    echo "wrote $workspace/preflight.json" >&2
    exit 1
fi

echo "preflight-check: all required tools present; wrote $workspace/preflight.json" >&2
exit 0
