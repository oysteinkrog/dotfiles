#!/usr/bin/env bash
# Utility: extract the marker-bounded KERNEL section from SKILL.md.
# Useful for embedding the kernel in subagent prompts.
# Usage: extract-kernel.sh [path-to-SKILL.md]
set -euo pipefail

skill_md="${1:-/data/projects/je_private_skills_repo/.claude/skills/git-repo-janitor/SKILL.md}"
[[ -f "$skill_md" ]] || { echo "ERROR: $skill_md not found" >&2; exit 1; }

# Extract between <!-- KERNEL_START vN.N --> and <!-- KERNEL_END vN.N -->
awk '
/<!-- KERNEL_START/ { in_kernel = 1; next }
/<!-- KERNEL_END/ { in_kernel = 0; exit }
in_kernel { print }
' "$skill_md"
