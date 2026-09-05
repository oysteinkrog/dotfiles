#!/usr/bin/env bash
# install-referenced-skills.sh — bulk-install missing skills via jsm.
#
# Usage: install-referenced-skills.sh <workspace>
# Reads <workspace>/phase0_skill_inventory.json. For each skill with
# installed: false, runs `jsm install <name>`. Idempotent.

set -euo pipefail
workspace="${1:-}"
if [ -z "$workspace" ]; then
    echo "usage: install-referenced-skills.sh <workspace>" >&2
    exit 64
fi
inv="$workspace/phase0_skill_inventory.json"
[ -f "$inv" ] || { echo "error: $inv not found; run check-skills.sh first" >&2; exit 66; }
if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required to parse $inv; install jq and re-run" >&2
    exit 66
fi

if ! command -v jsm >/dev/null 2>&1; then
    echo "jsm not installed; skipping. To install:" >&2
    echo "  curl -fsSL https://jeffreys-skills.md/install.sh | bash" >&2
    exit 0
fi

if ! jsm whoami >/dev/null 2>&1; then
    echo "jsm installed but not authenticated. Run 'jsm login' first." >&2
    exit 0
fi

# Verify the inventory has the expected schema BEFORE filtering. Without
# this guard, a schema_version=2.0 inventory with a renamed `.skills`
# field would silently produce no candidates → script reports "all
# installed; nothing to do" → false-positive success. Round-52
# triangulation finding (script #15).
if ! jq -e '.skills | type == "array"' < "$inv" >/dev/null 2>&1; then
    echo "error: $inv lacks a top-level .skills array (schema mismatch?)" >&2
    echo "  expected: {\"skills\": [{\"name\": ..., \"installed\": ...}, ...]}" >&2
    exit 66
fi

missing=$(jq -r '.skills[] | select(.installed == false) | .name' < "$inv")

if [ -z "$missing" ]; then
    echo "all referenced skills installed; nothing to do." >&2
    exit 0
fi

# Track failure count. Without this, the script's `|| echo warning`
# pattern would swallow every install failure and exit 0 — caller can't
# distinguish "all installed cleanly" from "5 of 10 silently failed."
fail_count=0
ok_count=0
while IFS= read -r name; do
    [ -z "$name" ] && continue
    echo "installing: $name" >&2
    if jsm install "$name"; then
        ok_count=$((ok_count + 1))
    else
        fail_count=$((fail_count + 1))
        echo "warning: jsm install $name failed; continuing" >&2
    fi
done <<< "$missing"

if [ "$fail_count" -gt 0 ]; then
    echo "done with errors: $ok_count installed, $fail_count failed." >&2
    exit 1
fi

echo "done: $ok_count installed." >&2
