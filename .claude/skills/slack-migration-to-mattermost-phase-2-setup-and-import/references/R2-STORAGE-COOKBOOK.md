# Cloudflare R2 Storage for Mattermost

## Why R2

Mattermost stores uploaded files (images, documents, attachments) either locally or in
S3-compatible object storage. For production, Mattermost explicitly recommends S3 over
local disk.

**R2 advantages over AWS S3:**

- **No egress fees** -- downloading files to users costs $0 (AWS charges ~$0.09/GB)
- **S3-compatible API** -- Mattermost talks to it natively via the `amazons3` driver
- **$0.015/GB/month storage** -- cheaper than S3 Standard ($0.023/GB)
- **No minimum storage duration** -- unlike S3 Glacier or Infrequent Access tiers
- **Reduces local disk pressure** -- your VPS disk stays small and cheap
- **Built-in redundancy** -- Cloudflare handles replication across their network

**Cost estimates:**

| Org Size | Estimated Files | Monthly Storage | Monthly Cost |
|----------|----------------|-----------------|--------------|
| 10 users | ~5 GB | 5 GB | $0.08 |
| 50 users | ~25 GB | 25 GB | $0.38 |
| 200 users | ~100 GB | 100 GB | $1.50 |
| 1000 users | ~500 GB | 500 GB | $7.50 |

Class A operations (writes): $4.50/million. Class B operations (reads): $0.36/million.
For most orgs, operations costs are negligible.

## Create R2 Bucket

### Via Cloudflare Dashboard

1. Log in to Cloudflare Dashboard
2. Navigate to **R2 Object Storage** in the left sidebar
3. Click **Create bucket**
4. Name it `mattermost-files` (or whatever you prefer)
5. Select location hint (closest to your server)
6. Click **Create bucket**

### Via Wrangler CLI

```bash
# Install wrangler if not already present
npm install -g wrangler

# Authenticate
wrangler login

# Create the bucket
wrangler r2 bucket create mattermost-files
```

## Generate R2 API Credentials

1. In Cloudflare Dashboard, go to **R2 Object Storage**
2. Click **Manage R2 API Tokens** (top-right area)
3. Click **Create API Token**
4. Configure:
   - **Token name**: `mattermost-file-storage`
   - **Permissions**: Object Read & Write
   - **Specify bucket(s)**: select `mattermost-files`
   - **TTL**: optional, leave blank for no expiry
5. Click **Create API Token**
6. **Copy immediately** -- the secret is shown only once:
   - **Access Key ID**: something like `a1b2c3d4e5f6...`
   - **Secret Access Key**: something like `x9y8z7w6v5u4...`

Save these securely (password manager, not a plain text file on the server).

## Find Your Account ID

Your R2 endpoint URL requires your Cloudflare Account ID:

1. Dashboard > any domain > **Overview** > right sidebar shows Account ID
2. Or: Dashboard > R2 > the endpoint URL is shown on the bucket detail page

The endpoint format is: `ACCOUNT_ID.r2.cloudflarestorage.com`

## Configure Mattermost for R2

Edit `/opt/mattermost/config/config.json` (or use `mmctl config set`):

```json
{
  "FileSettings": {
    "DriverName": "amazons3",
    "Directory": "./data/",
    "EnableFileAttachments": true,
    "MaxFileSize": 104857600,
    "AmazonS3AccessKeyId": "YOUR_R2_ACCESS_KEY_ID",
    "AmazonS3SecretAccessKey": "YOUR_R2_SECRET_ACCESS_KEY",
    "AmazonS3Bucket": "mattermost-files",
    "AmazonS3PathPrefix": "",
    "AmazonS3Region": "",
    "AmazonS3Endpoint": "ACCOUNT_ID.r2.cloudflarestorage.com",
    "AmazonS3SSL": true,
    "AmazonS3SignV2": false,
    "AmazonS3SSE": false,
    "AmazonS3Trace": false
  }
}
```

Or via mmctl:

