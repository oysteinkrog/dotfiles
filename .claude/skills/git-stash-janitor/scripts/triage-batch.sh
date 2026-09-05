#!/usr/bin/env bash
# triage-batch.sh — Phase 4 worker: triage one batch of stashes.
#
# Usage: triage-batch.sh <project-path> <batch-id> <n-start> <n-end>
#
# Output: <project>/.stash_janitor_workspace/triage/batch_<batch-id>.tsv
#
# This script runs the FINGERPRINT + VERIFY-ON-MAIN + APPLY-CHECK pipeline
# for stashes in [n-start, n-end] and writes a verdict per row.

set -euo pipefail

PROJECT="${1:?Usage: triage-batch.sh <project-path> <batch-id> <n-start> <n-end>}"
BATCH_ID="${2:?missing batch-id}"
N_START="${3:?missing n-start}"
N_END="${4:?missing n-end}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
INVENTORY="$WORKSPACE/inventory.tsv"
PROFILE="$WORKSPACE/project_profile.json"

# Explicit pre-condition checks: surface clear errors instead of cryptic
# `set -e` aborts when the run hasn't progressed far enough.
if [[ ! -f "$WORKSPACE/bundle_path.txt" ]]; then
  echo "ERROR: Phase 3 has not completed yet ($WORKSPACE/bundle_path.txt missing)." >&2
  exit 8
fi
BUNDLE="$(cat "$WORKSPACE/bundle_path.txt")"
if [[ ! -d "$BUNDLE" ]]; then
  echo "ERROR: bundle path '$BUNDLE' does not exist (stale bundle_path.txt?)" >&2
  exit 8
fi
if [[ ! -f "$INVENTORY" ]]; then
  echo "ERROR: Phase 2 has not completed yet ($INVENTORY missing)." >&2
  exit 8
fi
if [[ ! -f "$PROFILE" ]]; then
  echo "ERROR: Phase 1 has not completed yet ($PROFILE missing)." >&2
  exit 8
fi

TRIAGE_DIR="$WORKSPACE/triage"
mkdir -p "$TRIAGE_DIR"
OUT="$TRIAGE_DIR/batch_${BATCH_ID}.tsv"

# Extract primary branch through a real JSON parser. Regex extraction is not
# valid once project_profile.json contains normal JSON escapes.
profile_json_value() {
  local key="$1" out
  if command -v jq >/dev/null 2>&1; then
    if ! out=$(jq -r --arg key "$key" '.[$key] | if . == null then "" elif type == "boolean" then tostring elif type == "string" then . else tostring end' "$PROFILE"); then
      echo "ERROR: unable to parse $PROFILE as JSON." >&2
      exit 8
    fi
    printf '%s' "$out"
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    if ! out=$(python3 - "$PROFILE" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
value = data.get(sys.argv[2], "")
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(str(value))
PY
    ); then
      echo "ERROR: unable to parse $PROFILE as JSON." >&2
      exit 8
    fi
    printf '%s' "$out"
    return
  fi
  echo "ERROR: need jq or python3 to parse $PROFILE." >&2
  exit 8
}
PRIMARY_BRANCH=$(profile_json_value primary_branch)
if [[ -z "$PRIMARY_BRANCH" ]]; then
  echo "ERROR: project_profile.json has no primary_branch key (Phase 1 didn't detect)." >&2
  echo "Re-run discover-project.sh, or add the key manually." >&2
  exit 8
fi
if git -C "$PROJECT_ABS" rev-parse --verify --quiet "$PRIMARY_BRANCH" >/dev/null 2>&1; then
  PRIMARY_REF="$PRIMARY_BRANCH"
elif git -C "$PROJECT_ABS" rev-parse --verify --quiet "origin/$PRIMARY_BRANCH" >/dev/null 2>&1; then
  PRIMARY_REF="origin/$PRIMARY_BRANCH"
else
  echo "ERROR: primary_branch '$PRIMARY_BRANCH' does not resolve in this repo." >&2
  exit 8
fi

# Garbage-prefix patterns
is_garbage_prefix() {
  local msg="$1"
  case "$msg" in
    other-agent-broken*|temp-pre-push*|full-tree-reset-stash*|*do-not-restore*) return 0 ;;
    *) return 1 ;;
  esac
}

