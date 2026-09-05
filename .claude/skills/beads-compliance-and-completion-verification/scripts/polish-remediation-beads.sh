#!/usr/bin/env bash
# polish-remediation-beads.sh — Phase 9.5 SCAFFOLDING for the iterative polish
# loop. Generates a polish_log.md template that an orchestrator agent fills
# in while applying the user-mandated polish prompt 3 times in a row.
#
# Usage:
#   polish-remediation-beads.sh <project-path> <pass-dir>
#                                                [--sweeps 3]
#                                                [--no-bv]
#                                                [--out <file>]
#                                                [--force]
#
# What this script DOES (deterministic scaffolding):
#   * Reads <pass-dir>/remediation.md to discover the bead IDs Phase 9 wrote
#     or reopened (filtering out the table header / separator rows).
#   * Captures one snapshot of bv hygiene signals (--robot-suggest /
#     --robot-priority / --robot-alerts) into <pass-dir>/polish_bv_initial.json.
#   * Writes <pass-dir>/polish_log.md with one section per sweep (1, 2, 3),
#     each containing:
#       - the verbatim polish prompt (matches SKILL.md Phase 9.5 verbatim),
#       - per-bead pre-state (from `br show`),
#       - empty checklists / note slots for the orchestrator to fill in.
#
# What this script DOES NOT do:
#   * It does not invoke any LLM. The polish prompt is meant to be applied by
#     the orchestrator agent (the LLM that invoked this skill). This script is
#     pure scaffolding so the loop is auditable.
#   * It does not modify beads. All edits go through `br update` / `br comment`
#     in the orchestrator's hands, OUTSIDE this script.
#   * It does not snapshot beads "before/after" each sweep. The orchestrator
#     drives the sweeps in their own conversation; this script's structure is
#     what lets them keep state coherent.
#
# Idempotency:
#   * If polish_log.md already exists, the script REFUSES to overwrite (so
#     orchestrator notes are never silently clobbered). Pass --force to
#     overwrite anyway.
#
# Exit codes:
#   0  scaffolding written (or no-op when zero beads to polish)
#   2  remediation.md missing
#   3  invalid args / no .beads/ DB / refusing to overwrite without --force
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path}"
PASS_DIR="${2:?pass dir}"
shift 2 || true

SWEEPS=3
USE_BV=1
OUT=""
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sweeps)
      [ $# -ge 2 ] || { echo "ERROR: --sweeps requires a value" >&2; exit 3; }
      SWEEPS="$2"; shift 2 ;;
    --no-bv)             USE_BV=0; shift ;;
    --out)
      [ $# -ge 2 ] || { echo "ERROR: --out requires a value" >&2; exit 3; }
      OUT="$2"; shift 2 ;;
    --force)             FORCE=1; shift ;;
    # Accepted-but-ignored flag from the earlier API. Kept so callers that
    # hardcoded `--max-extra-sweeps N` (e.g. older `run-pass.sh` revisions)
    # don't break on upgrade. The current scaffolding-only design has no
    # extra-sweep concept — the orchestrator decides convergence and runs
    # additional sweeps inline if needed.
    --max-extra-sweeps)
      shift
      # Consume the value ONLY if it looks like a value (not another flag).
      # `--max-extra-sweeps 2` → consume both.  `--max-extra-sweeps --force`
      # → consume just the flag, leave --force for the next iteration.
      # Bare `--max-extra-sweeps` at end-of-args also handled (just shift once).
      if [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
        shift
      fi
      ;;
    *) echo "Unknown arg: $1" >&2; exit 3 ;;
  esac
done

[[ "$SWEEPS" =~ ^[0-9]+$ ]] && [ "$SWEEPS" -ge 1 ] || { echo "ERROR: --sweeps must be a positive integer" >&2; exit 3; }

PROJECT_ABS="$(cd "$PROJECT" && pwd)"
[ -z "$OUT" ] && OUT="$PASS_DIR/polish_log.md"

