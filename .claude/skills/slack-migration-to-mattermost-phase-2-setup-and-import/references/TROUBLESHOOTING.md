# Troubleshooting

## Server Won't Start

### Mattermost service fails immediately
**Symptom:** `systemctl start mattermost` exits without error but service is not running.
**Cause:** Config parse error, wrong permissions, or port conflict.
**Diagnose:**
```bash
sudo journalctl -u mattermost --no-pager -n 50
cat /opt/mattermost/logs/mattermost.log | tail -50
```
**Fix:** Check the log output for the specific error. Common causes below.

### "listen tcp 127.0.0.1:8065: bind: address already in use"
**Symptom:** Mattermost logs show address-in-use error.
**Cause:** Another Mattermost process or a previous instance didn't shut down cleanly.
**Diagnose:**
```bash
sudo ss -tlnp | grep 8065
sudo lsof -i :8065
```
**Fix:**
```bash
sudo kill $(sudo lsof -t -i :8065)
sudo systemctl start mattermost
```

### "config.json: permission denied"
**Symptom:** Mattermost can't read its config file.
**Cause:** Wrong file ownership after manual edits.
**Diagnose:**
```bash
ls -la /opt/mattermost/config/config.json
```
**Fix:**
```bash
sudo chown mattermost:mattermost /opt/mattermost/config/config.json
sudo chmod 600 /opt/mattermost/config/config.json
```

### "invalid character" in config.json
**Symptom:** Log shows JSON parse error with character position.
**Cause:** Trailing comma, missing quote, or invalid JSON in config.
**Diagnose:**
```bash
python3 -m json.tool /opt/mattermost/config/config.json
# Shows exact line and position of syntax error
```
**Fix:** Correct the JSON syntax at the indicated position.

## WebSocket Failures

### "could not find upgrade header" / WebSocket won't connect
**Symptom:** Mattermost loads but shows "WebSocket connection failed" banner. Real-time updates don't work. Messages require page refresh to appear.
**Cause:** Nginx is not passing WebSocket upgrade headers to Mattermost.
**Diagnose:**
```bash
# Check if WebSocket location block exists
grep -A5 "websocket" /etc/nginx/sites-available/mattermost
# Test WebSocket directly (bypassing Nginx)
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
    http://127.0.0.1:8065/api/v4/websocket
```
**Fix:** Ensure your Nginx config has the WebSocket location block:
```nginx
location ~ /api/v[0-9]+/(users/)?websocket$ {
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 600s;
    proxy_pass http://mattermost;
}
```
Reload after editing:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### WebSocket connects then drops after 60 seconds
**Symptom:** WebSocket works briefly, then disconnects repeatedly.
**Cause:** `proxy_read_timeout` too low (default 60s). WebSocket is a long-lived connection.
**Fix:** Set `proxy_read_timeout 600s;` in the WebSocket location block.

## Database Connection Errors

### "FATAL: password authentication failed for user mmuser"
**Symptom:** Mattermost logs show PostgreSQL auth failure on startup.
**Cause:** Password in config.json doesn't match what PostgreSQL expects, or `pg_hba.conf` is set to `peer` instead of `md5`/`scram-sha-256`.
**Diagnose:**
```bash
# Test direct connection
psql -U mmuser -h 127.0.0.1 -d mattermost -c "SELECT 1;"
# Check auth method
grep mmuser /etc/postgresql/*/main/pg_hba.conf
```
**Fix:**
```bash
# Reset password
sudo -u postgres psql -c "ALTER USER mmuser WITH PASSWORD 'new-password';"
# Update config.json DataSource to match
# Ensure pg_hba.conf has:
#   host mattermost mmuser 127.0.0.1/32 scram-sha-256
sudo systemctl reload postgresql
```

### "too many connections for role mmuser" / connection pool exhausted
**Symptom:** Intermittent 500 errors, "sorry, too many clients already" in logs.
**Cause:** PostgreSQL `max_connections` too low, or Mattermost `MaxOpenConns` set too high.
**Diagnose:**
```bash
sudo -u postgres psql -c "SHOW max_connections;"
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity WHERE usename = 'mmuser';"
curl -s http://127.0.0.1:8067/metrics | grep mattermost_db_pool
```
**Fix:**
```bash
# Increase PostgreSQL max_connections in postgresql.conf
# max_connections = 200
sudo systemctl restart postgresql

# Also check Mattermost config -- MaxOpenConns should be LESS than max_connections
# "SqlSettings": { "MaxOpenConns": 100 }
```

