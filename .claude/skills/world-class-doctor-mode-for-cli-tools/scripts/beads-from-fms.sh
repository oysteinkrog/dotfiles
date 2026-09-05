#!/usr/bin/env bash
# beads-from-fms.sh — emit beads for each P0/P1 failure mode from Phase 1.
#
# Phase 1 produces failure_modes/*.md files; Phase 4 implementers need
# beads to track work. This script bridges the two: for each FM file, it
# extracts the FM ID + severity + title, then calls `br create` (idempotent
# — skips already-created beads). After creating individual beads, reads
# dependency_graph.json and adds br dep edges.
#
# Usage: beads-from-fms.sh <workspace>
#
# Inputs:
#   <workspace>/analysis/failure_modes/*.md  (one or more)
#   <workspace>/analysis/dependency_graph.json (optional; emitted by Phase 3)
#
# Output: stderr summary; exit 0 if all beads created or already existed.
# Exit 64 usage; 66 missing inputs.

set -euo pipefail

usage() {
    echo "usage: beads-from-fms.sh <workspace>" >&2
}

workspace="${1:-}"
[ -n "$workspace" ] || { usage; exit 64; }
[ -d "$workspace" ] || { echo "beads-from-fms: $workspace not a directory" >&2; exit 66; }

fm_dir="$workspace/analysis/failure_modes"
[ -d "$fm_dir" ] || { echo "beads-from-fms: no failure_modes/ in workspace" >&2; exit 66; }

if ! command -v br >/dev/null 2>&1; then
    echo "beads-from-fms: br not installed; nothing to do" >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "beads-from-fms: jq not installed; cannot safely perform idempotent br lookups" >&2
    exit 1
fi

# Extract metadata from each FM file. Per assets/failure-mode-template.md and
# validate-fm.py, each FM is a `# FM-fm-...` block containing `id:`,
# `title:`, and `severity:` fields. Older draft outputs used `## fm-...`
# plus `**severity**:`; accept that shape too so existing workspaces remain
# readable while the canonical template drives new output.

created=0
existed=0
skipped=0

extract_fms() {
    # Outputs: tab-separated fm_id<TAB>severity<TAB>title (one per FM).
    local file="$1"
    awk '
        function emit_current() {
            if (id != "" && sev != "") {
                if (title == "") title = id
                printf "%s\t%s\t%s\n", id, sev, title
            }
        }
        /^# FM-fm-/ {
            emit_current()
            id = ""
            title = ""
            sev = ""
            next
        }
        /^## fm-/ {
            emit_current()
            id = substr($2, 1)
            title = ""
            for (i = 3; i <= NF; i++) title = title (i==3 ? "" : " ") $i
            sev = ""
            getline_severity = 1
            next
        }
        /^id:[[:space:]]*fm-/ {
            sub(/^id:[[:space:]]*/, "")
            id = $0
            next
        }
        /^title:[[:space:]]*/ {
            sub(/^title:[[:space:]]*/, "")
            title = $0
            next
        }
        /^severity:[[:space:]]*P[0-9]/ {
            sub(/^severity:[[:space:]]*/, "")
            sev = $0
            sub(/[ \t].*$/, "", sev)
            next
        }
        /^\*\*severity\*\*: *P[0-9]/ && getline_severity {
            sub(/.*severity[*]*: */, "")
            sev = $0
            sub(/[ \t].*$/, "", sev)
            getline_severity = 0
            next
        }
        END {
            emit_current()
        }
    ' "$file"
}

for f in "$fm_dir"/*.md; do
    [ -f "$f" ] || continue
    while IFS=$'\t' read -r fm_id severity title; do
        [ -z "$fm_id" ] && continue
        # Convert P-style severity to br's numeric priority (P0=0..P3=3).
        priority=${severity#P}
        [ -z "$priority" ] && priority=2

        # Idempotency: skip if a bead with this title already exists.
        # br doesn't have a stable ID-by-title query, so we list and grep.
        if br list --json 2>/dev/null \
            | jq -e --arg t "[$fm_id]" 'if type=="object" then (.issues // []) else . end | .[]? | select((.title // "") | startswith($t))' \
            >/dev/null 2>&1; then
            existed=$((existed + 1))
            continue
        fi

        # Only file P0/P1 by default; lower-priority FMs are queued
        # but not pre-claimed.
        if [ "$priority" -gt 1 ]; then
            skipped=$((skipped + 1))
            continue
        fi

        # Create the bead. Body is the path to the FM source file —
        # implementers can read the full spec there.
        if br create \
            --title "[$fm_id] $title" \
            --priority "$priority" \
            --type bug \
            --body "Source: $f
Severity: $severity
Subsystem: $(basename "$f" .md)

See the FM file for detector pseudocode, fixer pseudocode, preconditions,
backup spec, inverse, idempotence proof, and fixture spec." \
            >/dev/null 2>&1; then
            created=$((created + 1))
            echo "  created: [$fm_id]" >&2
        else
            echo "  failed: [$fm_id]" >&2
        fi
    done < <(extract_fms "$f")
done

# Add dependency edges from dependency_graph.json if present.
dep_graph="$workspace/analysis/dependency_graph.json"
edges_added=0
if [ -f "$dep_graph" ]; then
    while IFS=$'\t' read -r from_fm to_fm; do
        [ -z "$from_fm" ] && continue
        # Edge convention: from_fm must precede to_fm, so the dependent bead
        # is to_fm and its dependency is from_fm (`br dep add issue depends-on`).
        # `|| true` defends against SIGPIPE-141: if multiple beads share the
        # same `[fm-id]` title prefix (rare but possible if a previous run
        # was interrupted mid-creation), jq emits >1 matching id, head -1
        # closes after the first, jq's next write SIGPIPEs, pipefail+set-e
        # aborts the loop. Without the fallback we silently lose all
        # remaining edges.
        prerequisite_bead=$(br list --json 2>/dev/null \
            | jq -r --arg t "[$from_fm]" 'if type=="object" then (.issues // []) else . end | .[]? | select((.title // "") | startswith($t)) | .id' \
            | head -1 || true)
        dependent_bead=$(br list --json 2>/dev/null \
            | jq -r --arg t "[$to_fm]" 'if type=="object" then (.issues // []) else . end | .[]? | select((.title // "") | startswith($t)) | .id' \
            | head -1 || true)
        if [ -n "$prerequisite_bead" ] && [ -n "$dependent_bead" ]; then
            br dep add "$dependent_bead" "$prerequisite_bead" >/dev/null 2>&1 \
                && edges_added=$((edges_added + 1))
        fi
    done < <(jq -r '.edges[] | "\(.from)\t\(.to)"' "$dep_graph" 2>/dev/null || true)
fi

echo "beads-from-fms: created=$created existed=$existed skipped=$skipped (P2/P3 not auto-filed)" >&2
[ "$edges_added" -gt 0 ] && echo "beads-from-fms: added $edges_added dependency edges" >&2
exit 0
