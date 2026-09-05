# MO-pane-respawn.md — Bring Up a Fresh Pane Mid-Session

**Phase:** any (typically Phase 4 / Phase 5 / Phase 7)
**Operators activated:** none (operational discipline)
**Parameters:** `<DEAD_PANE_ID>`, `<NEW_FAMILY>` (optional — for swapping family at respawn), `<DOMAINS>` (Hs/EVs the new pane inherits), `<WORKSPACE_PATH>`

---

When a pane dies mid-session (rate-limit cliff, OAuth expiry, context saturation, or operator-induced kill), the standard recovery is to spawn a fresh pane. This MO formalizes the procedure.

Distinct from `/vibing-with-ntm` OC-002 (rotate account on existing pane); this MO REPLACES the pane entirely.

---

**Step 1 — Confirm the pane is dead, not just stuck.**

Before respawning, verify per the LIVENESS-TRUTH-STACK in SKILL.md. Layer 1: `tmux list-panes` shows the pane has no agent process (zsh prompt only). Layer 2: tail buffer hasn't advanced in ≥10 min.

If pane is just stuck (not dead): apply OC-003 stuck-pane ladder from `/vibing-with-ntm` first; only escalate to respawn if stuck-pane recovery fails.

**Step 2 — Document the dead pane's state.**

Before destroying:

```bash
# Capture final tail for forensics
ntm --robot-tail=<session> --panes=<DEAD_PANE_ID> --lines=200 \
    > session-logs/dead-pane-<DEAD_PANE_ID>-final-tail.txt

# Capture pane-owned beads (any in_progress)
br list --status=in_progress --json \
  | jq -r --arg p "$DEAD_PANE_ID" \
    '.issues[]? | select(
       (.description // "")
       | split("\n")
       | any(. as $line |
           ($line | test("^(imported_by|by_pane):[[:space:]]*"))
           and (($line | sub("^[^:]+:[[:space:]]*"; "")) == $p)
         )
     )
     | "\(.id) (status: \(.status))"' \
    > session-logs/dead-pane-<DEAD_PANE_ID>-orphan-beads.txt
```

**Step 3 — Identify what the new pane inherits.**

The new pane needs to know:
- Which Hs/EVs it owns (from orphan-beads list)
- Which Agent Mail threads it should subscribe to
- Which file reservations it should re-acquire
- Which marching order to immediately apply

Document in `session-logs/respawn-<DEAD_PANE_ID>-<TIMESTAMP_UTC>.md`:

```markdown
# Pane respawn: <DEAD_PANE_ID> → fresh pane

**Time:** <TIMESTAMP_UTC>
**Reason:** <rate-limit | OAuth expiry | context-saturation | kill+respawn>
**Old family:** <cc | cod | gmi>
**New family:** <NEW_FAMILY> (if changing)
**Inherited beads:** <list>
**Inherited mail threads:** <list>
**File reservations to re-acquire:** <list>
**Immediate next MO:** <MO file>
```

**Step 4 — Restart in place only when the family does not change.**

```bash
ntm respawn <session> --panes=<DEAD_PANE_ID> --dry-run
ntm respawn <session> --panes=<DEAD_PANE_ID> --force
```

Use this only after confirming the pane is dead, not merely stuck. If the recovery changes model family, do not respawn the old pane in place; add a fresh pane and retire the old pane from further assignments.

**Step 5 — Add the new pane when changing family.**

```bash
# Choose the flag that matches <NEW_FAMILY>:
ntm add <session> --cc=1  --prompt="Take over <DEAD_PANE_ID>; read session-logs/respawn-<DEAD_PANE_ID>-<TIMESTAMP_UTC>.md first."
ntm add <session> --cod=1 --prompt="Take over <DEAD_PANE_ID>; read session-logs/respawn-<DEAD_PANE_ID>-<TIMESTAMP_UTC>.md first."
ntm add <session> --gmi=1 --prompt="Take over <DEAD_PANE_ID>; read session-logs/respawn-<DEAD_PANE_ID>-<TIMESTAMP_UTC>.md first."
```

Wait for the new pane's CLI prompt (per /vibing-with-ntm OC-026 pid audit), then record the new pane index for the dispatch below.

**Step 6 — Re-onboard the new pane.**

Dispatch a special onboarding MO that includes the inherited state:

