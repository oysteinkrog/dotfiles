# br Troubleshooting

## The Doctor Command

```bash
br doctor                            # Run full diagnostics
```

Checks:
- Database integrity
- Schema version
- JSONL sync status
- Configuration validity
- Path permissions

---

## Common Errors and Fixes

### "Database locked"

```bash
# Check for other br processes
pgrep -f "br "

# Force close and retry
br sync --status  # Safe read-only check
```

### "Issue not found"

```bash
# Check if issue exists
br list --json | jq '.[] | select(.id == "<id>")'

# Check for similar IDs
br list | grep -i "abc"
```

### "Prefix mismatch"

```bash
# Check your prefix
br config get issue-prefix

# Import after aligning prefix/config with your existing IDs
br sync --import-only
```

### "`br ready` fails with blocked_issues_cache SQL error"

Some versions (e.g. `br 0.1.8`) have a known bug in `br ready` that can throw:

```
no such column: blocked_issues_cache.issue_id
```

Workarounds:

```bash
# Use bv's actionable recipe
bv --recipe actionable --robot-plan

# Or fall back to list + manual filtering
br list --json | jq '.[] | select(.status == "open" or .status == "in_progress")'
```

### Worktree Error

If you get `failed to create worktree: 'main' is already checked out`:

```bash
git branch beads-sync main
git push -u origin beads-sync
br config set sync-branch beads-sync
```

Always use a dedicated sync branch that you never check out directly.

### Sync Issues After Git Merge

```bash
# 1. Check for JSONL merge conflicts
git status .beads/

# 2. If conflicts, resolve manually then:
br sync --import-only

# 3. If database seems stale:
br doctor
```

---

## Debugging

```bash
# Verbose output
br -v list

# Debug output
br -vv list

# Check RUST_LOG for detailed logs
RUST_LOG=debug br list
```

---

## Quick Health Check

```bash
br doctor                    # Full diagnostics
br dep cycles                # Must be empty
br config list               # Check settings
which br                     # Verify br is installed
```
