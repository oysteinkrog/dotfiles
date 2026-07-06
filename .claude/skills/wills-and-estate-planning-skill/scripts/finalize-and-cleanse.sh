#!/usr/bin/env bash
# finalize-and-cleanse.sh — Delete intermediate estate-planning work products.
#
# Purpose. Reduce the contemporaneous paper trail left in a user's working
# folder after they have saved AND EMAILED the final package somewhere
# safe. Without this cleanup, the skill's intake record, decision ledger,
# analyses, drafts, and session logs accumulate exactly the kind of
# discoverable record a will-contest lawyer would love to see. For HNW/UHNW
# testators who anticipate challenge, this script lets the user delete
# that paper trail on their own files, at their own direction, at a time
# when no litigation is pending.
#
# This script is DESTRUCTIVE. It is NOT a substitute for legal advice. For
# deathbed drafting, capacity-fragile changes, or wills expected to be
# contested, the user still needs a human attorney as drafter and witness.
#
# Required to proceed (ALL of the below):
#
#   1.  --confirm-i-saved-the-final-package  flag on the command line
#   2.  FINAL_PACKAGE_SAVED.txt              file in the project directory,
#                                            containing at minimum:
#                                            - one '@' character (email)
#                                            - the word "EMAILED" or "SENT"
#                                            - the word "SAVED" or "STORED"
#   3.  "YES I SAVED AND EMAILED THE FINAL PACKAGE"   typed at the
#                                            interactive prompt (or
#                                            --yes-delete for unattended
#                                            use by the subagent)
#
# What is swept:
#
#   Directories:   intake/ analyses/ decisions/ drafts/ session-logs/
#                  working/ tmp/
#                  deliverables/   (except deliverables/final/)
#
#   Top-level:     intake-record.md, decision-ledger.md
#
#   Patterns:      *.tmp, *.scratch.*, DRAFT_*, SCRATCH_*, *.draft.md
#                  (at any depth, except the preserve list below)
#
# What is preserved:
#
#   FINAL_PACKAGE_SAVED.txt       the user's save marker
#   CLEANED.md                    this script writes it after the sweep
#   deliverables/final/           the user's curated final outputs
#   user-provided/                the user's original uploads
#   Anything listed (one path per line) in intake-inputs.txt
#   Anything outside the swept directories and not matching a swept pattern
#
# Containment. The script refuses to run on '/', the user's $HOME, or any
# path shallower than three directory levels from root.

set -euo pipefail

PROGNAME="$(basename -- "$0")"

usage() {
  cat >&2 <<EOF
Usage: $PROGNAME <project-dir> --confirm-i-saved-the-final-package [--yes-delete]

  <project-dir>                           path to the estate-planning working folder
  --confirm-i-saved-the-final-package     required; explicit caller acknowledgement
  --yes-delete                            optional; skip interactive confirmation prompt
                                          (required when stdin is not a terminal)

Refuses to run without ALL of: the --confirm flag, a valid
FINAL_PACKAGE_SAVED.txt, and the typed "YES I SAVED AND EMAILED THE FINAL
PACKAGE" confirmation (or --yes-delete from the subagent).
EOF
}

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
if [[ "$#" -lt 1 ]]; then
  usage; exit 2
fi

PROJECT_DIR="$1"; shift
CONFIRM_FLAG=""
YES_DELETE_FLAG=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --confirm-i-saved-the-final-package) CONFIRM_FLAG="yes" ;;
    --yes-delete)                        YES_DELETE_FLAG="yes" ;;
    -h|--help)                           usage; exit 0 ;;
    *)                                   echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

if [[ "$CONFIRM_FLAG" != "yes" ]]; then
  echo "ERROR: missing required --confirm-i-saved-the-final-package flag." >&2
  usage; exit 2
fi

# --------------------------------------------------------------------------
# Containment checks
# --------------------------------------------------------------------------
if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: project directory does not exist: $PROJECT_DIR" >&2
  exit 2
fi

RESOLVED="$(cd "$PROJECT_DIR" && pwd -P)"
HOME_RESOLVED="$(cd "$HOME" && pwd -P)"

if [[ "$RESOLVED" == "/" ]]; then
  echo "ERROR: refusing to run on root '/'." >&2; exit 2
fi
if [[ "$RESOLVED" == "$HOME_RESOLVED" ]]; then
  echo "ERROR: refusing to run on the user's home directory ($HOME_RESOLVED)." >&2; exit 2
fi

# Reject shallow system paths (depth < 3 directory levels from /).
DEPTH="$(awk -F/ '{print NF-1}' <<<"$RESOLVED")"
if [[ "$DEPTH" -lt 3 ]]; then
  echo "ERROR: refusing to run on shallow path (depth $DEPTH): $RESOLVED" >&2
  echo "       Work in a project-specific subfolder such as ~/Documents/my-estate-plan." >&2
  exit 2
