# Real-Time Origin Settings

Mattermost real-time behavior can fail even when the proxy config looks correct.

## Why This Matters

Mattermost tightened WebSocket origin validation in v7.8+. If users access the instance from a different domain than the configured `SiteURL`, real-time features can break even though the server otherwise appears healthy.

Typical symptoms:
- posts do not appear in real time
- notifications are delayed or missing
- users see connection warnings and need to refresh

## Required Settings

### 1. Primary Site URL

Set the canonical user-facing URL:

```json
"ServiceSettings": {
  "SiteURL": "https://chat.example.com"
}
```

### 2. Additional Trusted Origins

If users legitimately access the site from another trusted origin, add those origins to `AllowCorsFrom`:

```json
"ServiceSettings": {
  "SiteURL": "https://chat.example.com",
  "AllowCorsFrom": "https://chat.example.com https://alt-chat.example.com"
}
```

Multiple origins are space-separated.

## Security Rule

Only add trusted domains. Do not use permissive wildcard values just to make WebSockets "work."

## When To Use This

Use this reference when:
- Cloudflare Tunnel or alternate admin domains are in play
- staging and production use different domains
- users report real-time failures despite a seemingly healthy proxy

## Verification

- confirm `SiteURL` matches the primary production URL
- confirm `AllowCorsFrom` includes every legitimate additional origin
- restart Mattermost after changes
- have a user verify that posts and notifications update in real time
