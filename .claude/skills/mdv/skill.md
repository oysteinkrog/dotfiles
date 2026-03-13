---
name: mdv
description: |
  Open markdown files in Markpad (Windows GUI viewer).
  Use when user says "view markdown", "read md", "show readme", "preview markdown",
  "open in markpad", "mdv", or wants to open a .md file for reading.
allowed-tools:
  - Bash
---

# Markdown Viewer (Markpad)

Open one or more markdown files in Markpad, a lightweight Windows GUI markdown viewer.

## Launch Command

```bash
MARKPAD=$(wslpath -w "$(realpath ~/bin/Markpad.exe)")
MDFILE=$(wslpath -w "<absolute-path-to-file>")
powershell.exe -NoProfile -Command "Start-Process '$MARKPAD' -ArgumentList '$MDFILE'"
```

For multiple files, repeat the `powershell.exe Start-Process` line for each file.

## Key Details

- **Binary**: `~/bin/Markpad.exe` (symlinked from `~/.dotfiles/bin/`)
- **Type**: Portable Tauri app, no install required
- **`realpath` is required**: The binary is behind a WSL symlink. Windows cannot follow WSL symlinks, so `realpath` must resolve to the physical path before `wslpath -w` converts it.
- **`powershell.exe Start-Process` is required**: `cmd.exe /c start` fails with "Access is denied" on UNC paths in WSL. Always use `powershell.exe -NoProfile -Command "Start-Process ..."`.
- **Do not use** `cmd.exe /c`, `cmd.exe /c start`, or direct `.exe` invocation — they all fail in WSL for this binary.
- Confirm to the user which file(s) were opened.
