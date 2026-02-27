---
name: markdown-viewer
description: |
  View/read markdown files rendered in the terminal using glow.
  Use when user says "view markdown", "read md", "show readme", "preview markdown",
  or wants to open a .md file for reading.
allowed-tools:
  - Bash
---

# Markdown Viewer (glow)

Render and display a markdown file in the terminal using `glow`.

## Instructions

1. Determine the file to view from the user's request
2. Launch glow with the file:

```bash
glow -p "$FILE"
```

The `-p` flag enables pager mode for scrollable output.

For a full TUI browser (navigable, with search):

```bash
glow "$FILE"
```

Tips:
- `glow` is installed at `~/go/bin/glow` (in PATH via go env)
- For Windows-side paths, convert with `wslpath` first if needed
- If the user just wants a quick render without paging: `glow "$FILE" | head -80`