### "pq: the database system is starting up"
**Symptom:** Mattermost fails on boot because PostgreSQL isn't ready yet.
**Cause:** Mattermost service starts before PostgreSQL finishes initialization.
**Fix:**
```bash
# Add dependency in systemd
sudo systemctl edit mattermost
# Add:
# [Unit]
# After=postgresql.service
# Requires=postgresql.service
sudo systemctl daemon-reload
```

## Import Failures

### Import stuck in "in_progress" forever
**Symptom:** `mmctl import job list` shows `in_progress` for hours with no progress.
**Cause:** Worker crashed, insufficient memory, or Mattermost restarted during import.
**Diagnose:**
```bash
mmctl import job list --json | jq '.[0]'
cat /opt/mattermost/logs/mattermost.log | grep -i "import" | tail -20
free -h  # Check available memory
df -h    # Check disk space
```
**Fix:**
```bash
# Cancel the stuck job (if possible) and re-run
mmctl import process <filename>
# If worker is truly dead, restart Mattermost
sudo systemctl restart mattermost
# Then re-run import -- it's idempotent, won't create duplicates
```

### "could not count users" during import
**Symptom:** Import fails with "could not count users" or similar user-related error.
**Cause:** Database connection timeout during large imports. The user count query times out under heavy write load.
**Diagnose:**
```bash
cat /opt/mattermost/logs/mattermost.log | grep "could not count"
sudo -u postgres psql -c "SELECT count(*) FROM users;" mattermost
```
**Fix:**
```bash
# Increase statement timeout for the import
sudo -u postgres psql -c "ALTER DATABASE mattermost SET statement_timeout = '300s';"
# Restart Mattermost and re-run import
sudo systemctl restart mattermost
mmctl import process <filename>
```

### Import fails with disk full
**Symptom:** Import aborts partway through. Logs show write errors.
**Cause:** Import extracts the ZIP and writes to `/opt/mattermost/data/import/` which fills the disk.
**Diagnose:**
```bash
df -h /opt/mattermost
du -sh /opt/mattermost/data/import/
```
**Fix:**
```bash
# Clean failed import artifacts
sudo rm -rf /opt/mattermost/data/import/*
# Free space or mount larger volume
# Re-run import after ensuring sufficient space
# Rule of thumb: need 3x the ZIP size free
```

### Import fails with memory exhaustion (OOM)
**Symptom:** Mattermost process killed during import, `dmesg` shows OOM killer.
**Cause:** Large imports (100k+ messages with file attachments) can consume several GB of RAM.
**Diagnose:**
```bash
dmesg | grep -i "oom" | tail -5
journalctl -u mattermost | grep -i "killed"
```
**Fix:**
```bash
# Add swap if not present
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Alternatively, split the import into smaller ZIPs (by channel or date range)
```

## SSL/TLS Issues

### Cloudflare Origin CA certificate warnings in browser
**Symptom:** Browser shows "not a valid certificate" when accessing directly (bypassing Cloudflare).
**Cause:** Cloudflare Origin CA certs are only trusted by Cloudflare's edge, not browsers.
**Fix:** This is expected behavior. Users must access through Cloudflare (the orange-clouded DNS record). Direct-IP access will always show a warning. If you need direct access for debugging, add the Origin CA to your local trust store temporarily.

### Mixed content warnings
**Symptom:** Browser console shows "Mixed Content" errors. Some assets load over HTTP.
**Cause:** `SiteURL` in Mattermost config uses `http://` instead of `https://`.
**Diagnose:**
```bash
grep SiteURL /opt/mattermost/config/config.json
```
**Fix:**
```bash
# Update SiteURL to use https
mmctl config set ServiceSettings.SiteURL "https://chat.yourdomain.com"
sudo systemctl restart mattermost
```

### "SSL_ERROR_RX_RECORD_TOO_LONG"
**Symptom:** Browser shows SSL record error when connecting.
**Cause:** Nginx is serving plain HTTP on port 443 (missing SSL config) or SSL cert path is wrong.
**Diagnose:**
```bash
sudo nginx -t
openssl s_client -connect 127.0.0.1:443 -servername chat.yourdomain.com </dev/null 2>&1 | head -20
```
**Fix:** Verify `ssl_certificate` and `ssl_certificate_key` paths in Nginx config are correct and the files exist.

