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

The script patches **all** Claude Code binaries it finds — the native install
(`~/.local/share/claude/versions/<v>`) and any npm install — because shell
aliases can make `which claude` lie about which one actually runs.

## Instructions

Run this Python script via Bash:

```bash
python3 << 'PYEOF'
import os, glob, sys, subprocess

# === Discover all Claude Code binaries ===
candidates = set()

# Native install: ~/.local/share/claude/versions/<version>
home = os.path.expanduser("~")
for p in glob.glob(f"{home}/.local/share/claude/versions/*"):
    if os.path.isfile(p):
        candidates.add(os.path.realpath(p))

# npm install(s) under nvm
for p in glob.glob(f"{home}/.nvm/versions/node/*/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"):
    candidates.add(os.path.realpath(p))
for p in glob.glob(f"{home}/.nvm/versions/node/*/lib/node_modules/@anthropic-ai/claude-code/cli.js"):
    candidates.add(os.path.realpath(p))

# Whatever `which claude` and `which -a claude` resolve to
try:
    r = subprocess.run(['bash', '-c', 'which -a claude 2>/dev/null'], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        line = line.strip()
        if line and os.path.isfile(line):
            candidates.add(os.path.realpath(line))
except Exception:
    pass

if not candidates:
    print("ERROR: no Claude Code binaries found.")
    sys.exit(1)

print(f"Found {len(candidates)} binary/binaries:")
for c in sorted(candidates):
    print(f"  {c}")

# === Known patterns ===
# Patch 1 has multiple known shapes (minified names rotate per release).
# Each entry is the EXACT old pattern; replacement always becomes
# `isActive:()=>{return!1` + spaces + `}` (same length).
AUTH_OLD_PATTERNS = [
    # npm install shape (older builds)
    b'isActive:()=>{let{source:H}=rz({skipRetrievingKeyFromApiKeyHelper:!0}),$=sh();return H!=="none"&&$.source!=="none"&&!(H==="apiKeyHelper"&&$.source==="apiKeyHelper")}',
    # native install shape (~2.1.128)
    b'isActive:()=>{let H=pp();return Nq()&&(H.source==="ANTHROPIC_AUTH_TOKEN"||H.source==="apiKeyHelper")}',
]
AUTH_NEW_CORE = b'isActive:()=>{return!1'

NPM_OLD = b'return{timeoutMs:15000,key:"npm-deprecation-warning"'
NPM_NEW = b'return null;//                                      '
assert len(NPM_NEW) == len(NPM_OLD)


def make_replacement(old: bytes, new_core: bytes) -> bytes:
    pad = len(old) - len(new_core) - 1
    return new_core + b' ' * pad + b'}'


def patch_file(path: str) -> None:
    print(f"\n=== {path} ===")
    with open(path, 'rb') as f:
        data = bytearray(f.read())
    changed = False

    # --- Patch 1: auth-conflict ---
    matched_pattern = None
    for old in AUTH_OLD_PATTERNS:
        if data.count(old) > 0:
            matched_pattern = old
            break

    already = data.count(AUTH_NEW_CORE)
    if matched_pattern is None and already > 0:
        print(f"[auth-conflict] Already patched ({already} occurrence(s)).")
    elif matched_pattern is None:
        # Diagnostic: show any isActive arrow functions present so we can
        # extend AUTH_OLD_PATTERNS in a future Claude Code release.
        import re
        seen = set()
        for m in re.findall(rb'isActive:\(\)=>\{[^}]{20,300}\}', bytes(data)):
            seen.add(m)
        print("[auth-conflict] No known pattern found. isActive variants in this binary:")
        for m in list(seen)[:10]:
            print(f"    {m!r}")
        print("  → Add the matching one to AUTH_OLD_PATTERNS in this skill.")
    else:
        new = make_replacement(matched_pattern, AUTH_NEW_CORE)
        assert len(new) == len(matched_pattern)
        n = 0
        idx = 0
        while True:
            pos = data.find(matched_pattern, idx)
            if pos == -1:
                break
            data[pos:pos+len(matched_pattern)] = new
            idx = pos + len(new)
            n += 1
        print(f"[auth-conflict] Patched {n} occurrence(s).")
        changed = True

    # --- Patch 2: npm-deprecation ---
    if data.count(NPM_OLD) == 0 and data.count(b'return null;//') >= 1:
        print("[npm-deprecation] Already patched (or absent).")
    elif data.count(NPM_OLD) == 0:
        print("[npm-deprecation] Pattern not present (likely native install — skipping).")
    else:
        n = 0
        idx = 0
        while True:
            pos = data.find(NPM_OLD, idx)
            if pos == -1:
                break
            data[pos:pos+len(NPM_OLD)] = NPM_NEW
            idx = pos + len(NPM_NEW)
            n += 1
        print(f"[npm-deprecation] Patched {n} occurrence(s).")
        changed = True

    if changed:
        with open(path, 'wb') as f:
            f.write(data)
        print("Binary written.")

    # Verify
    with open(path, 'rb') as f:
        verify = f.read()
    any_old_left = any(verify.count(p) > 0 for p in AUTH_OLD_PATTERNS)
    auth_ok = (not any_old_left) and verify.count(AUTH_NEW_CORE) >= 1
    npm_ok = verify.count(NPM_OLD) == 0
    print(f"[auth-conflict] verified: {auth_ok}")
    print(f"[npm-deprecation] verified: {npm_ok}")


for c in sorted(candidates):
    try:
        patch_file(c)
    except PermissionError as e:
        print(f"\n=== {c} ===\nPermission denied: {e}")
    except Exception as e:
        print(f"\n=== {c} ===\nError: {e}")
PYEOF
```

Report per-binary, per-patch status to the user. If `[auth-conflict]` reports
"No known pattern found" for the native binary, the script prints the
`isActive:()=>{...}` variants it sees — copy the auth-related one back into
`AUTH_OLD_PATTERNS` in this skill (the replacement is always
`isActive:()=>{return!1}` with same length).
