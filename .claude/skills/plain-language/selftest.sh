#!/usr/bin/env bash
# Prove the plain-language gate works here. Exits non-zero if anything is wrong.
# Safe to run any time, and safe to run in CI.
#
#   bash selftest.sh
#
# Everything is exercised the way the hook exercises it: bare python3, no
# virtualenv, no install step, no launcher on PATH. The one exception is the
# unit-test lane, which needs pytest and therefore uv.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${PLAINLANG_GUARD:-$HERE/hooks/plain-language-guard.sh}"
fails=0

export PLAINLANG_HOME="$HERE"
export PLAINLANG_LEXICON="$HERE/data/lexicon.tsv.gz"
PYSRC="$HERE/tool/src"

SLOP="In todays fast-paced world, our journey to remote capture is not just a feature, it is a testament to the evolving landscape of mobile motion analysis. It is worth noting that experts agree this marks a pivotal moment for the whole team and for the product overall."
PLAIN="The phone now owns its settings. The desktop shows them and sends changes back over the existing protocol. Version 26.2 adds white balance control. The 26.1 protocol ignores unknown field types, so no backport is needed. Tested on four handsets over two days, with no dropped frames."

pass() { printf '  ok    %-46s %s\n' "$1" "${2:-}"; }
fail() { printf '  FAIL  %-46s %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }

runpl() { PYTHONPATH="$PYSRC" python3 -m plainlang.cli "$@"; }

expect() {  # name, wanted-exit, text, then the pl arguments
  local name="$1" want="$2" text="$3"; shift 3
  printf '%s' "$text" | runpl "$@" >/dev/null 2>&1
  local got=$?
  [ "$got" = "$want" ] && pass "$name" "exit $got" || fail "$name" "exit $got, wanted $want"
}

echo "python"
if python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)' 2>/dev/null; then
  pass "python3 is 3.12 or newer" "$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
else
  fail "python3 is 3.12 or newer" "$(python3 -V 2>&1)"
fi
if PYTHONPATH="$PYSRC" python3 -c 'import plainlang.model' 2>/dev/null; then
  pass "the scorer imports with no virtualenv"
else
  fail "the scorer imports with no virtualenv"
fi

echo "scorer"
expect "inflated text fails the gate" 1 "$SLOP"  check - --no-color
expect "plain text passes the gate"   0 "$PLAIN" check - --no-color
expect "empty input does not crash"   0 ""       score -
if printf '%s' "$PLAIN" | runpl json - 2>/dev/null | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  pass "json output parses"
else
  fail "json output parses"
fi

echo "data"
for f in data/lexicon.tsv.gz data/simpler.tsv data/glossary.txt data/weights.json; do
  [ -s "$HERE/$f" ] && pass "$f" || fail "$f" "missing or empty"
done

echo "loaded state"
if degraded=$(PLAINLANG_SELFCHECK=1 bash "$GUARD" < /dev/null 2>&1 >/dev/null); then
  pass "fully loaded, nothing degraded"
else
  fail "fully loaded, nothing degraded" "$degraded"
fi

echo "unit tests"
if command -v uv >/dev/null 2>&1; then
  if (cd "$HERE/tool" && uv run pytest -q) >/dev/null 2>&1; then
    pass "pytest"
  else
    fail "pytest" "run: cd $HERE/tool && uv run pytest"
  fi
else
  printf '  skip  %-46s %s\n' "pytest" "uv not on PATH"
fi

echo "hook"
if [ -f "$GUARD" ]; then
  if out=$(PLAINLANG_GUARD="$GUARD" python3 "$HERE/hooks/plain-language-guard.test.py" 2>&1); then
    pass "hook cases" "$(printf '%s' "$out" | tail -1)"
  else
    fail "hook cases"
    printf '%s\n' "$out" | grep '^FAIL' | head -5
  fi
else
  printf '  skip  %-46s %s\n' "hook cases" "guard not found at $GUARD"
fi

echo "health check"
health=$(bash "$HERE/hooks/plain-language-health.sh" 2>&1)
if [ -z "$health" ]; then
  pass "reports healthy"
else
  fail "reports healthy" "$(printf '%s' "$health" | head -1)"
fi

echo
if [ "$fails" = 0 ]; then echo "all checks passed"; else echo "$fails check(s) failed"; fi
exit $((fails > 0))
