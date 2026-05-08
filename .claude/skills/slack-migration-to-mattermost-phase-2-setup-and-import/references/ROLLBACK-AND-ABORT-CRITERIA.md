# Rollback And Abort Criteria

Rollback semantics should be at least as explicit as forward progress.

## Abort Before Production Import If

- Phase 2 intake validation fails
- staging rehearsal fails or was never run
- rollback owner is unassigned
- config validation fails
- SMTP/activation path is unproven

## Abort After Production Import But Before Activation If

- counts diverge materially from the handoff
- smoke tests fail
- file paths are broken
- direct messages map incorrectly
- real-time connectivity is broken

## Rollback Inputs

- latest DB snapshot
- config snapshot
- filestore snapshot
- DNS / Cloudflare rollback plan
- stakeholder status template

## Output

Every cutover should have a written answer to:
- when do we stop
- who declares rollback
- what exact assets are restored
- how user communications change if rollback occurs
