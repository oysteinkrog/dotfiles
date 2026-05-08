# Nginx Configuration Reference

## Installation

```bash
apt update && apt install -y nginx
systemctl enable nginx
nginx -v
```

## SSL Certificate Files

Place the Cloudflare Origin CA cert and key (see CLOUDFLARE-COOKBOOK.md):

```bash
sudo mkdir -p /etc/nginx/ssl
# origin.pem      -- Cloudflare Origin CA certificate
# origin-key.pem  -- private key (chmod 600)
ls -la /etc/nginx/ssl/
```

## Complete Server Block

Write this to `/etc/nginx/sites-available/mattermost`:

```nginx
upstream mattermost_backend {
    server 127.0.0.1:8065;
    keepalive 32;
}

# HTTP -> HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name chat.yourdomain.com;
    return 301 https://$server_name$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name chat.yourdomain.com;

    # --- TLS (Cloudflare Origin CA) ---
    ssl_certificate     /etc/nginx/ssl/origin.pem;
    ssl_certificate_key /etc/nginx/ssl/origin-key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    # --- Authenticated Origin Pulls (optional, see CLOUDFLARE-COOKBOOK.md) ---
    # ssl_client_certificate /etc/nginx/ssl/cloudflare-origin-pull-ca.pem;
    # ssl_verify_client on;

    # --- File upload limit ---
    client_max_body_size 50M;

    # --- Gzip compression ---
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 256;
    gzip_types
        text/plain
        text/css
        text/javascript
        application/javascript
        application/json
        application/xml
        image/svg+xml;

    # --- Security headers ---
    add_header X-Frame-Options       "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection      "1; mode=block" always;
    add_header Referrer-Policy        "strict-origin-when-cross-origin" always;

    # --- WebSocket endpoint (CRITICAL) ---
    location ~ /api/v[0-9]+/(users/)?websocket$ {
        proxy_pass          http://mattermost_backend;
        proxy_http_version  1.1;
        proxy_set_header    Upgrade $http_upgrade;
        proxy_set_header    Connection "upgrade";
        proxy_set_header    Host $host;
        proxy_set_header    X-Real-IP $remote_addr;
        proxy_set_header    X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto $scheme;
        proxy_read_timeout  600s;
        proxy_send_timeout  600s;
    }

    # --- Main proxy ---
    location / {
        proxy_pass          http://mattermost_backend;
        proxy_http_version  1.1;
        proxy_set_header    Connection "";
        proxy_set_header    Host $host;
        proxy_set_header    X-Real-IP $remote_addr;
        proxy_set_header    X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto $scheme;
        proxy_set_header    X-Frame-Options SAMEORIGIN;

        proxy_read_timeout  600s;
        proxy_send_timeout  600s;
        proxy_connect_timeout 60s;

        proxy_buffers       16 16k;
        proxy_buffer_size   32k;
    }
}
```

## Enable the Site

```bash
ln -sf /etc/nginx/sites-available/mattermost /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test configuration (ALWAYS do this before reload)
nginx -t
# Must print: syntax is ok / test is successful

systemctl reload nginx
```

## Testing

### Config Syntax

```bash
nginx -t
```

### HTTP Redirect

```bash
curl -sI http://chat.yourdomain.com | head -3
# HTTP/1.1 301 Moved Permanently
# Location: https://chat.yourdomain.com/
```

### HTTPS Proxy

```bash
curl -sI https://chat.yourdomain.com | head -5
# HTTP/2 200  (or 302 to login page on fresh install)
```

### WebSocket Upgrade

```bash
curl -sI \
  -H "Upgrade: websocket" \
  -H "Connection: Upgrade" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -H "Sec-WebSocket-Version: 13" \
  https://chat.yourdomain.com/api/v4/websocket
# HTTP/1.1 101 Switching Protocols
```

### Mattermost Health

```bash
curl -s https://chat.yourdomain.com/api/v4/system/ping | jq .
# {"status":"OK"}
```

### Direct Backend (bypass Nginx)

```bash
curl -s http://127.0.0.1:8065/api/v4/system/ping
# {"status":"OK"}
# If this fails, Mattermost itself is down -- check: journalctl -u mattermost -f
```

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| 502 Bad Gateway | Mattermost not running or not on :8065 | `systemctl status mattermost`, check `ListenAddress` |
| 413 Request Entity Too Large | `client_max_body_size` too small | Increase in server block, `nginx -t && systemctl reload nginx` |
| WebSocket stuck "Connecting..." | Missing `proxy_set_header Upgrade` | Verify the WebSocket location block exists |
| SSL handshake failure | Wrong cert paths or permissions | Check `ls -la /etc/nginx/ssl/`, key must be readable by nginx |
| 400 No required SSL certificate | Authenticated Origin Pulls enabled but accessing directly | Access through Cloudflare, not server IP |

## Log Locations

```bash
# Access log
tail -f /var/log/nginx/access.log

# Error log
tail -f /var/log/nginx/error.log

# Filter for errors
grep -E '(502|503|504|400)' /var/log/nginx/access.log | tail -20
```
