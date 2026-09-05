#!/usr/bin/env bash
# Heuristic content classifier: takes a path, outputs purpose label.
# Usage: classify-purpose.sh <path>
set -euo pipefail

path="${1:?usage: classify-purpose.sh <path>}"

if [[ ! -f "$path" ]]; then
    echo "missing"; exit 0
fi

# File magic
ftype=$(file -b "$path" 2>/dev/null || echo "")
case "$ftype" in
    *ELF*) echo "binary-elf"; exit 0 ;;
    *Mach-O*) echo "binary-mach-o"; exit 0 ;;
    *PE32*) echo "binary-pe"; exit 0 ;;
    *SQLite*) echo "sqlite-db"; exit 0 ;;
    *"empty"*) echo "0-byte-stub"; exit 0 ;;
esac

# First few lines for text files
first=$(head -c 4096 "$path" 2>/dev/null || echo "")
case "$first" in
    "#!"*python*) [[ "$path" == *test*.py ]] && echo "test-script" || echo "scratch-script-python"; exit 0 ;;
    "#!"*sh*) echo "scratch-script-shell"; exit 0 ;;
    "#!/usr/bin/env node"*) echo "scratch-script-js"; exit 0 ;;
    "<!DOCTYPE html>"*|"<html"*) echo "html-document"; exit 0 ;;
    "{"*) echo "json-document"; exit 0 ;;
    "---"*) echo "yaml-document"; exit 0 ;;
    "[package]"*|"[dependencies]"*) echo "rust-config"; exit 0 ;;
esac

# Markdown classification
if [[ "$path" == *.md ]] || [[ "$path" == *.markdown ]]; then
    case "$first" in
        "# "*"Skill Loop Progress"*) echo "skill-output"; exit 0 ;;
        "# "*"PLAN"*|"# "*"Plan"*|"# "*"plan"*|"# "*"Architecture"*|"# "*"ARCHITECTURE"*|"# "*"Spec"*|"# "*"SPEC"*) echo "planning-doc"; exit 0 ;;
        "# "*"Progress"*|"# "*"PROGRESS"*|"#"*"bd-"*) echo "progress-report"; exit 0 ;;
        "# "*"Audit"*|"# "*"AUDIT"*|"# "*"Report"*|"# "*"REPORT"*) echo "audit-report"; exit 0 ;;
        "# "*"Runbook"*|"# "*"RUNBOOK"*|"# "*"Recovery"*|"# "*"RECOVERY"*|"# "*"Operations"*) echo "runbook-or-recovery"; exit 0 ;;
        "# "*"Reference"*|"# "*"REFERENCE"*|"# "*"Index"*) echo "reference-doc"; exit 0 ;;
    esac
    echo "markdown-document"; exit 0
fi

case "$first" in
    "From "*"Mon Sep 17 00:00:00 2001"*) echo "format-patch-blob"; exit 0 ;;
esac

# Default
echo "unclassified"
