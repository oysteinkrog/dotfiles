# Reconciliation Diagnostics

Use these when the pipeline "succeeds" but trust is still low.

## Count Mismatches

Compare:
- channel count versus channel-audit CSV
- user count versus `users.json`
- message/post count versus sampled conversation totals
- attachment count versus file references

A mismatch is only acceptable if it is explained in writing.

## Slack Connect Boundary

If shared channels appear partial:
- verify whether external-org content is governed by the other org's retention/export rules
- classify as expected limitation, not transform bug

## Thread / Reaction Sampling

Sample:
- heavily threaded channels
- channels with many file uploads
- private channels
- DMs / group DMs where allowed

If threads collapse or reactions disappear, classify by source:
- absent in export
- lost in transform
- lost in patch/package

## Gap Report Template

```markdown
## Known Gaps
- Slack Connect content from external org may be partial.
- 17 deleted file links were unrecoverable.
- 4 users lacked email even after enrichment.
- Bookmarks and workflows are not importable and require manual recreation.
```

## Final Rule

Never sign off with "looks good" alone. Sign off with:
- what was verified
- what remains uncertain
- why the uncertainty exists
