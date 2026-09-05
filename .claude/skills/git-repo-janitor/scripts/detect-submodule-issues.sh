#!/usr/bin/env bash
# Phase 1: classify submodule states per SUBMODULE-HANDLING.md.
# Usage: detect-submodule-issues.sh <project>
set -euo pipefail

project="${1:?usage: detect-submodule-issues.sh <project>}"
cd "$project"
ws=".repo_janitor_workspace"
mkdir -p "$ws"

# Skip if no submodules
if [[ ! -f .gitmodules ]]; then
    echo "no submodules"
    exit 0
fi

out_warn="$ws/submodule_warnings.tsv"
# `printf` is portable; `echo -e` depends on bash's xpg_echo setting.
printf 'submodule_path\tstatus\trecorded_sha\tcurrent_sha\taction\n' > "$out_warn"

# Snapshot raw outputs
git submodule status > "$ws/submodule_status.txt" 2>&1 || true
git diff --submodule=log > "$ws/submodule_diff_log.txt" 2>&1 || true
git diff --submodule=short > "$ws/submodule_diff_short.txt" 2>&1 || true

# Parse submodule status. Each line is:
#   ` <sha> <path>`        — clean
#   `+<sha> <path>`        — pointer changed
#   `-<sha> <path>`        — not initialized
#   `U<sha> <path>`        — merge conflicts
warning_count=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    prefix=${line:0:1}
    sha=${line:1:40}
    rest=${line:42}
    sub_path=$(echo "$rest" | awk '{print $1}')

    case "$prefix" in
        " ")
            : # clean; skip
            ;;
        "+")
            # Pointer changed — check if rewind or fast-forward
            recorded=$(git ls-tree HEAD "$sub_path" 2>/dev/null | awk '{print $3}')
            current="$sha"

            # Check for -dirty suffix in submodule_diff_short.
            # `grep -c` always prints the count and exits 1 when count is 0;
            # `|| true` suppresses the non-zero exit without producing duplicate output.
            dirty=$(grep -c "${sub_path}.*-dirty" "$ws/submodule_diff_short.txt" 2>/dev/null || true)
            dirty="${dirty:-0}"

            # Check for rewind in submodule_diff_log
            rewind=$(grep -c "Submodule ${sub_path}.*rewind" "$ws/submodule_diff_log.txt" 2>/dev/null || true)
            rewind="${rewind:-0}"

            if [[ "$dirty" -gt 0 ]]; then
                printf '%s\t%s\t%s\t%s\t%s\n' \
                    "$sub_path" "dirty" "$recorded" "${current}-dirty" \
                    "skip; user must clean inside submodule first" >> "$out_warn"
                warning_count=$((warning_count + 1))
            elif [[ "$rewind" -gt 0 ]]; then
                printf '%s\t%s\t%s\t%s\t%s\n' \
                    "$sub_path" "rewind" "$recorded" "$current" \
                    "skip; require user override (would lose commits)" >> "$out_warn"
                warning_count=$((warning_count + 1))
            else
                # Likely fast-forward
                printf '%s\t%s\t%s\t%s\t%s\n' \
                    "$sub_path" "pointer-changed" "$recorded" "$current" \
                    "user can confirm; likely fast-forward" >> "$out_warn"
            fi
            ;;
        "-")
            printf '%s\t%s\t%s\t%s\t%s\n' \
                "$sub_path" "not-initialized" "$sha" "" \
                "skip; submodule not init'd" >> "$out_warn"
            ;;
        "U")
            printf '%s\t%s\t%s\t%s\t%s\n' \
                "$sub_path" "conflicted" "$sha" "" \
                "HALT; resolve conflict first" >> "$out_warn"
            warning_count=$((warning_count + 1))
            ;;
    esac
done < "$ws/submodule_status.txt"

# Check for shallow submodules
shallow=$(git config --get-regexp '^submodule\..*\.shallow$' 2>/dev/null | wc -l)
[[ "$shallow" -gt 0 ]] && echo "INFO: $shallow shallow submodule(s); filter-repo may lose history if used"

# Check protocol.file.allow
allow=$(git config --get protocol.file.allow 2>/dev/null || echo "user")
[[ "$allow" == "never" ]] && echo "WARN: protocol.file.allow=never may block submodule init"

if [[ "$warning_count" -gt 0 ]]; then
    echo ""
    echo "$warning_count submodule(s) require user attention. See $out_warn"
fi
