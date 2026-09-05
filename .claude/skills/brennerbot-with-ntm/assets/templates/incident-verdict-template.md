# Incident Verdict — RS-<YYYYMMDD>-<slug>

**Incident:** <one-paragraph description>
**Investigation duration:** ~<MIN> min
**Verdict timestamp:** <ISO-8601>
**Confidence:** high | medium | low | provisional

---

## Verdict

**Root cause: <H-NNN>: <one-sentence verdict>**

---

## Evidence

### Confirmed via

- **EV-NNN:** <verbatim log line | metric reading> (source: <log path>:line<N> | <dashboard URL>)
- **EV-NNN:** <verbatim>
- **EV-NNN:** <verbatim>

### Killed alternatives

- **H-NNN** (<claim>) — refuted by **EV-NNN** (verbatim: "<quote>")
- **H-NNN** (<claim>) — refuted by **EV-NNN** (verbatim: "<quote>")

(All hypotheses considered should appear here, either confirmed or refuted; deferred only for genuinely unresolvable.)

---

## Causal chain

1. **Trigger** (<timestamp>): <what initiated>. Cited: EV-NNN.
2. **Propagation:** <how the trigger became impact>. Cited: EV-NNN.
3. **Customer impact** (<timestamp range>): <what users / systems experienced>. Cited: EV-NNN.

---

## Recommended remediation

### Immediate (within 1h)

| Action | Owner | Status |
|--------|-------|--------|
| <action> | <team / person> | pending \| in-progress \| done |

### Short-term (within 24h)

| Action | Owner | Deadline |
|--------|-------|----------|
| <action> | <team> | <ISO> |

### Long-term (post-mortem)

| Action | Owner | Deadline |
|--------|-------|----------|
| <process improvement> | <team> | post-mortem session |
| <monitoring gap fix> | <team> | post-mortem session |

---

## Open questions deferred to post-mortem

(Anything unresolved that doesn't block immediate action.)

- <question 1>
- <question 2>
- <question 3>

---

## Anomalies observed (deferred to post-mortem)

(Per ΔE Exception-Quarantine — anomalies that emerged during investigation but weren't part of the verdict.)

- AN-NNN: <observation>
- AN-NNN: <observation>

---

## Confidence assessment

- **Verdict confidence:** high | medium | low | provisional
- **Reasoning:**
  - Multiple independent EVs: <yes | no>
  - Falsifier probed: <yes | no | partial>
  - Investigation duration: <minutes>
  - Devil's-advocate counter-evidence: <found | not found | not searched>

If confidence is low/provisional, recommend follow-up incident-investigation session within <hours>.

---

## Methodology

Produced by brennerbot incident-investigation mode (compressed Phase 1 + Phase 3 + Phase 5 with inline investigation + Phase 7) in ~<MIN> min.
- Roster: Pair (cc + cod) | Squad if escalated
- Operator algebra applied: ⌂ Materialize, ✂ Exclusion-Test, 🤝 GAN compressed, † Theory-Kill
- Operators NOT applied (deferred to post-mortem): ⊞ Scale-Check (full), ⊘ Level-Split, ≡ Invariant-Extract, ∿ Dephase

---

## Recommended next session

**Post-mortem-formalization mode** (full Phases 1-10) within 24h:

- **Question of record:** "What contributing factors led to <INCIDENT>, and what process improvements prevent recurrence?"
- **Expected wall time:** 4-6h
- **Roster:** Squad
- **Pre-registration recommended:** yes (lock falsifier before reading post-incident chatter that could anchor)

---

## Operator + on-call sign-off

- [ ] Verdict reviewed by operator
- [ ] Verdict reviewed by on-call lead
- [ ] Immediate remediation in flight or scheduled
- [ ] Customer communication initiated (if customer-impacting)
- [ ] Post-mortem scheduled

**Operator:** <name> | **Time:** <ISO>
**On-call:** <name> | **Time:** <ISO>

---

## Provenance

- **Workspace:** <path>
- **Session ID:** <RS-...>
- **Investigation start:** <ISO>
- **Verdict timestamp:** <ISO>
- **Total wall time:** <minutes>
- **Beads filed:** <count>
- **Evidence packs:** <count>
