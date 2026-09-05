# Agent Perspective — What the Doctor Looks Like from the Other Side

This file describes the doctor as an *agent* (Claude / Codex / Gemini / Cursor / a script with no human in the loop) experiences it. SKILL.md describes what the skill builds; this file describes what the agent sees when calling it.

Useful for: training prompts; agent-builder docs; explaining the doctor to a new agent in 60 seconds.

---

## The agent's first interaction

A fresh agent in a fresh sandbox is told: "the project at `/work` may be broken. Investigate."

```bash
$ <tool> doctor --json
```

Expected single-shot output:
```jsonc
{
  "schema_version": "1.0",
  "tool": "<tool>",
  "tool_version": "...",
  "doctor_version": "...",
  "run_id": "2026-05-06T14-23-07Z__a3f9b2",
  "ok": false,
  "summary": {
    "total_findings": 3,
    "by_severity": { "P0": 1, "P2": 2 },
    "auto_fixable": 3,
    "online_required": 0
  },
  "findings": [...],
  "exit_code": 1,
  "next_steps": [
    "Run: <tool> doctor --fix",
    "Or scope: <tool> doctor --fix --only fm-...",
    "Inspect: <tool> doctor explain fm-..."
  ]
}
```

The agent now has:
- A list of findings (specific, with evidence).
- A list of paste-ready next-step commands.
- An exit code (1 = findings present without --fix).
- A run-id (for later reference).

**Decision tree:**
1. Are all findings auto-fixable? (`auto_fixable == total_findings`)
   - Yes → run `<tool> doctor --fix`.
   - No → run `<tool> doctor explain <id>` for the manual ones; surface to the user/planner.
2. Is any finding P0?
   - Yes AND auto_fixable → run `--fix` immediately.
   - Yes AND NOT auto_fixable → SURFACE to the user before any other action.
3. Is `online_required > 0`?
   - The agent has determined whether `--online` is permitted in this sandbox. If yes, re-run with `--online` to see those findings.

---

## The mega-command

If the agent wants to short-circuit decision-making:

```bash
$ <tool> doctor --robot-triage
```

Output:
```jsonc
{
  "schema_version": "1.0",
  "summary": { "ok": false, "total_findings": 3, "auto_fixable": 3 },
  "quick_ref": [
    "P0: 1 finding",
    "P2: 2 findings",
    "All auto-fixable"
  ],
  "findings": [...],
  "actions_planned": [
    { "fixer_id": "fm-state-files-...", "writes_to": [".beads/issues.jsonl"], "estimated_bytes": 4096 }
  ],
  "recommended_command": "<tool> doctor --fix",
  "capabilities_url": "<tool> doctor capabilities --json",
  "robot_docs_command": "<tool> doctor robot-docs"
}
```

The agent gets EVERYTHING needed in one call:
- The summary.
- The findings.
- The actions that would be taken.
- The exact command to run.
- Pointers to deeper info (`capabilities_url`, `robot_docs_command`).

This is the canonical agent invocation.

---

## What the agent reads vs. what the user reads

**Agent reads (machine):**
- `--json` / `--robot` output from any subcommand
- `capabilities --json` (the contract)
- `robot-docs` (the agent handbook)
- `report.json` from `.doctor/runs/<id>/`
- `actions.jsonl` from `.doctor/runs/<id>/`

**User reads (human):**
- bare `<tool> doctor` output (human-formatted)
- `report.md` from `.doctor/runs/<id>/`
- `scorecard.md` from the workspace
- `HANDOFF.md` from the workspace

The **same information** is in both, but the JSON forms are stable schemas the agent parses; the markdown forms are narrative for human reading.

---

## What the agent SHOULD NOT do

### 1. Don't ignore exit codes

```bash
<tool> doctor --json | jq '.findings[]'
```

If you don't check the exit code, you might miss exit 4 (refused for safety) or exit 5 (concurrency lost). Always:

```bash
<tool> doctor --json
ec=$?
case "$ec" in
  0) ;;     # healthy
  1) ;;     # findings present (default behavior)
  2) ;;     # fix partial
  3) ;;     # fix failed and rolled back
  4) ;;     # unsafe — refused
  5) ;;     # concurrency lost
  6) ;;     # online required
  64) ;;    # usage error
  *) ;;     # unknown — read capabilities --json::exit_codes
esac
```

### 2. Don't run `--fix` repeatedly without diagnosing

The doctor IS idempotent (Axiom 4) — running `--fix` twice is safe. But it's wasteful and noisy. Diagnose first, then fix. Each run produces a run-artifact directory; spamming creates many.

### 3. Don't hold a lock you don't need

The Agent Mail reservations from [ETIQUETTE.md](ETIQUETTE.md) — get them, use them, release them. Long-held reservations starve other agents.

### 4. Don't parse the human-readable output

```bash
<tool> doctor 2>&1 | grep "fm-"   # FRAGILE
```

Always use `--json`. The human output's wording can change between releases without bumping `doctor_contract_version`. The JSON schema is the contract.

### 5. Don't skip `robot-docs` on first contact

A fresh agent's first action with a new doctor:

```bash
<tool> doctor robot-docs
```

This is a complete agent handbook. After reading it, you know:
- The verb space.
- The exit-code dictionary.
- The negative-space spec ("things this doctor will NEVER do").
- The schema URLs.
- Canonical invocation examples.

It takes 30 seconds. Skipping it costs round-trips later.

---

## Reading `actions.jsonl` after a run

When investigating a `--fix` run:

```bash
cat .doctor/runs/<run-id>/actions.jsonl | jq '.'
```

