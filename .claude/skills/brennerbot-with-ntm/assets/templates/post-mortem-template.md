# Post-Mortem Report — <INCIDENT_NAME>

**Incident date:** <ISO>
**Post-mortem date:** <ISO>
**Severity:** SEV-<1|2|3|4>
**Customers affected:** <count> | <impact description>
**Total downtime:** <duration>
**Session ID:** RS-<...>
**Operator:** <name>

---

## Executive summary

<2-3 sentences for executives. What happened, what caused it, what we're doing.>

---

## Timeline

| Time | Event | Source |
|------|-------|--------|
| <ISO> | <event> | <log path / monitoring link> |
| <ISO> | <event> | <log path / monitoring link> |
| ... | ... | ... |

(Reconstructed from logs/monitoring/comms.)

---

## Root cause

<Per incident verdict, refined through Phase 4 investigation. Cite specific
file:line + commit SHA, or specific runbook step that failed, or specific
infrastructure event.>

---

## 5-whys analysis

1. **Why did <surface symptom> happen?**
   <Layer 1 cause; cite EV>
2. **Why did <Layer 1 cause> happen?**
   <Layer 2 cause; cite EV>
3. **Why did <Layer 2 cause> happen?**
   <Layer 3 cause; cite EV>
4. **Why did <Layer 3 cause> happen?**
   <Layer 4 cause; cite EV>
5. **Why did <Layer 4 cause> happen?**
   <Layer 5: typically process / culture / training>

---

## Contributing factors

| Factor | Type | Severity | 5-whys layer | Cited evidence |
|--------|------|----------|--------------|----------------|
| <factor 1> | code | high | L1 | EV-NNN |
| <factor 2> | monitoring gap | medium | L2 | EV-NNN |
| <factor 3> | process | high | L3 | EV-NNN |
| <factor 4> | training | medium | L5 | EV-NNN |

---

## What went well

(Per blameless post-mortem norm: identify what saved us — what would have made the incident worse if it had failed too.)

- <thing 1>
- <thing 2>
- <thing 3>

---

## Action items

| Action | Type | Owner | Deadline | Tracker | Status |
|--------|------|-------|----------|---------|--------|
| <action 1> | code-fix | <team/person> | <ISO> | <ticket link> | open |
| <action 2> | monitoring | <team/person> | <ISO> | <ticket link> | open |
| <action 3> | docs | <team/person> | <ISO> | <ticket link> | open |
| <action 4> | training | <team/person> | <ISO> | <ticket link> | open |

(Each action: SMART — Specific, Measurable, Assigned, Realistic, Time-bound.)

---

## Process improvements

(Higher-level than action items; tied to 5-whys Layer 5.)

| Improvement | Layer | Owner | Tracking |
|-------------|-------|-------|----------|
| <improvement 1> | L4 | <team> | <link> |
| <improvement 2> | L5 | <team> | <link> |

---

## Methodology lessons

(For brennerbot itself — did this post-mortem reveal anything about the methodology?)

- <lesson 1>
- <lesson 2>

(If lessons exist, commit them to references/ per CROSS-SESSION-LEARNING.md.)

---

## Cross-incident pattern detection

| Pattern | Status | First seen | This incident |
|---------|--------|------------|---------------|
| <P-NNN if matched> | <under consideration / in progress / adopted / failed> | <ISO> | matches |

(If new pattern surfaced, add to references/INCIDENT-PATTERN-CATALOG.md.)

---

## Sign-off

- [ ] Engineering lead: <name>
- [ ] Product (if customer-facing): <name>
- [ ] Security (if security-related): <name>
- [ ] SRE / On-call lead: <name>
- [ ] Management: <name>

(Sign-off is not a rubber-stamp. Each signer attests they've read the report and accept the action items.)

---

## Provenance

- Workspace: <path>
- Session ID: <RS-...>
- Roster: <Squad/Pair/etc>
- Wall time: <H>h
- Phase 7 audit: converged at trio-round <N>
- Phase 10 drift verdict: <convergent | divergent-recoverable | divergent-regression>
- Methodology version: <skill commit SHA>

---

## Appendices

- A. Full bead inventory (link to .beads/)
- B. Evidence packs (link to evidence/packs/)
- C. Distillations (link to distillations/)
- D. Disagreement register (link to disagreement_register.md)
- E. Audit findings (link to audit-findings/)
- F. Drift check (link to DRIFT-CHECK.md)

---

## Follow-up review schedule

- 4-week review: <ISO> — Are action items on track?
- 12-week review: <ISO> — Has the incident pattern recurred?
