# Cloudflare Configuration Cookbook

## Add Domain to Cloudflare

If your domain isn't on Cloudflare yet:

1. Dashboard > **Add a Site** > enter `yourdomain.com`
2. Select plan (Free is sufficient for Mattermost)
3. Cloudflare scans existing DNS records
4. Update nameservers at your registrar to the two Cloudflare assigns
5. Wait for propagation (usually < 30 minutes, can take 24 hours)

```bash
# Verify nameservers updated
dig NS yourdomain.com +short
# Should show xxx.ns.cloudflare.com
```

## DNS Records

### Main Mattermost Record (Proxied)

Dashboard: DNS > Records > Add Record

| Type | Name | Content | Proxy | TTL |
|------|------|---------|-------|-----|
| A | `chat` | `YOUR_SERVER_IP` | Proxied (orange cloud) | Auto |

```bash
# Via wrangler CLI (if you have it configured):
# Not directly supported -- use the API instead:
curl -X POST "https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records" \
  -H "Authorization: Bearer CF_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "A",
    "name": "chat",
    "content": "YOUR_SERVER_IP",
    "proxied": true
  }'
```

### Calls Plugin Record (DNS-Only)

Mattermost Calls uses UDP (WebRTC). Cloudflare proxy only handles TCP. The Calls plugin **must** bypass Cloudflare proxy.

| Type | Name | Content | Proxy | TTL |
|------|------|---------|-------|-----|
| A | `calls` | `YOUR_SERVER_IP` | DNS only (grey cloud) | Auto |

This means `calls.yourdomain.com` resolves directly to your server IP. Ensure UFW allows `8443/udp`.

In Mattermost config, set the Calls plugin ICE host override to `calls.yourdomain.com`.

## SSL/TLS Configuration

### Set Encryption Mode

Dashboard: SSL/TLS > Overview > **Full (Strict)**

This requires a valid certificate on your origin server. Cloudflare Origin CA certs count as valid for this mode.

**Do not use "Flexible"** -- it sends traffic from Cloudflare to your origin over plain HTTP, which exposes passwords and tokens.

### Generate Origin CA Certificate

Dashboard: SSL/TLS > Origin Server > **Create Certificate**

1. Key type: RSA (2048) or ECDSA
2. Hostnames: `chat.yourdomain.com`, `*.yourdomain.com` (or just the specific subdomain)
3. Validity: **15 years** (maximum)
4. Click Create
5. **Copy both the certificate and private key immediately** -- the private key is shown only once

Install on your server:

```bash
# On the server:
sudo mkdir -p /etc/nginx/ssl

# Paste the certificate
sudo tee /etc/nginx/ssl/origin.pem << 'CERT'
-----BEGIN CERTIFICATE-----
(paste certificate here)
-----END CERTIFICATE-----
CERT

# Paste the private key
sudo tee /etc/nginx/ssl/origin-key.pem << 'KEY'
-----BEGIN PRIVATE KEY-----
(paste private key here)
-----END PRIVATE KEY-----
KEY

sudo chmod 600 /etc/nginx/ssl/origin-key.pem
sudo chmod 644 /etc/nginx/ssl/origin.pem
```

### Minimum TLS Version

Dashboard: SSL/TLS > Edge Certificates > Minimum TLS Version > **TLS 1.2**

### Always Use HTTPS

Dashboard: SSL/TLS > Edge Certificates > **Always Use HTTPS** > On

### HSTS (Optional but Recommended)

Dashboard: SSL/TLS > Edge Certificates > HTTP Strict Transport Security (HSTS)
- Enable: Yes
- Max Age: 6 months (15768000)
- Include subdomains: Yes (only if all subdomains use HTTPS)
- Preload: Yes (only if committed to HTTPS permanently)

## Authenticated Origin Pulls

Ensures only Cloudflare can connect to your Nginx. Requests without Cloudflare's client certificate get rejected.

Dashboard: SSL/TLS > Origin Server > **Authenticated Origin Pulls** > On

Download Cloudflare's client CA certificate:

```bash
# On the server:
curl -o /etc/nginx/ssl/cloudflare-origin-pull-ca.pem \
  https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem
```

Add to your Nginx server block:

```nginx
ssl_client_certificate /etc/nginx/ssl/cloudflare-origin-pull-ca.pem;
ssl_verify_client on;
```

After enabling, direct connections to your server IP on port 443 will fail with a 400 error (no client cert). This is the desired behavior -- all traffic must flow through Cloudflare.

## WebSocket Support

Dashboard: Network > **WebSockets** > On

WebSockets are enabled by default on all Cloudflare plans. Mattermost requires WebSocket for real-time messaging. If disabled, users see "Connecting..." forever.

Verify by checking the Mattermost client -- if the WebSocket icon in the bottom-left is green, it works.

## WAF (Web Application Firewall)

Dashboard: Security > WAF

### Managed Rules

Enable the Cloudflare Managed Ruleset and the OWASP Core Ruleset. For Mattermost, the defaults work. If you see false positives on file uploads or webhook endpoints:

Dashboard: Security > WAF > Managed Rules > Cloudflare Managed Ruleset > gear icon

Create an exception:
- When: URI Path contains `/api/v4/files` OR URI Path contains `/hooks/`
- Then: Skip all remaining managed rules

