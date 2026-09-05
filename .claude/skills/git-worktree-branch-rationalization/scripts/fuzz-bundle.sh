#!/usr/bin/env bash
# fuzz-bundle.sh — Defense-in-depth: fuzz the bundle's recovery surface.
#
# Generates N transformed copies of the bundle (default 100) under a fresh
# <workspace>/fuzz-<UTC>-<pid>/ directory, runs `verify-bundle.sh` semantics
# against each transform, and exits non-zero if any transformation breaks
# recovery on a copy that should still verify.
#
# Transformations applied (deterministic seed; SAFE_TRANSFORMS only mutate
# non-critical regions; CORRUPTING_TRANSFORMS are expected to fail and serve
# as positive controls):
#
#   safe:
#     - tar -C <bundle> ./ -cf - | tar -xf - to a fresh dir (round-trip)
#     - cp -a across two distinct mountpoints (when available)
#     - rsync -a copy preserving permissions
#     - touch -t to age files in the future
#     - re-pack object-bundle.pack via `git bundle create` from the same heads
#     - rewrite README.md with whitespace-only changes
#     - reorder index.tsv rows (preserving header)
#
#   corrupting (positive controls — expected to fail recovery):
#     - flip 8 random bytes in object-bundle.pack
#     - truncate object-bundle.pack by 64 bytes
#     - mutate a branches/<slug>/diff-vs-merge-base.diff, or truncate the pack
#
# Per AGENTS.md Rule 1, never `rm -rf` the fuzz directory; on completion the
# fuzz dir is `mv`'d to <workspace>/.archived/fuzz-<UTC>-<pid>.
#
# Read-only on the original bundle.
#
# Exit codes:
#   0  every safe transform recovered cleanly AND every corrupting transform
#      was correctly detected as broken
#   2  preflight failed (bundle / inventory missing)
#   5  one or more safe transforms failed recovery (bundle is fragile)
#   6  a corrupting transform was NOT detected as broken (verify-bundle is
#      under-strict)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: fuzz-bundle.sh <project-path> [<count>]

Defense-in-depth fuzz of the bundle's recovery surface. Generates <count>
(default 100) transformed bundle copies under <workspace>/fuzz/, runs the
verify-bundle.sh equivalent on each, and reports.

