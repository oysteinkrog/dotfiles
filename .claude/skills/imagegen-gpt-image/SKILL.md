---
name: imagegen-gpt-image
description: |
  Generate images via OpenAI's gpt-image-2 (the SOTA OpenAI image model as of 2026).
  Use when the user wants to create, generate, render, or produce an image with
  OpenAI / GPT (e.g. "make me an image of...", "generate a logo with gpt-image",
  "use openai image gen", "openai image 2"). Wraps the v1/images/generations API
  in a small bash script.
allowed-tools:
  - Bash
  - Read
---

# imagegen-gpt-image — OpenAI gpt-image-2 from the CLI

Thin shell wrapper around `POST https://api.openai.com/v1/images/generations`
using `gpt-image-2`. Decodes the base64 response straight to a file.

## Tool

```
~/.claude/skills/imagegen-gpt-image/bin/imagegen-gpt-image
```

Invoke with bash; no install step needed. Run with `--help` for the full flag
list. Common invocations:

```bash
# Default: 1024x1024 PNG to ./imagegen-gpt-image-<timestamp>.png
~/.claude/skills/imagegen-gpt-image/bin/imagegen-gpt-image \
  "a cat reading a newspaper"

# Specific output path, larger size
~/.claude/skills/imagegen-gpt-image/bin/imagegen-gpt-image \
  -o /tmp/coffee-shop.png \
  -s 2048x2048 -q high \
  "isometric coffee shop, soft pastel palette"

# Multiple variants in one call
~/.claude/skills/imagegen-gpt-image/bin/imagegen-gpt-image \
  -n 3 -o sketches.png "rough pencil sketch of a fox"
# -> writes sketches_1.png, sketches_2.png, sketches_3.png
```

## API key

Reads `OPENAI_API_KEY` in this order:

1. Environment variable.
2. `$IMAGEGEN_GPT_IMAGE_KEYS_FILE` if set, else
   `~/.config/imagegen-gpt-image/keys.env` — sourced as shell `KEY=value` lines.

Set up the file the first time:

```bash
mkdir -p ~/.config/imagegen-gpt-image && chmod 700 ~/.config/imagegen-gpt-image
printf 'OPENAI_API_KEY=sk-...\n' > ~/.config/imagegen-gpt-image/keys.env
chmod 600 ~/.config/imagegen-gpt-image/keys.env
```

The script exits with a clear error if the key is missing — no silent fallback.

## Flags

| Flag | Default | Notes |
|------|---------|-------|
| `-p, --prompt` | — | or pass as positional |
| `-o, --out` | `./imagegen-gpt-image-<ts>.<fmt>` | with `-n>1`, `_1`, `_2`, ... suffix |
| `-m, --model` | `gpt-image-2` | override if a newer model ships |
| `-s, --size` | `1024x1024` | `1536x1024`, `1024x1536`, `2048x2048`, ... |
| `-q, --quality` | `high` | `low` / `medium` / `high` / `auto` |
| `-n, --count` | `1` | number of images |
| `-f, --format` | `png` | `png` / `jpeg` / `webp` |
| `--stdout` | off | write decoded bytes to stdout (n=1 only) |

## How to use this skill

1. Pick a prompt. If the user wasn't specific, ask one short clarifying question
   about subject + style + aspect ratio rather than guessing.
2. Run the script via `Bash`. It prints the output file path on success.
3. Show the resulting image to the user (e.g. via `Read` on the path so it
   renders inline, or by mentioning the path so they can open it).
4. If the user wants iteration, tweak the prompt and re-run — gpt-image-2 is
   fast enough for several rounds in a session.

## Notes

- gpt-image-2 supports up to ~4K and renders multilingual text well — call that
  out as an option if the user is making a poster, ad, or anything text-heavy.
- The response is base64 (`b64_json`), so writes never go through a temporary
  URL. No external image hosts are involved.
- Org Verification may be required for image generation on some accounts; if
  you get a 403, ask the user to verify in their OpenAI dashboard.