fi

cd "$RESOLVED"

# --------------------------------------------------------------------------
# Saved-marker gate: FINAL_PACKAGE_SAVED.txt must exist AND describe a
# real save-and-email event.
# --------------------------------------------------------------------------
if [[ ! -f "FINAL_PACKAGE_SAVED.txt" ]]; then
  cat >&2 <<EOF
ERROR: FINAL_PACKAGE_SAVED.txt not found in $RESOLVED

This is the human-in-the-loop checkpoint. Before this script will run,
you must manually create FINAL_PACKAGE_SAVED.txt in your working folder,
with plain-text content that names:

  1. WHERE you saved the final package (e.g. a Dropbox folder, a USB
     stick in your safe, iCloud path, encrypted drive). Use the word
     "SAVED" or "STORED".

  2. WHO you emailed it to (yourself at a different address, your
     attorney, your spouse, your executor). Include at least one email
     address (must contain '@'). Use the word "EMAILED" or "SENT".

Example:

    I SAVED the final estate plan to: Dropbox /Estate/2026-04/ and a
    USB stick in the home safe.

    I EMAILED the final estate plan to: myself at firstname@example.com
    and to my attorney at janedoe@examplefirm.com.

Refusing to run until this file exists and contains those markers.
EOF
  exit 2
fi

# Validate the file's content: at least one '@', the EMAILED-or-SENT word,
# and the SAVED-or-STORED word.
MARKER_CONTENT="$(cat FINAL_PACKAGE_SAVED.txt)"

if ! grep -q '@' <<<"$MARKER_CONTENT"; then
  echo "ERROR: FINAL_PACKAGE_SAVED.txt does not contain an '@' character; no email address recorded." >&2
  echo "       Add a line naming who you emailed the final package to (at least one email address)." >&2
  exit 2
fi

if ! grep -qiwE '(EMAILED|SENT)' <<<"$MARKER_CONTENT"; then
  echo "ERROR: FINAL_PACKAGE_SAVED.txt does not contain the word EMAILED or SENT (case-insensitive, whole-word)." >&2
  echo "       Describe explicitly that you emailed (or sent) the final package, and to whom." >&2
  exit 2
fi

if ! grep -qiwE '(SAVED|STORED)' <<<"$MARKER_CONTENT"; then
  echo "ERROR: FINAL_PACKAGE_SAVED.txt does not contain the word SAVED or STORED (case-insensitive, whole-word)." >&2
  echo "       Describe explicitly where you saved (or stored) the final package." >&2
  exit 2
fi

# --------------------------------------------------------------------------
# Show the user what is about to happen
# --------------------------------------------------------------------------
cat <<EOF
========================================================================
FINALIZE AND CLEANSE
========================================================================
Working folder:  $RESOLVED

This will DELETE the following, permanently:

  Directories:   intake/ analyses/ decisions/ drafts/ session-logs/
                 working/ tmp/
                 deliverables/   (except deliverables/final/)

  Top-level:     intake-record.md, decision-ledger.md

  Patterns:      *.tmp, *.scratch.*, DRAFT_*, SCRATCH_*, *.draft.md
                 (anywhere in the working folder)

It will PRESERVE:

  FINAL_PACKAGE_SAVED.txt      your save marker
  CLEANED.md                   the summary of this run
  deliverables/final/          your curated final outputs (if you made one)
  user-provided/               your original uploads (if present)
  intake-inputs.txt whitelist  any path listed there
  Everything else              (files outside the swept dirs and patterns)

========================================================================
EOF

# --------------------------------------------------------------------------
# Interactive typed-confirmation gate
# --------------------------------------------------------------------------
EXPECTED_CONFIRMATION="YES I SAVED AND EMAILED THE FINAL PACKAGE"

if [[ "$YES_DELETE_FLAG" != "yes" ]]; then
  if [[ ! -t 0 ]]; then
    echo "ERROR: stdin is not a terminal; use --yes-delete for unattended runs." >&2
    exit 2
  fi
  printf 'Type exactly:\n    %s\n(anything else aborts): ' "$EXPECTED_CONFIRMATION"
  read -r REPLY_INPUT || REPLY_INPUT=""
  if [[ "$REPLY_INPUT" != "$EXPECTED_CONFIRMATION" ]]; then
    echo ""
    echo "Aborted. No files were deleted."
    exit 0
  fi
fi

# --------------------------------------------------------------------------
# Whitelist helper (portable; no associative arrays)
# --------------------------------------------------------------------------
is_whitelisted() {
  local rel="$1"
  [[ -f intake-inputs.txt ]] || return 1
  grep -Fxq -- "$rel" intake-inputs.txt
}

