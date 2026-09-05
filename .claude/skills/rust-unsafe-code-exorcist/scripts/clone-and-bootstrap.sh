#!/usr/bin/env bash
# clone-and-bootstrap.sh — clone a Rust project from a URL + bootstrap the audit dir.
#
# Usage:
#   clone-and-bootstrap.sh <git-url> [--ref <branch|tag|sha>] [--subdir <path>]
#                          [--shallow] [--clone-root <dir>] [--audit-dir <dir-under-project>]
#
# Examples:
#   # Default — clone to /tmp/<basename>, audit dir inside the project
#   clone-and-bootstrap.sh https://github.com/tokio-rs/tokio
#
#   # Specific tag, monorepo subdir, ~/audits as clone root
#   clone-and-bootstrap.sh https://github.com/rust-lang/rust \
#       --ref 1.89.0 --subdir library/std --clone-root ~/audits
#
#   # Shallow clone (faster; loses pre-50-commit history for archeology)
#   clone-and-bootstrap.sh git@github.com:owner/private --shallow
#
# Output:
#   - Cloned repo at <clone-root>/<basename> (or timestamped variant if collision).
#   - Audit dir at <project>/.unsafe-audit, or another dir inside <project>, git-init'd.
#   - check-prerequisites + check-skills run + reported.
#   - Next-step commands printed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

URL=""
REF=""
SUBDIR=""
SHALLOW=0
CLONE_ROOT="/tmp"
AUDIT_DIR_OVERRIDE=""

require_value() {
  local flag="$1"
  local value="${2-}"
  if [ -z "$value" ] || [[ "$value" == -* ]]; then
    echo "error: $flag requires a value" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ref) require_value "$1" "${2-}"; REF="$2"; shift 2 ;;
    --subdir) require_value "$1" "${2-}"; SUBDIR="$2"; shift 2 ;;
    --shallow) SHALLOW=1; shift ;;
    --clone-root) require_value "$1" "${2-}"; CLONE_ROOT="$2"; shift 2 ;;
    --audit-dir) require_value "$1" "${2-}"; AUDIT_DIR_OVERRIDE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,21p' "$0"; exit 0 ;;
    -*)
      echo "unknown flag: $1" >&2; exit 2 ;;
    *)
      if [ -z "$URL" ]; then URL="$1"; shift
      else echo "unexpected positional: $1" >&2; exit 2; fi ;;
  esac
done

if [ -z "$URL" ]; then
  echo "usage: clone-and-bootstrap.sh <git-url> [flags]" >&2
  echo "       run with --help for full options" >&2
  exit 2
fi

# Derive basename. Strip .git suffix; handle both HTTPS and SSH forms.
basename_of_url() {
  local u="$1"
  u="${u%.git}"
  u="${u%/}"
  # SSH form: git@host:owner/repo
  if [[ "$u" == *":"* ]] && [[ "$u" != *"//"* ]]; then
    u="${u##*:}"  # strip git@host:
  fi
  echo "${u##*/}"
}

BASENAME=$(basename_of_url "$URL")
if [ -z "$BASENAME" ]; then
  echo "could not derive basename from URL: $URL" >&2; exit 2
fi

CLONE_DIR="$CLONE_ROOT/$BASENAME"
if [ -e "$CLONE_DIR" ]; then
  TS=$(date -u +%Y%m%dT%H%M%SZ)
  CLONE_DIR="$CLONE_ROOT/${BASENAME}-${TS}"
  echo "note: $CLONE_ROOT/$BASENAME already exists; cloning to $CLONE_DIR instead" >&2
fi

mkdir -p "$CLONE_ROOT"

# Clone
echo "==> Cloning $URL into $CLONE_DIR"
CLONE_ARGS=()
if [ "$SHALLOW" = "1" ]; then CLONE_ARGS+=("--depth" "50"); fi
git clone "${CLONE_ARGS[@]}" "$URL" "$CLONE_DIR"

# Ref checkout
if [ -n "$REF" ]; then
  echo "==> Checking out ref: $REF"
  if (cd "$CLONE_DIR" && git fetch --tags origin "$REF" >/dev/null 2>&1); then
    (cd "$CLONE_DIR" && git -c advice.detachedHead=false switch --detach FETCH_HEAD)
  else
    (cd "$CLONE_DIR" && git -c advice.detachedHead=false switch --detach "$REF")
  fi
