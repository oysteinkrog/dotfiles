# Docker Compose vs APT Package Install

> Detailed comparison of the two primary Mattermost deployment methods.
> Recommendation: **APT for production**, Docker for dev/staging.

---

## Version Requirements

As of early 2026, Mattermost 10.5 ESR reached end of life in November 2025.
You must use **Mattermost 10.11+** (current stable) or the latest ESR if one has been designated.
Both APT and Docker support 10.11+.

---

## APT Package Install

### Advantages

1. **Native systemd integration** -- `systemctl start/stop/restart/status mattermost` works exactly like every other service on the box
2. **Automatic security updates** via `unattended-upgrades` -- Mattermost's PPA packages get pulled in automatically
3. **Simple debugging** -- `journalctl -u mattermost -f` for real-time logs, no container layers to pierce
4. **Official PPA** maintained by Mattermost Inc. -- not a community package
5. **Supported OS versions:** Ubuntu 20.04, 22.04, 24.04 LTS
6. **Direct filesystem access** -- config at `/opt/mattermost/config/config.json`, binaries at `/opt/mattermost/bin/`
7. **No Docker daemon dependency** -- one fewer service that can crash and take Mattermost down with it
8. **Lower memory overhead** -- no container runtime, no overlay filesystem

### Installation Commands

```bash
# Add the Mattermost APT repository
curl -o- https://deb.packages.mattermost.com/repo-setup.sh | sudo bash -s mattermost

# Install Mattermost
sudo apt install -y mattermost

# Verify installation
mattermost version
# Expected: 10.11.x or later

# Service management
sudo systemctl enable mattermost
sudo systemctl start mattermost
sudo systemctl status mattermost

# View logs
journalctl -u mattermost -f --no-pager

# Configuration
sudo nano /opt/mattermost/config/config.json

# Upgrade (with unattended-upgrades, this happens automatically for security patches)
sudo apt update && sudo apt upgrade -y mattermost
```

If the target host is not on a Mattermost-supported Ubuntu LTS release, the package repo may not expose the server package at all. In exact-flow validation on Ubuntu `questing`, the repo setup succeeded but `mattermost` was unavailable, so the skill fell back to the Docker path.

### Automatic Updates Setup

```bash
# Ensure unattended-upgrades is installed and configured
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# Verify the Mattermost repo is included in automatic updates
cat /etc/apt/apt.conf.d/50unattended-upgrades
# Should include the Mattermost origin or be configured to update all sources

# To limit to security updates only (safer for production):
# Edit /etc/apt/apt.conf.d/50unattended-upgrades and ensure
# Unattended-Upgrade::Allowed-Origins includes the Mattermost source
```

---

## Docker Compose

### Advantages

1. **Isolation** -- Mattermost runs in its own container with defined resource limits
2. **Reproducibility** -- `docker-compose.yml` is version-controlled, identical deploys everywhere
3. **Easy dev/staging** -- spin up a throwaway instance in seconds for testing imports
4. **Multi-version testing** -- run 10.11 and 10.12-rc side by side on different ports
5. **Clean teardown** -- `docker compose down -v` removes everything, no leftover state

For the executable skill path in this repo, Docker still sits behind Nginx. Mattermost binds to `127.0.0.1:8065`, Nginx fronts `80`/`443`, and exact-flow imports use the server-bundled `mmctl --local` via SSH when `ENABLE_LOCAL_MODE=1`.

### Installation Commands

```bash
# Clone the official Docker deployment repo
git clone https://github.com/mattermost/docker.git mattermost-docker
cd mattermost-docker

# Copy and edit environment file
cp env.example .env
nano .env
# Set: MATTERMOST_IMAGE_TAG=10.11
# Set: DOMAIN=chat.yourdomain.com
# Set: MM_SQLSETTINGS_DATASOURCE=postgres://mmuser:your_password@db:5432/mattermost?sslmode=disable

# Create required directories
mkdir -p ./volumes/app/mattermost/{config,data,logs,plugins,client/plugins,bleve-indexes}
sudo chown -R 2000:2000 ./volumes/app/mattermost

# Start
docker compose up -d

# View logs
docker compose logs -f app

# Check status
docker compose ps

# Upgrade
# Edit .env to change MATTERMOST_IMAGE_TAG, then:
docker compose pull
docker compose up -d

# Full teardown (destroys data!)
docker compose down -v
```

### Docker Compose File (Key Sections)

