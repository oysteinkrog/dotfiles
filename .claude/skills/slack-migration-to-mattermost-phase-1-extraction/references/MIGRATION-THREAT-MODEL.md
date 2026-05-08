# Phase 1 Migration Threat Model

## Sensitive Assets

- Slack session tokens and cookies
- raw export ZIPs
- member directory CSVs
- admin sidecar exports
- enriched ZIPs with downloaded files

## Likely Failure Modes

- exporting more than policy allows
- leaking tokens through history, logs, or shared notes
- mixing multiple workspaces in one artifact tree
- silently dropping files, emoji, or sidecars

## Required Countermoves

- legal/compliance gate before export
- quarantine and hash every stage
- scan/redact evidence before sharing
- classify every important gap explicitly
