#!/usr/bin/env bash
# anomaly-scan.sh — Phase 5 follow-up: check non-evidence-file anomalies
# (git history, close-reason hedge phrases, batch-close, time-to-close, etc.)
# and merge results into the bead's theater.json.
#
# Usage:
#   anomaly-scan.sh <project-path> <pass-dir>/beads/<bead-id>
#
# Reads:
#   show.json     (status, close_reason, closed_at, created_at, closed_by_session)
#   inventory.jsonl in the pass dir (for batch-close detection across the universe)
#
# Writes (merges into):
#   theater.json findings array (with category prefixed "anomaly_")
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path}"
BEAD_DIR="${2:?bead dir}"
SHOW="$BEAD_DIR/show.json"
THEATER="$BEAD_DIR/theater.json"
INVENTORY="$(dirname "$(dirname "$BEAD_DIR")")/inventory.jsonl"

[ -f "$SHOW" ] || { echo "no show.json" >&2; exit 0; }
[ -f "$THEATER" ] || { echo "no theater.json — run theater-scan.sh first" >&2; exit 0; }

ID="$(jq -r '.id // empty' "$SHOW")"
STATUS="$(jq -r '.status // empty' "$SHOW")"
CLOSE_REASON="$(jq -r '.close_reason // empty' "$SHOW")"
CLOSED_AT="$(jq -r '.closed_at // empty' "$SHOW")"
CREATED_AT="$(jq -r '.created_at // empty' "$SHOW")"
CLOSED_BY="$(jq -r '.closed_by_session // empty' "$SHOW")"

# Helper to append a finding. Write through a tmp file so failed jq output never
# corrupts theater.json. Per repo no-deletion policy, a failed write leaves the
# tmp artifact available for diagnosis; a successful mv consumes it.
append_finding() {
  local sev="$1" cat="$2" desc="$3"
  local tmp
  tmp="$(mktemp)"
  jq --arg sev "$sev" --arg cat "$cat" --arg desc "$desc" --arg id "$ID" \
    '.findings += [{
       id: ("anomaly." + (((.findings | length) + 1) | tostring)),
       severity: $sev,
       category: $cat,
       path: ("(bead " + $id + ")"),
       line: 0,
       snippet: "(see show.json)",
       description: $desc
     }]
     | .summary[$sev] = ((.summary[$sev] // 0) + 1)' \
    "$THEATER" > "$tmp"
  mv "$tmp" "$THEATER"
}

# Pattern 11 — apologetic close reason (Pattern 22 in catalog)
if [ -n "$CLOSE_REASON" ]; then
  if printf '%s' "$CLOSE_REASON" | grep -qiE '(for now|will follow up|first pass|coming next|temporary|placeholder|good enough|ship it|partial)'; then
    append_finding "MAJOR" "anomaly_apologetic_close" \
      "close_reason contains hedge phrase: \"$CLOSE_REASON\""
  fi
fi

# Pattern 11/22 — WIP / draft markers in close reason
if [ -n "$CLOSE_REASON" ]; then
  if printf '%s' "$CLOSE_REASON" | grep -qiE '\b(WIP|draft|TODO|FIXME)\b'; then
    append_finding "BLOCKING" "anomaly_wip_close_reason" \
      "close_reason explicitly says WIP/draft/TODO: \"$CLOSE_REASON\""
  fi
fi

# Pattern 12 — closed bead with zero git commits referencing it.
#
# Demotion logic (added v1.1): when inventory-beads.sh's
# git_xref_coverage.json says less than 30% of closed beads have ANY git
# xref, that's a project-wide commit-convention gap rather than a per-bead
# defect. In that case we still emit the finding (so it shows up in the
# evidence pack), but we demote it to NOTE — the score-bead.py rubric only
# penalizes BLOCKING / MAJOR / MINOR for anti-theater, so a NOTE-level
# finding becomes informational and doesn't drop the bead's score by 15
# points each.
if [ "$STATUS" = "closed" ] && [ -d "$PROJECT/.git" ]; then
  XREF_COUNT=$(git -C "$PROJECT" log --all -F --grep="$ID" --format=%H 2>/dev/null | wc -l | tr -d ' ')
  if [ "$XREF_COUNT" = "0" ]; then
    PASS_DIR="$(dirname "$(dirname "$BEAD_DIR")")"
    XREF_COVERAGE_FILE="$PASS_DIR/git_xref_coverage.json"
    SEV_FOR_NOXREF="MAJOR"
    DESC_FOR_NOXREF="Closed bead $ID has zero commits mentioning its ID across all branches"
    if [ -f "$XREF_COVERAGE_FILE" ] && \
       jq -e '.project_convention_gap_widespread == true' "$XREF_COVERAGE_FILE" >/dev/null 2>&1; then
      SEV_FOR_NOXREF="NOTE"
      # `// "?"` defaults `coverage_pct` to "?" if the field is null OR
      # missing, so the description never reads "...is only null%..." when
      # the JSON is partial.
      PCT=$(jq -r '.coverage_pct // "?"' "$XREF_COVERAGE_FILE" 2>/dev/null || echo "?")
      DESC_FOR_NOXREF="Closed bead $ID has zero commits mentioning its ID — DEMOTED from MAJOR to NOTE because project-wide git xref coverage is only ${PCT}% (project commit convention rather than per-bead defect)"
    fi
    append_finding "$SEV_FOR_NOXREF" "anomaly_no_git_xref" "$DESC_FOR_NOXREF"
  fi
fi

# Pattern 19 — empty PR diff (closing commit touches no production code)
if [ "$STATUS" = "closed" ] && [ -d "$PROJECT/.git" ]; then
  # `git log --grep` exits non-zero on a few edge cases (shallow repo, certain
  # --grep regex inputs); pipefail would otherwise propagate that and kill us
  # under set -e. We tolerate the failure and treat empty output as "no match".
  CLOSING_SHA=$(git -C "$PROJECT" log --all -F --grep="$ID" --format=%H 2>/dev/null | head -1 || true)
  if [ -n "$CLOSING_SHA" ]; then
    FILES_CHANGED=$(git -C "$PROJECT" show --pretty=format: --name-only "$CLOSING_SHA" 2>/dev/null \
      | grep -c -v '^$' || true)
    if [ "$FILES_CHANGED" = "0" ]; then
      append_finding "MAJOR" "anomaly_empty_diff" \
        "Closing commit $CLOSING_SHA touches zero files"
    fi
  fi
fi

# Pattern 21 — time-to-close < 5 minutes
if [ -n "$CLOSED_AT" ] && [ -n "$CREATED_AT" ]; then
  CLOSED_S=$(date -d "$CLOSED_AT" +%s 2>/dev/null || echo 0)
  CREATED_S=$(date -d "$CREATED_AT" +%s 2>/dev/null || echo 0)
  if [ "$CLOSED_S" -gt 0 ] && [ "$CREATED_S" -gt 0 ]; then
    DELTA=$(( CLOSED_S - CREATED_S ))
    BEAD_TYPE=$(jq -r '.issue_type // "task" | if type == "object" then to_entries[0].value else . end' "$SHOW")
    # Trivial chores can legitimately close fast; only flag for feature/bug.
    if [ "$DELTA" -lt 300 ] && [ "$DELTA" -gt 0 ]; then
      case "$BEAD_TYPE" in
        feature|bug|epic)
          append_finding "MAJOR" "anomaly_fast_close" \
            "Closed $DELTA seconds after creation (feature/bug should not close that fast)"
          ;;
      esac
    fi
  fi
