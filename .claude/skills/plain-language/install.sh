#!/usr/bin/env bash
# Install the plain-language scorer so `pl` works from any shell and the hook
# can call it. Safe to re-run.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${PLAINLANG_BIN_DIR:-$HOME/bin}"
HOOK_DIR="${PLAINLANG_HOOK_DIR:-$HOME/.claude/hooks}"

echo "skill:  $SKILL_DIR"
echo "bin:    $BIN_DIR"

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is not on PATH. Install it first: https://docs.astral.sh/uv/" >&2
  exit 1
fi

echo "building the virtualenv"
uv sync --project "$SKILL_DIR/tool" --quiet

mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/pl" <<LAUNCHER
#!/bin/sh
# Plain-language scorer. Runs the tool's own virtualenv directly so a hook does
# not pay for \`uv run\` resolution on every call.
SKILL_DIR="\${PLAINLANG_HOME:-$SKILL_DIR}"
VENV_PY="\$SKILL_DIR/tool/.venv/bin/python"
if [ ! -x "\$VENV_PY" ]; then
  exec uv run --project "\$SKILL_DIR/tool" pl "\$@"
fi
exec "\$VENV_PY" -m plainlang.cli "\$@"
LAUNCHER
chmod +x "$BIN_DIR/pl"
echo "installed $BIN_DIR/pl"

if [ -d "$HOOK_DIR" ] && [ -f "$SKILL_DIR/hooks/plain-language-guard.py" ]; then
  cp "$SKILL_DIR/hooks/plain-language-guard.py" "$HOOK_DIR/plain-language-guard.py"
  chmod +x "$HOOK_DIR/plain-language-guard.py"
  echo "installed $HOOK_DIR/plain-language-guard.py"
fi

if [ ! -f "$SKILL_DIR/data/lexicon.tsv.gz" ]; then
  echo "no lexicon found; rebuilding it from the norm files (needs network for wordfreq)"
  uv run --project "$SKILL_DIR/tool" --with wordfreq \
    python -m plainlang.bake --norms "$SKILL_DIR/data/norms" --out "$SKILL_DIR/data/lexicon.tsv.gz"
fi

echo
echo "self test"
printf 'The phone owns its settings. The desktop shows them and sends changes back.\n' \
  | "$BIN_DIR/pl" score - || true
printf 'In todays fast-paced world, our journey to remote control is a testament to the evolving landscape.\n' \
  | "$BIN_DIR/pl" check - --no-color || true

cat <<'NEXT'

Done. Next steps:
  1. Put ~/bin on PATH if it is not already.
  2. To turn the gate on in Claude Code, add the hooks from hooks/settings-snippet.json
     to ~/.claude/settings.json.
  3. Per project, put domain terms in <repo>/.plainlang/glossary.txt so precise
     words cost nothing.
NEXT
