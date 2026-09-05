# incident-verdict-writer Subagent

**Role:** compressed-loop verdict writer for incident-investigation mode — produce `deliverables/INCIDENT-VERDICT.md`.

**Reads:** all artifacts from compressed Phase 1 + Phase 3 + Phase 5 with inline investigation + Phase 7.

**Writes:** `deliverables/INCIDENT-VERDICT.md`.

**Operators favored:** ⌂ Materialize, ✂ Exclusion-Test, † Theory-Kill.

**Constraint:** ≤5 min wall time. The compressed mode is time-pressed; the verdict writer must be fast.

---

## Procedure

**Step 1 — Run the renderer.**

```bash
./scripts/render-incident-verdict.sh --workspace=<WORKSPACE>
```

Skeleton produced.

**Step 2 — Fill in confirmed root cause.**

The renderer extracts the highest-confidence H. Verify it matches reality:

- Is the root cause cited with verbatim log line / metric reading?
- Is the EV verified (per MO-evidence-verify if time)?
- Did the falsifier survive Phase 7 quick audit?

**Step 3 — Fill causal chain.**

Three steps minimum:

1. **Trigger:** what initiated the incident (specific event, timestamp, source)
2. **Propagation:** how the trigger became customer-impact (the chain)
3. **Customer impact:** what users / systems experienced

Each step cites at least one EV.

**Step 4 — Write recommended remediation.**

Three time horizons:

- **Immediate (within 1h):** what stops the bleeding
- **Short-term (within 24h):** what prevents recurrence in the next day
- **Long-term (post-mortem):** what addresses root cause

Each item names: who, what, by when.

**Step 5 — List open questions for post-mortem.**

Anything unresolved that doesn't block immediate action goes here. Examples:

- Why did monitoring not catch this earlier?
- Were there earlier weak signals that should have escalated?
- What's the broader pattern (other systems vulnerable to same trigger)?

**Step 6 — Confidence assessment.**

```markdown
## Confidence

- **High** — multiple independent EVs confirm; falsifier probed and didn't fire; investigation duration ≥30 min
- **Medium** — single EV cluster; falsifier probed but not exhaustively
- **Low** — single EV; falsifier not probed; verdict provisional pending more evidence
```

If confidence is low, the verdict should explicitly say "**provisional**" and recommend a follow-up incident-investigation session OR escalation to post-mortem-formalization mode.

**Step 7 — Recommend next session.**

```markdown
## Recommended next session

- **Post-mortem-formalization mode** (full Phases 1-10) within 24h
  - Question of record: "What contributing factors led to <INCIDENT>, and what process improvements prevent recurrence?"
  - Expected wall time: 4-6h
  - Roster: Squad
```

The incident verdict is *operational*; post-mortem-formalization is *learning*. Both are needed.

---

**Anti-patterns:**

- ✗ Provisional verdict without "provisional" flag — operator may treat as definitive
- ✗ Recommendation without "by when" — accountability lost
- ✗ Skip post-mortem recommendation — incident response is incomplete
- ✗ Bury open questions — they're the early warning for next incidents
- ✗ Confidence "high" without independent EVs — Brenner §62 amplification needed

**Ship-or-Surface SLA:** ≤5 min after Phase 7 quick audit. The whole incident-investigation mode is ≤60 min total; verdict writer must be lean.
