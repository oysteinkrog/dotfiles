#!/usr/bin/env bash
# self-test.sh — meta-pass that audits the SKILL itself.
#
# The skill audits Rust projects; this script audits the skill's installation
# to detect corruption / drift / missing referenced files / slop words / orphan
# subagents / broken markdown links.
#
# Usage:
#   scripts/self-test.sh                # run all checks
#   scripts/self-test.sh --quick        # skip slow checks (slop scan)
#
# Exit 0 = clean. Exit non-zero = something to fix.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

EXIT=0
fail() { echo "FAIL: $*" >&2; EXIT=1; }
ok()   { echo "  ok: $*"; }
hdr()  { echo; echo "== $* =="; }

python_syntax_ok() {
  python3 - "$1" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
except SyntaxError as exc:
    location = f"{exc.filename}:{exc.lineno or 0}:{exc.offset or 0}"
    print(f"{location}: SyntaxError: {exc.msg}", file=sys.stderr)
    if exc.text:
        print(exc.text.rstrip(), file=sys.stderr)
    sys.exit(1)
PY
}

cd "$SKILL_DIR"

# 1. Validators
hdr "validators"
if python3 scripts/validate-corpus.py >/dev/null 2>&1; then ok "validate-corpus.py"
else fail "validate-corpus.py"; python3 scripts/validate-corpus.py || true; fi
if python3 scripts/validate-operators.py >/dev/null 2>&1; then ok "validate-operators.py"
else fail "validate-operators.py"; python3 scripts/validate-operators.py || true; fi

