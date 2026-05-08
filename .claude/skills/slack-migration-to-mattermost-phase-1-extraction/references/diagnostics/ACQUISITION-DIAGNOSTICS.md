# Acquisition Diagnostics

Use these when the failure is before enrichment.

## Official Export Never Arrives

Check:
- wrong plan tier or missing all-conversations approval
- mailbox filtering or spam
- export page already shows download link even without email
- admin account lacks owner-level permissions

## Channel-Audit CSV Missing

Check:
- same admin area as export ZIP
- workspace/org permissions
- UI changed and the automation missed the secondary download

If you cannot obtain it, write that down as a verification handicap.

## Hash Mismatch

If a file hash changes unexpectedly:
- stop treating it as the same artifact
- store both copies separately
- write a note explaining which copy is authoritative

## Slackdump Authentication Fails

Check:
- `xoxc-` token paired with `xoxd-` cookie
- session not expired
- interactive browser path still works
- enterprise security controls did not invalidate the session

## Export Looks Too Small

Likely causes:
- plan only allows public channels
- narrow date range
- operator account lacks membership in the conversations you expected