# Fingerprint: extract introduced symbols (very simple text-based heuristic).
# Grep returns non-zero when there are 0 matches; guard with || true so the
# pipefail-protected pipeline doesn't abort the whole script.
fingerprint_diff() {
  local diff="$1"
  { grep -hE '^\+.*\b(fn|def|function|class|struct|enum|trait|interface|type|const) [A-Za-z_][A-Za-z0-9_]*' "$diff" 2>/dev/null || true; } \
    | sed -E 's/^\+.*\b(fn|def|function|class|struct|enum|trait|interface|type|const) +([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
    | sort -u
}

# Filter out symbols that are too generic to prove a stash's content already
# exists on the primary branch. These names are common across unrelated files;
# counting them in the denominator while skipping them during lookup makes a
# generic-only diff look "novel" instead of honestly unknown.
meaningful_fingerprint_diff() {
  local diff="$1"
  fingerprint_diff "$diff" | while IFS= read -r sym; do
    [[ -z "$sym" ]] && continue
    case "$sym" in main|new|init|run|build|test|setup|teardown|default) continue ;; esac
    printf '%s\n' "$sym"
  done
}

# Files added/modified
files_in_diff() {
  local diff="$1"
  { grep -E '^diff --git a/' "$diff" 2>/dev/null || true; } \
    | sed -E 's@^diff --git a/(.*) b/.*@\1@' \
    | sort -u
}

# Verify on main: returns fraction (0..1) of fingerprint symbols found on primary
verify_on_main() {
  local diff="$1"
  local fingerprint
  fingerprint=$(meaningful_fingerprint_diff "$diff")
  local total found
  # `grep -c .` prints "0" AND exits 1 when there are no matches; a naive
  # `|| echo 0` would then print "0" twice, giving total="0\n0" which bash
  # arithmetic mishandles. Use `|| true` to swallow the exit and let the
  # ${...:-0} default fill in the empty case (no output line).
  total=$({ printf '%s' "$fingerprint" | grep -c . 2>/dev/null ; } || true)
  total=${total:-0}
  if [[ "$total" -eq 0 ]]; then
    echo "0|0"
    return
  fi
  found=0
  while IFS= read -r sym; do
    [[ -z "$sym" ]] && continue
    if git -C "$PROJECT_ABS" grep -q -F -- "$sym" "$PRIMARY_REF" 2>/dev/null; then
      found=$((found + 1))
    fi
  done <<< "$fingerprint"
  printf '%s|%s' "$found" "$total"
}

# Apply-check (no actual apply)
apply_check() {
  local diff="$1"
  if git -C "$PROJECT_ABS" apply --3way --check "$diff" 2>/dev/null; then
    echo clean
  else
    echo reject
  fi
}