# 2. Bash syntax for every script
hdr "bash syntax"
for f in scripts/*.sh; do
  if bash -n "$f" 2>/dev/null; then ok "$f"
  else fail "$f"; bash -n "$f" || true; fi
done

# 3. Node syntax/runtime sanity for every .mjs against a minimal audit fixture
hdr "node syntax (.mjs)"
PROJECT_TMP=$(mktemp -d)
printf '[package]\nname = "self_test_fixture"\nversion = "0.0.0"\nedition = "2021"\n' > "$PROJECT_TMP/Cargo.toml"
TMPDIR="$PROJECT_TMP/.unsafe-audit"
mkdir -p "$TMPDIR/phase1" "$TMPDIR/audit/classification" "$TMPDIR/audit/synthesis"
printf '%s\n' "$PROJECT_TMP" > "$TMPDIR/phase1/project-root.txt"
# Provide a minimal valid inventory + classification so scripts that consume them
# don't fail on missing-input vs real syntax errors.
echo '{"id":"site-0001","crate":"x","file":"a.rs","line_start":1,"line_end":1,"kind":"block","enclosing_fn":null,"enclosing_type":null,"public_api_exposed":false,"macro_origin":false,"ffi":false,"intrinsic":false,"source_excerpt":"","geiger_count":1,"ubs_findings":[]}' \
  > "$TMPDIR/unsafe-inventory.jsonl"
echo '{"id":"site-0001","bucket":"C","confidence":0.9,"prior_bucket":"C"}' \
  > "$TMPDIR/audit/classification/summary.jsonl"
for f in scripts/*.mjs; do
  set +e
  out=$(node "$f" "$TMPDIR" 2>&1); ec=$?
  set -e
  if [ "$ec" -eq 0 ]; then ok "$f"
  else
    # If it's a usage-style error (missing input), tolerate; only fail on real parse / runtime crashes
    if echo "$out" | grep -qE 'SyntaxError|ReferenceError|TypeError'; then
      fail "$f"; echo "$out" | sed 's/^/    /'
    else
      ok "$f (non-syntax exit $ec — likely missing-input check; tolerated)"
    fi
  fi
done

# 4. Python syntax for every .py
hdr "python syntax"
for f in scripts/*.py; do
  if python_syntax_ok "$f" 2>/dev/null; then ok "$f"
  else fail "$f"; python_syntax_ok "$f" || true; fi
done

# 5. Markdown link resolution
# Strip fenced code blocks (```...```) before scanning, since example HEREDOCs
# and snippet code can reference paths that don't exist in THIS repo (e.g., the
# user's project README's SECURITY.md badge link).
hdr "markdown links resolve"
broken=0
while IFS= read -r -d '' f; do
  # Use awk to filter out fenced code blocks
  CONTENT=$(awk 'BEGIN{c=0} /^```/{c=1-c; next} c==0{print}' "$f")
  while IFS= read -r line; do
    # Find every markdown link to a .md file in this line
    while IFS= read -r link; do
      [ -z "$link" ] && continue
      echo "$link" | grep -qE '^https?://' && continue
      link_path="${link%%#*}"
      [ -z "$link_path" ] && continue
      target=$(cd "$(dirname "$f")" 2>/dev/null && readlink -f "$link_path" 2>/dev/null || echo "")
      if [ -z "$target" ] || [ ! -f "$target" ]; then
        echo "  broken: $f -> $link"
        broken=$((broken + 1))
      fi
    done < <(printf '%s\n' "$line" | grep -oE '\]\([^)]+\.md[^)]*\)' 2>/dev/null | sed 's/^](//; s/)$//' || true)
  done <<< "$CONTENT"
done < <(find . -name '*.md' -type f -not -path './.git/*' -print0 2>/dev/null)
if [ "$broken" -eq 0 ]; then ok "all markdown links resolve"
else fail "$broken broken links"; fi

# 6. Slop-word scan (the explicit banned list per AGENTS.md)
if [ "$QUICK" -ne 1 ]; then
  hdr "slop-word scan"
  slop=0
  # NOTE: set -euo pipefail will kill us on grep-no-match unless we `|| true`.
  while IFS= read -r -d '' f; do
    # Exclude files that LIST the banned words as a reminder (the kernel-bounded
    # AGENT-PROMPTS.md doc + the QUICK-REFERENCE banned-slop section).
    raw=$(grep -niE 'load-bearing|the moment|first-class|white-glove|battle-tested|rock-solid|future-proof|industry-leading' "$f" 2>/dev/null || true)
    if [ -z "$raw" ]; then continue; fi
    filtered=$(echo "$raw" | grep -vE 'banned|Banned|exception is the AGENT-PROMPTS|^[0-9]+:## Banned|slop-allowlist' || true)
    # Drop the line that immediately follows a "<!-- slop-allowlist:" marker line
    # (the marker grants the next line a pass; this single-line check is good enough
    # for the audit's discipline).
    # Iterate per-line so we can check the prior line of the source file.
    if [ -n "$filtered" ]; then
      newfiltered=""
      while IFS= read -r match_line; do
        # match_line is like "184:text"
        ln=${match_line%%:*}
        prev_ln=$((ln - 1))
        prev=$(sed -n "${prev_ln}p" "$f" 2>/dev/null || true)
        if echo "$prev" | grep -q 'slop-allowlist'; then
          continue
        fi
        newfiltered="${newfiltered}${match_line}"$'\n'
      done <<< "$filtered"
      filtered="${newfiltered%$'\n'}"
    fi
    if [ -n "$filtered" ]; then
      echo "$filtered" | sed "s|^|  $f: |"
      slop=$((slop + 1))
    fi
  done < <(find . -name '*.md' -type f -not -path './.git/*' -print0)
  if [ "$slop" -eq 0 ]; then ok "no slop"
  else fail "$slop files with slop-words"; fi
fi

# 7. Orphan subagent check — every subagents/*.md referenced from at least
#    one of PHASES.md / AGENT-PROMPTS.md / DECISION-TREE.md / SKILL.md /
#    QUICK-REFERENCE.md
hdr "subagent reference check"
orphans=0
for sa in subagents/*.md; do
  base=$(basename "$sa" .md)
  # Look for the subagent name across referencing docs
  if grep -rqE "$base" \
       references/methodology/PHASES.md \
       references/methodology/AGENT-PROMPTS.md \
       references/methodology/DECISION-TREE.md \
       references/methodology/QUICK-REFERENCE.md \
       SKILL.md 2>/dev/null; then
    ok "subagents/$base referenced"
  else
    fail "subagents/$base appears orphan (not referenced from PHASES/AGENT-PROMPTS/DECISION-TREE/QUICK-REFERENCE/SKILL.md)"
    orphans=$((orphans + 1))
  fi
done

# 8. Orphan script check — every scripts/*.sh + .mjs + .py referenced from
#    at least one .md
hdr "script reference check"
for sc in scripts/*.sh scripts/*.mjs scripts/*.py; do
  base=$(basename "$sc")
  if grep -rq "$base" --include='*.md' . 2>/dev/null; then
    ok "$sc referenced"
  else
    fail "$sc appears orphan (not mentioned in any .md)"
  fi
done

# 9. Pattern-bundle naming continuity (no gaps in NN- prefix sequence is required;
#    just check files have well-formed names and 95-INDEX references them all).
hdr "pattern-bundle index consistency"
missing_from_index=0
for pb in references/patterns/*.md; do
  base=$(basename "$pb")
  [ "$base" = "95-INDEX.md" ] && continue
  if grep -q "$base" references/patterns/95-INDEX.md 2>/dev/null; then
    ok "$base in 95-INDEX"
  else
    fail "$base missing from 95-INDEX"
    missing_from_index=$((missing_from_index + 1))
  fi
done

# 10. Frontmatter present on every subagent
hdr "subagent frontmatter"
for sa in subagents/*.md; do
  if head -1 "$sa" | grep -q '^---$'; then ok "$sa"
  else fail "$sa missing frontmatter"; fi
done

echo
if [ "$EXIT" -eq 0 ]; then
  echo "self-test: ALL CHECKS PASSED"
else
  echo "self-test: FAILURES DETECTED — exit $EXIT"
fi
exit "$EXIT"
