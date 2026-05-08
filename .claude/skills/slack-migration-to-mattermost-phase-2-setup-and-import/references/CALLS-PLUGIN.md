# Mattermost Calls Plugin -- Voice/Video Setup Guide

## Overview

The Calls plugin provides built-in voice and video calling in Mattermost channels. It uses WebRTC, which requires UDP connectivity -- this creates specific networking challenges, especially behind Cloudflare or restrictive firewalls.

## Installation

### Via Plugin Marketplace (Recommended)

1. System Console > Plugin Marketplace
2. Search "Calls"
3. Click **Install** then **Enable**

### Manual Installation

```bash
# Download the latest release
CALLS_VERSION="1.3.0"  # Check https://github.com/mattermost/mattermost-plugin-calls/releases
wget "https://github.com/mattermost/mattermost-plugin-calls/releases/download/v${CALLS_VERSION}/com.mattermost.calls-${CALLS_VERSION}.tar.gz"

# Upload via mmctl
mmctl plugin add "com.mattermost.calls-${CALLS_VERSION}.tar.gz" --local
mmctl plugin enable com.mattermost.calls
```

### Verify Installation

```bash
mmctl plugin list --local
# Should show: com.mattermost.calls (active)
```

## Critical Networking: UDP and Cloudflare

### The Problem

Mattermost Calls uses WebRTC, which requires **UDP port 8443** for media transport. Cloudflare's proxy (orange cloud) only handles HTTP, HTTPS, and WebSocket traffic over TCP. **Cloudflare cannot proxy UDP traffic.** Calls will silently fail if all DNS goes through Cloudflare's proxy.

### The Solution: DNS-Only Record

Create a **separate DNS record** with Cloudflare proxy **disabled** (grey cloud / DNS-only):

| Type | Name        | Content          | Proxy              | TTL  |
|------|-------------|------------------|---------------------|------|
| A    | `calls`     | `YOUR_SERVER_IP` | DNS only (grey cloud) | Auto |

This means `calls.yourdomain.com` resolves directly to your server IP. Your main `chat.yourdomain.com` stays proxied (orange cloud) for DDoS protection.

### Configure Calls Plugin to Use the DNS-Only Hostname

System Console > Plugins > Calls:

- **ICE Host Override**: `calls.yourdomain.com`
- **UDP Server Port**: `8443`
- **Enable on all channels**: your preference
- **Max call participants**: adjust based on server capacity (default: 8)

Or edit `config.json` directly:

```json
{
  "PluginSettings": {
    "Plugins": {
      "com.mattermost.calls": {
        "icehostoverride": "calls.yourdomain.com",
        "udpserverport": 8443,
        "maxcallparticipants": 8,
        "allowscreensharing": true,
        "enablerecordings": false,
        "defaultenabled": true
      }
    }
  }
}
```

After editing config.json, restart Mattermost:

```bash
sudo systemctl restart mattermost
```

## Firewall Rules (UFW)

```bash
# Allow UDP traffic for WebRTC media
sudo ufw allow 8443/udp comment "Mattermost Calls WebRTC"

# Verify the rule is active
sudo ufw status verbose | grep 8443
# Expected: 8443/udp ALLOW IN Anywhere

# If using TURN server as well (see below):
sudo ufw allow 3478/udp comment "TURN server"
sudo ufw allow 3478/tcp comment "TURN server TCP"
```

### iptables Alternative

```bash
iptables -A INPUT -p udp --dport 8443 -j ACCEPT
# Save:
netfilter-persistent save
```

## NAT / Cloud Firewall Considerations

If your server is behind NAT (AWS EC2, GCP, DigitalOcean with VPC, etc.):

1. **Cloud firewall/security group**: open UDP 8443 inbound from `0.0.0.0/0`
2. **ICE Host Override**: set to the **public** IP or the DNS-only hostname -- not the private IP
3. **AWS-specific**: also check the VPC Network ACL (NACLs are stateless -- need both inbound and outbound rules for UDP 8443)

```bash
# Verify your server can receive UDP on 8443 from outside
# From a different machine:
nc -u -z YOUR_SERVER_IP 8443 -v

# On the server, listen:
nc -u -l 8443
```

## RTCD (Real-Time Communication Daemon)

For self-hosted Enterprise deployments with many concurrent callers, Mattermost recommends running a dedicated **RTCD** server to offload WebRTC processing from the main Mattermost application server.

### When You Need RTCD

- More than ~50 concurrent call users
- Want to isolate media processing from the app server
- Running Mattermost in High Availability (multi-node) mode
- Need better call quality under load

### RTCD Setup (Separate Server)

