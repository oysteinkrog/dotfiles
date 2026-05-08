Drive the full cutover-day sequence, pausing for operator go at each critical gate.

T-24h:
- Send the first user announcement (reference `references/comms/USER-COMMS-KIT.md`).
- Freeze Slack integrations (deactivate auto-posting bots).

T-1h:
- Run final Phase 1 delta export. Hashed, verified, ready.
- Re-run Phase 2 `./operate.sh intake` + `render-config` + `ready` with the final bundle.

T-15min:
- Make Slack read-only (admin UI).
- Confirm `./operate.sh ready` is STILL green on the final bundle.
- Wait for my explicit "go".

T=0:
- Run `prompts/cutover.md`.

T+cutover:
- Post the activation announcement.

T+1h:
- Monitor /opt/mattermost/logs/mattermost.log and the help desk.
- Check password-reset emails are actually landing (not SPF/DKIM/DMARC-blocked).

Between every phase, pause and wait for my confirmation. Do NOT chain through.
