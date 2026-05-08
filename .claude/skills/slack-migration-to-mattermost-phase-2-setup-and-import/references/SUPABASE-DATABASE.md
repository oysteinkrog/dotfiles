# Supabase as Managed Database for Mattermost

Use Supabase instead of self-hosted PostgreSQL to eliminate DB operations overhead. Supabase provides managed PostgreSQL with automated backups, PITR, connection pooling, and a dashboard -- while you keep the Mattermost app server self-hosted.

## When to Choose Supabase

| Factor | Self-Hosted PG | Supabase |
|--------|:-:|:-:|
| DB ops burden | You manage backups, upgrades, PITR | Handled automatically |
| Tuning control | Full postgresql.conf access | Limited (some params adjustable) |
| Cost (1000 users) | ~$0 (runs on same box) | $25/month (Pro) or $599/month (Team) |
| Connection pooling | Must configure PgBouncer yourself | Built-in Supavisor |
| Latency | Local socket (zero network hop) | Network hop to Supabase region |
| Data sovereignty | Full control, your hardware | Supabase region (AWS) |
| Dashboard / SQL editor | pgAdmin or CLI only | Built-in web dashboard |
| Automatic backups | Must configure pg_dump / WAL | Daily backups + PITR included |
| RLS for custom tables | Available but you enable it | Available + well-documented patterns |

**Choose Supabase when:** You want zero database operations overhead, your team is small and doesn't have a DBA, latency to an AWS region is acceptable, and the cost delta is worth the ops savings.

**Stick with self-hosted when:** You need sub-millisecond DB latency, want full tuning control, are cost-sensitive, or have data sovereignty requirements that preclude cloud databases.

## Setup: Supabase for Mattermost

### 1. Create Supabase Project
1. Go to `supabase.com` > New Project
2. Select region closest to your Mattermost server (e.g., `us-east-1` if Hetzner Ashburn)
3. Set a strong database password
4. Choose plan: **Pro ($25/month)** recommended for production

### 2. Get Connection String
Dashboard > Settings > Database > Connection String > **Session Mode (port 5432)**

```
postgresql://postgres.<project_ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require
```

**CRITICAL: Use Session Mode (port 5432), NOT Transaction Mode (port 6543).**

Mattermost uses prepared statements internally. Transaction mode pooling (port 6543) breaks prepared statements with the error `prepared statement does not exist`. Session mode (port 5432) maintains per-connection state and supports prepared statements.

### 3. Create Mattermost Database
Connect via the SQL Editor in the Supabase Dashboard:

```sql
-- Create a dedicated database for Mattermost
-- (Supabase projects come with a 'postgres' database by default;
--  you can use it directly or create a separate one)

-- Option A: Use the default 'postgres' database
-- Just point Mattermost at the connection string above

-- Option B: Create a dedicated user with limited privileges
CREATE USER mmuser WITH PASSWORD 'mattermost-strong-password';
GRANT ALL PRIVILEGES ON DATABASE postgres TO mmuser;

-- If using a dedicated user, update the connection string:
-- postgresql://mmuser:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require
```

### 4. Configure Mattermost
In `/opt/mattermost/config/config.json`:

```json
{
  "SqlSettings": {
    "DriverName": "postgres",
    "DataSource": "postgresql://postgres.<project_ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require",
    "MaxIdleConns": 20,
    "MaxOpenConns": 100,
    "ConnMaxLifetimeMilliseconds": 3600000,
    "ConnMaxIdleTimeMilliseconds": 300000
  }
}
```

Or via environment variable:
```bash
export MM_SQLSETTINGS_DATASOURCE="postgresql://postgres.<ref>:<pass>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require"
```

### 5. Verify Connection
```bash
# Restart Mattermost
systemctl restart mattermost

# Check logs for database connection
journalctl -u mattermost --since "1 min ago" | grep -i "database\|sql\|postgres"

# Should see successful connection, no errors
# If you see "prepared statement does not exist", you're on port 6543 -- switch to 5432
```

## Security Hardening: RLS for Custom Tables

Mattermost manages its own tables and doesn't use Supabase's RLS features for its core data. However, if you add **custom tables** to the same Supabase project (e.g., for analytics dashboards, custom bots, or admin tooling), you MUST lock them down.

### The Risk
Supabase exposes a PostgREST API on every table in the `public` schema. Without RLS, anyone with your anon key can read/write those tables via the Data API. Mattermost's tables are safe because they're accessed directly via PostgreSQL, not through PostgREST. But any custom tables you create are exposed.

### Non-Negotiable Rules

1. **Enable RLS on ALL custom tables** -- tables without RLS are accessible via the anon role through the Data API
2. **Never expose `service_role` key** -- it bypasses all RLS; backend-only
3. **Move sensitive tables to a `private` schema** -- PostgREST only exposes the `public` schema by default
4. **Use `app_metadata` not `user_metadata`** for authorization -- user_metadata is user-editable

### Pattern: Protecting Custom Tables