fi

# Pattern 20 — batch-close (this session closed > 5 beads in 5 minutes)
if [ -n "$CLOSED_BY" ] && [ -f "$INVENTORY" ] && [ -n "$CLOSED_AT" ]; then
  CLOSED_S=$(date -d "$CLOSED_AT" +%s 2>/dev/null || echo 0)
  if [ "$CLOSED_S" -gt 0 ]; then
    BATCH_COUNT=$(jq -r --arg sess "$CLOSED_BY" --argjson now "$CLOSED_S" \
      'select(.closed_by_session == $sess and .closed_at != null)
       | .closed_at' "$INVENTORY" 2>/dev/null \
      | while read -r ts; do
          [ -n "$ts" ] || continue
          T=$(date -d "$ts" +%s 2>/dev/null || echo 0)
          if [ "$T" -gt 0 ]; then
            DIFF=$(( T - CLOSED_S ))
            [ "${DIFF#-}" -le 300 ] && echo 1
          fi
        done | wc -l | tr -d ' ')
    if [ "${BATCH_COUNT:-0}" -gt 5 ]; then
      append_finding "MAJOR" "anomaly_batch_close" \
        "Session $CLOSED_BY closed $BATCH_COUNT beads within 5 minutes of this one"
    fi
  fi
fi

# Pattern 23 — additions to ignore lists in the closing diff
if [ "$STATUS" = "closed" ] && [ -d "$PROJECT/.git" ]; then
  # `git log --grep` exits non-zero on a few edge cases (shallow repo, certain
  # --grep regex inputs); pipefail would otherwise propagate that and kill us
  # under set -e. We tolerate the failure and treat empty output as "no match".
  CLOSING_SHA=$(git -C "$PROJECT" log --all -F --grep="$ID" --format=%H 2>/dev/null | head -1 || true)
  if [ -n "$CLOSING_SHA" ]; then
    IGNORE_ADDS=$(git -C "$PROJECT" show "$CLOSING_SHA" -- '.ubsignore' '.eslintignore' '.gitignore' \
      '.flake8' 'pyproject.toml' 2>/dev/null | grep -c -E '^\+[^+]' || true)
    if [ "${IGNORE_ADDS:-0}" -gt 0 ]; then
      append_finding "BLOCKING" "anomaly_ignore_list_growth" \
        "Closing commit added $IGNORE_ADDS line(s) to ignore lists — possible silencing instead of fixing"
    fi
  fi
fi

# Done. Print summary.
jq -r '"Anomaly scan: " + (
  [.findings[] | select(.id | startswith("anomaly."))]
  | "BLOCKING=" + ([.[] | select(.severity == "BLOCKING")] | length | tostring)
  + " MAJOR=" + ([.[] | select(.severity == "MAJOR")] | length | tostring)
  + " MINOR=" + ([.[] | select(.severity == "MINOR")] | length | tostring))' "$THEATER" >&2
