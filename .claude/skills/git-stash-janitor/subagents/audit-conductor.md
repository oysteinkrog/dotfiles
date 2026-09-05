---
name: audit-conductor
description: Bundle integrity audit — deeper than verify-bundle.sh. Runs at Phase 3 (post-build), Phase 9 (pre-cleanup), and Phase 10 (handoff verification).
---

# Audit Conductor

Owns deep bundle audits. Three invocation points:

1. **Post-Phase-3 audit** — confirm bundle is sound before any classification logic runs
2. **Pre-Phase-9 audit** — confirm bundle is still sound before destructive cleanup
3. **Phase 10 handoff audit** — final confirmation; the count in handoff_report.md must match reality

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{INVOCATION}` — one of `post-phase-3`, `pre-phase-9`, `phase-10`

## Workflow

1. Run `scripts/bundle-audit.sh {PROJECT}`. Capture the findings count.

2. For `pre-phase-9` invocation, additionally:
   - Compare current `git stash list | wc -l` to inventory.tsv row count
   - If they differ: a stash was created or dropped between Phase 2 and now → Incident I6, halt
   - Re-verify byte-equality on a random sample of 10% of stashes (or all if <20)

3. For `phase-10` invocation, additionally:
   - Verify every backup ref still resolves
   - Verify the bundle directory still exists at the recorded path
   - Verify the recovery recipes parse (the README's shell snippets are valid syntax)

4. Write `<workspace>/audit_<invocation>.json`:
   ```json
   {
     "invocation": "post-phase-3",
     "timestamp": "2026-05-06T17:30:00Z",
     "findings_count": 0,
     "spot_checks_run": 3,
     "spot_checks_passed": 3,
     "byte_equality_verified": true,
     "decision": "PROCEED"
   }
   ```

## Critical rules

- **The audit is a gate.** If `findings_count > 0`, return `decision: HALT` and surface to incident-responder.
- **Don't fix bundle artifacts.** The audit detects; rebuilding is a separate operation.
- **Be honest about partial verification.** If only 3 of 127 spot-checks ran (because something timed out), document that.

## Coordination

- File reservation: `paths=["<workspace>/audit_<invocation>.json"]`, `exclusive=true`.

## Quality gates

- [ ] audit_<invocation>.json exists
- [ ] decision is PROCEED or HALT (no other values)
- [ ] If HALT, halt_reason.txt is also written

## Exit criteria

PROCEED: calling phase continues.
HALT: incident-responder is invoked.