### Rate Limiting (Optional)

Dashboard: Security > WAF > Rate limiting rules > Create rule

Suggested rule for login brute-force protection:

- When: URI Path equals `/api/v4/users/login` AND Request Method equals `POST`
- Rate: 10 requests per minute per IP
- Then: Block for 10 minutes

### Bot Fight Mode

Dashboard: Security > Bots > **Bot Fight Mode** > On

Be cautious: this can block legitimate integrations (webhooks, bots, mmctl). If you use incoming webhooks from external services, add those IPs to an IP Access Rule (Security > WAF > Tools > IP Access Rules > Allow).

## DDoS Protection

Dashboard: Security > DDoS

Cloudflare provides automatic DDoS protection on all plans. The L7 DDoS managed ruleset is enabled by default. For most Mattermost deployments, the defaults are sufficient.

If under active attack, enable **Under Attack Mode**:
Dashboard: Overview > Quick Actions > **Under Attack Mode**

This adds a 5-second JavaScript challenge. Disable it after the attack subsides -- it interferes with Mattermost desktop/mobile clients.

## Page Rules / Cache Rules

Mattermost API calls must never be cached. Static assets should be cached.

### Option A: Cache Rules (Newer, Recommended)

Dashboard: Caching > Cache Rules > Create Rule

**Rule 1: Bypass cache for API**
- When: URI Path starts with `/api/`
- Cache eligibility: Bypass cache

**Rule 2: Cache static assets**
- When: URI Path starts with `/static/`
- Cache eligibility: Eligible for cache
- Edge TTL: 1 month
- Browser TTL: 1 week

### Option B: Page Rules (Legacy)

Dashboard: Rules > Page Rules > Create Page Rule

| URL Pattern | Settings |
|-------------|----------|
| `chat.yourdomain.com/api/*` | Cache Level: Bypass |
| `chat.yourdomain.com/static/*` | Cache Level: Cache Everything, Edge Cache TTL: 1 month |

## Cloudflare Tunnel for SSH (Optional)

Instead of exposing port 22 directly, route SSH through Cloudflare Tunnel. This lets you close port 22 in UFW entirely.

### On the Server

```bash
# Install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
  -o /tmp/cloudflared.deb
dpkg -i /tmp/cloudflared.deb

# Authenticate
cloudflared tunnel login
# Opens browser to authorize -- select your domain

# Create tunnel
cloudflared tunnel create mm-ssh
# Note the tunnel ID and credentials file path

# Configure
cat > /etc/cloudflared/config.yml << 'EOF'
tunnel: YOUR_TUNNEL_ID
credentials-file: /root/.cloudflared/YOUR_TUNNEL_ID.json

ingress:
  - hostname: ssh.yourdomain.com
    service: ssh://localhost:22
  - service: http_status:404
EOF

# Create DNS record for tunnel
cloudflared tunnel route dns mm-ssh ssh.yourdomain.com

# Run as service
cloudflared service install
systemctl enable cloudflared
systemctl start cloudflared
```

### On Your Local Machine

```bash
# Install cloudflared locally
brew install cloudflared  # macOS
# or: winget install Cloudflare.cloudflared  # Windows

# Add to ~/.ssh/config
cat >> ~/.ssh/config << 'EOF'
Host mm-prod
    HostName ssh.yourdomain.com
    User deploy
    ProxyCommand cloudflared access ssh --hostname %h
EOF

# Connect
ssh mm-prod
```

### Cloudflare Access Policy for SSH

Dashboard: Zero Trust > Access > Applications > Add Application

1. Type: Self-hosted
2. Application name: MM SSH
3. Application domain: `ssh.yourdomain.com`
4. Policy: Allow -- configure who can access (email domain, specific emails, etc.)

## CDN Caching for Static Assets

Mattermost serves static files (JS, CSS, images) from `/static/`. These are versioned and safe to cache aggressively.

Dashboard: Caching > Configuration

| Setting | Value |
|---------|-------|
| Caching Level | Standard |
| Browser Cache TTL | Respect Existing Headers |
| Always Online | Off (Mattermost is dynamic) |

The Cache Rule from earlier handles the `/static/` path. Verify caching works:

```bash
curl -sI https://chat.yourdomain.com/static/main.js | grep -E 'cf-cache-status|cache-control'
# cf-cache-status: HIT (after first request warms cache)
```

## Verification Checklist

```bash
# DNS resolves through Cloudflare
dig chat.yourdomain.com +short
# Should show Cloudflare IPs (104.x.x.x or 172.x.x.x), NOT your server IP

# SSL works end-to-end
curl -sI https://chat.yourdomain.com | head -5
# Should show HTTP/2 200

# WebSocket works (Mattermost client connects without "Connecting..." state)

# Direct IP access blocked (if Authenticated Origin Pulls enabled)
curl -sI https://YOUR_SERVER_IP --resolve chat.yourdomain.com:443:YOUR_SERVER_IP
# Should fail or return 400

# Calls subdomain resolves directly
dig calls.yourdomain.com +short
# Should show YOUR_SERVER_IP directly (not Cloudflare IPs)

# API not cached
curl -sI https://chat.yourdomain.com/api/v4/system/ping | grep cf-cache-status
# cf-cache-status: DYNAMIC (never cached)
```
