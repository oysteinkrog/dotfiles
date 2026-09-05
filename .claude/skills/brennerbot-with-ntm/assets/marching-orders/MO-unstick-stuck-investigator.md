# MO-unstick-stuck-investigator.md — Specific-Terse Nudge for a Stuck Investigator

**Phase:** 4
**Parameters:** `<PANE_N>`, `<H_ID>`, `<LAST_OUTPUT_SHA>` (sha of pane's last meaningful output, for liveness check)

---

This is a specific-terse nudge per `/vibing-with-ntm` AP-21 (Orchestrator Prompt Degradation). NOT a generic "keep going" — that produces prose. Every nudge has one verb + one specific target.

Pick the variant matching the pane's stuck mode:

---

## Variant A: pane has been silent ≥10 min after a dispatch

```
Pane <PANE_N>: Status check on <H_ID>. Reply with one of:
(1) commit SHA of latest evidence pack write,
(2) bead id of latest EV/C filed,
(3) specific blocker (named file/error/missing tool).
No prose. One of (1)/(2)/(3) within 5 min or operator will smart-restart.
```

---

## Variant B: pane is producing prose but no beads

```
Pane <PANE_N>: Stop the prose. <H_ID> needs an EV-* bead with verbatim citation. File it now via:
  ev_ref="EV-NNN"; br create "$ev_ref: ..." --type=task --labels=evidence --slug="$ev_ref" --external-ref="$ev_ref" --silent --description="type: ...; source: ...; supports: [<H_ID>]; ..."
If you can't, surface why in one sentence.
```

---

## Variant C: pane is rate-limited

```
Pane <PANE_N>: Detected rate-limit. Operator is rotating account / waiting. Stand by — no action needed. Will redispatch <H_ID> after rotation.
```

(After this, the operator runs `ntm rotate <session> --pane=<PANE_N> --all-limited` per `/vibing-with-ntm`.)

---

## Variant D: pane's tail shows convergence language ("LGTM", "no fixes needed", "ready") on Phase 4 work

```
Pane <PANE_N>: "<H_ID> has no fixes needed" requires evidence. Cite the EV-NNN that fires its falsifier (if any) OR file the negative-search EV documenting that the falsifier was probed and didn't fire. Without one, do not claim convergence.
```

---

## Variant E: pane wrote a "Ready for validation" handoff message but didn't ship work

```
Pane <PANE_N>: "Ready for validation" is not a deliverable. Ship the bead OR surface the blocker. Operator does not validate — file the EV/C bead and continue.
```

---

## Variant F: stuck-pane ladder — escalate

```
Pane <PANE_N>: Identical tail for 3+ ticks. Operator escalating per /vibing-with-ntm OC-003:
1. wake-ping (sending "ping" Enter)
2. C-u + send (Escape Escape Escape C-u then redispatch)
3. smart-restart (--robot-smart-restart with current MO)
4. hard-kill if needed
You will see a new prompt soon.
```

(After this, the operator runs the ladder per `/vibing-with-ntm`.)

---

## Generic anti-patterns to avoid in nudges

- ✗ "Keep going" — too generic; produces more prose.
- ✗ "Status?" — invites prose answers; ask for SHA / bead id / blocker.
- ✗ Multiple nudges in 60 seconds — burns context. Wait 5 min between nudges.
- ✗ Nudging without a tail check — `ntm --robot-tail=<session> --panes=<N>` first; if pane is producing fresh content, no nudge needed.

**Ship-or-Surface SLA for the OPERATOR (not the pane):** unstick attempt resolves within 15 min, OR escalate to `/vibing-with-ntm` OC-003 stuck-pane ladder.
