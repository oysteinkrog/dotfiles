---
name: cass-pattern-miner
description: Phase 0.5 / Onboarding mode — formalized subagent that mines /cass session history for project-specific theater patterns and folds them into rubric.md
---

# CASS Pattern Miner

You operationalize the methodology in `references/CASS-MINING.md` so it runs the same way every time. The output is a *project-specific theater patterns* block injected into `rubric.md` AND a `cass_mining/patterns.md` artifact in the audit dir.

## When to invoke

- **Onboarding mode** (the first audit on a new project). Always.
- **Standard mode** if no `cass_mining/patterns.md` exists yet.
- **Comprehensive mode** if `cass_mining/patterns.md` is older than 30 days.
- **Re-verification mode** typically skips this step (fold the existing patterns).

## Inputs

- The project's path and basename.
- `cass` available on the system. If absent, exit 0 with a SKIPPED note (don't block the audit).
- Optional: a list of agent identifiers known to have closed beads on this project (gleaned from `git log --format='%an'` over `.beads/`).

## Output

`<AUDIT_DIR>/cass_mining/patterns.md`:

```markdown
# Project-specific theater patterns mined from /cass

_Project: foo. Mined at: 2026-05-06T14:00:00Z by cass-pattern-miner._

## Pattern P-01 — "tokio::time::sleep used as fake async I/O"

**Anchor quotes** (from cass):
> [Q-cass-1] "let me just sleep here for a bit to simulate the network call" — agent X, session abc, 2026-04-12
> [Q-cass-2] "sleep 100ms here is fine, the real implementation will replace it later" — agent Y, session def, 2026-04-15

**Greppable signature:** `tokio::time::sleep|asyncio.sleep|setTimeout` in non-test files cited by closed beads tagged `network|http|rpc|background`.

**Severity:** BLOCKING for these bead types (default MAJOR).

**Why this matters here:** This codebase had 6 closed beads where the implementation was a sleep-as-fake. The default catalog rates this MAJOR; project history justifies BLOCKING.
```

Then append a `# Project-specific patterns` section to `rubric.md` referencing each P-NN with its severity override.

## Workflow

1. **Probe `cass`.** `cass health` should return 0; otherwise SKIPPED.
2. **Mine queries** (use `--robot --limit 30` for each):
   - `cass search "false closed bead" --robot --limit 30 --days 365`
   - `cass search "I'll implement this later" --robot --limit 30 --days 365`
   - `cass search "stub for now" --robot --limit 30 --days 365`
   - `cass search "TODO before merge" --robot --limit 30 --days 365`
   - `cass search "looks like the test passes" --robot --limit 30 --days 365`
   - `cass search "<project_basename>" --robot --limit 100`
3. **Filter to this project.** Use `--project` flag if `cass` supports it; otherwise grep results for the project path / basename.
4. **Cluster** the matches into pattern-classes (sleep-as-fake, hardcoded-return, mock-where-forbidden, etc.). Use 4+ instances as the threshold for elevation.
5. **For each cluster** with ≥ 4 instances, write a P-NN entry per the format above with at least 2 verbatim anchor quotes.
6. **Severity override.** Default to MAJOR; elevate to BLOCKING if the cluster has ≥ 6 instances OR if any of those instances closed a bead that was later reopened (a clear false-closed signal).
7. **Append to rubric.md** under a `# Project-specific patterns` section. Bump `rubric_sha256` in `manifest.json`.

## Constraints

- **Verbatim quotes only.** Paraphrases lose the vibe; the next auditor needs to recognize the *style*, not just the regex.
- **Two-quote minimum per pattern.** A single quote is anecdote; two are a pattern.
- **Per-project only.** If the same pattern appears in many projects, it belongs in `references/FAILURE-MODES.md`, not the per-project block.

## Common mistakes

- Mining queries that match the audit skill's own session history. Filter strictly by project basename.
- Using AI-generated summaries as anchors. Anchors must be direct quotes from prior sessions — the only thing that survives drift is the verbatim text.
- Letting the patterns block grow unbounded. Cap at 15 patterns per project; rotate stale ones (no hits in last 60 days) out.

## When done

Emit `<PROJECT>: cass_patterns mined={n}, blocking={n}, major={n}` and confirm both `cass_mining/patterns.md` and the rubric.md append exist.
