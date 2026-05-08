# Mattermost + Playwright MCP for Phase 2

Wire two MCP servers into Claude Code / Codex so the agent can:

- hit the running Mattermost REST API directly (list teams, count users, probe
  permissions, stamp test posts, fetch plugin state) via the **Mattermost MCP**
- click through System Console screens that don't have clean API equivalents
  (plugin installs, enterprise-only toggles) via the **Playwright MCP**

## Install

```bash
# Create a system-admin Personal Access Token first:
#   System Console -> Integrations -> Personal Access Tokens
#   (toggle EnableUserAccessTokens=true for an admin account, then issue one)
# Put the token into config.env as MATTERMOST_ADMIN_TOKEN.

./scripts/install-mcp-servers.sh                       # both servers
./scripts/install-mcp-servers.sh --include mattermost  # API-only
./scripts/install-mcp-servers.sh --include playwright  # UI-only
```

## Which Tool For Which Step

| Phase 2 stage | Agent surface | Why |
|---------------|---------------|-----|
| intake / render-config | none required | deterministic JSON work |
| provision / deploy | SSH (via `operate.sh`) | direct server actions, no MCP needed |
| verify-live | Mattermost MCP (optional) | sanity-check `/api/v4/system/ping` from the agent POV |
| staging rehearsal | Mattermost MCP | stamp + fetch test messages, cross-check import counts |
| readiness / cutover | Mattermost MCP | sample channels post-import without writing custom code |
| plugin install (Calls, Playbooks) | Playwright MCP | System Console upload flow |
| activation assist | Mattermost MCP | probe `users.list`, issue temporary PATs, etc. |
| post-cutover ops | Mattermost MCP | ongoing admin tasks without re-auth |

## Sample Prompts

```
Use the Mattermost MCP to:
1. Count the number of channels in team "acme" — should be ≥ <handoff.counts.channels>.
2. Fetch the last post in each of these 5 random channels and print the ts + username.
3. Confirm that my test email's user is active and has the "System User" role.
```

```
Use the Playwright MCP to open https://chat.acme.com/admin_console/site_config/messaging
and screenshot the MaxPostSize value. If it shows 4000, set it to 16383 and save.
```

## Safety Rules

- Never paste the admin PAT into Claude's text output. The MCP wrapper reads it
  from `config.env`; treat the token like any other secret.
- Register MCP servers per-workstation, never commit their config.
- Revoke the PAT immediately after cutover is accepted — or at most 7 days
  later. See `playbooks/TOKEN-HANDLING.md`.

## Failure Modes

- `invalid token`: PAT expired or user role downgraded; re-mint.
- `CORS blocked`: the MCP server is calling `MATTERMOST_URL` from outside the
  trusted origins list; add the MCP origin to `ServiceSettings.AllowCorsFrom`
  for staging only.
- Playwright launches but the System Console refuses login: MFA likely
  enforced; disable MFA for the admin account temporarily or create a dedicated
  automation admin without MFA for the rehearsal window.
