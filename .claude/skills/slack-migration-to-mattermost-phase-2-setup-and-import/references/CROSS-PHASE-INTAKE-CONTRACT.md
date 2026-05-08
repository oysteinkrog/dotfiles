# Cross-Phase Intake Contract

Phase 2 consumes the machine-readable `handoff.json` emitted by Phase 1.

## What Phase 2 Must Trust

- authoritative final ZIP path
- final ZIP hash
- manifest paths
- counts for users/channels/posts/direct messages
- named sidecar channels
- explicit known gaps

## Phase 2 Rule

Do not upload or import anything until `scripts/validate-phase2-intake.py` passes against this contract.
