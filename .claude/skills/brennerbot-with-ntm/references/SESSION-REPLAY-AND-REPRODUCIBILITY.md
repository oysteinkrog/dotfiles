# SESSION-REPLAY-AND-REPRODUCIBILITY.md — Recording Sessions for Deterministic Replay

<!-- TOC: Why session replay | NTM-native replay stack | The SessionRecord schema | Inputs vs trace vs outputs | Content hashing | Replay modes | Per-purpose use cases | The reproducibility tarball | Cross-session diffing | Anti-patterns | Cross-references -->

A session that can't be replayed can't be debugged, can't be reproduced, and can't be used to evaluate model differences. Brennerbot needs **deterministic session replay** as a first-class capability: every session produces a `SessionRecord` JSON that captures *enough* to reconstruct what happened.

This file specifies the SessionRecord schema, hashing strategy, replay modes, and the use cases.

Mined from `/dp/brenner_bot/specs/session_replay_spec_v0.1.md` and `/dp/brenner_bot/CHANGELOG.md` v0.4.0, then updated for current NTM robot replay, causality, pipeline state, event feeds, and support bundles.

---

## Why session replay

Four distinct use cases:

1. **Deterministic reproducibility** — "can someone else replicate this research?" — for T4+ sessions, mandatory
2. **Debugging divergence** — "why did two operators produce different verdicts on the same question?"
3. **Agent / model evaluation** — "how does cc compare to cod on this session?" — replay with different model
4. **Training and onboarding** — "new operators shadow historical sessions step-by-step"

A natural-language transcript can support 1 weakly. Only structured replay supports all 4.

---

## NTM-native replay stack

The TypeScript-style `SessionRecord` below remains the methodology schema. In current NTM runs, the live replay/debug truth comes from five robot surfaces:

| Surface | Use |
|---|---|
| `ntm --robot-events --since-cursor=<cursor> --events-limit=100` | Raw attention-feed replay after a known cursor. Use for full history/debug, not routine tending. |
| `ntm --robot-causality=<session> --causality-project=<workspace>` | Unified audit + Agent Mail + pipeline/session timeline, with filters for bead, pane, type, chain, and time window. |
| `ntm --robot-pipeline=<run-id>` / `ntm pipeline status <run-id> --json` | Step status, timings, persisted outputs, foreach iteration results, resume boundary, and failure reasons. |
| `ntm --robot-history=<session>` + `ntm --robot-replay=<session> --replay-id=<id> --replay-dry-run` | Re-run a concrete command from NTM history after previewing the exact replay. |
| `ntm --robot-support-bundle=<session> --bundle-since=1h --bundle-output=<path>` | Freeze redacted diagnostic evidence for handoff, bug reports, or post-mortems. |

Pipeline state lives under `.ntm/pipelines/<run-id>.json`. Current NTM resume preserves completed step outputs by default, including foreach iteration outputs; use force/start-from modes only when deliberate replay is more important than preserving the original run boundary.

Default operator sequence after context loss:

```bash
ntm --robot-snapshot
ntm --robot-attention --attention-session=<session> --attention-cursor=<cursor> --profile=operator
ntm --robot-causality=<session> --causality-project=<workspace> --causality-since=2h
ntm --robot-pipeline=<run-id>
```

If these disagree, the causality timeline and pipeline state win over pane scrollback summaries; pane scrollback can be stale or truncated.

---

## The SessionRecord schema

Per `/dp/brenner_bot/specs/session_replay_spec_v0.1.md`:

```typescript
interface SessionRecord {
  id: string;                  // REC-{session}-{timestamp}
  session_id: string;          // The thread ID (RS-YYYYMMDD-slug)
  created_at: string;          // ISO 8601
  inputs: SessionInputs;       // What the session started with
  trace: SessionTrace;         // What happened
  outputs: SessionOutputs;     // What it produced
  schema_version: string;      // For versioning the record format
}
```

The three regions (Inputs / Trace / Outputs) are **independent** — you can re-run inputs to produce a new trace, or compare outputs across two traces, etc.

---

## Inputs (deterministic)

