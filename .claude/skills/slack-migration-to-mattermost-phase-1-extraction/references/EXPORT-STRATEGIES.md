# Export Strategies: Deep Comparison

## Slack Plan Tier Matrix

| Capability | Free | Pro | Business+ | Enterprise Grid |
|---|---|---|---|---|
| Public channel export | yes | yes | yes | yes |
| Private channel export | no | no (unless legal approval) | yes (after admin approval) | yes |
| DM export | no | no | yes | yes |
| Group DM export | no | no | yes | yes |
| Recurring scheduled exports | no | no | weekly/monthly | weekly/monthly |
| Channel audit CSV | no | no | yes | yes |
| Custom export scoping | no | no | no | by conversation type/member/workspace |
| Discovery API | no | no | no | yes (approved partners only) |

**Key insight:** "Paid Slack" is not enough. Pro only exports public channels unless Slack approves an exceptional legal request. Business+ is the minimum tier for all-conversations export.

### Business+ All-Conversations Export Approval

Business+ does NOT automatically grant all-conversations export. Workspace Owners must **apply to Slack for approval**, and Slack evaluates applications against specific criteria:

- **Valid legal process** (subpoena, court order, regulatory requirement)
- **Consent of members** (documented agreement from workspace members)
- **Requirement under applicable laws** (data retention, compliance obligations)

Slack will **reject applications** that don't meet these criteria. This approval step is a potential **multi-day or multi-week blocker** -- initiate it early in migration planning, not at cutover time.

Once approved, Business+ also unlocks:
- **Scheduled recurring exports** (weekly or monthly) for the delta migration pattern
- **Channel audit report CSV** for migration planning and verification

### Pro Plan Workaround
On Pro, Workspace Owners can contact Slack and apply under "limited circumstances" for all-conversations export, but approvals are rare. The practical alternative is slackdump (Strategy B), which exports everything the authenticated user can see.

## Strategy A: Official Slack Admin Export

### When to Use
- Business+ or Enterprise Grid (gets DMs and private channels)
- Compliance-friendly, officially sanctioned
- Want scheduled recurring exports for delta migration
- **Pre-requisite:** All-conversations export approval received from Slack

### Flow
1. Apply for and receive all-conversations export approval (Business+)
2. Admin > Workspace Settings > Security > Import/Export Data > Export tab
3. Select date range (or "Entire history")
4. Click Start Export
5. Slack emails when ready (can take hours for large workspaces)
6. Return to export page > click "Ready for download" > get ZIP
7. **Also download the channel audit report CSV** from the same page (for verification)

### What the ZIP Contains
- `channels.json` -- public channel metadata
- `groups.json` -- private channel metadata
- `dms.json` -- DM conversation metadata
- `mpims.json` -- group DM metadata
- `users.json` -- user profiles
- `integration_logs.json` -- app activity
- Per-channel folders with date-named JSON files (messages)
- Canvas HTML and list JSON (when all-conversations export approved)

### Critical Limitation
**File attachments are LINKS, not files.** The JSON contains `url_private` references to Slack-hosted files. These links expire. You MUST enrich with `slack-advanced-exporter` or download files via API before links go dead.

### Automation Options
No public API to trigger exports. Automate via:
- Playwright browser automation of the admin UI
- IMAP/Gmail API polling for the export-ready email
- Auto-download when email arrives

For Business+ with recurring exports enabled, the system can passively poll for new export emails.

## Strategy B: Slackdump

### When to Use
- Pro plan (can't get official DM/private export)
- Need actual file attachments in the archive
- Want CLI-driven automation without browser UI
- Gap-filling supplement to official export

### Key Commands
```bash
# Full export with files (Mattermost format by default in v4+)
slackdump export -o slack_export.zip -files

# Export specific channels
slackdump export -o export.zip C0123456789 C9876543210

# Exclude channels (prefix with ^)
slackdump export -o export.zip ^C0123456789

# Emoji export
slackdump emoji -o ./emoji_dir/
```

### Access Model
Slackdump uses your personal Slack session. It can only access:
- All public channels
- Private channels you are a member of
- DMs you are a participant in
- Group DMs you are a participant in

It **cannot** access other people's DMs or private channels you're not in.

### Slackdump vs Official Export

| Dimension | Official Export | Slackdump |
|-----------|:-:|:-:|
| Authoritative for compliance | yes | no |
| Gets other people's DMs (Biz+) | yes | no |
| Includes file binaries | no | yes |
| Needs admin access | yes | no |
| Risk of security alerts | no | yes (Enterprise) |
| Mattermost-compatible output | no (needs mmetl) | yes (native) |
| Custom emoji | no | yes (separate cmd) |
| Rate limiting handling | N/A | automatic backoff |

### Recommended Hybrid Approach
For maximum fidelity:
1. **Official export** as authoritative message archive (gets ALL private channels/DMs with Biz+)
2. **slack-advanced-exporter** to add emails and file binaries
3. **Slackdump** as fallback for channels/data the official export missed
4. **Slack API** for custom emoji and verification

## What Neither Strategy Captures

- Bookmarks (no export path exists)
- Workflows/automations (must rebuild)
- App integrations (must reconfigure)
- Slack Connect external org messages (external org controls their data)
- Deleted files/channels (may be irrecoverable)
- Message edit history (only latest version exported)
- Audit Logs API content (metadata only, not message content)
- Legal Holds content (preserves but does not provide access)
- `admin.analytics.messages.metadata` (structure without content)

## Enterprise Grid Specifics

- Org-level exports can span multiple workspaces
- Use `mmetl grid-transform` to split Enterprise Grid export into per-workspace files
- Custom exports can scope by conversation type, member, or workspace
- Discovery API available for approved eDiscovery/DLP partners
