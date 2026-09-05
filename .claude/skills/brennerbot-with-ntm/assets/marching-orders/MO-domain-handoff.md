# MO-domain-handoff.md — Cross-Pane Domain Transfer

**Phase:** any (typically Phase 4 mid-session)
**Operators activated:** none (operational discipline)
**Parameters:** `<FROM_PANE_N>`, `<TO_PANE_N>`, `<DOMAIN>` (the H-IDs being transferred), `<REASON>` (rate-limit | saturation | rebalance | other), `<SESSION_ID>`

---

When an Investigator pane needs to hand off its domain to another pane (mid-session), this MO formalizes the transfer to preserve continuity.

Distinct from `MO-context-saturated-rotation.md` (which respawns the same role on the same pane). This is a transfer to a *different* pane that may have different domain assignment.

---

**Step 1 (FROM pane) — Snapshot work.**

The pane handing off writes a continuity bead:

```bash
handoff_ref="H-handoff-NNN"  # public ref; replace NNN before running
handoff_id="$(br create "$handoff_ref: Domain handoff from <FROM_PANE_N> to <TO_PANE_N>" \
  --type=task --labels=task --priority=2 \
  --slug="$handoff_ref" --external-ref="$handoff_ref" --silent \
  --description="$(cat <<'EOF'
type: domain_handoff
from_pane: <FROM_PANE_N>
to_pane: <TO_PANE_N>
domain: <DOMAIN>
reason: <REASON>
session: <SESSION_ID>

## Current state per H
For each H in <DOMAIN>:
- H-NNN:
    state: <current state>
    investigation status: <what's done>
    next action would be: <what was planned>
    open critiques: <list of C-NNN>
    open assumptions: <list of A-NNN>
    blockers: <any>

## Mental model
<brief paragraph: what FROM-pane currently believes about the domain — for TO-pane to inherit>

## Decisions taken without explicit beads
<sometimes investigators make implicit choices; surface them>

## Risk register
<what could go wrong with the transfer; e.g., FROM-pane caught a partial pattern they were about to dig into>
EOF
)")"
printf 'Created %s as br id %s\n' "$handoff_ref" "$handoff_id"
```

**Step 2 (FROM pane) — Notify peers.**

Post to per-H thread for each H in domain:

```
Subject: [<SESSION_ID>-<h-id>] Domain handoff: <FROM_PANE_N> → <TO_PANE_N>

Continuity bead: H-handoff-NNN
Reason: <REASON>

<TO_PANE_N>: please read H-handoff-NNN, then continue from "next action would be" sections.
```

Post to `RS-...-INVEST-coord`:

```
Subject: [<SESSION_ID>] Domain transfer: <DOMAIN> from p<FROM_PANE_N> to p<TO_PANE_N>

p<FROM_PANE_N> handing off <DOMAIN> to p<TO_PANE_N> due to <REASON>.

Continuity at H-handoff-NNN.
```

**Step 3 (FROM pane) — Release bead claims.**

```bash
id_by_ref() {
  br list --all --json \
    | jq -r --arg ref "$1" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' \
    | head -1
}

domain_refs="<DOMAIN>"  # H refs, separated by spaces or commas
for h_ref in $(printf '%s\n' "$domain_refs" | tr ',' ' '); do
  h_id="$(id_by_ref "$h_ref")"
  [ -n "$h_id" ] || { echo "No bead found for public ref: $h_ref" >&2; exit 1; }
  br update "$h_id" --assignee=p<TO_PANE_N>
done
```

(In Agent Mail mode, also release file reservations.)

**Step 4 (TO pane) — Onboard to new domain.**

Read H-handoff-NNN. Read per-H evidence packs for `<DOMAIN>`. Read recent posts in per-H threads.

For each H, post acknowledgment in per-H thread:

```
Subject: [<SESSION_ID>-<h-id>] Acknowledged handoff from p<FROM_PANE_N>

I've read H-handoff-NNN and EV-pack-<h-id>.md.

My understanding of current state: <one sentence>
My next action: <one specific action>

Continuing investigation per `MO-04a-investigate.md`.
```

**Step 5 (operator) — Update phase0_scope_decision.md.**

```bash
cat >> .brenner_workspace/phase0_scope_decision.md <<EOF

## Roster change — domain handoff $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Domain <DOMAIN> transferred: p<FROM_PANE_N> → p<TO_PANE_N>
- Reason: <REASON>
- Continuity bead: H-handoff-NNN
EOF
```

**Step 6 — Verify continuity.**

Wait 30 min. Check that <TO_PANE_N> is producing artifacts (commits + bead activity) on the transferred domain. If no activity, escalate (likely TO_PANE didn't actually load the handoff context).

---

**Anti-patterns:**

- ✗ Hand off without continuity bead — TO pane has to reconstruct from scratch
- ✗ Hand off without notifying peers — confusion about who owns what
- ✗ TO pane skip reading H-handoff-NNN — they redo work or miss context
- ✗ FROM pane keeps working on transferred domain — race condition; collisions
- ✗ Skip the phase0_scope_decision.md update — Phase 10 drift-check can't reconstruct
- ✗ Use this MO for full role rotation (use `MO-context-saturated-rotation.md` for same-role respawn)

**Ship-or-Surface SLA:** within 30 min, transfer complete + TO pane producing artifacts.