```typescript
interface SessionInputs {
  kickoff: {
    thread_id: string;
    question?: string;
    excerpt?: string;
    theme?: string;
    domain?: string;
    operator_selection?: OperatorSelection;
    kickoff_body_md?: string;        // The full kickoff prompt
  };
  external_evidence: EvidenceRecordSummary[];   // EVs available at session start
  agent_roster: AgentRosterEntry[];   // Pane assignments (model + role)
  protocol_versions: {
    role_prompts?: string;           // e.g., "v0.1"
    delta_format: string;            // "v0.1"
    artifact_schema: string;         // "v0.1"
    evaluation_rubric?: string;
    evidence_pack?: string;
  };
}
```

Inputs are **deterministic** — given the same SessionInputs, the same models *should* produce a similar trace. (Models still have temperature; not perfect determinism, but reproducible-by-design.)

The `protocol_versions` block is critical. If you upgrade `delta_format` from v0.1 to v0.2, sessions recorded with v0.1 may not replay correctly under v0.2 — the field declares the contract.

---

## Trace (execution)

```typescript
interface SessionTrace {
  rounds: TraceRound[];
  interventions: OperatorIntervention[];
  intervention_summary?: InterventionSummary;
  total_duration_ms: number;
  started_at: string;
  ended_at?: string;
}

interface TraceRound {
  round_number: number;
  started_at: string;
  ended_at?: string;
  agent_messages: AgentMessage[];   // Full message bodies + hashes
  parsed_deltas: ParsedDelta[];     // What the parser extracted
  applied_deltas: AppliedDelta[];   // What was applied to the artifact
  rejected_deltas: RejectedDelta[]; // What failed validation + why
  artifact_state_hash: string;      // hash of artifact AFTER this round
}

interface OperatorIntervention {
  round_number: number;
  type: "manual_edit" | "force_state" | "skip_round" | "abort";
  description: string;
  applied_at: string;
}
```

The trace captures:
- **Per round**: what each agent said, what was parsed, what was applied, what was rejected
- **Per intervention**: when/why the operator manually intervened
- **Hashes**: artifact state after each round (for divergence detection)

The hash trail enables: "the two replays diverged at round 4 — here's the message that produced different parsing."

---

## Outputs (final state)

```typescript
interface SessionOutputs {
  final_artifact_path: string;
  final_artifact_hash: string;
  lint_results: LintResult;          // pass/fail counts per severity
  bead_counts: {
    H: number;
    T: number;
    A: number;
    X: number;
    C: number;
    EV: number;
  };
  hypothesis_states: Record<string, HypothesisState>;  // H1: "killed", H2: "validated", ...
  session_score?: number;            // 7-dimension score
  drift_verdict?: string;            // from Phase 10
}
```

Outputs are the **terminal state**. Two replays of the same Inputs may diverge mid-trace but should produce *similar* outputs (states, scores, hashes) if the methodology held.

---

## Content hashing

Every artifact, message, and delta has a content hash (SHA-256):

- `message_hash`: hash of the agent's raw message
- `delta_hash`: hash of the canonicalized JSON delta
- `artifact_state_hash`: hash of the artifact markdown after applying the round's deltas

Why? Because divergence detection requires comparing structurally-identical objects. "The artifact looks similar" is not the same as "the artifact is byte-identical."

The hash chain forms a **per-round Merkle DAG**. Replay correctness is verified by hash comparison at each round.

```
Round 1: artifact_state_hash = h1
Round 2: artifact_state_hash = h2  (must depend on h1 + Round 2 deltas)
Round 3: artifact_state_hash = h3  (must depend on h2 + Round 3 deltas)
```

If a replay produces a different h_i mid-trace, the divergence is at that round.

---

## Replay modes

The original BrennerBot spec names four modes. In NTM-native sessions, implement them through robot surfaces and the exported SessionRecord rather than a separate `brenner session replay` runtime command.

### `--mode trace`

Step-through replay showing round-by-round message summaries:

```bash
ntm --robot-causality=<session> --causality-project=<workspace> --causality-limit=500
ntm --robot-events --since-cursor=<cursor> --events-limit=200
```

