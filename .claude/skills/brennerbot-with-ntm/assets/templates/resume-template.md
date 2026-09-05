# RESUME.md template (YAML body)

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

# Top-level mirror of distillations.disagreement_register.hash so
# resume-session.sh can verify the disagreement register via parse_field
# (which only reads root-level keys). The two values must match.
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
      participants: [p2, p4, p5]
      last_post_at: <ISO-8601>

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
  phase: 4 | 6 | 7 | 10 | none-converged
  duration_estimate_hours: <float>
  reason: "<why this phase next>"

resume_token_version: 1.0
```

---

## Hash computation

```bash
sha256sum intake/question_of_record.md | awk '{print $1}'
```

## Beads head

```bash
cd <workspace> && git log -1 --format=%H -- .beads/
```

## ntm checkpoint

```bash
ntm checkpoint save <SESSION_ID> -m "Phase 8 freeze"
mkdir -p .ntm/checkpoints
ntm checkpoint export <SESSION_ID> <id> --output=.ntm/checkpoints/<id>.tar.gz
```

---

## Validation

Before promoting `RESUME.md.draft` → `RESUME.md`:

```bash
SKILL_SCRIPTS=/path/to/brennerbot-with-ntm/scripts
"$SKILL_SCRIPTS/resume-session.sh" --dry-run --resume RESUME.md.draft
```

Must exit 0.
