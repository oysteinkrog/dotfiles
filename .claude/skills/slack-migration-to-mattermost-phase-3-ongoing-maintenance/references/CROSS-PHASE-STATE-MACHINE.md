# Cross-Phase State Machine

How Phase 3 states evolve, including incident-driven transitions.

## States

```
                                        ┌─────────────┐
                                        │ POST-CUTOVER │  (Phase 2 complete,
                                        │   BASELINE   │   no Phase 3 yet)
                                        └──────┬──────┘
                                               │ doctor.sh --require-* green
                                               │ first `health` taken
                                               ▼
                                        ┌─────────────┐
              ┌────────────────────────▶│   STEADY    │◀──────────────┐
              │                         │   STATE     │               │
              │                         └──────┬──────┘               │
              │                                │                      │
              │             ┌──────────────────┼──────────────────┐   │
              │             │                  │                  │   │
              │             ▼                  ▼                  ▼   │
              │       weekly-sweep       update-mattermost    restore-drill
              │       (ok/yellow)          (per release)       (quarterly)
              │             │                  │                  │   │
              │             │ red              │ failed_rolled    │   │
              │             │                  │ _back            │   │
              │             ▼                  ▼                  │   │
              │       ┌──────────────────────────────┐            │   │
              │       │     INVESTIGATING (red)       │            │   │
              │       │  - health red                 │            │   │
              │       │  - backup failed              │            │   │
              │       │  - upgrade rolled back        │            │   │
              │       │  - restore-drill failed       │            │   │
              │       └──────────┬───────────────────┘            │   │
              │                  │                                 │   │
              │       ┌──────────┼──────────┐                      │   │
              │       │          │          │                      │   │
              │       ▼          ▼          ▼                      │   │
              │  remediate   INCIDENT   ESCALATE                    │   │
              │  in-place   RESPONSE    (human                      │   │
              │  (yellow→    (user-     decision                    │   │
              │  green)      reported   required)                   │   │
              │             outage)                                 │   │
              │       │          │          │                      │   │
              │       │          │          ▼                      │   │
              │       │          │   ┌──────────────┐               │   │
              │       │          │   │   DISASTER   │               │   │
              │       │          │   │   RECOVERY   │───────────────┘   │
              │       │          │   └──────────────┘                   │
              │       │          │                                      │
              │       │          ▼                                      │
              │       │    post-incident                                │
              │       │    review                                       │
              │       │          │                                      │
              └───────┴──────────┴──────────────────────────────────────┘
                                       (rejoin STEADY)
```

## Transition table

| From | Event | To | Gate |
|------|-------|----|----|
| POST-CUTOVER BASELINE | doctor green + first health taken | STEADY | — |
| STEADY | weekly-sweep yellow | STEADY | — |
| STEADY | weekly-sweep red | INVESTIGATING | operator ack required |
| STEADY | user reports outage | INCIDENT RESPONSE | paste `prompts/incident-response.md` |
| STEADY | new MM release published | STEADY | run `update-mattermost` when ready |
| STEADY | restore-drill failed | INVESTIGATING | do not run `update-mattermost` |
| INVESTIGATING | root cause + fix applied, health green | STEADY | post-mortem written |
| INVESTIGATING | cannot fix in place | DISASTER RECOVERY | `ROLLBACK_OWNER` approval |
| DISASTER RECOVERY | new host up, restore complete, verify-live green | STEADY | post-mortem, DNS swapped |
| INCIDENT RESPONSE | incident resolved | STEADY | post-mortem written |
| INCIDENT RESPONSE | incident unresolvable in place | DISASTER RECOVERY | `ROLLBACK_OWNER` approval |

## What each state permits

| State | Allowed stages | Blocked stages |
|-------|----------------|----------------|
| POST-CUTOVER BASELINE | `health` only | everything else (until baseline taken) |
| STEADY | all | — |
| INVESTIGATING | `health`, `backup`, `db-health`, investigation scripts | `update-mattermost`, `update-os` (avoid compounding) |
| INCIDENT RESPONSE | `health`, `backup` (pre-action snapshot), remediation | upgrades |
| DISASTER RECOVERY | all needed for rebuild | weekly-sweep on dead host |

## Recording state

Phase 3 does not currently persist the state machine's state to a file.
Operators infer state from:

- most recent `latest-*.json` reports and their status fields
- `workdir-phase3/reports/dr/` for active DR runs
- `workdir-phase3/rotate-credentials-audit.json` for in-progress rotations

If an explicit state file becomes useful, add `workdir-phase3/state.json`
and have every stage mutate it. Not required in v1 of the skill.

## Related docs

- [specs/OPERATING-MODEL.md](specs/OPERATING-MODEL.md) — how operator
  interacts with the state machine.
- [specs/MAINTENANCE-CONTRACT.md](specs/MAINTENANCE-CONTRACT.md) — what the
  skill guarantees per state.
- [playbooks/INCIDENT-RESPONSE.md](playbooks/INCIDENT-RESPONSE.md) — the
  INCIDENT RESPONSE state in detail.
