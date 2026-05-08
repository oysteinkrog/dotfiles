# Phase 1 ready-to-paste prompts

Each file in this directory is a short natural-language prompt you can paste directly into a Claude Code / Codex session (desktop app or CLI) to drive one stage of the Phase 1 pipeline.

## How to use

1. Open your migration working directory in Claude Code or Codex (wherever `config.env` lives).
2. `cat` or open the relevant prompt file, copy its body, paste into the chat prompt.
3. The agent will run the stage, watch the scripts, read the reports, and summarize the result.

Alternatively, ask the agent: *"Read `prompts/<stage>.md` and follow it."* and it will do the same thing.

## Index

| File | When to use |
|------|-------------|
| [orient.md](orient.md) | Very first prompt in a fresh session — loads the skill's mental model |
| [setup.md](setup.md) | Stage 1: initialize workdir + validate config |
| [export.md](export.md) | Stage 2: acquire the Slack export (official / slackdump / grid) |
| [enrich.md](enrich.md) | Stage 3: download files, resolve emails, emoji, sidecars |
| [transform.md](transform.md) | Stage 4: mmetl convert Slack → Mattermost JSONL |
| [package.md](package.md) | Stage 5: patch JSONL, bundle into final import ZIP |
| [verify.md](verify.md) | Stage 6: four validators + evidence pack + secret scan |
| [handoff.md](handoff.md) | Stage 7: emit handoff.json / handoff.md for Phase 2 |
| [all.md](all.md) | Run every stage end-to-end, reporting between each |
| [resume.md](resume.md) | Session died / laptop rebooted — figure out where you are and continue |
