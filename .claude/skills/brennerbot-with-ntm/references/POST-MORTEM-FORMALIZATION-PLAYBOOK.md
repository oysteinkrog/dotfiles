# POST-MORTEM-FORMALIZATION-PLAYBOOK.md — Deeper Companion to Incident-Investigation

<!-- TOC: When to use | Differs from incident mode | The 5-whys integration | Phase-by-phase | Action items + ownership | Process improvement loop | Cross-incident pattern detection | Anti-patterns -->

Mirrors saas-billing's INCIDENT-RESPONSE-PLAYBOOK.md adapted for brennerbot research methodology.

When `incident-investigation` mode (per OPERATING-MODES.md) produces a verdict in <60 min, the *learning* loop hasn't run. `post-mortem-formalization` mode (per EXTENDED-OPERATING-MODES.md) is the deeper companion that runs full Phases 1-10.

This playbook is the discipline for that mode.

---

## When to use

Use post-mortem-formalization mode within 24h of any:

- Customer-impacting production incident (after the immediate fix is deployed)
- Security incident (after containment)
- Methodology incident (e.g., a brennerbot session itself produced wrong recommendations that led to action)
- Process incident (e.g., a release went wrong)

Don't use for:

- Trivial issues with obvious cause (just file a bug, no methodology session needed)
- Issues still in progress (use incident-investigation first; post-mortem after)

---

## How this differs from incident-investigation mode

| Aspect | Incident-investigation | Post-mortem-formalization |
|--------|------------------------|----------------------------|
| Time pressure | high (≤60 min) | none (4-6h) |
| Output | INCIDENT-VERDICT.md | full HANDBACK + DRIFT |
| Scope | root cause | root cause + contributing factors + process improvements |
| Phases run | 1+3+5(with 4 inline)+7 only (compressed) | all 10 |
| Roster | Pair | Squad |
| Formal verification | none | per VERIFICATION-FIRST.md |
| Cross-session learning | flagged but not applied | committed to references/ |

The verdict from incident mode is *operational*; the post-mortem is *learning*. Both are needed.

---

## The 5-whys integration

Per industry standard (Toyota production system + TBM): a post-mortem asks "why" 5 times to reach root cause beyond surface trigger.

Brennerbot integrates this into Phase 1 framing:

### Question of record format

```
## Question
What is the load-bearing root cause of <INCIDENT> beyond the surface trigger
identified in INCIDENT-VERDICT.md, and what process improvements would prevent
recurrence at each contributing factor?

## 5-whys preliminary draft (Phase 1 only)
1. Why did <surface symptom> happen?
   <Layer 1 cause from incident verdict>
2. Why did <Layer 1 cause> happen?
   <Layer 2 cause>
3. Why did <Layer 2 cause> happen?
   <Layer 3 cause>
4. Why did <Layer 3 cause> happen?
   <Layer 4 cause>
5. Why did <Layer 4 cause> happen?
   <Layer 5: usually a process / culture / training issue>

## Falsifier
If exhaustive investigation produces zero contributing factors beyond the
surface trigger, the trigger was an isolated freak event with no systemic
cause (rare).
```

The 5-whys is a *preliminary* draft; Phase 4 investigation may revise.

---

## Phase-by-phase

### Phase 1: Framing
- 5-whys preliminary draft
- Pin incident-verdict (frozen) as a corpus source
- Pin logs / dashboards / metrics from incident window with content-hash
- Falsifier: "exhaustive investigation produces zero systemic contributing factors"

### Phase 2: Bootstrap
- Squad tier
- Investigators assigned domains: incident timeline, monitoring/alerting, code paths, process/communication, customer impact

### Phase 3: Hypotheses
- Each contributing-factor candidate is an H
- Mandatory third-alternative: "the issue was unique and won't recur"

### Phase 4: Investigation
- Investigators dive into their assigned domain
- Devil's-advocate seeks counter-evidence
- Cross-cutting factors (e.g., monitoring gap that contributed to multiple causes) get their own H

### Phase 5: Adjudication
- Each contributing factor adjudicated independently
- Some may be primary (caused the incident), some secondary (made it worse)

### Phase 6: Distillation
- Per-family distillation
- Meta-synthesis catalogs ALL contributing factors
- Disagreement register surfaces methodology disagreements (e.g., "is this a code issue or a process issue?")

### Phase 7: Audit
- Standard fresh-eyes
- Special: did the post-mortem identify ALL contributing factors? Or is there a deeper one Phase 4 missed?

### Phase 8: Freeze
- Standard

### Phase 9: Handback (post-mortem report)
- Format below

### Phase 10: Drift check + cross-incident pattern detection
- Did this incident match a pattern from prior incidents?
- Update CROSS-SESSION-DRIFT-CATALOG with incident-cross-references

---

## Phase 9 form — post-mortem report

`deliverables/POST-MORTEM-REPORT.md`:

