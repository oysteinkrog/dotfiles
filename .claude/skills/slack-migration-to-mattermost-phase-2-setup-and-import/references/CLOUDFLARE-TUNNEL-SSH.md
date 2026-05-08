# Cloudflare Tunnel + Access for SSH

## Why Replace Exposed Port 22

A standard SSH setup exposes port 22 to the internet. Even with key-only auth and
fail2ban, your server's IP is visible and port 22 is a constant target for brute-force
scanners.

**Cloudflare Tunnel + Access gives you:**

- **Hidden origin IP** -- server has no public-facing ports at all
- **Identity-aware access control** -- SSH requires authentication through Cloudflare (email OTP, Google, Okta, etc.)
- **No open SSH port** -- port 22 can be completely closed in UFW
- **Audit log** -- every SSH session is logged in the Cloudflare dashboard
- **Zero-trust posture** -- no VPN needed, works from any network

## Prerequisites

- Domain on Cloudflare (DNS managed by Cloudflare)
- `cloudflared` installed on both server and local machine
- Cloudflare Zero Trust plan (free tier includes 50 users)

## Server-Side Setup

### 1. Install cloudflared on the Server

```bash
# Debian/Ubuntu (amd64)
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
  -o cloudflared.deb
sudo dpkg -i cloudflared.deb
rm cloudflared.deb

# Verify
cloudflared --version
```

### 2. Authenticate with Cloudflare

```bash
cloudflared login
```

This opens a browser URL. Select the domain you want to use (e.g., `yourdomain.com`).
A certificate is saved to `~/.cloudflared/cert.pem`.

If working on a headless server, copy the URL it prints and open it on your local machine.

### 3. Create the Tunnel

```bash
cloudflared tunnel create mattermost-ssh
```

This outputs a tunnel UUID (e.g., `a1b2c3d4-e5f6-7890-abcd-ef1234567890`).
A credentials file is saved to `~/.cloudflared/<TUNNEL_UUID>.json`.

### 4. Create DNS Route

```bash
cloudflared tunnel route dns mattermost-ssh ssh.yourdomain.com
```

This creates a CNAME record pointing `ssh.yourdomain.com` to the tunnel.

### 5. Configure the Tunnel

Create `/etc/cloudflared/config.yml`:

```yaml
tunnel: a1b2c3d4-e5f6-7890-abcd-ef1234567890
credentials-file: /root/.cloudflared/a1b2c3d4-e5f6-7890-abcd-ef1234567890.json

ingress:
  - hostname: ssh.yourdomain.com
    service: ssh://localhost:22
  - service: http_status:404
```

The last `- service: http_status:404` is a required catch-all rule.

Copy credentials if needed:

```bash
sudo mkdir -p /etc/cloudflared
sudo cp ~/.cloudflared/config.yml /etc/cloudflared/config.yml
sudo cp ~/.cloudflared/*.json /etc/cloudflared/
```

### 6. Test the Tunnel

```bash
cloudflared tunnel run mattermost-ssh
```

You should see `Connection registered` messages. Press Ctrl+C after verifying.

### 7. Install as systemd Service

```bash
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
sudo systemctl status cloudflared
```

Verify it is running:

```bash
journalctl -u cloudflared -f --no-pager -n 20
```

## Cloudflare Access Policy

### 1. Create an Access Application

1. Cloudflare Dashboard > **Zero Trust** > **Access** > **Applications**
2. Click **Add an application** > **Self-hosted**
3. Configure:
   - **Application name**: `Mattermost SSH`
   - **Session duration**: 24 hours (or your preference)
   - **Application domain**: `ssh.yourdomain.com`

### 2. Configure Identity Provider

Under **Zero Trust** > **Settings** > **Authentication**:

- **One-time PIN (email OTP)** -- enabled by default, no setup needed
- **Google** -- add OAuth client ID and secret from Google Cloud Console
- **Okta / Azure AD** -- configure via SAML or OIDC

For a small team, email OTP is simplest. No external IdP setup required.

### 3. Define Access Policy

In the application configuration, add a policy:

- **Policy name**: `Admin SSH Access`
- **Action**: Allow
- **Include rule**: Emails -- list your admin email addresses
  - `admin@yourdomain.com`
  - `jeff@yourdomain.com`
- **Or**: Email domain -- `@yourdomain.com` (all company emails)

Click **Save**.

Anyone not matching the policy gets a 403 Forbidden.

## Local Machine Setup (Mac/Windows/Linux)

### 1. Install cloudflared Locally

```bash
# macOS
brew install cloudflared

# Windows (winget)
winget install Cloudflare.cloudflared

# Linux
# Same as server install above
```

### 2. Configure SSH ProxyCommand

Add to `~/.ssh/config`:

```ssh-config
Host ssh.yourdomain.com
  ProxyCommand cloudflared access ssh --hostname %h
  User your-ssh-username
  IdentityFile ~/.ssh/your_key
```

### 3. Connect

```bash
ssh ssh.yourdomain.com
```

The first time, `cloudflared` opens a browser for Cloudflare Access authentication.
After authenticating, a short-lived certificate is cached and subsequent connections
are seamless until the session expires.

## Close Port 22 in UFW

Once the tunnel is confirmed working, close port 22:

```bash
# IMPORTANT: Test tunnel SSH access thoroughly before doing this.
# If the tunnel fails and port 22 is closed, you are locked out.
# Keep a console/VNC session available as a fallback.

sudo ufw delete allow 22/tcp
sudo ufw delete allow OpenSSH
sudo ufw status
```

**Safety net**: Most VPS providers offer a web-based console (DigitalOcean Droplet Console,
Hetzner VNC, AWS EC2 Instance Connect). Verify you can access this before closing port 22.

## Bonus: Protect Mattermost Admin Console

The same tunnel can protect sensitive web paths. Add to `/etc/cloudflared/config.yml`:

```yaml
ingress:
  - hostname: ssh.yourdomain.com
    service: ssh://localhost:22
  - hostname: admin.yourdomain.com
    service: http://localhost:8065
    path: /admin_console.*
  - service: http_status:404
```

Then create a separate Access Application for `admin.yourdomain.com` with the same
admin-only policy. The public Mattermost URL continues to work through Nginx/Cloudflare
proxy as normal.

## Troubleshooting

| Issue | Diagnosis | Fix |
|-------|-----------|-----|
| `connection refused` locally | cloudflared not in PATH | Install cloudflared on local machine |
| Browser auth loop | Access policy too restrictive | Check email matches in the policy |
| `failed to connect to origin` | SSH not running on server | `sudo systemctl status sshd` |
| Tunnel disconnects | cloudflared service crashed | `sudo systemctl restart cloudflared`, check logs |
| `no such tunnel` | Wrong tunnel UUID in config | `cloudflared tunnel list` to get correct UUID |
| Locked out after closing port 22 | Tunnel misconfigured | Use VPS provider web console to re-open port |

## Maintenance

```bash
# Update cloudflared on server
sudo apt update && sudo apt upgrade cloudflared

# Check tunnel health
cloudflared tunnel info mattermost-ssh

# View active connections
cloudflared tunnel list

# Rotate tunnel credentials (if compromised)
cloudflared tunnel delete mattermost-ssh
cloudflared tunnel create mattermost-ssh
# Update config.yml with new UUID and credentials, restart service
```
