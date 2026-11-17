#!/usr/bin/env bash
# Forwarder. See plain-language-guard.sh.
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# A project that registers its own copy of this hook runs it itself: skip here so
# the gate runs once. Any doubt or error means run (fail open to the gate).
payload=$(cat)
if printf '%s' "$payload" | python3 "$here/../skills/plain-language/hooks/plain-language-project-has-own.py" 2>/dev/null; then
  exit 0
fi
printf '%s' "$payload" | exec bash "$here/../skills/plain-language/hooks/plain-language-health.sh" "$@"
