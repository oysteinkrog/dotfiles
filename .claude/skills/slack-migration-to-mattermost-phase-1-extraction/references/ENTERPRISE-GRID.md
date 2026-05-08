# Enterprise Grid Specifics

Enterprise Grid introduces multi-workspace complexity. This reference covers the unique aspects of Grid migrations.

## How Grid Exports Differ

Enterprise Grid exports span **multiple workspaces** within an organization. The export ZIP structure is different from single-workspace exports.

### Grid Export Structure
```
enterprise_grid_export.zip
├── org_metadata.json           # Organization-level metadata
├── workspace_1/
│   ├── channels.json
│   ├── users.json
│   └── #channel-name/*.json
├── workspace_2/
│   ├── channels.json
│   ├── users.json
│   └── #channel-name/*.json
└── ...
```

### Splitting Grid Exports
Use `mmetl grid-transform` to split into per-workspace ZIPs:
```bash
./mmetl grid-transform --file enterprise_grid_export.zip
# Produces: workspace_1.zip, workspace_2.zip, etc.

# Then transform each workspace individually
for ws_zip in workspace_*.zip; do
  ws_name=$(basename "$ws_zip" .zip)
  ./mmetl transform slack \
    --team "$ws_name" \
    --file "$ws_zip" \
    --output "${ws_name}_import.jsonl"
done
```

## Enterprise Export Scoping

Enterprise Grid admins have more granular export controls than Business+:

| Scope | Description |
|-------|-------------|
| By conversation type | Public channels, private channels, DMs, group DMs |
| By member | Export only conversations involving specific users |
| By workspace | Export specific workspaces within the org |
| Full org export | Everything across all workspaces |

### When to Use Scoped Exports
- **Partial migration:** Moving only specific teams/workspaces to Mattermost
- **Compliance extract:** Pulling data for specific users under legal hold
- **Incremental testing:** Testing with a single workspace before full migration

## Discovery API

Enterprise Grid includes access to the **Discovery API** for approved third-party eDiscovery/DLP applications.

### What It Provides
- Programmatic access to message content across the org
- Real-time or near-real-time data access
- Integration with approved partners (Relativity, Veritas, etc.)

### What It Doesn't Do
- NOT available to customer-built apps (requires Slack partnership)
- NOT a migration tool (designed for compliance/eDiscovery)
- NOT a replacement for the official export

### When to Use Discovery API for Migration
Only if:
1. Your org already has Discovery API enabled
2. You have an approved partner in place
3. The official export is insufficient for some reason
4. Treat it as an **optional enterprise-only supplement**, not the default backbone

## Enterprise-Specific Gotchas

### Cross-Workspace Channels
Enterprise Grid supports channels shared between workspaces. These appear in the export of each workspace they're shared with, potentially creating duplicates in a multi-workspace import.

**Fix:** Import into separate Mattermost teams (one per workspace) and use Mattermost's shared channels feature if available, or choose one canonical workspace for each shared channel.

### User Identity Across Workspaces
In Enterprise Grid, users can be members of multiple workspaces. Their user ID is consistent across the org, but workspace-level profiles may differ.

**For migration:** Use the org-level user profile as canonical. Ensure emails are consistent across workspace exports.

### Admin Roles
Enterprise Grid has org-level admins and workspace-level admins. Org-level admin access is needed for org-wide exports.

### Security Alerts
Slackdump's README explicitly warns that Enterprise Grid workspaces may trigger security alerts or admin notifications when scraping tools are detected. If using slackdump as a supplement:
- Get explicit authorization from the Enterprise admin
- Document the authorization
- Use during approved maintenance windows
- Expect security team inquiries

## Enterprise Migration Decision Tree

```
Enterprise Grid?
|
+-- Single workspace to migrate
|   |
|   +-- Use workspace-scoped export
|   +-- Transform with mmetl as normal
|   +-- Import to single Mattermost team
|
+-- Multiple workspaces to migrate
|   |
|   +-- Option A: Full org export → grid-transform → per-workspace import
|   |   Pro: Complete, consistent
|   |   Con: Very large, complex
|   |
|   +-- Option B: Per-workspace exports → individual transforms
|       Pro: Smaller, can parallelize
|       Con: Must coordinate user dedup
|
+-- All workspaces to migrate
    |
    +-- Full org export (recommended)
    +-- grid-transform to split
    +-- Import each workspace as separate Mattermost team
    +-- Consider Mattermost Enterprise for multi-team management
```

## Mattermost Enterprise Licensing

For 1000+ user migrations, consider Mattermost Enterprise:
- Team Edition is positioned for <250 users
- Enterprise adds: SSO/SAML, AD/LDAP sync, HA, compliance features
- Enterprise E20 adds: advanced compliance, custom retention policies
- The server software itself can scale beyond Team Edition limits with enough hardware, but support and features are gated

Plan licensing as part of the migration design, not as an afterthought.
