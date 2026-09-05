#!/usr/bin/env bash
# Bulk-install missing skills via jsm (if available).
# Usage: install-referenced-skills.sh <workspace>
set -euo pipefail

ws="${1:?usage: install-referenced-skills.sh <workspace>}"
inv="$ws/phase0_skill_inventory.json"

[[ -f "$inv" ]] || { echo "no inventory; run check-skills.sh first"; exit 1; }

if ! command -v jsm >/dev/null 2>&1; then
    echo "jsm not available; skipping install"
    exit 0
fi

if ! jsm auth status 2>/dev/null | grep -q "authenticated"; then
    echo "jsm not authenticated; skipping install"
    exit 0
fi

# Install missing skills
python3 - <<PYEOF
import json, subprocess
with open("$inv") as f:
    data = json.load(f)
for skill, available in data.get("skills", {}).items():
    if not available:
        print(f"installing {skill}")
        subprocess.run(["jsm", "install", skill], check=False)
PYEOF
