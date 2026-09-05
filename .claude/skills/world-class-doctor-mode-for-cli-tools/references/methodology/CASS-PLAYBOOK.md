# CASS Playbook — Specific Mining Recipes

The 13 canned queries in [PHASES.md § Phase 0](PHASES.md) are the baseline. This file goes deeper: query recipes for specific situations, with the rationale for *why* each query matters and what to look for in the results.

Use as a reference when running cass-miner during Phase 0 of any pass, or quarterly per [OPS-RUNBOOK.md](OPS-RUNBOOK.md).

---

## Recipe 1 — "Find every `<tool> X` failure my agents complained about"

```bash
cass search "<tool>" --robot --limit 50 --days 90 \
    --kind error,frustration,manual_fix
```

**Why it matters:** the broadest sweep. If a recurring symptom appears here, it's a candidate FM regardless of subsystem.

**What to look for:**
- Repetition of the same string across multiple sessions. If "I had to manually fix `<tool> X`" appears in 5+ sessions, it's a P1+ FM.
- Recent surges. If 80% of complaints are from the past 7 days, something just regressed in the project.
- Severity drift. Compare against the prior 90-day window; emerging severity patterns are early warning.

**Translate to FMs:** any string of the form "had to {verb} {state}" where `{verb}` is a manual repair (delete, recreate, reset, edit by hand) becomes a candidate FM. The detection is the symptom; the remediation is the manual fix.

---

## Recipe 2 — "Find sessions where my agent gave up and asked me for help"

```bash
cass search "I'm stuck" "I cannot proceed" "asking for help" \
    --robot --limit 30 --days 90
```

**Why it matters:** the most expensive failure mode is *agent escalation* — when the agent runs out of tools and asks the user. Every escalation is friction; the doctor should turn many of them into auto-resolutions.

**What to look for:**
- Patterns where the agent escalated for something the doctor *should* handle (corrupt state, stale lock, schema mismatch).
- Patterns where the agent escalated correctly (genuine human-decision point — credentials, intent ambiguity).

**Translate:** the first class becomes new auto-fixable FMs. The second class becomes `manual_remediations` entries that surface the question more cleanly.

---

## Recipe 3 — "Mine for race-condition incidents"

```bash
cass search "race condition" "TOCTOU" "concurrent" "deadlock" "lock contention" \
    "another process" "PID" "stale lock" \
    --robot --limit 40 --days 180
```

**Why it matters:** races are subtle, often diagnosed only post-mortem. The doctor's concurrency primitives (Axiom 6) are designed against this class.

**What to look for:**
- Specific scenarios that hit a race window in the project. Each becomes a fixture in `tests/doctor_fixtures/race/`.
- Lock-related quotes. They often map directly to the `concurrency_primitives` subsystem.

---

## Recipe 4 — "Find sessions where the user manually edited a config"

```bash
cass search "edit ~/.config" "vim ~/.zshrc" "edit the config" \
    "manually update" "had to change" --robot --limit 30
```

**Why it matters:** every manual config edit is a missed automation opportunity. Some are correct (intent-bearing); others are routine (drift, schema change).

**What to look for:**
- Same edit happens in 3+ sessions → it's mechanical → automate it.
- Different edits each time → it's intent-bearing → list as manual_remediation; don't automate.

---

## Recipe 5 — "Find sessions where the agent ran a destructive command"

```bash
cass search "rm -rf" "git reset --hard" "DROP TABLE" "kubectl delete" \
    --robot --limit 30 --days 365
```

**Why it matters:** AGENTS.md forbids these. If the agent invoked them anyway, the doctor's negative-space spec didn't prevent it. Each instance is a FM the doctor should handle gracefully (refuse with redirect, per Axiom 22).

**What to look for:**
- Cases where the user typed it (not the agent). Those are user-driven, not skill defects.
- Cases where the agent invoked it. Those are training-data inheritance the doctor's exit-4 surface should redirect.

---

## Recipe 6 — "Find sessions where state was lost"

```bash
cass search "lost data" "lost issues" "lost work" "lost commits" \
    "had to redo" "had to recreate" --robot --limit 30 --days 365
```

**Why it matters:** data loss is the worst-case outcome. Every quote here is a P0 case study candidate.

**What to look for:**
- Was the loss preventable with backups (Axiom 2)? → fixture for the doctor.
- Was it an irreversible mutation outside doctor scope? → cookbook addition or operating-modes refinement.

---

## Recipe 7 — "Find sessions where the agent waited > 5 minutes for something to load"

```bash
cass search "still loading" "took forever" "slow" "timed out" "5 minutes" \
    "running for hours" --robot --limit 40 --days 90
```

**Why it matters:** doctor performance budget (per [PERFORMANCE.md](PERFORMANCE.md)). If an agent waited > 5 minutes for ANY operation, the doctor's `health` budget (< 200ms) doesn't cover it.

**What to look for:**
- Slow operations the doctor could detect early (e.g., a wedged lock, a runaway process).
- Slow operations the doctor's performance metrics should track.

---

## Recipe 8 — "Find sessions where the agent worked around a known issue"

```bash
cass search "workaround" "bypass" "as a workaround" "work around" "skip the" \
    --robot --limit 30 --days 90
```

