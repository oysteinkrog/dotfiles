#!/usr/bin/env bash
# bootstrap-audit.sh — Initialize the audit directory for a project.
#
# Usage:
#   bootstrap-audit.sh <project-path> [score-threshold] [mode] [policy]
#
# Effect:
#   - Creates <project>/beads_compliance_audit/ as a subdirectory of the
#     project (default). Override via AUDIT_DIR_OVERRIDE env var.
#   - git init it (if not already a git repo) AND adds an entry to the
#     project's .gitignore so the audit dir is never accidentally committed
#     into the project's own git history.
#   - Writes manifest.json and rubric.md (copied from this skill's assets).
#   - Computes rubric_sha256 and pins it into the manifest for convergence checks.
#   - Opens passes/<UTC>/ for the new pass.
#   - Verifies br doctor exits clean; aborts with code 2 if any check has
#     status="fail" or any anomaly has severity="error". A workspace_health
#     of "degraded" with only WARN-level checks (e.g. preserved frankensqlite
#     recovery WAL artifacts, "never used" page warnings) is tolerated by
#     default — set BCV_REQUIRE_HEALTHY=1 to make the legacy strict check
#     active, or BCV_ALLOW_DEGRADED_FAIL=1 to also tolerate fail-status
#     checks (use only when the user has confirmed the failures are benign).
#
# Exit codes:
#   0  bootstrap succeeded; pass dir is ready to populate (path printed to stdout)
#   2  br doctor is unhealthy; hand off to /fixing-beads-problems
#   3  invalid arguments / no .beads/ / no .db file in .beads/
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path required}"
THRESHOLD="${2:-700}"
MODE="${3:-full-audit}"
POLICY="${4:-completion-debt}"

if [ ! -d "$PROJECT/.beads" ]; then
  echo "ERROR: $PROJECT does not have a .beads/ directory. Aborting." >&2
  exit 3
fi

PROJECT_ABS="$(cd "$PROJECT" && pwd)"
BASENAME="$(basename "$PROJECT_ABS")"

