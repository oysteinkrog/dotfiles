#!/usr/bin/env bash
# classify-new.sh — diff-only CI classifier for newly-added unsafe-related Rust lines.
# Usage: ./classify-new.sh [--project <path>] [--base <git-ref>] [--format markdown|jsonl] [--fail-on-new]

set -euo pipefail

PROJECT="${PROJECT:-$(pwd)}"
BASE="${BASE_REF:-}"
FORMAT="markdown"
FAIL_ON_NEW=0

usage() {
  cat <<'EOF'
usage: classify-new.sh [--project <path>] [--base <git-ref>] [--format markdown|jsonl] [--fail-on-new]

Scans the diff between <base> and the current working tree for newly-added
unsafe-related Rust lines, then emits a best-effort PR-comment table.

Defaults:
  --project  current directory
  --base     BASE_REF env, origin/$GITHUB_BASE_REF, origin/main, main, or HEAD~1
  --format   markdown

Notes:
  - This is a fast CI guard, not a replacement for the full Phase 1-4 audit.
  - It intentionally includes raw pointer / UnsafeCell / unchecked intrinsic
    additions because those often become part of the soundness surface even when
    the added line itself is not inside an `unsafe {}` block.
EOF
}

die() {
  echo "error: $*" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project)
      [ "${2:-}" ] || die "--project requires a value"
      PROJECT="$2"
      shift 2
      ;;
    --base)
      [ "${2:-}" ] || die "--base requires a value"
      BASE="$2"
      shift 2
      ;;
    --format)
      [ "${2:-}" ] || die "--format requires markdown or jsonl"
      FORMAT="$2"
      case "$FORMAT" in markdown|jsonl) ;; *) die "--format requires markdown or jsonl" ;; esac
      shift 2
      ;;
    --fail-on-new)
      FAIL_ON_NEW=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

PROJECT="$(cd "$PROJECT" && pwd -P)"
git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "$PROJECT is not inside a git checkout"
PROJECT="$(git -C "$PROJECT" rev-parse --show-toplevel)"

resolve_base() {
  if [ -n "$BASE" ]; then
    printf '%s\n' "$BASE"
    return
  fi

  if [ -n "${GITHUB_BASE_REF:-}" ] \
     && git -C "$PROJECT" rev-parse --verify --quiet "origin/$GITHUB_BASE_REF^{commit}" >/dev/null; then
    printf 'origin/%s\n' "$GITHUB_BASE_REF"
    return
  fi

  for candidate in origin/main main HEAD~1; do
    if git -C "$PROJECT" rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  return 1
}

BASE="$(resolve_base)" || die "cannot infer a base ref; pass --base <git-ref>"
BASE_COMMIT="$(git -C "$PROJECT" rev-parse --verify "$BASE^{commit}")" \
  || die "base ref is not a commit: $BASE"
if DIFF_BASE="$(git -C "$PROJECT" merge-base "$BASE_COMMIT" HEAD 2>/dev/null)"; then
  :
else
  DIFF_BASE="$BASE_COMMIT"
fi

matches() {
  printf '%s\n' "$1" | grep -Eq "$2"
}

kind_for_line() {
  local text="$1"
  if matches "$text" '(^|[[:space:]])unsafe[[:space:]]+fn[[:space:]]'; then echo "unsafe_fn"; return 0; fi
  if matches "$text" '(^|[[:space:]])unsafe[[:space:]]+impl[[:space:]]'; then echo "unsafe_impl"; return 0; fi
  if matches "$text" '(^|[[:space:]])unsafe[[:space:]]+trait[[:space:]]'; then echo "unsafe_trait"; return 0; fi
  if matches "$text" '(^|[[:space:]])(unsafe[[:space:]]+)?extern([[:space:]]+"[^"]+")?[[:space:]]*\{'; then echo "extern_block"; return 0; fi
  if matches "$text" '(^|[^A-Za-z0-9_])asm![[:space:]]*\('; then echo "asm"; return 0; fi
  if matches "$text" 'UnsafeCell([[:space:]]*::|[[:space:]]*<|[[:space:]])'; then echo "unsafe_cell_decl"; return 0; fi
  if matches "$text" '(core|std)::(intrinsics|hint)::(unreachable_unchecked|assert_unchecked|assume|atomic_load_unsynchronized|atomic_store_unsynchronized|likely|unlikely)'; then echo "intrinsic_call"; return 0; fi
  if matches "$text" '(core|std)::ptr::(read|write|read_unaligned|write_unaligned|read_volatile|write_volatile|copy|copy_nonoverlapping|swap|swap_nonoverlapping|replace|drop_in_place)[[:space:]]*\('; then echo "intrinsic_ptr"; return 0; fi
  if matches "$text" '[[:space:]]as[[:space:]]+\*(const|mut)[[:space:]]'; then echo "raw_ptr_cast"; return 0; fi
  if matches "$text" '(^|[^A-Za-z0-9_])\*(const|mut)[[:space:]][A-Za-z0-9_:<>]+'; then echo "raw_ptr_decl"; return 0; fi
  if matches "$text" '(^|[^A-Za-z0-9_])unsafe[[:space:]]*\{'; then echo "block"; return 0; fi
  return 1
}

