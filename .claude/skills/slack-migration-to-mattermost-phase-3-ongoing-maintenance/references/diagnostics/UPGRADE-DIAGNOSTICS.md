# Upgrade Diagnostics

Things that go wrong during `./maintain.sh update-mattermost`.

## APT version not found

Symptom: `apt-get install mattermost=X.Y.Z` reports "Version '...' not
found."

Causes:
- Version published for a different Ubuntu codename (Mattermost's APT
  repo is distro-specific).
- Typo in the version string.
- The version is too new and not yet propagated to the mirror.

Fix:
```
ssh $TARGET apt-cache madison mattermost | head -10
```
Pick one of the listed candidates. Update `MATTERMOST_TARGET_VERSION`.

## Long migration hang

Symptom: `update-mattermost` reports "waiting for ping" for > 3 minutes,
but health probe eventually recovers.

Cause: schema migration runs on startup. For DBs > 50 GB, some minor
version bumps take 10-30 min.

Fix: extend the ping poll timeout. Manual form:
```
ssh $TARGET sudo tail -f /opt/mattermost/logs/mattermost.log
```
Wait for `msg="Migration completed"`. Don't restart in between.

## Post-upgrade ping 502 / 504

Cause: Mattermost process started but Nginx upstream is confused.

Fix:
```
ssh $TARGET sudo systemctl restart nginx
```

If still bad, check `ssh $TARGET sudo journalctl -u nginx -n 50`.

## Auto-rollback triggered but didn't complete

Symptom: `latest-update-mattermost.json.status=failed_manual_intervention_required`.

Causes:
- APT couldn't reinstall the previous version (it was removed from the
  cache, or a security update was pulled in mid-sequence).
- `pg_restore` choked on the pre-upgrade dump (corruption between dump
  and restore? rare).

Fix (manual rollback):
```
ssh $TARGET sudo systemctl stop mattermost
ssh $TARGET sudo apt-get install --allow-downgrades mattermost=<previous>
ssh $TARGET "sudo -u postgres dropdb mattermost && sudo -u postgres createdb mattermost"
ssh $TARGET "gunzip -c /var/backups/mattermost/pre-upgrade-<ts>.sql.gz | sudo -u postgres psql mattermost"
ssh $TARGET sudo systemctl start mattermost
```

## Plugin broken after upgrade

Cause: plugin compiled against an older Mattermost server API.

Fix: disable the plugin in System Console → Plugins → Management, verify
Mattermost is healthy, then update the plugin (often a new version is
available that targets the new server API).

## Upgrade completed but users report slowness

Cause: new version's query planner regressed, OR caches are cold.

Fix:
- Let it warm up for 15 minutes before diagnosing.
- If still slow, `db-health` shows which tables are hot.
- Consider `ANALYZE` to refresh planner statistics:
  ```
  ssh $TARGET sudo -u postgres psql mattermost -c "ANALYZE;"
  ```

## Upgrade touched Postgres major version

`[Q-DB-001]` — Mattermost 10.x needs PG 13+, 11.x needs PG 15+. A Mattermost
major upgrade may require a prior PG major upgrade.

PG major upgrades are not in scope for `update-mattermost`. Do it
separately:
1. Take a full pg_dump.
2. Install the new PG major.
3. `pg_upgrade` or restore from dump into the new cluster.
4. Update `POSTGRES_DSN` if port changed.
5. Then proceed with `update-mattermost`.

See [../POSTGRES-MAINTENANCE-DEEP-DIVE.md](../POSTGRES-MAINTENANCE-DEEP-DIVE.md).
