---
name: agent-mail-ops
version: 1.0.0
description: |
  Operate and repair the local mcp-agent-mail service on this WSL1 machine:
  the pm2 unit, the port, the storage root, and above all the SQLite database,
  which has a long history of going corrupt. Use when the user says "fix
  agent-mail", "agent-mail is down", "agent-mail is broken", when a session
  hook blocks because agent-mail is unreachable, or when you see "database
  disk image is malformed", "corruption circuit breaker open", "wrong # of
  entries in index", "am doctor", or "reconstruct-failed". For USING agent-mail
  as an agent (reservations, messages, inboxes) see the `agent-mail` skill;
  this skill owns the machine it runs on.
allowed-tools: [Bash, Read, AskUserQuestion]
---

# agent-mail operations (WSL1 desktop)

Scope: the service and its data on this machine. Using the mailbox as an agent
belongs to the `agent-mail` skill.

## The layout

| Thing | Where |
|---|---|
| Server binary | `~/.local/bin/am`, run as `am serve-http --no-tui --no-auth --port 4809` |
| Operator CLI | the same `am` binary |
| Supervisor | pm2 unit `mcp-agent-mail`, defined in `~/.config/pm2/ecosystem.config.js` |
| Logs | `~/.config/pm2/logs/mcp-agent-mail-error.log` (this is where everything lands, not `~/.pm2/logs`) |
| Storage root | `/home/oystein/.mcp_agent_mail_git_mailbox_repo` (wslfs) |
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
set, to the same value, in `~/.config/pm2/ecosystem.config.js` and
`~/.config/fish/conf.d/agent-mail.fish`. Change one, change the other.

`pm2 restart` does **not** pick up a changed ecosystem env. Use:

```bash
pm2 delete mcp-agent-mail
pm2 start ~/.config/pm2/ecosystem.config.js --only mcp-agent-mail
pm2 save
```

## Four warnings that are permanent WSL1 artifacts, not faults

`server_port`, `server_process_cpu`, `server_http_health`, `server_jsonrpc_health`
all report no listener. WSL1 does not list sockets in `/proc/net/tcp`, so `ss` and
the doctor probe see nothing even while `curl http://127.0.0.1:4809/health` returns
200. Trust curl, not the probe. The CLI also defaults to port 8765; `HTTP_PORT=4809`
points it at the right one for a single run.

`wal_mode`, `query_plan_hot_paths` and `timestamp_format` warnings that say
"skipped" are the read-only doctor declining to open the database in WAL mode. Check
`PRAGMA journal_mode` yourself instead of believing the warning.

The Tantivy index cannot build on WSL1 (`os error 22`), so `search_messages` is
degraded and `AM_SEARCH_ENGINE=lexical` is set. Messaging and reservations are
unaffected. Do not try to fix this.

## Triage

```bash
curl -s -m 10 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4809/health   # 200 = listening
pm2 list | grep agent-mail
am doctor check                      # ignore the four server_* warnings
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
grep -c "corruption circuit breaker open" ~/.config/pm2/logs/mcp-agent-mail-error.log
```

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

**Ubuntu's `/usr/bin/sqlite3` cannot run `.recover`.** It links against the system
libsqlite3, which has no `sqlite_dbpage`, so you get `no such table: sqlite_dbpage`
and it looks like the database is beyond help. Build a real CLI first:

```bash
~/.claude/skills/agent-mail-ops/scripts/build-sqlite-recover.sh   # prints the binary path
```

Then run the repair, which stops the service, salvages, verifies and swaps:

```bash
~/.claude/skills/agent-mail-ops/scripts/am-recover.sh --dry-run   # always first
~/.claude/skills/agent-mail-ops/scripts/am-recover.sh
```

It refuses to touch anything until `am doctor drain` reports `safe_to_mutate=true`,
keeps the corrupt original as `storage.sqlite3.corrupt-<ts>`, and aborts if the
recovered database has fewer rows than the corrupt one.

### The manual steps

If the script does not fit the situation, the steps are: `pm2 stop mcp-agent-mail`,
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

It lived on `/c`, which is drvfs, the Windows drive seen from WSL1. SQLite in WAL
mode on drvfs does not get the file locking and fsync behaviour it needs. The log
carried malformed-page warnings on nearly every day from 2026-08-25, and on
2026-09-15 a verified clean database corrupted again within eleven minutes of the
repair. That is why the store now lives on `/` (wslfs), which has proper POSIX
semantics.

If corruption starts recurring on wslfs too, that theory is wrong and the next
suspects are the pm2 `max_memory_restart: "2G"` cap killing the process mid-write,
and the custom fsqlite layer (the `-fsqlite-ns-*` and `-wal-cert*` sidecars).

One consequence of wslfs: Windows tools cannot reach the store, so no Windows
indexer or antivirus touches the database, but a Windows-side backup will not see
it either.

## Storage root moves

Copy speed across the WSL boundary decides the plan. Measured on the `projects/`
tree of about 40,000 small files: `rsync` managed about 7 files a second, `tar`
piped into `tar` about 130. A large single file copies at roughly 130 MB/s.

1. `tar -C <src> -cf - projects | tar -C <dst> -xf -` while the service is still
   running, and `rsync -a` for everything else. No downtime yet.
2. `pm2 stop mcp-agent-mail`, confirm `am doctor drain`.
3. `rsync -a --delete` delta pass. Seconds to a couple of minutes.
4. Run `integrity_check` on the copy. Repair it there if the last minutes of drvfs
   life damaged it.
5. Set `STORAGE_ROOT` **and** `AGENT_MAIL_STORAGE_ROOT` in the ecosystem file and
   the fish conf.d file.
6. `pm2 delete` and `pm2 start <ecosystem> --only`, then `pm2 save`.
7. Confirm the log's `Active database ... storage_root=` line names the new path.
   This is the only trustworthy confirmation.
8. Leave the old root in place with a `RETIRED.md` marker.

Leave behind `backups/`, `doctor/` and every `storage.sqlite3.{corrupt,restoring,
reconstruct-failed,precorruption}-*` file. On the last move that was 1.4 GB of the
2.2 GB total.

## Clean restarts

Restarting the pm2-managed `mcp-agent-mail` service with the commands in this skill is the named exception to "never kill a process you did not start".

```bash
pm2 restart mcp-agent-mail && pm2 save      # no env change
am doctor drain                              # must say safe_to_mutate before any repair
```

Never hard-kill the server. `kill_timeout` is 30s specifically so SQLite can
checkpoint the WAL and release locks. A kill mid-write is a plausible way to create
the corruption you are trying to fix.
