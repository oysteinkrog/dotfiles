#!/usr/bin/env bash
# PostToolUse hook for Write, Edit and MultiEdit. When the edited file is a
# .py file, runs ruff check, ruff format --check and ty check on it and hands
# any findings to the agent as additionalContext. Report only: it never
# rewrites the file (python-lint-report.py explains why).
#
# Always exits 0, so it can never fail or block the tool call. Test matrix in
# python-lint-hook.test.py. Run the tests after any change to either file.

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 0

payload=$(cat) || exit 0

# Cheap pre-filter so most edits never spawn python.
case $payload in
  *'.py"'*) ;;
  *) exit 0 ;;
esac

printf '%s' "$payload" | python3 "$here/python-lint-report.py" 2>/dev/null
exit 0
