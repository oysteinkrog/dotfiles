# Secret Handling

## Rules

- keep tokens and passwords in env vars or locked-down files only
- use `chmod 600` on secret-bearing files
- never paste raw tokens into handoff docs or evidence packs
- run `scripts/scan-and-redact-migration-secrets.py` before sharing logs or configs
- revoke or rotate temporary export credentials after cutover

## High-Risk Secrets

- `xoxc-`, `xoxd-`, `xoxp-`, `xoxb-` tokens
- Mattermost admin passwords
- SMTP credentials
- R2 / S3 secrets
