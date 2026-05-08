# Slackdump Supplement Workflow

Use this when:
- the workspace is on Pro or Free
- you need gap-filling beyond the official export
- you need file downloads from conversations the authenticated account can access

## What Slackdump Is Good At

- exporting what the authenticated account can actually see
- downloading file binaries with `-files`
- capturing personal/private scope that the operator account has access to
- creating Mattermost-shaped archives quickly

## What It Cannot Promise

- org-wide private-channel completeness
- other people's DMs
- safe invisibility in Enterprise environments
- compliance-grade completeness comparable to approved official all-conversations export

## Workflow

1. Authenticate with browser flow or `xoxc-` + `xoxd-`.
2. Run a small smoke-test export first.
3. Scope by channel/date only if you understand the gap tradeoff.
4. Export with files when preservation matters.
5. Hash the output ZIP and record the operator account used.
6. If an official export also exists, treat `slackdump` output as supplement, not replacement.

## Recommended Commands

```bash
./tools/slackdump auth test
./tools/slackdump export -o artifacts/raw/slackdump-export.zip -files
```

For targeted gap-fill:

```bash
./tools/slackdump export -o artifacts/raw/slackdump-gapfill.zip -files C0123456789
```

## Merge Policy

- never merge `slackdump` data into the official ZIP blindly
- use it to recover files, public channels, or explicitly scoped missing conversations
- document every gap-fill in the manifest and verification report

## Required Warning

If `slackdump` is primary, write this into the report:

> Completeness is bounded by what the authenticated account can see in Slack.
