# Operating Modes

Pick a mode first; the phase loop is the same but the **stop conditions, required artifacts, and which phases run** differ. Most run-time mistakes come from picking `audit-only` when the user actually needs `audit-and-fix`, or running `greenfield` when there's already a half-built schema in `migrations/` that should be respected.

---

## How to pick

```
Is there ANY billing code in the repo?
├─ NO  → greenfield
└─ YES
   │
   Did a real production billing incident happen in the last 14 days?
   ├─ YES → harden-incident
   └─ NO
      │
      Is the user asking for ONE bounded billing capability?
      ├─ YES → add-feature  (teams, dunning, MRR, refund workflow, etc.)
      └─ NO
         │
         Is there an existing provider that we're switching from / adding a second to?
         ├─ YES → migration
         └─ NO
            │
            Is there a pending compliance review (SOC2, ISO, annual audit)?
            ├─ YES → compliance-pass
            └─ NO
               │
               Does the user want changes shipped, or only a report?
               ├─ Report → audit-only
               └─ Ship  → audit-and-fix   ← default
```

`scripts/discover-stack.sh` runs this tree automatically and proposes a mode. The user can override at the Up-Front Confirmations step.

---

## Mode definitions

### `audit-only`

| Field | Value |
|-------|-------|
| **When** | The user wants an honest assessment without code changes (often a stakeholder ask, a procurement security review, or a "is this safe to scale?" question). |
| **Phases run** | 1, 2, 3 only. NO Phase 4+. |
| **Required artifacts** | `phase1_archaeology.md` per bundle, `phase2_coverage_matrix.md`, `phase3_risk_scored_gaps.md`, `phase3_executive_summary.md` (≤2 pages, written for a non-engineer). |
| **Stop condition** | `phase3_executive_summary.md` is committed to `.billing_workspace/` and reviewed by the user. |
| **Forbidden** | Any `Edit`/`Write` outside `.billing_workspace/`. Any `git commit` on source files. Any provider API call other than read-only catalog audits. |

### `audit-and-fix`

| Field | Value |
|-------|-------|
| **When** | Default. The user wants gaps closed and is OK with a multi-PR program of work. |
| **Phases run** | All 10. |
| **Required artifacts** | All `audit-only` artifacts + `phase4_implementation_plan.md` + per-bundle implementation diff + drift-guard tests + integration tests + runbooks. |
| **Stop condition** | Phase 7 fresh-eyes runs ≥2 times clean (only trivial edits) AND Phase 8 integration tests green AND Phase 9 staging drills green AND Phase 10 runbooks committed. |
| **Cadence** | Default to one PR per bundle (B10 schema → B40 webhooks → ...). Never bundle "schema change + 200 lines of handler logic" into one PR — unreviewable. |

### `harden-incident`

| Field | Value |
|-------|-------|
| **When** | A real incident JUST happened (duplicate charge, hijacked subscription, leaked secret, dunning email storm, etc.). The user is paged or postmortem-driven. |
| **Phases run** | 1 (scoped to incident blast radius) → 4 (RCA-driven plan) → 5 (scoped fix) → 7 (fresh-eyes) → 8 (regression test) → 9 (drill the exact incident) → 10 (postmortem runbook). Then expand to `audit-and-fix` for the bundles touched. |
| **Required artifacts** | All of the above + `phaseX_postmortem.md` formatted as: *what happened, what we expected, root cause (5 whys), fix, regression test name, what we'll detect next time, who was paged when, customer impact.* |
| **Stop condition** | Postmortem committed AND the incident's exact reproduction case is now a green test in CI AND a production-ready alarm is wired for the failure mode. |
| **Important** | Do NOT skip Phase 7 fresh-eyes under time pressure. Incident-pressure code is the most likely to introduce new bugs. |

### `add-feature`

