---
name: patch-claude-auth
description: |
  Suppress the "Auth conflict: Both a token and an API key are set" warning
  in Claude Code. Re-run after every Claude Code update.
  Use when user says "patch auth warning", "fix auth conflict", or after updating claude.
allowed-tools:
  - Bash
---

# Patch Claude Code Auth Conflict Warning

Suppress the "both-auth-methods" auth conflict warning in Claude Code's cli.js.
This is needed when intentionally using both OAuth and ANTHROPIC_API_KEY (e.g., proxy setups).

## Instructions

1. Find the Claude Code cli.js using `which claude` to resolve the installation path
2. Verify the file contains the `"both-auth-methods"` warning string
3. Patch the `isActive` function for that warning to return `false` immediately
4. Verify the patch was applied

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

# Check if already patched
if grep -q 'isActive:()=>{return false;/\*patched\*/' "$CLI" 2>/dev/null; then
  echo "Already patched — nothing to do."
  exit 0
fi

# Check the warning exists
if ! grep -q '"both-auth-methods"' "$CLI"; then
  echo "WARNING: 'both-auth-methods' string not found — Claude Code may have changed its warning structure."
  exit 1
fi

# Apply patch: inject `return false;/*patched*/` at the start of isActive
sed -i 's/id:"both-auth-methods",type:"warning",isActive:()=>{/id:"both-auth-methods",type:"warning",isActive:()=>{return false;\/*patched*\//' "$CLI"

# Verify
if grep -q 'isActive:()=>{return false;/\*patched\*/' "$CLI"; then
  echo "Patched successfully."
else
  echo "ERROR: Patch verification failed."
  exit 1
fi
```

Report the result to the user.
