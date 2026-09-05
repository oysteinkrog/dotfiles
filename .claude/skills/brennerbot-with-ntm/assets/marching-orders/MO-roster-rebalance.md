# MO-roster-rebalance.md — Mid-Session Roster Rebalance

**Phase:** any (typically Phase 4 mid-session)
**Operators activated:** none (operational discipline)
**Parameters:** `<SESSION_ID>`, `<REASON>` (workload-imbalance | model-family-bias | rate-limit-cluster | role-collision | other), `<NEW_ROSTER>` (post-rebalance assignment), `<WORKSPACE_PATH>`

---

When the existing roster has become unbalanced — too many Investigators with too few Hs, one model family dominating, multiple panes simultaneously rate-limited, etc. — this MO formalizes the rebalance.

Distinct from `MO-context-saturated-rotation.md` (single pane respawn) and `MO-domain-handoff.md` (single domain transfer). This is multi-pane reorganization.

---

**Step 1 — Diagnose the imbalance.**

Run `tick.sh` and `liveness-check.sh` to confirm the imbalance is real:

```bash
./scripts/tick.sh <WORKSPACE_PATH> > /tmp/tick.before.txt
./scripts/liveness-check.sh <WORKSPACE_PATH> >> /tmp/tick.before.txt
```

Specific signals to confirm:

- **Workload-imbalance:** ≥1 pane has 0 active H assignment AND ≥1 pane has ≥4 active Hs
- **Model-family-bias:** Phase 5 adjudications consistently favor one family (per F-502)
- **Rate-limit-cluster:** ≥2 panes simultaneously rate-limited on the same provider
- **Role-collision:** two panes claiming the same role (Investigator-2 working on H-005 that Investigator-1 also claims)

Document the diagnosis in `session-logs/rebalance-<timestamp>.md`.

**Step 2 — Plan the rebalance.**

Based on `<REASON>`, choose the rebalance strategy:

### For workload-imbalance:
- Reassign Hs from over-loaded panes to under-loaded panes
- Use `MO-domain-handoff.md` per H

### For model-family-bias:
- Rotate model families (e.g., kill cc Adjudicator pane, respawn as cod or gmi)
- Update `phase0_scope_decision.md § adjudicator_rotation`

### For rate-limit-cluster:
- Per `/vibing-with-ntm` OC-002: rotate accounts on affected panes
- Or: kill rate-limited panes, respawn on different families
- Continue with reduced effective roster

### For role-collision:
- Adjudicator (rotating role) decides the canonical owner
- Loser pane gets a different H or role
- Update `MO-domain-handoff.md` for the displaced

**Step 3 — Snapshot pre-rebalance state.**

```bash
br sync --flush-only
git add .brenner_workspace/ .beads/ session-logs/ deliverables/
git status
git commit -m "Pre-rebalance snapshot: <REASON>"
```

This creates a recovery point if the rebalance produces unexpected issues.

**Step 4 — Execute the rebalance.**

For each pane affected:

- If pane is being retired: dispatch a continuity bead (per `MO-domain-handoff.md`) before removing it from new assignments
- If pane is being re-roled: dispatch new role briefing per `MO-02-onboarding.md`
- If pane needs a different family: add a fresh pane via `ntm add` and hand it the continuity bead

```bash
# Example: add a Gemini adjudicator and point it at the handoff note.
ntm add <session> --gmi=1 --prompt="Take over as Adjudicator; read session-logs/rebalance-<TIMESTAMP_UTC>.md first."
```

**Step 5 — Notify all panes.**

```
Subject: [<SESSION_ID>] Roster rebalance: <REASON>

Pre-rebalance roster: <list>
Post-rebalance roster: <list>

Affected panes:
- p<N>: <change>
- p<N>: <change>

If your role/domain changed, refer to your continuity bead at <H-handoff-NNN>.

Continue work; no current investigation should be lost — handoffs are in continuity beads.
```

**Step 6 — Update phase0_scope_decision.md.**

```bash
cat >> .brenner_workspace/phase0_scope_decision.md <<EOF

## Roster rebalance — $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Reason: <REASON>
- Pre-rebalance roster:
$(grep -A 20 "## Roster" .brenner_workspace/phase0_scope_decision.md | tail -10)
- Post-rebalance roster:
$(echo "$NEW_ROSTER")
- Continuity beads filed: <list>
EOF
```

**Step 7 — Verify post-rebalance.**

Wait 30 min. Run:

```bash
./scripts/tick.sh <WORKSPACE_PATH>
./scripts/liveness-check.sh <WORKSPACE_PATH>
```

Confirm:
- Each new pane is producing artifacts
- Each transferred H has a single owner
- No model-family bias signals
- No rate-limited panes blocking work

If new imbalance emerges, dispatch this MO again. Persistent imbalance after 2 rebalances → escalate to `MO-emergency-stop.md`.

---

**Anti-patterns:**

- ✗ Rebalance without diagnosis — may not fix the root cause
- ✗ Rebalance without continuity beads — lose investigator state
- ✗ Rebalance without notifying all panes — confusion about who owns what
- ✗ Rebalance frequently (>1× per phase) — instability worse than imbalance
- ✗ Skip phase0_scope_decision.md update — Phase 10 drift can't reconstruct

**Ship-or-Surface SLA:** within 30 min, rebalance complete + verified + new state stable.