```bash
mmctl config set FileSettings.DriverName amazons3
mmctl config set FileSettings.AmazonS3AccessKeyId "YOUR_R2_ACCESS_KEY_ID"
mmctl config set FileSettings.AmazonS3SecretAccessKey "YOUR_R2_SECRET_ACCESS_KEY"
mmctl config set FileSettings.AmazonS3Bucket "mattermost-files"
mmctl config set FileSettings.AmazonS3Endpoint "ACCOUNT_ID.r2.cloudflarestorage.com"
mmctl config set FileSettings.AmazonS3Region ""
mmctl config set FileSettings.AmazonS3SSL true
mmctl config set FileSettings.AmazonS3SignV2 false
```

**Restart Mattermost after config changes:**

```bash
sudo systemctl restart mattermost
```

## Common Configuration Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Including `https://` in endpoint | Connection refused / TLS errors | Use bare hostname: `ACCOUNT_ID.r2.cloudflarestorage.com` |
| Setting Region to `auto` or `us-east-1` | SignatureDoesNotMatch errors | Set Region to empty string `""` |
| AmazonS3SSL set to false | Connection timeout | Must be `true` for R2 |
| Using full bucket URL as endpoint | 403 Forbidden | Endpoint is just the host, bucket name goes in AmazonS3Bucket |
| Wrong API token permissions | 403 on upload | Token needs Object Read & Write on the specific bucket |

## Verify R2 is Working

### Quick Test via Mattermost

1. Log in to Mattermost as any user
2. Upload a file in any channel (drag and drop an image)
3. Confirm the file appears and is downloadable
4. Check R2 dashboard -- the object should appear in the bucket

### Check via CLI

```bash
# Install rclone if not present
sudo apt install rclone

# Configure rclone for R2
rclone config create r2 s3 \
  provider=Cloudflare \
  access_key_id=YOUR_R2_ACCESS_KEY_ID \
  secret_access_key=YOUR_R2_SECRET_ACCESS_KEY \
  endpoint=https://ACCOUNT_ID.r2.cloudflarestorage.com \
  acl=private

# List bucket contents
rclone ls r2:mattermost-files

# You should see the file you just uploaded
```

## Migrate Existing Local Files to R2

If Mattermost was previously using local storage (`"DriverName": "local"`), existing
files live in `/opt/mattermost/data/`. Migrate them to R2:

```bash
# Dry run first -- see what would be transferred
rclone sync /opt/mattermost/data/ r2:mattermost-files --dry-run --progress

# Actual transfer
rclone sync /opt/mattermost/data/ r2:mattermost-files --progress --transfers=16

# Verify file counts match
LOCAL_COUNT=$(find /opt/mattermost/data -type f | wc -l)
R2_COUNT=$(rclone ls r2:mattermost-files | wc -l)
echo "Local: $LOCAL_COUNT files, R2: $R2_COUNT files"
```

After migration:
1. Update `config.json` to use `amazons3` driver (see above)
2. Restart Mattermost
3. Verify old files are still accessible (open an old message with an attachment)
4. Keep local files for a week as a safety net, then remove

## Backup Considerations

With R2 as your file store, backups are simplified:

- **Files are already off-server** -- a VPS failure does not lose files
- **Database backup is the priority** -- PostgreSQL dumps are your critical backup
- **R2 has built-in redundancy** -- Cloudflare replicates across their network
- **Optional**: set up a second rclone remote to sync R2 to another provider (B2, etc.)

```bash
# Optional: mirror R2 to a local backup directory periodically
rclone sync r2:mattermost-files /backups/mattermost-files --progress
```

## R2 Lifecycle Rules (Optional)

For very active workspaces, consider lifecycle rules to manage old files:

1. Dashboard > R2 > `mattermost-files` > **Settings** > **Object lifecycle rules**
2. Add rule: delete objects older than N days (only if your retention policy allows)

Most orgs should **not** set lifecycle rules -- users expect old files to remain available.

## Monitoring R2 Usage

```bash
# Check bucket size via rclone
rclone size r2:mattermost-files

# Example output:
# Total objects: 12,847
# Total size: 23.456 GiB
```

In the Cloudflare Dashboard, R2 > Analytics shows:
- Storage used over time
- Operations breakdown (Class A vs Class B)
- Bandwidth consumed (all free egress, but tracked for visibility)