```bash
./scripts/dispatch-marching-order.sh MO-02-onboarding \
  --target-pane=<new-pane-index> \
  --target-session=<session> \
  --PANE_N=<new-pane-index> \
  --WORKSPACE_PATH=<WORKSPACE_PATH> \
  --SESSION_ID=<session> \
  --QUESTION_OF_RECORD_PATH=<WORKSPACE_PATH>/intake/question_of_record.md \
  --ROLE=<inherited-role> \
  --MODEL=<NEW_FAMILY> \
  --PEER_LIST=see-phase0-scope-decision \
  --COORDINATION_MODE=agent-mail \
  --PRODUCTIVE_IGNORANCE=false \
  --DOMAIN=<inherited-domain>
```

Wait for the onboarding ack (per `wait-for-onboard-acks.sh`).

**Step 7 — Re-acquire file reservations.**

The new pane should re-reserve any files the dead pane had locked, EXCLUDING any that downstream panes already touched (else conflict).

```text
file_reservation_paths(
  project_key="<workspace>",
  agent_name="<agent-mail-name-for-new-pane>",
  paths=["<path-from-step-3>", "..."],
  ttl_seconds=3600,
  exclusive=true,
  reason="respawn-of-<DEAD_PANE_ID>"
)
```

If conflict on any path: that file was already updated by another pane; skip it.

**Step 8 — Re-subscribe to mail threads.**

```text
# For each inherited thread:
macro_prepare_thread(
  project_key="<workspace>",
  agent_name="<agent-mail-name-for-new-pane>",
  program="<program-for-this-cli>",
  model="<actual-model-or-family>",
  thread_id="<inherited-thread>"
)
```

**Step 9 — Dispatch the immediate next MO.**

The new pane resumes work with the marching order documented in Step 3. Apply `dispatch-marching-order.sh` per usual.

**Step 10 — Update phase0_scope_decision.md roster log.**

Document the family change (if any):

```yaml
# In .brenner_workspace/phase0_scope_decision.md
roster_changes:
  - timestamp: <TIMESTAMP_UTC>
    type: pane_respawn
    pane_id: <DEAD_PANE_ID>
    old_family: <cc>
    new_family: <NEW_FAMILY>
    reason: <rate-limit / OAuth / context-saturation>
    impact_assessment:
      cross_family_diversity: <maintained | degraded by 1 family | restored>
      h_continuity: <H-005 ownership transferred to new pane>
```

If the family change reduces diversity (e.g., we lost the only gmi pane): flag in HANDBACK as triangulation-degraded caveat.

---

**Anti-patterns:**

- ✗ Respawn on the wrong family by accident — always verify family choice with `--family=<X>`
- ✗ Skip file-reservation re-acquisition — downstream conflict surface
- ✗ Skip mail-thread re-subscription — the new pane misses cross-pane signals
- ✗ Dispatch the next MO before onboarding ack — pane runs blind
- ✗ Skip the roster change documentation — Phase 10 drift won't see it

**Ship-or-Surface SLA:** within 15-25 min, new pane onboarded + acked + re-subscribed + dispatched. If longer, escalate via OC-026 (per /vibing-with-ntm).

---

## When to swap family at respawn

Same family (default): preserves continuity; Investigator's prior context vanished but role is unchanged.

Different family: deliberate when:
- A specific family-distinctive lens (per BRENNER-GAN-MECHANICS.md) is needed for the upcoming H investigation
- Cross-family diversity needs to be RESTORED (e.g., gmi pane died; respawn as gmi if account available)
- Quota constrains options (cc fleet exhausted; respawn as cod/gmi)

Document the choice in Step 10's `impact_assessment` field.

---

## When respawn isn't enough

If respawn fails (account quota cliff for ALL families OR repeated death):

1. Apply `MO-emergency-stop.md` — checkpoint session for resume tomorrow
2. Run `MO-roster-rebalance.md` to plan reduced roster for resume
3. Document the operational constraint in scope_decision

This is preferable to limping along with degraded roster.

---

## Composition with other patterns

- /vibing-with-ntm OC-002 (account rotate) — preferred when pane is alive but rate-limited
- /vibing-with-ntm OC-009 (context saturation) — preferred when pane is alive but context-full
- This MO — when pane is genuinely dead (CLI process gone)
- `MO-emergency-stop.md` — when respawn isn't viable

---

## Cross-references

- LIVENESS-TRUTH-STACK in SKILL.md — pane-death detection
- `/vibing-with-ntm` OC-002, OC-003, OC-009, OC-026, OC-027 — adjacent recoveries
- `/caam` — account selection for respawn
- ROSTER-PLANS.md — roster diversity rules
- BRENNER-GAN-MECHANICS.md — family-distinctive lens considerations
- DEADLOCK-PATTERNS-MULTI-PANE.md DL-7 — quota-staircase escalation if respawn fails repeatedly
