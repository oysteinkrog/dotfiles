# MO-context-saturated-rotation.md — Recover a Pane Whose Context Window Is Saturated

**Phase:** any (typically 4-7, mid-session)
**Operators activated:** none specifically (this is operator-loop discipline)
**Parameters:** `<SATURATED_PANE_N>`, `<NEW_PANE_N>` (the replacement; may be respawn of same pane), `<H_OR_DOMAIN>` (what the saturated pane was working on), `<ROLE>`, `<SESSION_ID>`

---

Per `/vibing-with-ntm` AP-23 (Saturated Context Drift): a pane running long enough that context >85% starts circular planning instead of real artifact production. The fix: rotate. This MO formalizes the brennerbot-specific handoff.

---

**Step 1 — Detect saturation.**

Saturation signals:

- `ntm --robot-snapshot` shows `context_pct >= 85%` for the pane
- Pane tail shows repetitive content; fresh dispatches produce paraphrases of prior content
- Bead production rate drops despite continued pane activity (per M-CX4)
- Pane explicitly mentions context concerns ("running out of context", "compaction soon")

If detected, dispatch this MO.

**Step 2 — Snapshot pane state to a handoff bead.**

The saturated pane writes a brief handoff snapshot:

```bash
handoff_ref="H-handoff-NNN"  # public ref; replace NNN before running
handoff_id="$(br create "$handoff_ref: Pane <SATURATED_PANE_N> handoff snapshot" \
  --type=task --labels=task --priority=3 \
  --slug="$handoff_ref" --external-ref="$handoff_ref" --silent \
  --description="$(cat <<'EOF'
type: handoff_snapshot
saturated_pane: <SATURATED_PANE_N>
new_pane: <NEW_PANE_N>
working_on: <H_OR_DOMAIN>
session: <SESSION_ID>

## Current state
- Hypotheses claimed: <list>
- EVs filed in current round: <list>
- In-progress investigation thread: <link>
- Open critiques to respond to: <list>

## What's next (would have done)
<3-5 bullet next-actions>

## Open uncertainties
<2-3 things the saturated pane wanted clarification on>

## Verification status
<which EVs need independent verification>
EOF
)")"
printf 'Created %s as br id %s\n' "$handoff_ref" "$handoff_id"
```

**Step 3 — Kill or respawn the saturated pane.**

Per `/vibing-with-ntm` OC-009 (handoff-then-restart):

```bash
ntm --robot-restart-pane=<session> --panes=<SATURATED_PANE_N> --restart-bead=<H_OR_DOMAIN-id>
```

The restart spawns a fresh CLI with full context budget. The pane's role and domain assignment carry over (per `phase0_scope_decision.md`).

**Step 4 — Onboard the fresh pane.**

The fresh pane gets a tailored MO-resume (or MO-02-onboarding for fresh roles):

```
You are pane <NEW_PANE_N> in session <SESSION_ID>. You replace pane <SATURATED_PANE_N> who was saturated and restarted.

Your role: <ROLE> (carry over from saturated pane's role)
Your domain: <H_OR_DOMAIN>

Refresh state:
1. Read the handoff snapshot at H-handoff-NNN (filed by your predecessor).
2. Read the relevant evidence pack(s) for `<H_OR_DOMAIN>` to see the current state.
3. Read recent posts in the Agent Mail thread(s) for `<H_OR_DOMAIN>`.
4. Run `git log --since='1 hour ago' --oneline` to see what your predecessor committed.

Then resume from the "What's next" bullets in the handoff snapshot. Do NOT redo what's already done; build on it.

Same Ship-or-Surface SLA. Same operator algebra.

Begin.
```

**Step 5 — Update phase0_scope_decision.md roster_changes log.**

```bash
cat >> .brenner_workspace/phase0_scope_decision.md <<EOF

## Roster change — $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Saturated pane <SATURATED_PANE_N> rotated to fresh <NEW_PANE_N>
- Reason: context_pct >= 85%
- Handoff bead: H-handoff-NNN
- Domain preserved: <H_OR_DOMAIN>
EOF
```

**Step 6 — Verify continuity.**

After the fresh pane acks, run:

```bash
ntm --robot-attention --attention-session=<session> --attention-cursor=<cursor>
ntm --robot-is-working=<session> --panes=<NEW_PANE_N>
```

Attention should be clean and the supporting boolean should report `is_working: true`, with artifacts appearing in <30 min. If not, the rotation didn't take — dispatch again.

---

**Anti-patterns:**

- ✗ Rotate without a handoff bead. The fresh pane has no idea what its predecessor was doing.
- ✗ Rotate to the SAME model family if a different family is available. Use the rotation as an opportunity to inject diversity.
- ✗ Skip the roster_changes log entry. Phase 10 drift-check needs to know rotations happened.
- ✗ Wait until context_pct hits 99% before rotating. By then the pane is producing junk; rotate at 85%.
- ✗ Treat rotation as "the pane failed". It's expected — context windows have finite capacity. Rotation is hygiene.

**Ship-or-Surface SLA:** within 15 min, the rotation is complete and the fresh pane has acked. The session continues without losing methodology compliance.
