# Server Provisioning Runbook

## Provider Selection

### Hetzner Dedicated (Recommended)

Order at https://www.hetzner.com/dedicated-rootserver/

| Model | CPU | RAM | Storage | Monthly |
|-------|-----|-----|---------|---------|
| AX42-U | Ryzen 7 PRO 8700GE (8c/16t) | 64GB DDR5 | 2x512GB NVMe | ~$50 |
| AX52 | Ryzen 7 7700 (8c/16t) | 64GB DDR5 | 2x1TB NVMe | ~$70 |
| AX102 | Ryzen 9 7950X3D (16c/32t) | 128GB DDR5 | 2x1TB NVMe | ~$130 |

### OVH Bare Metal

Order at https://www.ovhcloud.com/en/bare-metal/prices/

| Model | CPU | RAM | Storage | Monthly |
|-------|-----|-----|---------|---------|
| Advance-1 | Intel Xeon-E 2386G | 32GB DDR4 ECC | 2x512GB NVMe | ~$70 |
| Advance-2 | EPYC 4345P (8c/16t) | 64GB DDR5 ECC | 2x960GB NVMe | ~$90 |

**Target spec:** 8+ cores, 64GB RAM, 2x NVMe (for RAID 1). OS: **Ubuntu 24.04 LTS**.

Both providers let you select Ubuntu 24.04 at order time. Hetzner also offers a rescue system for custom installs.

## Initial Access

```bash
# From your Mac/Windows machine. Provider emails root password or you set SSH key at order.
ssh root@YOUR_SERVER_IP

# Verify OS
lsb_release -a
# Should show: Ubuntu 24.04.x LTS
```

## Disk Setup: Software RAID 1

If the provider didn't configure RAID at order time (Hetzner lets you choose):

```bash
# Check current disks
lsblk
# Expect: nvme0n1 and nvme1n1 (two NVMe drives)

# If provider used installimage (Hetzner), RAID is likely already configured.
# Verify:
cat /proc/mdstat
# Should show md0, md1, etc. with [UU] (both drives healthy)

# If you need to set up from scratch via Hetzner rescue:
# Boot into rescue mode from Hetzner Robot panel, then:
installimage
# Select: Ubuntu 24.04, RAID 1, partition layout as needed
```

### Partition Layout (Recommended)

| Mount | Size | Type |
|-------|------|------|
| `/boot` | 1GB | ext4, RAID 1 |
| `swap` | 8GB | RAID 1 |
| `/` | remainder | ext4 or xfs, RAID 1 |

For production with LUKS encryption (optional):

```bash
# During installimage or manual setup:
# Create RAID arrays first, then LUKS on top of the root RAID device
cryptsetup luksFormat /dev/md1
cryptsetup open /dev/md1 cryptroot
mkfs.ext4 /dev/mapper/cryptroot
# Update /etc/crypttab and /etc/fstab accordingly
# Note: requires physical/IPMI console for boot passphrase entry
```

## Create Non-Root User

```bash
adduser deploy
usermod -aG sudo deploy

# Copy SSH authorized_keys to new user
mkdir -p /home/deploy/.ssh
cp /root/.ssh/authorized_keys /home/deploy/.ssh/
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys

# Test login from your local machine BEFORE locking root
ssh deploy@YOUR_SERVER_IP
sudo whoami  # should print: root
```

## SSH Hardening

```bash
# Back up original config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Apply hardening
cat >> /etc/ssh/sshd_config.d/hardening.conf << 'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers deploy
EOF

# Validate before restarting (critical -- a bad config locks you out)
sshd -t
# Must print nothing (no errors)

systemctl restart sshd

# Test from a NEW terminal before closing current session
ssh deploy@YOUR_SERVER_IP
```

## Firewall (UFW)

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP redirect'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 8443/udp comment 'Mattermost Calls plugin'
ufw enable
ufw status verbose
```

## Fail2ban

```bash
apt update && apt install -y fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF

systemctl enable fail2ban
systemctl restart fail2ban
fail2ban-client status sshd
```

## Unattended Security Upgrades

```bash
apt install -y unattended-upgrades apt-listchanges

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "your-email@example.com";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF

# Verify
unattended-upgrades --dry-run --debug 2>&1 | head -20
```

## Swap Configuration

With 64GB RAM, swap is a safety net, not a crutch.

```bash
# Check if swap already exists (Hetzner installimage often creates it)
swapon --show

# If no swap exists:
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Tune swappiness (low value = prefer RAM, swap only under pressure)
echo 'vm.swappiness=10' >> /etc/sysctl.d/99-swap.conf
sysctl -p /etc/sysctl.d/99-swap.conf
```

## NTP / Time Sync

```bash
# Ubuntu 24.04 uses systemd-timesyncd by default
timedatectl set-timezone UTC
timedatectl set-ntp true
timedatectl status
# Should show: NTP service: active, System clock synchronized: yes
```

## Hostname

```bash
hostnamectl set-hostname mm-prod-01
echo "127.0.1.1 mm-prod-01" >> /etc/hosts

# Verify
hostname -f
```

## System Tuning

```bash
cat >> /etc/sysctl.d/99-mattermost.conf << 'EOF'
# Network performance
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.core.netdev_max_backlog = 4096

# File descriptors
fs.file-max = 524288

# Keep connections alive
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5
EOF

sysctl -p /etc/sysctl.d/99-mattermost.conf

# Raise file descriptor limits for mattermost user (created later by apt install)
cat >> /etc/security/limits.d/mattermost.conf << 'EOF'
mattermost soft nofile 65536
mattermost hard nofile 65536
EOF
```

## Final Verification Checklist

```bash
# Run all checks
echo "=== OS ===" && lsb_release -a 2>/dev/null | grep Description
echo "=== RAID ===" && cat /proc/mdstat | grep -E 'md[0-9]'
echo "=== User ===" && id deploy
echo "=== SSH ===" && sshd -t && echo "config OK"
echo "=== UFW ===" && ufw status | grep -c ALLOW
echo "=== fail2ban ===" && fail2ban-client status sshd | grep "Currently banned"
echo "=== Swap ===" && swapon --show
echo "=== NTP ===" && timedatectl show | grep NTPSynchronized
echo "=== Hostname ===" && hostname -f
echo "=== Kernel ===" && uname -r
```

Server is ready for Stage 2 (PostgreSQL + Mattermost installation).
