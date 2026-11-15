# Global rules for Codex and opencode

These are the tool-neutral rules from `~/.claude/CLAUDE.md`, the full rule file for Claude
Code. That file also covers Claude-only workflows (subagents, swarms, model choice). Read a
section of it when a task needs the detail. When the two files disagree, the full file wins.

## Writing for people

Chat replies, docs, commit and PR messages, and comments meant for a person all follow this:

- Lead with the answer. A yes or no gets one line.
- Use short, common words and one idea per sentence. Write in active voice. Give concrete
  numbers and names.
- Keep technical terms, numbers, units and caveats. Simplify the sentence, not the term.
- Never use an em dash. Use a period, colon, comma or parentheses.
- No slogans, hype words or rule-of-three lists.
- Say plainly what you verified, what you inferred and what you guessed.
- Never estimate time or effort. Measured times (a build took 44 s) are fine.

## Safety

- Never kill a process you did not start.
- Never change branch, reset, rebase or amend in a shared checkout. Commit with a pathspec
  (`git commit -m "..." -- <files>`), and commit only the files that belong to your task.
- Check the real state (`git log`, the file tree) before you assume something is done.
- Run `gh pr list --head <branch>` before you create a PR.
- You may install packages (`sudo pacman -S`, `paru`, `sudo apt install`) and run root
  commands. Say what you changed. A reboot needs Oystein's yes first.
- Questions go to Oystein, never to colleagues.

## Secrets

- All secrets are in `~/.config/secrets/.env`. Do not search the filesystem or old session
  logs for them.
- Read one with `secret KEY`. Run a command with some of them using
  `with-secrets KEY [KEY ...] -- CMD ARGS`.
- Never print a secret value, not even part of one. To check that a key is set, check its
  length only.
- Never commit a secret. Reference it by its variable name.

## Repos and scratch space

- Never `git clone` a repo that already exists on this machine. For a second checkout, add
  a worktree under `/var/tmp/claude/<task>` and remove it when the task ends.
- Never clone, build or store scratch files in `/tmp`. It is RAM. Use `/var/tmp/claude/`.
- The monorepo under `~/work/desktop` belongs to grove. Use `grove new --ephemeral`, never a
  raw `git worktree add` there.
- Upstream clones under `~/src` are only fetched. Build and install them with `localbuild`.
- New files for `~` go in `~/.dotfiles` first, symlinked from `~`.

## Builds and big jobs

- Run every heavy build or test through `heavy-build` (cargo, dotnet, cmake, ninja,
  `build.sh`, `localbuild build`). It hands the job to the jobd queue.
- Exit code 75, 76 or 77 means the build did not run. Read the last `heavy-build:` line and
  follow it. Never resubmit in a loop.
- Jobs that may use more than 2 GB of memory (renders, video, ML) go through `heavy-build`
  or `job submit`.
- Never set `CARGO_TARGET_DIR`, `CARGO_BUILD_BUILD_DIR` or `build.build-dir`.

## Tools

- Beads: `br` is the CLI. Never run bare `bv`, it opens a TUI and hangs. Always pass a
  `--robot-*` flag.
- `cass` searches past agent sessions. Never run `cass index --semantic`.
- When you are asked for a second opinion, give your own answer. Do not call `codex exec`.
