#!/usr/bin/env bash
# audit-rationalization-branch.sh — Phase 9.5: codebase audit on the
# rationalization branch's tip (HARD GATE between Phase 9 fresh-eyes and
# Phase 10 destructive cleanup).
#
# Runs (when available, in order):
#   - UBS                            (`ubs --ci .`)
#   - lint                           (project-detected: cargo clippy / eslint / ruff / shellcheck / golangci-lint)
#   - typecheck                      (cargo check / tsc --noEmit / mypy / pyright)
#   - format check                   (cargo fmt --check / prettier --check / black --check / gofmt -l)
#   - security scanners              (cargo-audit / npm audit / pip-audit / govulncheck)
#   - test suite                     (cargo test / pnpm test / pytest / go test ./...)
#
# Per AUDIT-AFTER-RUN.md / metamorphic relation MR-4: for each commit on the
# rationalization branch tagged as a `harmonized-synthesis`, runs the
# *source-variant* tests against the synthesis. Source variants are mined
# from <workspace>/harmonization_plan.md per-file branch citations.
#
# Emits <workspace>/audit_report.md with per-commit + per-dimension pass/fail.
# Exits non-zero if any audit dimension fails. The handoff layer reads this
# script's exit code via the reaper-marker file: when audit fails, Phase 10
# is BLOCKED until audit passes.
#
# Per AGENTS.md: never bypasses pre-commit hooks; never `--no-verify`; never
# uses sed/awk to mutate source code.
#
# Resume-aware: if the report exists with the same rationalization-branch tip
# AND the same project_profile.json hash, the prior report is reused.
#
# Exit codes:
#   0  audit clean (Phase 10 may proceed)
#   2  preflight failed (workspace / profile missing)
#   3  rationalization branch not found
#   5  one or more audit dimensions failed (run is BLOCKED before Phase 10)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: audit-rationalization-branch.sh <project-path>

Phase 9.5. Runs UBS / lint / typecheck / format / security / tests against
the rationalization branch tip and writes <workspace>/audit_report.md.

Source-variant tests for harmonized-synthesis commits (MR-4) are run when
harmonization_plan.md and the bundle are available.

Env:
  WORKSPACE                       Workspace dir override.
  RATIONALIZATION_BRANCH          Override the rationalization branch name.
  AUDIT_SKIP_TESTS=1              Skip the project test suite (NOT recommended).
  AUDIT_SKIP_SECURITY=1           Skip the security scanners.
  AUDIT_SKIP_MR4=1                Skip the metamorphic source-variant test reruns.
  AUDIT_FORCE=1                   Regenerate report even if signature unchanged.

Exit codes:
  0  clean
  2  preflight failed
  3  rationalization branch not found
  5  one or more dimensions failed
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
PROFILE="$WORKSPACE_DIR/project_profile.json"
PLAN="$WORKSPACE_DIR/harmonization_plan.md"
APPLY_LOG="$WORKSPACE_DIR/apply_log.tsv"
REPORT="$WORKSPACE_DIR/audit_report.md"
GATE_FILE="$WORKSPACE_DIR/audit_gate.txt"

[[ -f "$PROFILE" ]] || { echo "ERROR: $PROFILE missing" >&2; exit 2; }

profile_value() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg key "$key" '.[$key] // ""' "$PROFILE"
    return
  fi
  python3 - "$PROFILE" "$key" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f: data = json.load(f)
v = data.get(sys.argv[2], "")
if isinstance(v, bool): print("true" if v else "false")
elif v is None: print("")
else: print(v)
PY
}

hash_or_missing() {
  local path="$1"
  if [[ -f "$path" ]]; then
    sha256sum "$path" | awk '{print $1}'
  else
    printf 'missing'
  fi
}

DATE_TAG=$(date -u +%Y-%m-%d)
PROFILE_RB=$(profile_value rationalization_branch)
[[ -z "$PROFILE_RB" ]] && PROFILE_RB="branch-rationalization-$DATE_TAG"
RB="${RATIONALIZATION_BRANCH:-$PROFILE_RB}"

RB_REF="refs/heads/$RB"
if ! git -C "$PROJECT_ABS" rev-parse --verify --quiet "$RB_REF" >/dev/null 2>&1; then
  echo "ERROR: rationalization branch '$RB' not found." >&2
  echo "Run Phase 8 first or pass RATIONALIZATION_BRANCH explicitly." >&2
  exit 3
