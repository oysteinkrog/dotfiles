# POST-MORTEM-MODE.md — Incident-Driven Retro Audit

<!-- TOC: When to invoke | The retro flow | Identifying culprit beads | Why-this-failed analysis | Adding new patterns from incidents | Worked example -->

> Production incident happened. The audit goes back and asks: which closed beads were *supposed to prevent this*, and which of them were false-closed?

---

## When to invoke post-mortem mode

After any production incident (outage, data loss, security disclosure, regulatory finding) where the **proximate cause** maps to a bead that was previously closed.

The post-mortem audit answers:

1. Which closed beads should have prevented this incident class?
2. Were any of them false-closed?
3. What missing items in the bead's spec, had they been verified, would have caught the gap?
4. Should the rubric or theater catalog be tightened to prevent recurrence?

---

## The retro flow

### 1. Incident classification

What broke and what bead-class would have prevented it?

| Incident | Likely bead labels |
|----------|-------------------|
| Auth bypass | `security`, `auth`, `rbac` |
| Data corruption | `migration`, `schema`, `data-integrity` |
| Outage from race condition | `concurrency`, `deadlock` |
| Slow request | `perf`, `latency`, `optimization` |
| Email send failure | `notifications`, `email` |
| CSP / XSS / CSRF | `security`, `frontend`, `headers` |

### 2. Bead enumeration

```bash
br --db .beads/*.db list --label=security --status=closed --limit 0 --json \
  | jq '.issues[] | {id, title, closed_at, close_reason}'
```

Filter to beads closed in the last N months (the "incident window").

### 3. Single-bead audits

For each candidate, run a Single-bead-mode audit:

```bash
~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh \
  /data/projects/myproject \
  --mode single-bead --bead-id bd-XYZ \
  --threshold 700 --policy report-only
```

Look at the per-bead scorecard. Compare its missing-items list to the incident's symptoms.

### 4. Why-this-failed analysis

For each bead that scores below threshold:

| Question | Where to look |
|----------|---------------|
| Was a test missing that would have caught it? | `evidence.json#tests.*` MISSING |
| Was a test there but didn't assert behavior? | `theater.json#findings` BLOCKING |
| Was coverage too low? | `test_depth.json` |
| Was the bead's spec too vague to verify? | `spec.json#coverage_gaps` |
| Was the closer pressured (apologetic close)? | `anomaly-scan` flags |

### 5. Add to QUOTE-BANK and FAILURE-MODES

