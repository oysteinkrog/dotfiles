#!/usr/bin/env bash
# PreToolUse hook for Bash. Enforces the "Builds" rules in ~/.claude/CLAUDE.md.
#
# Blocks (exit 2):
#   build_dir    CARGO_BUILD_BUILD_DIR or `--config build.build-dir=...` set by
#                hand. ~/.cargo/config.toml keeps intermediate files in the
#                workspace target dir; an override brings back one fresh
#                20 to 40 GiB tree per run. Values under ~/.cache/build
#                (localbuild) are allowed.
#   tmp          clone, worktree add or a heavy build in /tmp, which is tmpfs.
#   grove_lane   `git worktree add` from the monorepo to a path outside grove's
#                work_dir (the old ~/lane-wt pattern).
#
# Warns, without blocking:
#   no_wrapper   a heavy cargo or dotnet command, or build.cmd/build.sh, that
#                does not run under heavy-build. The warning reaches the agent
#                as additional context.
#
# Detection lives in build-detect.py, which reuses the shell segmentation in
# grove-worktree-detect.py. Test matrix in build-guard.test.py. Run the tests
# after any change to either file.
#
# Every failure of this hook's own parsing fails OPEN (allows the command).
# To bypass on purpose, append ` # noqa: build-guard` to the command.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 0

payload=$(cat) || exit 0
command=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null) || cwd=

# Cheap pre-filter so most Bash calls never start python.
if ! printf '%s' "$command" | grep -qE 'cargo|dotnet|build\.(cmd|sh)|BUILD_DIR|build-dir|clone|worktree'; then
  exit 0
fi
if [[ $command == *"noqa: build-guard"* ]]; then
  exit 0
fi

out=$(BUILD_GUARD_COMMAND="$command" BUILD_GUARD_CWD="$cwd" \
  timeout 10 python3 "$here/build-detect.py" 2>/dev/null) || exit 0
[[ -n $out ]] || exit 0

block=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "block"' | head -1)
if [[ -n $block ]]; then
  kind=$(printf '%s' "$block" | cut -f2)
  detail=$(printf '%s' "$block" | cut -f3-)
  case $kind in
    build_dir)
      cat >&2 <<EOF
BLOCKED: build dir override.

Command: $detail

Do not set CARGO_BUILD_BUILD_DIR or build.build-dir. ~/.cargo/config.toml keeps
cargo's intermediate files in the workspace's own target dir, so they are
reused and removed with the worktree. An override makes a new 20 to 40 GiB tree.
Setting CARGO_TARGET_DIR is fine; it now moves only the final binaries.

Use instead: heavy-build cargo <subcommand> ...   (see ~/.claude/CLAUDE.md, "Builds")
EOF
      ;;
    tmp)
      cat >&2 <<EOF
BLOCKED: clone, worktree or build in /tmp.

Command: $detail

/tmp is tmpfs, so every byte there is RAM. Scratch work goes in /var/tmp/claude/.
For a second checkout of a repo you already have:
  git -C ~/work/<repo> worktree add --detach /var/tmp/claude/<task> <ref>
EOF
      ;;
    grove_lane)
      cat >&2 <<EOF
BLOCKED: monorepo worktree outside grove.

Command: $detail

Worktrees of the monorepo go through grove, so grove can list and remove them:
  grove new --ephemeral --ttl 3d <tag>      (lands in <work_dir>/.scratch/<tag>)
  grove done <tag>                          (when the work is merged)
EOF
      ;;
    *)
      exit 0
      ;;
  esac
  exit 2
fi

warn=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "warn" && $2 == "no_wrapper"' | head -1 | cut -f3-)
if [[ -n $warn ]]; then
  msg="build-guard: this looks like a heavy build without heavy-build ($warn). Machine rule (~/.claude/CLAUDE.md, \"Builds\"): run every cargo build/test/check/clippy and dotnet build/test as \`heavy-build <command>\`. It takes the shared build lock, so it may wait; run it in the background if your tool call has a timeout. The command was allowed this time."
  jq -cn --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}' 2>/dev/null || true
fi
exit 0
