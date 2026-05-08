# Phase 2 Handoff Contract

Phase 2 should receive a clean import-ready bundle plus enough evidence to trust it.
This contract now has **two forms**:

- a human-readable `reports/handoff.md`
- a machine-readable `reports/handoff.json`

Use `references/specs/CROSS-PHASE-INTAKE-CONTRACT.md` for the JSON contract.

## Required Handoff Items

- Final `mattermost-bulk-import.zip`
- `mattermost_import.jsonl` if Phase 2 wants to inspect or patch further
- all manifest files
- machine-readable `handoff.json`
- verification report
- unresolved gap report
- channel-audit CSV
- emoji manifest
- notes on sidecar archive channels and what they contain

## Handoff Summary Template

```markdown
# Handoff Summary

- Workspace: `acme-slack`
- Export basis: official Slack export + enrichment
- Plan tier: Business+
- Scope: full history through 2026-04-15
- Final package: `import-ready/mattermost-bulk-import-2026-04-15.zip`
- Hash: `sha256:...`

## Counts
- Users:
- Channels:
- DMs / group DMs:
- Posts:
- Attachments:
- Emoji:
- Sidecar artifacts:

## Required Phase 2 Settings
- Team must already exist
- Email sign-in enabled during import
- `Allow any user with an account on this server to join this team`
- `MaxPostSize` raised if oversized Slack posts exist

## Known Gaps
- Slack Connect external-org messages may be partial
- Bookmarks / workflows / app integrations not importable

## Sidecar Channels Injected
- `slack-canvases-archive`
- `slack-lists-archive`
- `slack-export-admin`
```

## Handoff Quality Bar

Phase 2 should not have to ask:
- which ZIP is authoritative
- whether files were actually downloaded
- whether emoji were preserved
- what sidecar archives exist
- which gaps are expected versus unexpected
- whether the final ZIP hash is authoritative
- whether the bundle passed semantic JSONL validation
- whether the migration is in a branch-safe state for staging or cutover
