# Phase 2 Tool Bootstrap Reference

Operator-workstation bootstrap for running Phase 2. Phase 2 orchestrates a
remote Ubuntu Mattermost host from your Mac / Windows / Linux workstation
via SSH; this doc is about the workstation side only. Host provisioning is
handled by `./operate.sh provision`.

## One-Shot

```bash
./scripts/doctor.sh                       # health check (required items only)
./scripts/doctor.sh --require-remote      # additionally probe SSH to TARGET_HOST
./scripts/bootstrap-tools.sh              # install mmctl, jq, psql, etc.
./scripts/install-mcp-servers.sh          # Mattermost + Playwright MCP wiring
./scripts/doctor.sh --require-mcp         # verify MCP registration
```

## Platform Matrix

| Tool | Purpose | macOS (brew) | Ubuntu/Debian/WSL | Windows PowerShell |
|------|---------|--------------|-------------------|---------------------|
| python3 | validators + report generators | `brew install python@3.12` | `apt install python3` | `choco install python3` |
| jq | JSON munging | `brew install jq` | `apt install jq` | `choco install jq` |
| curl | Mattermost probes | preinstalled | preinstalled | builtin |
| ssh / scp / rsync | remote Mattermost ops | preinstalled | `apt install openssh-client rsync` | `choco install openssh` |
| psql | DB-side smoke + reconciliation | `brew install libpq` (add to PATH) | `apt install postgresql-client` | `choco install postgresql` |
| openssl | TLS / Cloudflare Origin CA handling | preinstalled | preinstalled | builtin |
| go | build mmctl from source if no release binary | `brew install go` | `apt install golang-go` | `choco install golang` |
| mmctl | Mattermost CLI client | `go install github.com/mattermost/mmctl/v6@latest` | same | release zip |
| requests (Python) | HTTP checks | `pip install --user requests` | same | same |
| node + npx | MCP servers | `brew install node` | `apt install nodejs npm` | `choco install nodejs-lts` |
| claude / codex | agent hosts | per vendor docs | same | same |

If the remote host is not reachable from your workstation's `psql`, set
`TARGET_HOST` + `TARGET_SSH_USER` + `ENABLE_LOCAL_MODE=1`. `operate.sh` will
then materialize an SSH-backed `mmctl --local` wrapper and route `psql`
through the remote host automatically.

## What `doctor.sh` Actually Checks

| Check | Required? | Remediation |
|-------|-----------|-------------|
| `python3`, `jq`, `curl` on PATH | yes | `./scripts/bootstrap-tools.sh` |
| `requests` importable | yes | `pip install --user requests` |
| `mmctl` locally OR SSH-backed via `TARGET_HOST` + `ENABLE_LOCAL_MODE=1` | yes | bootstrap-tools or set the env vars |
| `HANDOFF_JSON` file exists | yes | receive from Phase 1 operator |
| `MATTERMOST_URL`, admin creds | yes | edit `config.env` |
| a DB DSN of some shape | yes | `POSTGRES_DSN` / `SMOKE_DATABASE_URL` / `DATABASE_URL` |
| SSH reachability (`--require-remote`) | when `DEPLOY_MODE=ssh` | install ssh key on `TARGET_HOST`; confirm with `ssh -o BatchMode=yes` |
| MCP servers (`--require-mcp`) | optional | `./scripts/install-mcp-servers.sh` |

## Secrets Hygiene

`config.env` carries admin credentials, SMTP passwords, Cloudflare tokens, and
PostgreSQL DSNs. It must never be committed. Add `config.env` to a top-level
`.gitignore` before your first run. Rotate all tokens after cutover completes
(see `playbooks/TOKEN-HANDLING.md`).
