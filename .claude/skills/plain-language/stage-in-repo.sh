#!/usr/bin/env bash
# Stage exactly the files this skill should ship, in a repository whose
# .gitignore excludes `.claude`.
#
#   ./stage-in-repo.sh /c/WORK/desktop/master          # list what would be staged
#   ./stage-in-repo.sh /c/WORK/desktop/master --apply  # actually stage it
#
# Why this exists. The monorepo gitignores `.claude` wholesale, and its own
# CLAUDE.md tells you to use `git add -f`. But `-f` also overrides the skill's
# nested .gitignore, so `git add -f .claude/skills/plain-language` stages the
# virtualenv and the pytest cache: 934 files and 77 MB instead of 66 files and
# 4 MB. This script force-adds a computed list instead of a directory.
#
# It also handles the second trap: that repository gitignores every `*.txt`, so
# the word lists and the per-repo glossary need forcing too.
set -euo pipefail

REPO="${1:?usage: stage-in-repo.sh <repo root> [--apply]}"
APPLY="${2:-}"
REL=".claude/skills/plain-language"
DIR="$REPO/$REL"

[ -d "$REPO/.git" ] || { echo "$REPO is not a git repository" >&2; exit 1; }
[ -d "$DIR" ] || { echo "$DIR does not exist; run sync-to-monorepo.sh first" >&2; exit 1; }

# Everything except build output, caches, and corpora the host repo should not hold.
#
# evals/data/ is excluded wholesale, with one exception. Every file in there is
# either rebuildable (build_corpus.py, fetch_external.sh) or a byproduct of a
# workflow run, and human_writing.json and backtest_blocked.json additionally
# hold the text of real commits, documents and messages. rule_cases.json is the
# exception: it is the 738-case corpus that rulecheck.py scores the pattern rules
# against, so without it nobody in this repo can check the precision claim in
# SKILL.md. It stays private to this repo and is NOT shipped to the public
# dotfiles repo, because its cases are written in this repo's domain vocabulary.
mapfile -t FILES < <(
  cd "$REPO" && find "$REL" -type f \
    -not -path "*/.venv/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.pytest_cache/*" \
    -not -name "*.pyc" \
    -not -name "*.cache" \
    -not -name "uv.lock" \
    \( -not -path "*/evals/data/*" -o -name "rule_cases.json" -o -name ".gitkeep" \) \
    | sort
)

# The per-repo glossary, if the repo has one. Generated from that repo's own docs.
if [ -f "$REPO/.plainlang/glossary.txt" ]; then
  FILES+=(".plainlang/glossary.txt")
fi

bytes=0
for f in "${FILES[@]}"; do
  n=$(stat -c%s "$REPO/$f" 2>/dev/null || echo 0)
  bytes=$((bytes + n))
done

printf '%d files, %.1f MB\n' "${#FILES[@]}" "$(echo "$bytes" | awk '{print $1/1048576}')"

if [ "$APPLY" != "--apply" ]; then
  printf '\n%s\n' "would stage:"
  printf '  %s\n' "${FILES[@]}" | head -20
  [ "${#FILES[@]}" -gt 20 ] && printf '  ... and %d more\n' "$((${#FILES[@]} - 20))"
  printf '\n%s\n' "re-run with --apply to stage. Note: in a checkout shared with other"
  printf '%s\n' "agents the git index is shared too, so stage only when you are about to"
  printf '%s\n' "commit, and commit with an explicit pathspec."
  exit 0
fi

(cd "$REPO" && git add -f -- "${FILES[@]}")
printf 'staged %d files\n' "${#FILES[@]}"
printf 'commit with an explicit pathspec, so a shared index cannot sweep in other work:\n'
printf "  git commit -m '...' -- %s .plainlang/glossary.txt\n" "$REL"
