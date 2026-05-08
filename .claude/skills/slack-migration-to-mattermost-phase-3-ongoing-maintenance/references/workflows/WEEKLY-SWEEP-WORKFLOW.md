# Workflow — Weekly Sweep

The Saturday-night (or any off-peak) combo run.

## Prerequisites

- `./scripts/doctor.sh` green (tools + config)
- `./scripts/doctor.sh --require-remote` green (SSH + MM reachable)
- Previous week's sweep was either green, or its red items were resolved

## Steps

1. Paste [prompts/weekly-sweep.md](../../prompts/weekly-sweep.md) to the agent.
2. The agent runs `./maintain.sh weekly-sweep`, which is `health →
   update-os → backup → db-health` in order. Aborts on first failure.
3. Agent reads all four `latest-*.json` files and produces a one-paragraph
   summary.
4. If the paragraph includes any red or yellow metric, the agent:
   - maps the metric to the relevant diagnostic file
   - proposes a remediation band (A/B/C/D from INCIDENT-RESPONSE.md)
   - asks the operator for approval to proceed
5. If `update-os` flagged `reboot_required=yes`, agent offers to run
   `./maintain.sh schedule-reboot` after the sweep completes.

## Agent output format

```
Weekly sweep complete — $(date -u)

Overall: [green / yellow / red]

- health: ok/yellow/red (N red checks)
- update-os: N security updates installed, reboot_required=yes/no
- backup: mm_<ts>.sql.gz, X GB, SHA-verified, uploaded to <remote>
- db-health: ok/yellow/red (DB size X, conn usage Y%)

Next action: [none / schedule reboot / investigate <check>]
```

## Timing

Stage runtimes for a 340-user workspace on an AX42:

| Stage | Duration |
|-------|----------|
| health | 10-30 sec |
| update-os | 2-10 min (depends on available patches) |
| backup | 2-20 min (depends on DB size + bandwidth) |
| db-health | 15-45 sec |
| **Total** | ~5-30 min wall-clock |

## Failure handling

`weekly-sweep` aborts on first failed stage. This is intentional: a
failed `update-os` shouldn't cause a backup attempt against a host
possibly mid-upgrade.

On abort:
- Fix the failing stage (see its diagnostic doc)
- Re-run `weekly-sweep` fresh (don't try to resume mid-way)

## Automation

Cron on the operator workstation:

```cron
# Saturday 02:00 UTC
0 2 * * 6  cd ~/mattermost-ops && ./maintain.sh weekly-sweep >> /var/log/mm-sweep.log 2>&1
```

Or as a scheduled agent run via `/loop` or `/schedule` skill.

## Post-sweep operator checklist

- [ ] Weekly-sweep ran to completion (not aborted mid-way).
- [ ] Every `latest-*.json` has a recent timestamp.
- [ ] Overall is green or yellow (or red with a remediation plan).
- [ ] If reboot required: `schedule-reboot` queued.
- [ ] Any new trend reported by `health-drift-auditor` subagent was
      logged for attention.

## Integration with other cadences

- **Monthly:** first week's sweep also runs `version-drift-auditor`
  subagent to check for pending Mattermost releases.
- **Quarterly:** first week's sweep also prompts for `./maintain.sh
  restore-drill` (before anything else that week).
- **Annual:** skip a weekly sweep to run the full DR drill (takes longer
  and simulates the sweep as part of verification).