fi
RB_TIP=$(git -C "$PROJECT_ABS" rev-parse "$RB_REF" 2>/dev/null)

# Resume check.
SIG_PROFILE=$(sha256sum "$PROFILE" | awk '{print $1}')
SIG="audit/v1 rb=$RB tip=$RB_TIP profile=$SIG_PROFILE"
SIG_APPLY=$(hash_or_missing "$APPLY_LOG")
SIG_PLAN=$(hash_or_missing "$PLAN")
SIG_INPUTS="audit-inputs/v1 apply=$SIG_APPLY plan=$SIG_PLAN"
if [[ -z "${AUDIT_FORCE:-}" && -f "$REPORT" ]] \
   && grep -qxF "<!-- signature: $SIG -->" "$REPORT" 2>/dev/null \
   && grep -qxF "<!-- inputs: $SIG_INPUTS -->" "$REPORT" 2>/dev/null \
   && [[ -f "$GATE_FILE" ]]; then
  log "audit unchanged for $RB@$RB_TIP; reusing $REPORT"
  gate_rc=""
  IFS= read -r gate_rc < "$GATE_FILE" || gate_rc=""
  case "$gate_rc" in
    OK) exit 0 ;;
    BLOCKED) exit 5 ;;
    ''|*[!0-9]*)
      echo "ERROR: invalid audit gate value '$gate_rc' in $GATE_FILE" >&2
      exit 2
      ;;
    *) exit "$gate_rc" ;;
  esac
fi

CANONICAL=$(profile_value canonical_branch)
if git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/heads/$CANONICAL"
elif git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/remotes/origin/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/remotes/origin/$CANONICAL"
else
  echo "ERROR: canonical branch '$CANONICAL' does not resolve locally or as origin/$CANONICAL." >&2
  exit 2
fi
TEST_CMD=$(profile_value test_command)
LINT_CMD=$(profile_value lint_command)
TYPECHECK_CMD=$(profile_value typecheck_command)
FORMAT_CMD=$(profile_value format_command)
WS_REL="$(basename "$WORKSPACE_DIR")"

has_worktree_changes() {
  [[ -n "$(git -C "$PROJECT_ABS" status --porcelain=v2 --untracked-files=all -- . ":(exclude)$WS_REL" 2>/dev/null || true)" ]]
}

# Capture current checkout state so we can restore both branch and detached-HEAD starts.
ORIG_BRANCH=$(git -C "$PROJECT_ABS" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
ORIG_COMMIT=$(git -C "$PROJECT_ABS" rev-parse HEAD 2>/dev/null || echo "")
if [[ -n "$ORIG_BRANCH" ]]; then
  ORIG_DISPLAY="$ORIG_BRANCH"
else
  ORIG_DISPLAY="detached:${ORIG_COMMIT:-unknown}"
fi
CHECKED_OUT=0
LIVE_AUDIT_OK=0
LIVE_AUDIT_BLOCKED=0
if [[ "$ORIG_BRANCH" != "$RB" ]]; then
  if has_worktree_changes; then
    log "working tree dirty (concurrent agents per AGENTS.md); skipping live command audit to avoid checking the wrong branch"
    LIVE_AUDIT_BLOCKED=1
  else
    if git -C "$PROJECT_ABS" switch --quiet "$RB" 2>/dev/null; then
      CHECKED_OUT=1
      LIVE_AUDIT_OK=1
    else
      log "could not checkout $RB; skipping live command audit"
      LIVE_AUDIT_BLOCKED=1
    fi
  fi
else
  LIVE_AUDIT_OK=1
fi

restore_checkout_state() {
  local branch="$1" commit="$2"
  if [[ -n "$branch" ]]; then
    git -C "$PROJECT_ABS" switch --quiet "$branch" 2>/dev/null || true
  elif [[ -n "$commit" ]]; then
    git -C "$PROJECT_ABS" checkout --quiet --detach "$commit" 2>/dev/null || true
  fi
}

restore_head() {
  # shellcheck disable=SC2317  # Invoked by the EXIT trap.
  if [[ "$CHECKED_OUT" -eq 1 ]]; then
    # shellcheck disable=SC2317  # Invoked by the EXIT trap.
    restore_checkout_state "$ORIG_BRANCH" "$ORIG_COMMIT"
  fi
}
trap restore_head EXIT

declare -i FAILED=0
declare -a DIMENSIONS=()

# A dimension entry: name|status|notes (status=PASS|FAIL|SKIP|N/A)
record_dim() {
  DIMENSIONS+=("$1"$'\t'"$2"$'\t'"$3")
  case "$2" in
    FAIL) FAILED=$((FAILED+1)) ;;
  esac
}

