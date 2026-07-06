#!/usr/bin/env bash
# scan-secrets.sh — Scan files for leaked secrets.
#
# Used by:
#   - .git_template/hooks/pre-commit (repo hook via core.hooksPath; --staged)
#   - manual full sweeps over tracked files (--all)
#
# Usage:
#   scan-secrets.sh --staged     # Pre-commit: scan git staged content
#   scan-secrets.sh --all        # CI: scan all tracked files
#   scan-secrets.sh FILE [FILE]  # Scan specific files
#
# Exit code: 0 = clean, 1 = secrets found

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ── Secret patterns ─────────────────────────────────────────────────────
# Format: "regex|description"
# These are checked against file content. Add new patterns here.

SECRET_PATTERNS=(
    'ANTHROPIC_API_KEY.*["'"'"'][a-zA-Z0-9_]{20,}["'"'"']|Anthropic API key in config'
    'bccf_[a-f0-9]{30,}|better-ccflare proxy key'
    'sk-ant-api[a-zA-Z0-9_-]{20,}|Anthropic direct API key'
    'sk-proj-[a-zA-Z0-9_-]{20,}|OpenAI project API key'
    'AIzaSy[a-zA-Z0-9_-]{30,}|Google API key'
    'ghp_[a-zA-Z0-9]{30,}|GitHub personal access token'
    'gho_[a-zA-Z0-9]{30,}|GitHub OAuth token'
    'ghs_[a-zA-Z0-9]{30,}|GitHub server token'
    'github_pat_[a-zA-Z0-9_]{50,}|GitHub fine-grained PAT'
    'xoxb-[a-zA-Z0-9-]{30,}|Slack bot token'
    'xoxp-[a-zA-Z0-9-]{30,}|Slack user token'
    'HCLOUD_TOKEN.*[a-zA-Z0-9]{30,}|Hetzner Cloud token'
    'DASHBOARD_PASSWORD.*[a-zA-Z0-9/+=]{15,}|Dashboard password'
    'Bearer [a-zA-Z0-9_.-]{40,}|Hardcoded bearer token'
    'ssh-ed25519 AAAA[a-zA-Z0-9+/]{60,}|SSH private key material'
    'BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY|Private key file'
    'MCP_AGENT_MAIL_TOKEN.*[a-f0-9]{40,}|Agent mail token'
)

# Files/patterns to skip (binary, lock files, etc.)
SKIP_PATTERNS="\.png$|\.jpg$|\.gif$|\.ico$|\.woff|\.ttf|\.lock$|\.pyc$"

# ── Argument parsing ────────────────────────────────────────────────────

MODE=""
FILES=()

for arg in "$@"; do
    case "$arg" in
        --staged) MODE="staged" ;;
        --all)    MODE="all" ;;
        *)        FILES+=("$arg") ;;
    esac
done

if [ "$MODE" = "staged" ]; then
    mapfile -t FILES < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
elif [ "$MODE" = "all" ]; then
    mapfile -t FILES < <(git ls-files 2>/dev/null || true)
fi

if [ ${#FILES[@]} -eq 0 ]; then
    exit 0
fi

# ── Scan ────────────────────────────────────────────────────────────────

FOUND=0

for file in "${FILES[@]}"; do
    # Skip binary/irrelevant files
    if echo "$file" | grep -qE "$SKIP_PATTERNS"; then
        continue
    fi

    # Get content: staged content for pre-commit, file content otherwise
    if [ "$MODE" = "staged" ]; then
        CONTENT=$(git show ":$file" 2>/dev/null || true)
    else
        [ -f "$file" ] || continue
        CONTENT=$(cat "$file" 2>/dev/null || true)
    fi

    [ -z "$CONTENT" ] && continue

    for pattern_entry in "${SECRET_PATTERNS[@]}"; do
        PATTERN="${pattern_entry%%|*}"
        DESC="${pattern_entry##*|}"

        if echo "$CONTENT" | grep -qE "$PATTERN" 2>/dev/null; then
            if [ "$FOUND" -eq 0 ]; then
                echo -e "${RED}ERROR: Potential secrets detected!${NC}" >&2
                echo "" >&2
            fi
            FOUND=$((FOUND + 1))
            echo -e "  ${YELLOW}${file}${NC}: ${DESC}" >&2
        fi
    done
done

if [ "$FOUND" -gt 0 ]; then
    echo "" >&2
    echo -e "${RED}Found ${FOUND} potential secret(s).${NC}" >&2
    echo "" >&2
    echo "To bypass pre-commit hook: git commit --no-verify" >&2
    echo "To add an exception: edit .claude/scripts/scan-secrets.sh" >&2
    exit 1
fi

exit 0
