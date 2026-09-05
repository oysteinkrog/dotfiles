#!/usr/bin/env bash
# verify-capabilities.sh — Phase 6 contract round-trip.
#
# Usage: verify-capabilities.sh [<tool>]
# Asserts every detector and fixer declared in `<tool> doctor capabilities --json`
# is invocable via `--only <id>`.

set -euo pipefail
tool="${1:-${TOOL:-}}"
if [ -z "$tool" ]; then
    echo "usage: verify-capabilities.sh <tool>     (or set TOOL env var)" >&2
    exit 64
fi

caps=$("$tool" doctor capabilities --json) \
    || { echo "FAIL: capabilities --json failed" >&2; exit 1; }

# Validate JSON parseability first; THEN check schema_version. The prior
# version conflated the two: `assert "schema_version" in json.load(...) 2>/dev/null`
# silenced parse errors AND key-missing errors, then printed
# "lacks schema_version" — confusing the operator about whether the JSON
# was even valid. Audit finding (verify-capabilities #18).
caps_check=$(echo "$caps" | python3 -c '
import sys, json
try:
    obj = json.loads(sys.stdin.read())
except json.JSONDecodeError as e:
    print(f"INVALID_JSON:{e}"); sys.exit(2)
if "schema_version" not in obj:
    print("MISSING:schema_version"); sys.exit(2)
print("OK")
' 2>&1) || { echo "FAIL: capabilities --json: $caps_check" >&2; exit 1; }

# Extract detector + fixer ids in a way that FAILS LOUDLY on a missing
# `id` field, instead of silently truncating the list. The prior version
# used `[print(d["id"]) for d in ...]` inside a process-substitution; if
# any detector dict lacked `id`, KeyError fired and the python process
# closed early — but `mapfile` succeeded with whatever was emitted before
# the crash, AND set -e doesn't fire on process-substitution failures.
# Result: silently truncated detector list, false PASS.
read_ids() {
    local field="$1"
    echo "$caps" | python3 -c "
import sys, json
obj = json.loads(sys.stdin.read())
items = obj.get('$field', [])
ids = []
for i, item in enumerate(items):
    if 'id' not in item:
        print(f'MISSING_ID:item[{i}] in $field has no \\\"id\\\" field', file=sys.stderr)
        sys.exit(2)
    ident = item['id']
    if not isinstance(ident, str) or not ident.strip() or any(c.isspace() for c in ident):
        print(f'BAD_ID:item[{i}] in $field has invalid id {ident!r}', file=sys.stderr)
        sys.exit(2)
    ids.append(ident)
for x in ids:
    print(x)
"
}
detectors_raw=$(read_ids detectors) \
    || { echo "FAIL: capabilities.detectors malformed: $detectors_raw" >&2; exit 1; }
fixers_raw=$(read_ids fixers) \
    || { echo "FAIL: capabilities.fixers malformed: $fixers_raw" >&2; exit 1; }

# Now mapfile from the validated output.
mapfile -t detectors <<< "$detectors_raw"
mapfile -t fixers <<< "$fixers_raw"
# Strip trailing empty-string entries that mapfile produces from a final
# newline.
[ -z "${detectors[-1]:-}" ] && unset 'detectors[-1]'
[ -z "${fixers[-1]:-}" ] && unset 'fixers[-1]'

if [ "${#detectors[@]}" -eq 0 ]; then
    echo "FAIL: capabilities has zero detectors" >&2
    exit 1
fi

errors=0
for id in "${detectors[@]}"; do
    # Capture exit code precisely; exit 1 (findings) is OK, we just need the detector
    # to be invocable. Per canonical exit-code table, exit 4 (refused-unsafe) is
    # ALSO a legitimate response when a precondition is unmet (e.g., detector
    # requires --online and we're in offline mode). Accept {0, 1, 4}; reject
    # anything else as "not invocable".
    rc=0
    "$tool" doctor --only "$id" --json --quiet > /dev/null 2>&1 || rc=$?
    case "$rc" in
        0|1|4) ;;
        *)
            echo "FAIL: detector $id declared but not invocable (rc=$rc)" >&2
            errors=$((errors + 1))
            ;;
    esac
done

# Robot-docs sanity. Use grep -F to avoid regex interpretation of needle
# strings ("EXIT CODES", "NEVER do" both contain spaces; the previous
# unflagged grep was harmless for these but `capabilities` would substring-
# match `incapabilities` etc. — a real edge case if doctor_robot-docs grows
# new sections).
docs=$("$tool" doctor robot-docs) \
    || { echo "FAIL: robot-docs invocation nonzero" >&2; exit 1; }
for needle in 'EXIT CODES' 'capabilities' 'NEVER do'; do
    if ! echo "$docs" | grep -qF -- "$needle"; then
        echo "FAIL: robot-docs missing '$needle'" >&2
        errors=$((errors + 1))
    fi
done

# Health endpoint timing (< 200ms target; lenient gate at 1000ms here).
start=$(date +%s%N)
"$tool" doctor health > /dev/null 2>&1 || true
end=$(date +%s%N)
elapsed_ms=$(( (end - start) / 1000000 ))
if [ "$elapsed_ms" -gt 1000 ]; then
    echo "FAIL: health took ${elapsed_ms}ms (expected < 1000)" >&2
    errors=$((errors + 1))
fi

if [ $errors -gt 0 ]; then
    echo "$errors error(s)" >&2
    exit 1
fi

echo "PASS: verify-capabilities.sh ($((${#detectors[@]})) detectors, ${#fixers[@]} fixers, health=${elapsed_ms}ms)" >&2