Read-only on the original bundle. Each run uses a fresh fuzz directory, which
is moved (NEVER \`rm -rf\`) to <workspace>/.archived/fuzz-<UTC>-<pid> on
completion.

Env:
  WORKSPACE                Workspace dir override.
  FUZZ_SAFE_RATIO          Fraction (0.0-1.0) of safe vs corrupting transforms;
                           default 0.85 (85% safe, 15% positive controls).
  FUZZ_SEED                Numeric seed for deterministic generation (default 1).
  FUZZ_KEEP=1              Keep <workspace>/fuzz/ in place instead of moving.

Exit codes:
  0  all transforms behaved correctly
  2  preflight failed
  5  safe transform failed recovery
  6  corrupting transform not detected
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
COUNT="${2:-100}"
if [[ ! "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
  echo "ERROR: count must be a positive integer; got '$COUNT'" >&2
  exit 64
fi

PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
BUNDLE_PATH_FILE="$WORKSPACE_DIR/bundle_path.txt"
[[ -f "$BRANCHES_TSV" ]] || { echo "ERROR: $BRANCHES_TSV missing" >&2; exit 2; }
[[ -f "$BUNDLE_PATH_FILE" ]] || { echo "ERROR: $BUNDLE_PATH_FILE missing" >&2; exit 2; }
BUNDLE="$(cat "$BUNDLE_PATH_FILE")"
[[ -d "$BUNDLE" ]] || { echo "ERROR: $BUNDLE missing" >&2; exit 2; }

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
FUZZ_DIR="$WORKSPACE_DIR/fuzz-$RUN_ID"
LOG="$WORKSPACE_DIR/fuzz_bundle.log"
mkdir -p "$FUZZ_DIR"

SAFE_RATIO="${FUZZ_SAFE_RATIO:-0.85}"
SEED="${FUZZ_SEED:-1}"

awk -v r="$SAFE_RATIO" 'BEGIN{ if (r<0||r>1) exit 1 }' || {
  echo "ERROR: FUZZ_SAFE_RATIO must be in [0,1]; got '$SAFE_RATIO'" >&2
  exit 64
}
SAFE_COUNT=$(awk -v c="$COUNT" -v r="$SAFE_RATIO" 'BEGIN{printf "%d", c*r}')
[[ "$SAFE_COUNT" -gt "$COUNT" ]] && SAFE_COUNT="$COUNT"
[[ "$SAFE_COUNT" -lt 0 ]] && SAFE_COUNT=0
CORRUPT_COUNT=$((COUNT - SAFE_COUNT))

: > "$LOG"
declare -i SAFE_FAILED=0
declare -i CORRUPT_UNDETECTED=0

# A minimal verifier: re-runs the byte-equality + bundle-list-heads gate
# against the COPY (not the live repo), since the live repo state hasn't
# changed and copies must remain self-consistent.
verify_copy() {
  local copy="$1"
  # Object bundle present + lists at least one backup-namespace head.
  local pack="$copy/object-bundle.pack"
  if [[ ! -f "$pack" ]]; then
    return 1
  fi
  if ! git -C "$PROJECT_ABS" bundle verify "$pack" >/dev/null 2>&1; then
    return 1
  fi
  local heads
  heads=$(git -C "$PROJECT_ABS" bundle list-heads "$pack" 2>/dev/null || true)
  local n_heads missing_heads mismatched_heads slug head_sha expected_ref pack_sha
  declare -A pack_head_shas=()
  while IFS=' ' read -r sha ref _rest; do
    [[ -z "${sha:-}" || -z "${ref:-}" ]] && continue
    pack_head_shas["$ref"]="$sha"
  done <<< "$heads"
  n_heads=0
  for ref in "${!pack_head_shas[@]}"; do
    case "$ref" in
      refs/branch-rationalization-backup/*) n_heads=$((n_heads + 1)) ;;
    esac
  done
  if [[ "$n_heads" -lt 1 ]]; then
    return 1
  fi
  missing_heads=()
  mismatched_heads=()
  while IFS= read -r row; do
    slug=""; head_sha=""
    tsv_read "$row" _name slug head_sha _rest
    [[ -z "$slug" || "$slug" == "slug" ]] && continue
    expected_ref="refs/branch-rationalization-backup/$slug"
    pack_sha="${pack_head_shas[$expected_ref]:-}"
    if [[ -z "$pack_sha" ]]; then
      missing_heads+=("$expected_ref")
    fi
    if [[ -n "$pack_sha" && -n "$head_sha" && "$pack_sha" != "$head_sha" ]]; then
      mismatched_heads+=("$expected_ref")
    fi
  done < "$BRANCHES_TSV"
  if [[ "${#missing_heads[@]}" -gt 0 || "${#mismatched_heads[@]}" -gt 0 ]]; then
    return 1
  fi
  local verify_git="$copy/.verify-fetch.git"
  if [[ ! -d "$verify_git" ]]; then
    git init --bare --quiet "$verify_git" >/dev/null 2>&1 || return 1
  fi
  if ! git --git-dir="$verify_git" fetch --quiet "$pack" '+refs/branch-rationalization-backup/*:refs/branch-rationalization-backup/*' >/dev/null 2>&1; then
    return 1
  fi
  # Required structural files.
  [[ -f "$copy/index.tsv" ]] || return 1
  [[ -f "$copy/README.md" ]] || return 1
  # Safe transforms must not change per-branch recovery diffs. Check every
  # original diff, not just "at least one", so a single blanked branch payload
  # is detected even in multi-branch bundles.
  if [[ -d "$BUNDLE/branches" ]]; then
    local orig_diff rel copy_diff orig_h copy_h
    while IFS= read -r orig_diff; do
      rel="${orig_diff#"$BUNDLE"/}"
      copy_diff="$copy/$rel"
      [[ -f "$copy_diff" ]] || return 1
      orig_h=$(sha256sum "$orig_diff" | awk '{print $1}')
      copy_h=$(sha256sum "$copy_diff" | awk '{print $1}')
      if [[ "$orig_h" != "$copy_h" ]]; then
        return 1
      fi
    done < <(find "$BUNDLE/branches" -name 'diff-vs-merge-base.diff' -type f 2>/dev/null | sort)
  elif [[ -d "$copy/branches" ]]; then
    if [[ -n "$(find "$copy/branches" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null)" ]]; then
      return 1
    fi
  fi
  return 0
}

# Apply a safe transform.
apply_safe_transform() {
  local copy="$1" idx="$2"
  case $((idx % 7)) in
    0) # tar round-trip
      local sibling="${copy}.tar"
      mkdir -p "$sibling"
      if ( cd "$copy" && tar -cf - . ) | ( cd "$sibling" && tar -xf - ); then
        mv "$copy" "${copy}.orig-$idx"
        mv "$sibling" "$copy"
      fi
      ;;
    1) # whitespace-noise on README.md (append a comment line; never modifies
       # critical hashes since README is human text only)
      printf '\n<!-- fuzz-bundle: harmless append %s -->\n' "$idx" >> "$copy/README.md"
      ;;
    2) # touch dates into the future
      find "$copy" -type f -exec touch -d '+1 day' {} + 2>/dev/null || true
      ;;
    3) # rsync to a sibling, swap
      if command -v rsync >/dev/null 2>&1; then
        local sibling="${copy}.rsynced"
        rsync -a "$copy/" "$sibling/" >/dev/null 2>&1 || true
        if [[ -d "$sibling" ]]; then
          mv "$copy" "${copy}.orig"
          mv "$sibling" "$copy"
          mv "${copy}.orig" "${copy}.orig-$idx" 2>/dev/null || true
        fi
      fi
      ;;
    4) # cp -a copy back-and-forth
      local sibling="${copy}.cpa"
      cp -a "$copy" "$sibling" >/dev/null 2>&1 || true
      if [[ -d "$sibling" ]]; then
        mv "$copy" "${copy}.orig-$idx"
        mv "$sibling" "$copy"
      fi
      ;;
    5) # reorder index.tsv rows preserving header
      if [[ -f "$copy/index.tsv" ]]; then
        local hdr body
        hdr=$(head -1 "$copy/index.tsv")
        body=$(awk 'NR>1' "$copy/index.tsv" | shuf 2>/dev/null \
               || awk 'NR>1' "$copy/index.tsv" | sort)
        {
          printf '%s\n' "$hdr"
          printf '%s\n' "$body"
        } > "$copy/index.tsv.tmp"
        mv "$copy/index.tsv.tmp" "$copy/index.tsv"
      fi
      ;;
    6) # bundle re-pack from the copy's current heads
      local backup_refs=()
      mapfile -t backup_refs < <(git -C "$PROJECT_ABS" bundle list-heads "$copy/object-bundle.pack" 2>/dev/null | awk '{print $2}' | sort -u)
      if [[ "${#backup_refs[@]}" -gt 0 ]]; then
        git -C "$PROJECT_ABS" bundle create "$copy/object-bundle.pack" \
          "${backup_refs[@]}" >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

# Apply a corrupting transform (positive control).
apply_corrupt_transform() {
  local copy="$1" idx="$2"
  case $((idx % 3)) in
    0) # bit-flip 8 bytes near the middle of the pack
      if [[ -f "$copy/object-bundle.pack" ]]; then
        local size off
        size=$(wc -c < "$copy/object-bundle.pack")
        if [[ "$size" -gt 200 ]]; then
          off=$((size / 2))
          dd if=/dev/urandom of="$copy/object-bundle.pack" bs=1 count=8 \
             seek="$off" conv=notrunc 2>/dev/null || true
        fi
      fi
      ;;
    1) # truncate the pack
      if [[ -f "$copy/object-bundle.pack" ]]; then
        local size new
        size=$(wc -c < "$copy/object-bundle.pack")
        new=$((size / 2))
        if [[ "$new" -gt 0 ]]; then
          # Use head to safely shorten without rm. Cutting the pack roughly in
          # half makes this a reliable positive control even for tiny bundles.
          head -c "$new" "$copy/object-bundle.pack" > "$copy/object-bundle.pack.short"
          mv "$copy/object-bundle.pack.short" "$copy/object-bundle.pack"
        fi
      fi
      ;;
    2) # mutate one diff file, falling back to pack truncation if no diff exists
      local d
      d=$(find "$copy/branches" -name 'diff-vs-merge-base.diff' -type f -print -quit 2>/dev/null || true)
      if [[ -n "$d" ]]; then
        if [[ -s "$d" ]]; then
          : > "$d"
        else
          printf '# fuzz-bundle corrupt empty diff %s\n' "$idx" >> "$d"
        fi
      elif [[ -f "$copy/object-bundle.pack" ]]; then
        local size new
        size=$(wc -c < "$copy/object-bundle.pack")
        new=$((size / 2))
        if [[ "$new" -gt 0 ]]; then
          head -c "$new" "$copy/object-bundle.pack" > "$copy/object-bundle.pack.short"
          mv "$copy/object-bundle.pack.short" "$copy/object-bundle.pack"
        fi
      fi
      ;;
  esac
}

# Round 1 — safe transforms.
i=0
while [[ "$i" -lt "$SAFE_COUNT" ]]; do
  copy="$FUZZ_DIR/safe-$i"
  if [[ ! -d "$copy" ]]; then
    cp -a "$BUNDLE" "$copy" 2>/dev/null || {
      echo "FAIL safe-$i copy stage" | tee -a "$LOG" >&2
      SAFE_FAILED=$((SAFE_FAILED+1))
      i=$((i+1))
      continue
    }
  fi
  apply_safe_transform "$copy" "$((SEED + i))"
  if verify_copy "$copy"; then
    echo "OK safe-$i" >> "$LOG"
  else
    echo "FAIL safe-$i" >> "$LOG"
    SAFE_FAILED=$((SAFE_FAILED+1))
  fi
  i=$((i+1))
done

# Round 2 — corrupting transforms (positive controls).
j=0
while [[ "$j" -lt "$CORRUPT_COUNT" ]]; do
  copy="$FUZZ_DIR/corrupt-$j"
  if [[ ! -d "$copy" ]]; then
    cp -a "$BUNDLE" "$copy" 2>/dev/null || {
      echo "FAIL corrupt-$j copy stage (cannot test detection)" | tee -a "$LOG" >&2
      j=$((j+1))
      continue
    }
  fi
  apply_corrupt_transform "$copy" "$((SEED + j))"
  if verify_copy "$copy"; then
    echo "UNDETECTED corrupt-$j (verify-bundle missed corruption)" >> "$LOG"
    CORRUPT_UNDETECTED=$((CORRUPT_UNDETECTED+1))
  else
    echo "DETECTED corrupt-$j" >> "$LOG"
  fi
  j=$((j+1))
done

# Archive (mv) per AGENTS.md Rule 1.
if [[ -z "${FUZZ_KEEP:-}" ]]; then
  ARCHIVE_DIR="$WORKSPACE_DIR/.archived"
  mkdir -p "$ARCHIVE_DIR"
  archive_dest="$ARCHIVE_DIR/fuzz-$RUN_ID"
  suffix=0
  while [[ -e "$archive_dest" ]]; do
    suffix=$((suffix + 1))
    archive_dest="$ARCHIVE_DIR/fuzz-$RUN_ID-$suffix"
  done
  mv "$FUZZ_DIR" "$archive_dest"
  log "moved fuzz dir to $archive_dest"
fi

echo "summary: safe_failed=$SAFE_FAILED corrupt_undetected=$CORRUPT_UNDETECTED log=$LOG"

if [[ "$SAFE_FAILED" -gt 0 ]]; then
  exit 5
fi
if [[ "$CORRUPT_UNDETECTED" -gt 0 ]]; then
  exit 6
fi
exit 0
