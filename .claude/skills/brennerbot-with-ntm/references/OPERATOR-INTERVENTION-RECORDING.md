# OPERATOR-INTERVENTION-RECORDING.md — Audit Trail for Human Overrides

<!-- TOC: Why intervention recording | The 6 intervention types | The 4 severity levels | The intervention schema | Per-intervention audit trail | When operators legitimately intervene | Cross-session intervention patterns | Per-phase intervention activity | Anti-patterns | Cross-references -->

Brennerbot is multi-agent autonomous-orchestration friendly (per ROBOT-MODE-AUTONOMOUS-ORCHESTRATION.md), but **the operator can always intervene**. The question is: how do we audit those interventions?

Without recording, operator overrides become invisible — the artifact looks like agent-produced when it was really operator-edited. With recording, every intervention is logged with type, severity, target, and state-change diff. Replay reproducibility (per SESSION-REPLAY-AND-REPRODUCIBILITY.md) depends on this audit trail.

Mined from `/dp/brenner_bot/README.md § Operator Intervention Recording`.

---

## Why intervention recording

Three failures of unaudited interventions:

1. **Hidden bias** — operators silently nudge artifacts toward preferred verdicts; the artifact looks consensus-derived
2. **Replay broken** — re-running the session's inputs against fresh agents produces different outputs because operator edits are invisible
3. **Trust collapses** — readers can't tell what's agent-produced vs operator-shaped

Three benefits of recording:

1. **Provenance per change** — every artifact element traces to either an agent message OR a logged operator intervention
2. **Replay viable** — interventions are re-applied during replay (or counted as divergence points)
3. **Calibration loop** — patterns of intervention reveal where operators systematically don't trust agents (or do too much)

---

## The 6 intervention types

| Type | Description | Typical Severity |
|------|-------------|-------------------|
| `artifact_edit` | Direct edit to compiled artifact (bypassing delta protocol) | moderate |
| `delta_exclusion` | Excluded an agent's delta from compilation | moderate |
| `delta_injection` | Added a delta not from an agent (operator-authored) | major |
| `decision_override` | Overrode a protocol decision (e.g., kept H alive past kill-trigger) | major |
| `session_control` | Terminated, forked, or reset session | critical |
| `role_reassignment` | Changed agent-role mappings mid-session | major |

The types form a graduated severity hierarchy. `artifact_edit` is mild ("fix typo"); `session_control` is heavy ("abort and restart").

---

## The 4 severity levels

| Severity | Examples |
|----------|----------|
| `minor` | Typo fixes, formatting adjustments |
| `moderate` | Delta exclusion, small artifact edits, role-name corrections |
| `major` | Killing hypotheses, adding tests, role reassignments, delta injection |
| `critical` | Session termination, protocol bypass, mid-session reset |

Severity drives:
- **Replay handling** — minor interventions auto-applied; critical require explicit replay-mode flag
- **Audit-finding generation** — major+ interventions generate audit-finding beads at Phase 7
- **HANDBACK transparency** — major+ interventions appear in HANDBACK § Caveats

---

## The intervention schema

```typescript
interface OperatorIntervention {
  id: string;                  // INT-RS20251230-001
  session_id: string;          // RS-20251230-...
  timestamp: string;           // ISO 8601
  operator_id: string;         // "human" or pane identity
  type: InterventionType;
  severity: InterventionSeverity;
  target: {
    message_id?: number;
    artifact_version?: number;
    item_id?: string;          // H-001, T-002, etc.
    item_type?: string;        // hypothesis, test, assumption, ...
  };
  state_change?: {
    before: string;            // serialized state before
    after: string;             // serialized state after
    before_hash?: string;      // SHA-256
    after_hash?: string;
  };
  reason: string;              // operator's stated reason
  alternative_considered?: string;  // what the agent would have done
}
```

Beads stored at `.beads/interventions.jsonl` (append-only); never modified after write.

