# Intake Quarantine

Only verified Phase 1 bundles should touch staging or production.

## Intake Rules

- copy bundle into a staging/production-specific intake directory
- verify handoff JSON, hashes, and manifests before upload
- never rename the authoritative ZIP manually
- never import from a workstation temp directory

## Why This Matters

This prevents importing the wrong bundle, importing a stale ZIP, or bypassing the hash chain established in Phase 1.
