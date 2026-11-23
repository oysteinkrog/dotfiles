---
name: moss-comfyui
description: Use the MOSS-Image ComfyUI server on the office desktop (RTX 5070 Ti) from the home desktop. Start, stop and save it, generate images from the command line with the "MOSS app" workflow, add models or LoRAs from Civitai, and edit the custom nodes and prompt lists. Use when the user says comfy, ComfyUI, MOSS, MOSS-Image, MOSS app, image generation on the office GPU, or asks to start, stop, save or generate.
---

# MOSS-Image ComfyUI

Read `~/projects/life/docs/computers/moss-image-comfyui-usage.md` first. It covers the MOSS app
controls, models, speeds, LoRAs, prompt templates, seeds and the agent rules. Server setup and
privacy design: `~/projects/life/docs/computers/moss-image-comfyui.md`.

The command is `~/projects/life/tools/moss-comfyui/comfy`:

```sh
comfy status | start | save | stop | deploy | rebuild
comfy gen --list
comfy gen --prompt "..." [--model ...] [--speed ...] [--lora "Label=strength|off"] [--seed N] [--preview]
```

Rules that matter most:

- Tell `oystein/manager-office` on Agent Hub when you start the server.
- Never stop or restart while the queue is busy. `comfy stop` and `comfy deploy` wait for it.
- A restart wipes the workflows on the server. `comfy save` before, or use `comfy deploy`.
- Nothing may be stored on the office desktop except models and nodes. Images go to
  `~/Pictures/moss-image` at home.
- Test with neutral prompts. Never copy Oystein's prompts into messages, commits or logs.
- Downloads: say the size first (office disk is 98% full), check SHA256, and ask before
  spending Buzz on Early Access files.
