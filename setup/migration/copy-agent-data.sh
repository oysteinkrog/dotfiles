#!/usr/bin/env bash
# Copy the agent data that git does not hold from an old Windows disk, then check it.
# Used once per machine when it moves from Windows + WSL to Linux. See
# docs/migration-from-windows.md for where each item goes afterwards.
#
#   copy-agent-data.sh copy   SRC [DEST]   rsync into DEST (default ~/migration/win-c)
#   copy-agent-data.sh verify SRC [DEST]   checksum-compare DEST against SRC
#
# SRC is the Windows user folder on the mounted disk, e.g. /mnt/win-c/Users/oystein.
# Mount the disk with ntfs-3g, not ntfs3: only ntfs-3g reads WSL-style symlinks.
set -uo pipefail

mode="${1:?usage: copy-agent-data.sh copy|verify SRC [DEST]}"
S="${2:?usage: copy-agent-data.sh copy|verify SRC [DEST]}"
D="${3:-$HOME/migration/win-c}"
# The WSL distro's home, inside the Windows profile. Adjust if the distro differs.
U="${WSL_HOME:-AppData/Local/Packages/CanonicalGroupLimited.Ubuntu24.04LTS_79rhkp1fndgsc/LocalState/rootfs/home/oystein}"

items=(
  .dotfiles/.claude/projects                               # Claude transcripts
  .dotfiles/.claude/history.jsonl
  AppData/Roaming/coding-agent-search/coding-agent-search/data   # cass index
  .codex
  "$U/.mcp_agent_mail_git_mailbox_repo"                    # the live agent-mail store
  .mcp_agent_mail_git_mailbox_repo
  .local/share/mcp-agent-mail
  .gemini
  .local/share/opencode
  .cass-memory
  .ft-bookmarks
  .config/secrets
  .gnupg
  .ssh
  .agents
)

case "$mode" in
  copy)
    for i in "${items[@]}"; do
      [ -e "$S/$i" ] || { echo "MISSING $i"; continue; }
      echo "=== $i  $(date +%T)"
      mkdir -p "$D/$(dirname "$i")"
      rsync -rlt --partial --info=stats1 "$S/$i" "$D/$(dirname "$i")/" 2>&1 |
        grep -E 'error|Number of regular files transferred|Total transferred file size|rsync:'
    done
    chmod -R go-rwx "$D/.config/secrets" "$D/.gnupg" "$D/.ssh" 2>/dev/null
    echo "=== done $(date +%T)"
    ;;
  verify)
    # NTFS reparse points and gpg sockets always show up here; they are expected.
    for i in "${items[@]}"; do
      n=$(rsync -rlc --dry-run --out-format='%n' "$S/$i" "$D/$(dirname "$i")/" 2>&1 |
        grep -v '/$' | tee -a "$D/verify-diffs.txt" | wc -l)
      echo "$n differences: $i"
    done
    ;;
  *) echo "unknown mode: $mode" >&2; exit 2 ;;
esac