**Why it matters:** workarounds are deferred FM detection. Each workaround is a FM the doctor SHOULD have caught.

**What to look for:**
- Workarounds that recur. They've graduated from "occasional" to "systemic" — the doctor must absorb them.

---

## Recipe 9 — "Find sessions where the user said 'why does X happen'"

```bash
cass search "why does this happen" "why is this" "what causes" \
    "where does X come from" --robot --limit 30 --days 90
```

**Why it matters:** unexplained state is a doctor's responsibility to clarify. The doctor's `--explain` subcommand is the answer.

**What to look for:**
- Repeated "why" questions about the same project state → the doctor's findings should preempt them.
- One-off "why" questions → the doctor's `<tool> doctor explain <id>` should answer when invoked.

---

## Recipe 10 — "Find sessions where the user upgraded `<tool>` and broke things"

```bash
cass search "upgraded" "after upgrade" "since the upgrade" "version bump" \
    "v0.X to v0.Y" --robot --limit 30 --days 365
```

**Why it matters:** version-skew FMs (per [VERSIONING.md](VERSIONING.md)) are systemic.

**What to look for:**
- Specific version transitions cited as breaking. Each is a P0 FM for the doctor to detect.
- Migration steps the user did manually → absorb into Pattern 5 (installer) recovery.

---

## Recipe 11 — "Find sessions where the agent used a different tool to fix `<tool>`"

```bash
cass search "manually with sqlite3" "manually with jq" "manually with sed" \
    "by hand with" "I used X to fix Y" --robot --limit 30
```

**Why it matters:** when the user reaches for `sqlite3` or `jq` to repair `<tool>`'s state, the doctor should have done it. Each instance is a clear absorb-playbook target.

**What to look for:**
- The exact `sqlite3` queries / `jq` filters used. They're literal repair recipes — the doctor's fixer is a programmatic version.

---

## Recipe 12 — "Find sessions where the user said 'just trust me on this'"

```bash
cass search "just trust me" "I know what I'm doing" "override" \
    "force" "yes I really mean it" --robot --limit 30
```

**Why it matters:** these are `--force --yes` situations. The doctor's force path needs to handle them per [OPERATORS.md § 🚧 Refuse-As-Feature](OPERATORS.md).

**What to look for:**
- Cases where the user genuinely needs the override (a real intent-bearing situation).
- Cases where the user is just frustrated and the doctor should DOUBLE-DOWN on refusing.

---

## Recipe 13 — Quarterly trend mining

```bash
# Compare last quarter vs. quarter-before-that
last_q=$(cass search "<tool>" --days 90 --robot | jq '.hits | length')
prev_q=$(cass search "<tool>" --days 180 --robot \
    | jq '[.hits[] | select(.created_at < (now - 90*86400))] | length')
echo "Last quarter: $last_q hits; Previous quarter: $prev_q hits"
```

If the count grew, the doctor's coverage is lagging. If it shrank, the prior pass's fixers are working.

Combine with finding-rate from `.doctor/scorecard_history.jsonl` (per [METRICS.md](METRICS.md)) to cross-validate: doctor finding-rate UP + cass complaint-rate UP = doctor catching more, possibly because there's more breakage. Doctor finding-rate UP + cass complaint-rate DOWN = doctor catching the breakage upstream of user notice (good).

---

## Recipe 14 — Per-pattern mining

For each cookbook pattern the project matches, mine the canonical phrases:

| Pattern | Mining phrases |
|---------|----------------|
| 1 (state-owning) | "lost data", "corrupt state", "had to delete .X" |
| 2 (multi-binary) | "version skew", "binaries out of sync" |
| 3 (config-only) | "config malformed", "config drift" |
| 4 (daemon) | "wedged", "EADDRINUSE", "stale pid" |
| 5 (installer) | "broken install", "had to reinstall" |
| 6 (TUI-first) | "tui hangs", "rendering broken" |
| 7 (AI-agent) | "agent stuck", "session corrupt", "credentials expired" |
| 8 (third-party) | "wrapper failed", "upstream changed" |
| 9 (distributed) | "vendor 5xx", "auth invalid", "rate limit" |
| 10 (absorb) | "manual playbook", "had to follow steps" |
| 11 (installer-bootstrap) | "curl pipe bash", "signature failed" |
| 12 (meta-doctor) | "skill broken", "doctor itself" |
| 13 (forensic) | "audit", "compliance", "what changed" |
| 14 (build-system) | "lockfile", "cache corrupt", "phantom dep" |
| 15 (compliance) | "audit log gap", "PII", "retention" |

When applying the skill, mine for the patterns that match the project's shape. The other patterns' mining is wasted.

---

## What CASS won't tell you

- **Future FMs.** Cass surfaces what's already happened. Phase 1 archaeology must also reason from first principles about FMs that COULD happen even if they haven't yet.
- **Cross-tool failures.** If the FM only fires when `<tool>` interacts with another tool, cass may not see it (the user blames whichever tool was active).
- **Latent failures.** A FM that's been silently corrupting for months without user notice. Cass won't see it — but a fresh-eyes audit might.

These gaps are why Phase 1 has multiple inputs (cass + bug tracker + git log + AGENTS.md + first principles) — no single source is complete.
