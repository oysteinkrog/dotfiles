Run `./maintain.sh health` against the live Mattermost. When it finishes, read `workdir-phase3/reports/latest-health.json` and summarize:

- Overall status (ok / yellow / red)
- Any red or yellow checks and what they mean
- Disk usage on `/` and `/opt/mattermost`
- Postgres connection usage
- Mattermost log error rate in the last 5 min
- All service statuses (mattermost, nginx, postgresql, fail2ban, ufw)

If any check is red, tell me the likely cause and the next-best action. Don't take remediation actions without approval.
