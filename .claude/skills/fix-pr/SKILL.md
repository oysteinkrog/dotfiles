---
name: fix-pr
description: |
  Monitor PR and fix any check failures until it is all green. Use when user says
  "monitor PR", "fix CI", "fix checks", "make PR green", or after creating a PR
  that has failing checks.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - Task
---

# Monitor PR Checks

Poll a PR's check status, diagnose failures, fix them, push, and repeat until all checks pass.

## When to Use

- After creating a PR and wanting to ensure all checks pass
- When CI checks are failing on an existing PR
- User says "monitor PR", "fix CI", "fix checks", "make it green"

## Inputs

- **PR number or URL** - if not provided, detect from current branch:
  ```bash
  gh pr view --json number,url,headRefName 2>/dev/null
  ```
- If no PR exists for the current branch, abort with a message.

## Workflow

### Loop: Poll -> Diagnose -> Fix -> Push -> Repeat

```
while checks not all green:
  1. Poll check status
  2. If all passed -> done, report success
  3. If any still pending -> wait and re-poll
  4. If any failed -> diagnose and fix
  5. Push fix and restart loop
```

### Step 1: Poll Check Status

```bash
gh pr checks <number> --json name,state,conclusion,detailsUrl
```

Classify each check:
- `SUCCESS`/`NEUTRAL`/`SKIPPED` -> passed
- `PENDING`/`QUEUED`/`IN_PROGRESS`/`WAITING`/`REQUESTED`/`ACTION_REQUIRED` -> pending
- `FAILURE`/`CANCELLED`/`TIMED_OUT`/`STALE`/`STARTUP_FAILURE` -> failed

### Step 2: Handle Pending Checks

If checks are still running and none have failed yet, wait and re-poll:
```bash
sleep 60
```

Re-poll up to 30 times (30 minutes). If still pending after that, report status and ask user.

### Step 3: Diagnose Failures

For each failed check, get details:

```bash
# Get the details URL from the check output
gh pr checks <number> --json name,state,conclusion,detailsUrl
```

#### Common failure types and how to diagnose:

**Build failures:**
- Look for compiler errors in the CI log
- Reproduce locally: `build.cmd build` or `./build.sh build`

**Test failures:**
- Identify which tests failed from CI output
- Run failing tests locally: `build.cmd test --filter <TestName>`

**Code inspection failures:**
- Run inspection locally: `build.cmd inspect`
- Look for ERROR-level issues

**Linting/format failures:**
- Check for trailing whitespace, formatting issues
- Run relevant linters locally

#### Fetching CI Logs

Use `gh` to fetch run logs when detailsUrl points to GitHub Actions:
```bash
# Extract run ID from the details URL
# URL format: https://github.com/OWNER/REPO/actions/runs/RUN_ID/...
gh run view <run-id> --log-failed
```

If the log is too large, focus on the failing step:
```bash
gh run view <run-id> --log-failed 2>&1 | tail -200
```

### Step 4: Fix the Issue

Based on diagnosis:

1. **Read the relevant source files** to understand context
2. **Make the fix** - edit files as needed
3. **Verify locally** - build/test to confirm the fix works
4. **Absorb into correct commit** if the branch has multiple commits:
   ```bash
   git add -A
   git absorb --and-rebase
   ```
   Or amend if single commit:
   ```bash
   git add -A
   git commit --amend --no-edit
   ```

### Step 5: Push and Restart

```bash
git push --force-with-lease
```

Then go back to Step 1 and wait for new checks to run.

## Completion

When all checks are green, report:
```
All PR checks passed:
- check-name-1: passed
- check-name-2: passed
- ...

PR is ready for review.
```

## Safety

- Never force push to main/master
- Use `--force-with-lease` for safety
- Ask user before making non-obvious fixes (e.g., disabling tests, changing CI config)
- If a fix requires architectural changes or is unclear, stop and ask the user
- Maximum 5 fix iterations before asking the user for guidance
- Do not modify CI workflow files unless explicitly told to

## Tips

- If multiple checks fail, fix the build first (other checks often depend on it)
- If a test is flaky (passes locally, fails in CI), note it and ask the user
- Check if the failure is in code you changed vs pre-existing