## Cloudflare Issues

### 522 Connection Timed Out
**Symptom:** Users see Cloudflare 522 error page.
**Cause:** Cloudflare can't reach your origin server. Server is down, firewall blocks Cloudflare IPs, or Nginx isn't listening.
**Diagnose:**
```bash
sudo systemctl status nginx
sudo systemctl status mattermost
curl -s http://127.0.0.1:8065/api/v4/system/ping
sudo ufw status | grep 443
```
**Fix:**
```bash
# Ensure Nginx is running
sudo systemctl start nginx
# Ensure UFW allows 443
sudo ufw allow 443/tcp
# Verify Mattermost is responding
curl http://127.0.0.1:8065/api/v4/system/ping
# If server was rebooted, services may not have auto-started
sudo systemctl enable mattermost nginx postgresql
```

### 524 A Timeout Occurred
**Symptom:** Cloudflare 524 error on large file uploads or slow API calls.
**Cause:** Cloudflare's proxy timeout is 100 seconds (free plan). Your request took longer.
**Diagnose:**
```bash
# Check if the request works directly
curl --max-time 120 http://127.0.0.1:8065/api/v4/system/ping
```
**Fix:** Cloudflare free/pro plan has a fixed 100-second timeout. For large file uploads, consider:
- Reduce `MaxFileSize` to avoid uploads that take >100s on your bandwidth
- Use Cloudflare Enterprise (customizable timeouts)
- Use a DNS-only (grey cloud) subdomain for file upload endpoints

### WebSocket disconnects through Cloudflare
**Symptom:** WebSocket works for a while then drops. More frequent under Cloudflare than direct.
**Cause:** Cloudflare terminates idle WebSocket connections after 100 seconds of no traffic.
**Diagnose:**
```bash
# Check Mattermost WebSocket keepalive -- it should send pings
cat /opt/mattermost/logs/mattermost.log | grep -i "websocket" | tail -10
```
**Fix:** Mattermost sends WebSocket pings by default. If disconnects persist:
- Verify Cloudflare dashboard > Network > WebSockets is ON
- Check that no Cloudflare Page Rule or WAF rule is interfering with `/api/v4/websocket`
- Consider a DNS-only (grey cloud) record as a fallback if WebSocket issues persist

## Performance Problems

### Slow queries / high database CPU
**Symptom:** Mattermost feels sluggish. PostgreSQL at high CPU.
**Cause:** Missing indexes, untuned PostgreSQL, or queries scanning full tables.
**Diagnose:**
```bash
# Find slow queries
sudo -u postgres psql -c "SELECT pid, now() - query_start AS duration, query
    FROM pg_stat_activity
    WHERE state = 'active' AND now() - query_start > interval '5 seconds'
    ORDER BY duration DESC;" mattermost

# Check if autovacuum is running
sudo -u postgres psql -c "SELECT relname, last_vacuum, last_autovacuum, n_dead_tup
    FROM pg_stat_user_tables WHERE n_dead_tup > 10000
    ORDER BY n_dead_tup DESC;" mattermost
```
**Fix:**
```bash
# Run VACUUM ANALYZE on heavy tables
sudo -u postgres psql -c "VACUUM ANALYZE posts;" mattermost
sudo -u postgres psql -c "VACUUM ANALYZE channelmembers;" mattermost

# Ensure PostgreSQL is tuned (see SKILL.md Stage 2)
# shared_buffers = 16GB, effective_cache_size = 48GB, work_mem = 64MB
```

### High memory usage (Mattermost process)
**Symptom:** Mattermost process using 10+ GB RSS.
**Cause:** Large file cache, many goroutines, or memory leak in older versions.
**Diagnose:**
```bash
ps aux | grep mattermost | grep -v grep
curl -s http://127.0.0.1:8067/metrics | grep process_resident_memory_bytes
curl -s http://127.0.0.1:8067/metrics | grep go_goroutines
```
**Fix:**
```bash
# If goroutines are high (>10k), restart Mattermost
sudo systemctl restart mattermost
# If memory climbs back rapidly, check for known issues in your Mattermost version
# Upgrade to latest patch release
mmctl version
```

