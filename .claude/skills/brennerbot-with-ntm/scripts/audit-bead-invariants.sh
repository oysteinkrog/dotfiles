#!/usr/bin/env bash
# audit-bead-invariants.sh — Verify mandatory invariants on beads.
#
# Usage:
#   audit-bead-invariants.sh --check=<check-name> [--workspace=<path>]
#   audit-bead-invariants.sh --all [--workspace=<path>]
#
# Checks:
#   third_alternative_present  — Slate has ≥1 H with origin: third_alternative (Phase 3 exit)
#   every_H_has_falsifier      — Every hypothesis bead has non-empty falsifier (✂)
#   every_H_has_expected_evidence — Every hypothesis has expected_evidence (⌂)
#   every_refuted_has_refuted_by — Every state: refuted hypothesis has refuted_by (†)
#   every_scale_physics_has_calculation — Every assumption.type: scale_physics has calculation (⊞)
#   every_confirmed_has_debate — Every state: confirmed hypothesis cites a DEBATE-* + ≥2 EVs from independent sources
#   layout_invariants          — Workspace layout invariants per WORKSPACE-LAYOUT.md
#   handback_open_thread_tags  — Every H/EV/AF/D listed as still open in HANDBACK.md has next-action
#   phase3_exit                — All Phase 3 invariants
#   phase4_round               — All Phase 4 round invariants
#   phase7_exit                — All Phase 7 invariants

set -uo pipefail

WORKSPACE="."
CHECK=""
ALL="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check=*) CHECK="${1#*=}" ;;
    --all) ALL="true" ;;
    --workspace=*) WORKSPACE="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

cd "$WORKSPACE" 2>/dev/null || { echo "workspace not found: $WORKSPACE" >&2; exit 1; }
command -v br >/dev/null 2>&1 || { echo "br CLI not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq not found" >&2; exit 2; }

VIOLATIONS=0

violation() {
  echo "VIOLATION [$1]: $2" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
}

check_third_alternative_present() {
  # Vacuously satisfied when there's no slate yet — `--all` runs in early
  # Phase 0/1 workspaces (e.g., from brennerbot-doctor.sh) where 0 hypotheses
  # exist, and firing a violation in that state was a false positive that made
  # `pillar 3` light up yellow on every fresh bootstrap.
  local total third
  total=$(br list --label=hypothesis --json 2>/dev/null | \
    jq '.issues | length' 2>/dev/null || echo 0)
  if [ "$total" -lt 1 ]; then
    return 0
  fi
  third=$(br list --label=hypothesis --status=open --json 2>/dev/null | \
    jq '[.issues[]? | select((.description // "") | contains("origin: third_alternative"))] | length' 2>/dev/null || echo 0)
  if [ "$third" -lt 1 ]; then
    violation third_alternative_present "Slate has $total hypotheses but 0 with origin: third_alternative; per Brenner §103"
  fi
}

check_every_H_has_falsifier() {
  while read -r id; do
    [ -n "$id" ] && violation every_H_has_falsifier "$id missing falsifier:"
  done < <(br list --label=hypothesis --json 2>/dev/null | \
    jq -r '.issues[]? | select((.description // "") | contains("falsifier:") | not) | .id' 2>/dev/null)
}

check_every_H_has_expected_evidence() {
  while read -r id; do
    [ -n "$id" ] && violation every_H_has_expected_evidence "$id missing expected_evidence:"
  done < <(br list --label=hypothesis --json 2>/dev/null | \
    jq -r '.issues[]? | select((.description // "") | contains("expected_evidence:") | not) | .id' 2>/dev/null)
}

