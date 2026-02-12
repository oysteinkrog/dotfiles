---
name: clipboard
description: |
  Copy text to the Windows clipboard from WSL. Handles Unicode correctly.
  Use when user says "copy to clipboard", "clip this", or "copy that".
allowed-tools:
  - Bash
---

# Copy to Clipboard (WSL/Windows)

Copy the provided text to the Windows clipboard with correct Unicode encoding.

## Instructions

1. Write the text to a temp file as UTF-8
2. Convert to UTF-16LE with BOM and pipe to `clip.exe`
3. Clean up the temp file

Use this pattern:

```bash
tmpfile=$(mktemp) && cat <<'CLIP_EOF' > "$tmpfile"
<TEXT TO COPY>
CLIP_EOF
iconv -f utf-8 -t utf-16le "$tmpfile" | clip.exe && rm -f "$tmpfile"
```

Important:
- Always use `iconv -f utf-8 -t utf-16le` before piping to `clip.exe` — without this, Unicode characters (em dashes, curly quotes, etc.) get garbled
- Use a heredoc with `'CLIP_EOF'` (quoted) to prevent shell expansion
- Confirm to the user when done