```markdown
# Post-Mortem Report — <INCIDENT_NAME>

**Incident date:** <ISO>
**Post-mortem date:** <ISO>
**Severity:** SEV-<1|2|3|4>
**Customers affected:** <count> | <impact description>
**Total downtime:** <duration>

## Executive summary

(2-3 sentences for executives. What happened, what caused it, what we're doing.)

## Timeline

| Time | Event | Source |
|------|-------|--------|
| <ISO> | <event> | <log path / monitoring link> |

(Reconstructed from logs/monitoring/comms.)

## Root cause

(Per incident verdict, refined.)

## 5-whys analysis

1. Why did <surface symptom> happen?
   - <Layer 1>
2. Why did <Layer 1> happen?
   - <Layer 2>
3. Why did <Layer 2> happen?
   - <Layer 3>
4. Why did <Layer 3> happen?
   - <Layer 4>
5. Why did <Layer 4> happen?
   - <Layer 5: typically process or culture>

## Contributing factors

| Factor | Type | Severity | Cited evidence |
|--------|------|----------|----------------|
| <factor 1> | code | high | EV-NNN |
| <factor 2> | monitoring gap | medium | EV-NNN |
| <factor 3> | process | high | EV-NNN |

## What went well

(Per blameless post-mortem norm: identify what saved us.)

- <thing 1>
- <thing 2>

## Action items

| Action | Owner | Deadline | Status | Tracks |
|--------|-------|----------|--------|--------|
| <action 1> | <team/person> | <ISO> | open | <ticket link> |
| ... | ... | ... | ... | ... |

Each action: SMART (specific, measurable, assigned, realistic, time-bound).

## Process improvements

(Higher-level than action items; tied to 5-whys Layer 5.)

- <improvement 1>
- <improvement 2>

## Methodology lessons

(For brennerbot itself — did this post-mortem reveal anything about the methodology?)

- <lesson 1>
- <lesson 2>

## Sign-off

- [ ] Engineering lead
- [ ] Product (if customer-facing)
- [ ] Security (if security-related)
- [ ] Management

## Provenance

- Workspace: <path>
- Session ID: <RS-...>
- Roster: Squad
- Wall time: <H>h
- Phase 7 audit: converged at trio-round <N>
- Phase 10 drift: <verdict>
```

---

## Action items + ownership discipline

Every action item must:

1. Have a single owner (person or team)
2. Have a SMART deadline
3. Have a tracking link (ticket, project board)
4. Be measurable (you can tell when it's done)

Vague items ("improve monitoring") are anti-patterns. Specific items ("add Prometheus alert rule monitoring queue depth >5000 with PagerDuty escalation, by 2026-06-01, owner: SRE") are good.

---

## Process improvement loop

Post-mortem identifies process improvements. Apply them:

1. Document in `deliverables/PROCESS-IMPROVEMENTS.md`
2. Open tracking tickets per improvement
3. Quarterly review: which improvements landed? Which didn't?
4. Update `references/CROSS-SESSION-DRIFT-CATALOG.md` with patterns

If similar incidents recur DESPITE process improvements, the improvements failed. Document and re-engage.

---

## Cross-incident pattern detection

After several post-mortems, patterns emerge. Track in `references/INCIDENT-PATTERN-CATALOG.md`:

```markdown
# Incident Pattern Catalog

## Pattern P-001: Webhook idempotency edge cases

**Incidents matching:** INC-2026-03-14, INC-2026-04-22, INC-2026-05-06
**Common factor:** clock-aligned dedup windows allow brief race
**Prevention:** rolling dedup windows
**Prevention status:** SRE Q3 2026 roadmap

## Pattern P-002: ...
```

When a new incident matches P-001, the post-mortem can leverage prior learning. After 3+ instances of the same pattern, escalate: the prevention strategy isn't working OR isn't being adopted.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip post-mortem for "small" incidents | Patterns emerge from many small incidents; missing data |
| Run post-mortem the same day as incident | Emotion + context-saturation distort analysis; wait 24h |
| Single-pane post-mortem | Multi-perspective is critical for understanding contributing factors |
| Blame-driven post-mortem | Anti-Brenner; methodologically and culturally toxic |
| 5-whys that stops at Layer 1 ("the bug was the cause; fix it") | Doesn't surface systemic factors |
| Action items without owners | Won't get done |
| Action items without deadlines | Won't get prioritized |
| Skip cross-incident pattern check | Repeating same incident wasn't caught |
| Skip Phase 10 drift | Methodology lessons get lost |

---

## Compose with other skills

- /reality-check-for-project — for incidents involving product claims
- /codebase-archaeology — for incidents in unfamiliar code
- /testing-real-service-e2e-no-mocks — for verifying remediations in real environments
- /security-audit-for-saas — for security-related incidents

Per SKILL-COMPOSITION-PATTERNS.md.

---

## Sample timeline

For a typical post-mortem session:

```
Hour 1: Phase 1 + 2 + 3 — frame question, bootstrap, hypotheses
Hour 2-4: Phase 4 — investigation across domains
Hour 5: Phase 5 — adjudication
Hour 5.5: Phase 6 — distillation
Hour 6: Phase 7 — audit
Hour 6.5: Phase 8 + 9 — freeze + post-mortem report
Hour 7: Phase 10 — drift check + pattern detection
```

Total: 6-7 hours wall time. T3 tier defaults.

For SEV-1 incidents, escalate to T4: deeper Phase 4 investigation, mandatory red-team subagent, external review by adjacent team.

---

## When the post-mortem reveals the methodology was wrong

Sometimes a brennerbot session itself produces a recommendation that led to the incident. Two cases:

### Methodology-violation post-mortem

The brennerbot session violated its own methodology (e.g., F-501 — adjudicator never killed; F-403 — no falsifier-firing). The post-mortem must:

1. Identify which methodology violation occurred
2. Update brennerbot references/ to prevent recurrence (per CROSS-SESSION-LEARNING.md)
3. Re-run the original brennerbot session with stricter discipline if the underlying decision is still pending

### Methodology-soundness post-mortem

The brennerbot session followed methodology correctly but the recommendation was wrong (the world surprised us). The post-mortem must:

1. Identify what evidence was missing during the session
2. Add the missing evidence type to CASS-MINING-RECIPES.md
3. Update VERIFICATION-FIRST.md if the missing evidence was time-volatile
4. Accept that even sound methodology has uncertainty

This is humility — the methodology doesn't promise infallibility, just defensibility.
