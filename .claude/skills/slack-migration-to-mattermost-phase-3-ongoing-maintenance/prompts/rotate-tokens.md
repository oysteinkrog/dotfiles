Rotate Phase 3 credentials on their cadence. Review
[references/playbooks/TOKEN-HANDLING.md](../references/playbooks/TOKEN-HANDLING.md) first.

Walk me through the rotation of ONE of these (I'll tell you which):

- Mattermost admin PAT (quarterly — 90 days)
- `mmuser` Postgres password (semi-annual — 180 days)
- SSH keypair (annual)
- `OFFSITE_REMOTE` credentials (annual)
- Cloudflare API token (annual)
- Postmark server token (annual)

Procedure:

1. Confirm `ROLLBACK_OWNER` set and available.
2. Create new credential via provider UI. Pause for me to complete this.
3. Test new credential works (e.g. `curl -H "Authorization: Bearer $NEW_TOKEN" .../users/me`).
4. Update `config.env` atomically (backup to `.bak.<ts>` first).
5. Run `./scripts/doctor.sh --require-remote --require-mcp`. All green.
6. Revoke old credential in provider UI. Pause for me to complete.
7. Verify old credential is dead (same test should now 401/403).
8. Append to `workdir-phase3/rotate-credentials-audit.json` with my name,
   timestamp, reason, and confirmation that old was revoked.

If any step fails: STOP. Don't proceed to revoke the old credential with
unverified new one; we'd lock ourselves out.
