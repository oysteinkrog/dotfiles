#!/usr/bin/env bash
# verify-source-coverage.sh — Confirm every section of the source guide maps to at least one bundle.
#
# Usage: ./scripts/verify-source-coverage.sh
#
# Reads:
#   $SAAS_BILLING_SOURCE_GUIDE (defaults to COMPREHENSIVE_GUIDE_TO_SAAS_BILLING_PATTERNS_WITH_STRIPE_AND_PAYPAL.md in cwd)
#   references/source/SOURCE-INDEX.md
#
# Exits 0 if every section is mapped, 1 if any orphan section, 2 if deps missing.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_GUIDE="${SAAS_BILLING_SOURCE_GUIDE:-COMPREHENSIVE_GUIDE_TO_SAAS_BILLING_PATTERNS_WITH_STRIPE_AND_PAYPAL.md}"
INDEX_FILE="$SKILL_DIR/references/source/SOURCE-INDEX.md"

if [[ ! -f "$SOURCE_GUIDE" ]]; then
  echo "Source guide not found: $SOURCE_GUIDE" >&2
  exit 2
fi
if [[ ! -f "$INDEX_FILE" ]]; then
  echo "Source index not found: $INDEX_FILE" >&2
  exit 2
fi

# Extract section numbers from the source guide (lines starting with "## N." where N is a number)
GUIDE_SECTIONS=$(grep -E "^## [0-9]+[a-z]?\." "$SOURCE_GUIDE" | sed -E 's/^## ([0-9]+[a-z]?)\..*/\1/' | sort -u)

# Extract section numbers from the source index (the "Source §" column)
INDEXED_SECTIONS=$(grep -E "^\| [0-9]+[a-z]?[. ]" "$INDEX_FILE" | sed -E 's/^\| ([0-9]+[a-z]?\.?[0-9a-z]*) .*/\1/' | sed 's/\.$//' | sort -u)

# Find missing
MISSING=$(comm -23 <(echo "$GUIDE_SECTIONS") <(echo "$INDEXED_SECTIONS"))

echo "## Source Coverage Verification"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "### Source-guide sections found"
echo "$GUIDE_SECTIONS" | wc -l | xargs printf "  count: %s\n"
echo
echo "### Sections referenced in SOURCE-INDEX.md"
echo "$INDEXED_SECTIONS" | wc -l | xargs printf "  count: %s\n"
echo
echo "### Orphan sections (in guide but not in index)"
if [[ -z "$MISSING" ]]; then
  echo "  (none)"
  echo
  echo "✓ Every source-guide section is mapped to at least one bundle."
  exit 0
else
  echo "$MISSING" | sed 's/^/  ✗ § /'
  echo
  echo "✗ Orphan sections found. Update references/source/SOURCE-INDEX.md."
  exit 1
fi