fi

# Resolve project root (clone root, or subdir if monorepo)
PROJECT="$CLONE_DIR"
if [ -n "$SUBDIR" ]; then
  PROJECT="$CLONE_DIR/$SUBDIR"
  if [ ! -d "$PROJECT" ]; then
    echo "error: --subdir target does not exist: $PROJECT" >&2; exit 1
  fi
fi

# Sanity-check it looks like a Rust project
if [ ! -f "$PROJECT/Cargo.toml" ]; then
  echo "warning: no Cargo.toml at $PROJECT — is this actually a Rust project?" >&2
  echo "         (the audit will still run, but enumeration may produce nothing)" >&2
fi

# Audit dir
if [ -n "$AUDIT_DIR_OVERRIDE" ]; then
  # Relative overrides are resolved from the project root. Absolute overrides
  # are accepted only if they still resolve under the project root.
  case "$AUDIT_DIR_OVERRIDE" in
    /*) AUDIT_DIR="$AUDIT_DIR_OVERRIDE" ;;
    *) AUDIT_DIR="$PROJECT/$AUDIT_DIR_OVERRIDE" ;;
  esac
else
  # Contained in the project tree; existing source files stay read-only.
  AUDIT_DIR="${PROJECT}/.unsafe-audit"
fi

PROJECT_ABS=$(audit_realpath "$PROJECT")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT_ABS")

if [ -e "$AUDIT_DIR" ]; then
  echo "note: audit dir already exists at $AUDIT_DIR (treating as resume)"
else
  mkdir -p "$AUDIT_DIR"
  (cd "$AUDIT_DIR" && git init -q)
  # Drop the gitignore + audit-dir README templates if present
  if [ -f "$SKILL_DIR/assets/audit-dir-gitignore.template" ]; then
    cp "$SKILL_DIR/assets/audit-dir-gitignore.template" "$AUDIT_DIR/.gitignore"
  fi
  if [ -f "$SKILL_DIR/assets/audit-dir-readme.template" ]; then
    cp "$SKILL_DIR/assets/audit-dir-readme.template" "$AUDIT_DIR/README.md"
  fi
fi

# Report the ignore entry the outer project may want. Do not write it here:
# audit-only mode promises existing project files stay untouched.
if [ -d "$PROJECT/.git" ] || git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
  PROJECT_GITIGNORE="$PROJECT/.gitignore"
  AUDIT_REL=$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]).replace(os.sep, "/"))' "$AUDIT_DIR" "$PROJECT_ABS")
  IGNORE_ENTRY="/$AUDIT_REL"
  if [ ! -f "$PROJECT_GITIGNORE" ] || ! grep -qxF "$IGNORE_ENTRY" "$PROJECT_GITIGNORE" 2>/dev/null; then
    echo "==> note: add '$IGNORE_ENTRY' to $PROJECT_GITIGNORE if you want the outer git repo to ignore the audit dir"
  fi
fi

echo "==> Clone target:  $CLONE_DIR"
echo "==> Project root:  $PROJECT"
echo "==> Audit dir:     $AUDIT_DIR"
echo

# Run check-prerequisites + check-skills
if [ -x "$SKILL_DIR/scripts/check-prerequisites.sh" ]; then
  echo "==> check-prerequisites:"
  "$SKILL_DIR/scripts/check-prerequisites.sh" || true
  echo
fi
if [ -x "$SKILL_DIR/scripts/check-skills.sh" ]; then
  echo "==> check-skills:"
  "$SKILL_DIR/scripts/check-skills.sh" "$AUDIT_DIR" || true
  echo
fi

# Print next-step commands
cat <<EOF
==> Next steps:

# Enumerate unsafe sites
"$SKILL_DIR/scripts/enumerate-unsafe.sh" "$PROJECT" "$AUDIT_DIR"
node "$SKILL_DIR/scripts/generate-inventory.mjs" "$AUDIT_DIR"

# Run the orchestrator in your local coding-agent session
# /rust-unsafe-code-exorcist "$PROJECT" --audit-dir "$AUDIT_DIR" --mode audit-only

# Resume / re-run is idempotent — re-running this bootstrap script will
# detect the existing audit dir and treat it as a resume.
EOF
