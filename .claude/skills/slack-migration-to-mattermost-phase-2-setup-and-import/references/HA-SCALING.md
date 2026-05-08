# High Availability and Scaling Guide

> When and how to scale Mattermost beyond a single node.
> Covers the 2000-concurrent-user reference architecture, horizontal scaling indicators,
> Kubernetes deployment, dedicated RTCD for calls, and planning for HA from day one.

---

## The Single-Node Ceiling

Mattermost's reference architecture defines the single-node ceiling at approximately
**2000 concurrent users** (active WebSocket connections, not registered users).

For context:
- 1000 registered users typically produce 100-300 concurrent users during peak business hours
- 5000 registered users typically produce 500-1500 concurrent users
- The ratio depends heavily on timezone spread and usage patterns

A well-tuned single node (8 cores, 64GB RAM, NVMe) handles this comfortably.
You have more headroom than you think.

---

## When to Scale: Indicators

Do not scale proactively. Monitor these indicators and scale when thresholds are breached.

### 1. Connection Pool Exhaustion

```bash
# Check active PostgreSQL connections vs max
psql -U mmuser -d mattermost -c "
  SELECT
    count(*) AS active,
    (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_conn,
    round(count(*)::numeric / (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') * 100, 1) AS pct_used
  FROM pg_stat_activity
  WHERE state = 'active';"
```

**Threshold:** If `pct_used` consistently exceeds 70% during peak hours, you need either
more connections (increase `max_connections`) or a second app node with connection pooling.

### 2. API Response Time Degradation

```bash
# Check Mattermost's built-in metrics (if Prometheus endpoint is enabled)
# In config.json: "MetricsSettings": { "Enable": true, "ListenAddress": ":8067" }
curl -s http://localhost:8067/metrics | grep 'mattermost_api_time'

# Or check Nginx upstream response times
grep 'upstream_response_time' /var/log/nginx/access.log | awk '{print $NF}' | sort -n | tail -20
```

**Threshold:** P95 API response time consistently above 500ms. Occasional spikes are normal
(large channel loads, search queries). Sustained degradation indicates capacity limits.

### 3. WebSocket Capacity

```bash
# Count established connections on the Mattermost port
ss -s | grep estab
# Or more specifically:
ss -tn state established '( dport = :8065 )' | wc -l
```

**Threshold:** Each Mattermost process can handle ~10,000-25,000 WebSocket connections
depending on message rate. If you're above 15,000 sustained connections, plan for scaling.

### 4. Memory Pressure

```bash
# Check if OOM killer has been active
dmesg | grep -i 'oom\|killed process'

# Check swap usage (should be near zero on a well-sized box)
free -h | grep Swap

# Check Mattermost RSS
ps aux | grep mattermost | grep -v grep | awk '{print $6/1024 " MB"}'
```

**Threshold:** If Mattermost RSS exceeds 8GB or swap usage is non-trivial, you're memory-bound.

---

## HA Architecture: The Reference Design

HA requires **Enterprise E20 license**. There is no workaround.

```
                    Cloudflare Edge (CDN/WAF/DDoS)
                              │
                     ┌────────┴────────┐
                     │  Load Balancer  │
                     │  (CF or HAProxy)│
                     └───┬─────────┬───┘
                         │         │
              ┌──────────┴──┐  ┌──┴──────────┐
              │ Mattermost  │  │ Mattermost  │
              │  App Node 1 │  │  App Node 2 │
              └──────┬──────┘  └──────┬──────┘
                     │                │
          ┌──────────┴────────────────┴──────────┐
          │                                       │
    ┌─────┴─────┐                          ┌──────┴──────┐
    │ PostgreSQL│                          │   S3 / R2   │
    │  Writer   │──── replication ────▶    │ File Storage│
    │           │                          └─────────────┘
    └─────┬─────┘
          │
    ┌─────┴─────┐
    │ PostgreSQL│
    │  Reader   │
    └───────────┘
```

### Components

**Load Balancer:**
- Cloudflare handles this at the edge if both app nodes share the same origin IP (not typical)
- More commonly: HAProxy or Nginx on a small VPS ($5-10/month) or on one of the app nodes
- Must support WebSocket proxying (sticky sessions or connection-aware routing)
- Mattermost's ClusterSettings handle session routing internally -- the LB just needs to forward

**Multiple App Nodes:**
- Each node runs the same Mattermost binary with the same config
- Nodes discover each other via `ClusterSettings` in config.json
- Inter-node communication uses gossip protocol on a configurable port
- All nodes must share the same database and file storage