```
Round 1 (started 2026-01-02T10:15:30Z)
  BlueLake [hypothesis_generator]: 3 deltas applied (H1, H2, H3); hash 3f7c...
  PurpleMountain [test_designer]: 2 deltas applied (T1, T2); hash 8b2e...
  → artifact state: 7e9a...
Round 2 (started 2026-01-02T10:23:14Z)
  ...
```

Useful for understanding what happened and reading the trace.

### `--mode rerun`

Re-execute the inputs against fresh agents:

```bash
ntm --robot-history=<session>
ntm --robot-replay=<session> --replay-id=<history-id> --replay-dry-run
ntm --robot-replay=<session> --replay-id=<history-id>
```

Use cases:
- Re-run with different models (e.g., cod replaced by claude-haiku-4.5)
- Re-run with same models but different temperatures
- Re-run after protocol upgrade to detect breakage

The replay produces a new SessionRecord with the same Inputs, new Trace, new Outputs. You diff the two records.

### `--mode shadow`

Step through historical session interactively, allowing operator to predict next action:

```bash
ntm --robot-causality=<session> --causality-project=<workspace> --causality-limit=1
# Reveal one causality/event chunk at a time; operator predicts next transition before expanding.
```

```
Round 4 begins. Question: "Devil's advocate has filed C-003 against H-1. What state should H-1 transition to?"
Your prediction: under_attack
Actual: under_attack ✓
```

For onboarding (per OPERATOR-ONBOARDING-CURRICULUM.md Week 2-3).

### `--mode export-trace`

Export trace as a step-by-step Markdown narrative for human review:

```bash
ntm --robot-causality=<session> --causality-project=<workspace> --causality-limit=1000 > trace-causality.json
ntm --robot-support-bundle=<session> --bundle-since=24h --bundle-output=trace-support.zip
./scripts/export-reproducibility-package.sh <workspace>
```

Useful for incident post-mortems (per POST-MORTEM-FORMALIZATION-PLAYBOOK.md).

---

## Per-purpose use cases

### Use case 1: Reproducibility for external reviewers

For T4+ session published externally:

```bash
./scripts/export-reproducibility-package.sh <workspace>
# → tar.gz with: artifacts/, evidence.json, session-record.json, README.md
```

External reviewers run:
```bash
ntm pipeline run .ntm/pipelines/brennerbot-squad.yaml \
  --session brennerbot-review \
  --var workspace_path=/abs/replay-workspace \
  --var session_id=brennerbot-review \
  --var question_of_record_path=intake/question_of_record.md \
  --var mode=replay \
  --dry-run
```

If their replay's outputs match (hash equivalence on artifact_state_hash post-Round-N), reproducibility verified.

### Use case 2: Model A/B comparison

Same session, different roster:

```bash
# Original: cc-cod-gmi
ntm pipeline run .ntm/pipelines/brennerbot-squad.yaml \
  --session brennerbot-cc-only \
  --var workspace_path=/abs/replay-workspace \
  --var session_id=brennerbot-cc-only \
  --var question_of_record_path=intake/question_of_record.md \
  --var mode=replay \
  --var model_mix=cc:3

# Compare:
diff -u session-A.json session-A-cc-only.json
ntm --robot-causality=brennerbot-cc-only --causality-project=/abs/replay-workspace
```

Per BRENNERBOT-AT-SCALE.md: this is how the operator discovers model-specific failure modes.

### Use case 3: Protocol upgrade verification

Before upgrading delta_format v0.1 → v0.2:

```bash
# Replay 50 historical sessions under v0.2
for record in $(ls records/*.json); do
  source_ws="$(jq -r '.workspace_path // empty' "$record")"
  test -n "$source_ws" || { echo "record lacks workspace_path: $record" >&2; continue; }
  replay_name="replay-$(basename "$record" .json)"
  ./scripts/session-fork.sh "$source_ws" "$replay_name" --purpose protocol-upgrade
  ntm pipeline run "$(dirname "$source_ws")/$replay_name/.ntm/pipelines/brennerbot-squad.yaml" \
    --session "$replay_name" \
    --var session_id="$replay_name" \
    --var delta_format=v0.2 \
    --dry-run
done
# Compare: did any session change verdict?
```

