#!/usr/bin/env bash
# gather-evidence.sh — Phase 3: locate code/tests/CI/docs that allegedly fulfill
# one bead's spec. Read-only against the project.
#
# Usage:
#   gather-evidence.sh <project-path> <pass-dir>/beads/<bead-id>
#
# Reads spec.json. For each checklist item, writes a record into evidence.json
# with status FOUND | MISSING | AMBIGUOUS and citations (path:line:commit).
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path}"
BEAD_DIR="${2:?bead dir}"
SPEC="$BEAD_DIR/spec.json"
OUT="$BEAD_DIR/evidence.json"
ID="$(basename "$BEAD_DIR")"

# Strip any trailing slash so prefix-strip in resolve_path_hint works correctly.
PROJECT="${PROJECT%/}"

[ -f "$SPEC" ] || { echo "no spec.json" >&2; exit 2; }
if ! jq -e 'type == "object" and (.checklist | type == "object")' "$SPEC" >/dev/null 2>&1; then
  echo "invalid spec.json: expected a JSON object with checklist object" >&2
  exit 2
fi

# Initial empty envelope
jq -n --arg id "$ID" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{bead_id: $id, gathered_at: $now, gatherer: "scripts/gather-evidence.sh", checks: []}' \
  > "$OUT"

# Pre-compute commits that mention the bead.
COMMITS=""
if [ -d "$PROJECT/.git" ]; then
  # `-F` (--fixed-strings) so regex meta-chars in $ID (`.`, `+`, `[`, etc.,
  # which appear in child-bead IDs like `bd-foo.1`) are not interpreted as a
  # regex — otherwise we'd silently grab commits referencing wrong IDs.
  COMMITS="$(git -C "$PROJECT" log --all -F --grep="$ID" --format='%H' 2>/dev/null || true)"
fi

# Files touched by those commits (deduped).
TOUCHED_FILES=""
if [ -n "$COMMITS" ]; then
  TOUCHED_FILES="$(printf '%s\n' "$COMMITS" \
    | xargs -I{} git -C "$PROJECT" show --pretty=format: --name-only {} 2>/dev/null \
    | grep -v '^$' | sort -u || true)"
fi

# Helper: emit a check record through a tmp file so failed jq output never
# corrupts evidence.json. Per repo no-deletion policy, a failed write leaves the
# tmp artifact available for diagnosis; a successful mv consumes it.
emit_check() {
  local item_id="$1" status="$2" notes="$3" citations_json="$4"
  local tmp
  tmp="$(mktemp)"
  jq --arg item "$item_id" --arg status "$status" --arg notes "$notes" \
     --argjson cites "$citations_json" \
     '.checks += [{spec_item_id: $item, status: $status, citations: $cites, notes: $notes}]' \
     "$OUT" > "$tmp"
  mv "$tmp" "$OUT"
}

# Resolve a path hint in the project. Returns the first matching file or empty.
resolve_path_hint() {
  local hint="$1"
  case "$hint" in
    ""|/*|..|../*|*/../*|*/..)
      printf ''
      return
      ;;
  esac
  # Exact path?
  if [ -e "$PROJECT/$hint" ]; then
    printf '%s' "$hint"
    return
  fi
  # Path within touched files?
  if [ -n "$TOUCHED_FILES" ]; then
    while IFS= read -r f; do
      case "$f" in *"$hint"*) printf '%s' "$f"; return ;; esac
    done <<< "$TOUCHED_FILES"
  fi
  # Last resort: ripgrep for the basename. The basename can contain regex
  # meta-chars (`.`, `+`, `[`, etc.) — e.g., `feature.flag.ts` — which would
  # otherwise let `feature_flag_ts` match too. Escape them before composing
  # the suffix-anchored pattern.
  local base
  base="$(basename "$hint")"
  local base_esc
  # shellcheck disable=SC2016 # This is a sed regex, not a shell expression.
  base_esc="$(printf '%s' "$base" | sed 's/[][\\.*^$(){}|+?]/\\&/g')"
  local found
  found="$(rg --files "$PROJECT" 2>/dev/null | rg --no-heading "/${base_esc}\$" | head -1 || true)"
  if [ -n "$found" ]; then
    printf '%s' "${found#"$PROJECT"/}"
    return
  fi
  printf ''
}

