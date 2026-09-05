# MO-resume.md — Brief a Pane After resume-session.sh

**Phase:** post-resume (entry to whatever phase RESUME.md indicates)
**Parameters:** `<PANE_N>`, `<ROLE>`, `<DOMAIN>`, `<LAST_THREAD>`, `<LAST_PHASE_COMPLETED>`, `<MODE_TO_RESUME>`, `<NEXT_PHASE>`, `<SESSION_ID>`

The placeholders are FLAT (`<ROLE>` not `<RESUME_TOKEN.role>`) because `dispatch-marching-order.sh` does literal placeholder substitution from `--PLACEHOLDER=value` flags. `resume-session.sh` extracts these per-pane from the parsed RESUME.md roster and dispatches one MO per pane.

---

You are pane `<PANE_N>`. This is a **RESUMED** session.

**Step 1 — You already have context.**

You were previously the **`<ROLE>`** for this session. Your domain (if applicable) was `<DOMAIN>`. Your last thread was `<LAST_THREAD>`.

The session is now at **Phase `<NEXT_PHASE>`** ready to resume. Last completed phase: `<LAST_PHASE_COMPLETED>`.

**Step 2 — Refresh state (≤5 minutes).**

```bash
h_refs="<your relevant H refs, space-separated>"  # e.g. H-001 H-005
for h_ref in $h_refs; do
  h_id="$(br list --all --json | jq -r --arg ref "$h_ref" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' | head -1)"
  [ -n "$h_id" ] && br show "$h_id" --json
done
ntm mail inbox <SESSION_ID> --json | jq -r '.messages[]? | select((.thread_id // .thread // "") == "<LAST_THREAD>")'
git log --oneline -20             # what happened since you last worked
```

Do NOT re-read the corpus / question of record / AGENTS.md unless your context was wiped (post-compaction). The hashes in RESUME.md verify the workspace is unchanged from your last session.

**Step 3 — Resume mode.**

Per `<MODE_TO_RESUME>`:

| Mode | Your immediate task |
|------|---------------------|
| `fresh-pass` | Resume at Phase `<NEXT_PHASE>` per the phase's standard MO. The operator will dispatch your phase-specific MO next. |
| `targeted-investigation` | Phase 4 only on H-IDs in RESUME.md `open_threads`. Pick the open thread assigned to you (`owner_pane: <PANE_N>` in RESUME.md); apply MO-04a-investigate.md to it. |
| `distillation-only` | Phase 6 only. If you're a Synthesizer, apply MO-06a-distill.md afresh. |
| `audit-only` | Phase 7 only. Apply MO-07a-fresh-eyes.md (this is a *new* trio-round). |
| `drift-check` | Skip — Phase 10 is dispatched to a fresh general-purpose Agent, not to swarm panes. You stand by or shut down. |

**Step 4 — Apply Ship-or-Surface SLA.**

Same as fresh sessions: within 60 minutes, ship a real artifact OR surface a specific blocker.

**Step 5 — Reply to operator.**

```
Pane <PANE_N> ready, role=<ROLE>, mode=<MODE_TO_RESUME>, target=<H_ID or N/A>.
Refreshed: [<list of beads / threads checked>]
Awaiting phase-specific dispatch.
```

---

**Anti-patterns to avoid:**

- ✗ Re-introducing yourself in Agent Mail. Your `register_agent` was re-attached by `resume-session.sh`. The peer panes know you.
- ✗ Re-creating threads with new IDs (per AP-O10). Reuse the `<LAST_THREAD>` value the operator passed.
- ✗ Re-reading the question of record from scratch (wastes ~30s/tick of context). Skip unless post-compaction.
- ✗ Treating `<NEXT_PHASE>` as Phase 1 framing. Phase 1 was already done; the question of record is settled.

**Ship-or-Surface SLA:** within 5 minutes, the ack reply. Within 60 minutes of phase-specific dispatch, the first artifact.
