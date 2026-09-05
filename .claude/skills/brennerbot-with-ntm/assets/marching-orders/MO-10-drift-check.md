# MO-10-drift-check.md — Methodology Drift Check (fresh agent only)

**Phase:** 10
**Operators activated:** ∿ Dephase, ◊ Paradox-Hunt (between trajectory and method)
**Parameters:** `<WORKSPACE_PATH>` (the workspace to audit)

---

**You are a FRESH agent. You were NOT part of the original swarm.** The operator has dispatched you (likely a `general-purpose` Agent or `/idea-wizard` Agent) specifically because Phase 10 requires fresh perspective per [DRIFT-RUBRIC.md](../../references/DRIFT-RUBRIC.md) anti-pattern AP-O11.

If you ARE one of the original swarm panes, decline this dispatch. Tell the operator to dispatch to a fresh agent instead.

---

**Step 1 — Read the rubric.**

Read `references/DRIFT-RUBRIC.md` end-to-end. Note:

- The 8 rubric sections
- The Replacement Test (you'll apply it to every deviation)
- The Verdict legend (convergent / divergent-improvement / divergent-regression / mixed)

**Step 2 — Read the inputs.**

```bash
cat <WORKSPACE_PATH>/.brenner_workspace/phase0_scope_decision.md
ls <WORKSPACE_PATH>/.brenner_workspace/phase_*_complete.flag    # phase exit timestamps
ls <WORKSPACE_PATH>/session-logs/round-*.md                     # per-round operator notes
ls <WORKSPACE_PATH>/session-logs/dispatch-*.log                 # dispatched marching orders
cat <WORKSPACE_PATH>/deliverables/RESUME.md
cat <WORKSPACE_PATH>/deliverables/HANDBACK.md
br list --json | jq '.issues[]?'                                 # all beads
```

**Do NOT read** `intake/question_of_record.md` for content. Drift check is methodology-level, not content-level. (Reading it once for *context* is fine; using it to form domain opinions is not.)

**Step 3 — Write rubric section 1: Operators applied vs canonical.**

Per [DRIFT-RUBRIC.md § 1](../../references/DRIFT-RUBRIC.md#1-operators-applied-vs-canonical), produce a table for each of the 15 operators with verdict (`applied` / `partial` / `skipped` / `replaced`).

For evidence: cite specific files, beads, or marching orders in the workspace.

**Step 4 — Write rubric section 2: Phase ordering vs canonical.**

Read `phase_*_complete.flag` timestamps. Detect:

- Skipped phases (no flag)
- Reordered phases (timestamps out of order)
- Compressed phases (very short duration relative to others)

For each, note: was the deviation justified?

**Step 5 — Write rubric section 3: Marching-order modifications.**

For each `MO-*.md` template that was dispatched (look at `session-logs/dispatch-*.log`), check for modifications. Was the operator deviating? With what rationale?

**Step 6 — Write rubric section 4: Convergence behavior.**

For each reapply-until-quiet phase (4, 6, 7), report rounds run vs hard cap, and convergence outcome.

**Step 7 — Write rubric section 5: Evidence + bead invariants.**

Run `scripts/audit-bead-invariants.sh --all` and report violations. Each violation is a regression.

**Step 8 — Apply the Replacement Test to every deviation.**

For each `partial` / `skipped` / `replaced` operator AND every phase deviation AND every MO modification, apply the test:

1. Is the skipped/modified Brenner principle named explicitly with `§`-anchor?
2. Is the replacement named explicitly with rationale?
3. Is the replacement measurably stronger by a specific metric?
4. Is the metric reported with a number?

If all 4 pass: **improvement**. If any fail: **regression**.

**Step 9 — Write rubric section 6: Improvements.**

For each deviation that passed the Replacement Test:

```markdown
### I-NNN: <one-line summary>
- **Replaced:** <Brenner principle + § anchor>
- **Replacement:** <what we did instead>
- **Rationale:** <why>
- **Metric:** <number-bearing measurement>
- **Verdict:** improvement
```

**Step 10 — Write rubric section 7: Regressions.**

For each deviation that failed:

```markdown
### R-NNN: <one-line summary>
- **Source:** <§-anchor>
- **Expected:** <canonical behavior>
- **Actual:** <what happened>
- **F-code:** <F-NNN>
- **Recommendation:** <fix for next session>
```

**Step 11 — Write rubric section 8: Lessons.**

Pick ≥1 lesson. Update at least one file in this skill's `references/`:

```markdown
### L-NNN: <update X.md to do Y>
- **Reason:** <which improvement / regression motivates this>
- **Change:** <specific edit to <reference-file>.md>
- **Owner:** operator commits this update before closing Phase 10.
```

**Step 12 — Write the verdict at the top.**

```
DRIFT VERDICT: <convergent | divergent-improvement | divergent-regression | mixed>
```

**Step 13 — Write `DRIFT-CHECK.md`.**

Save to `<WORKSPACE_PATH>/deliverables/DRIFT-CHECK.md` with all sections in order.

**Step 14 — Apply the lessons.**

The operator commits the references/ updates from Step 11. **Phase 10 cannot exit until ≥1 references/ file is updated.** This is the F-1003 hard invariant.

**Step 15 — Mark phase complete.**

```bash
echo "Phase 10 complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > <WORKSPACE_PATH>/.brenner_workspace/phase_10_complete.flag
git add deliverables/DRIFT-CHECK.md
# Plus any references/ updates from Step 11/14
git commit -m "Phase 10: drift check + lessons"
```

---

**Anti-patterns to avoid (per F-1001..F-1003):**

- ✗ Treating "we couldn't find a proxy" as automatic improvement (F-1001). Apply the Replacement Test strictly.
- ✗ Missing `§`-anchors / canonical-operator citations (F-1002). Cite the source.
- ✗ Skipping the lessons step (F-1003). Mandatory.
- ✗ Auditing as one of the original swarm panes (AP-O11). Decline and tell operator to dispatch a fresh agent.
- ✗ Reading the question of record to form domain opinions. Drift check is method-level only.

**Ship-or-Surface SLA:** within 60 minutes, deliver `DRIFT-CHECK.md` with all sections. The operator commits the lessons from Step 11 immediately.