if [ -n "${AUDIT_DIR_OVERRIDE:-}" ]; then
  case "$AUDIT_DIR_OVERRIDE" in
    /*) AUDIT_DIR="$AUDIT_DIR_OVERRIDE" ;;
    *)  AUDIT_DIR="$(cd "$(dirname "$AUDIT_DIR_OVERRIDE")" && pwd)/$(basename "$AUDIT_DIR_OVERRIDE")" ;;
  esac
  # Hard rule: the audit dir MUST live inside the project tree unless the user
  # explicitly opted in to the sibling/external layout via
  # BCV_ALLOW_EXTERNAL_AUDIT_DIR=1. The user's standing instruction (and the
  # repeated lesson from prior runs) is that audit artifacts belong inside the
  # project being audited — sibling dirs get lost, accidentally pushed, or
  # re-created by future runs that don't know the override existed.
  case "$AUDIT_DIR" in
    "$PROJECT_ABS"|"$PROJECT_ABS"/*) ;;
    *)
      if [ "${BCV_ALLOW_EXTERNAL_AUDIT_DIR:-0}" != "1" ]; then
        echo "ERROR: AUDIT_DIR_OVERRIDE=$AUDIT_DIR_OVERRIDE resolves to" >&2
        echo "       $AUDIT_DIR" >&2
        echo "       which is OUTSIDE the project tree ($PROJECT_ABS)." >&2
        echo "" >&2
        echo "       Audit artifacts must live INSIDE the project (default" >&2
        echo "       <project>/beads_compliance_audit/). Sibling/external" >&2
        echo "       directories get lost or accidentally re-created — this is" >&2
        echo "       why this skill enforces an in-tree layout." >&2
        echo "" >&2
        echo "       If you really need an external location (e.g. CI artifacts" >&2
        echo "       dir, dedicated audit-only filesystem), set" >&2
        echo "       BCV_ALLOW_EXTERNAL_AUDIT_DIR=1 and re-run." >&2
        exit 3
      fi
      echo "WARNING: BCV_ALLOW_EXTERNAL_AUDIT_DIR=1 — placing audit dir OUTSIDE" >&2
      echo "         project tree at $AUDIT_DIR. The project's .gitignore will" >&2
      echo "         NOT be updated (no in-tree leakage to guard against), and" >&2
      echo "         future audit runs that don't set this env var will fall" >&2
      echo "         back to the default in-tree layout." >&2
      ;;
  esac
else
  AUDIT_DIR="$PROJECT_ABS/beads_compliance_audit"
fi
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Hard rule: the audit must NEVER switch the project repo's branch. Capture the
# branch we entered on so the run-pass.sh wrapper can sanity-check at the end.
# (We don't enforce here because the user might legitimately be on a non-main
# branch — what matters is that we leave it on whatever branch we found.)
ENTRY_BRANCH=""
if [ -d "$PROJECT_ABS/.git" ]; then
  ENTRY_BRANCH="$(git -C "$PROJECT_ABS" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
fi

PASS_ID="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
PASS_DIR="$AUDIT_DIR/passes/$PASS_ID"

# Resolve DB path explicitly so we don't pass an unexpanded glob to br.
shopt -s nullglob
DBS=( "$PROJECT_ABS/.beads"/*.db )
shopt -u nullglob
if [ "${#DBS[@]}" -eq 0 ]; then
  echo "ERROR: no SQLite *.db file in $PROJECT_ABS/.beads/. Aborting." >&2
  exit 3
fi
DB="${DBS[0]}"

# 1. Verify br doctor BEFORE creating anything. Capture exit code correctly.
echo "Running br doctor on $PROJECT_ABS ..." >&2
DOCTOR_OUT=""
DOCTOR_EXIT=0
DOCTOR_OUT="$(br --db "$DB" doctor --json 2>&1)" || DOCTOR_EXIT=$?

if [ "$DOCTOR_EXIT" -ne 0 ]; then
  echo "ERROR: br doctor failed with exit code $DOCTOR_EXIT. Hand off to /fixing-beads-problems." >&2
  echo "$DOCTOR_OUT" >&2
  exit 2
fi

# Health gate. We fail on hard-fail signals only:
#   - explicit ok=false / healthy=false
#   - any check with status=="fail"
#   - any reliability_audit anomaly with severity=="error"
#
# A bare workspace_health=="degraded" with only WARN-level detail (e.g.
# preserved frankensqlite recovery WAL artifacts, "Page N: never used"
# integrity notes) is treated as advisory, not a blocker — `br doctor` itself
# already exited 0 above, the bead DB is intact, and these conditions
# accumulate routinely on long-running projects.
#
# Two env-var escape hatches:
#   BCV_REQUIRE_HEALTHY=1        — strict mode (also fail when
#                                  workspace_health != "healthy")
#   BCV_ALLOW_DEGRADED_FAIL=1    — also tolerate fail-status checks (use only
#                                  when the user has confirmed they're benign)
HEALTH_REPORT="$(printf '%s' "$DOCTOR_OUT" | jq -r '
  {
    ok_false:           ((has("ok") and .ok == false) // false),
    healthy_false:      ((has("healthy") and .healthy == false) // false),
    workspace_label:    (.workspace_health // null),
    fail_check_count:   (if has("checks") then ([.checks[]? | select(.status == "fail")] | length) else 0 end),
    error_anomaly_count:(if (.reliability_audit?.anomalies // []) | type == "array" then ([.reliability_audit.anomalies[]? | select(.severity == "error")] | length) else 0 end),
    fail_check_names:   (if has("checks") then ([.checks[]? | select(.status == "fail") | (.name // .id // "?")]) else [] end),
    warn_check_names:   (if has("checks") then ([.checks[]? | select(.status == "warn") | (.name // .id // "?")]) else [] end)
  }' 2>/dev/null || echo "{}")"

OK_FALSE="$(printf '%s' "$HEALTH_REPORT" | jq -r '.ok_false // false')"
HEALTHY_FALSE="$(printf '%s' "$HEALTH_REPORT" | jq -r '.healthy_false // false')"
WORKSPACE_LABEL="$(printf '%s' "$HEALTH_REPORT" | jq -r '.workspace_label // "null"')"
FAIL_CHECK_COUNT="$(printf '%s' "$HEALTH_REPORT" | jq -r '.fail_check_count // 0')"
ERROR_ANOMALY_COUNT="$(printf '%s' "$HEALTH_REPORT" | jq -r '.error_anomaly_count // 0')"

ABORT=false
ABORT_REASON=""
if [ "$OK_FALSE" = "true" ]; then
  ABORT=true; ABORT_REASON="br doctor reports ok=false"
elif [ "$HEALTHY_FALSE" = "true" ]; then
  ABORT=true; ABORT_REASON="br doctor reports healthy=false"
elif [ "${BCV_ALLOW_DEGRADED_FAIL:-0}" != "1" ] && [ "$FAIL_CHECK_COUNT" -gt 0 ] 2>/dev/null; then
  FAIL_NAMES="$(printf '%s' "$HEALTH_REPORT" | jq -r '.fail_check_names | join(", ")')"
  ABORT=true; ABORT_REASON="br doctor has $FAIL_CHECK_COUNT check(s) with status=fail: $FAIL_NAMES"
elif [ "$ERROR_ANOMALY_COUNT" -gt 0 ] 2>/dev/null; then
  ABORT=true; ABORT_REASON="br doctor reports $ERROR_ANOMALY_COUNT reliability_audit anomaly(s) with severity=error"
elif [ "${BCV_REQUIRE_HEALTHY:-0}" = "1" ] && [ "$WORKSPACE_LABEL" != "healthy" ] && [ "$WORKSPACE_LABEL" != "null" ]; then
  ABORT=true; ABORT_REASON="BCV_REQUIRE_HEALTHY=1 set and workspace_health=$WORKSPACE_LABEL (not healthy)"
fi

if [ "$ABORT" = "true" ]; then
  echo "ERROR: $ABORT_REASON. Hand off to /fixing-beads-problems." >&2
  echo "$DOCTOR_OUT" >&2
  exit 2
fi

# Surface a non-fatal warning when "degraded" is observed so the user knows the
# audit ran on an advisory state. This is intentional — we want the user to see
# br is reporting WARNs, but not block the audit on benign accumulations like
# preserved frankensqlite recovery artifacts.
if [ "$WORKSPACE_LABEL" != "healthy" ] && [ "$WORKSPACE_LABEL" != "null" ]; then
  WARN_NAMES="$(printf '%s' "$HEALTH_REPORT" | jq -r '.warn_check_names | join(", ")')"
  echo "NOTE: br doctor reports workspace_health=$WORKSPACE_LABEL (advisory; no fail-status checks)." >&2
  if [ -n "$WARN_NAMES" ] && [ "$WARN_NAMES" != "null" ]; then
    echo "      Warn-level checks: $WARN_NAMES" >&2
  fi
  echo "      Proceeding (frankensqlite recovery artifacts are common; see references/PRE-AUDIT-CHECKS.md)." >&2
  echo "      To make this strict, set BCV_REQUIRE_HEALTHY=1." >&2
fi

# 2. Create the audit dir and pass dir.
if [ -d "$AUDIT_DIR" ]; then
  echo "Audit dir exists: $AUDIT_DIR (will create new pass)" >&2
else
  mkdir -p "$AUDIT_DIR"
  ( cd "$AUDIT_DIR" && git init -q )
  echo "Created audit dir: $AUDIT_DIR" >&2
fi

# Ensure the audit dir is ignored by the project's git when it lives inside the
# project (default layout). Without this, the project's `git status` shows
# every audit pass as a giant pile of untracked files. The audit dir has its
# own `.git/` so it's tracked separately.
case "$AUDIT_DIR" in
  "$PROJECT_ABS"/*)
    REL_AUDIT="${AUDIT_DIR#$PROJECT_ABS/}"
    GITIGNORE="$PROJECT_ABS/.gitignore"
    if [ -d "$PROJECT_ABS/.git" ]; then
      # Match the rel-audit path as a whole line (anchored). Don't add
      # duplicates if the user (or a prior bootstrap) already added it.
      if [ ! -f "$GITIGNORE" ] || ! grep -Fxq "/$REL_AUDIT/" "$GITIGNORE"; then
        printf '\n# Beads compliance audit dir (managed by /beads-compliance-and-completion-verification skill)\n/%s/\n' "$REL_AUDIT" >> "$GITIGNORE"
        echo "Added /$REL_AUDIT/ to $GITIGNORE" >&2
      fi
    fi
    ;;
esac

# Pass-id collision avoidance. The default PASS_ID is second-precision
# (`%Y-%m-%dT%H-%M-%SZ`); two passes that fire in the SAME UTC second would
# otherwise share PASS_DIR and the second one would silently overwrite the
# first's manifest, scorecards, and convergence.json — violating the
# "audit dirs are sacred" invariant. We use atomic `mkdir` (without -p) to
# claim PASS_DIR; on collision we retry with a 4-hex random suffix until
# we find a free name (bounded retries to avoid an infinite loop if some
# other process is hammering the dir).
mkdir -p "$AUDIT_DIR/passes"
attempt=0
while ! mkdir "$PASS_DIR" 2>/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 16 ]; then
    echo "ERROR: couldn't create unique PASS_DIR after $attempt attempts" >&2
    echo "       (last tried: $PASS_DIR — is something else writing to passes/?)" >&2
    exit 4
  fi
  PASS_ID="$(date -u +%Y-%m-%dT%H-%M-%SZ)_$(printf '%04x' "$RANDOM")"
  PASS_DIR="$AUDIT_DIR/passes/$PASS_ID"
done
mkdir -p "$PASS_DIR/beads"

# 3. Copy rubric template if not already present, then compute its SHA so the
# manifest pins the rubric and convergence checks can detect rubric drift.
if [ ! -f "$AUDIT_DIR/rubric.md" ]; then
  cp "$SKILL_DIR/assets/rubric-template.md" "$AUDIT_DIR/rubric.md"
  # Patch the threshold into rubric.md frontmatter (best-effort; works on GNU sed and BSD sed).
  if sed --version >/dev/null 2>&1; then
    sed -i "s/^score_threshold: .*/score_threshold: $THRESHOLD/" "$AUDIT_DIR/rubric.md"
  else
    sed -i '' "s/^score_threshold: .*/score_threshold: $THRESHOLD/" "$AUDIT_DIR/rubric.md"
  fi
