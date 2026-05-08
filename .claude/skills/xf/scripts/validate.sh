#!/bin/bash
#
# Validate xf Installation — Quick health check
#
# Usage:
#     ./validate.sh
#
# Returns:
#     0 = All checks pass
#     1 = Some checks failed

set -euo pipefail

echo "Validating xf installation..."
echo ""

ERRORS=0
HAVE_XF=0
XF_DOCTOR_TIMEOUT="${XF_DOCTOR_TIMEOUT:-15}"

run_xf_doctor() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "${XF_DOCTOR_TIMEOUT}s" xf -q doctor >/dev/null 2>&1
    else
        xf -q doctor >/dev/null 2>&1
    fi
}

# 1. Check xf exists
echo -n "1. xf command exists: "
if command -v xf &> /dev/null; then
    HAVE_XF=1
    echo "✓"
else
    echo "✗ (xf not found in PATH)"
    ERRORS=$((ERRORS + 1))
fi

# 2. Check jq exists
echo -n "2. jq command exists: "
if command -v jq &> /dev/null; then
    echo "✓"
else
    echo "✗ (jq not found - install with: apt install jq)"
    ERRORS=$((ERRORS + 1))
fi

# 3. Check xf doctor
echo -n "3. xf doctor passes: "
if [ "$HAVE_XF" -eq 0 ]; then
    echo "⊘ skipped (xf not installed)"
elif run_xf_doctor; then
    echo "✓"
else
    doctor_status=$?
    if [ "$doctor_status" -eq 124 ]; then
        echo "✗ (xf doctor timed out after ${XF_DOCTOR_TIMEOUT}s)"
    else
        echo "✗ (run 'xf doctor' for details)"
    fi
    ERRORS=$((ERRORS + 1))
fi

# 4. Check xf stats works
echo -n "4. xf stats accessible: "
if [ "$HAVE_XF" -eq 0 ]; then
    echo "⊘ skipped (xf not installed)"
elif xf -q -f json stats &> /dev/null; then
    echo "✓"
else
    echo "✗ (archive may not be indexed)"
    ERRORS=$((ERRORS + 1))
fi

# 5. Check search works
echo -n "5. xf search works: "
if [ "$HAVE_XF" -eq 0 ]; then
    echo "⊘ skipped (xf not installed)"
elif xf -q -f json search "test" --limit 1 &> /dev/null; then
    echo "✓"
else
    echo "✗ (search failed)"
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "All checks passed! ✓"
    exit 0
else
    echo "$ERRORS check(s) failed. ✗"
    exit 1
fi
