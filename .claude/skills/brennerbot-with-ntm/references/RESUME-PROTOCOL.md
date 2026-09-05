# RESUME-PROTOCOL.md — RESUME.md Grammar + Verification

<!-- TOC: Schema | Producing the RESUME.md (Phase 8) | Consuming the RESUME.md | Hash Verification Failure Modes | Resume Token Versioning | What MO-resume.md Tells the Pane | Anti-Patterns in Resume | Resume Modes -->

`RESUME.md` is the single source of truth for resuming a session. Phase 8 produces it; `scripts/resume-session.sh --resume RESUME.md` consumes it.

The protocol is *idempotent*: resume can be called any number of times; it never destroys workspace state.

---

## Schema

```yaml
session_id: RS-<YYYYMMDD>-<slug>
session_label: <one-line label>
mode_to_resume: fresh-pass | targeted-investigation | distillation-only | drift-check | audit-only
last_phase_completed: <int 1..10>
created_at: <ISO-8601>
operator_signature: <free-text — usually the operator email>

question_of_record_path: intake/question_of_record.md
question_of_record_hash: <sha256>

corpus_index_path: corpus/corpus_index.md
corpus_index_hash: <sha256>

# REQUIRED top-level mirror of distillations.disagreement_register.hash. The
# resume verifier (scripts/resume-session.sh:67) reads this via parse_field,
# which only inspects root-level YAML scalars; without the mirror, every
# resume errors with "disagreement_register_hash: hash or path empty in
# RESUME.md". The two values must match.
disagreement_register_hash: <sha256>

beads_head_sha: <git sha of last commit touching .beads/>
ntm_checkpoint_archive: .ntm/checkpoints/<id>.tar.gz
ntm_checkpoint_id: <ntm-assigned id>

distillations:
  per_model:
    - by: cc
      path: distillations/by_cc.md
      hash: <sha256>
    - by: cod
      path: distillations/by_cod.md
      hash: <sha256>
    - by: gmi
      path: distillations/by_gmi.md
      hash: <sha256>
  meta:
    path: distillations/meta_synthesis.md
    hash: <sha256>
  disagreement_register:
    path: distillations/disagreement_register.md
    hash: <sha256>

roster:
  - pane: 1
    role: proposer
    model: cc
    productive_ignorance: true
    last_thread: RS-...-onboard-p1
  - pane: 2
    role: investigator
    model: cod
    domain: [H-001, H-005]
    last_thread: RS-...-H-001
  - pane: 3
    role: investigator
    model: cc
    domain: [H-002, H-007]
    last_thread: RS-...-H-002
  - pane: 4
    role: devils-advocate
    model: gmi
    last_thread: RS-...-DEBATE-H-005-vs-H-007
  - pane: 5
    role: synthesizer
    model: cc
    last_thread: RS-...-META-DISTILL

agent_mail:
  available: true
  threads_open:
    - id: RS-20260506-event-log-H-005
      participants: [p2, p4]
      last_post_at: <ISO-8601>
    - id: RS-...-DEBATE-H-005-vs-H-007
      ...

open_threads:
  - bead: H-005
    state: confirmed
    next_action: "Verify scale-physics calculation for assumption A-003"
    owner_pane: p3
  - bead: H-009
    state: deferred
    next_action: "Reopen if Phase 4 round 6 surfaces evidence; otherwise close"
    owner_pane: null

audit_findings_open:
  - id: AF-002
    severity: high
    target: distillations/by_cc.md § Operators
    next_action: "Operator ⊞ never applied in cc distillation; investigate why"

next_loop_recommendation:
  phase: 4 | 6 | 7 | 10
  duration_estimate_hours: <float>
  reason: "<why this phase next>"

resume_token_version: 1.0
```

---

## Producing the RESUME.md (Phase 8)

`MO-08-freeze.md` dispatches one pane to write the RESUME.md. The script `scripts/dump-session-report.sh --emit-resume` produces a draft RESUME.md from the workspace; the pane verifies and adds free-text fields (`session_label`, `next_loop_recommendation.reason`).

Hash computation:

```bash
sha256sum intake/question_of_record.md | awk '{print $1}'
```

Beads head:

```bash
cd <workspace> && git log -1 --format=%H -- .beads/
```

ntm checkpoint:

```bash
ntm checkpoint save <SESSION_ID> -m "Phase 8 freeze"
mkdir -p .ntm/checkpoints
ntm checkpoint export <SESSION_ID> <id> --output=.ntm/checkpoints/<id>.tar.gz
```

---

## Consuming the RESUME.md (script: `resume-session.sh`)

```bash
./scripts/resume-session.sh --resume <workspace>/deliverables/RESUME.md
```

The script:

