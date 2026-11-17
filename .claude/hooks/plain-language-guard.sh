#!/usr/bin/env bash
# Forwarder for work outside a repository that carries the skill itself.
# The implementation, its tests and its data live in
# ~/.claude/skills/plain-language/hooks/. Deliberately trivial, so nothing here
# can drift from it.
#
# A repository may also wire the same guard in its own .claude/settings.json. Then this
# wrapper skips (see the block at the end), so the gate runs once. The guard also caches its
# decision for a few seconds keyed on the payload and the configuration, so the
# second run replays the first one instead of scoring again.
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# A project that registers its own copy of this hook runs it itself: skip here so
# the gate runs once. Any doubt or error means run (fail open to the gate).
payload=$(cat)
if printf '%s' "$payload" | python3 "$here/../skills/plain-language/hooks/plain-language-project-has-own.py" 2>/dev/null; then
  exit 0
fi
printf '%s' "$payload" | exec bash "$here/../skills/plain-language/hooks/plain-language-guard.sh" "$@"