fi
RUBRIC_SHA="$(sha256sum "$AUDIT_DIR/rubric.md" | awk '{print $1}')"

# 3.5 Seed audit-policy.yaml in audit-dir on first creation. Resolution:
#   - if <project>/audit-policy.yaml exists, copy it (project-local override wins).
#   - elif <project>/.beads/audit-policy.yaml exists, copy it.
#   - else copy the skill's template (so consumers always have a real file
#     to read; otherwise the helper silently falls back to defaults and
#     newly-introduced YAML fields would never surface).
if [ ! -f "$AUDIT_DIR/audit-policy.yaml" ]; then
  if [ -f "$PROJECT_ABS/audit-policy.yaml" ]; then
    cp "$PROJECT_ABS/audit-policy.yaml" "$AUDIT_DIR/audit-policy.yaml"
    echo "Copied audit-policy.yaml from $PROJECT_ABS/" >&2
  elif [ -f "$PROJECT_ABS/.beads/audit-policy.yaml" ]; then
    cp "$PROJECT_ABS/.beads/audit-policy.yaml" "$AUDIT_DIR/audit-policy.yaml"
    echo "Copied audit-policy.yaml from $PROJECT_ABS/.beads/" >&2
  else
    cp "$SKILL_DIR/assets/audit-policy.yaml" "$AUDIT_DIR/audit-policy.yaml"
    echo "Seeded audit-policy.yaml from skill template" >&2
  fi
