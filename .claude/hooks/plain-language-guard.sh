#!/usr/bin/env bash
# Forwarder for work outside a repository that carries the skill itself.
# The implementation, its tests and its data live in
# ~/.claude/skills/plain-language/hooks/. Deliberately trivial, so nothing here
# can drift from it.
#
# A repository may also wire the same guard in its own .claude/settings.json, in
# which case both fire. That is handled rather than avoided: the guard caches its
# decision for a few seconds keyed on the payload and the configuration, so the
# second run replays the first one instead of scoring again.
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec bash "$here/../skills/plain-language/hooks/plain-language-guard.sh" "$@"