| Field | Value |
|-------|-------|
| **When** | One bounded capability. Scope examples: "add team plans," "add a dunning ladder," "add MRR card to admin," "add manual invoice retry," "add SCA routing." |
| **Phases run** | 1 (only the bundles the new feature crosses) → 4 (scoped) → 5 → 6 (cross-cutting harmonization for the touched tables/crons) → 7 → 8 (only the touched test surfaces). Phase 9 only if the feature changes the webhook handler set. |
| **Required artifacts** | `phase1_archaeology_for_<feature>.md`, `phase4_plan_for_<feature>.md`, per-bundle implementation, regression tests pinned to the feature's bead/issue. |
| **Stop condition** | All Polish-Bar dimensions for the touched bundles are green AND the feature has a ≥1 happy-path integration test AND ≥1 adversarial test (replay, hijack attempt, race, etc.). |

#### Blast-radius escalator

Keep `add-feature` as `add-feature` when the request is one capability and the touched bundles are explicit in `phase0_scope_decision.md`.

Escalate only the affected bundles to `audit-and-fix` depth when the feature:

- adds or changes shared schema primitives used outside the feature;
- adds, removes, or changes webhook event handlers;
- introduces a cron, reconciliation path, provider catalog dependency, or async side-effect queue;
- changes entitlement ownership, team/org state, or cross-provider duplicate-subscription behavior;
- reveals incident evidence, live provider drift, or missing idempotency/staleness guards in existing code.

Do not turn a narrow feature request into a full audit because an optional reference file exists. If escalation happens, update `phase0_scope_decision.md` with the trigger and leave unrelated bundles `n/a`.

### `greenfield`

| Field | Value |
|-------|-------|
| **When** | No `payment_events`, no `subscriptions`, no Stripe / PayPal SDK imports. |
| **Phases run** | 4 (using the step-ordered build from `references/patterns/110-OPERATIONS.md` § Battle-tested-checklist) → 5 → 6 → 7 → 8 → 9 → 10. Skip 1/2/3 (no existing code to inventory). |
| **Required artifacts** | All `audit-and-fix` artifacts EXCEPT the coverage matrix is replaced by `phase2_greenfield_dependency_graph.md` (which step depends on which earlier step). |
| **Stop condition** | All 12 steps from the checklist are green AND all Phase 7/8/9/10 gates pass. |
| **Important** | The build order is NOT optional. Many later steps literally won't compile without earlier steps (intent table needs `paused_for_org`; team coverage suppression needs the projection function; verify-as-write needs the stale-checkout race guard; etc.). Resist the temptation to "add MRR first because it's most visible to leadership" — you'll have to undo it later. |

### `migration`

| Field | Value |
|-------|-------|
| **When** | Switching from a single billing provider (Lemon Squeezy, Paddle, Chargebee, Recurly, hand-rolled) to dual Stripe + PayPal, OR adding a second provider to an existing single-provider system. |
| **Phases run** | 1 (both old + new providers) → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → **9.5 cutover sub-phase** → 10. |
| **Required artifacts** | All `audit-and-fix` + `phaseX_provider_mapping.md` (event → handler equivalences) + `phase9_5_cutover_runbook.md` (exact sequence, who signs off, how to roll back) + `phase9_5_dual_run_window_plan.md` (overlap period during which both old and new providers are recording subscriptions). |
| **Stop condition** | All `audit-and-fix` gates + cutover dry-run successful in staging AND rollback tested AND a live customer's first payment landed cleanly through the new provider. |
| **Important** | Plan a real **dual-run window** — at least 2 weeks where new sign-ups go to the new provider AND existing subs continue on the old. Don't try a flag-flip cutover for a paying-customer SaaS. |

### `compliance-pass`

