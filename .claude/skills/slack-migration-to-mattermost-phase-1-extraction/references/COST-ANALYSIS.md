# Cost Analysis: Slack vs Self-Hosted Mattermost

The economic case for migration and infrastructure planning numbers.

## Slack Pricing (as of 2026)

| Plan | Per User/Month | 1000 Users/Month | Annual |
|------|---------------|-------------------|--------|
| Free | $0 | $0 | $0 |
| Pro | $7.25 | $7,250 | $87,000 |
| Business+ | $12.50 | $12,500 | $150,000 |
| Enterprise Grid | Custom (~$15-25) | $15,000-25,000 | $180,000-300,000 |

## Self-Hosted Mattermost Cost

### Server Options (Bare Metal, Monthly)

| Provider | Model | Specs | Monthly |
|----------|-------|-------|---------|
| **Hetzner AX42-U** (value pick) | Ryzen 7 PRO 8700GE | 8c/16t, 64GB DDR5, 2x512GB NVMe | ~$50 |
| **Hetzner AX52** | Ryzen 7 7700 | 8c/16t, 64GB DDR5, 2x1TB NVMe | ~$70 |
| **OVH Advance-2** (production pick) | EPYC 4345P | 8c/16t, 64GB DDR5 ECC, 2x960GB NVMe | ~$90 |
| **Hetzner EX44** (budget) | i5-13500 | 14c, 64GB DDR4, 2x512GB NVMe | ~$45 |

### Total Monthly Cost

| Component | Cost |
|-----------|------|
| Server (Hetzner AX52) | ~$70 |
| Cloudflare (Free plan) | $0 |
| Domain registration | ~$1 (amortized) |
| Backup storage (Hetzner Storage Box 1TB) | ~$5 |
| Mattermost Team Edition | $0 (open source) |
| **Total** | **~$76/month** |

### The Math

| Metric | Slack Business+ | Self-Hosted Mattermost |
|--------|----------------|----------------------|
| 1000 users/month | $12,500 | $76 |
| Annual | $150,000 | $912 |
| **Savings** | -- | **$149,088/year (99.4%)** |

Even with Mattermost Enterprise licensing ($10/user/month = $10,000/month), the total ($10,076/month) is still **19.4% of Slack Business+**.

## Storage Planning

### File Storage Growth
For medium-usage teams (5-25 MB/user/month):
- 1000 users: 5-25 GB/month new file storage
- Per year: 60-300 GB with 2x safety factor
- 2x1TB NVMe gives 2-3 years of runway

### Object Storage (Cloudflare R2)
For offloading file attachments to S3-compatible storage:
- R2 free tier: 10 GB storage, 10M reads, 1M writes
- R2 paid: $0.015/GB/month storage, no egress fees
- 300 GB of files: ~$4.50/month

### Database Growth
PostgreSQL for 1000 users:
- Typical: 1-5 GB/year of message data
- With search indexes: 2-10 GB/year
- NVMe on the same box handles this easily

## Migration Costs (One-Time)

| Item | Cost |
|------|------|
| Slack Business+ upgrade (if needed for export) | 1 month at $12,500 |
| Migration effort (admin time) | 1-2 weeks |
| Testing/staging server | ~$70 (can reuse) |
| **Total one-time** | **~$12,600** |

The one-time migration cost is recouped in **1 month** of Slack savings.

## Hidden Costs to Consider

### Self-Hosted Adds
- Admin/ops time for maintenance
- Security patching responsibility
- Backup verification
- Monitoring setup (Prometheus/Grafana)
- SSL certificate management (free with Cloudflare Origin CA)

### Slack Removes
- Slack Connect (external org messaging)
- Slack AI features
- Built-in video clips
- Automated workflow builder
- App ecosystem breadth

### What Mattermost Adds
- Full data sovereignty
- No per-seat scaling costs
- Custom integrations without API limits
- Self-hosted = no vendor lock-in
- Compliance (data stays on your infrastructure)

## Sizing Guide

### Minimum Viable Specs by User Count

| Users | vCPU | RAM | Storage | Note |
|-------|------|-----|---------|------|
| 1-50 | 2 | 4 GB | 50 GB | VPS is fine |
| 50-250 | 4 | 8 GB | 100 GB | Small dedicated or large VPS |
| 250-1000 | 8 | 64 GB | 500 GB+ | Dedicated server recommended |
| 1000-2000 | 8+ | 64 GB+ | 1 TB+ | Dedicated + separate PostgreSQL |
| 2000+ | HA cluster | -- | -- | Mattermost Enterprise HA required |

### Import Processing Requirements
During import (temporary spike):
- CPU: Import is I/O bound, not CPU bound
- RAM: PostgreSQL needs 8 GB+ for large imports
- Disk: Plan for 3x export size (export + transform output + working space)
- NVMe SSDs make a significant difference for large imports
