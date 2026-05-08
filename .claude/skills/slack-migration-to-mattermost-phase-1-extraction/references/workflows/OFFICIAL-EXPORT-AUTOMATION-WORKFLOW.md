# Official Export Automation Workflow

Use this when the workspace has Business+ or Enterprise permissions for all-conversations export.

## Goal

Automate the documented Slack admin flow without pretending there is a hidden export API.

## Components

- dedicated Slack owner/admin service account
- dedicated mailbox for export notifications
- browser automation worker
- mailbox poller
- artifact storage directory with manifests

## Workflow

1. Log in with the dedicated admin account.
2. Navigate to Slack admin export UI.
3. Trigger the export for the desired scope or date range.
4. Poll the mailbox for Slack's export-ready email.
5. Return to the export page and download:
   - export ZIP
   - channel-audit CSV
6. Hash both files and write `manifest.raw.json`.
7. Move artifacts into `artifacts/raw/`.

## Browser Automation Notes

- Use Playwright or browser automation only for UI steps.
- Keep selectors resilient: prefer visible text, stable labels, or `data-qa` attributes when present.
- Record screenshots on failures because Slack admin UI changes.
- Keep a manual fallback path in the runbook.

## Mailbox Poller Notes

- Poll every 2-5 minutes.
- Filter on Slack sender and subject patterns for export-ready mail.
- Treat missing email as ambiguous, not fatal: the export page may already show the download link.

## Scheduling Pattern

For recurring exports:
- enable scheduled all-conversations export when plan tier allows it
- store each delta ZIP separately
- process each delta through the same enrichment and transform pipeline

## Artifact Rules

- never overwrite a prior raw ZIP
- always store the channel-audit CSV beside the ZIP
- every acquisition run writes a manifest and short operator note

## Success Criteria

- ZIP downloaded
- channel-audit CSV downloaded
- both hashed
- manifest written
- source account and date range recorded
