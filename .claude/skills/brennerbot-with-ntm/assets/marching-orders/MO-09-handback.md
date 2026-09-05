# MO-09-handback.md — One-Page Operator Briefing

**Phase:** 9
**Operators activated:** ≡ Invariant-Extract (one final pass)
**Parameters:** `<PANE_N>`, `<SESSION_ID>`, `<WORKSPACE_PATH>`, `<SKILL_SCRIPTS>`

---

You are pane `<PANE_N>` (Synthesizer or operator). Your job: produce `deliverables/HANDBACK.md`, the one-page operator briefing.

**Hard limit: 1 page (≤80 lines).** If yours runs longer, compress.

---

**Step 1 — Read the inputs.**

```bash
cat <WORKSPACE_PATH>/intake/question_of_record.md
cat <WORKSPACE_PATH>/distillations/meta_synthesis.md
cat <WORKSPACE_PATH>/distillations/disagreement_register.md
br list --label=hypothesis --json | jq '.issues[]?'
br list --label=audit-finding --status=open --json | jq '.issues[]?'
cat <WORKSPACE_PATH>/deliverables/RESUME.md
```

**Step 2 — Apply ≡ Invariant-Extract one final time.**

What's the kernel claim of this session? What did we learn that holds independent of the surviving H?

**Step 3 — Write `HANDBACK.md` with these sections.**

```markdown
# Handback — <SESSION_ID>

**Question:** <one-sentence verbatim from question_of_record.md>

## TL;DR (3 sentences)
<sentence 1: the verdict>
<sentence 2: the load-bearing evidence>
<sentence 3: the one open thread that matters most>

## What we found (≤8 bullets)
- **Kernel invariants** (≥1 from meta_synthesis.md): <invariant>
- **Confirmed hypothesis** (if any): H-NNN — <claim summary>
- **Refuted hypotheses** (count + summary): <count>; e.g., H-NNN refuted by EV-NNN ("...")
- **Notable disagreement among model families:** D-NNN — <subject>
- **Anomalies** (if any clustered): AN-NNN — <observation>
- **Methodology improvements** (if any): operator X applied effectively at Y

## What's still open (≤6 bullets, each with next-action)
- H-NNN (state: deferred): next-action: <specific>
- EV-NNN (unverified): next-action: <how to verify>
- AF-NNN (audit finding deferred): next-action: <fix>
- D-NNN (disagreement unresolved): next-action: <which evidence would settle it>

## Recommended next loop
- **Phase to re-enter:** <4 / 6 / 7 / 10 / none — converged>
- **Estimated duration:** <hours>
- **Reason:** <one sentence>

To run: `<SKILL_SCRIPTS>/resume-session.sh --resume <WORKSPACE_PATH>/deliverables/RESUME.md`

## Risk register (≤3 items)
- <risk 1, with mitigation>
- <risk 2, with mitigation>
- <risk 3, with mitigation>

---

**Session metadata:**
- Workspace: <WORKSPACE_PATH>
- Mode: <mode>
- Roster tier: <tier>
- Wall time: <hours>
- Phases completed: 1–<N>
- Beads filed: <count>
- Evidence packs: <count>
```

**Step 4 — Verify every listed unresolved thread has a next-action.**

```bash
<SKILL_SCRIPTS>/audit-bead-invariants.sh --check=handback_open_thread_tags --workspace=<WORKSPACE_PATH>
```

If any `H-*`, `EV-*`, `AF-*`, or `D-*` listed under "What's still open" lacks a `next-action:` in HANDBACK.md, F-902 fires. Add the missing tags.

**Step 5 — Verify ≤80 lines.**

```bash
wc -l <WORKSPACE_PATH>/deliverables/HANDBACK.md
```

If >80, compress. Drop adjectives, fold bullets, kill explanations the operator can derive from `meta_synthesis.md`.

**Step 6 — Commit.**

```bash
cd <WORKSPACE_PATH>
git add deliverables/HANDBACK.md
git commit -m "Phase 9: handback briefing"
```

**Step 7 — Mark phase complete.**

```bash
echo "Phase 9 complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > <WORKSPACE_PATH>/.brenner_workspace/phase_9_complete.flag
```

**Step 8 — Offer the next loop.**

Reply to the operator:

```
HANDBACK.md ready. ≤<N> lines.

Recommended next loop: <phase>, ~<hours>h.

Run with:
  <SKILL_SCRIPTS>/resume-session.sh --resume <WORKSPACE_PATH>/deliverables/RESUME.md

Or skip to Phase 10 drift-check:
  (operator dispatches subagents/drift-auditor.md to fresh general-purpose Agent)

Or close the session as converged: no further action needed.
```

---

**Anti-patterns to avoid:**

- ✗ Exceeds 1 page (F-901). Compress; the value of a one-pager *is* one page.
- ✗ TL;DR with hedging ("perhaps", "it seems"). Pick a verdict; if no verdict, say "no convergent verdict — see disagreement_register.md".
- ✗ Listed unresolved threads without next-action (F-902). Mandatory.
- ✗ "Recommended next loop: TBD" (F-903). Pick one. "None — converged" is a valid pick.
- ✗ Risk register with vague risks ("things might go wrong"). Specific risks with specific mitigations.

**Ship-or-Surface SLA:** within 30 minutes, deliver `HANDBACK.md` ≤80 lines.