class_for_line() {
  local kind="$1"
  local text="$2"
  case "$kind" in
    extern_block)
      echo "(A) boundary-contract required"
      ;;
    unsafe_impl)
      if matches "$text" '(Send|Sync)'; then
        echo "(A) Send/Sync proof required"
      else
        echo "(A) impl invariant required"
      fi
      ;;
    unsafe_fn|unsafe_trait)
      echo "(A) caller-obligation proof required"
      ;;
    asm|intrinsic_call)
      echo "(B) perf/intrinsic claim to prove"
      ;;
    unsafe_cell_decl)
      echo "(C) cell-wrapper candidate"
      ;;
    raw_ptr_cast|intrinsic_ptr)
      echo "(C) safe-wrapper candidate"
      ;;
    block)
      if matches "$text" '(transmute|from_raw_parts|MaybeUninit|assume_init|set_len|copy_nonoverlapping|read_unaligned|write_unaligned)'; then
        echo "(C) rewrite candidate"
      else
        echo "(A) local invariant required"
      fi
      ;;
    *)
      echo "(?) manual classification required"
      ;;
  esac
}

score_for_line() {
  local kind="$1"
  local text="$2"
  local blast=1
  local likelihood=3
  local discoverability=1

  if matches "$text" '(^|[[:space:]])pub([[:space:]]|\()'; then
    blast=2
    discoverability=3
  fi
  case "$kind" in
    extern_block) blast=3; discoverability=3 ;;
    asm|intrinsic_call|intrinsic_ptr) [ "$blast" -lt 2 ] && blast=2 ;;
  esac
  if matches "$text" '(unwrap_unchecked|unreachable_unchecked|assert_unchecked|assume_init|transmute|from_raw_parts|set_len|Send|Sync)'; then
    likelihood=4
  fi
  if matches "$text" '(&[[:space:]]*\[u8\]|&str)'; then
    [ "$discoverability" -lt 4 ] && discoverability=4
  fi

  local score=$((blast * likelihood * discoverability))
  local bucket="P3"
  if [ "$score" -ge 60 ]; then bucket="P0"
  elif [ "$score" -ge 25 ]; then bucket="P1"
  elif [ "$score" -ge 10 ]; then bucket="P2"
  fi
  printf '%s:%s\n' "$score" "$bucket"
}

md_escape() {
  # shellcheck disable=SC2016 # sed script is intentionally literal.
  printf '%s' "$1" | sed 's/|/\\|/g; s/`/\\`/g'
}

json_record() {
  python3 - "$@" <<'PY'
import json
import sys

keys = [
    "file", "line", "kind", "heuristic_class", "risk_score",
    "risk_bucket", "source",
]
record = dict(zip(keys, sys.argv[1:]))
for key in ("line", "risk_score"):
    record[key] = int(record[key])
print(json.dumps(record, separators=(",", ":")))
PY
}

rows=()
json_rows=()
count=0
current_file=""
new_line=0

while IFS= read -r raw; do
  if [[ "$raw" =~ ^\+\+\+[[:space:]]b/(.*)$ ]]; then
    current_file="${BASH_REMATCH[1]}"
    continue
  fi
  if [[ "$raw" =~ ^\+\+\+[[:space:]]/dev/null ]]; then
    current_file=""
    continue
  fi
  if [[ "$raw" =~ ^@@[[:space:]]-[0-9,]+[[:space:]]\+([0-9]+)(,([0-9]+))?[[:space:]]@@ ]]; then
    new_line="${BASH_REMATCH[1]}"
    continue
  fi
  if [[ "$raw" == "--- "* ]]; then
    continue
  fi

  if [[ "$raw" == +* ]]; then
    added="${raw#+}"
    if [ -n "$current_file" ] && kind="$(kind_for_line "$added")"; then
      heuristic_class="$(class_for_line "$kind" "$added")"
      score_bucket="$(score_for_line "$kind" "$added")"
      score="${score_bucket%%:*}"
      risk_bucket="${score_bucket##*:}"
      source="$(md_escape "$added")"
      rows[count]="| \`$current_file\` | $new_line | $kind | $heuristic_class | $score | $risk_bucket | \`$source\` |"
      json_rows[count]="$(json_record "$current_file" "$new_line" "$kind" "$heuristic_class" "$score" "$risk_bucket" "$added")"
      count=$((count + 1))
    fi
    new_line=$((new_line + 1))
  elif [[ "$raw" == -* ]]; then
    continue
  elif [ "$new_line" -gt 0 ]; then
    new_line=$((new_line + 1))
  fi
done < <(git -C "$PROJECT" diff --unified=0 --no-ext-diff "$DIFF_BASE" -- '*.rs')

if [ "$FORMAT" = "jsonl" ]; then
  for row in "${json_rows[@]}"; do
    printf '%s\n' "$row"
  done
else
  if [ "$count" -eq 0 ]; then
    echo "No new unsafe-related Rust lines detected relative to $BASE ($DIFF_BASE)."
  else
    echo "Found $count new unsafe-related Rust line(s) relative to $BASE ($DIFF_BASE)."
    echo
    echo "| File | Line | Kind | Heuristic class | Risk score | Bucket | Added line |"
    echo "|------|------|------|-----------------|------------|--------|------------|"
    for row in "${rows[@]}"; do
      printf '%s\n' "$row"
    done
    echo
    echo "These classifications are tentative. Confirm them with the full Phase 1-4 audit before landing soundness claims."
  fi
fi

if [ "$FAIL_ON_NEW" -eq 1 ] && [ "$count" -gt 0 ]; then
  exit 1
fi
