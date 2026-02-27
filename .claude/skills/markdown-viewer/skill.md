---
name: markdown-viewer
description: |
  Open markdown files in Markpad (Windows GUI viewer).
  Use when user says "view markdown", "read md", "show readme", "preview markdown",
  or wants to open a .md file for reading.
allowed-tools:
  - Bash
---

# Markdown Viewer (Markpad)

Open a markdown file in Markpad, a lightweight Windows GUI markdown viewer.

## Instructions

1. Determine the file to view from the user's request
2. Convert the path to a Windows path and launch Markpad:

```bash
MARKPAD=$(wslpath -w ~/bin/Markpad.exe)
MDFILE=$(wslpath -w "$FILE")
powershell.exe -NoProfile -Command "Start-Process '$MARKPAD' -ArgumentList '$MDFILE'"
```

Tips:
- Markpad.exe is a portable Tauri app at `~/bin/Markpad.exe`
- Always use `wslpath -w` to convert WSL paths to Windows paths before passing to Markpad
- Use `powershell.exe Start-Process` to avoid the cmd.exe UNC path cwd issue in WSL
- Confirm to the user which file was opened
