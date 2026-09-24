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

- **PR number or URL**: if not provided, detect from current branch:
  ```bash
  gh pr view --json number,url,headRefName 2>/dev/null
  ```
- If no PR exists for the current branch, abort with a message.
- **Repository**: detect `OWNER/REPO` from the current checkout and use it as `<repo>` below:
  ```bash
  gh repo view --json nameWithOwner --jq .nameWithOwner
  ```

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
gh pr checks <number> --repo <repo>
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
gh run view <run-id> --repo <repo> --log-failed 2>&1 | tail -100

# Or get specific job logs via API
gh api repos/<repo>/actions/jobs/<job-id>/logs 2>&1 | tail -60
```

#### Find the Local Equivalent

Read the failed step's log to see the exact command CI ran. Run that command locally to reproduce the failure. Check the repo's `CLAUDE.md` and `AGENTS.md` for its build, test and lint commands, and for any project skills that cover them.

### Step 4: Fix the Issue

1. **Read the relevant source files**
2. **Make the fix**
3. **Verify locally**: build and test to confirm
4. **Commit the fix:**
   ```bash
   git add <specific-files>
   git commit -m "<area>: fix <description>"
   ```
   End the message with the attribution lines the session gives you.

### Step 5: Push and Restart

```bash
git push --force-with-lease
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