1. Verifies hashes (every `_hash` field must match the current file content). Mismatch → abort with diff.
2. Verifies `beads_head_sha` is reachable in `.beads/`. If not → abort.
3. Verifies `ntm_checkpoint_archive` exists. If not → warn (operator may need to manually re-spawn panes).
4. If MCP Agent Mail is available, `register_agent` for each pane in `roster` (re-attaches identity).
5. Spawns / restores ntm session: `ntm checkpoint restore <SESSION_ID> <ntm_checkpoint_id>` if archive present, otherwise `ntm spawn` per roster.
6. Per pane in `roster`, dispatches `MO-resume.md` with parameters:
   - `<PANE_N>`, `<ROLE>`, `<DOMAIN>`, and `<LAST_THREAD>` from that pane's `roster:` entry
   - `<LAST_PHASE_COMPLETED>` = from the RESUME.md header
   - `<MODE_TO_RESUME>` = from RESUME.md header
   - `<NEXT_PHASE>` = from `last_phase_completed + 1` (or per `next_loop_recommendation.phase`)
7. Logs the resume in `session-logs/resume-<timestamp>.md`.

---

## Hash Verification Failure Modes

| Failure | Cause | Recovery |
|---------|-------|----------|
| `question_of_record_hash mismatch` | The question was edited after Phase 8 freeze | Operator decides: accept new question (full re-frame, MO-01 again) or revert |
| `corpus_index_hash mismatch` | Corpus changed | F-102 corpus drift; pin new SHA in fresh corpus_index and decide if hypotheses survive |
| `disagreement_register_hash mismatch` | Distillations were edited post-freeze | Re-run Phase 6 meta-synthesis (the disagreement register is *the* artifact of Phase 6) |
| `beads_head_sha unreachable` | History was rewritten (force-push, hard reset) | DO NOT auto-recover; flag to operator with the orphan SHA from `git reflog` |
| `ntm_checkpoint_archive missing` | Cleanup or export failure | Re-spawn panes from scratch via `ntm spawn`; pane-level scrollback is lost but bead state survives |

---

## Resume Token Versioning

The `resume_token_version` field in RESUME.md is the schema version. v1.0 is the initial. When the schema changes:

- **Backwards-compatible additions** (new optional fields): bump to 1.x.
- **Breaking changes** (renamed/removed fields, restructured schema): bump to 2.0; `resume-session.sh` must support migration.

Migration logic lives in `scripts/resume-session.sh § migrate_token_v1_to_v2()`. The skill should never invisibly upgrade an old RESUME.md — always log the migration and ask operator to confirm.

---

## What `MO-resume.md` Tells the Pane

The post-resume marching order is brief — the pane already has its workspace, beads, mail threads (if Agent Mail). It just needs to know:

```
You are pane <PANE_N>. This is a RESUMED session: RS-...-<slug>.

You were previously the <ROLE> for <DOMAIN if any>. Your last thread was <LAST_THREAD>.

The session is at phase <NEXT_PHASE> ready to begin (last completed phase: <LAST_COMPLETED>).

Per the operator's resume request, your immediate task is: <RESUME_INSTRUCTION>.

Refresh state:
1. `br show <YOUR_DOMAIN_H-IDS>` — see current state of your hypotheses.
2. `ntm mail inbox <session> --json` — check for any messages from the prior session.
3. `git log --oneline -20` — review the last commits to understand prior pane work.

Then resume. Same SHIP-OR-SURFACE SLA as before: within 60 minutes commit a real artifact or surface a specific blocker.
```

---

## Anti-Patterns in Resume

| ✗ | Why |
|---|-----|
| Resuming without verifying hashes | Workspace drift makes the resume incoherent |
| Ignoring `next_loop_recommendation` and re-running the same phase | The recommendation encodes operator judgment about what to do next; ignoring it loses session memory |
| Dispatching the OLD onboarding (MO-02) instead of MO-resume | Wastes context on re-introduction; the pane already knows the workspace |
| Re-creating Agent Mail threads with new IDs | Breaks thread continuity; reuse the original thread IDs |
| Cleaning the workspace before resuming | Phase 8 froze the workspace; cleaning destroys the session memory |
| Treating an old RESUME.md as authoritative for current state | The RESUME.md is a *snapshot* — current state may have moved if the workspace was edited; verify with hashes |

---

## Resume Modes

The `mode_to_resume` field directs `resume-session.sh` to which phase to enter:

| Mode | Effect |
|------|--------|
| `fresh-pass` | Re-enter at `last_phase_completed + 1`; full Phase 4 round, etc. |
| `targeted-investigation` | Re-enter Phase 4 only on specific H-IDs listed in `open_threads` |
| `distillation-only` | Re-enter Phase 6; assume Phases 1–5 are frozen |
| `drift-check` | Skip to Phase 10 only |
| `audit-only` | Re-enter Phase 7 only; produce another audit pass |

Mode determines which marching orders are dispatched and which panes are required.