```json
{
  "ClusterSettings": {
    "Enable": true,
    "ClusterName": "production",
    "OverrideHostname": "",
    "NetworkInterface": "eth0",
    "BindAddress": "",
    "AdvertiseAddress": "",
    "UseIPAddress": true,
    "EnableGossipCompression": true,
    "GossipPort": 8074,
    "StreamingPort": 8075
  }
}
```

**PostgreSQL Writer + Reader:**
- Writer handles all INSERT/UPDATE/DELETE operations
- Reader handles SELECT queries (search, channel loads, user lookups)
- Streaming replication from writer to reader(s) with <1s lag
- Mattermost config supports separate `DataSource` and `DataSourceReplicas`

```json
{
  "SqlSettings": {
    "DataSource": "postgres://mmuser:pass@writer-host:5432/mattermost?sslmode=verify-full",
    "DataSourceReplicas": [
      "postgres://mmuser:pass@reader-host:5432/mattermost?sslmode=verify-full"
    ],
    "MaxIdleConns": 20,
    "MaxOpenConns": 300,
    "ConnMaxLifetimeMilliseconds": 3600000,
    "ConnMaxIdleTimeMilliseconds": 300000
  }
}
```

**Shared File Storage (S3/R2):**
- All app nodes must access the same file storage
- Local disk storage breaks HA (uploaded files only exist on one node)
- This is why ADR-004 recommends R2 from day one

---

## Dedicated RTCD for Calls

The Mattermost Calls plugin (voice/video calls) runs an RTCD (Real-Time Communication Daemon)
process. On a single node, this runs embedded in the Mattermost process.

**When to dedicate RTCD:**
- More than 50 concurrent call participants
- Call quality degrades (audio/video artifacts, high latency)
- Calls compete with chat for CPU/bandwidth

**Dedicated RTCD setup:**

```bash
# On a separate server (or the same server on a different port)
# Download RTCD binary from Mattermost releases
wget https://github.com/mattermost/rtcd/releases/latest/download/rtcd-linux-amd64
chmod +x rtcd-linux-amd64

# Run RTCD
./rtcd-linux-amd64 \
  --listen-address ":8443" \
  --api-security-key "your-shared-secret" \
  --ice-host-override "your-server-public-ip"
```

**Mattermost config for external RTCD:**
```json
{
  "PluginSettings": {
    "Plugins": {
      "com.mattermost.calls": {
        "rtcdserviceurl": "https://rtcd.yourdomain.com:8443",
        "rtcdservicesecretkey": "your-shared-secret"
      }
    }
  }
}
```

**RTCD hardware requirements:**
- 4+ cores (RTCD is CPU-intensive for media processing)
- 4GB RAM minimum
- Low-latency network connection to app nodes
- UDP port 8443 open for WebRTC traffic

---

## Kubernetes Deployment

Kubernetes is the officially recommended path for HA deployments.

### Helm Chart Installation

```bash
# Add Mattermost Helm repo
helm repo add mattermost https://helm.mattermost.com
helm repo update

# Create namespace
kubectl create namespace mattermost

# Install with custom values
helm install mattermost mattermost/mattermost-enterprise-edition \
  --namespace mattermost \
  --values values.yaml
```

### Minimal values.yaml

```yaml
global:
  siteUrl: "https://chat.yourdomain.com"
  mattermostLicense: "your-license-key-here"

mattermostApp:
  replicaCount: 2
  resources:
    requests:
      cpu: "2"
      memory: "4Gi"
    limits:
      cpu: "4"
      memory: "8Gi"

mysql:
  enabled: false  # Use external PostgreSQL

externalDB:
  enabled: true
  driver: "postgres"
  dataSource: "postgres://mmuser:pass@your-pg-host:5432/mattermost?sslmode=verify-full"

minio:
  enabled: false  # Use external S3/R2

externalFileStore:
  enabled: true
  driver: "amazons3"
  bucket: "mattermost-files"
  endpoint: "your-account-id.r2.cloudflarestorage.com"
  accessKeyId: "your-r2-key"
  secretAccessKey: "your-r2-secret"

ingress:
  enabled: true
  className: "nginx"
  hosts:
    - host: chat.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: mattermost-tls
      hosts:
        - chat.yourdomain.com
```

### When Kubernetes Makes Sense

- You already run Kubernetes for other workloads
- You need auto-scaling based on load
- You need rolling updates with zero downtime
- You have a dedicated platform/DevOps team

### When Kubernetes Does Not Make Sense

- Mattermost is your only workload (running K8s for one app is massive overhead)
- You don't have K8s expertise on the team
- Your user count is under 2000 concurrent (single-node is fine)

