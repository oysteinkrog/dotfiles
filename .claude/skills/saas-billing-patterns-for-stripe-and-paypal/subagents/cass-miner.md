---
name: billing-cass-miner
description: Phase 0 — mines the user's cass session history for billing-relevant patterns, prior incidents, decisions, and reusable prompts
---

# Billing CASS Miner

If the user has `/cass` installed and indexed, mine their past agent sessions BEFORE diving into Phase 1 archaeology. The user's own history surfaces incidents that don't appear in commits / beads, decisions that were made but never documented, and prompts that worked.

## Inputs

- `/cass` skill installed and indexed.
- Project path (for filtering / scoping).
- Time window (default: last 365 days).

## Output

`.billing_workspace/phase0_cass_mining_results.md` per the format in `references/methodology/CASS-MINING.md`.

## Procedure

Follow the 7 recipes in `references/methodology/CASS-MINING.md`:

1. **Recipe 1** — search for prior billing-incident discussions (duplicate charges, hijacks, stale events, refunds, pool exhaustion, webhook 200-on-error, email failsafe, dunning).
2. **Recipe 2** — find working prompts the user has used before for billing tasks.
3. **Recipe 3** — mine for environment / stack hints (env var names, helper names, decisions).
4. **Recipe 4** — mine for bug-class recurrences (3+ sessions on same class signals systemic gap).
5. **Recipe 5** — mine for prior partial implementations to pick up from.
6. **Recipe 6** — discover new cass capabilities you didn't know about.
7. **Recipe 7** — mine prior scope decisions before widening the billing run or activating optional bundles.

## Discipline

- NEVER run bare `cass` (TUI). Always use `--robot` or `--json`.
- Use `--days N` to bound time windows.
- Use `--agent` to filter by specific agent if needed.
- Don't dump raw cass JSONL into the workspace; distill to themes.
- Don't trust cass over current code; always cross-reference with `git log` / current files.
- Capture user voice exactly (don't paraphrase policy commitments).
- Don't search for secrets; redact if found.

## Output template

```markdown
# CASS Mining Results

Generated: <timestamp>
Project: <PROJECT_PATH>
Time window: --days 365
Total sessions reviewed: <N>

## Themes (most informative findings)

### Theme A: <name>
- N prior sessions discussed this class.
- Session 1 (<date>): <summary>
- Session 2 (<date>): <summary>
→ Phase 4 task: <action>

### Theme B: ...

## Prompts to reuse
- "<prompt>" — worked well in session <date>; reuse for <bundle> implementer.

## Decisions already made (from prior sessions)
- <decision> (per session <date>) → mark <bundle> patterns <status>.

## Recurring bug classes (signal for systemic fix)
- Class X: N occurrences in 12 months → propose a drift-guard.

## Reusable prompts
[list of prompts the user has successfully used; they'll be more effective than generic prompts]
```

## When cass is missing

Inline fallback: ask the user for:
- Last 5 billing-incident postmortems.
- Bead/issue history filtered by `billing` / `stripe` / `paypal` labels.
- Support tickets filtered by `payment` / `subscription` / `refund`.
- Git log filtered by `^(stripe|paypal|webhook|subscription|invoice|refund|dunning|mrr)`.

These give you 80% of what cass would surface.

## Integration

Pass the artifact to:
- Phase 1 archaeologists (per-bundle context).
- Phase 3 risk scorer (recurring bugs get higher severity).
- Phase 4 planner (reuse prior task structures).
- Phase 7 fresh-eyes (search for prior failed-approach context).
- Phase 10 runbook writer (prior incident threads → runbooks).
