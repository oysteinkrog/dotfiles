---
name: explorer
description: |
  Open Windows Explorer in the current git worktree root.
  Use when user says "open explorer", "open folder", "show in explorer".
allowed-tools:
  - Bash
---

# Open Explorer

```bash
cmd.exe /c "explorer $(cygpath -w "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
```

Confirm to the user which folder was opened.
