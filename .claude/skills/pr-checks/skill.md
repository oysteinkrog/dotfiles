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

# Watch mode (append-only log, hard timeout, stuck-detection)
pr-checks 6384 --repo InitialForce/ScDesktop --watch \
    --interval 60 --timeout 1800 --max-stable-polls 10 \
    --summary-to /tmp/pr-6384.json

# JSON output (one-shot)
pr-checks --json
```

## Watch mode

Watch mode emits one append-only line per poll (`[T+0060s poll#1] ✓31 ✗1 ⏳2 ⊝1 stable=0/10`),
honors `--timeout` (hard wall-clock limit), and detects "stuck" via `--max-stable-polls`
(give up if the pending set is identical for N consecutive polls). It also writes a
machine-readable JSON summary via `--summary-to`. Safe to run from a Claude Code
background task — it can never loop forever, and the output preserves scrollback.

Exit codes in watch mode:

- `0` all checks passed
- `1` at least one check failed (all terminal)
- `2` wall-clock timeout exceeded
- `3` pending set unchanged for N polls (stuck — investigate manually)
- `4` `gh` itself hung or failed repeatedly
- `130` user interrupt

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