```yaml
services:
  app:
    image: mattermost/mattermost-enterprise-edition:${MATTERMOST_IMAGE_TAG}
    restart: unless-stopped
    # IMPORTANT: Do NOT use pids_limit. Use mem_limit instead.
    mem_limit: 4g
    ports:
      - "8065:8065"
      - "8443:8443/udp"  # Calls plugin
    volumes:
      - ./volumes/app/mattermost/config:/mattermost/config
      - ./volumes/app/mattermost/data:/mattermost/data
      - ./volumes/app/mattermost/logs:/mattermost/logs
      - ./volumes/app/mattermost/plugins:/mattermost/plugins
    depends_on:
      - db

  db:
    image: postgres:16-alpine
    restart: unless-stopped
    # IMPORTANT: Do NOT use pids_limit here either
    mem_limit: 2g
    volumes:
      - ./volumes/db:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: mmuser
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: mattermost
```

---

## The pids_limit Bug

This deserves its own section because it has bitten real deployments.

**What happened:** The default Docker Compose configuration shipped by Mattermost included `pids_limit: 200`
on the PostgreSQL container. Under load, PostgreSQL spawns backend processes for each connection.
When the process count hit 200, new connections were refused with cryptic errors. Mattermost would
log database connection failures and become unresponsive.

**The fix:** Mattermost now recommends using `mem_limit` instead of `pids_limit` for resource control.
If you see `pids_limit` in any Docker Compose configuration, remove it.

```yaml
# BAD -- do not use
services:
  db:
    pids_limit: 200  # This WILL break under load

# GOOD -- use mem_limit instead
services:
  db:
    mem_limit: 2g
```

**Lesson:** Container resource limits can interact with database behavior in unexpected ways.
With APT install, PostgreSQL runs natively and this entire category of bugs is avoided.

---

## Docker Is Not Recommended for HA

From Mattermost's own documentation:

> "Docker is not recommended for High Availability (HA) deployments. For HA, use Kubernetes."

The reasoning:
- Docker Compose manages services on a single host -- it cannot coordinate across multiple nodes
- Docker Swarm exists but Mattermost does not officially support or test it
- Kubernetes (via the official Mattermost Helm chart) is the supported path for HA
- If you start with Docker and later need HA, you face a full migration to Kubernetes

This means Docker locks you into single-node unless you're willing to re-architect.
APT install on a single node transitions more cleanly to a multi-node APT-based HA setup
(with a load balancer in front), though Kubernetes is still the preferred HA path.

---

## When to Use Which

| Scenario | Recommendation | Reason |
|----------|---------------|--------|
| Production (1000+ users) | APT | Simpler ops, native systemd, auto-updates |
| Production single-node (<250 users) | Either works | Docker is fine at low scale |
| Development/testing | Docker | Fast spin-up, easy teardown |
| Staging environment | Docker | Reproducible, disposable |
| Import testing | Docker | Test imports without affecting production |
| HA deployment | Kubernetes | Neither Docker Compose nor APT alone handle HA |
| Air-gapped environment | APT (with local repo mirror) | No Docker Hub dependency |

---

## Migration Path: Docker to APT

If you started with Docker and want to switch to APT:

```bash
# 1. Export current config
docker compose exec app cat /mattermost/config/config.json > config-backup.json

# 2. Dump the database
docker compose exec db pg_dump -U mmuser mattermost > mattermost-backup.sql

# 3. Copy file attachments (if using local storage)
sudo cp -r ./volumes/app/mattermost/data /tmp/mattermost-data-backup

# 4. Stop Docker
docker compose down

# 5. Install via APT
curl -o- https://deb.packages.mattermost.com/repo-setup.sh | sudo bash -s mattermost
sudo apt install -y mattermost

# 6. Install PostgreSQL natively (if it was in Docker)
sudo apt install -y postgresql-16
sudo -u postgres createuser mmuser
sudo -u postgres createdb -O mmuser mattermost
sudo -u postgres psql -c "ALTER USER mmuser WITH PASSWORD 'your_password';"

# 7. Restore database
psql -U mmuser -d mattermost < mattermost-backup.sql

# 8. Restore config
sudo cp config-backup.json /opt/mattermost/config/config.json
sudo chown mattermost:mattermost /opt/mattermost/config/config.json

# 9. Restore file data (if local storage)
sudo cp -r /tmp/mattermost-data-backup/* /opt/mattermost/data/
sudo chown -R mattermost:mattermost /opt/mattermost/data/

# 10. Start
sudo systemctl enable mattermost
sudo systemctl start mattermost
```

---

## Summary

APT wins for production because it removes an entire layer of abstraction (the container runtime)
that adds failure modes without adding meaningful value for a single-node chat server. Docker wins
for development because disposability and reproducibility matter more than operational simplicity
in that context. If you anticipate needing HA, skip Docker entirely and plan for Kubernetes.