# File existence: fraction of files referenced still on primary
file_existence_coverage() {
  local diff="$1"
  local files=()
  while IFS= read -r f; do files+=("$f"); done < <(files_in_diff "$diff")
  local total=${#files[@]}
  if [[ $total -eq 0 ]]; then echo "0|0"; return; fi
  local exists=0
  for f in "${files[@]}"; do
    if git -C "$PROJECT_ABS" cat-file -e "$PRIMARY_REF:$f" 2>/dev/null; then
      exists=$((exists + 1))
    fi
  done
  echo "${exists}|${total}"
}

# Header
printf 'n\tverdict\tconfidence\tevidence_on_main\tapply_check\tfingerprint_summary\n' > "$OUT"

# Process rows in range
awk -F'\t' -v ns="$N_START" -v ne="$N_END" 'NR > 1 && $1 >= ns && $1 <= ne' "$INVENTORY" \
| while IFS=$'\t' read -r n _ref _sha _parent_sha _date _author message files _ins _dels _has_untracked; do
  npad=$(printf '%03d' "$n")
  diff="$BUNDLE/diffs/$npad.diff"

  if [[ ! -f "$diff" ]]; then
    printf '%s\tunknown\t0.0\tdiff-missing\tn/a\tdiff-not-in-bundle\n' "$n" >> "$OUT"
    continue
  fi

  # Quick garbage-prefix check.
  # `head -3` would SIGPIPE the upstream `sort -u` inside fingerprint_diff
  # whenever the diff has >3 symbols. Under `set -euo pipefail` that aborts
  # the entire batch mid-loop. `sed -n '1,3p'` reads all stdin and prints
  # only the first 3 lines, never closing stdin early.
  if is_garbage_prefix "$message"; then
    fingerprint=$(fingerprint_diff "$diff" | sed -n '1,3p' | tr '\n' ',' | sed 's/,$//')
    printf '%s\tgarbage\t0.99\tn/a\tn/a\tprefix-match: %s\n' "$n" "${fingerprint:-empty}" >> "$OUT"
    continue
  fi

  # Compute signals
  vcoverage=$(verify_on_main "$diff")
  acheck=$(apply_check "$diff")
  fcoverage=$(file_existence_coverage "$diff")

  found=${vcoverage%|*}
  total=${vcoverage#*|}
  fexists=${fcoverage%|*}
  ftotal=${fcoverage#*|}

  if [[ "$total" -eq 0 ]]; then
    fp_frac=0
  else
    fp_frac=$(awk -v f="$found" -v t="$total" 'BEGIN { printf "%.2f", f/t }')
  fi
  if [[ "$ftotal" -eq 0 ]]; then
    file_frac=1
  else
    file_frac=$(awk -v f="$fexists" -v t="$ftotal" 'BEGIN { printf "%.2f", f/t }')
  fi

  # Same SIGPIPE concern as the garbage-prefix branch above. This call site
  # runs for EVERY non-garbage stash, so an unfixed `head -3` would abort the
  # batch on virtually any normal stash with >3 meaningful symbols.
  fingerprint_summary=$(meaningful_fingerprint_diff "$diff" | sed -n '1,3p' | tr '\n' ',' | sed 's/,$//')
  fingerprint_summary=${fingerprint_summary:-no-meaningful-symbols}

  # Classify. Order matters: handle empty fingerprint FIRST to avoid the
  # silent "fp_frac=0 → novel-and-accretive" false positive on diffs that
  # are binary, whitespace-only, or in a language our regex doesn't catch.
  if [[ "$total" -eq 0 ]]; then
    # Empty fingerprint: could be binary, whitespace-only, comment-only,
    # config-only, or in an unsupported language. Surface to user.
    if [[ "$acheck" == "clean" ]] && [[ "$ftotal" -gt 0 ]]; then
      verdict=unknown
      conf=0.50
      evidence="empty fingerprint (binary/whitespace/unsupported-language); apply-check clean — surface to user"
    else
      verdict=unknown
      conf=0.45
      evidence="empty fingerprint AND apply-check ${acheck} — surface to user"
    fi
  elif awk -v fp="$fp_frac" 'BEGIN { exit !(fp >= 0.95) }'; then
    verdict=superseded
    conf=$(awk -v fp="$fp_frac" 'BEGIN { printf "%.2f", 0.85 + 0.15 * fp }')
    evidence="${found}/${total} symbols found on $PRIMARY_REF"
  elif awk -v fp="$fp_frac" 'BEGIN { exit !(fp <= 0.05) }' && [[ "$acheck" == "clean" ]]; then
    verdict=novel-and-accretive
    conf=$(awk -v fp="$fp_frac" 'BEGIN { printf "%.2f", 0.75 + 0.20 * (1 - fp) }')
    evidence="no symbols found on $PRIMARY_REF; apply-check clean"
  elif [[ "$acheck" == "reject" ]] && awk -v fp="$fp_frac" -v ff="$file_frac" 'BEGIN { exit !(fp <= 0.05 && ff >= 0.5) }'; then
    verdict=partially-novel
    conf=0.70
    evidence="apply rejects with mostly-novel fingerprint; needs split"
  elif awk -v fp="$fp_frac" -v ff="$file_frac" 'BEGIN { exit !(fp <= 0.05 && ff < 0.5) }'; then
    verdict=novel-but-stale
    conf=0.70
    evidence="files removed from $PRIMARY_REF (${fexists}/${ftotal} still exist); apply rejects"
  else
    verdict=unknown
    conf=0.60
    evidence="ambiguous: fp=${fp_frac} file=${file_frac} apply=${acheck}"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$verdict" "$conf" "$evidence" "$acheck" "$fingerprint_summary" >> "$OUT"
done

# Summary
echo "wrote $OUT"
echo "Verdict counts in this batch:"
awk -F'\t' 'NR > 1 {print $2}' "$OUT" | sort | uniq -c
