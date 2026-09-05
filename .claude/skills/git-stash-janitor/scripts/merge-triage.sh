#!/usr/bin/env bash
# merge-triage.sh — Merge per-batch triage tsvs into the canonical triage.tsv;
# emit triage_decision.md for the user.
#
# Reads <workspace>/triage/batch_*.tsv
# Writes <workspace>/triage.tsv and <workspace>/triage_decision.md

set -euo pipefail

PROJECT="${1:?Usage: merge-triage.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
TRIAGE_DIR="$WORKSPACE/triage"
INVENTORY="$WORKSPACE/inventory.tsv"

if [[ ! -d "$TRIAGE_DIR" ]]; then
  echo "ERROR: $TRIAGE_DIR does not exist (run triage workers first)" >&2
  exit 1
fi

# Merge: header from first batch + rows from all batches; sort by n
TRIAGE_TSV="$WORKSPACE/triage.tsv"
batch_files=( "$TRIAGE_DIR"/batch_*.tsv )
if [[ ${#batch_files[@]} -eq 0 || ! -f "${batch_files[0]}" ]]; then
  echo "ERROR: no batch tsv files in $TRIAGE_DIR" >&2
  exit 1
fi

head -1 "${batch_files[0]}" > "$TRIAGE_TSV"
for f in "${batch_files[@]}"; do
  awk 'NR > 1' "$f" >> "$TRIAGE_TSV"
done

# Sort by n (numeric, ascending), keep header
{
  head -1 "$TRIAGE_TSV"
  awk 'NR > 1' "$TRIAGE_TSV" | sort -t $'\t' -k1,1n
} > "$TRIAGE_TSV.sorted"
mv "$TRIAGE_TSV.sorted" "$TRIAGE_TSV"

# Sanity check: row count should match inventory
inv_rows=$(awk 'NR > 1' "$INVENTORY" | wc -l)
tri_rows=$(awk 'NR > 1' "$TRIAGE_TSV" | wc -l)
if [[ "$inv_rows" != "$tri_rows" ]]; then
  echo "WARNING: triage rows ($tri_rows) != inventory rows ($inv_rows)" >&2
  echo "  Some stashes may not have been triaged." >&2
fi

# --- Build triage_decision.md ---
DECISION_MD="$WORKSPACE/triage_decision.md"

# Get message + verdict counts
verdict_count() {
  awk -F'\t' -v v="$1" 'NR > 1 && $2 == v' "$TRIAGE_TSV" | wc -l
}

# Helper: enrich with stash message from inventory.
# Markdown tables use `|` as the column delimiter, so any `|` in a cell value
# (stash messages and evidence strings can legitimately contain pipes) breaks
# the rendered table — the user sees mis-aligned columns and missing data.
# Escape every interpolated string column with `\|`.
join_with_message() {
  awk -F'\t' -v inv="$INVENTORY" -v target_v="$1" '
    function md_escape(s) {
      gsub(/\|/, "\\|", s)
      # Backticks would close inline-code spans if a cell value embedded one;
      # neutralize them so the table cell renders as text.
      gsub(/`/, "\\`", s)
      return s
    }
    BEGIN {
      while ((getline line < inv) > 0) {
        n = split(line, f, "\t")
        if (f[1] == "n") continue   # header
        msg[f[1]] = f[7]
      }
      close(inv)
    }
    NR > 1 && $2 == target_v {
      printf "| %s | %s | %s | %s | %s |\n", \
        $1, md_escape(msg[$1]), $3, md_escape($4), md_escape($5)
    }
  ' "$TRIAGE_TSV"
}

n_novel=$(verdict_count novel-and-accretive)
n_partial=$(verdict_count partially-novel)
n_super=$(verdict_count superseded)
n_garbage=$(verdict_count garbage)
n_stale=$(verdict_count novel-but-stale)
n_unknown=$(verdict_count unknown)
n_super_newer=$(verdict_count superseded-by-newer-stash)

{
  printf '# Triage decision\n\n'
  printf '%s stashes triaged. Review below; reply with "go" to proceed (or override per-row).\n\n' "$tri_rows"

  printf '## Verdict counts\n\n'
  printf '| verdict | count | proposed action |\n'
  printf '|---------|-------|----------------|\n'
  printf '| novel-and-accretive | %s | apply on stash-recovery branch |\n' "$n_novel"
  printf '| partially-novel | %s | split-apply (novel hunks only) |\n' "$n_partial"
  printf '| superseded | %s | drop after Phase 9 authorization |\n' "$n_super"
  printf '| superseded-by-newer-stash | %s | drop after Phase 9 authorization |\n' "$n_super_newer"
  printf '| garbage | %s | drop after Phase 9 authorization |\n' "$n_garbage"
  printf '| novel-but-stale | %s | manual decision (default: drop with note) |\n' "$n_stale"
  printf '| unknown | %s | **surface to user** (must resolve before Phase 6) |\n' "$n_unknown"
  printf '\n'

  if [[ "$n_unknown" -gt 0 ]]; then
    printf '## ⚠ MANUAL — unknown (%s) — needs user verdict\n\n' "$n_unknown"
    printf '| n | message | conf | evidence | apply_check |\n'
    printf '|---|---------|------|----------|-------------|\n'
    join_with_message unknown
    printf '\n'
  fi

  if [[ "$n_novel" -gt 0 ]]; then
    printf '## ✓ KEEP — novel-and-accretive (%s)\n\n' "$n_novel"
    printf '| n | message | conf | evidence | apply_check |\n'
    printf '|---|---------|------|----------|-------------|\n'
    join_with_message novel-and-accretive
    printf '\n'
  fi

  if [[ "$n_partial" -gt 0 ]]; then
    printf '## ✂ KEEP-WITH-SPLIT — partially-novel (%s)\n\n' "$n_partial"
    printf '| n | message | conf | evidence | apply_check |\n'
    printf '|---|---------|------|----------|-------------|\n'
    join_with_message partially-novel
    printf '\n'
  fi

  if [[ "$n_stale" -gt 0 ]]; then
    printf '## ? MANUAL — novel-but-stale (%s)\n\n' "$n_stale"
    printf '| n | message | conf | evidence | apply_check |\n'
    printf '|---|---------|------|----------|-------------|\n'
    join_with_message novel-but-stale
    printf '\n'
  fi

  printf '## 🗑 DROP — superseded (%s)\n\n' "$n_super"
  if [[ "$n_super" -gt 30 ]]; then
    printf '<details><summary>Click to expand %s rows</summary>\n\n' "$n_super"
  fi
  printf '| n | message | conf | evidence | apply_check |\n'
  printf '|---|---------|------|----------|-------------|\n'
  join_with_message superseded
  if [[ "$n_super" -gt 30 ]]; then
    printf '\n</details>\n'
  fi
  printf '\n'

  if [[ "$n_super_newer" -gt 0 ]]; then
    printf '## 🗑 DROP — superseded-by-newer-stash (%s)\n\n' "$n_super_newer"
    if [[ "$n_super_newer" -gt 30 ]]; then printf '<details><summary>Click to expand %s rows</summary>\n\n' "$n_super_newer"; fi
    # 5-column header to match join_with_message's output
    printf '| n | message | conf | evidence | apply_check |\n'
    printf '|---|---------|------|----------|-------------|\n'
    join_with_message superseded-by-newer-stash
    if [[ "$n_super_newer" -gt 30 ]]; then printf '\n</details>\n'; fi
    printf '\n'
  fi

  if [[ "$n_garbage" -gt 0 ]]; then
    printf '## 🗑 DROP — garbage (%s)\n\n' "$n_garbage"
    if [[ "$n_garbage" -gt 30 ]]; then printf '<details><summary>Click to expand %s rows</summary>\n\n' "$n_garbage"; fi
    # 5-column header to match join_with_message's output
    printf '| n | message | conf | evidence | apply_check |\n'
    printf '|---|---------|------|----------|-------------|\n'
    join_with_message garbage
    if [[ "$n_garbage" -gt 30 ]]; then printf '\n</details>\n'; fi
    printf '\n'
  fi

  printf '## Next step\n\n'
  printf 'Reply with one of:\n'
  # Single-quoted format strings are intentional (markdown literal backticks).
  # shellcheck disable=SC2016
  printf -- '- `go` — proceed to Phase 6 with the verdicts above\n'
  # shellcheck disable=SC2016
  printf -- '- `keep stash@{N} too` (per-row override) — change verdict to novel-and-accretive\n'
  # shellcheck disable=SC2016
  printf -- '- `drop stash@{N}` (per-row override) — change verdict to garbage\n'
  # shellcheck disable=SC2016
  printf -- '- `wait` / `stop` — abort the run; bundle and refs remain intact\n'
} > "$DECISION_MD"

echo "wrote $TRIAGE_TSV ($tri_rows rows)"
echo "wrote $DECISION_MD"
echo
echo "Verdict counts:"
awk -F'\t' 'NR > 1 {counts[$2]++} END {for (v in counts) printf "  %-30s %s\n", v, counts[v]}' "$TRIAGE_TSV"
