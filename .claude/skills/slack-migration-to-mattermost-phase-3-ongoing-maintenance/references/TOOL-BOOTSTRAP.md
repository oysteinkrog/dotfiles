# Tool Bootstrap

`./scripts/bootstrap-tools.sh` does this automatically; this doc is the
manual fallback and the reference for what's installed and why.

## What Phase 3 needs on the workstation

| Tool | Purpose | Install via |
|------|---------|-------------|
| `ssh`, `scp`, `rsync` | Talk to target host | OS default (Mac, Linux) or OpenSSH on Windows |
| `jq` | Parse JSON reports | `brew install jq` / `apt install jq` |
| `curl` | HTTP probes | OS default |
| `psql`, `pg_dump`, `pg_restore` | PostgreSQL client | `brew install libpq` / `apt install postgresql-client` |
| `mmctl` | Mattermost admin CLI | `go install github.com/mattermost/mmctl@latest` or release binary |
| `rclone` | Off-site backup transport | `brew install rclone` / `apt install rclone` |
| `python3` + `requests` | Helper scripts | OS default + `pip install --user requests` |
| `go` | Builds `mmctl` on demand | `brew install go` / `apt install golang-go` |

## What Phase 3 needs on the target host

Nothing new to install; Phase 2's `provision` stage put all of this in place.
Phase 3 verifies:

- `pg_dump` (via local `postgres` user)
- `apt-get`, `unattended-upgrade`, `shutdown`, `at` (`at` is auto-installed by `schedule-reboot.sh` on first use)
- `rclone` (for off-site backup uploads; auto-installed by `db-backup.sh` if missing)
- `systemctl` controls for `mattermost`, `nginx`, `postgresql`, `fail2ban`, `ufw`

## Per-platform notes

### macOS

- Uses Homebrew. `libpq` is keg-only so `psql` is not on PATH by default;
  add `export PATH="$(brew --prefix)/opt/libpq/bin:$PATH"` to your shell rc.
- `mmctl` is not in Homebrew as of April 2026; built via `go install`.

### Debian / Ubuntu / WSL Ubuntu

- `sudo apt-get install postgresql-client rclone jq python3-requests` gets
  most of what's needed.
- `mmctl` built via `go install` or downloaded from
  [mattermost/mmctl releases](https://github.com/mattermost/mmctl/releases).

### Windows (native PowerShell)

- Ships OpenSSH on Windows 10 1809+ / 11.
- Install `psql` via
  [EDB PostgreSQL installer](https://www.postgresql.org/download/windows/)
  or use WSL2 Ubuntu for the full toolchain.
- Chocolatey works for `jq`, `rclone`, `golang`, `python3`.

### WSL2 on Windows

Treat as Ubuntu. `mmctl` via `go install`. SSH keys in
`~/.ssh/` in WSL map to `%USERPROFILE%\.ssh` in Windows if you symlink them;
simpler is to generate a new keypair inside WSL.

## Verification

```bash
./scripts/doctor.sh                       # tool + config completeness
./scripts/doctor.sh --require-remote      # + SSH + MM ping + PAT
./scripts/doctor.sh --require-mcp         # + MCP registration
```

All three green means the workstation is ready. See
[MATTERMOST-MCP-SETUP.md](MATTERMOST-MCP-SETUP.md) for the MCP registration
step.