fi

# 4. Write manifest.json (per-pass and top-level).
TOOLS_JSON="{}"
# Some tools (notably `go`) exit non-zero on `--version` and that would trip
# `set -o pipefail`. Each per-tool block is wrapped in its own `|| true` so a
# version probe can never abort the bootstrap.
for tool in br bv ast-grep rg jq cargo go npm pnpm bun python3 pytest cargo-fuzz; do
  command -v "$tool" >/dev/null 2>&1 || continue
  case "$tool" in
    go)        VER_CMD=(go version) ;;
    *)         VER_CMD=("$tool" --version) ;;
  esac
  VER="$( ( "${VER_CMD[@]}" 2>/dev/null || true ) | head -1 | tr -d '\n' | sed 's/"/\\"/g' )"
  TOOLS_JSON="$(printf '%s' "$TOOLS_JSON" | jq --arg t "$tool" --arg v "$VER" '. + {($t): $v}')"
done

PROJECT_SHA="$(git -C "$PROJECT_ABS" rev-parse HEAD 2>/dev/null || echo unknown)"

MANIFEST=$(jq -n \
  --arg project "$PROJECT_ABS" \
  --arg sha "$PROJECT_SHA" \
  --arg entry_branch "$ENTRY_BRANCH" \
  --arg pass_id "$PASS_ID" \
  --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg mode "$MODE" \
  --arg policy "$POLICY" \
  --arg rubric_sha "$RUBRIC_SHA" \
  --argjson threshold "$THRESHOLD" \
  --argjson tools "$TOOLS_JSON" \
  '{
    audit_dir_version: "1.0.0",
    project_path: $project,
    project_git_sha_at_pass_start: $sha,
    project_branch_at_pass_start: $entry_branch,
    skill_version: "1.0.0",
    rubric_version: "1.0.0",
    rubric_sha256: $rubric_sha,
    pass_id: $pass_id,
    pass_started_at: $started,
    pass_completed_at: null,
    mode: $mode,
    score_threshold: $threshold,
    remediation_policy: $policy,
    parallelism: 6,
    tools: $tools,
    bead_counts: null,
    phase_status: {"1":"pending","2":"pending","3":"pending","4":"pending","5":"pending","6":"pending","7":"pending","8":"pending","9":"pending","9.5":"pending","10":"pending"},
    convergence: null
  }')