---

## Per-intervention audit trail

Every intervention produces an `INT-NNN` bead:

```yaml
id: INT-RS20260301-007
label: operator_intervention
type: delta_exclusion
severity: moderate
operator_id: human
timestamp: 2026-03-01T15:42:00Z
target:
  message_id: 47
  item_id: H-002
reason: "Delta proposed by BlueLake added an H that's a near-duplicate of H-001 (similarity 0.87 per cross-session search). Excluding to avoid F-302 hypothesis duplication."
alternative_considered: "Could have accepted the H and let triage dedupe at Phase 3 end, but with 4 active Hs already, additional dupe creates noise."
```

Quality bar:

- **`reason` mandatory** — vague reasons ("doesn't fit") rejected by validator
- **`alternative_considered` recommended** — shows the operator weighed the trade-off
- Severity must be calibrated honestly; persistent under-reporting flagged

---

## When operators legitimately intervene

There are valid intervention scenarios:

### Legitimate: artifact_edit

- Typo or formatting fix in a compiled artifact (severity: minor)
- Correcting a §-anchor that the agent mis-typed (severity: minor)

### Legitimate: delta_exclusion

- Agent posted a near-duplicate H; exclude to keep slate clean
- Agent posted invalid JSON in a delta; exclude rather than fail-fast the round
- Per Phase 7 audit: high exclusion rate triggers calibration coaching D-Cal-13

### Legitimate: delta_injection

- Operator notices a hypothesis nobody proposed; injects it as `origin: operator_proposed`
- (Severity: major; should be rare for T3+; if frequent, panes are missing key options)

### Legitimate: decision_override

- Adjudicator's verdict is being overruled because it missed a key piece of evidence
- (Severity: major; per F-502 adjudicator-bias detection, rotate adjudicator)

### Legitimate: session_control

- Session is going off-track; terminate and re-frame at Phase 1
- Session is forked into two parallel investigations
- (Severity: critical; document extensively; HANDBACK § Caveats lists)

### Legitimate: role_reassignment

- Pane assigned wrong role at bootstrap; correct it
- Pane is consistently failing at its role; reassign or replace
- (Severity: major; if frequent, ROSTER-PLANS.md needs update)

---

## When intervention is NOT legitimate

Anti-patterns:

| ✗ | Reason |
|---|--------|
| Edit artifact to make verdict more "convincing" | Bypasses tribunal; per F-403 |
| Inject delta because "this is what we should have concluded" | Bypasses agent reasoning; replay broken |
| Override adjudicator because "I disagree" | Per F-502; rotate adjudicator instead |
| Silently amend a locked prediction | Per PREDICTION-LOCK-CRYPTOGRAPHIC.md: amendments tracked |
| Reset session mid-Phase to "start over with what I know now" | Per HYPOTHESIS-LIFECYCLE: this is a refine, not a reset |
| Reassign roles to favor "the agent that agrees with me" | Bias amplification |

These patterns generate audit-finding beads (severity: critical) at Phase 7.

---

## Cross-session intervention patterns

Per BRENNERBOT-AT-SCALE.md: track patterns across sessions:

- **High `delta_injection` rate** — operator is doing the panes' job; either agents are under-performing or operator is bypassing
- **High `decision_override` rate** — adjudicator-rotation isn't working; per OC-013
- **High `session_control` (resets)** — Phase 1 framing is consistently weak (per FRAMING-WORKBOOK.md)
- **High `role_reassignment`** — ROSTER-PLANS.md tier-defaults need adjustment

These feed FAILURE-MODE-ANALYTICS.md as patterns P-12 through P-15.

---

## Per-phase intervention activity

Most interventions cluster around specific phases:

