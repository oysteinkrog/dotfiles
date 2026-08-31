#!/usr/bin/env bash
# Check that the scorer, the gate and the hook all work on this machine.
# Exits non-zero if anything is wrong. Safe to run any time.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PL="${PLAINLANG_BIN:-$HOME/bin/pl}"
GUARD="${PLAINLANG_GUARD:-$HOME/.claude/hooks/plain-language-guard.py}"
fails=0

check() {  # name, expected exit, command...
  local name="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then
    printf '  ok    %-42s exit %s\n' "$name" "$got"
  else
    printf '  FAIL  %-42s exit %s, wanted %s\n' "$name" "$got" "$want"
    fails=$((fails + 1))
  fi
}

SLOP="In today's fast-paced world, our journey to remote capture is not just a feature, it is a testament to the evolving landscape. It is worth noting that experts agree this marks a pivotal moment, underscoring our commitment to excellence and delivering a seamless, robust and comprehensive result for every user."
PLAIN="The phone now owns its own settings. The desktop shows them and sends changes back over the existing protocol. Version 26.2 adds white balance control. The 26.1 protocol already ignores unknown field types, so we do not need a backport. I tested it on four handsets over two days and saw no dropped frames."

echo "scorer"
if [ ! -x "$PL" ]; then
  echo "  FAIL  pl is not installed at $PL (run install.sh)"
  exit 1
fi
check "inflated text fails the gate" 1 sh -c "printf '%s' \"$SLOP\" | '$PL' check - --no-color"
check "plain text passes the gate"   0 sh -c "printf '%s' \"$PLAIN\" | '$PL' check - --no-color"
check "empty input does not crash"   0 sh -c "printf '' | '$PL' score -"
check "json output parses"           0 sh -c "printf '%s' \"$PLAIN\" | '$PL' json - | python3 -c 'import json,sys; json.load(sys.stdin)'"

echo "data"
for f in data/lexicon.tsv.gz data/simpler.tsv data/glossary.txt data/weights.json; do
  if [ -s "$HERE/$f" ]; then printf '  ok    %-42s\n' "$f"
  else printf '  FAIL  %-42s missing or empty\n' "$f"; fails=$((fails + 1)); fi
done

echo "unit tests"
if command -v uv >/dev/null 2>&1; then
  if (cd "$HERE/tool" && uv run pytest -q) >/dev/null 2>&1; then
    printf '  ok    %-42s\n' "pytest"
  else
    printf '  FAIL  %-42s\n' "pytest"; fails=$((fails + 1))
  fi
else
  printf '  skip  %-42s uv not on PATH\n' "pytest"
fi

echo "hook"
if [ -f "$GUARD" ]; then
  if PLAINLANG_GUARD="$GUARD" python3 "$HERE/hooks/test_guard.py" > /tmp/plainlang-hooktest.log 2>&1; then
    printf '  ok    %-42s %s\n' "hook cases" "$(tail -1 /tmp/plainlang-hooktest.log)"
  else
    printf '  FAIL  %-42s\n' "hook cases"; sed -n '/^FAIL/p' /tmp/plainlang-hooktest.log | head -5
    fails=$((fails + 1))
  fi
else
  printf '  skip  %-42s guard not installed\n' "hook"
fi

echo
if [ "$fails" = 0 ]; then echo "all checks passed"; else echo "$fails check(s) failed"; fi
exit $((fails > 0))