printf '%s' "$MANIFEST" > "$PASS_DIR/manifest.json"
printf '%s' "$MANIFEST" > "$AUDIT_DIR/manifest.json"

# 5. Write README.md if not present.
if [ ! -f "$AUDIT_DIR/README.md" ]; then
  cat > "$AUDIT_DIR/README.md" <<EOF
# Beads Compliance Audit — ${BASENAME}

Sibling audit directory for \`$PROJECT_ABS\`. Tracks every \`closed\` bead's actual completion against its spec.

- **Mode:** ${MODE}
- **Score threshold for false-closed flag:** ${THRESHOLD}
- **Remediation policy:** ${POLICY}
- **Bootstrapped:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Skill:** beads-compliance-and-completion-verification

## How to read this dir

1. \`REPORT.md\` — latest master report (executive summary, false-closed list).
2. \`trends.md\` — score-over-time across passes.
3. \`passes/<UTC>/\` — per-pass artifacts.
4. \`passes/<UTC>/beads/<bead-id>/scorecard.md\` — per-bead score breakdown.

Every pass is a single git commit. History is sacred — never delete a prior pass.
EOF
fi

# 6. Compute initial bead counts.
COUNTS_JSON="{}"
if COUNTS_RAW="$(br --db "$DB" stats --json 2>/dev/null)"; then
  COUNTS_JSON="$(printf '%s' "$COUNTS_RAW" | jq '.summary // .')"
fi
TMP_MAN="$(mktemp)"
# Write through a tmp file so failed jq output never corrupts the manifest. Per
# repo no-deletion policy, failed tmp output is retained for diagnosis; a
# successful mv consumes it.
jq --argjson counts "$COUNTS_JSON" '.bead_counts = $counts' "$PASS_DIR/manifest.json" > "$TMP_MAN"
mv "$TMP_MAN" "$PASS_DIR/manifest.json"
cp "$PASS_DIR/manifest.json" "$AUDIT_DIR/manifest.json"

# 7. Done. Print pass dir to stdout for the calling agent.
echo "$PASS_DIR"
