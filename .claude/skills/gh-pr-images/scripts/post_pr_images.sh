#!/usr/bin/env bash
# Upload images to Cloudflare R2 and post them inline in a GitHub PR/issue comment.
#
# For PRIVATE repos this is the only way to render images inline without committing
# them: GitHub's camo proxy fetches the public R2 URL and serves it in the comment.
#
# Usage:
#   post_pr_images.sh --repo OWNER/REPO --number 7220 [--title "Heading"] img1.png img2.png ...
#
# Auth:
#   gh must be authenticated (token used only to post the comment).
#   R2_* env vars must be set for upload_r2.py (see that script's header).
#
# The comment is posted to the issue/PR timeline. PRs and issues share the same
# /issues/{n}/comments endpoint, so --number works for either.
set -euo pipefail

REPO=""
NUMBER=""
TITLE=""
PREFIX=""
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --number|--pr|--issue) NUMBER="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --) shift; while [[ $# -gt 0 ]]; do FILES+=("$1"); shift; done ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

[[ -z "$REPO" ]]   && { echo "error: --repo OWNER/REPO is required" >&2; exit 2; }
[[ -z "$NUMBER" ]] && { echo "error: --number N is required" >&2; exit 2; }
[[ ${#FILES[@]} -eq 0 ]] && { echo "error: at least one image file is required" >&2; exit 2; }
[[ -z "$PREFIX" ]] && PREFIX="pr-${NUMBER}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Upload and collect the Markdown image lines.
mapfile -t LINES < <(uv run --with boto3 --quiet "$SCRIPT_DIR/upload_r2.py" --prefix "$PREFIX" "${FILES[@]}")

# Assemble the comment body.
BODY=""
[[ -n "$TITLE" ]] && BODY="## ${TITLE}"$'\n\n'
for line in "${LINES[@]}"; do
  BODY+="${line}"$'\n\n'
done

# Post via gh (token auth is fine for posting comments; only the upload needed R2).
echo "$BODY" | gh api "repos/${REPO}/issues/${NUMBER}/comments" -F body=@- --jq '.html_url'
