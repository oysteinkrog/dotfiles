Use the Phase 1 skill to run the `package` stage.

1. Run `./migrate.sh package`. This runs `patch-phase1-import.py` (adds custom emoji, sidecar channels/posts, memberships) and `package-phase1-import.py` (zips everything into `mattermost-bulk-import.zip`).
2. After success, show me the final ZIP size and its SHA256 from `manifest.import-ready.json`.
3. Confirm the sidecar channels in `PHASE1_SIDECAR_CHANNELS` each have at least one post plus all members added.
4. Any warnings from patch-phase1-import (e.g. "user XYZ missing from memberships") should be surfaced and classified, not swallowed.
