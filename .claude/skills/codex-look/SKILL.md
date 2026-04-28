---
name: codex-look
description: |
  Get a second opinion on an image by asking the OpenAI Codex CLI to look at it.
  Use when the user wants Codex (GPT) to analyze an image they (or you) just looked at,
  asks for "a second opinion on this image", says "have codex look at it", or wants
  cross-model verification of a screenshot, photo, diagram, or any image file.
allowed-tools:
  - Bash
  - Read
---

# codex-look — Image Second Opinion via Codex CLI

Use the `codex` CLI (OpenAI Codex) to analyze an image for a second opinion.
Useful when you (Claude / Opus) have already looked at an image and the user wants
verification from a different model, or when the user explicitly asks Codex.

## When to trigger

- User says "second opinion on this image", "ask codex", "have codex look", "codex-look"
- User pastes/attaches an image and asks for cross-model verification
- You just analyzed an image and the user wants a different model's take

## The exact command

```bash
codex exec \
  --skip-git-repo-check \
  --sandbox read-only \
  -o /tmp/codex-look-out.txt \
  "<your prompt about the image>" \
  -i "<absolute path to image>" \
  >/dev/null 2>&1
cat /tmp/codex-look-out.txt
```

Then `Read` or `cat` `/tmp/codex-look-out.txt` to get Codex's reply.

### Why this exact form

- `--skip-git-repo-check` — Codex normally refuses to run outside a git repo; this lets it run from any working directory.
- `--sandbox read-only` — Codex won't try to edit anything; we only want a description.
- `-o /tmp/codex-look-out.txt` — writes only Codex's final answer to a file. Cleaner than parsing stdout.
- **Prompt comes BEFORE `-i`.** `codex exec -i FILE "prompt"` is parsed as `-i [FILE, "prompt"]` and Codex then reads from stdin and finds nothing. Always put the prompt first, image flag last.
- Redirect stdout/stderr to `/dev/null` — Codex prints MCP startup chatter and a session header. The `-o` file holds the only thing worth keeping.

## Examples

### Basic second opinion

```bash
codex exec --skip-git-repo-check --sandbox read-only \
  -o /tmp/codex-look-out.txt \
  "Describe what is in this image in 2-3 sentences." \
  -i /path/to/screenshot.png \
  >/dev/null 2>&1
cat /tmp/codex-look-out.txt
```

### Targeted question

```bash
codex exec --skip-git-repo-check --sandbox read-only \
  -o /tmp/codex-look-out.txt \
  "I think this UI has a contrast problem in the header. Do you agree, and if so, what specifically?" \
  -i ~/Pictures/screenshot.png \
  >/dev/null 2>&1
cat /tmp/codex-look-out.txt
```

### Pin a specific model

Add `-m <model>` if the user asked for a specific Codex model:

```bash
codex exec --skip-git-repo-check --sandbox read-only \
  -m gpt-5.4 \
  -o /tmp/codex-look-out.txt \
  "..." \
  -i /path/to/image.png \
  >/dev/null 2>&1
```

## Workflow

1. Confirm the image path exists (`ls -la <path>`). Resolve `~` to absolute first.
2. If the user has not already given a prompt, frame one that mirrors what *you* were
   asked about the image — Codex needs to know what to look for.
3. Run the command above. It typically takes 10-60s.
4. `Read` `/tmp/codex-look-out.txt` and present Codex's answer to the user, clearly
   labelled as "Codex says:" so they can compare against your own analysis.
5. If your reading and Codex's disagree, note the disagreement explicitly — that's
   the whole value of a second opinion.

## Notes

- Multiple images: pass `-i FILE1 -i FILE2` (repeat the flag) or `-i FILE1 FILE2`.
- Supported formats: anything Codex / the upstream model accepts (PNG, JPG, WEBP, etc.).
- If Codex output is empty, check `/tmp/codex-look-out.txt` exists and re-run without
  the stderr redirect to see startup errors.
- Codex login state is per-user; if you get an auth error, ask the user to run
  `! codex login` themselves.
