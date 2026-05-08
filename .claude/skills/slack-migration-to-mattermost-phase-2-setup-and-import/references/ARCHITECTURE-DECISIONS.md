# Architecture Decision Records

> Every major component choice in a Mattermost deployment, documented as a decision record.
> Each record captures context, the decision made, consequences, and alternatives considered.
> Written from real deployment experience for ~1000-user organizations.

---

## ADR-001: Server Provider

### Context

We need a dedicated server for a self-hosted Mattermost deployment serving ~1000 registered users.
The server will run Mattermost, PostgreSQL, Nginx, and supporting services on a single box.
We need 8+ cores, 64GB RAM, and mirrored NVMe storage. Budget matters but so does reliability.

### Decision

**Hetzner AX52** as the primary recommendation; **OVH Advance-2** when production safety outweighs budget.

### Consequences

**Hetzner AX52 (~$70/month):**
- Ryzen 7 7700 (8c/16t Zen4), 64GB DDR5, 2x1TB Gen4 NVMe
- Best price-to-performance ratio in the market for this class of hardware
- Available in Falkenstein (DE) and Helsinki (FI) -- latency to US East Coast is 80-120ms
- Robot panel for rescue mode, installimage, hardware RAID setup at provision time
- Known limitation: no ECC memory on consumer Ryzen parts
- Hetzner's abuse department is aggressive -- make sure you comply with GDPR if hosting EU user data

**OVH Advance-2 (~$90/month):**
- EPYC 4345P (8c/16t), 64GB DDR5 ECC, 2x960GB NVMe
- ECC memory provides data integrity guarantees that matter for database workloads
- OVH has data centers in US (Vint Hill, VA) and Canada (Beauharnois, QC) -- lower latency for NA users
- Better SLA and incident response than Hetzner for production workloads
- vRack private networking available if you later add a second node

**Contabo:**
- On paper, Contabo offers similar specs at lower prices
- In practice: oversubscribed network, inconsistent disk I/O, slower support response
- Not recommended for a single-purpose production chat server where reliability matters
- Acceptable for a throwaway staging/testing instance

### Alternatives Considered

- **Cloud VPS (AWS/GCP/Azure):** Equivalent specs cost $300-600/month. Not justified for a chat server that doesn't need auto-scaling or managed services.
- **Hetzner Cloud:** Cheaper per month but shared resources. Dedicated metal gives predictable performance for PostgreSQL and avoids noisy-neighbor I/O spikes.
- **Hetzner AX42 (~$50/month):** Ryzen 7 PRO 8700GE with 2x512GB NVMe. Viable if you offload file storage to S3/R2 early. The 512GB drives limit runway for local file storage.

---

## ADR-002: Database Placement

### Context

PostgreSQL is the only production-supported database for Mattermost. MySQL is supported but PostgreSQL is
recommended. The question is whether to run PostgreSQL on the same server as Mattermost or on a separate machine.

### Decision

**Single-box deployment** (PostgreSQL on the same server as Mattermost). This is the single biggest compromise
in the architecture, and it should be made deliberately.

### Consequences

**Why single-box despite Mattermost recommending separate:**
- Mattermost's documentation explicitly recommends a separate database server for production
- However, for <2000 concurrent users, a single box with 64GB RAM and NVMe is more than adequate
- Running separate servers doubles your infrastructure cost and operational burden
- PostgreSQL on NVMe with 16GB of shared_buffers handles Mattermost's query patterns without breaking a sweat
- The bottleneck for most Mattermost deployments is network/WebSocket, not database I/O

**Resource allocation on a single box (64GB RAM):**
- PostgreSQL: shared_buffers=16GB, effective_cache_size=32GB, work_mem=256MB
- Mattermost: typically uses 2-4GB RSS for 1000 concurrent users
- OS page cache: remainder (~12-16GB) serves as additional disk cache
- NVMe IOPS (500K+ random reads) eliminate the disk I/O argument for separation

**When to split:**
- If you hit >2000 concurrent users (not registered -- concurrent)
- If PostgreSQL WAL writes start competing with Mattermost file I/O
- If you need HA (at which point you need Enterprise license anyway)
- If compliance requires database-level network isolation

