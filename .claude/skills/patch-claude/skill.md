---
name: patch-claude
description: |
  Patch Claude Code's cli.js to suppress two nag warnings:
  (1) "Auth conflict: Both a token and an API key are set" — for intentional dual-auth/proxy setups.
  (2) "Claude Code has switched from npm to native installer" — when keeping the npm install on purpose.
  Re-run after every Claude Code update.
  Use when user says "patch claude", "patch auth warning", "fix auth conflict",
  "remove native install warning", "suppress npm deprecation", or after updating claude.
allowed-tools:
  - Bash
---

# Patch Claude Code Nag Warnings

Suppresses two startup nags in the Claude Code cli.js:

1. **`both-auth-methods`** — auth conflict warning when both OAuth and `ANTHROPIC_API_KEY` are set (e.g., proxy setups).
2. **`npm-deprecation-warning`** — "Claude Code has switched from npm to native installer" notice shown on each launch for npm installs.

Each patch is idempotent (skipped if already applied) and verified after application. Must be re-run after every Claude Code update since it overwrites cli.js.

## Instructions

1. Find the Claude Code cli.js by resolving `which claude`
2. Apply each patch only if not already present; verify after each
3. Report per-patch status (applied / already-patched / skipped-missing / failed)

Run these commands:

```bash
# Resolve cli.js path from the claude binary location
CLAUDE_BIN=$(readlink -f "$(which claude)" 2>/dev/null || realpath "$(which claude)")
CLI=$(dirname "$CLAUDE_BIN")/../lib/node_modules/@anthropic-ai/claude-code/cli.js

# Fallback: search common nvm location if the above doesn't work
if [ ! -f "$CLI" ]; then
  CLI=$(find ~/.nvm/versions/node -path "*/node_modules/@anthropic-ai/claude-code/cli.js" 2>/dev/null | sort -V | tail -1)
fi

if [ ! -f "$CLI" ]; then
  echo "ERROR: Could not find Claude Code cli.js"
  exit 1
fi

echo "Found cli.js at: $CLI"

# ---- Patch 1: both-auth-methods ----
if grep -q 'isActive:()=>{return false;/\*patched\*/' "$CLI" 2>/dev/null; then
  echo "[auth-conflict] Already patched."
elif ! grep -q '"both-auth-methods"' "$CLI"; then
  echo "[auth-conflict] WARNING: 'both-auth-methods' string not found — Claude Code may have changed its warning structure. Skipping."
else
  sed -i 's/id:"both-auth-methods",type:"warning",isActive:()=>{/id:"both-auth-methods",type:"warning",isActive:()=>{return false;\/*patched*\//' "$CLI"
  if grep -q 'isActive:()=>{return false;/\*patched\*/' "$CLI"; then
    echo "[auth-conflict] Patched successfully."
  else
    echo "[auth-conflict] ERROR: Patch verification failed."
  fi
fi

# ---- Patch 2: npm-deprecation-warning ----
if grep -q 'return null;/\*patched\*/return{timeoutMs:15000,key:"npm-deprecation-warning"' "$CLI" 2>/dev/null; then
  echo "[npm-deprecation] Already patched."
elif ! grep -q 'return{timeoutMs:15000,key:"npm-deprecation-warning"' "$CLI"; then
  echo "[npm-deprecation] WARNING: target pattern not found — Claude Code may have changed its notification structure. Skipping."
else
  sed -i 's|return{timeoutMs:15000,key:"npm-deprecation-warning"|return null;/*patched*/return{timeoutMs:15000,key:"npm-deprecation-warning"|' "$CLI"
  if grep -q 'return null;/\*patched\*/return{timeoutMs:15000,key:"npm-deprecation-warning"' "$CLI"; then
    echo "[npm-deprecation] Patched successfully."
  else
    echo "[npm-deprecation] ERROR: Patch verification failed."
  fi
fi

# Final syntax check
if command -v node >/dev/null 2>&1; then
  if node --check "$CLI" 2>/dev/null; then
    echo "Syntax check: OK"
  else
    echo "Syntax check: FAILED — cli.js may be broken, please restore from a fresh install."
  fi
fi
```

Report the per-patch result to the user.
