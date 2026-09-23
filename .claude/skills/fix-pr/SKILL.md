---
name: fix-pr
description: |
  Monitor PR and fix any check failures until it is all green. Use when user says
  "monitor PR", "fix CI", "fix checks", "make PR green", or after creating a PR
  that has failing checks.
triggers:
  - "monitor PR"
  - "fix CI"
  - "fix checks"
  - "make PR green"
  - "make it green"
  - "fix PR"
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - Task
  - Skill
argument-hint: "[PR-number]"
---

# Monitor PR Checks

Poll a PR's check status, diagnose failures, fix them, push, and repeat until all checks pass.

## Inputs

- **PR number or URL** — if not provided, detect from current branch:
  ```bash
  gh pr view --json number,url,headRefName 2>/dev/null
  ```
- If no PR exists for the current branch, abort with a message.

## Workflow

### Loop: Poll → Diagnose → Fix → Push → Repeat

```
while checks not all green:
  1. Poll check status
  2. If all passed → done, report success
  3. If any still pending → run the watcher until checks finish
  4. If any failed → diagnose and fix
  5. Push fix and restart loop
```

### Step 1: Poll Check Status

```bash
gh pr checks <number> --repo InitialForce/ScDesktop
```

Parse the tabular output. Classify each check:
- `pass` → passed
- `pending` → pending (wait)
- `skipping` → finished without running (not pending)
- `fail` → failed (diagnose)

Note: `gh pr checks` does NOT support `--json`. Parse the tab-separated text output.

Also check: if `skipping` checks depend on a failed check (e.g. Build skips when a gate fails), fix the gate first.

### Step 2: Handle Pending Checks

If checks are still running and none have failed, do not write a `sleep` loop (foreground `sleep` is blocked). Run the watcher with the Bash tool's `run_in_background: true`, so it can outlast the 10-minute Bash timeout:
```bash
pr-checks <number> --watch
```

It polls every 60s, treats `skipping` as finished, and exits when every check is done: 0 = all passed, 1 = a check failed. It gives up after 30 min (exit 2) or when the pending set has not changed for 10 polls (exit 3). On exit 2 or 3, report status and ask the user. If `pr-checks` is missing, use `gh pr checks <number> --watch --fail-fast` the same way.

### Step 3: Diagnose Failures

#### Get CI Logs

Extract the run ID from the details URL in `gh pr checks` output:
```
# URL format: https://github.com/OWNER/REPO/actions/runs/RUN_ID/job/JOB_ID
```

```bash
# Get failed step logs
gh run view <run-id> --repo InitialForce/ScDesktop --log-failed 2>&1 | tail -100

# Or get specific job logs via API
gh api repos/InitialForce/ScDesktop/actions/jobs/<job-id>/logs 2>&1 | tail -60
```

#### Common CI Checks and Fixes

| Check | What it does | How to fix |
|-------|-------------|-----------|
| **Banned API Check** | Scans Test.Unit for `Process.Start`, `File.` I/O | Move offending test to Test.Integration |
| **Provider Isolation** | Checks Test.Unit has no direct EF SQLite ref | Remove PackageReference or move test |
| **Build** | `dotnet build` | Fix compiler errors: `cmd.exe /c "dotnet build ..."` |
| **Unit Tests** | `dotnet test` Test.Unit | Run locally: `/run-tests --filter <name>` |
| **Integration Tests** | `dotnet test` Test.Integration | Run locally: `/run-tests --filter <name>` |
| **Code Analysis** | ReSharper InspectCode | Use `/inspectcode` skill |
| **Check Localization** | Validates .resx files | Use `/localize` skill |

### Step 4: Fix the Issue

1. **Read the relevant source files**
2. **Make the fix**
3. **Verify locally** — build/test to confirm
4. **Commit the fix:**
   ```bash
   git add <specific-files>
   git commit -m "<area>: fix <description>"
   ```
   End the message with the attribution lines the session gives you.

### Step 5: Push and Restart

```bash
git push my <branch> --force-with-lease
```

Then go back to Step 1 and wait for new checks.

## Completion

When all checks are green:
```
✅ All PR checks passed:
- Check 1: pass
- Check 2: pass
- ...

PR #XXXX is ready for review.
```

## Safety

- Never force push to main/master
- Use `--force-with-lease` for safety
- Ask user before making non-obvious fixes (disabling tests, changing CI config)
- Maximum 5 fix iterations before asking user for guidance
- Do not modify CI workflow files unless explicitly told to
- If a test is flaky (passes locally, fails in CI), note it and ask user
