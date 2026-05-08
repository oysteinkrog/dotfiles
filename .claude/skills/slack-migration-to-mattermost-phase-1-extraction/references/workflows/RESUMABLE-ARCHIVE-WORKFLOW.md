# Resumable Archive Workflow

Use this when `slackdump export` is too blunt for a large workspace or when you need resumability.

## Why This Exists

The `slackdump` docs recommend **archive** mode as the default for large or incremental work because it is resumable and later convertible into export format.

That makes this workflow useful for:
- very large workspaces
- repeated delta harvesting on Pro/Free
- interrupted exports
- situations where you want dedupe/cleanup before producing the final ZIP

## Workflow

1. Create or resume an archive database.
2. Let `slackdump` collect data incrementally.
3. Resume as needed after failures or token expiry.
4. Run cleanup/dedupe if overlap occurred.
5. Convert the archive into Mattermost export format.
6. Feed that export into the normal Phase 1 transform/patch/package flow.

## Commands

```bash
# Initial archive
slackdump archive -channel-users -o slackdump.sqlite

# Resume later
slackdump resume slackdump.sqlite

# Optional dedupe/cleanup tools
slackdump tools dedupe slackdump.sqlite
slackdump tools cleanup

# Convert archive to Mattermost export ZIP
slackdump convert -f export slackdump.sqlite
```

## When To Prefer This

Prefer archive/resume over plain export when:
- the workspace is large enough that repeated restarts are painful
- the authenticated session may expire mid-run
- you need a recoverable intermediate state

## Constraints

- this does not remove the visibility limits of the authenticated account
- for Business+ / Enterprise official exports, this remains a supplement or fallback, not the main source of truth

## Deliverables

- archive database or archive artifact
- converted export ZIP
- notes on any resume/dedupe operations performed
- updated manifest describing the provenance chain
