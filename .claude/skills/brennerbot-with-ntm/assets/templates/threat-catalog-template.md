# Threat Catalog — RS-<YYYYMMDD>-<slug>

**Audit date:** <YYYY-MM-DD>
**Subject:** <one-line: what was audited>
**Audit duration:** <H>h
**Roster:** <Squad with 2 Devil's-Advocates | Swarm with red-team subagent>

---

## Methodology

Adversarial design audit per QUESTION-ARCHETYPES.md A6.

Operators applied:
- ✂ Exclusion-Test (forbidden patterns)
- ⊞ Scale-Check (adversary scale exploitation)
- ΔE Exception-Quarantine (anomaly-driven attacks)
- ⊕ Cross-Domain (importing known attack patterns)

Devil's-Advocate panes + (T4+) red-team subagent (per `subagents/red-team.md`) enumerated threats. Each threat has: attack class, precondition, evidence-to-confirm, severity, recommended remediation.

---

## Top-priority threats (act on these immediately)

### THREAT-001 — <one-line title>
- **Attack class:** correctness | security (passive | active | replay | downgrade) | side-channel | regulatory | social | scale
- **Severity:** critical | high
- **Precondition:** <what must hold>
- **Evidence to confirm:** <observable>
- **Attack walkthrough:**
  1. <step 1>
  2. <step 2>
  3. <step 3>
- **Recommended remediation:** <specific>
- **Cost of remediation:** <hours | days | weeks>
- **Cost of NOT remediating:** <impact estimate>
- **Source:** <C-NNN | AF-NNN | red-team>

### THREAT-002 — ...

### THREAT-003 — ...

(Top 5 most-actionable threats. Priority formula: `severity × likelihood / remediation_cost`. Ties broken by exploit-prevalence.)

---

## All threats by severity

### Critical
- THREAT-NNN: <title> (one-liner)
- THREAT-NNN: ...

### High
- ...

### Medium
- ...

### Low
- ...

---

## All threats by attack class

### Correctness
- ...

### Security — Passive observation
- ...

### Security — Active attack
- ...

### Security — Replay
- ...

### Security — Downgrade
- ...

### Side-channel — Timing
- ...

### Side-channel — Memory
- ...

### Regulatory / legal
- ...

### Social / governance
- ...

### Scale — DoS / resource exhaustion / cost amplification
- ...

(Skip empty classes.)

---

## Recommended remediations (prioritized roadmap)

| Priority | Remediation | Threats addressed | Cost | Owner | Deadline |
|----------|-------------|--------------------|------|-------|----------|
| 1 | <specific> | THREAT-001, THREAT-005 | 2 days | <team> | <date> |
| 2 | <specific> | THREAT-002 | 1 week | <team> | <date> |
| 3 | ... | ... | ... | ... | ... |

---

## Audit coverage attestation

This threat catalog represents the result of:
- <N> Devil's-Advocate panes × <M> rounds of investigation
- Phase 7 audit converged at trio-round <N>
- Red-team subagent run: <yes | no>
- External verification: <none | reviewer X>

### Threat surface NOT covered by this audit

(Important: declare what's out of scope so the user doesn't assume completeness.)

- <out-of-scope class 1: e.g., physical attacks>
- <out-of-scope class 2: e.g., supply-chain compromise>
- <out-of-scope class 3: e.g., insider with admin access>

### Time-bounded coverage

- Audit reflects subject state at <ISO timestamp>
- Re-audit recommended after:
  - Major architecture change
  - <next deadline>
  - 6 months from audit date for high-stakes systems

---

## Open questions

(Threats hypothesized but not resolved within audit time budget; defer to next audit.)

- <one-line> — investigation deferred because <reason>
- <one-line>

---

## Cross-references

- Open audit findings: <list of AF-NNN with severity>
- Anomalies that did NOT cluster (per ΔE): <list of AN-NNN>
- Pre-existing known issues: <list>

---

## Sign-off

For T4+ audits:

- [ ] Operator reviewed
- [ ] Security-domain expert reviewed
- [ ] Critical/high threats acknowledged
- [ ] Remediation roadmap approved
- [ ] Re-audit scheduled

**Operator:** <name> | **Date:** <ISO>
**Security expert:** <name> | **Date:** <ISO>
