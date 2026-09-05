---
name: disk-cleanup
version: 1.0.0
description: |
  Diagnose and clean up disk space and disk mess on this machine (WSL1 desktop,
  C: drive). Finds and safely removes worktree sprawl, stale agent scratchpads,
  dead logs, orphaned WSL distros, package-cache bloat, and session litter.
  Use when the user says "disk full", "low on disk space", "free up space",
  "clean up disk", "what's using my disk", "C: drive full", "disk mess",
  "out of space", or "wiztree says". For zombie/stuck PROCESSES use sysperf;
  for the remote build-server fleet use system-performance-remediation.
allowed-tools: [Bash, Read, AskUserQuestion]
---

# Disk Cleanup (WSL1 / C: drive)

Scope: **bytes on disk, this machine**. Process cleanup → `sysperf`. Remote
fleet disk → `system-performance-remediation` (its Disk Cleanup section has the
generic technique; this skill owns the local WSL1 ground). If a directory grows
because a process is still writing (stuck build, log-spamming daemon), fix the
process first via sysperf — reclaimed space refills otherwise (observed: a
log-spam loop refilling 3.4G/week).

## Rule zero: never recursive-du big trees through WSL1

WSL1 per-file stat is the bottleneck, not the disk — both DrvFs (/c/...) and
VolFs (rootfs paths like /tmp). `du -sh` on >50k-file trees takes minutes or
never finishes (observed: 500s+ on ~/.rustup; /c/work/desktop and even /tmp
never complete; `grove list` full status takes 17+ min). Enumeration must run
**natively on Windows**:

```bash
S=~/.claude/skills/disk-cleanup/scripts/fastscan.py
python3 $S                                    # user profile, top 25 dirs + files
python3 $S /c/work/desktop --top 40           # WSL path in, WSL paths out
python3 $S /c --depth 2 --min-size 500M       # tree summary + only big files
python3 $S /c/users/oystein --json /tmp/scan.json --top 50   # machine-readable
python3 $S /c/users/oystein --exclude node_modules --exclude .git
python3 $S 'C:\' --engine mft                 # whole volume; ADMIN shell only
```

`fastscan.py` re-execs itself via `python.exe` (all enumeration runs natively),
skips junctions/reparse points, and prints top directories/files by size.
Measured: /c/work/desktop (3.8M files, 1.3 TiB) in 142s where `du` produced
nothing in 30 minutes; warm small-tree scans ~0.8s. The scandir engine needs no
elevation; `--engine mft` is only for whole-volume sweeps from an admin shell
(`--image FILE` scans a captured volume image instead).

**Linux-rootfs paths (/tmp, /home in rootfs) are scannable from Windows too**:
the live distro's rootfs sits under
`C:\Users\oystein\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu24.04LTS_*\LocalState\rootfs`.
Unelevated reads of another distro's private dirs get ACL-denied, but
**`sudo` inside WSL bypasses DrvFs ACLs** for reads. Windows-side reads of
rootfs are fine; **never create/modify/delete rootfs files from Windows**
(WSL1 metadata corruption) — delete from inside WSL even though it's slower.

Cheap in-WSL fallbacks: `df -h`, `ls | wc -l`, depth-limited `du` under
`timeout 120` — and treat a timeout as data (it means huge file count).

## Diagnosis procedure

1. **Pressure check**: `df -h /c /tmp` — C: free and % used.
2. **Fast scan** the known hog areas (table below) before exploring. Don't
   rediscover what the table already names.
3. **Categorize**: regenerable cache / dead log / stale worktree / stale
   scratchpad / orphaned distro / needs-user-review.
4. **Report first, delete second.** Ranked table with estimated reclaim and
   exact commands; one AskUserQuestion for everything not clearly regenerable.

## Known disk hogs (verified 2026-08-27 — sizes drift, re-verify)

