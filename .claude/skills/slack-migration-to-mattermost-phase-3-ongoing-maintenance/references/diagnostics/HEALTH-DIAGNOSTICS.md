# Health Diagnostics

Symptom → investigation → common root causes. Pair with [OPERATOR-LIBRARY.md](../OPERATOR-LIBRARY.md) "HEALTH" card.

## §app-process — `mattermost_ping=red`

```
ssh $TARGET sudo systemctl status mattermost
ssh $TARGET sudo journalctl -u mattermost -n 200 --no-pager
```

Common roots:
- **OOM**: `dmesg | grep -i killed`. If the Go process was killed, low
  `GOMEMLIMIT` / missing swap / runaway plugin. Fix: add `MemoryMax=` to
  systemd unit, or bump server tier.
- **Crashed migration**: look for `level=error msg="Failed to apply
  migrations"`. Usually post-upgrade, should auto-rollback.
- **Port 8065 collision**: another process bound port. `sudo lsof -i:8065`.
- **config.json corrupted**: `sudo jq . /opt/mattermost/config/config.json`
  to validate; if it's bad, restore from Phase 2's `rendered/config.json`.

## §nginx-websocket — `websocket_upgrade=red`, ping ok

```
ssh $TARGET sudo nginx -t
ssh $TARGET cat /etc/nginx/sites-enabled/mattermost.conf | grep -A3 websocket
```

Common root: the `Upgrade` / `Connection: upgrade` location block is
missing. Usually from a hand-edit of the Nginx config. Fix: re-run Phase
2's `render-config` + `deploy` to regenerate.

## §disk — `disk_root=red` or `disk_mattermost=red`

```
ssh $TARGET sudo du -shx /* 2>/dev/null | sort -h | tail -20
ssh $TARGET sudo du -shx /opt/mattermost/* | sort -h | tail
```

Common roots:
- **`/opt/mattermost/data/`** big: file attachments stored locally. Move
  to R2 per Phase 2 `5.4`.
- **`/opt/mattermost/logs/`** big: log rotation broken. `sudo logrotate
  -f /etc/logrotate.d/mattermost`.
- **`/var/log/`** big: syslog flood. `sudo journalctl --vacuum-time=7d`.
- **`/var/backups/mattermost/`** big: rotation not running. Manual
  cleanup + verify `BACKUP_RETENTION_*` in config.
- **`/var/cache/apt/`** big: `sudo apt-get clean`.

## §pg-saturation — `pg_connections=red`

```
ssh $TARGET "sudo -u postgres psql -c \"SELECT pid, usename, application_name, state, state_change, query FROM pg_stat_activity ORDER BY state_change LIMIT 30;\""
```

Common roots:
- **"idle in transaction"** accumulating: a plugin leaked a transaction.
  Terminate with `SELECT pg_terminate_backend(pid) FROM pg_stat_activity
  WHERE state='idle in transaction' AND state_change < now() - interval
  '5 minutes';`.
- **Burst from integration**: a newly-added webhook firing per-message;
  throttle at the integration side.
- **max_connections too low**: default 200; if you have multiple Mattermost
  workers, raise to 300-400.

## §logs — `mattermost_errors=red`

```
./scripts/inspect-mattermost-log.py --window 1h
```

Read the top-bucket. Common buckets:
- **plugin crash loop**: disable the plugin in System Console.
- **DB connection churn**: see §pg-saturation.
- **SMTP send failure**: 500-level from Postmark; see Phase 2 SMTP walkthrough.
- **WebSocket reconnects**: network path issue; check Cloudflare + origin.

## §smtp — `smtp_tcp=red`

Postmark (or your provider) blocked the IP, revoked the token, or
changed the SMTP endpoint. First check provider status page, then:

```
swaks --to $SMTP_TEST_EMAIL --from noreply@$DOMAIN \
      --server smtp.postmarkapp.com:587 --tls \
      --auth-user $SMTP_USERNAME --auth-password $SMTP_PASSWORD
```

If it fails: regenerate server token in Postmark, update config, retry.

## §services — any `service_*=red`

```
ssh $TARGET sudo systemctl status <service>
ssh $TARGET sudo journalctl -u <service> -n 100 --no-pager
```

For `fail2ban` stopped: `sudo systemctl restart fail2ban`. For `ufw`
stopped: `sudo ufw enable` (verify rules still include 22/80/443 first).

## When to escalate

If two bands of diagnosis don't pinpoint root cause within 30 minutes,
escalate per [../comms/ESCALATION-LADDER.md](../comms/ESCALATION-LADDER.md).