**Mitigation:**
- Monitor with `pg_stat_activity` and Prometheus/Grafana
- Set up streaming replication to a cheap secondary for backups (does not require separate production DB)
- Use connection pooling (Mattermost has built-in pool; PgBouncer is overkill for single-box)

### Alternatives Considered

- **Separate DB server:** Doubles cost to ~$140/month minimum. Adds network latency between app and DB (even on the same provider's private network, 0.1-0.5ms adds up over thousands of queries per second). Worth it only at scale.
- **Managed PostgreSQL (Hetzner, Aiven, Supabase):** Adds $50-200/month. Removes operational burden for backups and upgrades, but introduces network dependency. Better for teams without a sysadmin.

---

## ADR-003: APT Package vs Docker Compose

### Context

Mattermost offers two primary deployment methods: APT package install (via their official PPA) and
Docker Compose. The choice affects upgradeability, debugging, and HA readiness.

### Decision

**APT package install for production.** Docker Compose for development/staging only.

### Consequences

See `references/DOCKER-VS-APT.md` for the full comparison. Summary:

- APT integrates with systemd for service management, journalctl for logging, and unattended-upgrades for automatic security patches
- Mattermost's own documentation states Docker is not recommended for HA deployments
- The `pids_limit` Docker bug that broke PostgreSQL connections was a real production incident -- Mattermost now recommends `mem_limit` instead, but this kind of footgun is avoided entirely with APT
- Docker adds a layer of abstraction that makes debugging harder when things go wrong at 2 AM
- APT install path: `/opt/mattermost/` with config at `/opt/mattermost/config/config.json`

### Alternatives Considered

- **Docker Compose:** Legitimate for staging environments, CI/CD test instances, and teams with strong container expertise. Not recommended for the production instance.
- **Kubernetes (Helm chart):** The correct path for HA at scale. Requires Enterprise license. Overkill for single-node deployments. See `references/HA-SCALING.md`.
- **Snap package:** Exists but poorly maintained. Avoid.

---

## ADR-004: File Storage -- Local vs Cloudflare R2

### Context

Mattermost stores uploaded files (images, documents, attachments) either on local disk or in
S3-compatible object storage. The choice affects disk pressure, backup complexity, and HA readiness.

### Decision

**Cloudflare R2 for production.** Local storage is acceptable for initial setup and testing,
but migrate to R2 before going live.

### Consequences

**R2 advantages:**
- No egress fees (unique among S3-compatible providers)
- Reduces disk pressure on the server -- uploaded files don't consume NVMe space
- Required for future HA (multiple app nodes need shared file access)
- Simplifies backups -- files are durably stored by Cloudflare, you only back up the database
- Free tier: 10GB storage, 10M Class A ops, 1M Class B ops per month
- Paid: $0.015/GB/month storage -- 1TB costs $15/month

**R2 configuration in Mattermost:**
```json
{
  "FileSettings": {
    "DriverName": "amazons3",
    "AmazonS3AccessKeyId": "your-r2-access-key",
    "AmazonS3SecretAccessKey": "your-r2-secret-key",
    "AmazonS3Bucket": "mattermost-files",
    "AmazonS3Region": "",
    "AmazonS3Endpoint": "your-account-id.r2.cloudflarestorage.com",
    "AmazonS3SSL": true,
    "AmazonS3SignV2": false,
    "AmazonS3SSE": false,
    "AmazonS3PathStyle": true
  }
}
```

**Local storage risks:**
- 1000 users generating 5-25MB/user/month = 60-300GB/year
- 2x1TB NVMe in RAID 1 gives 1TB usable -- fills in 3-10 years
- File backups become expensive and slow as volume grows
- Blocks future HA migration (must move files to S3 first)

### Alternatives Considered

- **AWS S3:** Works perfectly with Mattermost. Egress fees ($0.09/GB) add up with many file downloads. R2 has zero egress.
- **Hetzner Object Storage:** S3-compatible, very cheap ($0.005/GB/month), available in Falkenstein. No egress fees within Hetzner network. Good option if your server is at Hetzner and you prefer to keep everything with one provider.
- **MinIO on the same box:** Adds operational complexity for no real benefit over local storage on a single node. Only useful as an S3-compatibility layer for testing.
- **Backblaze B2:** S3-compatible, cheap ($0.005/GB/month), but egress fees apply outside Cloudflare alliance.

---

## ADR-005: TLS Certificate -- Cloudflare Origin CA vs Let's Encrypt

### Context

The Nginx reverse proxy in front of Mattermost needs a TLS certificate. Since we're behind Cloudflare's proxy
(orange cloud), we have a choice between Cloudflare's free Origin CA certificate and Let's Encrypt.

### Decision

**Cloudflare Origin CA certificate.** Simpler, longer-lived, no renewal automation needed.

### Consequences

**Origin CA advantages:**
- 15-year validity period -- set it and forget it
- No certbot, no cron jobs, no renewal failures at 3 AM
- Free, unlimited certificates
- Trusted by Cloudflare's edge servers (which is all that matters when proxied)

**Origin CA limitations:**
- Only valid when traffic flows through Cloudflare's proxy (orange cloud enabled)
- If you ever need to bypass Cloudflare (grey cloud / DNS-only), the cert won't be trusted by browsers
- Not a publicly trusted CA -- cannot be used for non-Cloudflare traffic

**Setup:**
```bash
# 1. Generate in Cloudflare dashboard: SSL/TLS → Origin Server → Create Certificate
# 2. Choose PEM format, 15-year validity, hostnames: *.yourdomain.com, yourdomain.com
# 3. Save the certificate and private key

# On the server:
sudo mkdir -p /etc/cloudflare
sudo tee /etc/cloudflare/origin.pem    # paste certificate
sudo tee /etc/cloudflare/origin.key    # paste private key
sudo chmod 600 /etc/cloudflare/origin.key

# In nginx.conf:
# ssl_certificate /etc/cloudflare/origin.pem;
# ssl_certificate_key /etc/cloudflare/origin.key;
```

**Cloudflare SSL mode must be Full (Strict):** This ensures Cloudflare validates the origin certificate.
Plain "Full" mode would also work but doesn't validate, defeating the purpose.

### Alternatives Considered

- **Let's Encrypt (certbot):** Free, publicly trusted, auto-renewing. Requires port 80 open for HTTP-01 challenge or DNS-01 via Cloudflare API plugin. More moving parts. Better choice if you might ever serve traffic without Cloudflare.
- **Paid CA certificate:** No advantage over Origin CA for a Cloudflare-proxied site. Unnecessary cost.

---

## ADR-006: Single Node vs High Availability

### Context

Mattermost supports both single-node deployment and HA (multiple app nodes behind a load balancer).
HA requires Enterprise E20 license. The question is whether to deploy HA from day one.

### Decision

**Start single-node. Plan for HA from day one in your architecture choices, but don't deploy it
until you hit scaling limits.**

### Consequences

**The 2000-concurrent-user boundary:**
- Mattermost's own reference architecture puts the single-node ceiling at ~2000 concurrent users
- This is concurrent (active WebSocket connections), not registered users
- 1000 registered users typically means 100-300 concurrent during business hours
- You have significant headroom before HA becomes necessary

**Planning for HA from day one means:**
1. Use S3/R2 for file storage from the start (not local disk)
2. Don't put application state in local files
3. Use environment variables or database-backed config (not local config.json for secrets)
4. Document your setup so a second node can replicate it
5. Choose a server provider with private networking (Hetzner vSwitch, OVH vRack)

**When to upgrade to HA:**
- Connection pool exhaustion (check `pg_stat_activity` -- if `active` regularly exceeds `max_connections * 0.7`)
- WebSocket connection count approaching server limits (check with `ss -s | grep estab`)
- Response time degradation (P95 API response time consistently >500ms)
- Business requirement for zero-downtime deployments

**Cost of HA:**
- Enterprise E20 license: contact Mattermost for pricing (typically $8-10/user/year for 1000+ users)
- Second app server: ~$50-70/month
- Load balancer: Cloudflare handles this at the edge, or use HAProxy on a small VPS
- Dedicated database server: ~$70-90/month
- Total incremental: ~$800-1000/month including license for 1000 users

### Alternatives Considered

- **HA from day one:** Triples infrastructure cost and operational complexity. Not justified until concurrent user load demands it.
- **Active-passive failover:** Not natively supported by Mattermost. You could maintain a cold standby with streaming replication, but this is manual failover, not HA.

See `references/HA-SCALING.md` for the full scaling guide.

---

## ADR-007: PostgreSQL Tuning on the Same Box

### Context

Running PostgreSQL on the same box as Mattermost is our "single biggest compromise" (see ADR-002).
Proper tuning is essential to make this work well.

### Decision

**Tune PostgreSQL for shared tenancy with Mattermost, not as a standalone database server.**
This means giving PostgreSQL less memory than you would if it had the whole box, and relying
on the OS page cache to bridge the gap.

### Consequences

**Recommended postgresql.conf for 64GB shared box:**
```ini
# Memory
shared_buffers = 16GB              # 25% of RAM (would be 40-50% on a dedicated DB server)
effective_cache_size = 32GB        # Tell planner about OS cache (would be 48GB if dedicated)
work_mem = 256MB                   # Per-operation sort/hash memory
maintenance_work_mem = 2GB         # For VACUUM, CREATE INDEX

# WAL
wal_buffers = 64MB
checkpoint_completion_target = 0.9
max_wal_size = 4GB
min_wal_size = 1GB

# Connections
max_connections = 200              # Mattermost default pool is 25; leave headroom for mmctl, backups
```

**Why 16GB shared_buffers, not more:**
- Mattermost itself needs 2-4GB RSS for 1000 concurrent users
- Nginx, OS, monitoring tools need ~2GB
- Remaining ~10-14GB serves as OS page cache, which PostgreSQL benefits from via effective_cache_size
- Going above 25% of RAM for shared_buffers on a shared box causes memory pressure that hurts everything

**Monitoring the compromise:**
```bash
# Check PostgreSQL buffer cache hit rate (should be >99%)
psql -U mmuser -d mattermost -c "
  SELECT
    sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) AS cache_hit_ratio
  FROM pg_statio_user_tables;"

# Check if Mattermost is memory-pressured
grep -i 'oom\|killed' /var/log/syslog

# Check overall memory
free -h
```

**Backup strategy for single-box:**
```bash
# Daily logical backup (safe, portable, but slow for large DBs)
pg_dump -U mmuser -Fc mattermost > /backups/mattermost-$(date +%Y%m%d).dump

# Continuous archiving for point-in-time recovery (recommended)
# Configure archive_command in postgresql.conf to ship WAL to a Hetzner Storage Box or R2
```

### Alternatives Considered

- **PgBouncer in front of PostgreSQL:** Unnecessary for single-box. Mattermost has its own connection pool. PgBouncer adds value only when multiple app nodes share one database.
- **PostgreSQL on ZFS:** Gives you snapshots and compression. Adds complexity. Not worth it for a chat server unless you're already a ZFS shop.

---

## Decision Summary

| # | Decision | Choice | Key Trade-off |
|---|----------|--------|---------------|
| 001 | Server provider | Hetzner AX52 | Value vs ECC (OVH for production safety) |
| 002 | Database placement | Same box | Cost vs Mattermost's recommendation |
| 003 | Install method | APT package | Simplicity vs container isolation |
| 004 | File storage | Cloudflare R2 | Minimal cost vs local simplicity |
| 005 | TLS certificate | CF Origin CA | Zero maintenance vs portability |
| 006 | Scaling | Single-node start | Cost vs availability |
| 007 | PostgreSQL tuning | Shared-box profile | Memory allocation compromise |

All decisions should be revisited when:
- Concurrent user count consistently exceeds 1000
- Organization requires contractual uptime SLAs (>99.9%)
- Compliance requirements mandate network-isolated database tiers