Each line:
```jsonc
{
  "path": ".beads/issues.jsonl",
  "op": "WriteFile",
  "before_hash": "sha256:abc...",
  "after_hash": "sha256:def...",
  "started_at_ns": 12345678,
  "finished_at_ns": 12399999,
  "run_id": "...",
  "fixer_id": "fm-...",
  "ok": true
}
```

The agent uses this to:
- Verify what changed.
- Compute total mutation bytes.
- Plan an undo (in reverse order).

---

## Reading `report.json` after a run

```bash
cat .doctor/runs/<run-id>/report.json | jq '.'
```

Per [OUTPUT-SCHEMA.md](OUTPUT-SCHEMA.md), this is the canonical "what happened on this run" document.

- `report.json::state` — terminal STATE-MACHINE state (DONE_OK, DONE_FAILED, REFUSING, …).
- `report.json::findings[]` — the findings (always present, even after fix).
- `report.json::summary.actions_taken` — count of mutations.

---

## When the agent itself is the doctor's caller

The doctor's `report.json::next_steps` includes paste-ready commands. The agent's job is to:

1. Read `next_steps[0]`.
2. Validate it's a `<tool> doctor` invocation (security: never blindly execute).
3. Run it.
4. Recurse.

Eventually `report.json::ok == true` AND `next_steps == []`. The agent is done.

---

## Streaming / long-running

For Pattern 4 (daemon CLI), the agent can subscribe:

```bash
<tool> doctor health --watch | jq -c '.'
```

Each line is one health check. The agent keeps it open, processes events, may decide to invoke `<tool> doctor --fix` if things go red.

---

## When the doctor refuses

```jsonc
{
  "exit_code": 4,
  "state": "REFUSING",
  "reason": "schema_version_unknown",
  "evidence": {
    "on_disk": 9,
    "compiled_against": 8
  },
  "remediation": {
    "command_or_instruction": "Upgrade <tool> to version 0.6+ to handle schema v9, OR roll back to schema v8 with a migration script."
  }
}
```

The agent reads the structured remediation. It can:
- Surface to the user (canonical for "manual remediation required").
- Recurse if the remediation is itself an automatable command (e.g., upgrade via package manager, with user authorization).

The `<tool> doctor explain <finding-id>` command expands the evidence further if needed.

---

## A complete agent script (60-second tour)

```bash
#!/usr/bin/env bash
# minimal-doctor-loop.sh — agent's first-pass loop against a freshly-cloned project.

set -euo pipefail
target="${1:?usage: minimal-doctor-loop.sh <target-dir>}"
cd "$target"

echo "[agent] reading robot-docs..."
<tool> doctor robot-docs > .doctor.docs.txt    # Skip if already read in prior context

echo "[agent] running diagnose..."
diag=$(<tool> doctor --json) || true            # Exit 1 is OK for findings
echo "$diag" | jq '{ok: .ok, total: .summary.total_findings, auto: .summary.auto_fixable}'

if echo "$diag" | jq -e '.ok' >/dev/null; then
    echo "[agent] healthy; nothing to do"
    exit 0
fi

if echo "$diag" | jq -e '.summary.total_findings == .summary.auto_fixable' >/dev/null; then
    echo "[agent] all findings auto-fixable; running --fix"
    # Capture exit code separately — under set -e, `fix=$(cmd)` would abort
    # on non-zero exit (e.g., 2=partial, 3=rolled back) before we can inspect
    # the terminal state. The `|| fix_exit=$?` pattern keeps the script alive
    # so we can log a useful diagnosis.
    fix_exit=0
    fix=$(<tool> doctor --fix --json) || fix_exit=$?
    state=$(echo "$fix" | jq -r '.state // "MISSING_STATE_FIELD"')
    echo "[agent] fix exit=$fix_exit, terminal state=$state"
    if [ "$state" != "DONE_OK" ]; then
        echo "[agent] fix did not complete cleanly; surfacing to user"
        echo "$fix" | jq .
        exit 2
    fi
else
    echo "[agent] manual remediations present; surfacing"
    <tool> doctor --json | jq '.findings[] | select(.remediation.auto_fixable | not)'
    exit 1
fi

echo "[agent] done; final scorecard:"
<tool> doctor health
```

This script is the agent's complete contract with the doctor. It's < 30 lines because the doctor's surface is well-designed.

---

## Recommended reading order for a new agent

1. **`<tool> doctor robot-docs`** (30 seconds). Internalizes the verb space + negative-space spec.
2. **`<tool> doctor capabilities --json`** (10 seconds). Internalizes detector + fixer + exit-code lists.
3. **`<tool> doctor --robot-triage`** (current state in 1 call).
4. (Skim) The skill's [SKILL.md](../../SKILL.md) if the agent is curious about *why* the doctor behaves this way.

Everything else (PHASES.md, KERNEL.md, etc.) is for skill BUILDERS, not skill USERS. A user-agent doesn't need them.

---

## What the doctor learns about the agent

(For privacy / observability transparency.)

The doctor logs to `.doctor/runs/<id>/`:
- The shell environment (which env vars were set, NOT their values).
- The command-line invocation (the arguments).
- Tool version and OS.
- A run-id (deterministic; not user-derived).

It does **not** log:
- The agent's name, model, or session ID.
- The agent's prior commands or context.
- Any environment variable values (only their names, for the few it cares about).

If the agent wants to attribute its run for ops purposes, it can pass `--annotation "agent=claude-4-7"`. The annotation goes into `report.json::run_metadata.annotation` and is replayable.