If verdicts diverge widely, the upgrade has methodology implications, not just format implications.

### Use case 4: Onboarding

```bash
ntm --robot-causality=<historical-T3-session> --causality-project=<workspace> --causality-limit=1
```

New operator predicts each transition; system reveals actual; difference becomes a teaching moment.

---

## The reproducibility tarball

For T4+ sessions, `scripts/export-reproducibility-package.sh` (already in scripts) bundles:

```
RS-YYYYMMDD-slug-reproducibility.tar.gz
├── README.md                    # how to reproduce
├── session-record.json          # the SessionRecord
├── evidence.json + evidence.md  # the evidence pack (excerpts only)
├── artifact.md                  # the final artifact
├── intake/                      # original framing
│   └── question_of_record.md
├── distillations/               # per-family distillations
├── protocol-versions.json       # version pins
└── checksums.txt                # SHA-256 of every file
```

The tarball is **self-contained reproduction**. A reviewer with brennerbot installed can rerun.

---

## Cross-session diffing

```bash
diff -u RS-A/session-record.json RS-B/session-record.json
ntm --robot-causality=RS-A --causality-project=/abs/RS-A > RS-A-causality.json
ntm --robot-causality=RS-B --causality-project=/abs/RS-B > RS-B-causality.json
```

Output shows:
- Inputs differences (different question, evidence, roster)
- Per-round divergence (round N differed because ...)
- Outputs differences (verdict diff, score diff, hypothesis-state diff)

This drives:
- Post-mortem: why did pilots A and B diverge on the same question?
- Calibration: which operator's session more closely matches an exemplar walkthrough?
- Methodology evolution: which protocol changes consistently shifted outputs?

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip recording Inputs ("the operator remembers") | Inputs morph; replay drifts |
| Hash messages but not the artifact state | Divergence undetectable mid-trace |
| Store full PDFs in evidence.json | Bloats record; copyright risk |
| Skip `protocol_versions` block | Replay under newer protocol may silently break |
| Use replay to "prove" the verdict was correct | Replay verifies *process consistency*, not truth |
| Treat replay rerun as deterministic | Models have temperature; expect *similar*, not identical |
| Discard rejected_deltas from trace | Often diagnostic for parser bugs |
| Replay without preserving the original artifact_state_hash chain | Lose divergence localization |

---

## Composition with brennerbot phases

| Phase | Replay activity |
|-------|-------------------|
| 1-9 | Trace is being recorded continuously |
| 8 freeze | SessionRecord is finalized + committed |
| 10 drift | Replay history is the evidence for trajectory |
| Across sessions | Cross-session diff is the basis for METHODOLOGY-EVOLUTION-LOG.md updates |

For T4+: Phase 8 freeze cannot complete until SessionRecord lints clean (per BRENNERBOT-DOCTOR-RUBRIC.md Pillar 1 extension).

---

## Cross-references

- [EVIDENCE-PACK-PROTOCOL.md](EVIDENCE-PACK-PROTOCOL.md) — evidence in record format
- [DELTA-PROTOCOL-FAIL-FAST.md](DELTA-PROTOCOL-FAIL-FAST.md) — delta hashing
- [ARTIFACT-7-SECTION-SCHEMA.md](ARTIFACT-7-SECTION-SCHEMA.md) — artifact format being hashed
- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — hypothesis_states in outputs
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — A/B comparison at scale
- [OPERATOR-ONBOARDING-CURRICULUM.md](OPERATOR-ONBOARDING-CURRICULUM.md) — shadow-mode replay
- [POST-MORTEM-FORMALIZATION-PLAYBOOK.md](POST-MORTEM-FORMALIZATION-PLAYBOOK.md) — incident replay
- [scripts/export-reproducibility-package.sh](../scripts/export-reproducibility-package.sh) — packaging
- /dp/brenner_bot/specs/session_replay_spec_v0.1.md — spec source
- /dp/brenner_bot/CHANGELOG.md v0.4.0 — implementation milestone
