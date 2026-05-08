# Phase 1 Tool Bootstrap Reference

Operator-workstation bootstrap for the extraction pipeline. Runs on any Mac,
Windows (PowerShell/WSL), or Linux box where the user already has a Slack
session available (Slack desktop or browser).

## One-Shot

```bash
./scripts/bootstrap-tools.sh        # detect platform + install
./scripts/install-mcp-servers.sh    # wire Slack + Playwright MCP into Claude / Codex
./scripts/doctor.sh                 # required items OK?  exit 0
./scripts/doctor.sh --require-mcp   # additionally verify MCP servers are registered
```

`bootstrap-tools.sh` is idempotent. Re-run after adding a credential or switching
from slackdump to official export.

## Platform Matrix

| Tool | Purpose | macOS (Homebrew) | Ubuntu / Debian / WSL (apt) | Windows (PowerShell) |
|------|---------|------------------|-----------------------------|----------------------|
| python3 | scripts | `brew install python@3.12` | `apt install python3` | `choco install python3` |
| jq | JSON munging | `brew install jq` | `apt install jq` | `choco install jq` |
| zip / unzip | archive handling | `brew install zip unzip` | `apt install zip unzip` | builtin |
| curl | HTTP / downloads | preinstalled | `apt install curl` | builtin |
| sha256sum / shasum | hashing | `brew install coreutils` | preinstalled | `Get-FileHash` (native) |
| go | build migration tools from source | `brew install go` | `apt install golang-go` | `choco install golang` |
| slackdump | Slack extraction | `go install github.com/rusq/slackdump/v3/cmd/slackdump@latest` | same | grab release zip |
| slack-advanced-exporter | email/file enrichment | `go install github.com/grundleborg/slack-advanced-exporter@latest` | same | grab release zip |
| mmetl | Slack -> Mattermost JSONL | `go install github.com/mattermost/mmetl@latest` | same | release zip |
| mmctl | import upload + process | `go install github.com/mattermost/mmctl/v6@latest` | `apt install mattermost-mmctl` | release zip |
| requests, beautifulsoup4 | `automate-official-export.py` | `pip install --user requests beautifulsoup4` | same | same |
| node + npx | MCP servers | `brew install node` | `apt install nodejs npm` or `nvm install --lts` | `choco install nodejs-lts` |
| claude / codex CLI | agent host | `brew install claude` (or per Anthropic docs) | download from anthropic.com | same |

Everything the Go-based installers land at ends up under `$(go env GOPATH)/bin`.
If `go install` succeeded but the binary is not on `PATH`, add `$(go env GOPATH)/bin`
to your shell init (`~/.zshrc`, `~/.bashrc`, or PowerShell profile).

## What `doctor.sh` Actually Checks

| Check | Required? | Remediation |
|-------|-----------|-------------|
| `python3`, `jq`, `zip`, `unzip`, `curl`, `sha256sum` on PATH | yes | `./scripts/bootstrap-tools.sh` |
| Python modules `requests`, `bs4` | yes (for official-export automation + intake scripts) | `pip install --user requests beautifulsoup4` |
| `slackdump`, `slack-advanced-exporter`, `mmetl`, `mmctl` | yes for the stages that use them | `bootstrap-tools.sh` or manual release download |
| `SLACK_EXPORT_ZIP` or `SLACK_TOKEN`/`SLACK_COOKIE` | one of the two | obtain via admin export email or `AUTHENTICATION.md` |
| 20 GiB free on `$PHASE1_WORKSPACE_ROOT` | warn | prune old workdirs or point `PHASE1_WORKSPACE_ROOT` at a larger disk |
| Claude / Codex MCP servers (`--require-mcp`) | optional | `./scripts/install-mcp-servers.sh` |

`doctor.sh --json` emits a machine-readable summary so agents can gate on it.

## Secrets Hygiene

`config.env` holds the Slack token, cookie, and optional Cloudflare / IMAP
credentials. It must never be committed. Add a top-level `.gitignore` entry for
`config.env` before running any export. `scan-and-redact-migration-secrets.py`
is a second line of defense; the first line is keeping the file out of git.
See [playbooks/TOKEN-HANDLING.md](playbooks/TOKEN-HANDLING.md).

## Skipping Bootstrap

If you already have the tools installed and just want to verify, run
`doctor.sh` directly. `bootstrap-tools.sh --print-plan` emits every action it
would take so you can review before executing.
