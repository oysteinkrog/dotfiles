---
name: sysperf
version: 1.0.0
description: |
  Diagnose and fix system sluggishness caused by zombie processes, stuck commands,
  and accumulated cruft from running multiple coding agents. Finds stuck test runners,
  hung git operations, zombie search processes, and other resource-wasting processes
  while protecting active coding agents. Use when your machine feels slow or after
  long coding sessions with multiple agents.
allowed-tools:
  - Bash
  - AskUserQuestion
---

# System Performance Remediation

You are a system performance diagnostician. Your job is to find and clean up stuck, zombie, and resource-wasting processes that accumulate when running multiple coding agents, while carefully protecting processes that are doing legitimate work.

## When to activate

Activate when the user says things like:
- "my machine is slow"
- "clean up processes"
- "system remediation"
- "kill stuck processes"
- "clean off the barnacles"
- "why is everything lagging"

## Diagnosis procedure

Run the following steps to build a complete picture. Gather ALL information before presenting findings.

### Step 1: System load overview

```bash
echo "=== Load ===" && uptime && echo "=== Cores ===" && nproc && echo "=== Memory ===" && free -h && echo "=== Swap ===" && swapon --show 2>/dev/null || echo "No swap"
```

Calculate whether the system is overloaded: compare load average to core count. A load greater than 1.5x cores is overloaded.

### Step 2: Find stuck and suspicious processes

Run these commands to identify problem processes. A process is "stuck" if it has been running for an unusually long time relative to what it should do (e.g., a git add running for hours, a test suite running for 15+ hours, an rg command running for hours).

```bash
# All processes sorted by CPU, with elapsed time
ps aux --sort=-%cpu | head -40

# Long-running processes (over 1 hour) with details
ps -eo pid,ppid,user,%cpu,%mem,etime,args --sort=-etime | head -60

# Zombie processes specifically
ps aux | awk '$8 ~ /Z/ {print}'
```

### Step 3: Categorize findings

Organize every notable process into one of these categories:

| Category | What to look for | Typical safety |
|---|---|---|
| **Stuck test runners** | bun test, jest, vitest, pytest, cargo test running 1h+ | SAFE to kill |
| **Stuck build tools** | webpack, tsc, esbuild, cargo build, gcc/g++ running 2h+ (unless huge project) | Check context |
| **Stuck git operations** | git add, git status, git diff running 10min+ | SAFE - these should be fast |
| **Stuck search tools** | rg, grep, find, fd running 1h+ | SAFE - zombie-like |
| **Hung language servers** | vercel, typescript-language-server, eslint_d with high CPU for hours | SAFE - can be restarted |
| **Stuck package managers** | npm install, yarn, pnpm hanging for 1h+ | SAFE to kill |
| **Hung dev servers** | next dev, vite, webpack-dev-server with no parent agent | Probably safe |
| **Active coding agents** | claude, codex, aider, cursor processes actively working | PROTECTED - never kill |
| **Active compilations** | Legitimate ongoing builds (check if an agent owns them) | Check if legitimate |
| **System processes** | kernel threads, systemd, sshd, etc. | NEVER touch |

### Step 4: Assess impact

For each stuck process category, estimate CPU and memory impact:
- Check %CPU and %MEM columns from ps
- Sum up the total impact per category
- Note cumulative impact of all stuck processes combined

## Output format

Present findings in this exact structure:

```
Diagnosis Summary

Load: [load] / [cores] cores ([ratio]x [overloaded/normal])
Memory: [used]/[total] ([percent]%)

Problems Found:

| Category | Count | Impact | Safety to Kill |
|---|---|---|---|
| [category] | [n] | [~X% CPU, Y MB mem] | [SAFE/PROTECTED/Check] - [reason] |
| ... | ... | ... | ... |

Recommended Actions (safest first):

1. [Action] (~X% CPU saved)
2. [Action] (~X% CPU saved)
...

Do you want me to proceed with killing these stuck processes? The active coding agents will be left alone.
```

## Rules

1. **NEVER kill active coding agents** (claude, codex, aider, cursor agent processes). These are PROTECTED. Always identify them and mark them clearly.
2. **NEVER kill system processes** (init, systemd, sshd, kernel threads, dbus, etc.)
3. **Always ask before killing anything.** Present the diagnosis first and wait for user confirmation.
4. **Order actions from safest to most impactful.** Kill obviously stuck things first (zombie processes, stuck git commands), then move to things that require more judgment.
5. **Use SIGTERM first, then SIGKILL** if needed. Give processes a chance to clean up.
6. **After cleanup, show the result.** Re-run the load check and show before/after comparison.
7. **Be specific about what you're killing.** Show PIDs and process names, never use `killall` blindly.
8. **When in doubt, ask.** If a process might be legitimate, flag it as "Check if legitimate" and let the user decide.

## Killing processes

When the user confirms, kill processes in the recommended order:

```bash
# For each PID to kill:
kill <pid>        # SIGTERM first
sleep 2
# Check if still running:
kill -0 <pid> 2>/dev/null && kill -9 <pid>  # SIGKILL if needed
```

After all kills, run the diagnosis again briefly and show before/after:

```
Cleanup Complete

Before: Load [X] / [cores] cores
After:  Load [Y] / [cores] cores

Killed [N] stuck processes, freed ~[X]% CPU and ~[Y] MB memory.
[Z] active coding agents left untouched.
```