| Field | Value |
|-------|-------|
| **When** | SOC2 Type 2, ISO 27001, annual security review, customer-driven security questionnaire. The auditor needs evidence, not new features. |
| **Phases run** | 1 (compliance-relevant subset) → 2 (compliance subset of patterns) → 3 → 4 → 5 (only audit-trail / logging / secret / RLS gaps) → 6 → 7 → audit-trail-only sub-phase → 10. |
| **Required artifacts** | `phaseX_compliance_evidence_pack/` containing: secret-custody matrix, rotation log, RLS policy audit, rate-limiter coverage proof, security-event taxonomy completeness check, log-tampering audit, integrity-audit cron output proof, drift-guard test list, and a per-control mapping (SOC2 / ISO control → evidence file). |
| **Stop condition** | The evidence pack is complete enough that an auditor can verify each control without reading source code. |
| **Forbidden** | New features. New schema columns. Anything that would force a freshly-written control to be re-audited. |

Compliance-pass can file follow-up work, but it should not solve that work inline unless the missing control itself is the audit target. Keep evidence collection and feature delivery as separate modes so the auditor has a stable system to inspect.

---

## Mode-to-phase coverage matrix

| Phase | audit-only | audit-and-fix | harden-incident | add-feature | greenfield | migration | compliance-pass |
|-------|------------|---------------|-----------------|-------------|------------|-----------|-----------------|
| 1 Archaeology | ✓ | ✓ | scoped | scoped | — | ✓ (×2) | scoped |
| 2 Coverage | ✓ | ✓ | scoped | — | replaced | ✓ | scoped |
| 3 Risk | ✓ | ✓ | scoped | — | — | ✓ | ✓ |
| 4 Plan | — | ✓ | RCA-driven | scoped | ✓ | ✓ | ✓ (audit-trail only) |
| 5 Implement | — | ✓ | scoped | ✓ | ✓ | ✓ | ✓ (audit-trail only) |
| 6 Harmonize | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 7 Fresh-eyes | — | ✓ (×2 clean) | ✓ | ✓ | ✓ | ✓ | ✓ |
| 8 Real-DB tests | — | ✓ | ✓ (regression) | ✓ (touched) | ✓ | ✓ | read-only |
| 9 Staging drill | — | ✓ | ✓ (drill incident) | conditional | ✓ | ✓ + **9.5 cutover** | — |
| 10 Ops handoff | — | ✓ | ✓ (postmortem) | conditional | ✓ | ✓ | ✓ (evidence pack) |

`scoped` = run only on the bundles in the incident / feature blast radius.
`replaced` = the artifact is replaced by a mode-specific equivalent.
`—` = phase does not run in this mode.

---

## Common confusions

- **"audit-only" is not a draft of "audit-and-fix."** They have different output shapes. `audit-only` produces a *report*; `audit-and-fix` produces a *program of work*. Don't promise an executive summary if you're going to ship code, and don't ship code if you promised only a report.
- **"add-feature" is not "audit a tiny slice."** If the feature touches the webhook handler set, the schema, or any cron, you've crossed into `audit-and-fix` territory for those bundles. Be honest about this with the user upfront.
- **"greenfield" still needs Phase 7 fresh-eyes.** New code is not "obviously correct" code. The most common greenfield bug is forgetting `WHERE last_event_at < new_event_at` on the very first UPDATE.
- **"compliance-pass" forbids new features intentionally.** Auditors need a stable target. If you discover a real bug during a compliance pass, file it for the next `audit-and-fix` cycle and document it in the evidence pack as a known issue.

---

## Mode handoff template

When you finish a mode and the user asks "what next," use this template:

```
You ran <mode> on <project>. Status: <complete | partial>.

What's done:
- <bullet per phase, what artifact landed>

What's open:
- <each gap with bead/issue ID, severity, and which mode would close it>

Recommended next mode: <mode-name>
Why: <one paragraph>
Estimated scope: <day-equivalents>
Gates that would block:  <e.g. "no Stripe sandbox creds yet — need from user">
```

This keeps users from accidentally re-running the same mode hoping for different output, and from skipping straight to `compliance-pass` when there's still a B40 webhook gap that the auditor will catch.
