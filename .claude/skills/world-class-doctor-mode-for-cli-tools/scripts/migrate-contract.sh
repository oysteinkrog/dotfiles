#!/usr/bin/env bash
set -euo pipefail
# migrate-contract.sh — apply contract-version migrations across the skill.
#
# When the doctor contract is bumped (e.g., 1.0 → 2.0 with a renamed flag,
# repurposed exit code, or added required field), the skill's docs and
# templates must be updated in lock-step. This script reads a migration
# registry (references/methodology/CONTRACT-MIGRATIONS.md) and applies
# documented mechanical changes for the named version transition.
#
# Usage:
#   migrate-contract.sh --from <semver> --to <semver> [--dry-run] [--target-dir DIR]
#
# Args:
#   --from / --to    semver versions; --to MUST be > --from
#   --dry-run        print what would change; don't write
#   --target-dir     directory to apply migrations to (default: skill root)
#
# Migration registry format (markdown — see CONTRACT-MIGRATIONS.md):
#   ## 1.0 → 2.0
#   - rename: <old>=<new>  (applied to *.md, *.json, *.sh, and *.py)
#   - rename-flag: --old=<--new>
#   - rename-exit-code: <code>:<old_name>=<new_name>
#   - field-required-add: <schema>.<field>:<default>  (informational; agent must hand-add)
#
# Direct transitions only. To migrate 1.0 → 3.0, run 1.0 → 2.0 and then
# 2.0 → 3.0 explicitly. Passing --acknowledge-skipped records a deliberate
# no-op only when no direct transition section exists.
#
# Exit: 0 success, 64 usage, 66 missing migration registry, 1 if any
# transition has unapplied migrations.

usage() {
    echo "usage: migrate-contract.sh --from <semver> --to <semver> [--dry-run] [--target-dir DIR] [--acknowledge-skipped]" >&2
}

from_version=""
to_version=""
dry_run=0
target_dir="$(cd "$(dirname "$0")/.." && pwd)"
acknowledge_skipped=0
need_value() {
    [ -n "${2:-}" ] || { echo "migrate-contract: $1 requires a value" >&2; usage; exit 64; }
    case "$2" in --*) echo "migrate-contract: $1 requires a value, got option-like token: $2" >&2; usage; exit 64 ;; esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --from) need_value "$1" "${2:-}"; from_version="$2"; shift 2 ;;
        --to)   need_value "$1" "${2:-}"; to_version="$2"; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        --target-dir) need_value "$1" "${2:-}"; target_dir="$2"; shift 2 ;;
        --acknowledge-skipped) acknowledge_skipped=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "migrate-contract: unknown arg $1" >&2; usage; exit 64 ;;
    esac
done

if [ -z "$from_version" ] || [ -z "$to_version" ]; then
    usage; exit 64
fi
[ -d "$target_dir" ] || { echo "migrate-contract: $target_dir not a directory" >&2; exit 66; }

registry="$target_dir/references/methodology/CONTRACT-MIGRATIONS.md"
if [ ! -f "$registry" ]; then
    echo "migrate-contract: no registry at $registry" >&2
    echo "  create it with one section per major-version transition (see template in script)" >&2
    exit 66
fi

