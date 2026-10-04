---
name: agent-mail-ops
version: 1.0.0
description: |
  Operate and repair the local mcp-agent-mail service on this Linux desktop:
  the systemd user unit, the port, the storage root, and above all the SQLite database,
  which has a long history of going corrupt. Use when the user says "fix
  agent-mail", "agent-mail is down", "agent-mail is broken", when a session
  hook blocks because agent-mail is unreachable, or when you see "database
  disk image is malformed", "corruption circuit breaker open", "wrong # of
  entries in index", "am doctor", or "reconstruct-failed". For USING agent-mail
  as an agent (reservations, messages, inboxes) see the `agent-mail` skill;
  this skill owns the machine it runs on.
allowed-tools: [Bash, Read, AskUserQuestion]
---

# agent-mail operations (Linux desktop)

Scope: the service and its data on this machine. Using the mailbox as an agent
belongs to the `agent-mail` skill.

## The layout

| Thing | Where |
|---|---|
| Server binary | `~/.local/bin/am`, run as `am serve-http --no-tui --no-auth --port 4809` |
| Operator CLI | the same `am` binary |
| Supervisor | systemd user unit `agent-mail.service`, file `~/.dotfiles/.config/systemd/user/agent-mail.service` (symlinked into `~/.config/systemd/user/`) |
| Logs | `journalctl --user -u agent-mail.service` |
| Storage root | `/home/oystein/.mcp_agent_mail_git_mailbox_repo` (btrfs) |
| Memory cap | `MemoryMax=3G` in the unit. The server peaked at 1.89 GB in a 1-hour watch. Do not lower it (see "Why the database keeps corrupting"). |
| Restart limit | `StartLimitIntervalSec=600`, `StartLimitBurst=5`. After 5 failed starts in 10 minutes the unit stays failed. `systemctl --user reset-failed agent-mail` clears it. |
| Old storage root | `/c/users/oystein/.mcp_agent_mail_git_mailbox_repo`, retired 2026-09-15, kept as a backup |
| Endpoint | `http://127.0.0.1:4809/mcp/` (canonical) and `/api/` (legacy), localhost only, no bearer token |

Port 4809, not 8765: MotionCatalyst's Mobile Camera pairing service takes 8765,
and agent-mail sitting there stopped it from starting at all.

## Rule zero: never run `am doctor fix`

It rewrites all twelve MCP configs on this machine to port 8765 and adds bearer
tokens, which breaks the deliberate 4809 no-auth setup. Its `mcp_config` and
`mcp_config_token` warnings are the CLI wanting its own defaults back, not a
fault. `am doctor check` for diagnosis is fine and does not mutate.

## Two environment variables, and only one of them works

The **server** reads `STORAGE_ROOT`. The **CLI** reads `AGENT_MAIL_STORAGE_ROOT`.
Setting only the second one is silently ignored by the server, which will keep
writing to its default root while everything you inspect says otherwise. Both are
set, to the same value, in the unit file (`Environment=` lines) and
`~/.config/fish/conf.d/agent-mail.fish`. Change one, change the other.

After editing the unit file:

```bash
systemctl --user daemon-reload
systemctl --user restart agent-mail.service
```

## Doctor warnings that are not faults

The CLI defaults to port 8765; `HTTP_PORT=4809` points `am doctor check` at the
right one for a single run. With it, the four `server_*` checks pass.

`wal_mode`, `query_plan_hot_paths` and `timestamp_format` warnings that say
"skipped" are the read-only doctor declining to open the database in WAL mode. Check
`PRAGMA journal_mode` yourself instead of believing the warning.

## Triage

```bash
curl -s -m 10 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4809/health   # 200 = listening
systemctl --user status agent-mail.service --no-pager
HTTP_PORT=4809 am doctor check
```

Then call `health_check` over MCP. It is the only check that reports
`health_level` and the per-verdict breakdown, and a **red** `integrity_check`
verdict with a 200 from `/health` is the signature failure: reads work, writes do
not.

**A healthy endpoint does not mean a healthy service.** When the corruption circuit
breaker is open the server refuses every write but answers reads normally. The
visible damage is that `file_reservation_paths` returns without reserving anything,
so parallel agents lose all conflict protection while appearing to have it. Grep the
log for it:

```bash
journalctl --user -u agent-mail.service --since today | grep -cE "corruption circuit breaker open|malformed|desync"
```

**A restart loop fills the disk.** Each failed start puts a 38 MB rebuild in
`doctor/reclaimable/`, and the server never deletes that folder. From 2026-09-30 to
2026-10-04 a corrupt database caused 6420 restarts and 234 GiB of rebuilds. The
restart limit in the unit now stops this after 5 tries. If `doctor/` is large, check
`systemctl --user show -p NRestarts agent-mail.service` first.

## Database repair

Read the `integrity_check` output first and pick by damage type.

| Symptom | Repair |
|---|---|
| `wrong # of entries in index`, `row N missing from index` and nothing else | `REINDEX`. Table data is intact; this rebuilds indexes from it. Seconds. |
| `2nd reference to page N`, `cell extends past usable page size`, `Rowid out of order` | `sqlite3 .recover`. Page-level damage. Minutes. |

