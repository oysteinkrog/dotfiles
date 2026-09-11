---
name: imagegen-gpt-image
description: |
  Generate and edit images with OpenAI GPT Image 2.5 (gpt-image-2.5-flare and
  gpt-image-2.5-sunburst, released 2026-09-08). Use when the user wants to
  create, generate, render, or edit an image with OpenAI / GPT (e.g. "make me
  an image of...", "generate a logo with gpt-image", "use openai image gen",
  "gpt image 2.5", "edit this photo with gpt image"). Wraps the
  v1/images/generations and v1/images/edits APIs in a small bash script.
allowed-tools:
  - Bash
  - Read
---

# imagegen-gpt-image: OpenAI GPT Image 2.5 from the CLI

Shell wrapper around `POST https://api.openai.com/v1/images/generations` and
`POST https://api.openai.com/v1/images/edits`. Decodes the base64 response
straight to a file.

## Models

GPT Image 2.5 ships as two model IDs. There is no bare `gpt-image-2.5`.

| Model ID | Use it for |
|----------|-----------|
| `gpt-image-2.5-flare` | Fast everyday generation. The script's default. |
| `gpt-image-2.5-sunburst` | Best instruction following and edit precision. The model OpenAI documents for masked inpainting. |

Both cost the same: $5/M text input tokens, $8/M image input tokens, $30/M
image output tokens. Cached input is $1.25/M (text) and $2/M (image). Same
per-token rates as gpt-image-2, so 2.5 is not a price increase.

Rough guide: pick Flare unless the job is an edit that must keep a face, a
logo, or product detail intact, or the prompt has many precise constraints.
Then pick Sunburst.

`gpt-image-2` still works if you pass `-m gpt-image-2`, but 2.5 is better and
costs the same, so there is no reason to.

## Tool

```
~/.claude/skills/imagegen-gpt-image/bin/imagegen-gpt-image
```

Invoke with bash; no install step needed. Run with `--help` for the full flag
list. Common invocations:

```bash
# Default: Flare, 1024x1024 PNG, to ./imagegen-gpt-image-<timestamp>.png
~/.claude/skills/imagegen-gpt-image/bin/imagegen-gpt-image \
  "a cat reading a newspaper"

# Sunburst at top quality, specific output path and size
~/.claude/skills/imagegen-gpt-image/bin/imagegen-gpt-image \
  --sunburst -q max -s 2048x2048 -o /tmp/coffee-shop.png \
  "isometric coffee shop, soft pastel palette"

# Transparent-background asset
~/.claude/skills/imagegen-gpt-image/bin/imagegen-gpt-image \
  -b transparent -o logo.png "flat fox head icon, two colours"

# Multiple variants in one call
~/.claude/skills/imagegen-gpt-image/bin/imagegen-gpt-image \
  -n 3 -o sketches.png "rough pencil sketch of a fox"
# -> writes sketches_1.png, sketches_2.png, sketches_3.png
```

## Editing existing images

Pass `-i` one or more times and the script switches to the edits endpoint. Up
to 16 reference images per call.

```bash
# Keep the person's face, change everything around it
~/.claude/skills/imagegen-gpt-image/bin/imagegen-gpt-image \
  --sunburst \
  -i me.png -o portrait.png "put this person in a wool coat, snowy street"

# Combine several product shots into one scene
~/.claude/skills/imagegen-gpt-image/bin/imagegen-gpt-image \
  --sunburst -i lotion.png -i soap.png -i candle.png \
  -o basket.png "arrange these three products in a gift basket"

# Inpaint: only the transparent pixels of the mask get repainted
~/.claude/skills/imagegen-gpt-image/bin/imagegen-gpt-image \
  --sunburst -i room.png --mask wall.png \
  -o room2.png "paint the masked wall deep green"
```

Do not pass `--input-fidelity` with a 2.5 model. The API reference still lists
it as an edits parameter, but both 2.5 models reject it with
`invalid_input_fidelity_model` (checked against the live API on 2026-09-11).
Holding faces, logos, and fine texture is built into 2.5, so there is nothing
to turn on. The flag stays in the script for `-m gpt-image-2` and earlier, and
the script now fails fast if you combine it with a 2.5 model.

## API key

Reads `OPENAI_API_KEY` in this order:

1. Environment variable.
2. `$IMAGEGEN_GPT_IMAGE_KEYS_FILE` if set, else
   `~/.config/imagegen-gpt-image/keys.env`, sourced as shell `KEY=value` lines.

Set up the file the first time:

```bash
mkdir -p ~/.config/imagegen-gpt-image && chmod 700 ~/.config/imagegen-gpt-image
printf 'OPENAI_API_KEY=sk-...\n' > ~/.config/imagegen-gpt-image/keys.env
chmod 600 ~/.config/imagegen-gpt-image/keys.env
```

The script exits with a clear error if the key is missing. No silent fallback.

## Flags

| Flag | Default | Notes |
|------|---------|-------|
| `-p, --prompt` | none | or pass as positional |
| `-o, --out` | `./imagegen-gpt-image-<ts>.<fmt>` | with `-n>1`, `_1`, `_2`, ... suffix |
| `-m, --model` | `gpt-image-2.5-flare` | |
| `--sunburst` / `--flare` | none | shorthand for `-m` |
| `-s, --size` | `1024x1024` | `WIDTHxHEIGHT` or `auto` |
| `-q, --quality` | `high` | `low` / `medium` / `high` / `xhigh` / `max` / `auto` |
| `-n, --count` | `1` | number of images |
| `-f, --format` | `png` | `png` / `jpeg` / `webp` |
| `-b, --background` | server default | `transparent` / `opaque` / `auto` |
| `-c, --compression` | none | 0-100, jpeg and webp only |
| `--moderation` | server default | `auto` / `low` |
| `--stdout` | off | write decoded bytes to stdout (n=1 only) |
| `-i, --image` | none | reference image, repeat up to 16, switches to edit mode |
| `--mask` | none | inpainting mask PNG |
| `--input-fidelity` | none | `high` / `low`, pre-2.5 models only |

Size rules: both edges must be multiples of 16, at most 3840 per edge, aspect
ratio between 1:3 and 3:1, and total pixels between 655,360 and 8,294,400.
The three sizes OpenAI tunes for are 1024x1024, 1536x1024, and 1024x1536.

## How to use this skill

1. Pick a prompt. If the user was not specific, ask one short question about
   subject, style, and aspect ratio rather than guessing.
2. Pick the model. Flare by default. Sunburst for edits that must preserve a
   subject, for masked inpainting, or for prompts with many constraints.
3. Run the script via `Bash`. It prints the output file path on success.
4. Show the image to the user: `Read` the path so it renders inline, and give
   the path so they can open it themselves.
5. To iterate, feed the previous output back in with `-i` and describe only
   what should change. 2.5 changes only what you ask for and holds the rest,
   which makes multi-turn editing work far better than it did in 2.0.

## Notes

- 2.5 is up to 50% faster than 2.0 at the same quality, so several rounds in
  one session is normal.
- Text rendering is good, including non-English. Say so if the user is making
  a poster, an ad, or anything text-heavy.
- The response is base64 (`b64_json`), so writes never go through a temporary
  URL. No external image hosts are involved.
- Streaming partial images (`stream`, `partial_images`) is supported by the API
  but not by this script. It only helps interactive previews.
- Org Verification may be required for image generation on some accounts. On a
  403, ask the user to verify in their OpenAI dashboard.
