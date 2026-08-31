#!/usr/bin/env bash
# Push this skill into a repository that should carry its own copy.
#
#   ./sync-to-monorepo.sh /c/WORK/desktop/master
#
# The dotfiles copy is the single source. This repository is public, so the eval
# corpora built from a private repo are excluded here and gitignored there; the
# target keeps its own.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_REPO="${1:?usage: sync-to-monorepo.sh <repo root>}"
DEST="$TARGET_REPO/.claude/skills/plain-language"

[ -d "$TARGET_REPO/.git" ] || { echo "$TARGET_REPO is not a git repository" >&2; exit 1; }
mkdir -p "$DEST"

tar --exclude='.venv' --exclude='__pycache__' --exclude='*.pyc' --exclude='*.cache' \
    --exclude='evals/data/external' --exclude='evals/data/human_writing.json' \
    --exclude='evals/data/backtest_blocked.json' \
    --exclude='sync-to-monorepo.sh' \
    --exclude='stage-in-repo.sh' \
    -cf - -C "$(dirname "$SRC")" "$(basename "$SRC")" | tar -xf - -C "$(dirname "$DEST")"

python3 - "$DEST/SKILL.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
note = """# Plain language

> Synced from `~/.dotfiles/.claude/skills/plain-language`, which is the single
> source. Edit there and re-run `sync-to-monorepo.sh`; a change made only here
> will be overwritten. The dotfiles copy is public, so the eval corpora built from
> this repository live only here.
"""
if "Synced from" not in t:
    p.write_text(t.replace("# Plain language\n", note, 1), encoding="utf-8")
    print("  added the provenance note")
PY

echo "synced to $DEST"
cat <<NEXT

next:
  PLAINLANG_HOME=$DEST bash $DEST/selftest.sh
  $SRC/stage-in-repo.sh $TARGET_REPO            # list what should be staged
  $SRC/stage-in-repo.sh $TARGET_REPO --apply    # stage it

Do not run "git add -f" on the directory. That repository gitignores .claude, and
-f also overrides this skill's own .gitignore, so it would stage the virtualenv:
934 files and 77 MB instead of 66 and 4 MB.
NEXT
