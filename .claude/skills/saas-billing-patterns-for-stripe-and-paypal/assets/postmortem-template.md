# Postmortem: <short-name>

> **Template.** Copy to `<project>/docs/postmortems/<YYYY-MM-DD>-<short-name>.md`. Fill in. Commit within 1 week of incident.

## Summary
- **Detected:** <YYYY-MM-DD HH:MM UTC> via <source>
- **Contained:** <YYYY-MM-DD HH:MM UTC> by <action>
- **Resolved:** <YYYY-MM-DD HH:MM UTC> by <commit hash>
- **Severity:** <P0 | P1 | P2 | P3>
- **Customer impact:** <count of users affected; $$ refunds issued; trust impact>
- **Failure-mode class:** <e.g., Triple-charge (`bd-1m86f`); references/patterns/110-OPERATIONS.md § 72>

## What happened (timeline)
- **T0 (provider clock):** <yyyy-mm-dd hh:mm UTC> — <first occurrence>
- **T1:** <yyyy-mm-dd hh:mm UTC> — <first customer-affected occurrence>
- **T2:** <yyyy-mm-dd hh:mm UTC> — <first internal detection>
- **T3:** <yyyy-mm-dd hh:mm UTC> — <first response action>
- **T4:** <yyyy-mm-dd hh:mm UTC> — <bleeding stopped>
- **T5:** <yyyy-mm-dd hh:mm UTC> — <fix deployed>
- **T6:** <yyyy-mm-dd hh:mm UTC> — <verification: no recurrence in 24h>

## What we expected
[The intended behavior. Cite the pattern bundle / Polish Bar dimension that was supposed to enforce this. Quote from references/patterns/...]

## Root cause (5 whys)
1. (proximate code) ...
2. (architectural) ...
3. (process) ...
4. (detection) ...
5. (institutional) ...

[Stop at the level where the answer is "we made an explicit choice."]

## Fix
- **Commit:** <sha> — <commit message>
- **Files touched:** <list>
- **Pattern bundle updated:** <e.g., references/patterns/40-WEBHOOKS.md § XYZ>
- **Regression test:** <test name, e.g., __tests__/incidents/incident-2026-05-04-triple-charge.test.ts>
- **Drift-guard added:** <test name | n/a>

## What we'll detect next time
- **New alarm:** <name + condition + paging policy>
- **New runbook:** <docs/runbooks/<name>.md>
- **Updated runbook:** <docs/runbooks/<name>.md sections changed>

## Customer communication
- [Did we proactively notify? When? Via what channel?]
- [Did we issue refunds? On what timeline?]
- [Public communication if any? Status page update?]

## Action items
- [ ] <item> — owner: <name> — due: <YYYY-MM-DD>
- [ ] <item> — owner: <name> — due: <YYYY-MM-DD>

## Lessons learned (1-3 sentences for the team)
[Specific, action-oriented. NOT "we should be more careful." Use blameless framing — name the system that allowed the mistake, not the engineer who made it.]

## Cross-references
- Source guide § <NN>: <quote>
- Bead/issue: <id>
- Related postmortems: <list>
- Related Phase 7 fresh-eyes findings: <list>
