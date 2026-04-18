---
name: patch-claude
description: |
  Patch Claude Code's native binary to suppress two nag warnings:
  (1) "Auth conflict: Both a token and an API key are set" — for intentional dual-auth/proxy setups.
  (2) "Claude Code has switched from npm to native installer" — when keeping the npm install on purpose.
  Re-run after every Claude Code update (npm install or native).
  Use when user says "patch claude", "patch auth warning", "fix auth conflict",
  "remove native install warning", "suppress npm deprecation", or after updating claude.
allowed-tools:
  - Bash
---

# Patch Claude Code Nag Warnings

Suppresses two startup nags by binary-patching the Claude Code executable:

1. **`both-auth-methods`** — auth conflict warning when both OAuth and `ANTHROPIC_API_KEY` are set.
2. **`npm-deprecation-warning`** — "Claude Code has switched from npm to native installer" notice.

Both patches are same-length binary replacements (preserves file size/integrity). Idempotent — safe to re-run.
Must be re-run after every Claude Code update.

## Instructions

Run this Python script via Bash:

```bash
python3 << 'PYEOF'
import sys

# Resolve the binary path from `which claude`
import subprocess, os
result = subprocess.run(['which', 'claude'], capture_output=True, text=True)
claude_bin = result.stdout.strip()
if not claude_bin:
    print("ERROR: 'claude' not in PATH")
    sys.exit(1)

# Follow symlinks
cli = os.path.realpath(claude_bin)
print(f"Found binary at: {cli}")

with open(cli, 'rb') as f:
    data = bytearray(f.read())

changed = False

# === Patch 1: both-auth-methods isActive — make it always return false ===
old1 = b'isActive:()=>{let{source:H}=rz({skipRetrievingKeyFromApiKeyHelper:!0}),$=sh();return H!=="none"&&$.source!=="none"&&!(H==="apiKeyHelper"&&$.source==="apiKeyHelper")}'
new1_core = b'isActive:()=>{return!1'
new1 = new1_core + b' ' * (len(old1) - len(new1_core) - 1) + b'}'
assert len(new1) == len(old1)

# Check if already patched
if data.count(b'isActive:()=>{return!1') >= 1 and data.count(old1) == 0:
    print("[auth-conflict] Already patched.")
elif data.count(old1) == 0:
    print("[auth-conflict] WARNING: pattern not found — binary may have changed. Skipping.")
else:
    n = 0
    idx = 0
    while True:
        pos = data.find(old1, idx)
        if pos == -1:
            break
        data[pos:pos+len(old1)] = new1
        idx = pos + len(new1)
        n += 1
    print(f"[auth-conflict] Patched {n} occurrence(s).")
    changed = True

# === Patch 2: npm-deprecation-warning — return null instead of the notification ===
old2 = b'return{timeoutMs:15000,key:"npm-deprecation-warning"'
new2 = b'return null;//                                      '
assert len(new2) == len(old2)

if data.count(b'return null;//') >= 1 and data.count(old2) == 0:
    print("[npm-deprecation] Already patched.")
elif data.count(old2) == 0:
    print("[npm-deprecation] WARNING: pattern not found — binary may have changed. Skipping.")
else:
    n = 0
    idx = 0
    while True:
        pos = data.find(old2, idx)
        if pos == -1:
            break
        data[pos:pos+len(old2)] = new2
        idx = pos + len(new2)
        n += 1
    print(f"[npm-deprecation] Patched {n} occurrence(s).")
    changed = True

if changed:
    with open(cli, 'wb') as f:
        f.write(data)
    print("Binary written.")

# Verify
with open(cli, 'rb') as f:
    verify = f.read()

auth_ok = verify.count(b'isActive:()=>{return!1') >= 1 and verify.count(old1) == 0
npm_ok = verify.count(b'return null;//') >= 1 and verify.count(old2) == 0
print(f"[auth-conflict] verified: {auth_ok}")
print(f"[npm-deprecation] verified: {npm_ok}")
PYEOF
```

Report per-patch status to the user.
