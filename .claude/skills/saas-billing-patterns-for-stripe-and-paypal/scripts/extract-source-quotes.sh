#!/usr/bin/env bash
# extract-source-quotes.sh — Extract the triangulated kernel + quote bank from the source guide.
#
# Usage: ./scripts/extract-source-quotes.sh > corpus_kernel_extract.md
#
# Reads:
#   $SAAS_BILLING_SOURCE_GUIDE (defaults to COMPREHENSIVE_GUIDE_TO_SAAS_BILLING_PATTERNS_WITH_STRIPE_AND_PAYPAL.md in cwd)
#   references/methodology/SOURCE-CORPUS.md  (the curated quote bank)
#
# Writes the marker-bounded kernel block + quote bank to stdout.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_GUIDE="${SAAS_BILLING_SOURCE_GUIDE:-COMPREHENSIVE_GUIDE_TO_SAAS_BILLING_PATTERNS_WITH_STRIPE_AND_PAYPAL.md}"
KERNEL_FILE="$SKILL_DIR/references/patterns/00-NORTH-STAR.md"
QUOTE_FILE="$SKILL_DIR/references/methodology/SOURCE-CORPUS.md"

if [[ ! -f "$SOURCE_GUIDE" ]]; then
  echo "Source guide not found: $SOURCE_GUIDE" >&2
  exit 2
fi

echo "# Billing Skill Corpus Extract"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Source guide: $SOURCE_GUIDE"
echo
echo "---"
echo

# ============================================================
# Triangulated kernel (the 16 north-star principles)
# ============================================================
echo "## Triangulated Kernel"
echo
# Extract from the marker-bounded block in 00-NORTH-STAR.md if present;
# else extract from the source guide § 1
if grep -q "BILLING_KERNEL_START" "$KERNEL_FILE" 2>/dev/null; then
  awk '/BILLING_KERNEL_START/,/BILLING_KERNEL_END/' "$KERNEL_FILE"
else
  echo "(Kernel markers not yet inserted in 00-NORTH-STAR.md; extracting from source guide § 1.)"
  echo
  # Extract the section, then trim the next-section header from the tail using awk.
  # (head -n -2 is GNU coreutils only; this awk approach works on macOS too.)
  awk '/^## 1\. North-star principles$/,/^## 2\./' "$SOURCE_GUIDE" | awk '
    /^## 2\./ { exit }
    { print }
  '
fi

echo
echo "---"
echo

# ============================================================
# Quote bank
# ============================================================
echo "## Quote Bank"
echo
if [[ -f "$QUOTE_FILE" ]]; then
  awk '
    /^## Quote Bank$/ { printing=1 }
    /^## Triangulated Kernel/ { printing=0 }
    printing { print }
  ' "$QUOTE_FILE"
else
  echo "(Quote bank not yet curated; see references/methodology/SOURCE-CORPUS.md)"
fi

echo
echo "---"
echo

# ============================================================
# Section index
# ============================================================
echo "## Source Guide Section Index"
echo
grep -n "^## " "$SOURCE_GUIDE" | sed 's/^/  /'
