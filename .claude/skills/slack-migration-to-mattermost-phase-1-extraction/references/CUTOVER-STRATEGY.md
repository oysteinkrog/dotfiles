# Cutover Strategy: Baseline + Deltas + Final

For production migrations, don't do a single big-bang import. Use an incremental approach.

## The Three-Phase Pattern

```
Phase A: Baseline Import (weeks before cutover)
  - Full export + enrich + transform + import into STAGING
  - Verify counts, sample threads, check attachments
  - Iterate until staging looks correct

Phase B: Delta Imports (ongoing until cutover)
  - Business+ recurring exports (weekly/monthly)
  - Each delta covers only the new period's data
  - Transform and import deltas into staging
  - Mattermost's idempotent import handles overlap safely

Phase C: Final Cutover (cutover day)
  - Freeze Slack to read-only
  - Run one last ad hoc export for the final window
  - Enrich + transform + import the final delta
  - Run verification
  - Switch DNS / announce move to users
```

## Phase A: Baseline

### Steps
1. Run full official export (all-conversations, entire history)
2. Enrich: slack-advanced-exporter for emails + files
3. Export custom emoji separately
4. Transform with mmetl
5. Import into a **staging** Mattermost instance (not production)
6. Verify:
   - Channel count matches Slack channel audit CSV
   - User count matches Slack admin user list
   - Sample 10-20 channels: message counts, thread integrity, file attachments
   - Check reactions on a sample of messages
   - Verify custom emoji appear correctly

### Common Issues at Baseline
- Missing users (email mismatches) -- fix with `--default-email-domain`
- Missing files (enrichment incomplete) -- re-run attachment fetcher
- Truncated messages (MaxPostSize too low) -- increase to 16383
- Guest role conflicts -- transform script should auto-fix

### How Long?
- Small team (<100 users, <1 GB export): hours
- Medium team (100-500 users, 1-10 GB): a day or two
- Large team (500-1000+ users, 10-50+ GB): several days to a week, with split-import

## Phase B: Delta Imports

### Setup
On Business+, enable **recurring scheduled exports** (weekly or monthly). Each export covers only the new period.

### Process
For each delta:
1. Download new export ZIP from Slack
2. Enrich (emails and new file attachments)
3. Transform with same team name
4. Import into staging

### Why This Works
Mattermost's bulk import is **idempotent**: importing the same post twice doesn't create a duplicate. Posts are matched by original timestamp + channel + user. So even if deltas overlap slightly with the baseline, no harm done.

### When Not Available
If recurring exports aren't available (Pro plan), use slackdump with date-range filtering as an approximate delta source. Less authoritative but still useful for keeping staging current.

## Phase C: Final Cutover

### Pre-Cutover Checklist
- [ ] Staging Mattermost verified and approved
- [ ] Production Mattermost deployed and configured (Phase 2 skill)
- [ ] DNS ready to switch (or already pointing to Mattermost)
- [ ] User communication sent: "Slack goes read-only on DATE, Mattermost goes live"
- [ ] Admin has Slack export permissions ready
- [ ] All tools installed and tested on production host

### Cutover Day
1. **Freeze Slack** -- set workspace to read-only or announce freeze
2. **Final export** -- trigger ad hoc all-conversations export covering the delta window
3. **Enrich** -- run slack-advanced-exporter on the final export
4. **Transform** -- mmetl with same team name
5. **Import into PRODUCTION** -- upload and process
6. **Import emoji** -- if any new emoji since baseline
7. **Verify**:
   - Channel counts match
   - User counts match
   - Latest messages from the delta window are present
   - File attachments accessible
8. **Activate** -- announce Mattermost is live
9. **Users activate accounts** -- password reset via Slack email address

### Rollback Plan
If critical issues are found after cutover:
- Mattermost data is still there; users can keep using it
- Slack can be unfrozen temporarily
- Run additional delta imports to fill gaps
- The idempotent import means you can always re-import without duplicates

## Verification Checklist

| Check | How |
|-------|-----|
| Channel count | `mmctl channel list TEAM` vs Slack channel audit CSV |
| User count | `mmctl user list --all` vs Slack admin user list |
| Message sample | Pick 5 channels, compare recent message counts |
| Thread integrity | Check 3-4 long threads for reply continuity |
| File attachments | Open 10 random file attachments in Mattermost |
| Custom emoji | Use 5-10 custom emoji in a test message |
| DM preservation | Check 2-3 DM conversations |
| Reactions | Verify reactions on a few known messages |
| Bot messages | Check messages from Slack bots/integrations |

## Timeline Template

| When | Action |
|------|--------|
| T-4 weeks | Baseline export + enrichment + staging import |
| T-3 weeks | Verify staging, iterate on issues |
| T-2 weeks | First delta import, re-verify |
| T-1 week | Second delta, user communication, production server ready |
| T-1 day | Final prep, test cutover on staging |
| T-0 | Freeze Slack, final export, import to production, go live |
| T+1 day | Monitor, handle user issues, verify |
| T+1 week | Revoke Slack tokens, delete migration app, secure exports |