```sql
-- Example: Analytics dashboard table you add alongside Mattermost
CREATE TABLE public.migration_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  admin_user_id UUID REFERENCES auth.users(id)
);

-- ALWAYS enable RLS
ALTER TABLE public.migration_audit_log ENABLE ROW LEVEL SECURITY;

-- Policy: Only authenticated admins can read
CREATE POLICY "admins can read audit log"
  ON public.migration_audit_log
  FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

-- Policy: Only service role can write (server-side only)
CREATE POLICY "service role can write audit log"
  ON public.migration_audit_log
  FOR INSERT
  WITH CHECK (
    (SELECT current_setting('request.jwt.claim.role', TRUE)) = 'service_role'
  );

-- Index for RLS performance
CREATE INDEX idx_audit_log_admin ON public.migration_audit_log(admin_user_id);
```

### Pattern: Private Schema for Sensitive Data

```sql
-- Create a private schema that PostgREST doesn't expose
CREATE SCHEMA IF NOT EXISTS private;

-- Put sensitive tables there
CREATE TABLE private.mattermost_config_snapshots (
  id SERIAL PRIMARY KEY,
  config_json JSONB NOT NULL,
  snapshot_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Only accessible via direct SQL connection (Mattermost), not via Data API
-- No RLS needed because PostgREST doesn't serve this schema
```

### Pattern: Read-Only Public Views

```sql
-- Expose limited data via a view in public schema
CREATE VIEW public.channel_stats AS
  SELECT
    c.name,
    COUNT(p.id) as post_count,
    MAX(p.createat) as last_activity
  FROM channels c
  LEFT JOIN posts p ON p.channelid = c.id
  GROUP BY c.name;

-- RLS on the view
ALTER VIEW public.channel_stats SET (security_invoker = true);
-- This ensures the view respects the caller's RLS policies
```

## Supabase-Specific Gotchas for Mattermost

| Issue | Cause | Fix |
|-------|-------|-----|
| `prepared statement does not exist` | Using transaction pooler (port 6543) | Switch to session pooler (port 5432) |
| `ENETUNREACH` / `network unreachable` | Direct connection is IPv6 only | Use pooler connection string (IPv4) |
| `Tenant or user not found` | Wrong username format | Use `postgres.<project_ref>` (dot is real) |
| Connection drops under load | Supavisor connection limits | Increase `MaxOpenConns` in Mattermost; upgrade Supabase plan |
| Slow imports | Network latency to Supabase | Accept slower imports, or use self-hosted PG for import then migrate to Supabase after |
| `relation does not exist` | Mattermost auto-creates tables on first run | Just start Mattermost; it handles schema creation |

## Import Performance with Supabase

Large imports (>5 GB JSONL) are **slower** with Supabase than local PostgreSQL because every database operation traverses the network. Strategies:

1. **Accept the slowdown** -- a 2x slowdown is common. A 4-hour local import becomes 8 hours.
2. **Import locally, then migrate** -- do the import with local PG, then `pg_dump` and restore to Supabase:
   ```bash
   # Local import first
   pg_dump -U mmuser mattermost | gzip > mattermost_dump.sql.gz

   # Restore to Supabase
   gunzip -c mattermost_dump.sql.gz | psql "postgresql://postgres.<ref>:<pass>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require"

   # Switch Mattermost config to Supabase connection string
   # Restart Mattermost
   ```
3. **Use Supabase from the start** for small/medium imports (<2 GB) where the slowdown is negligible.

## Cost Comparison

| Scenario | Self-Hosted PG | Supabase Pro | Supabase Team |
|----------|---------------|-------------|--------------|
| Monthly cost | $0 (on same box) | $25 | $599 |
| DB storage included | Disk space | 8 GB | 8 GB |
| Extra storage | N/A | $0.125/GB | $0.125/GB |
| Backups | DIY (pg_dump cron) | Daily + PITR | Daily + PITR |
| Connection pooling | DIY (PgBouncer) | Supavisor included | Supavisor included |
| Support | Community | Email | Priority |
| Dashboard | pgAdmin (DIY) | Included | Included |

For a 1000-user Mattermost with ~5 GB database, Supabase Pro at $25/month is reasonable if you value zero DB ops. The total monthly cost becomes ~$95 (server $70 + Supabase $25) vs ~$70 (server + local PG).

## Monitoring Supabase

Use the Supabase Dashboard for:
- **Database health** -- connections, query performance, disk usage
- **Query inspector** -- slow query identification
- **Logs** -- PostgreSQL logs accessible in Dashboard > Logs

For Mattermost-specific monitoring, still use Prometheus/Grafana on the app server to watch Mattermost metrics (connection pool usage, query latency from the app's perspective).

## Backup Strategy with Supabase

Supabase Pro/Team includes:
- **Daily automated backups** -- retained for 7 days (Pro) or 14 days (Team)
- **Point-in-time recovery** -- restore to any second within the backup window
- **Manual backups** -- trigger from Dashboard at any time

You don't need to run `pg_dump` cron jobs. But you should still:
- Back up `/opt/mattermost/config/` on your app server
- Back up Nginx certs and config
- Consider an independent `pg_dump` to your own storage as defense-in-depth (Supabase provides the connection, you can still dump from it)
