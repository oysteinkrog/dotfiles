# AGENT-MAIL-CONVENTIONS.md — Thread Schema & Body Conventions

<!-- TOC: Thread-ID Schema | Per-Thread Body Conventions | Summary | Evidence cited | Operator applied | Next action | Outcome | Reasoning | Falsifier event | Bead state changes | Findings | File Reservations | Macros to Prefer | Pre-Commit Guard | Failure Modes & Recovery -->

Brenner's "conversational science" (§66, §167) is the substrate for cross-pane debate. We operationalize it as Agent Mail thread discipline: each thread has a known shape, expected participants, and body conventions that the adjudicator can validate.

---

## Thread-ID Schema

```
RS-<YYYYMMDD>-<slug>                  # main session thread
RS-<YYYYMMDD>-<slug>-H-<NNN>          # per-hypothesis thread (one per surviving H)
RS-...-DEBATE-<H_I>-vs-<H_J>          # pairwise debate (e.g. RS-20260506-event-log-DEBATE-H-001-vs-H-002 — bead IDs interpolated, hyphens preserved)
RS-...-INVEST-coord                   # investigation coordination
RS-...-ADJUDICATE                     # consolidated adjudication
RS-...-AUDIT-p<N>                     # per-pane fresh-eyes audit
RS-...-META-DISTILL                   # meta-distillation
RS-...-DRIFT                          # methodology drift check
RS-...-onboard-p<N>                   # onboarding ack thread (per pane)
```

**Placeholder convention.** `<H_I>` and `<H_J>` are the *actual hypothesis bead IDs* (e.g., `H-001`, `H-014`) — interpolated verbatim with their hyphens preserved. Earlier docs spelled this `Hi-vs-Hj` as a free-text shorthand; that was misleading because pane-side substitution produces `H-001-vs-H-002`, not the literal `Hi-vs-Hj`. The canonical MO templates (`MO-05a-cross-exam.md`, `MO-05b-adjudicate.md`) all use the `<H_I>-vs-<H_J>` form.

**Subjects ALWAYS prefix with `[<thread-id>]`** so the inbox can be filtered:

```
[RS-20260506-event-log-H-005] Investigator pack v1: 3 supporting EVs, 1 attempted falsifier missed
```

---

## Per-Thread Body Conventions

### Per-hypothesis thread (`RS-...-H-NNN`)

**Participants:** the assigned Investigator (primary), Devil's-Advocate (when active), Adjudicator (final round only).

**Body schema for posts:**

```markdown
**Pane:** <pane-id>  **Role:** investigator | devils-advocate | adjudicator
**Round:** <int>
**Beads referenced:** EV-001, EV-007, T-002

## Summary
<3-5 sentence summary of what this post adds>

## Evidence cited (must be ≥1 for non-summary posts)
- EV-001: <one-line claim + file path>
- EV-007: <...>

## Operator applied
- ⌂ Materialize: confirmed expected_evidence at <file:line>
- ✂ Exclusion-Test: probed falsifier; result <not seen | seen>

## Next action
<specific, observable next step>
```

**Adjudicator-rejection rule:** posts WITHOUT a `## Evidence cited` block (≥1 EV-NNN) are auto-rejected. The investigator/advocate must re-post with citations.

---

### Pairwise debate thread

Thread ID format: `RS-...-DEBATE-<H_I>-vs-<H_J>` (e.g., `RS-20260506-event-log-DEBATE-H-001-vs-H-002` — bead IDs interpolated verbatim with hyphens preserved).

**Participants:** two Champions (one per H, ideally different model families per 🤝 GAN). Adjudicator joins at the end.

**Round structure** — strictly enforced; Adjudicator rejects out-of-round posts:

| Round | Champion-Hi posts | Champion-Hj posts |
|-------|------------------|------------------|
| 1 | `[opening]` Hi case (≤300 words) | `[opening]` Hj case (≤300 words) |
| 2 | `[rebuttal]` attacking Hj's opening | `[rebuttal]` attacking Hi's opening |
| 3 | `[counter-rebuttal]` defending Hi against Hj's rebuttal | `[counter-rebuttal]` defending Hj |
| 4 | (silent) | (silent) |
| Final | (silent) | (silent) |

**Adjudicator post (round Final):**

```markdown
**Adjudicator:** <pane-id>  **Adjudicating:** DEBATE-NNN

## Outcome
H-<i> = <confirmed | refuted | superseded | deferred>
H-<j> = <confirmed | refuted | superseded | deferred>

## Reasoning
<paragraph citing specific EV-NNN that fired falsifiers or supported claims>

## Falsifier event (if any)
- H-<i>.falsifier was: "<verbatim falsifier>"
- Observed via EV-<NNN> (<source>): "<verbatim quote>"
- Conclusion: H-<i> killed.

## Bead state changes
- H-<i> `state: refuted`
- H-<i> `refuted_by: EV-<NNN>`
- DEBATE-<NNN> `state: settled`
```

**Hard cap:** 3 rounds before adjudicator MUST rule. If both champions still want more, that's a Phase 4 reopen — file a new `T-*` test and exit the debate.

---

### Investigation coordination thread (`RS-...-INVEST-coord`)

**Participants:** all Investigators + Devil's-Advocates.

**Use cases:**