check_every_refuted_has_refuted_by() {
  while read -r id; do
    [ -n "$id" ] && violation every_refuted_has_refuted_by "$id state=refuted but no refuted_by"
  done < <(br list --label=hypothesis --json 2>/dev/null | \
    jq -r '
      def field_is($name; $value):
        (.description // "") | test("(^|\\n)" + $name + ":[[:space:]]*" + $value + "([[:space:]]|$)");
      def has_field($name):
        (.description // "") | test("(^|\\n)" + $name + ":[[:space:]]*[^[:space:]\\n]");
      .issues[]? | select(field_is("state"; "refuted") and (has_field("refuted_by") | not)) | .id
    ' 2>/dev/null)
}

check_every_scale_physics_has_calculation() {
  while read -r id; do
    [ -n "$id" ] && violation every_scale_physics_has_calculation "$id is type: scale_physics but no calculation"
  done < <(br list --label=assumption --json 2>/dev/null | \
    jq -r '.issues[]? | select((.description // "") | contains("type: scale_physics") and (contains("calculation:") | not)) | .id' 2>/dev/null)
}

supporting_ev_count() {
  local h_id="$1"
  local h_ref="$2"
  printf '%s' "$EVIDENCE_JSON" | jq --arg h "$h_id" --arg ref "$h_ref" '
    def refs($name):
      ((try ((.description // "") | capture($name + ":[[:space:]]*\\[(?<ids>[^\\]]*)\\]").ids) catch "")
       | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")));
    [.issues[]? | refs("supports") as $refs | select(($refs | index($h)) or ($refs | index($ref)))] | length
  ' 2>/dev/null || echo 0
}

supporting_source_count() {
  local h_id="$1"
  local h_ref="$2"
  printf '%s' "$EVIDENCE_JSON" | jq --arg h "$h_id" --arg ref "$h_ref" '
    def refs($name):
      ((try ((.description // "") | capture($name + ":[[:space:]]*\\[(?<ids>[^\\]]*)\\]").ids) catch "")
       | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")));
    def field($name):
      (((.description // "") | capture("(^|\\n)" + $name + ":[[:space:]]*(?<x>[^\\n]+)")? | .x) // ""
       | gsub("^[[:space:]]+|[[:space:]]+$"; ""));
    def source_key:
      (field("source_id")) as $source_id |
      (field("source")) as $source |
      (field("source_url")) as $source_url |
      (field("source_path")) as $source_path |
      if ($source_id | length) > 0 then $source_id
      elif ($source | length) > 0 then $source
      elif ($source_url | length) > 0 then $source_url
      elif ($source_path | length) > 0 then $source_path
      else "" end;
    [.issues[]? | refs("supports") as $refs | select(($refs | index($h)) or ($refs | index($ref))) | source_key | select(length > 0)] | unique | length
  ' 2>/dev/null || echo 0
}

check_every_confirmed_has_debate() {
  # For each H with state: confirmed, check it cites a DEBATE-* and has at
  # least two supporting EVs from distinct source URLs/files/sessions.
  local EVIDENCE_JSON
  local support_count source_count
  EVIDENCE_JSON=$(br list --label=evidence --json 2>/dev/null || echo '{"issues":[]}')
  while IFS=$'\t' read -r id public_ref has_debate; do
    [ -n "$id" ] || continue
    public_ref=${public_ref:-$id}
    if [ "$has_debate" != "true" ]; then
      violation every_confirmed_has_debate "$public_ref state=confirmed but no adjudication: DEBATE-* in description"
    fi
    support_count=$(supporting_ev_count "$id" "$public_ref")
    source_count=$(supporting_source_count "$id" "$public_ref")
    if [ "${support_count:-0}" -lt 2 ]; then
      violation every_confirmed_has_debate "$public_ref state=confirmed but has only ${support_count:-0} supporting EV(s); need >=2"
    elif [ "${source_count:-0}" -lt 2 ]; then
      violation every_confirmed_has_debate "$public_ref state=confirmed but supporting EVs cite only ${source_count:-0} independent source(s); need >=2"
    fi
  done < <(br list --label=hypothesis --json 2>/dev/null | \
    jq -r '
      def field_is($name; $value):
        (.description // "") | test("(^|\\n)" + $name + ":[[:space:]]*" + $value + "([[:space:]]|$)");
      def public_ref:
        (.external_ref // "") as $external_ref
        | (try ((.title // "") | capture("^(?<ref>H-[0-9]+):").ref) catch "") as $title_ref
        | if $external_ref != "" then $external_ref
          elif $title_ref != "" then $title_ref
          else .id
          end;
      .issues[]? | select(field_is("state"; "confirmed")) |
      [.id, public_ref, ((.description // "") | test("(^|\\n)adjudication:[[:space:]]*DEBATE-[A-Za-z0-9_-]+"))] | @tsv' 2>/dev/null)
}

check_layout_invariants() {
  if [ -f .brenner_workspace/phase_1_complete.flag ]; then
    [ -f intake/question_of_record.md ] || violation layout_invariants "phase_1_complete but intake/question_of_record.md missing"
    [ -f corpus/corpus_index.md ] || violation layout_invariants "phase_1_complete but corpus/corpus_index.md missing"
  fi
  if [ -f .brenner_workspace/phase_6_complete.flag ]; then
    [ -f distillations/meta_synthesis.md ] || violation layout_invariants "phase_6_complete but distillations/meta_synthesis.md missing"
    [ -f distillations/disagreement_register.md ] || violation layout_invariants "phase_6_complete but distillations/disagreement_register.md missing"
  fi
  if [ -f .brenner_workspace/phase_8_complete.flag ]; then
    [ -f deliverables/RESUME.md ] || violation layout_invariants "phase_8_complete but deliverables/RESUME.md missing"
  fi
  if [ -f .brenner_workspace/phase_9_complete.flag ]; then
    [ -f deliverables/HANDBACK.md ] || violation layout_invariants "phase_9_complete but deliverables/HANDBACK.md missing"
  fi
  if [ -f .brenner_workspace/phase_10_complete.flag ]; then
    [ -f deliverables/DRIFT-CHECK.md ] || violation layout_invariants "phase_10_complete but deliverables/DRIFT-CHECK.md missing"
  fi
}

check_handback_open_thread_tags() {
  if [ ! -f deliverables/HANDBACK.md ]; then
    return
  fi
  # Every unresolved item mentioned in HANDBACK.md under "What's still open"
  # should have next-action:. This intentionally checks the handback section,
  # not raw Beads open status; terminal H states stay bead-open until closeout.
  local missing
  missing=$(awk '/## What.s still open/,/## Recommended next loop/' deliverables/HANDBACK.md | \
    grep -oE '(H-[0-9]+|EV-[0-9]+|AF-[0-9]+|D-[0-9]+)' | sort -u | \
    while read -r ref; do
      grep -q "${ref}.*next.action:" deliverables/HANDBACK.md || echo "$ref"
    done)
  if [ -n "$missing" ]; then
    for r in $missing; do
      violation handback_open_thread_tags "$r in 'What's still open' section but no next-action: tag"
    done
  fi
}

run_check() {
  case "$1" in
    third_alternative_present) check_third_alternative_present ;;
    every_H_has_falsifier) check_every_H_has_falsifier ;;
    every_H_has_expected_evidence) check_every_H_has_expected_evidence ;;
    every_refuted_has_refuted_by) check_every_refuted_has_refuted_by ;;
    every_scale_physics_has_calculation) check_every_scale_physics_has_calculation ;;
    every_confirmed_has_debate) check_every_confirmed_has_debate ;;
    layout_invariants) check_layout_invariants ;;
    handback_open_thread_tags) check_handback_open_thread_tags ;;
    phase3_exit)
      check_third_alternative_present
      check_every_H_has_falsifier
      check_every_H_has_expected_evidence
      ;;
    phase4_round)
      check_every_H_has_falsifier
      check_every_H_has_expected_evidence
      check_every_refuted_has_refuted_by
      check_every_scale_physics_has_calculation
      ;;
    phase7_exit)
      check_every_H_has_falsifier
      check_every_H_has_expected_evidence
      check_every_refuted_has_refuted_by
      check_every_scale_physics_has_calculation
      check_every_confirmed_has_debate
      ;;
    *) echo "unknown check: $1" >&2; exit 2 ;;
  esac
}

if [ "$ALL" = "true" ]; then
  for c in every_H_has_falsifier every_H_has_expected_evidence every_refuted_has_refuted_by \
           every_scale_physics_has_calculation every_confirmed_has_debate \
           layout_invariants third_alternative_present handback_open_thread_tags; do
    run_check "$c"
  done
elif [ -n "$CHECK" ]; then
  run_check "$CHECK"
else
  echo "Usage: audit-bead-invariants.sh [--check=<name> | --all]" >&2
  exit 2
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "Total violations: $VIOLATIONS" >&2
  exit 1
fi
echo "Audit clean."
exit 0
