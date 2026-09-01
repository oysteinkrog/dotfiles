#!/usr/bin/env bash
# Forwarder. See plain-language-guard.sh.
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec bash "$here/../skills/plain-language/hooks/plain-language-health.sh" "$@"
