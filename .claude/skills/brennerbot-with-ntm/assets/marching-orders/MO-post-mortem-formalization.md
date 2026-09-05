# MO-post-mortem-formalization.md — Deep Post-Mortem (Companion to Incident-Investigation)

**Mode:** post-mortem-formalization (per EXTENDED-OPERATING-MODES.md)
**Phase:** all (1-10)
**Wall time:** 4-6h (T2-T3 typical)
**Parameters:** `<INCIDENT_VERDICT_PATH>` (path to deliverables/INCIDENT-VERDICT.md from prior incident-investigation), `<SESSION_ID>`

---

You are the operator running a post-mortem-formalization mode session. The incident has been triaged via incident-investigation mode (≤60 min); this session formalizes learning over 4-6 hours.

Per POST-MORTEM-FORMALIZATION-PLAYBOOK.md.

---

**Step 1 — Verify prior incident verdict exists.**

```bash
test -f "<INCIDENT_VERDICT_PATH>" || { echo "Run incident-investigation mode first"; exit 1; }
```

The incident verdict is the *operational* verdict; this session is the *learning* loop.

**Step 2 — Phase 1 framing.**

Question of record:

```markdown
## Question
What is the load-bearing root cause of the incident summarized in
`<INCIDENT_VERDICT_PATH>` beyond the surface trigger, and what process improvements would prevent
recurrence at each contributing factor?

## Falsifier
If exhaustive investigation across timeline, monitoring, code, process, and
communication produces zero contributing factors beyond the surface trigger,
the incident was an isolated freak event with no systemic cause.

## Scope
- Contributing factors at each layer (code / process / monitoring / culture)
- Process improvements per layer
- Cross-incident pattern detection (does this match prior incidents?)

## Out of Scope
- Customer compensation (separate workstream)
- Press / external comms (separate workstream)
- Personnel decisions (separate, blameless post-mortem)

## Mode
post-mortem-formalization

## 5-whys preliminary
1. Why did <surface symptom>? <Layer 1 from incident verdict>
2. Why did <Layer 1>? <Layer 2 hypothesis>
3. Why did <Layer 2>? <Layer 3 hypothesis>
4. Why did <Layer 3>? <Layer 4 hypothesis>
5. Why did <Layer 4>? <Layer 5: typically process / culture>
```

The 5-whys is preliminary; Phase 4 may revise.

Pin incident logs / dashboards / timeline as corpus sources S-001 onward.

**Step 3 — Phase 2 bootstrap.**

Squad tier (cc:3 + cod:1 + gmi:1).

Domain assignments per investigator:

- Investigator-1 (cc): incident timeline reconstruction
- Investigator-2 (cod): monitoring / alerting gaps
- Investigator-3 (gmi): code paths involved
- Devil's-Advocate: process / communication failures
- Synthesizer + Adjudicator (rotating): cross-domain coordination

Productive-ignorance pane: optional but useful — re-asks "why didn't we catch this earlier?" from naïve perspective.

**Step 4 — Phase 3 hypotheses.**

Each contributing-factor candidate is an H. Mandatory ≥3 Hs including third-alternative ("the issue was unique and won't recur" — must be tested).

Sample Hs:

- H-001: code-path bug at file:line was the load-bearing factor
- H-002: monitoring gap allowed the issue to escalate
- H-003 (third-alternative): the deployed system was correct; environmental factor caused incident
- H-004: process gap prevented early detection
- H-005: communication delay extended impact

**Step 5 — Phase 4 investigation.**

Per MO-04a-investigate.md per H. Specifically for post-mortems:

- Cite incident logs verbatim
- Cite specific code paths (file:line + commit SHA)
- Cite process documents / runbooks
- Cite communication channels (slack thread links, etc)

Quickie pilots highly valuable here — many H can be quickly tested against logs.

**Step 6 — Phase 5 adjudication.**

Each H independently adjudicated. Some may be primary (caused incident); some secondary (made it worse). The 5-whys layer at which each contributing factor sits matters.

**Step 7 — Phase 6 distillation.**

Catalog ALL contributing factors. Disagreement register may surface:

- "Is this code issue or process issue?" (could be both)
- "How significant was the monitoring gap?"
- "Was the customer impact mitigated by what factor?"

**Step 8 — Phase 7 audit.**

Standard fresh-eyes trio. Plus:

- Did the post-mortem identify ALL contributing factors? Phase 4 reopen if missed.
- Are action items SMART (specific, measurable, assigned, realistic, time-bound)?
- Are process improvements tied to specific 5-whys layers?

**Step 9 — Phase 8 freeze.**

Standard. Plus update CROSS-SESSION-DRIFT-CATALOG.md with cross-incident patterns:

```markdown
## Pattern P-NNN

**Incidents matching:** INC-..., INC-..., INC-...
**Common factor:** <one-line>
**Prevention strategy:** <one-line>
**Status:** <under consideration | in progress | adopted | failed>
```

**Step 10 — Phase 9 handback (post-mortem report).**

Use `assets/templates/post-mortem-template.md`. Save to `deliverables/POST-MORTEM-REPORT.md`.

Mandatory sections:

- Executive summary (2-3 sentences)
- Timeline
- Root cause
- 5-whys analysis
- Contributing factors table (with severity + cited evidence)
- What went well (blameless culture)
- Action items table (SMART)
- Process improvements
- Methodology lessons (for brennerbot)
- Sign-off section

**Step 11 — Phase 10 drift + cross-incident pattern detection.**

Standard drift check. Plus:

- Did this incident match a pattern from INCIDENT-PATTERN-CATALOG.md?
- If yes: update the pattern's "incidents matching" list
- If new pattern: add P-NNN entry
- If pattern's prevention is failing: escalate

**Step 12 — Action item commitment.**

Each action item gets a tracking ticket (whatever your org uses). Owner + deadline non-negotiable.

Schedule a follow-up review (4-6 weeks): which action items landed? Which didn't? Pattern emerges across post-mortems.

---

**Anti-patterns:**

- ✗ Run post-mortem same day as incident (emotion + context-saturation)
- ✗ Skip the 5-whys (stops at surface trigger)
- ✗ Action items without owners (won't get done)
- ✗ Skip cross-incident pattern check (fail to learn)
- ✗ Blame-driven post-mortem (anti-Brenner; toxic)
- ✗ Post-mortem solo (multi-perspective is critical)

**Ship-or-Surface SLA:** within 4-6h wall time, post-mortem complete + report committed + action items tracked.
