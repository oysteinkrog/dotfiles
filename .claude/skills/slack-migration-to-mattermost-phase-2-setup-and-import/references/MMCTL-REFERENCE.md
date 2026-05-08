# mmctl Command Reference for Migration

> Complete mmctl cheat sheet for Slack-to-Mattermost migration operations.
> Use an `mmctl` binary that is compatible with the Mattermost server you are talking to. In exact-flow validation against Mattermost `11.5.1`, the public GitHub `latest` release still resolved to `v7.8.15`, so the safest fallback on newer servers is the server-bundled `mmctl`.

## Installation

```bash
# Public GitHub release track (currently the easiest generic install path)
curl -L https://github.com/mattermost/mmctl/releases/latest/download/linux_amd64.tar -o mmctl.tar
tar xf mmctl.tar && sudo mv mmctl /usr/local/bin/

# macOS (Homebrew)
brew install mmctl

# Verify
mmctl version
```

If the server is newer than the public GitHub release track, prefer the server-bundled binary:

```bash
# APT/tarball installs
/opt/mattermost/bin/mmctl version

# Docker deploys
docker exec mattermost /mattermost/bin/mmctl version
```

That bundled binary is the safest choice for import-heavy paths when `mmctl auth login` warns that the client/server versions do not match.

## Authentication

```bash
# Interactive login -- saves credentials to ~/.config/mmctl/credentials
mmctl auth login https://chat.yourdomain.com \
  --name migration \
  --username admin \
  --password 'YOUR_ADMIN_PASSWORD'

# Switch between stored profiles
mmctl auth list
mmctl auth set migration

# Token-based login (for scripting)
mmctl auth login https://chat.yourdomain.com \
  --name migration \
  --access-token YOUR_PERSONAL_ACCESS_TOKEN

# Remove stored credentials
mmctl auth delete migration
```

Personal access tokens are created in System Console > Integrations > Bot Accounts (or via user menu > Security > Personal Access Tokens). Prefer tokens for automation; they avoid password rotation issues.

## Team Management

```bash
# Create the team that will receive imported channels
mmctl team create --name myteam --display-name "My Team"

# CRITICAL: make the team public before import
# Bulk import cannot create users in invite-only teams
mmctl team modify myteam --public

# List all teams
mmctl team list

# Add a user to a team
mmctl team users add myteam user@example.com

# Remove a user from a team
mmctl team users remove myteam user@example.com

# Rename a team
mmctl team rename myteam --display-name "New Display Name"

# After migration, lock the team back down
mmctl team modify myteam --private
```

## Import Workflow

This is the core migration sequence. Run these in order.

### Step 1: Upload the ZIP

```bash
mmctl import upload ~/mattermost-bulk-import.zip
# Output: Upload session ID and filename
# For large files (>1GB), this can take several minutes
```

### Step 2: List Available Imports

```bash
mmctl import list available
# Shows filenames of uploaded ZIPs ready to process
# Example output:
#   cj8x9q7m87yh9e6nz4gfhpry5r_mattermost-bulk-import.zip
```

### Step 3: Process the Import

```bash
# Use the exact filename from "list available" output
mmctl import process cj8x9q7m87yh9e6nz4gfhpry5r_mattermost-bulk-import.zip
```

### Step 4: Monitor Progress

```bash
# List recent import jobs (newest first)
mmctl import job list

# JSON output for scripting
mmctl import job list --json | jq '.[0]'

# Show a specific job by ID
mmctl import job show JOB_ID

# Poll until completion (bash one-liner)
while true; do
  STATUS=$(mmctl import job list --json 2>/dev/null | jq -r '.[0].status')
  echo "$(date +%H:%M:%S) Status: $STATUS"
  [[ "$STATUS" == "success" || "$STATUS" == "error" ]] && break
  sleep 10
done
```

### Step 5: Check for Errors

```bash
# If status is "error", inspect the job data
mmctl import job list --json | jq '.[0].data'

# Common errors:
#   "line_number": N  -- malformed JSONL at line N
#   "missing team"    -- team doesn't exist or isn't public
#   "file not found"  -- attachment referenced in JSONL missing from ZIP
```

### Re-Import (Safe)

Import is idempotent. Duplicate posts (same channel + timestamp + user) are skipped. You can safely run baseline + delta imports without creating duplicates.

## User Management

```bash
# List all users
mmctl user list --all

# List with JSON for scripting
mmctl user list --all --json | jq '.[].username'

# Count total users
mmctl user list --all --json | jq length

# Set a user's password (for manual activation)
mmctl user change-password jsmith --password 'TempPassword123!'

# Activate a deactivated user
mmctl user activate jsmith

# Deactivate a user (disable login, preserve history)
mmctl user deactivate jsmith

# Search for a user by email
mmctl user search user@example.com

# Promote a user to system admin
mmctl roles system-admin jsmith

# Demote from system admin
mmctl roles member jsmith

# Reset MFA for a locked-out user
mmctl user resetmfa jsmith

# Convert a regular user to a bot
mmctl user convert jsmith --bot
```

## Channel Management

```bash
# List all channels in a team (public + private)
mmctl channel list myteam

# Rename a channel
mmctl channel rename myteam:old-channel-name --name new-name \
  --display-name "New Display Name"

# Archive (soft-delete) a channel
mmctl channel archive myteam:channel-name

# Unarchive
mmctl channel unarchive myteam:channel-name

# Move a channel to a different team
mmctl channel move destination-team myteam:channel-name

# Make a channel private/public
mmctl channel modify myteam:channel-name --private
mmctl channel modify myteam:channel-name --public

# Add a user to a channel
mmctl channel users add myteam:channel-name user@example.com

# Remove a user from a channel
mmctl channel users remove myteam:channel-name user@example.com
```

## System & Diagnostics

```bash
# Server version
mmctl system version

# Server status (DB, filestore, etc.)
mmctl system status

# Clear all caches (useful after large import)
mmctl system clearbusy

# Get a specific config value
mmctl config get ServiceSettings.SiteURL

# Set a config value
mmctl config set ServiceSettings.SiteURL "https://chat.yourdomain.com"
mmctl config set TeamSettings.MaxUsersPerTeam 1500

# Export config to stdout
mmctl config show
```

## Permissions & Roles

```bash
# Show role details
mmctl permissions role show system_admin

# Add a permission to a role
mmctl permissions add system_user_manager manage_team

# Remove a permission from a role
mmctl permissions remove system_user_manager manage_team
```

## Scripting Patterns

### Bulk Activate All Imported Users
```bash
mmctl user list --all --json | \
  jq -r '.[] | select(.delete_at == 0) | .username' | \
  while read -r user; do
    mmctl user activate "$user" 2>/dev/null
    echo "Activated: $user"
  done
```

### Export Channel Membership Counts
```bash
for ch in $(mmctl channel list myteam --json | jq -r '.[].name'); do
  COUNT=$(mmctl channel users list myteam:"$ch" --json 2>/dev/null | jq length)
  echo "$ch: $COUNT members"
done
```

### Verify Import Counts Match Phase 1
```bash
EXPECTED_USERS=150
EXPECTED_CHANNELS=75
ACTUAL_USERS=$(mmctl user list --all --json | jq length)
ACTUAL_CHANNELS=$(mmctl channel list myteam --json | jq length)
echo "Users: $ACTUAL_USERS / $EXPECTED_USERS"
echo "Channels: $ACTUAL_CHANNELS / $EXPECTED_CHANNELS"
```
