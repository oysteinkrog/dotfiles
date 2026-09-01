#!/usr/bin/env bash
# PreToolUse / Stop / UserPromptSubmit / SessionStart hook. Runs the
# plain-language gate on anything about to reach a person: writes to prose files,
# commit messages, pull request bodies, Jira and Confluence text, Slack, Zendesk,
# email, artifacts, and the chat reply itself.
#
# This wrapper does one job: find a usable python3 and the skill, then hand the
# payload to plain-language-detect.py. All the logic lives there, and the tests
# live in plain-language-guard.test.py. Run them after any change to either.
#
# Why there is no install step and no virtualenv. The scorer imports nothing
# outside the standard library, which is enforced by a test, so bare `python3`
# with a PYTHONPATH is enough. That matters because the alternative, a launcher
# a developer has to install, means the gate silently does nothing on any machine
# where nobody ran the installer. A guard that quietly stops working is worse than
# no guard.
#
# Off switches, in order of precedence:
#   PLAINLANG_OFF=1        everything off
#   PLAINLANG_MODE=warn    report, never block
#   a `plainlang: skip` line in the text itself
set -uo pipefail

[ "${PLAINLANG_OFF:-}" = "1" ] && exit 0

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# The skill sits next to this hook in a repository checkout, or is pointed at
# explicitly. Try both, and prefer the explicit one.
for candidate in \
  "${PLAINLANG_HOME:-}" \
  "$here/.." \
  "${CLAUDE_PROJECT_DIR:-}/.claude/skills/plain-language" \
  "$HOME/.claude/skills/plain-language"
do
  [ -n "$candidate" ] || continue
  if [ -f "$candidate/tool/src/plainlang/cli.py" ]; then
    SKILL=$(cd -- "$candidate" && pwd)
    break
  fi
done

# No skill, nothing to do. Silent because this hook may be wired in a repository
# that does not carry the skill; the SessionStart health check is what tells a
# developer when the skill IS present but unusable.
[ -n "${SKILL:-}" ] || exit 0

DETECT="$here/plain-language-detect.py"
[ -f "$DETECT" ] || DETECT="$SKILL/hooks/plain-language-detect.py"
[ -f "$DETECT" ] || exit 0

# Prefer a python3 that is at least 3.12, which is what the tool requires. Fall
# back to whatever python3 exists and let the detector report the version
# problem rather than dying on a syntax error.
PY=""
for cand in "${PLAINLANG_PYTHON:-}" python3.13 python3.12 python3; do
  [ -n "$cand" ] || continue
  command -v "$cand" >/dev/null 2>&1 || continue
  if "$cand" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)' 2>/dev/null; then
    PY="$cand"
    break
  fi
  [ -n "$PY" ] || PY="$cand"
done
[ -n "$PY" ] || exit 0

PLAINLANG_SKILL_DIR="$SKILL" PYTHONPATH="$SKILL/tool/src${PYTHONPATH:+:$PYTHONPATH}" \
  exec "$PY" "$DETECT"
