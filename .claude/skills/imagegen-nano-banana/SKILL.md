---
name: imagegen-nano-banana
description: |
  Generate images via Google Gemini Nano Banana Pro (gemini-3-pro-image-preview),
  the SOTA Google image model as of 2026. Use when the user wants to create,
  generate, render, or produce an image with Google / Gemini (e.g. "make me an
  image with gemini", "use nano banana", "nano banana pro", "google image gen",
  "imagen alternative"). Wraps the v1beta generateContent REST API in a small
  bash script. Supports up to 14 reference images for blending and 4K output.
allowed-tools:
  - Bash
  - Read
---

# imagegen-nano-banana — Gemini Nano Banana Pro from the CLI

Thin shell wrapper around
`POST generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`.
Defaults to `gemini-3-pro-image-preview` (Nano Banana Pro). Decodes the inline
base64 image straight to a file.

## Tool

```
~/.claude/skills/imagegen-nano-banana/bin/imagegen-nano-banana
```

Run with `--help` for the full flag list. Common invocations:

```bash
# Default: 1:1, 2K, gemini-3-pro-image-preview
~/.claude/skills/imagegen-nano-banana/bin/imagegen-nano-banana \
  "a cat reading a newspaper"

# Wide 4K poster
~/.claude/skills/imagegen-nano-banana/bin/imagegen-nano-banana \
  -a 16:9 -s 4K -o /tmp/sunrise.png \
  "panoramic alpine sunrise, dramatic clouds, photorealistic"

# Blend reference images
~/.claude/skills/imagegen-nano-banana/bin/imagegen-nano-banana \
  -i ref1.png -i ref2.png -i ref3.png \
  "compose these into a single cohesive product shot, studio lighting"

# Switch to faster Nano Banana 2 (Flash variant)
~/.claude/skills/imagegen-nano-banana/bin/imagegen-nano-banana \
  -m gemini-3.1-flash-image-preview \
  "a quick concept sketch of a cyberpunk corgi"

# Use Google Search grounding for up-to-date data
~/.claude/skills/imagegen-nano-banana/bin/imagegen-nano-banana --grounding \
  "infographic of today's NASDAQ close, clean editorial style"
```

## API key

Reads `GEMINI_API_KEY` in this order:

1. Environment variable.
2. `$IMAGEGEN_NANO_BANANA_KEYS_FILE` if set, else
   `~/.config/imagegen-nano-banana/keys.env` — sourced as shell `KEY=value` lines.

Set up the file the first time:

```bash
mkdir -p ~/.config/imagegen-nano-banana && chmod 700 ~/.config/imagegen-nano-banana
printf 'GEMINI_API_KEY=...\n' > ~/.config/imagegen-nano-banana/keys.env
chmod 600 ~/.config/imagegen-nano-banana/keys.env
```

Get a key from <https://aistudio.google.com/apikey>. The script exits with a
clear error if the key is missing.

## Flags

| Flag | Default | Notes |
|------|---------|-------|
| `-p, --prompt` | — | or pass as positional |
| `-o, --out` | `./imagegen-nano-banana-<ts>.<ext>` | extension follows response mime |
| `-m, --model` | `gemini-3-pro-image-preview` | see model table below |
| `-a, --aspect` | `1:1` | `16:9`, `9:16`, `4:3`, `3:4`, `21:9`, `2:3`, `3:2` |
| `-s, --size` | `2K` | `1K` / `2K` / `4K` (Pro supports all) |
| `-i, --image` | — | reference image path; repeatable |
| `--grounding` | off | enable Google Search grounding (Pro only) |
| `--thinking` | — | `low` / `medium` / `high` reasoning depth |

### Models

| Model ID | Codename | Use for |
|----------|----------|---------|
| `gemini-3-pro-image-preview` | Nano Banana Pro | Highest fidelity, 4K, complex layouts, text-in-image |
| `gemini-3.1-flash-image-preview` | Nano Banana 2 | Fast everyday generation |
| `gemini-2.5-flash-image` | Nano Banana | Original; fastest, cheapest |

## How to use this skill

1. Pick a prompt. If the user wasn't specific, ask one short clarifying question
   about subject + style + aspect ratio rather than guessing.
2. Run the script via `Bash`. Pro at 2K typically returns in 8–12s.
3. The script prints the output path on success — show the image to the user
   (`Read` it so it renders inline, or mention the path).
4. For iteration, tweak the prompt (or add `-i previous.png` as a reference).

## Notes

- All Google-generated images carry the imperceptible **SynthID** watermark.
  Mention this if the user is producing assets where AI provenance matters.
- Multilingual text-in-image is a strength — call it out for posters/ads.
- `--grounding` adds a fixed surcharge per call but lets the model use real-time
  web context (e.g. "today's weather map", "current charts"). Pro only.
- Reference-image blend works up to ~14 inputs; the model treats them as visual
  context for the prompt, not as a starting canvas to edit.
- The default model often returns JPEG (not PNG). The script picks the file
  extension from the response mime type when no `-o` is supplied; if you do
  pass `-o foo.png`, the file will be written to that exact path even if the
  bytes are JPEG (most viewers handle the mismatch).
- If the response comes back text-only (e.g. safety filter), the script surfaces
  the model's text reply in the error message.