**Do not use `am doctor reconstruct`.** It rebuilds from the git archive, and the
rebuild itself is clean, but an acceptance gate rejects it and parks the output as
`storage.sqlite3.reconstruct-failed-<ts>.sqlite3`. It failed that way on three
consecutive days in September 2026 while the operator believed repair was running.
It also drops rows: one such output held 5040 messages against 5753 live.

On this CachyOS desktop `/usr/bin/sqlite3` (3.53) runs `.recover` directly.
**Ubuntu's `/usr/bin/sqlite3` cannot.** It links against the system libsqlite3,
which has no `sqlite_dbpage`, so you get `no such table: sqlite_dbpage` and it looks
like the database is beyond help. On Ubuntu, build a real CLI first:

```bash
~/.claude/skills/agent-mail-ops/scripts/build-sqlite-recover.sh   # prints the binary path
```

**`am-recover.sh` still stops and starts the service with pm2, which no longer
exists here. Until it is ported to `systemctl --user`, use the manual steps below.**
It stops the service, salvages, verifies and swaps:

```bash
~/.claude/skills/agent-mail-ops/scripts/am-recover.sh --dry-run   # always first
~/.claude/skills/agent-mail-ops/scripts/am-recover.sh
```

It refuses to touch anything until `am doctor drain` reports `safe_to_mutate=true`,
keeps the corrupt original as `storage.sqlite3.corrupt-<ts>`, and aborts if the
recovered database has fewer rows than the corrupt one.

### The manual steps

If the script does not fit the situation, the steps are: `systemctl --user stop agent-mail.service`,
confirm `am doctor drain` says `safe_to_mutate=true`, copy `storage.sqlite3` and its
`-wal` and `-shm` to scratch, `.recover` into a new file, check `integrity_check`,
`foreign_key_check` and row counts against the corrupt original, set
`journal_mode=WAL`, move the old database aside **together with every `-wal`, `-shm`
and `-wal-cert*` sidecar** (a stale sidecar left beside a new database is a fresh
corruption risk), copy the recovered file in, start.

**The server tells you whether it worked.** It refreshes `storage.sqlite3.bak` only
when the source passes its own integrity gate, so a fresh `.bak.meta.json` timestamp
after restart is real confirmation. A stale one means it is still refusing.

## Why the database keeps corrupting

The server does not use the C SQLite library. am 0.3.30 is built on fsqlite 0.3.8,
a Rust reimplementation, and its own writes are what break the file. The C
`sqlite3` tool is the trusted second opinion.

On 2026-10-04 the unit ran with `MemoryMax=512M` while the server needs about 1 GB.
A clean recovered database broke 2 seconds after the startup check passed. The
first write grew the file to page 9077 while the engine still saw 9076 pages, and
page 9077 read back as zeros. Nothing was killed: 0 restarts, no OOM, btrfs
reported 0 errors. On a copy, the same database stayed clean for 3.5 minutes
without the cap. With a 512M cap, the server's guard reported an index/table
desync (GH#214) within 9 seconds. That is one run each, so treat memory pressure
as the strongest lead, not a proof. Keep `MemoryMax=3G`.

Before 2026-09-15 the store lived on `/c` (drvfs under WSL1), and corruption was
blamed on drvfs locking and fsync. That machine is retired.

## Storage root moves

These steps and speeds come from the 2026-09-15 move across the WSL boundary.
Measured on the `projects/` tree of about 40,000 small files: `rsync` managed about
7 files a second, `tar` piped into `tar` about 130. A large single file copies at
roughly 130 MB/s. On btrfs, `cp -a --reflink=always` is near instant.

1. `tar -C <src> -cf - projects | tar -C <dst> -xf -` while the service is still
   running, and `rsync -a` for everything else. No downtime yet.
2. `systemctl --user stop agent-mail.service`, confirm `am doctor drain`.
3. `rsync -a --delete` delta pass. Seconds to a couple of minutes.
4. Run `integrity_check` on the copy. Repair it there if the last minutes of drvfs
   life damaged it.
5. Set `STORAGE_ROOT` **and** `AGENT_MAIL_STORAGE_ROOT` in the unit file and
   the fish conf.d file.
6. `systemctl --user daemon-reload`, then `systemctl --user start agent-mail.service`.
7. Confirm the log's `Active database ... storage_root=` line names the new path.
   This is the only trustworthy confirmation.
8. Leave the old root in place with a `RETIRED.md` marker.

Leave behind `backups/`, `doctor/` and every `storage.sqlite3.{corrupt,restoring,
reconstruct-failed,precorruption}-*` file. On the last move that was 1.4 GB of the
2.2 GB total.

## Clean restarts

Restarting or stopping `agent-mail.service` with the commands in this skill is the named exception to "never kill a process you did not start".

```bash
systemctl --user restart agent-mail.service   # graceful SIGTERM, then start
systemctl --user stop agent-mail.service      # before any repair
am doctor drain                               # must say safe_to_mutate before any repair
```

Never hard-kill the server. `systemctl stop` sends SIGTERM and waits (90 s by
default) so the server can checkpoint the WAL and release locks. A kill mid-write
is a likely way to create the corruption you are trying to fix.
