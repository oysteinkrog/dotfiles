# Secret Handling

## Rules

- keep admin, SMTP, database, and storage secrets out of logs and screenshots
- prefer env vars or secret stores over copying credentials into ad hoc notes
- validate and redact before sharing war-room evidence externally
- rotate temporary or elevated credentials after cutover stabilizes

## High-Risk Secrets

- Mattermost admin credentials
- SMTP passwords
- PostgreSQL connection strings
- Cloudflare / R2 credentials
- personal access tokens
