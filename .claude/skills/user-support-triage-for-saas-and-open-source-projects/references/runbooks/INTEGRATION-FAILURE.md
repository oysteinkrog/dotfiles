# Runbook: INTEGRATION-FAILURE

A customer's integration with our service stopped working. Common across API products, webhooks, OAuth apps, third-party connectors, and CLI tools.

## Triggers

- "Webhook stopped firing"
- "API returns 401/403 (was working yesterday)"
- "Rate limited" / "429s"
- "OAuth token refresh fails"
- "CLI command times out"
- "Library version X breaks against API version Y"
- "Your SDK is broken"

## First Hour Triage

1. **Their side or ours?** Check our error rate / status — if normal, focus on theirs.
2. **Recent changes?** Did we deploy? Did we change webhook signing? Did we deprecate?
3. **Their version vs current?** SDK, integration version, OAuth scope.
4. **Specific failures or all calls?** Single endpoint vs system-wide.

## Investigation

```bash
# 1. Their account's recent API calls
psql -c "SELECT path, status_code, response_time_ms, ts
         FROM api_request_log
         WHERE org_id = '<org>' AND ts > NOW() - INTERVAL '1h'
         ORDER BY ts DESC LIMIT 100;"

# 2. Their webhook delivery history
psql -c "SELECT event_id, target_url, status, response_code, attempts, last_attempt_at
         FROM webhook_deliveries
         WHERE org_id = '<org>' AND ts > NOW() - INTERVAL '1h'
         ORDER BY ts DESC LIMIT 50;"

# 3. Their OAuth token state
psql -c "SELECT scopes, expires_at, refresh_failed_at, last_used_at
         FROM oauth_tokens WHERE org_id = '<org>';"

# 4. Recent API/SDK changes that could affect them
git log --since='14 days ago' -- 'api/' 'src/api/' 'sdk/'

# 5. Are they on a deprecated SDK / API version?
psql -c "SELECT user_agent, count(*) FROM api_request_log
         WHERE org_id = '<org>' AND ts > NOW() - INTERVAL '1h'
         GROUP BY 1;"
```

## Common Failure Modes

### A. Webhook Delivery Failures

```
Check delivery log:
- 4xx → their endpoint rejected (auth / signature / format)
- 5xx → their endpoint errored
- Timeout → their endpoint slow / down
- TLS/cert errors → their cert expired

If 4xx with 401/403:
  - Did we rotate signing secret? When?
  - Are they verifying signature correctly?
  - Time-skew issues if HMAC includes timestamp?

If 5xx:
  - Their endpoint is down — they need to fix it
  - Our retry policy: confirm we're retrying with backoff (not hammering)

If timeout:
  - Their endpoint slow during burst — recommend acknowledgment endpoint pattern
```

### B. API 401/403 Suddenly

Common causes:
1. OAuth token expired and refresh broke (most common)
2. We rotated API keys server-side (rare; should never do without notice)
3. They migrated regions and tokens are scoped to old region
4. We deprecated a scope they were using
5. Their account was suspended (separate issue)

### C. Rate Limit Sudden 429s

```
Did their usage spike? They got featured / launched?
Did we tighten limits? When?
Are they on the right tier for the volume?

Action:
- Confirm tier vs actual usage
- If sustainable burst: temporary tier-up (within tier limits)
- If permanent: recommend tier upgrade
- If we tightened: communicate with reasoning
```

### D. SDK Version Mismatch

User on SDK 1.x, API now requires 2.x patterns:

```
Identify their SDK version (User-Agent header)
Cross-reference against deprecation timeline
Provide:
  - Specific upgrade path
  - Backwards-compat shim if available
  - Timeline before old SDK breaks
```

### E. OAuth Token Refresh Broken

```
Check refresh attempts: are tokens marked refresh_failed_at?
Common: their app was deleted in our system, tokens orphaned
Common: refresh-token rotation policy changed (we now require single-use)

Fix path: re-auth required. Specific error message and re-auth URL.
```

### F. CLI Command Hangs / Times Out

```
Get their CLI version: `tool --version` from them
Get their command: exact invocation
Get our service status for that endpoint
Check if we changed timeout / streaming behavior

Common: CLI version pre-streaming; our endpoint now streams
Common: we increased response size; CLI buffer too small
```

## Drafts

### INTEGRATION-FAILURE-WEBHOOK-401

```
Confirmed — your webhook endpoint is returning 401s on our delivery
attempts. From our side, we're sending the right signature in the
`X-Signature-256` header for every event since <date>.

Two things to check:
1. Are you on signing key version 2 (we rotated 90 days ago — old keys
   stopped working <date>)? If not: new key is in your dashboard at
   <link>.
2. Are you verifying the signature server-side? Quickest test: check
   our docs example at <link>.

If both check out and you're still 401-ing, send me a sample request as
your endpoint sees it and I'll diff against what we're sending.
```

### INTEGRATION-FAILURE-RATE-LIMITED

```
You're at <X> req/sec sustained over the past hour, on the <tier> plan
which caps at <Y>. That's why you're seeing 429s.

Two paths:
1. If this is a one-off burst: I can give you a 24h grace window to
   absorb it without changing tiers.
2. If this is the new normal: tier upgrade to <next-tier> at $<price>/mo
   gives you <Z> req/sec headroom.

Tell me which fits.
```

### INTEGRATION-FAILURE-DEPRECATED-SDK

```
You're on SDK v1.4 (we've been tracking your User-Agent). The v1.x line
is end-of-life as of <date>; v2.0 is the current line.

Your specific issue (<bug>) is fixed in v2.0 — root cause was <reason>.

Upgrade path: <link to migration guide>. Most v1 code ports straight
across; the breaking changes are <list>.

Need help with the upgrade? Reply with what's blocking and I'll dig in.
```

## Anti-Patterns

| Don't | Why |
|---|---|
| Blame the customer's code first | Default assumption: it's our deploy. Verify before deflecting |
| Tell them "upgrade your SDK" without diagnosing | Often the bug is on our side, not in their version |
| Say "it's fine on our end" without checking THEIR account specifically | Aggregate metrics hide per-account problems |
| Deprecate API versions without 90-day notice | Breaks integrations silently; wave of tickets |
| Rotate signing secrets without grace period | Mass webhook failures all at once |
| Auto-disable webhooks after N failures without notifying | Customer thinks "events are now sparse" — they're missing |

## Companion Refs

- [BILLING-DEEP.md](BILLING-DEEP.md) — when integration involves payment provider
- [SECURITY-DISCLOSURE.md](SECURITY-DISCLOSURE.md) — if integration exposes credentials
- `../OPERATOR-LIBRARY.md` — ⊕ CORRELATE for cross-checking deploys
- `../ORCHESTRATOR-WORKFLOW.md` — Pipeline K