# Walk code_artifacts
while IFS= read -r item; do
  ITEM_ID="$(printf '%s' "$item" | jq -r '.id')"
  HINTS="$(printf '%s' "$item" | jq -r '.expected_path_hints[]?' 2>/dev/null || true)"
  CITATIONS="[]"
  STATUS="MISSING"
  NOTES=""
  while IFS= read -r hint; do
    [ -n "$hint" ] || continue
    resolved="$(resolve_path_hint "$hint")"
    if [ -n "$resolved" ]; then
      # Find the commit that last modified it
      COMMIT="$(git -C "$PROJECT" log -n1 --format=%H -- "$resolved" 2>/dev/null || echo unknown)"
      # `wc -l < <directory>` errors out and the failure can leave LINES
      # empty, which then makes `--argjson e "$LINES"` raise
      # `jq: invalid JSON text passed to --argjson` and `set -e` kills the
      # script. Detect file vs directory explicitly and zero LINES for any
      # non-file (directory citations are common when a bead names a path
      # like `src/indexer/` rather than a single file). A final defense
      # against any remaining edge case: coerce empty/non-numeric to 0.
      if [ -f "$PROJECT/$resolved" ]; then
        LINES="$(wc -l < "$PROJECT/$resolved" 2>/dev/null || echo 0)"
      else
        LINES=0
      fi
      [[ "$LINES" =~ ^[0-9]+$ ]] || LINES=0
      CITATIONS="$(printf '%s' "$CITATIONS" | jq --arg p "$resolved" --arg c "$COMMIT" --argjson e "$LINES" \
        '. + [{path: $p, line_start: 1, line_end: $e, commit_sha: $c, via: "expected_path_hints"}]')"
      STATUS="FOUND"
    fi
  done <<< "$HINTS"
  if [ "$STATUS" = "MISSING" ]; then
    NOTES="No file matched any of: $HINTS"
  fi
  emit_check "$ITEM_ID" "$STATUS" "$NOTES" "$CITATIONS"
done < <(jq -c '.checklist.code_artifacts[]?' "$SPEC")

# Walk tests (each type)
for ttype in unit integration e2e fuzz property metamorphic golden conformance; do
  while IFS= read -r item; do
    ITEM_ID="$(printf '%s' "$item" | jq -r '.id')"
    DESC="$(printf '%s' "$item" | jq -r '.description // ""')"
    CITATIONS="[]"
    STATUS="MISSING"
    # Heuristic: search for the test name (id) in the project
    NAME="$(printf '%s' "$ITEM_ID" | sed 's/.*\.//')"
    if [ -n "$NAME" ] && [ "$NAME" != "primary" ]; then
      MATCHES="$(rg -F -l --no-heading -- "$NAME" "$PROJECT" 2>/dev/null | head -3 || true)"
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        rel="${f#"$PROJECT"/}"
        CITATIONS="$(printf '%s' "$CITATIONS" | jq --arg p "$rel" \
          '. + [{path: $p, line_start: 1, line_end: 1, commit_sha: "unknown", via: "rg test name"}]')"
        STATUS="FOUND"
      done <<< "$MATCHES"
    fi
    emit_check "$ITEM_ID" "$STATUS" "type=$ttype desc=$DESC" "$CITATIONS"
  done < <(jq -c --arg ttype "$ttype" '.checklist.tests[$ttype][]?' "$SPEC")
done

# Walk documentation / migrations / feature_flags / telemetry / ci_workflows
for cat in documentation migrations feature_flags telemetry ci_workflows; do
  while IFS= read -r item; do
    ITEM_ID="$(printf '%s' "$item" | jq -r '.id')"
    CITATIONS="[]"
    STATUS="MISSING"
    case "$cat" in
      documentation)
        if [ -f "$PROJECT/README.md" ]; then
          STATUS="FOUND"
          CITATIONS='[{"path":"README.md","line_start":1,"line_end":1,"via":"file existence"}]'
        fi ;;
      ci_workflows)
        if [ -d "$PROJECT/.github/workflows" ]; then
          STATUS="FOUND"
          CITATIONS='[{"path":".github/workflows/","line_start":1,"line_end":1,"via":"directory existence"}]'
        fi ;;
    esac
    emit_check "$ITEM_ID" "$STATUS" "category=$cat" "$CITATIONS"
  done < <(jq -c --arg cat "$cat" '.checklist[$cat][]?' "$SPEC")
done

# Print summary to stderr
jq -r '"evidence.json: " + (.checks | length | tostring) + " checks; " +
  ([.checks[] | select(.status == "FOUND")] | length | tostring) + " FOUND, " +
  ([.checks[] | select(.status == "MISSING")] | length | tostring) + " MISSING"' "$OUT" >&2