```bash
# On the RTCD server:
wget https://github.com/mattermost/rtcd/releases/latest/download/rtcd-linux-amd64.tar.gz
tar xzf rtcd-linux-amd64.tar.gz
sudo mv rtcd /usr/local/bin/

# Generate config
rtcd init

# Edit /etc/rtcd/config.toml
# Key settings:
#   [api]
#   security.admin_secret_key = "GENERATE_A_STRONG_KEY"
#   [rtc]
#   udp_server_port = 8443
#   ice_host_override = "rtcd.yourdomain.com"

# Create systemd service
sudo tee /etc/systemd/system/rtcd.service > /dev/null <<'EOF'
[Unit]
Description=Mattermost RTCD
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/rtcd serve --config /etc/rtcd/config.toml
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now rtcd
```

### Connect Mattermost to RTCD

In Calls plugin settings or `config.json`:

```json
{
  "com.mattermost.calls": {
    "rtcdserviceurl": "https://rtcd.yourdomain.com:8045"
  }
}
```

## TURN Server Setup

Some users sit behind restrictive corporate firewalls that block UDP entirely. A TURN (Traversal Using Relays around NAT) server relays media over TCP as a fallback.

### Using coturn

```bash
sudo apt install -y coturn

# Enable coturn service
sudo sed -i 's/#TURNSERVER_ENABLED=1/TURNSERVER_ENABLED=1/' /etc/default/coturn

# Configure /etc/turnserver.conf:
sudo tee /etc/turnserver.conf > /dev/null <<'EOF'
listening-port=3478
tls-listening-port=5349
realm=yourdomain.com
server-name=turn.yourdomain.com
fingerprint
lt-cred-mech
use-auth-secret
static-auth-secret=YOUR_VERY_LONG_RANDOM_SECRET
total-quota=100
stale-nonce=600
cert=/etc/letsencrypt/live/turn.yourdomain.com/fullchain.pem
pkey=/etc/letsencrypt/live/turn.yourdomain.com/privkey.pem
no-multicast-peers
EOF

sudo systemctl enable --now coturn
```

### Configure Calls Plugin for TURN

```json
{
  "com.mattermost.calls": {
    "iceservers": "[{\"urls\":[\"turn:turn.yourdomain.com:3478\"],\"username\":\"mattermost\",\"credential\":\"YOUR_VERY_LONG_RANDOM_SECRET\"}]"
  }
}
```

## Testing Calls

### Quick Smoke Test

1. Open any channel in Mattermost
2. Click the phone icon in the channel header
3. A call should start -- your browser will ask for microphone permission
4. Have a second user (or second browser/incognito) join the same call
5. Verify two-way audio works

### Network Diagnostic

```bash
# Check that UDP 8443 is listening
sudo ss -ulnp | grep 8443

# Check from an external client (requires netcat on client):
echo "test" | nc -u calls.yourdomain.com 8443

# Check Mattermost logs for Calls errors:
journalctl -u mattermost --since "5 minutes ago" | grep -i "calls\|rtc\|webrtc\|ice"

# Verify DNS-only record resolves to server IP (not Cloudflare):
dig +short calls.yourdomain.com
# Should return YOUR_SERVER_IP directly, NOT a Cloudflare IP (104.x.x.x / 172.x.x.x)
```

## Common Issues and Fixes

### "Cannot connect to call" / Call never connects

**Root cause**: almost always a firewall or Cloudflare proxy issue.

1. Verify UFW allows UDP 8443: `sudo ufw status | grep 8443`
2. Verify the DNS record is DNS-only (grey cloud), not proxied
3. Verify `dig +short calls.yourdomain.com` returns your server IP
4. Check cloud provider security group / firewall allows UDP 8443 inbound
5. Check ICE Host Override is set to the DNS-only hostname

### Echo / Poor Audio Quality

- Usually caused by media being relayed through TURN instead of direct UDP
- Check if the user is behind a restrictive firewall forcing TURN fallback
- If widespread, verify UDP 8443 is actually reachable (not just TCP)
- Check server CPU -- WebRTC media processing is CPU-intensive

### Calls Work Locally but Not Remotely

- ICE Host Override is probably set to a private/LAN IP instead of the public hostname
- Fix: set `icehostoverride` to `calls.yourdomain.com` (the DNS-only record)

### Cloudflare Blocking UDP

- This is by design. Cloudflare proxy is TCP-only.
- You **must** use a DNS-only record for the Calls endpoint
- Alternatively, use a completely separate domain/subdomain not on Cloudflare

### Screen Sharing Not Working

- Ensure `allowscreensharing` is `true` in plugin config
- Browser must be running over HTTPS (WebRTC screen capture requires secure context)
- Some browsers require additional permissions -- check browser console for errors

### Recordings Not Working

- Requires Mattermost Enterprise license
- Requires Calls plugin v0.17+ and a running `calls-recorder` sidecar
- Check System Console > Plugins > Calls > Enable Recordings
