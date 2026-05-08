# Quarantine And Evidence Playbook

Treat exports as sensitive evidence, not disposable intermediates.

## Rules

- raw ZIPs go into `artifacts/raw/` and become read-only after hashing
- enriched ZIPs go into `artifacts/enriched/` and are never renamed silently
- patched JSONL and final ZIP go into `artifacts/import-ready/`
- every transition writes a manifest or report
- never mix workspaces in the same artifact tree

## Minimal Quarantine Flow

1. download/export artifact
2. hash it into a manifest
3. move it into the stage directory
4. record owner and timestamp in the evidence pack
5. only then proceed to the next stage

## Why This Matters

This prevents cross-workspace mixups, stale ZIP reuse, and “which file was authoritative?” failures during staging and cutover.