# --------------------------------------------------------------------------
# Sweep
# --------------------------------------------------------------------------
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
DELETED_LIST=()

safe_rm_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    local res
    res="$(cd "$dir" && pwd -P)"
    if [[ "$res" != "$RESOLVED/"* && "$res" != "$RESOLVED" ]]; then
      echo "WARN: skipping non-contained directory $dir ($res)" >&2
      return 0
    fi
    rm -rf -- "$dir"
    DELETED_LIST+=("$dir/")
  fi
}

safe_rm_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local rel="${f#./}"
  # Never delete the confirmation marker or the cleanup report.
  case "$rel" in
    FINAL_PACKAGE_SAVED.txt|CLEANED.md) return 0 ;;
    user-provided/*|deliverables/final/*) return 0 ;;
  esac
  if is_whitelisted "$rel"; then
    return 0
  fi
  # Defend against symlinks pointing outside the project dir.
  local parent res
  parent="$(cd "$(dirname -- "$f")" && pwd -P)"
  res="$parent/$(basename -- "$f")"
  if [[ "$res" != "$RESOLVED/"* ]]; then
    echo "WARN: skipping non-contained file $f ($res)" >&2
    return 0
  fi
  rm -f -- "$f"
  DELETED_LIST+=("$rel")
}

# Wipe top-level intermediate directories.
for d in intake analyses decisions drafts session-logs working tmp; do
  safe_rm_dir "$d"
done

# Wipe deliverables/ but preserve deliverables/final/ if present.
if [[ -d deliverables ]]; then
  if [[ -d deliverables/final ]]; then
    PRESERVE_TMP=".__final_preserve__.$$"
    if [[ -e "$PRESERVE_TMP" ]]; then
      echo "ERROR: temporary preserve path $PRESERVE_TMP already exists; aborting." >&2
      exit 3
    fi
    mv deliverables/final "$PRESERVE_TMP"
    rm -rf -- deliverables
    mkdir -p deliverables
    mv "$PRESERVE_TMP" deliverables/final
    DELETED_LIST+=("deliverables/ (except deliverables/final/)")
  else
    safe_rm_dir deliverables
  fi
fi

# Wipe named top-level files.
for f in intake-record.md decision-ledger.md; do
  safe_rm_file "./$f"
done

# Wipe pattern matches anywhere, excluding the preserve list.
while IFS= read -r -d '' f; do
  case "$f" in
    ./FINAL_PACKAGE_SAVED.txt|./CLEANED.md) continue ;;
    ./user-provided/*|./deliverables/final/*) continue ;;
  esac
  safe_rm_file "$f"
done < <(find . -type f \( \
    -name '*.tmp' -o \
    -name '*.scratch.*' -o \
    -name 'DRAFT_*' -o \
    -name 'SCRATCH_*' -o \
    -name '*.draft.md' \
  \) -print0)

# --------------------------------------------------------------------------
# Write CLEANED.md summary
# --------------------------------------------------------------------------
DELETED_COUNT="${#DELETED_LIST[@]}"
LIST_LIMIT=50

{
  printf '# Intermediate work products removed on %s\n\n' "$TIMESTAMP"
  cat <<'EXPLAIN'
You chose to delete intermediate files and session work products from this
folder to reduce the contemporaneous paper trail. Preserved items:

- `FINAL_PACKAGE_SAVED.txt` — your save marker.
- `CLEANED.md` — this file.
- `deliverables/final/` — your curated final outputs (if you created one).
- `user-provided/` — your original uploads (if present).
- Any file listed in `intake-inputs.txt` (if present).
- Any file outside the swept directories and not matching a swept pattern.

## What was removed

EXPLAIN

  if [[ "$DELETED_COUNT" -eq 0 ]]; then
    echo "_(nothing was found to remove)_"
  else
    printf '%d items:\n\n' "$DELETED_COUNT"
    if [[ "$DELETED_COUNT" -le "$LIST_LIMIT" ]]; then
      printf -- '- `%s`\n' "${DELETED_LIST[@]}"
    else
      printf -- '- `%s`\n' "${DELETED_LIST[@]:0:$LIST_LIMIT}"
      printf -- '- _(and %d more not listed here)_\n' "$((DELETED_COUNT - LIST_LIMIT))"
    fi
  fi

  cat <<'DISCLAIMER'

## Disclaimer

This deletion was performed at your direction, on files you owned, at a
time when no litigation was pending. It is not spoliation of evidence. For
HNW/UHNW testators who anticipate a will contest, this cleanup is not a
substitute for working with your attorney under an enterprise AI plan
with zero-retention, or for deathbed / capacity drafting that requires a
human attorney as drafter and witness.
DISCLAIMER
} > CLEANED.md

echo "Cleanup complete. $DELETED_COUNT items removed. See CLEANED.md for details."