### Connection pool exhaustion under load
**Symptom:** Intermittent errors during peak usage, "connection pool exhausted" in logs.
**Cause:** `MaxOpenConns` too low for concurrent user load.
**Diagnose:**
```bash
curl -s http://127.0.0.1:8067/metrics | grep mattermost_db_pool_open_connections
curl -s http://127.0.0.1:8067/metrics | grep mattermost_db_pool_max_open_connections
```
**Fix:** Increase `MaxOpenConns` in config.json (and correspondingly increase PostgreSQL `max_connections`):
```json
{
  "SqlSettings": {
    "MaxOpenConns": 150,
    "MaxIdleConns": 30,
    "ConnMaxLifetimeMilliseconds": 3600000
  }
}
```

## User Activation Issues

### Password reset emails not sending
**Symptom:** Users click "Forgot Password" but never receive the email.
**Cause:** SMTP not configured, wrong credentials, or firewall blocking outbound SMTP.
**Diagnose:**
```bash
# Check SMTP config
grep -A10 EmailSettings /opt/mattermost/config/config.json
# Test SMTP connectivity
openssl s_client -connect smtp.example.com:587 -starttls smtp </dev/null 2>&1 | head -5
# Check Mattermost logs for send errors
grep -i "smtp\|email\|send" /opt/mattermost/logs/mattermost.log | tail -20
```
**Fix:**
1. Verify SMTP credentials in System Console > Environment > SMTP
2. Click "Send Test Email" in System Console
3. Check that `SendEmailNotifications` is `true`
4. Ensure outbound port 587 (or 465) is not blocked by your hosting provider

### Password reset emails going to spam
**Symptom:** Emails send but land in spam/junk folder.
**Cause:** Missing SPF, DKIM, or DMARC records for your sending domain.
**Fix:**
1. Add SPF record: `v=spf1 include:your-smtp-provider.com ~all`
2. Configure DKIM signing with your SMTP provider
3. Add DMARC record: `v=DMARC1; p=quarantine; rua=mailto:dmarc@yourdomain.com`
4. Verify with: https://www.mail-tester.com/

### "This server does not allow open signups"
**Symptom:** Imported users can't create accounts or reset passwords.
**Cause:** `EnableOpenServer` is `false`.
**Fix:**
```bash
mmctl config set TeamSettings.EnableOpenServer true
# After all users have activated, disable it:
mmctl config set TeamSettings.EnableOpenServer false
```

## Calls Plugin Issues

### Voice/video calls not connecting
**Symptom:** Calls plugin shows "connecting" indefinitely. Audio/video never establishes.
**Cause:** UDP traffic for WebRTC cannot traverse Cloudflare's proxy (Cloudflare only proxies TCP).
**Diagnose:**
```bash
# Check if calls plugin is enabled
mmctl plugin list | grep calls
# Check UFW for UDP
sudo ufw status | grep 8443
```
**Fix:**
1. Create a DNS-only (grey cloud) A record: `calls.yourdomain.com` -> server IP
2. Open UDP port in UFW: `sudo ufw allow 8443/udp`
3. Configure Calls plugin ICE server URL to use the DNS-only subdomain
4. In System Console > Plugins > Calls: set "ICE Host Override" to `calls.yourdomain.com`

### Calls work internally but not externally
**Symptom:** Calls work on LAN but fail for remote users.
**Cause:** NAT/firewall blocking UDP, or TURN server not configured.
**Fix:**
```bash
# Verify UDP is reachable from outside
# From an external machine:
nc -zuv calls.yourdomain.com 8443

# If NAT is the issue, configure a TURN server
# Mattermost Calls has a built-in TURN server -- enable it:
# System Console > Plugins > Calls > Enable TURN server
```

## Quick Diagnostic Commands

```bash
# Overall health
curl -s http://127.0.0.1:8065/api/v4/system/ping | python3 -m json.tool

# Service status
sudo systemctl status mattermost postgresql nginx

# Recent errors (last 100 lines)
tail -100 /opt/mattermost/logs/mattermost.log | grep -i "error\|fatal\|panic"

# Disk space
df -h /opt/mattermost /var/lib/postgresql

# Memory
free -h

# Network connections to Mattermost
sudo ss -tlnp | grep -E "8065|443|8067"

# Active database connections
sudo -u postgres psql -c "SELECT state, count(*) FROM pg_stat_activity WHERE datname='mattermost' GROUP BY state;"

# Mattermost version
/opt/mattermost/bin/mattermost version

# Import job status
mmctl import job list --json | python3 -m json.tool
```