- Cross-pane handoff: "I claim H-007's investigation; releasing H-003 to whoever wants it."
- Reservation conflict: "Two of us are working on `corpus/ingested/paper-12.md`; reserving lines 200-400 for me."
- Cross-cutting evidence: "EV-019 supports BOTH H-005 AND H-011 — flagging."

**Body convention:** brief; always cite the bead id you're claiming/releasing/flagging.

---

### Adjudication thread (`RS-...-ADJUDICATE`)

**Participants:** all Adjudicators (rotating role).

**Use cases:**

- Cross-debate consistency: "I just adjudicated DEBATE-002 confirmed H-005; checking that doesn't conflict with DEBATE-001's adjudication."
- Anomaly cluster check: "AN-003 and AN-008 share feature X; spawning H-NNN with origin:anomaly_spawned."
- Phase 5 exit decision: "All H states finalized. Phase 5 ready to exit."

---

### Per-pane audit thread (`RS-...-AUDIT-p<N>`)

**Participants:** one pane (the auditor).

**Body convention:** every audit finding cites a specific artifact file + bead. Rejected if vibes-only.

```markdown
**Auditor pane:** <pane-id>  **Round:** <int>  **Prompt:** 1 | 2 | 3 (which trio prompt)

## Findings (severity-tagged)
- [CRITICAL] `evidence/packs/EV-pack-H-005.md § Methodology` — citation `[ref]` doesn't exist
- [HIGH] `H-007` — falsifier "X" is unfalsifiable in practice (no observation could ever fire it)
- [MEDIUM] `distillations/by_cc.md § Operators` — operator ⊞ Scale-Check listed but never applied
- [LOW] typo in `intake/question_of_record.md` line 14
```

---

### Meta-distillation thread (`RS-...-META-DISTILL`)

**Participants:** all Synthesizers + Meta-synthesizer.

**Body convention:** structured around `disagreement_register.md` entries. Every disagreement entry must have:

- The point under dispute (one sentence)
- cc reading (citing `distillations/by_cc.md § X`)
- cod reading (citing `distillations/by_cod.md § X`)
- gmi reading (citing `distillations/by_gmi.md § X`)
- Chosen synthesis (with reasoning)

---

## File Reservations

When investigators are filling evidence packs or synthesizers are merging distillations:

```
file_reservation_paths(
  project_key="<workspace-path>",
  agent_name="<agent-mail-name-for-pane>",
  paths=["evidence/packs/EV-pack-H-007.md"],
  ttl_seconds=3600,
  exclusive=true,
  reason="<thread-id>"
)
```

Pane IDs (`p1`, `p2`, ...) are local NTM labels. Agent Mail `agent_name` is the
registered name returned by `register_agent`; record the pane -> Agent Mail name
mapping in `phase0_scope_decision.md` during onboarding.

**Conflict resolution:**

- Oldest claim wins.
- Loser **flips role** to devil's-advocate against the winner's hypothesis (this is a *feature* — accelerates Phase 5).
- If reservation expires mid-edit, the loser's edits are queued for review — not silently overwritten.

---

## Macros to Prefer

For speed, prefer macros over granular tools:

```text
# Phase 2 onboarding:
macro_start_session(
  human_key="<workspace-path>",
  program="<program-for-this-cli>",
  model="<actual-model-or-family>",
  task_description="brennerbot pane <PANE_N> role <ROLE>"
)

# Phase 4 file claim:
macro_file_reservation_cycle(
  project_key="<workspace-path>",
  agent_name="<agent-mail-name-for-pane>",
  paths=["evidence/packs/EV-pack-H-007.md"],
  ttl_seconds=3600,
  exclusive=true,
  reason="RS-...-H-007"
)

# Cross-repo (e.g., source corpus is in different repo):
macro_contact_handshake(
  project_key="<workspace-path>",
  requester="<agent-mail-name-for-pane>",
  target="<target-agent-name>",
  to_project=<corpus-repo>,
  reason="brennerbot corpus coordination"
)
```

Use `send_message(...)` separately when you need to announce the reservation or
post into a specific thread; the reservation macro does not send thread mail.

---

## Pre-Commit Guard

When MCP Agent Mail is available, install the pre-commit guard:

```bash
am guard status .
am guard install .
```

The guard prevents committing changes to files with active reservations held by other panes. This catches Phase 4 cross-pane collisions automatically.

If the guard blocks a commit unexpectedly, the operator inspects via `am mail status .` and resolves via `release_file_reservations` (with reason) or `force_release_file_reservation` (last resort, audit-logged).

---

## Failure Modes & Recovery

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `from_agent not registered` | Pane skipped Phase 2 onboarding | Re-dispatch `MO-02-onboarding.md` to that pane |
| `FILE_RESERVATION_CONFLICT` | Two panes claimed same path | Adjust pattern, wait for expiry, or apply oldest-wins rule |
| Mail server unavailable | MCP Agent Mail server down | Fall back to `ntm-inbox` per [AGENT-MAIL-FALLBACKS.md](AGENT-MAIL-FALLBACKS.md); flag in scope_decision |
| Adjudicator never sees debate posts | Subject not prefixed with thread-id | Force template compliance |
| Mail thread has 50+ posts | Debate ran past 3 rounds | Hard exit to Phase 4 reopen with new test |
| Posts without `## Evidence cited` block | Convergence-language failure mode | Auto-reject; require resubmit with citations |