---

## Planning for HA from Day One

Even if you deploy single-node today, make these choices now to avoid a painful migration later.

### 1. Use S3/R2 for File Storage from the Start

Local file storage is the single biggest blocker for future HA migration.
Moving terabytes of files from local disk to S3 under time pressure is miserable.

```json
{
  "FileSettings": {
    "DriverName": "amazons3",
    "AmazonS3Bucket": "mattermost-files",
    "AmazonS3Endpoint": "your-account-id.r2.cloudflarestorage.com",
    "AmazonS3PathStyle": true
  }
}
```

### 2. Externalize All State

- **Config:** Use database-backed config (`MM_CONFIG` environment variable pointing to database)
  or ensure config.json is identical across future nodes
- **Plugins:** Store in S3/R2 alongside files, or use the Marketplace for installation
- **Bleve indexes:** When migrating to HA with Elasticsearch, Bleve indexes become irrelevant

### 3. Avoid Local File Assumptions

- Do not write custom integrations that depend on local filesystem paths
- Do not use local Bleve search if you plan to eventually use Elasticsearch
- Do not configure cron jobs on the server that assume they're the only Mattermost instance

### 4. Document Your Setup

Future-you (or a colleague) needs to replicate the setup on a second node. Document:
- Every manual configuration step
- Every environment variable
- Every firewall rule
- Every Nginx config change

### 5. Choose a Provider with Private Networking

When you add a second node, inter-node communication should not traverse the public internet.
- **Hetzner:** vSwitch (free, VLAN-based private networking between dedicated servers)
- **OVH:** vRack (free, private network spanning data centers)
- Both support private subnets with no bandwidth charges

---

## Scaling Checklist

When the time comes to scale, follow this sequence:

```
[ ] Purchase Enterprise E20 license
[ ] Verify file storage is already on S3/R2
[ ] Set up PostgreSQL streaming replication (writer → reader)
[ ] Provision second app server (same spec as first)
[ ] Install Mattermost via APT on second server (same version)
[ ] Copy config.json to second server
[ ] Enable ClusterSettings on both nodes
[ ] Set up HAProxy or Nginx load balancer
[ ] Update Cloudflare DNS to point to load balancer
[ ] Configure DataSourceReplicas to include reader
[ ] Test: post a message on node 1, verify it appears on node 2
[ ] Test: kill node 1, verify node 2 serves all traffic
[ ] Test: bring node 1 back, verify cluster resyncs
[ ] Set up monitoring for both nodes
[ ] (Optional) Deploy dedicated RTCD if using Calls
[ ] (Optional) Deploy Elasticsearch for search at scale
```

---

## Cost Comparison: Single Node vs HA

| Component | Single Node | HA (Minimum) | HA (Full) |
|-----------|------------|--------------|-----------|
| App server(s) | $70/month (1x AX52) | $140/month (2x AX52) | $210/month (3x AX52) |
| Database | Included | $70/month (dedicated) | $140/month (writer + reader) |
| Load balancer | N/A | $5-10/month (VPS) | $5-10/month |
| File storage | Included (local) | $15/month (1TB R2) | $15/month |
| RTCD | Included | $30/month (VPS) | $70/month (dedicated) |
| Elasticsearch | N/A | N/A | $50-100/month |
| License (1000 users) | Free (Team) | ~$833/month (E20) | ~$833/month (E20) |
| **Total** | **$70/month** | **~$1,100/month** | **~$1,400/month** |

The jump from single-node to HA is dominated by the Enterprise license cost.
Infrastructure is the minority of the expense. This is why the licensing decision
(see `references/LICENSING-GUIDE.md`) should be made early.

---

## Reference: Mattermost Sizing Guide

From Mattermost's documentation (adapted for practical use):

| Concurrent Users | App Nodes | Database | File Storage | Elasticsearch |
|-----------------|-----------|----------|-------------|---------------|
| 0-2,000 | 1 (single box with DB) | PostgreSQL on same box | Local or S3 | Not needed |
| 2,000-5,000 | 2 | Dedicated PostgreSQL (1 writer) | S3/R2 (required) | Recommended |
| 5,000-10,000 | 2-3 | 1 writer + 1 reader | S3/R2 (required) | Required |
| 10,000-25,000 | 3-5 | 1 writer + 2 readers | S3/R2 (required) | Required (cluster) |
| 25,000+ | 5+ | 1 writer + 3+ readers | S3/R2 (required) | Required (cluster) |

All multi-node configurations require Enterprise E20 license.