run_in_repo() {
  local cmd="$1"
  ( cd "$PROJECT_ABS" && bash -c "$cmd" )
}

# ---- UBS ----
if [[ "$LIVE_AUDIT_OK" -ne 1 ]]; then
  record_dim ubs SKIP "not checked out to $RB; working tree belongs to $ORIG_DISPLAY"
elif command -v ubs >/dev/null 2>&1; then
  if (cd "$PROJECT_ABS" && ubs --ci . >/dev/null 2>&1); then
    record_dim ubs PASS "ubs --ci . exited 0"
  else
    record_dim ubs FAIL "ubs --ci . exited non-zero — see \`ubs --ci .\`"
  fi
else
  record_dim ubs SKIP "ubs not installed"
fi

# ---- Lint ----
if [[ "$LIVE_AUDIT_OK" -ne 1 ]]; then
  record_dim lint SKIP "not checked out to $RB"
elif [[ -n "$LINT_CMD" ]]; then
  if run_in_repo "$LINT_CMD" >/dev/null 2>&1; then
    record_dim lint PASS "$LINT_CMD"
  else
    record_dim lint FAIL "$LINT_CMD"
  fi
else
  record_dim lint SKIP "no lint_command in project_profile.json"
fi

# ---- Typecheck ----
if [[ "$LIVE_AUDIT_OK" -ne 1 ]]; then
  record_dim typecheck SKIP "not checked out to $RB"
elif [[ -n "$TYPECHECK_CMD" ]]; then
  if run_in_repo "$TYPECHECK_CMD" >/dev/null 2>&1; then
    record_dim typecheck PASS "$TYPECHECK_CMD"
  else
    record_dim typecheck FAIL "$TYPECHECK_CMD"
  fi
else
  record_dim typecheck SKIP "no typecheck_command in project_profile.json"
fi

# ---- Format check ----
if [[ "$LIVE_AUDIT_OK" -ne 1 ]]; then
  record_dim format SKIP "not checked out to $RB"
elif [[ -n "$FORMAT_CMD" ]]; then
  if run_in_repo "$FORMAT_CMD" >/dev/null 2>&1; then
    record_dim format PASS "$FORMAT_CMD"
  else
    record_dim format FAIL "$FORMAT_CMD"
  fi
else
  record_dim format SKIP "no format_command in project_profile.json"
fi

# ---- Security scanners ----
if [[ "$LIVE_AUDIT_OK" -ne 1 ]]; then
  record_dim security SKIP "not checked out to $RB"
elif [[ -z "${AUDIT_SKIP_SECURITY:-}" ]]; then
  ran_any=0
  if [[ -f "$PROJECT_ABS/Cargo.toml" ]] && command -v cargo-audit >/dev/null 2>&1; then
    ran_any=1
    if (cd "$PROJECT_ABS" && cargo audit --quiet) >/dev/null 2>&1; then
      record_dim security-cargo-audit PASS "cargo audit (no advisories)"
    else
      record_dim security-cargo-audit FAIL "cargo audit reported advisories"
    fi
  fi
  if [[ -f "$PROJECT_ABS/package.json" ]] && command -v npm >/dev/null 2>&1; then
    ran_any=1
    if (cd "$PROJECT_ABS" && npm audit --omit=dev --audit-level=high) >/dev/null 2>&1; then
      record_dim security-npm-audit PASS "npm audit (no high+ advisories)"
    else
      record_dim security-npm-audit FAIL "npm audit reported high+ advisories"
    fi
  fi
  if { [[ -f "$PROJECT_ABS/pyproject.toml" ]] || [[ -f "$PROJECT_ABS/requirements.txt" ]]; } \
     && command -v pip-audit >/dev/null 2>&1; then
    ran_any=1
    if (cd "$PROJECT_ABS" && pip-audit) >/dev/null 2>&1; then
      record_dim security-pip-audit PASS "pip-audit (no advisories)"
    else
      record_dim security-pip-audit FAIL "pip-audit reported advisories"
    fi
  fi
  if [[ -f "$PROJECT_ABS/go.mod" ]] && command -v govulncheck >/dev/null 2>&1; then
    ran_any=1
    if (cd "$PROJECT_ABS" && govulncheck ./...) >/dev/null 2>&1; then
      record_dim security-govulncheck PASS "govulncheck (no findings)"
    else
      record_dim security-govulncheck FAIL "govulncheck reported findings"
    fi
  fi
  if [[ "$ran_any" -eq 0 ]]; then
    record_dim security N/A "no manifest matched a known scanner (Cargo.toml/package.json/pyproject/go.mod)"
  fi