REMED="$PASS_DIR/remediation.md"
[ -f "$REMED" ] || { echo "ERROR: missing $REMED — run Phase 9 (remediate.sh) first" >&2; exit 2; }

# Idempotency check. Don't clobber an existing polish_log.md (which may already
# contain the orchestrator's notes from a prior partial run).
if [ -f "$OUT" ] && [ "$FORCE" -ne 1 ]; then
  echo "ERROR: $OUT already exists. Refusing to overwrite (orchestrator notes" >&2
  echo "       would be lost). Pass --force to override, or back up the file" >&2
  echo "       first if it has work in progress." >&2
  exit 3
fi

# Resolve the bead store DB so `br --db` can address it explicitly.
shopt -s nullglob
DBS=( "$PROJECT_ABS/.beads"/*.db )
shopt -u nullglob
if [ "${#DBS[@]}" -eq 0 ]; then
  echo "ERROR: no SQLite *.db file in $PROJECT_ABS/.beads/" >&2
  exit 3
fi
DB="${DBS[0]}"

# Extract every "New/Reopened ID" from the Actions table in remediation.md.
# The table format is:
#   | Original bead | Score | Action | New/Reopened ID | Status |    ← header
#   |---------------|------:|--------|-----------------|--------|    ← separator
#   | `bd-orig`     | 540   | …      | `bd-new`        | open   |    ← data
#
# With `-F '|'`, awk's $1 is the empty leading field, $2..$6 are the visible
# columns, $7 is the empty trailing field. We capture $5 (the New/Reopened ID
# column) and filter out:
#   * the literal header text ("New/Reopened ID")
#   * the markdown table separator ("-----------------" — all dashes)
#   * the "no remediation" placeholder rows (cell == "-")
#
# The accepted-character set is intentionally conservative: bead IDs come
# from `br create --json | jq -r .id` and are alphanumerics + dashes + dots
# + underscores. Anything else is suspicious and likely a parse artifact.
mapfile -t TARGET_IDS < <(awk -F '|' '
  /^## Actions/ {flag=1; next}
  /^## / && flag {flag=0}
  flag && NF >= 6 {
    nid = $5
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", nid)
    gsub(/`/, "", nid)
    if (nid == "" || nid == "-") next
    if (nid == "New/Reopened ID") next
    if (nid ~ /^-+$/) next
    if (nid !~ /^[a-zA-Z0-9_.-]+$/) next
    if (nid !~ /[a-zA-Z0-9]/) next
    print nid
  }
' "$REMED" | awk '!seen[$0]++')

# Verbatim polish prompt — MUST stay character-identical to SKILL.md's
# "Phase 9.5 — Mandatory polish loop" section. Any drift between the two
# breaks the auditability guarantee (the user's intent was that the same
# string is applied each sweep).
POLISH_PROMPT='Check over each bead super carefully — are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It'\''s a lot easier and faster to operate in "plan space" before we start implementing these things! DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY! Also make sure that as part of the beads we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Make sure to ONLY use the `br` cli tool for all changes, and you can and should also use the `bv` tool to help diagnose potential problems with the beads.'

# No-op fast path — Phase 9 wrote nothing.
if [ "${#TARGET_IDS[@]}" -eq 0 ]; then
  {
    echo "# Polish log — pass $(basename "$PASS_DIR")"
    echo ""
    echo "_Phase 9 wrote zero beads (policy may be report-only, or every closed_"
    echo "_bead scored ≥ threshold, or every Phase-9 br call failed)._"
    echo ""
    echo "_No polish loop needed. ✓_"
  } > "$OUT"
  echo "Phase 9.5 scaffold: nothing to polish (0 new/reopened beads). See $OUT" >&2
  exit 0
fi

echo "Phase 9.5 scaffold: $SWEEPS sweep section(s) over ${#TARGET_IDS[@]} bead(s)..." >&2

# Capture an initial bv hygiene snapshot (one capture, not per-sweep — the
# orchestrator can re-capture between sweeps if they want, but a single shared
# baseline keeps polish_log.md compact). Each `bv --robot-*` call is captured
# atomically via tmp-files so a partial output never produces malformed JSON.
collect_bv_signal() {
  local subcmd="$1" tmp
  tmp="$(mktemp)"
  if [ "$USE_BV" -eq 0 ] || ! command -v bv >/dev/null 2>&1; then
    printf 'null' > "$tmp"
  else
    if ! bv "$subcmd" >"$tmp" 2>/dev/null; then
      printf 'null' > "$tmp"
    elif [ ! -s "$tmp" ]; then
      printf 'null' > "$tmp"
    elif ! jq -e . "$tmp" >/dev/null 2>&1; then
      # bv exited zero but produced non-JSON. Shouldn't happen for --robot-*
      # commands, but defend anyway.
      printf 'null' > "$tmp"
    fi
  fi
  printf '%s' "$tmp"
}

BV_FILE="$PASS_DIR/polish_bv_initial.json"
SUGGEST_FILE="$(collect_bv_signal --robot-suggest)"
PRIORITY_FILE="$(collect_bv_signal --robot-priority)"
ALERTS_FILE="$(collect_bv_signal --robot-alerts)"
trap 'rm -f "$SUGGEST_FILE" "$PRIORITY_FILE" "$ALERTS_FILE"' EXIT

# Compose the bv signal file from the three captures. Each input is either
# valid JSON or the literal string "null"; jq treats "null" as JSON null, so
# the output is always a valid JSON object.
jq -n --slurpfile s "$SUGGEST_FILE" --slurpfile p "$PRIORITY_FILE" --slurpfile a "$ALERTS_FILE" \
  '{suggest: ($s[0] // null), priority: ($p[0] // null), alerts: ($a[0] // null)}' \
  > "$BV_FILE" 2>/dev/null || echo '{"suggest":null,"priority":null,"alerts":null}' > "$BV_FILE"

DUP_COUNT="$(jq '[.suggest.duplicates // []] | flatten | length' "$BV_FILE" 2>/dev/null || echo 0)"
MISS_DEP_COUNT="$(jq '[.suggest.missing_dependencies // []] | flatten | length' "$BV_FILE" 2>/dev/null || echo 0)"
MISMATCH_COUNT="$(jq '[.priority.mismatches // []] | flatten | length' "$BV_FILE" 2>/dev/null || echo 0)"

# Truncate `br show` output for compactness (multi-page descriptions blow up
# polish_log.md without adding signal).
truncate_lines() {
  local n="$1"
  awk -v n="$n" 'NR<=n; END{ if (NR>n) print "... (truncated " (NR-n) " more lines)" }'
}

# Now write the scaffold. Single brace group → single $OUT redirect → if
# anything below errors, the file is left empty rather than half-written.
{
  echo "# Polish log — pass $(basename "$PASS_DIR")"
  echo ""
  echo "**Beads under polish:** ${#TARGET_IDS[@]}"
  echo ""
  echo "**Sweeps:** $SWEEPS (the user's standing rule: minimum 3, run a 4th if Sweep $SWEEPS still produces meaningful edits)."
  echo ""
  echo "**bv hygiene snapshot (initial):** \`$BV_FILE\`"
  echo ""
  echo "  - duplicates flagged: $DUP_COUNT"
  echo "  - missing-dependency suggestions: $MISS_DEP_COUNT"
  echo "  - priority mismatches: $MISMATCH_COUNT"
  echo ""
  echo "## Polish prompt (verbatim — apply to each bead each sweep)"
  echo ""
  echo "> $POLISH_PROMPT"
  echo ""
  echo "## Targets"
  echo ""
  for ID in "${TARGET_IDS[@]}"; do
    # `br show --json` emits a JSON ARRAY (not an object). Always index .[0].
    # Without the index, jq raises "Cannot index array with string" and TITLE
    # falls back to "(unknown)" — observed during v1.2 self-review smoke test.
    TITLE="$(br --db "$DB" show "$ID" --json 2>/dev/null \
              | jq -r '(if type=="array" then .[0] else . end) | (.title // "(untitled)")' 2>/dev/null \
              || echo "(unknown)")"
    echo "- \`$ID\` — $TITLE"
  done
  echo ""
  echo "## Orchestrator instructions"
  echo ""
  echo "For each Sweep section below, apply the polish prompt VERBATIM to every bead. For each bead:"
  echo ""
  echo "  1. Read the bead's current state (\`br show <id>\`)."
  echo "  2. Decide: needs revision, no change, or split / merge."
  echo "  3. If revising:"
  echo "     - \`br update <id> --title='…'\` (only if the title needs sharpening)"
  echo "     - \`br update <id> --description='…'\` (full new description, NEVER hand-edit JSONL)"
  echo "     - \`br update <id> --acceptance-criteria='…'\` (must include unit tests + e2e tests + detailed logging per the prompt)"
  echo "     - \`br comment <id> --body='sweep N: <one-line decision summary>'\`"
  echo "  4. If splitting / merging: \`br create\` and \`br dep add\` as appropriate, recording rationale in a \`br comment\`."
  echo "  5. Fill in the \"Decision\" line under the bead's section below."
  echo ""
  echo "Between sweeps, re-run \`bv --robot-suggest\` and \`bv --robot-priority\` to see whether the graph improved."
  echo ""
  echo "After all sweeps, run \`br sync --flush-only\` and commit \`.beads/\` (do NOT push)."
  echo ""

  for sweep_n in $(seq 1 "$SWEEPS"); do
    echo "---"
    echo ""
    echo "## Sweep $sweep_n / $SWEEPS"
    echo ""
    echo "_Apply the polish prompt above to each bead. Record decisions inline._"
    echo ""

    for ID in "${TARGET_IDS[@]}"; do
      SHOW_OUT="$(br --db "$DB" show "$ID" 2>/dev/null || true)"
      [ -z "$SHOW_OUT" ] && SHOW_OUT="(br show failed for $ID — bead may have been tombstoned)"
      echo "### Sweep $sweep_n — \`$ID\`"
      echo ""
      echo "<details><summary>Current state (br show)</summary>"
      echo ""
      echo '```'
      printf '%s\n' "$SHOW_OUT" | truncate_lines 80
      echo '```'
      echo ""
      echo "</details>"
      echo ""
      echo "**Decision:** _(orchestrator fills in: \`revised\` / \`no-change\` / \`split\` / \`merged\` / \`closed\`; one line summary)_"
      echo ""
      echo "**\`br update\` invocations (paste here for audit trail):**"
      echo ""
      echo '```'
      echo "(none yet)"
      echo '```'
      echo ""
    done
  done

  echo "---"
  echo ""
  echo "## Sign-off"
  echo ""
  echo "- [ ] All $SWEEPS sweep(s) completed."
  echo "- [ ] If Sweep $SWEEPS still produced meaningful edits, ran a Sweep $((SWEEPS + 1))."
  echo "- [ ] \`br sync --flush-only\` run."
  echo "- [ ] \`.beads/\` staged (\`git add .beads/\`)."
  echo "- [ ] (Optional) committed locally; user decides when to push."
  echo ""
  echo "_Final bv hygiene check — paste the \`bv --robot-suggest\` output below to confirm the graph improved:_"
  echo ""
  echo '```'
  echo "(orchestrator: paste post-polish bv --robot-suggest output)"
  echo '```'
} > "$OUT"

echo "Phase 9.5 scaffold written: $OUT" >&2
echo "  Beads under polish: ${#TARGET_IDS[@]}" >&2
echo "  Sweep sections: $SWEEPS" >&2
echo "  bv signals captured: $BV_FILE" >&2
echo "" >&2
echo "Next step: orchestrator agent applies the polish prompt to each bead in" >&2
echo "each sweep section, makes \`br update\` / \`br comment\` calls, and fills" >&2
echo "in the Decision line per bead. See $OUT." >&2