| Phase | Common interventions |
|-------|---------------------|
| 1 framing | minor edits to question of record |
| 2 bootstrap | role_reassignment if pane crashes |
| 3 hypothesis | delta_exclusion (duplicates), delta_injection (missing third-alt) |
| 4 investigation | artifact_edit (anchor corrections) |
| 5 cross-exam | decision_override (rare; high-severity if used) |
| 6 distillation | minor edits |
| 7 audit | (operators ideally don't intervene; let auditors find issues) |
| 8 freeze | (no interventions; freeze is locked) |
| 9 handback | minor edits to HANDBACK voice |

Phase 7 should have **near-zero** operator interventions. If audit pane work is being overruled, the audit isn't being trusted — that's a methodology problem.

---

## Replay handling

Per SESSION-REPLAY-AND-REPRODUCIBILITY.md, interventions are part of the SessionTrace:

```typescript
interface SessionTrace {
  rounds: TraceRound[];
  interventions: OperatorIntervention[];   // ← stored separately
  ...
}
```

During replay:
- `--mode trace`: interventions shown in the timeline
- `--mode rerun`: operator chooses whether to re-apply interventions or skip them
- `--mode shadow`: operator predicts each intervention before it's revealed

The intervention list is *part of the SessionRecord*; reproducibility includes faithful re-application of operator decisions.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Edit artifact directly without filing INT-NNN bead | Audit trail broken; replay broken |
| Use `severity: minor` for everything | Sandbagging; audit will catch via scale of state_change |
| Skip `reason` field | Validator rejects; per audit, vague reasons = audit-finding |
| Combine multiple interventions in one bead | Each intervention atomic; one bead per |
| Backdate timestamps | Per AGENTS.md: integrity matters; backdating is fraud |
| Hide interventions from HANDBACK § Caveats | major+ interventions must surface |
| `delta_injection` to "fix" what the operator believes the agents missed | Per Phase 7: this is your bias; let the tribunal review |
| `session_control` reset without documenting prior state | Loses prior work; AGENTS.md no-deletion applies; preserve session-logs/ |

---

## Composition with brennerbot

Interventions integrate with:

- **Tribunal** (per TRIBUNAL-AND-OBJECTION-REGISTER.md): high-severity interventions auto-file critique beads
- **Calibration** (per OPERATOR-CALIBRATION-LOG.md): intervention rate per operator tracked
- **Replay** (per SESSION-REPLAY-AND-REPRODUCIBILITY.md): interventions in SessionTrace
- **Failure analytics** (per FAILURE-MODE-ANALYTICS.md): patterns P-12 through P-15
- **Doctor rubric** (per BRENNERBOT-DOCTOR-RUBRIC.md): per-session intervention count
- **HANDBACK** (per HANDBACK-VOICE-GUIDE.md): § Caveats lists major+ interventions

---

## Cross-references

- [SESSION-REPLAY-AND-REPRODUCIBILITY.md](SESSION-REPLAY-AND-REPRODUCIBILITY.md) — interventions in SessionTrace
- [TRIBUNAL-AND-OBJECTION-REGISTER.md](TRIBUNAL-AND-OBJECTION-REGISTER.md) — auto-file critiques on overrides
- [PREDICTION-LOCK-CRYPTOGRAPHIC.md](PREDICTION-LOCK-CRYPTOGRAPHIC.md) — amendment tracking
- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — illegal state transitions detected as decision_override
- [OPERATOR-CALIBRATION-LOG.md](OPERATOR-CALIBRATION-LOG.md) — per-operator intervention rate
- [FAILURE-MODE-ANALYTICS.md](FAILURE-MODE-ANALYTICS.md) — patterns P-12..P-15
- [BRENNERBOT-DOCTOR-RUBRIC.md](BRENNERBOT-DOCTOR-RUBRIC.md) — Pillar 5 (Cross-session) checks
- [HANDBACK-VOICE-GUIDE.md](HANDBACK-VOICE-GUIDE.md) — surface major+ in caveats
- /dp/brenner_bot/README.md § Operator Intervention Recording — original source
