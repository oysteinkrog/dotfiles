# PR Checks — Beautiful PR Check Status

Display PR check status in a beautiful, aligned, color-coded format.

## When to Use

Use when user says "check PR", "PR status", "check checks", "pr checks", or wants to see CI status for a PR.

## Usage

```bash
# Current branch PR (auto-detect)
pr-checks

# Specific PR
pr-checks 6384

# Specific repo
pr-checks 6384 --repo InitialForce/ScDesktop

# Watch mode (poll every 60s)
pr-checks 6384 --repo InitialForce/ScDesktop --watch

# JSON output
pr-checks --json
```

## Output

Shows:
- Overall status badge (ALL GREEN / FAILING / PENDING)
- Progress bar with pass/fail/pending/skip proportions
- Each check with icon, badge, name, and duration
- Sorted: failures first, then pending, then passed, then skipped
- Color-coded for instant scanning

## Exit Codes

- 0: All checks passed
- 1: At least one check failed
- 2: Checks still pending

## Arguments

Run the script with `pr-checks` (it's in ~/bin which is on PATH).
Pass any arguments the user provides. Default to auto-detecting PR from current branch.