# Parse the registry: extract sections of the form "## <from> → <to>".
# Each section's lines starting with "- rename: ..." or "- rename-flag: ..."
# define the migrations.
extract_section() {
    local from="$1"
    local to="$2"
    awk -v from="$from" -v to="$to" '
        BEGIN { in_section = 0; in_fence = 0 }
        /^## / {
            line = $0
            sub(/^## /, "", line)
            # Match "<from> → <to>" or "<from> -> <to>" or "<from> →  <to>".
            if (line ~ "^"from" *(→|->) *"to"$") { in_section = 1; in_fence = 0; next }
            if (in_section) { in_section = 0; in_fence = 0 }
        }
        in_section && /^```/ { in_fence = !in_fence; next }
        in_section && in_fence { next }
        in_section { print }
    ' "$registry"
}

# Build the ordered list of transitions to apply.
# For now: support a single direct transition (from → to). Sequential application
# of intermediate transitions is documented as future work.
section_lines=$(extract_section "$from_version" "$to_version")
if [ -z "$section_lines" ]; then
    echo "migrate-contract: no migration found for $from_version → $to_version in $registry" >&2
    if [ "$acknowledge_skipped" -ne 1 ]; then
        echo "  if you want to apply intermediate transitions, name them explicitly with --from/--to" >&2
        echo "  or pass --acknowledge-skipped to proceed with no-op (records the version bump only)" >&2
        exit 1
    fi
    echo "migrate-contract: --acknowledge-skipped set; recording version bump $from_version → $to_version (no mechanical changes)" >&2
    exit 0
fi

apply_rename() {
    local old="$1"
    local new="$2"
    local count=0
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        # Skip the registry itself + CHANGELOG (history must remain accurate).
        case "$f" in
            "$registry"|*/CHANGELOG.md) continue ;;
        esac
        # Use `grep -F` (fixed-string mode) — `$old` is a literal token to
        # rename, NOT a regex. Without -F, characters like `.`, `[`, `*` in
        # the old token would be interpreted as regex metacharacters: grep
        # would falsely match files that don't actually contain the literal,
        # and Python's .replace (which IS literal) would do nothing on those
        # files, producing a "renamed in $f" log line that's a lie.
        if grep -Fq -- "$old" "$f" 2>/dev/null; then
            if [ "$dry_run" -eq 1 ]; then
                echo "  [dry-run] would rename '$old' → '$new' in $f"
            else
                # Use python for safe replacement (sed -i has macOS/GNU portability issues).
                python3 -c "
import sys
p = sys.argv[1]; old = sys.argv[2]; new = sys.argv[3]
with open(p, 'r', encoding='utf-8') as fh: content = fh.read()
content = content.replace(old, new)
with open(p, 'w', encoding='utf-8') as fh: fh.write(content)
" "$f" "$old" "$new"
                echo "  renamed '$old' → '$new' in $f"
            fi
            count=$((count + 1))
        fi
    done < <(find "$target_dir" -type f \( -name '*.md' -o -name '*.json' -o -name '*.sh' -o -name '*.py' \) ! -path '*/.git/*' ! -path '*/target/*' ! -path '*/node_modules/*')
    echo "rename '$old' → '$new': touched $count file(s)" >&2
}

unknown_count=0
while IFS= read -r migration_line; do
    # Strip leading dash + whitespace.
    line="${migration_line#- }"
    line="${line## }"
    case "$line" in
        rename:*|rename-flag:*|rename-exit-code:*|field-required-add:*|''|---|_*) ;;
        *)
            echo "  unrecognized migration directive: $line" >&2
            unknown_count=$((unknown_count + 1))
            ;;
    esac
done <<< "$section_lines"

if [ "$unknown_count" -gt 0 ]; then
    echo "migrate-contract: refused $unknown_count unrecognized directive(s)" >&2
    exit 1
fi

echo "migrate-contract: applying $from_version → $to_version migrations" >&2
[ "$dry_run" -eq 1 ] && echo "(dry run)" >&2

while IFS= read -r migration_line; do
    # Strip leading dash + whitespace.
    line="${migration_line#- }"
    line="${line## }"
    case "$line" in
        rename:*)
            spec="${line#rename:}"
            spec="${spec## }"
            old="${spec%%=*}"
            new="${spec#*=}"
            apply_rename "$old" "$new"
            ;;
        rename-flag:*)
            spec="${line#rename-flag:}"
            spec="${spec## }"
            old="${spec%%=*}"
            new="${spec#*=}"
            apply_rename "$old" "$new"
            ;;
        rename-exit-code:*)
            spec="${line#rename-exit-code:}"
            spec="${spec## }"
            # Format: <code>:<old_name>=<new_name>
            code="${spec%%:*}"
            rest="${spec#*:}"
            old_name="${rest%%=*}"
            new_name="${rest#*=}"
            apply_rename "\"$code\": \"$old_name\"" "\"$code\": \"$new_name\""
            ;;
        field-required-add:*)
            spec="${line#field-required-add:}"
            echo "  INFORMATIONAL: field-required-add '$spec' — must be hand-added to schemas + report-template.json + per-recipe examples; mechanical migration not provided" >&2
            ;;
        ''|---) ;;  # blank line / markdown separator
        _*) ;;  # prose note, not a directive
    esac
done <<< "$section_lines"

echo "migrate-contract: done" >&2
exit 0
