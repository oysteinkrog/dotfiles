# Workflow — Annual Disaster Recovery Drill

Once a year, rebuild production Mattermost on a fresh host from backups,
without actually losing production. Proves every DR procedure, end to
end, in the conditions you'd face in a real disaster.

## Why annually, not more

DR drills consume operator time (~2-4 hours) and cost a new server
(€0.10-€1 for the drill duration). Annually bounds the rust on the
procedure without making the drill itself noise.

## Prerequisites

- Last `restore-drill` passed (quarterly cadence).
- Access to order a new Hetzner / OVH / Contabo server.
- Phase 2 skill installed on the workstation.
- `ROLLBACK_OWNER` available for destructive-step approval.
- 4-hour Saturday budget.

## Steps

### Phase D1 — Setup (15 min)

1. Order a new Hetzner CX22 (or equivalent): `dr-<year>.chat.<domain>` is
   the operator hostname; no DNS change to production.
2. Add a temporary DNS A record for `dr-<year>.chat.<domain>` pointing
   at the new VPS. Grey cloud (no Cloudflare proxy for the drill).
3. Clone / copy Phase 2 + Phase 3 skill working directories to a DR
   scratch location.
4. Modify the DR Phase 2 `config.env` to target the new VPS.

### Phase D2 — Provision + deploy on DR host (30-60 min)

Run the full Phase 2 pipeline against the DR host:

```
cd <phase2>
PHASE2_CONFIG=./config.env.dr ./operate.sh intake render-config provision deploy verify-live
```

No staging stage; DR host starts empty.

### Phase D3 — Restore from backup (30-90 min, depends on DB size)

```
cd <phase3>
PHASE3_CONFIG=./config.env.dr ./maintain.sh restore-drill
```

This uses the normal restore-drill script but pointed at the new DR host's
PG instead of `SCRATCH_DB_URL`. Row counts should match live production.

### Phase D4 — Verify Mattermost boots (15 min)

```
PHASE3_CONFIG=./config.env.dr ./maintain.sh health
```

- Green overall
- Log into `dr-<year>.chat.<domain>` as admin, verify channels / posts /
  users look like production
- Spot-check one known-good post ID

### Phase D5 — Simulate DNS cutover (15 min, optional)

If you want the full drill:

1. Update a test client's `/etc/hosts` to point `chat.<domain>` at the
   DR host IP.
2. Verify the test client can log in and use Mattermost normally.
3. Un-revert the `/etc/hosts` change.

Do NOT change production DNS during the drill.

### Phase D6 — Tear down (5 min)

1. Delete the DR DNS record.
2. Cancel the Hetzner CX22 (stops billing immediately).
3. Delete the DR working directory copies.

### Phase D7 — Write the post-mortem (30 min)

Even if everything went perfectly, document:

- Wall-clock time per phase (helps sizing real DR)
- Anything that surprised you
- Any gap discovered (missing contact, stale config, outdated doc)
- Any improvement you'd make to the process

Store at `workdir-phase3/reports/dr/<year>-drill-postmortem.md`.

## Scoring

| Metric | Target | What failing means |
|--------|--------|---------------------|
| End-to-end wall-clock | ≤ 4 hours | Real DR may exceed your SLO |
| Manual intervention steps | ≤ 5 | Automation has gaps |
| Phase 2 provision success | pass | Phase 2 has drifted since last deployment |
| Row counts match production | ≤ 1% delta | Backup is incomplete |
| Post-restore login works | yes | Auth config drift |

Any fail is actionable: fix the identified gap before the next
quarterly `restore-drill`.

## Cost

- Hetzner CX22 for ~4 hours: ~€0.10 (hourly billing)
- R2 egress for backup download: trivial
- Operator time: 2-4 hours
- **Total**: <€1 infrastructure + half a Saturday

Against any real production outage, trivially worth it.

## Related

- [../DISASTER-RECOVERY.md](../DISASTER-RECOVERY.md) — the playbook
  itself
- [QUARTERLY-RESTORE-DRILL-WORKFLOW.md](QUARTERLY-RESTORE-DRILL-WORKFLOW.md)
- [../specs/MAINTENANCE-CONTRACT.md](../specs/MAINTENANCE-CONTRACT.md)
  "SLO targets"
