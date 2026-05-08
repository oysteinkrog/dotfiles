# Monitoring (Prometheus + Grafana)

Mattermost exposes a Prometheus-compatible `/metrics` endpoint. This guide sets up scraping, dashboarding, and alerting for a production Mattermost instance.

## Enable Mattermost Metrics

Edit `/opt/mattermost/config/config.json`:
```json
{
  "MetricsSettings": {
    "Enable": true,
    "ListenAddress": ":8067"
  }
}
```

Restart Mattermost:
```bash
sudo systemctl restart mattermost
```

Verify the endpoint is live:
```bash
curl -s http://127.0.0.1:8067/metrics | head -20
```

Do NOT expose port 8067 to the internet. Keep it bound to localhost or your monitoring VLAN.

## Prometheus + Grafana Deployment

Mattermost recommends running monitoring **off-box** -- a separate host avoids contention during incident investigation. If you only have one server, run Prometheus and Grafana in Docker containers so they're isolated from the Mattermost process.

### Docker Compose (on monitoring host or same server)

```yaml
# /opt/monitoring/docker-compose.yml
version: "3.8"
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "127.0.0.1:9090:9090"
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "127.0.0.1:3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: "changeme-grafana-password"
    restart: unless-stopped

volumes:
  prometheus_data:
  grafana_data:
```

Start it:
```bash
cd /opt/monitoring
docker compose up -d
```

### Prometheus Scrape Configuration

```yaml
# /opt/monitoring/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alerts.yml"

scrape_configs:
  - job_name: "mattermost"
    # If Prometheus runs on the same host:
    static_configs:
      - targets: ["127.0.0.1:8067"]
    # If Prometheus runs on a different host:
    # static_configs:
    #   - targets: ["mattermost-server-ip:8067"]
    # Requires opening 8067 in UFW for the monitoring host only:
    #   ufw allow from MONITOR_IP to any port 8067

  - job_name: "node"
    static_configs:
      - targets: ["127.0.0.1:9100"]
    # Optional: install node_exporter for OS-level metrics
    # apt install prometheus-node-exporter
```

Reload after editing:
```bash
docker compose restart prometheus
```

## Grafana Dashboard Import

Mattermost provides an official Grafana dashboard.

1. Open Grafana at `http://127.0.0.1:3000` (default login: `admin` / password from compose)
2. Add Prometheus as a data source: Configuration > Data Sources > Add > Prometheus > URL `http://prometheus:9090`
3. Import dashboard: Dashboards > Import > Dashboard ID **15582** (Mattermost Performance Monitoring) > Load > Select Prometheus data source > Import

If the official ID changes, search for "Mattermost" at https://grafana.com/grafana/dashboards/ and use the latest one.

## Key Metrics to Watch

| Metric | What It Tells You | Healthy Range |
|--------|-------------------|---------------|
| `mattermost_http_websockets_total` | Active WebSocket connections | Should match online user count |
| `mattermost_api_time_seconds` | API response latency (histogram) | p99 under 500ms |
| `mattermost_db_pool_idle_connections` | Idle database connections in pool | Should not be 0 constantly |
| `mattermost_db_pool_open_connections` | Active database connections | Under `MaxOpenConns` (100) |
| `go_goroutines` | Goroutine count | 200-2000 normal; 10k+ is a leak |
| `mattermost_post_total` | Cumulative message post count | Monotonically increasing |
| `mattermost_post_broadcasts_total` | Post broadcast events | Proportional to post rate |
| `mattermost_cluster_event_type_totals` | Cluster events (if HA) | No errors piling up |
| `process_resident_memory_bytes` | Mattermost process RSS | Under 70% of server RAM |

## Alerting Rules

Create `/opt/monitoring/alerts.yml`:
```yaml
groups:
  - name: mattermost
    rules:
      - alert: MattermostDown
        expr: up{job="mattermost"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Mattermost metrics endpoint unreachable"

      - alert: HighWebSocketDropRate
        expr: rate(mattermost_http_websockets_total[5m]) < -1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "WebSocket connections dropping rapidly"

      - alert: APILatencyHigh
        expr: histogram_quantile(0.99, rate(mattermost_api_time_seconds_bucket[5m])) > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "API p99 latency exceeds 2 seconds"

      - alert: DatabaseConnectionPoolExhausted
        expr: mattermost_db_pool_open_connections / mattermost_db_pool_max_open_connections > 0.9
        for: 3m
        labels:
          severity: critical
        annotations:
          summary: "Database connection pool above 90% capacity"

      - alert: GoroutineLeak
        expr: go_goroutines > 10000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Goroutine count exceeds 10,000 -- possible leak"

      - alert: ImportJobFailed
        expr: increase(mattermost_jobs_active{type="import_process"}[1h]) > 0 and mattermost_jobs_active{type="import_process"} == 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Import job completed -- check mmctl import job list for errors"

  - name: node
    rules:
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Root filesystem has less than 10% free space"

      - alert: HighMemoryUsage
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Memory usage exceeds 90%"

      - alert: HighCPU
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "CPU usage exceeds 85% for 10 minutes"
```

Node-level alerts require `prometheus-node-exporter`:
```bash
sudo apt install -y prometheus-node-exporter
sudo systemctl enable prometheus-node-exporter
```

## Notification Channels

Configure Grafana alerting to deliver notifications:
- **Email:** Grafana > Alerting > Contact Points > Add > Email
- **Slack/Mattermost webhook:** Add incoming webhook integration in Mattermost, paste URL into Grafana contact point
- **PagerDuty:** Use the built-in Grafana PagerDuty integration

## Quick Health Check (No Grafana)

For a fast command-line check without opening Grafana:
```bash
# WebSocket connections
curl -s http://127.0.0.1:8067/metrics | grep mattermost_http_websockets_total

# API latency
curl -s http://127.0.0.1:8067/metrics | grep mattermost_api_time_seconds_count

# DB connections
curl -s http://127.0.0.1:8067/metrics | grep mattermost_db_pool

# Goroutines
curl -s http://127.0.0.1:8067/metrics | grep go_goroutines

# Process memory (bytes)
curl -s http://127.0.0.1:8067/metrics | grep process_resident_memory_bytes
```
