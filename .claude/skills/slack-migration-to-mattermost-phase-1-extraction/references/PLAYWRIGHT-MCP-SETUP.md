# Playwright MCP for Phase 1

Drive the Slack admin export UI from Claude Code / Codex without hand-writing a
Playwright script. The official Microsoft Playwright MCP server exposes a
browser-automation surface (navigate, click, fill, screenshot, extract text)
that agents can drive while the operator watches.

## Install

```bash
./scripts/install-mcp-servers.sh --include playwright
# or manually:
claude mcp add playwright -- npx -y @playwright/mcp@latest
codex mcp add playwright --  npx -y @playwright/mcp@latest
```

First launch downloads Chromium via Playwright. If you already have a logged-in
Slack browser session (`app.slack.com` cookies), point the MCP server at that
profile so the admin export page is already authenticated:

```bash
# Claude Code variant — pin to your default profile
claude mcp add playwright \
  -e PLAYWRIGHT_USER_DATA_DIR="$HOME/.cache/ms-playwright/phase1" \
  -- npx -y @playwright/mcp@latest --user-data-dir "$HOME/.cache/ms-playwright/phase1"
```

## When This Beats `automate-official-export.py`

| Scenario | Use |
|----------|-----|
| You have a one-shot migration and want Claude to click through the admin UI visibly | Playwright MCP |
| The admin UI has A/B changes or unusual selectors | Playwright MCP (agent adapts) |
| Recurring exports, headless, no human | `scripts/automate-official-export.py` (stable, auditable) |
| Mailbox polling required | `automate-official-export.py --imap-host ...` |
| Agent needs to take a screenshot of a failure | Playwright MCP |

## Exact Prompt to Drive the Export

Paste this after the Playwright MCP is registered and the operator confirms
they want Claude to click through the admin UI:

```
Use the Playwright MCP to:
1. Open https://<workspace>.slack.com/admin/settings#data_retention_policy
   and confirm my session is already authenticated; if not, stop and ask me
   to log in.
2. Navigate to Workspace settings → Security → Import & export data → Export.
3. Select the whole-history date range (or the range I name).
4. Click Start Export. Take a screenshot.
5. Wait for the confirmation modal and capture the text.
6. Stop. Do NOT try to poll for the ready email; that is the job of
   scripts/automate-official-export.py with --imap-host / --mailbox-dir.
```

The browser path is a *trigger only*. The artifact hash + manifest step still
belongs to `scripts/intake-official-export.py` or `scripts/automate-official-export.py`.

## Capturing the Download Link

Once Slack emails the export-ready URL, either:

1. Paste the URL manually into `config.env` as `SLACK_EXPORT_ZIP_URL` and run
   `./migrate.sh export` (which will curl + hash it via
   `automate-official-export.py --mailbox-dir`).
2. Or: give Claude the URL from the email and ask the Playwright MCP to
   download the ZIP into `workdir/artifacts/raw/`. Follow with
   `scripts/intake-official-export.py` to hash + manifest it.

## Rehearsing Without a Real Slack Admin

`scripts/serve-official-export-fixture.py` exposes a mock export page on
`localhost`. Agents can exercise the Playwright MCP against that fixture to
validate the runbook before touching real Slack.

```bash
python3 scripts/serve-official-export-fixture.py --port 9125 &
# ... then in Claude Code, ask Playwright MCP to open http://localhost:9125/
#     and click the "Start Export" button.
```

## Safety Rules

- Never paste the `xoxc-` session token into a Playwright script. Authenticate
  via the persisted browser profile instead, and let Slack's own cookie flow
  handle auth.
- Always screenshot the final confirmation modal. The screenshot goes into the
  evidence pack (`build-migration-evidence-pack.py`) so provenance is
  auditable months later.
- Rate-limit: trigger at most one export per 24 h; Slack silently deduplicates
  within that window.
- When the rehearsal is done, remove the profile cache (`rm -rf
  "$PLAYWRIGHT_USER_DATA_DIR"`) before the machine changes hands.