| Location | What / size then | Action |
|---|---|---|
| `/c/work/desktop/*` worktrees | ~97 worktrees × 4–8G checked-out LFS media (~485G); Aug 2026 audit found 613G reclaimable across 83 merged trees | `grove gc --dry-run`, review, then `--yes`. Never enumerate via `grove list`; grove gc reads `git worktree list --porcelain` directly. `.scratch/*` worktrees self-expire (expires_at) — leave them |
| Build output *inside kept worktrees* | 200–300G (master alone 196G) | `purge-stale-builds --dry-run` (~/bin, age-gated, motioncatalyst BUILD* dirs); other build dirs need per-repo clean |
| `/tmp/claude-1000/<proj>/<session>` scratchpads | **266G measured** (1.1M files); only ~54G was >30d old — most is *recent* swarm-session churn (per-worktree projects at 20–34G each) | `scripts/purge-scratchpads.sh [days]` — age-gated, skips own session + any live process cwd, logs freed space. For the recent churn: check for finished sessions' huge dirs (scratch clones, build output) before tightening the age gate |
| `/tmp` loose top-level files | 22k files, 10G (8G >30d): `claude-edit-tracker-*.json{,.lock}`, `br-*-msg.txt`, stray logs | Covered by purge-scratchpads.sh (loose-file pass). Entry count alone slows every /tmp scan |
| **Orphaned WSL distros** | Ubuntu-22.04 held 27G incl. its own stale 18G /tmp (removed 2026-08-27) | `wsl.exe -l -v` + `reg.exe query HKCU\...\Lxss /s` → for each unused distro: audit references (bare `wsl.exe` inherits the DEFAULT distro: pm2-resurrect.vbs, CASS-Maintenance task, launch-claude-tabs.sh), `wsl --set-default` first, inspect rootfs for unique data (sudo via DrvFs), then `wsl --unregister` (IRREVERSIBLE) + Remove-AppxPackage |
| `desktop/master/.git` | 64G: 50G LFS store (SHARED — **keep**), 569M rr-cache | Only `git -C /c/work/desktop/master rerere gc`; objects had 0 garbage |
| PM2 logs (`~/.pm2/logs`, `~/.config/pm2/logs`) | 11G of dead `better-ccflare-rs` logs found once; agent-mail error log grows | Delete logs of apps absent from `pm2 ls`. Long-term: `pm2 install pm2-logrotate`. `~/.pm2` = LEGACY home, `~/.config/pm2` = active |
| `~/.claude/projects` | 12–15G, 22.5k session .jsonl (~5.7G >30d) | **Report-only** — cass indexes these. Offer archive/compress, deletion is the user's call |
| Package caches: `~/.rustup` 8.9G, `~/.cargo`, `~/.npm`, `~/.bun`, `~/go`, `~/.nvm`, `~/.gradle`, `~/.nuget` | 50k–260k files each (du times out — size with fastscan) | Regenerable: prune old rustup toolchains / nvm versions, `npm cache clean --force`, `go clean -modcache`. Keep `~/.cargo/bin` |
| Migration/backup leftovers | `~/.claude-clean` 340M, `~/.claude-backeupbeforedotfiles` 13M, `~/OneDrive_Backup_*` 6.3G | Confirm superseded with user, then remove |
| `~/.mcp_agent_mail_git_mailbox_repo` | 60k files | `git gc` inside it; see `~/bin/agent-mail-prune.sh` first |
| Agent-isolation worktrees `<repo>/.claude/worktrees/agent-*` | usually zero; known vector | `find <repo>/.claude/worktrees -maxdepth 1 -name 'agent-*' -mtime +2`; grove gc cat. 5 covers desktop |

D: has free space (~240G): for large-but-wanted data, **moving to /d is a
lower-risk alternative to deletion** — offer it.

## Existing tools — invoke, don't reinvent

| Tool | Covers |
|---|---|
| `grove gc [--dry-run\|--yes]` | Worktree sprawl: dead registry entries, expired `.scratch` ephemerals, stale agent worktrees, `git worktree prune`, merged+clean candidates |
| `scripts/purge-scratchpads.sh [days] [--yes]` (this skill) | /tmp/claude-1000 session dirs + loose /tmp litter, age-gated; dry-run by default (2026-08-27 run: 1,979 dirs + 12k loose files, ~22 GiB) |
| `scripts/fastscan.py` (this skill) | Fast native enumeration (scandir + MFT engines); `scripts/mkntfs.py` regenerates the MFT-parser test image |
| `~/bin/purge-stale-builds` | Stale motioncatalyst `BUILD*` dirs under /c/work (age-gated, `--dry-run`) |
| `~/bin/grove-gc-weekly.sh` | Scheduled Sunday grove GC — check it's still landing before manual work |
| `~/bin/agent-mail-prune.sh` | Agent-mail store pruning |
| `pm2 flush <app>` / pm2-logrotate | PM2 log growth |

## Safety rules

1. **Dry-run first, always.** Show what would be deleted + estimated reclaim
   before any destructive command. House pattern: age-gate + dry-run +
   freed-space report.
2. **Age-gate everything** (`-mtime +N`); never delete same-day files.
3. **Never delete uncommitted git state.** Before `grove done`/removing any
   worktree or clone: `git status --porcelain` clean AND branch merged/pushed
   (verify via PR state — squash merges defeat `git branch --merged`).
4. **Never touch live working dirs**: check `/proc/*/cwd` (and `fuser -v`)
   before removing a dir. Never remove the current session's own scratchpad.
5. **NEVER run `wsl --shutdown`** from agent context — it kills every WSL
   session on the machine including your own and all running agents.
   `wsl.exe -t <other-distro>` is fine.
6. **Never write/delete WSL rootfs files from the Windows side** — read-only
   scanning is fine; mutations corrupt WSL1 metadata.
7. **Don't double-count/delete through symlinks**: `~/.claude` IS
   `~/.dotfiles/.claude`; `~/.dotfiles` has tracked files throughout `~`.
   Corollary: `du -sb ~/.claude` reports 34 bytes (the link target string),
   not the ~15G tree — measure the target, and expect fastscan totals to
   exclude reparse points by design.
8. **Regenerable caches are fair game; data is not.** Session transcripts
   (`~/.claude/projects`, cass-indexed), agent-mail archive, `~/.cargo/bin`,
   anything under version control: report-only unless the user opts in.
9. **`wsl --unregister` is irreversible** — always: repoint default distro,
   audit bare-`wsl.exe` callers (Startup .vbs, scheduled tasks, launch
   scripts), inspect rootfs for unique data, THEN unregister.
10. **Ask before acting** on anything non-regenerable — one AskUserQuestion
    with the ranked candidates, not one prompt per item.
11. After cleanup, re-run `df -h /c` and report before/after and total freed.

## Output format

```
## Disk report — <date>
C: <used>/<total> (<pct>%), <free> free   [before]

| # | Target | Size | Category | Action | Risk |
|---|--------|------|----------|--------|------|

Freed this session: <N> GB  → C: now <pct>%, <free> free
Deferred (needs user): <list>
```