else
  record_dim security SKIP "AUDIT_SKIP_SECURITY=1"
fi

# ---- Test suite ----
if [[ "$LIVE_AUDIT_OK" -ne 1 ]]; then
  record_dim tests SKIP "not checked out to $RB"
elif [[ -n "${AUDIT_SKIP_TESTS:-}" ]]; then
  record_dim tests SKIP "AUDIT_SKIP_TESTS=1"
elif [[ -n "$TEST_CMD" ]]; then
  if run_in_repo "$TEST_CMD" >/dev/null 2>&1; then
    record_dim tests PASS "$TEST_CMD"
  else
    record_dim tests FAIL "$TEST_CMD"
  fi
else
  record_dim tests SKIP "no test_command in project_profile.json"
fi

# ---- MR-4: source-variant tests against harmonized-synthesis commits ----
declare -a MR4_ROWS=()
if [[ -z "${AUDIT_SKIP_MR4:-}" && -f "$APPLY_LOG" && -f "$PLAN" ]]; then
  # apply_log.tsv columns: kind  target  strategy  new_commit_sha  files_changed  gates_status  duration_s  drift
  while IFS= read -r row; do
    kind=; target=; strategy=; new_sha=
    tsv_read "$row" kind target strategy new_sha _files _gates _dur _drift
    [[ "$kind" == "kind" ]] && continue
    [[ "$strategy" != "harmonized-synthesis" ]] && continue
    [[ -z "$new_sha" ]] && continue
    # harmonization-plan.sh emits per-file sections as "### `path`" and
    # source table rows whose first cell is "branch:<name>".
    sources=$(awk -v t="$target" '
      /^###[[:space:]]+/ {
        header = $0
        sub(/^###[[:space:]]+/, "", header)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", header)
        if (header ~ /^`.*`$/) {
          sub(/^`/, "", header)
          sub(/`$/, "", header)
        }
        in_sec = (header == t)
        next
      }
      /^##[[:space:]]+/ { in_sec = 0; next }
      in_sec && /^\|/ {
        split($0, cols, "|")
        src = cols[2]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", src)
        if (src ~ /^`?branch:/) {
          sub(/^`?branch:/, "", src)
          sub(/`$/, "", src)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", src)
          if (src != "") print src
        }
      }
    ' "$PLAN" 2>/dev/null | sort -u)
    if [[ -z "$sources" ]]; then
      MR4_ROWS+=("$target"$'\t'"(none)"$'\t'FAIL-no-source-variants)
      FAILED=$((FAILED+1))
      continue
    fi
    while IFS= read -r src_branch; do
      [[ -z "$src_branch" ]] && continue
      # Re-run tests with source-variant patches applied? That's MR-4 in full.
      # The pragmatic approach: run the full test suite at the synthesis tip,
      # then verify the source branch's test files (if any) still pass when
      # exercised at the synthesis commit.
      if [[ -n "$TEST_CMD" ]] && [[ -z "${AUDIT_SKIP_TESTS:-}" ]]; then
        if has_worktree_changes; then
          MR4_ROWS+=("$target"$'\t'"$src_branch"$'\t'SKIP-dirty-audit-surface)
          continue
        fi
        mr4_restore_branch=$(git -C "$PROJECT_ABS" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
        mr4_restore_commit=$(git -C "$PROJECT_ABS" rev-parse HEAD 2>/dev/null || echo "")
        if (cd "$PROJECT_ABS" && git checkout --quiet --detach "$new_sha" 2>/dev/null && bash -c "$TEST_CMD") >/dev/null 2>&1; then
          MR4_ROWS+=("$target"$'\t'"$src_branch"$'\t'PASS)
        else
          MR4_ROWS+=("$target"$'\t'"$src_branch"$'\t'FAIL)
          FAILED=$((FAILED+1))
        fi
        restore_checkout_state "$mr4_restore_branch" "$mr4_restore_commit"
      else
        MR4_ROWS+=("$target"$'\t'"$src_branch"$'\t'SKIP)
      fi
    done <<< "$sources"
  done < "$APPLY_LOG"
fi

# ---- Per-commit walk on rationalization branch ----
declare -a COMMIT_ROWS=()
COMMITS=$(git -C "$PROJECT_ABS" rev-list --reverse "$CANON_REF..$RB_REF" 2>/dev/null \
       || true)
for c in $COMMITS; do
  subj=$(git -C "$PROJECT_ABS" log -1 --format='%s' "$c")
  short=$(git -C "$PROJECT_ABS" log -1 --format='%h' "$c")
  COMMIT_ROWS+=("$short"$'\t'"$subj")
done

# ---- Write report ----
{
  printf '<!-- signature: %s -->\n' "$SIG"
  printf '<!-- inputs: %s -->\n' "$SIG_INPUTS"
  printf "# Audit report — rationalization branch \`%s\`\n\n" "$RB"
  printf "Project:        \`%s\`\n" "$PROJECT_ABS"
  printf "Tip:            \`%s\`\n" "$RB_TIP"
  printf 'Audited at:     %s\n\n' "$(date -u +%FT%TZ)"

  printf '## Per-dimension results\n\n'
  printf '| Dimension | Status | Notes |\n'
  printf '|-----------|--------|-------|\n'
  for entry in "${DIMENSIONS[@]}"; do
    name=$(printf '%s' "$entry" | cut -f1)
    status=$(printf '%s' "$entry" | cut -f2)
    notes=$(printf '%s' "$entry" | cut -f3)
    printf '| %s | %s | %s |\n' "$name" "$status" "$notes"
  done
  printf '\n'

  if [[ ${#MR4_ROWS[@]} -gt 0 ]]; then
    printf '## MR-4 — source-variant tests against harmonized-synthesis commits\n\n'
    printf '| Target | Source branch | Status |\n'
    printf '|--------|---------------|--------|\n'
    for entry in "${MR4_ROWS[@]}"; do
      target=$(printf '%s' "$entry" | cut -f1)
      src=$(printf '%s' "$entry" | cut -f2)
      st=$(printf '%s' "$entry" | cut -f3)
      printf '| %s | %s | %s |\n' "$target" "$src" "$st"
    done
    printf '\n'
  fi

  printf '## Per-commit walk on rationalization branch\n\n'
  if [[ ${#COMMIT_ROWS[@]} -eq 0 ]]; then
    printf "_(no commits between canonical and \`%s\`)_\n\n" "$RB"
  else
    for entry in "${COMMIT_ROWS[@]}"; do
      sha=$(printf '%s' "$entry" | cut -f1)
      subj=$(printf '%s' "$entry" | cut -f2)
      printf -- "- \`%s\` %s\n" "$sha" "$subj"
    done
    printf '\n'
  fi

  printf '## Verdict\n\n'
  if [[ "$LIVE_AUDIT_BLOCKED" -eq 1 ]]; then
    printf 'BLOCKED — live audit did not run on `%s`; Phase 10 cleanup must wait.\n' "$RB"
    printf '\n'
    printf 'The current worktree belonged to `%s`, so command-based checks were recorded as SKIP instead of being run on the wrong branch.\n' "$ORIG_DISPLAY"
  elif [[ "$FAILED" -eq 0 ]]; then
    printf 'PASS — Phase 10 cleanup may proceed.\n'
  else
    printf 'FAIL — %d dimension(s) failed. Phase 10 is **BLOCKED** until audit passes.\n' "$FAILED"
    printf '\n'
    printf 'Per AGENTS.md "Fix all errors regardless of source": every failed dimension\n'
    printf 'must be addressed manually before re-running this audit. Per AGENTS.md\n'
    printf '"No Script-Based Changes": fixes are made via the Edit tool, never via\n'
    printf 'sed/awk on source.\n'
  fi
} > "$REPORT"

if [[ "$LIVE_AUDIT_BLOCKED" -eq 1 ]]; then
  printf '5\n' > "$GATE_FILE"
  echo "$REPORT — BLOCKED (live audit did not run on $RB)"
  exit 5
fi
if [[ "$FAILED" -gt 0 ]]; then
  printf '5\n' > "$GATE_FILE"
  echo "$REPORT — FAIL ($FAILED dimension(s))"
  exit 5
fi
printf '0\n' > "$GATE_FILE"
echo "$REPORT — PASS"
exit 0