Every incident produces a quote (the bead body, the agent's reasoning, the close reason). Add it to QUOTE-BANK.md as a real-world anchor for the corresponding pattern. If the incident exposes a *new* theater pattern, add it to FAILURE-MODES.md per CONTRIBUTING-PATTERNS.md.

### 6. Tighten the rubric

If the post-mortem reveals that the audit *should have caught* this pre-incident:

- The pattern that would have caught it: tighten its severity (MAJOR → BLOCKING).
- The dimension weight that under-weighted the missing item: adjust per `BEAD-TYPE-WEIGHTS.md`.
- The threshold that was too lenient: raise it.

Bump `rubric_version` per CONTRIBUTING-PATTERNS.md so the change is tracked.

---

## Worked example: CSRF token bypass

**Incident.** 2026-04-15: customer reports CSRF protection bypass on `/api/admin/delete-user`. Investigation: middleware checks the token but the comparison is `==` instead of constant-time, and a timing attack succeeded.

**Step 1 — Classification.** Class: `security`, `csrf`. Window: last 6 months.

**Step 2 — Enumeration.** Found 3 candidate beads:
- `bd-csrf-mw-impl` — "Implement CSRF middleware" — closed 2026-01-10.
- `bd-csrf-test-coverage` — "Add CSRF test coverage" — closed 2026-02-15.
- `bd-admin-route-hardening` — "Harden /api/admin/* routes" — closed 2026-03-01.

**Step 3 — Single-bead audits.**

`bd-csrf-mw-impl` scorecard:
- Score: 850/1000 — passes threshold.
- Phase 5 finding: `// TODO: use constant_time_eq once we add the dep` (severity MINOR).

`bd-csrf-test-coverage` scorecard:
- Score: 920/1000 — passes threshold.
- All tests verify `==` comparison; no test for timing-attack resistance.

`bd-admin-route-hardening` scorecard:
- Score: 780/1000 — passes threshold.
- Cross-references CSRF middleware as upstream; no contract drift detected.

**Step 4 — Why this failed.**
- The CSRF impl bead had a TODO MINOR finding the audit caught but didn't escalate.
- The test bead's tests verify *correctness*, not *security properties* (timing-resistance).
- The hardening bead trusted the upstream — which the audit's cross-bead check accepted because the upstream "passed" its own audit.

**Step 5 — Add to QUOTE-BANK + FAILURE-MODES.**

Add Pattern 31 to FAILURE-MODES.md:
> ## Pattern 31 — Security primitive uses non-constant-time comparison
>
> **Trigger.** `rg -n '==' <auth-files>` on functions that compare secrets / tokens / signatures. Cross-reference: function name contains `verify`, `check`, `validate`, `compare`, AND its caller passes a secret-bearing value.
>
> **Severity.** BLOCKING for security-labeled beads.
>
> **Quote (from QUOTE-BANK.md).** *"Using `==` for now; we'll switch to constant_time_eq once we pull in subtle. Test passes."* (closer's note)

**Step 6 — Tighten rubric.**

In `rubric.md`:
```yaml
project_specific_patterns:
  - name: non_constant_time_secret_compare
    severity: BLOCKING
    files_pattern: "src/auth/**"
    detection: 'rg -n "==" $files | rg -v "(==.+\\bnull\\b|==.+0)"'
    description: "Use constant-time comparison for secret-bearing values"
```

Bump `rubric_version: 1.0.1 → 1.1.0` (minor — new pattern added).

**Step 7 — Re-audit.**

Run the audit. Both `bd-csrf-mw-impl` and `bd-csrf-test-coverage` now score below threshold. Completion-debt beads are created.

The next agent who picks them up implements `constant_time_eq` and adds a timing-attack test. Pass 3 confirms the fix.

---

## Cadence after a post-mortem

A post-mortem audit is a one-shot, but the *learnings* are durable. Going forward:

- The new pattern in FAILURE-MODES.md catches the same class on every future bead.
- The new project-specific rubric tuning catches it specifically on this project.
- The next time tripwire mode runs, the now-tightened rubric flags any new bead that has the same theater.

---

## When NOT to do a post-mortem audit

- Incident is a clear human error / process failure unrelated to bead claims (e.g., someone disabled a CI check manually).
- Incident's cause maps to no closed bead (the work was never planned).
- Incident's bead candidates are all over a year old (the audit can't reach back that far cheaply).

In those cases, the post-mortem audit produces noise. Stick with traditional incident retro.

---

## Output artifact

The post-mortem produces `passes/<UTC>/postmortem_<incident-id>.md`:

```markdown
# Post-mortem audit — Incident <ID>

## Incident summary
- Class: csrf-bypass
- Date: 2026-04-15
- Resolved: 2026-04-16

## Bead candidates
- bd-csrf-mw-impl (score 850 → re-scored 580 with new rubric)
- bd-csrf-test-coverage (score 920 → re-scored 620 with new rubric)
- bd-admin-route-hardening (score 780 → re-scored 720)

## Pattern added to FAILURE-MODES.md
Pattern 31 — Non-constant-time secret comparison

## Rubric tunings
- New project_specific_patterns entry: non_constant_time_secret_compare
- Severity BLOCKING for security-labeled beads
- rubric_version: 1.0.1 → 1.1.0

## Remediation beads created
- bd-csrf-mw-impl.1: implement constant_time_eq + add timing-attack test
- bd-csrf-test-coverage.1: add timing-attack test fixture
```

This artifact is shared with the incident retro doc so the audit's contribution is visible to the team.

---

## Integration with `/security-audit-for-saas`

For security incidents specifically, the post-mortem flow doubles as a `/security-audit-for-saas` re-run scoped to the affected attack class. Cross-reference both skills:

- `/security-audit-for-saas` finds the *attack surface* gaps in current code.
- `beads-compliance-and-completion-verification` post-mortem mode finds the *bead-graph* gaps that should have prevented the incident.

Run both. The intersection is high-value remediation work.