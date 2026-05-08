# Mattermost API Health Cookbook

Admin HTTP endpoints used by Phase 3 probes, plus what a "healthy"
response looks like.

## `/api/v4/system/ping` (anonymous)

```bash
curl -fsS https://chat.acme.com/api/v4/system/ping
# → {"status":"OK","AndroidLatestVersion":"","AndroidMinVersion":"","IosLatestVersion":"","IosMinVersion":""}
```

200 status + `"status":"OK"` → alive. Non-200 or timeout → red.

## `/api/v4/config/client?format=old` (anonymous)

Returns server version + feature flags visible to clients.

```bash
curl -fsS 'https://chat.acme.com/api/v4/config/client?format=old' \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["Version"], d["BuildNumber"])'
# → 10.11.3 1234567
```

Used by `update-mattermost` to confirm post-upgrade version.

## `/api/v4/users/me` (PAT-authenticated)

Proves PAT validity.

```bash
curl -fsS -H "Authorization: Bearer $TOKEN" https://chat.acme.com/api/v4/users/me
```

200 → PAT valid. 401/403 → revoked, rotated, or user is deactivated.

## `/api/v4/websocket` (WebSocket upgrade)

Expects a `101 Switching Protocols` on HTTP, or `401` if anon (still
indicates the endpoint is reachable).

Used by `health-check.sh` WebSocket probe.

## `/api/v4/users/me/tokens` (PAT-authenticated, self)

Lists the current user's personal access tokens, including `id` and
`description`. Used by `security-posture-auditor` to audit PAT age.

```bash
curl -fsS -H "Authorization: Bearer $TOKEN" \
  https://chat.acme.com/api/v4/users/me/tokens
```

## `/api/v4/system/timezones`

Used as a cheap readiness check after upgrade (any 200 that requires DB
access is better than `/ping` which can lie if Mattermost is mid-boot).

## Admin-level: `/api/v4/reports/users`

Useful during incident response:

```bash
curl -fsS -H "Authorization: Bearer $TOKEN" \
  "https://chat.acme.com/api/v4/reports/users?role_filter=system_admin" | jq .
```

Returns admin-role users; quick check for unauthorized admin grants.

## Admin-level: `/api/v4/audits`

```bash
curl -fsS -H "Authorization: Bearer $TOKEN" \
  "https://chat.acme.com/api/v4/audits?since=$(date -u -d '-1 hour' +%s)000" | jq .
```

Recent admin-plane actions. Used by `security-posture-auditor`.

## Rate limiting

Mattermost's API rate limit is 10 req/sec per user by default. Phase 3
probes are well under this; if you batch (e.g. iterating channels), add
a 100ms sleep to stay polite.

## CORS / origin

Admin API calls from a browser require `AllowCorsFrom` in server config
to include the calling origin. Phase 3's scripts use `curl` directly, so
CORS doesn't apply.

## Error envelope

Failed responses:

```json
{
  "id": "api.context.invalid_credentials.app_error",
  "message": "Invalid or expired session, please login again.",
  "status_code": 401
}
```

Phase 3 scripts parse `status_code` and `message` for the summary line.

## Latency baseline

A healthy Mattermost on AX42 for a 500-user workspace:

- `/ping`: ~5-20 ms
- `/config/client?format=old`: ~20-50 ms
- `/users/me` (PAT): ~30-80 ms
- `/audits?since=...`: ~100-300 ms (DB-heavy)

If your numbers are ~5× these, investigate DB pressure or network.

## Useful one-liners

Get running version:
```bash
curl -fsS https://chat.acme.com/api/v4/config/client?format=old \
  | grep -o '"Version":"[^"]*"' | head -1
```

Count active sessions (admin):
```bash
curl -fsS -H "Authorization: Bearer $TOKEN" \
  "https://chat.acme.com/api/v4/users?per_page=200&active=true" | jq 'length'
```

Check a known-good post still exists after a restore:
```bash
curl -fsS -H "Authorization: Bearer $TOKEN" \
  "https://chat.acme.com/api/v4/posts/$POST_ID"
```
