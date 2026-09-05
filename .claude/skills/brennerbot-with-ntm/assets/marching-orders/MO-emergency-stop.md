# MO-emergency-stop.md — Operator-Initiated Emergency Halt

**Phase:** any
**Operators activated:** none (this is a halt, not a methodology operator)
**Parameters:** `<SESSION_ID>`, `<WORKSPACE_PATH>`, `<SKILL_SCRIPTS>`, `<REASON>` (categorical: time-pressure | budget-cap | methodology-collapse | external-event | user-redirect | other), `<DETAIL>` (one-paragraph)

---

You (the operator) are stopping the session deliberately. This is the safe-shutdown protocol — distinct from convergence (which is "we're done") and from abandonment (which is "we're giving up without record").

---

**Step 1 — Verify the stop decision.**

Re-read `<REASON>` and `<DETAIL>`. Valid reasons:

- `time-pressure` — wall-time budget exceeded; user needs answer now even partial
- `budget-cap` — tier hard cap hit; can't justify continuing
- `methodology-collapse` — multiple F-### codes firing; can't recover within budget
- `external-event` — something outside the session changed (user redirect, infrastructure failure, conflicting priority)
- `user-redirect` — user explicitly asked to stop or redirect
- `other` — document specifically

If reason is fuzzy ("we should stop"), make it specific OR don't stop yet.

**Step 2 — Snapshot current state.**

```bash
# Save current state for resumability later
mkdir -p <WORKSPACE_PATH>/session-logs
STOP_REPORT="<WORKSPACE_PATH>/session-logs/emergency-stop-$(date -u +%Y%m%dT%H%M%SZ).md"
"<SKILL_SCRIPTS>/dump-session-report.sh" --workspace=<WORKSPACE_PATH> > "$STOP_REPORT"
"<SKILL_SCRIPTS>/tick.sh" <WORKSPACE_PATH> >> "$STOP_REPORT" 2>&1
cd <WORKSPACE_PATH>
br sync --flush-only
git add session-logs/ .brenner_workspace/ .beads/ deliverables/
git status
git commit -m "Emergency stop: <REASON>" || true
```

**Step 3 — Notify panes.**

Send to all panes via `ntm --robot-send=<session> --all --msg=...`:

```
EMERGENCY STOP at $(date -u +%Y-%m-%dT%H:%M:%SZ).

Reason: <REASON>
Detail: <DETAIL>

Stop current work IMMEDIATELY. Do NOT file new beads. Do NOT post new mail.

Current state has been snapshotted. The session can be resumed via RESUME.md.

Stand by for further instructions or pane shutdown.
```

**Step 4 — Run a partial Phase 8 freeze.**

Even though we're stopping early, produce a RESUME.md so the session can resume:

```bash
# Portable sha256: GNU/Linux ships `sha256sum`; macOS/BSD ships `shasum -a 256`.
sha256() { command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"; }

cd <WORKSPACE_PATH>
ntm checkpoint save <SESSION_ID> -m "Emergency stop: <REASON>"
NTM_CHECKPOINT_ID=$(ntm checkpoint list <SESSION_ID> --json | jq -r '.checkpoints[-1].id')
mkdir -p .ntm/checkpoints
ARCHIVE_PATH=".ntm/checkpoints/${NTM_CHECKPOINT_ID}.tar.gz"
ntm checkpoint export <SESSION_ID> "$NTM_CHECKPOINT_ID" --output="$ARCHIVE_PATH"

"<SKILL_SCRIPTS>/dump-session-report.sh" --emit-resume --workspace=<WORKSPACE_PATH> \
  --session="<SESSION_ID>" \
  --qor-hash=$(sha256 <WORKSPACE_PATH>/intake/question_of_record.md 2>/dev/null | awk '{print $1}') \
  --corpus-hash=$(sha256 <WORKSPACE_PATH>/corpus/corpus_index.md 2>/dev/null | awk '{print $1}') \
  --disagreement-hash=$(sha256 <WORKSPACE_PATH>/distillations/disagreement_register.md 2>/dev/null | awk '{print $1}') \
  --beads-head=$(git log -1 --format=%H -- .beads/ 2>/dev/null) \
  --checkpoint-archive="$ARCHIVE_PATH" \
  --checkpoint-id="$NTM_CHECKPOINT_ID" \
  > <WORKSPACE_PATH>/deliverables/RESUME.md.draft
```

Add explicit annotation to RESUME.md:

```yaml
emergency_stop_at: <ISO-8601>
emergency_stop_reason: <REASON>
emergency_stop_detail: <DETAIL>
mode_to_resume: emergency-resume
last_phase_completed: <best estimate; conservative>
incomplete_phase: <which phase was active>
incomplete_work:
  - <description of in-flight investigation>
  - <description of pending Phase X step>
```

Promote draft to `RESUME.md`.

**Step 5 — Write a partial HANDBACK.**

Even partial results have value:

```markdown
# Emergency Handback — <SESSION_ID>

**STATUS: SESSION STOPPED EARLY at <ISO-8601>**

**Reason:** <REASON> (<DETAIL>)

## What we found so far

(Partial results; cite specific Hs, EVs, audit findings)
- ...

## What's incomplete

- Phase <N>: <what was in flight>
- Active Hs not yet adjudicated: <list>
- Audit findings open: <list with severity>

## Recommended path forward

Either:
1. Resume via RESUME.md when conditions allow (estimated wall time: <H>h to complete)
2. Accept current partial state as best-available answer; note caveats
3. Reframe and start new session (if methodology collapse was the cause)

## Volatile-source caveat

(If applicable)

## Risk register

- Acting on partial results: risk = <one sentence>
- Waiting for full session: risk = <one sentence>
```

**Step 6 — Optionally kill panes.**

Per operator decision:

- **Pause panes:** `ntm --robot-send=<session> --all --msg="stand by; await resume"` — leaves panes alive for fast resume
- **Kill session:** `ntm kill <session>` — frees resources; resume requires re-spawn

For `time-pressure` or `external-event`, prefer pause (resume soon expected). For `budget-cap` or `methodology-collapse`, prefer kill.

**Step 7 — Mark phase flags.**

For each phase that was COMPLETE, ensure `phase_<N>_complete.flag` exists. For the active phase, do NOT create the flag (it would falsely indicate completion).

**Step 8 — Commit and inform user.**

```bash
git add deliverables/HANDBACK-EMERGENCY.md session-logs/ .brenner_workspace/ .beads/
git status
git commit -m "Emergency stop: <REASON>; partial handback at deliverables/HANDBACK-EMERGENCY.md"
```

Tell the user:

```
Session stopped at phase <N> due to <REASON>.

Partial results: deliverables/HANDBACK-EMERGENCY.md
Resume token: deliverables/RESUME.md (mode: emergency-resume)

Confidence in partial results: <low | partial | substantial>
Recommended action: <resume | accept partial | reframe>
```

---

**Anti-patterns:**

- ✗ Stop without snapshot — destroys resumability
- ✗ Skip the partial HANDBACK — user has no way to act on partial work
- ✗ Don't tell panes — they keep working past the operator's decision
- ✗ Mark all phases complete to fake convergence — Phase 10 drift will catch this and it's worse than honest partial
- ✗ Stop without categorical reason — drift-check can't categorize the stop pattern

**Ship-or-Surface SLA:** within 10 min of decision, full snapshot + partial handback + RESUME.md + git commit.
