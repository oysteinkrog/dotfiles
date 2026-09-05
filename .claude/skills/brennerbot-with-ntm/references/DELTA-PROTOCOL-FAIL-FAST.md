# DELTA-PROTOCOL-FAIL-FAST.md — The Machine-Handshake Layer

<!-- TOC: Why a structured delta protocol | The fenced JSON block format | The 3 operations | Section + ID conventions | The inline-delta failure mode | Fail-fast on 0-block messages | Lenient parser tolerance | Conflict resolution | Per-phase delta usage | Composition with beads | Anti-patterns | Cross-references -->

The brennerbot artifact is updated through **structured deltas**, not free-form prose. Agents output operations (ADD/EDIT/KILL) as fenced JSON blocks, the compiler merges them deterministically. This is the machine-handshake layer — and it's *the most failure-prone interface in the entire system*.

Pilot retrospective (per `/dp/brenner_bot/specs/pilot_retrospective_v0.1.md`) explicitly identifies inline-delta-without-fence as a high-frequency, high-impact failure mode: agents post inline JSON that *looks* like a delta, the parser extracts 0 blocks, the artifact silently drops the intended update.

This file specifies the delta protocol with **fail-fast** semantics.

Mined from `/dp/brenner_bot/specs/delta_output_format_v0.1.md`, `artifact_delta_spec_v0.1.md`, and `pilot_retrospective_v0.1.md`.

---

## Why a structured delta protocol

Three failures of free-form prose:

1. **Non-deterministic merge** — two agents writing prose can't be combined automatically
2. **Hidden additions** — what's "new" vs "modified" is implicit
3. **No audit trail** — you can't tell who proposed what or when

Three benefits of structured deltas:

1. **Mechanizable compilation** — apply ops in order; deterministic output
2. **Per-op audit trail** — every change has agent + timestamp + rationale
3. **Concurrent updates** — two agents can edit the same artifact section without race

The cost: agents must output *exactly* the right format. The protocol is brittle. Hence fail-fast.

---

## The fenced JSON block format

A delta is always a **fenced JSON block** with the `delta` language tag:

~~~markdown
```delta
{
  "operation": "ADD",
  "section": "hypothesis_slate",
  "target_id": null,
  "payload": {
    "name": "Epigenetic memory",
    "claim": "Cells use chromatin state inheritance for fate determination",
    "mechanism": "Histone modifications inherited through division encode positional memory",
    "anchors": ["§58", "EV-001#E1"]
  },
  "rationale": "Adding alternative mechanism that doesn't fit lineage/gradient dichotomy"
}
```
~~~

### Field schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `operation` | string | ✓ | `"ADD"` \| `"EDIT"` \| `"KILL"` |
| `section` | string | ✓ | `hypothesis_slate` \| `predictions_table` \| `discriminative_tests` \| `assumption_ledger` \| `anomaly_register` \| `adversarial_critique` \| `research_thread` |
| `target_id` | string \| null | conditional | Required for EDIT/KILL; must be null for ADD |
| `payload` | object | conditional | Content for ADD/EDIT; reason object for KILL |
| `rationale` | string | recommended | Why this change |

### Section + ID convention

| Section | ID prefix | Example |
|---------|-----------|---------|
| `hypothesis_slate` | `H` | H1, H2, H3 |
| `predictions_table` | `P` | P1.H1, P2.H2 |
| `discriminative_tests` | `T` | T1, T2, T3 |
| `assumption_ledger` | `A` | A1, A2 |
| `anomaly_register` | `X` | X1, X2 |
| `adversarial_critique` | `C` | C1, C2 |
| `research_thread` | `RT` | RT (singleton; EDIT only) |

---

## The 3 operations

### ADD

Append a new item to a section. `target_id` is **null** (the compiler auto-assigns the next sequential ID).

```json
{
  "operation": "ADD",
  "section": "hypothesis_slate",
  "target_id": null,
  "payload": {
    "name": "...",
    "claim": "...",
    "mechanism": "...",
    "anchors": ["§n", "EV-001"]
  },
  "rationale": "..."
}
```

Side effects: ID assignment, duplicate detection (warning if semantically similar to existing item), schema validation.

### EDIT

Modify an existing item. `target_id` must reference a non-killed item. Payload fields are merged (deep merge); fields not in payload are preserved.

```json
{
  "operation": "EDIT",
  "section": "hypothesis_slate",
  "target_id": "H2",
  "payload": {
    "confidence": "high"
  },
  "rationale": "Updated based on EV-007 results"
}
```

### KILL

Mark an item as killed (not deleted; preserved with strikethrough + reason).

```json
{
  "operation": "KILL",
  "section": "hypothesis_slate",
  "target_id": "H1",
  "payload": {
    "reason": "Contradicted by EV-002#E3 [verbatim] showing fate determined post-division"
  },
  "rationale": "Test T1 ruled out this hypothesis"
}
```

KILL is **idempotent** — killing an already-killed item produces no error.

KILL on H-NNN drives the lifecycle FSM (per HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md): `under_attack` → `killed`.

---

## The inline-delta failure mode

**The single highest-frequency failure** observed in pilots:

```markdown
# (Bad — inline JSON, NO fence)
Here is my hypothesis:

{
  "operation": "ADD",
  "section": "hypothesis_slate",
  ...
}
```

Why it happens:
- Agents (especially smaller models) skip the fence
- Markdown rendering shows the JSON, so it *looks* correct
- The delta parser only matches fenced blocks (`` ```delta ``)
- Result: **0 deltas extracted**; message silently produces no artifact change

The pilot retrospective: "Round 2 explicitly calls this out as 'format evolution'. ... This is not a 'doc polish' issue — it is a *protocol robustness* issue because it breaks the mechanistic handshake."

---

## Fail-fast on 0-block messages

Per the pilot retrospective Change 1: **"Fail-fast on DELTA messages with 0 parsed delta blocks."**

Implementation:

1. **Parser counts** delta blocks in incoming message
2. **If subject contains `DELTA[role]:` prefix AND block count == 0**: emit error
3. **Error becomes a critique** (`C-NNN` bead, severity: serious, target: methodology)
4. **Operator + sender are both notified** via mail thread
5. **The intended update is not silently dropped** — the failure is audible

Detection script (per `scripts/diagnose-deltas.sh` — Tier-7 future addition; until then, manually scan agent messages for `DELTA[role]:` subjects whose bodies contain JSON without ` ```delta ` fences):

```bash
brenner session diagnose --thread-id RS-... --check deltas
```

Output:

```
✗ FAIL: 2 messages claim DELTA[role] but parser extracted 0 fenced blocks
  - msg-id-7c3a (BlueLake, Round 1): inline JSON without ```delta fence
  - msg-id-9f2b (PurpleMountain, Round 2): JSON in plain code fence (```json instead of ```delta)
```

Per BRENNERBOT-DOCTOR-RUBRIC.md Pillar 1: this is a structural-integrity failure.

---

## Lenient parser tolerance

Per CHANGELOG.md v0.3.0: **"Lenient delta parsing that tolerates agent hallucinations and partial syntax."**

The parser still:
- Accepts `````delta`, `````json`, or `````` fences (all match)
- Tolerates trailing commas
- Tolerates missing optional fields (warning, not error)
- Tolerates field aliasing (`reason` and `kill_reason` treated as equivalent)
- Tolerates array payloads expanded into individual ADD deltas

But the parser **never** silently produces 0-block extraction:

| Condition | Behavior |
|-----------|----------|
| Valid fence + valid JSON + valid schema | Apply |
| Valid fence + invalid JSON | Error: "JSON parse failed at line N" |
| Valid fence + valid JSON + invalid schema | Error: "missing required field `section`" |
| Missing fence + JSON-shaped content + DELTA prefix | **Error: "0 fenced delta blocks but DELTA prefix used"** |
| Missing fence + JSON-shaped content + no DELTA prefix | Warning: "appears to be a delta but no DELTA prefix" |

The lenient-but-not-silent invariant: ambiguity is OK; silent dropping is not.

---

## Conflict resolution

Two agents EDIT the same target concurrently:

```
Agent A at t=100: EDIT H2 { predictions: { T1: "<500ms" } }
Agent B at t=101: EDIT H2 { predictions: { T1: "<600ms", T2: ">1000ms" } }
```

Resolution rule: **last-write-wins per field; non-conflicting fields merged.**

```
H2.predictions.T1 = "<600ms"  (B wins on conflict)
H2.predictions.T2 = ">1000ms"  (B-only, no conflict)
```

The conflict is **logged** to `session-logs/merge-conflicts.jsonl` for audit:

```json
{
  "target": "H2",
  "field": "predictions.T1",
  "agent_A": { "value": "<500ms", "timestamp": 100 },
  "agent_B": { "value": "<600ms", "timestamp": 101, "winner": true }
}
```

If conflicts cluster around a target, that's a signal: per CONVERGENCE.md, file `RS-...-DEBATE-H2` thread to debate which value is correct.

---

## Per-phase delta usage

| Phase | Primary operations | Notes |
|-------|---------------------|-------|
| 1 framing | EDIT research_thread (singleton) | Set RT = question of record |
| 3 hypothesis | ADD hypothesis_slate × ≥3 | Including third_alternative |
| 4 investigation | EDIT hypothesis_slate (confidence); ADD discriminative_tests | EV anchors per H |
| 5 cross-exam | KILL hypothesis_slate (refuted H); ADD adversarial_critique | Per BRENNER-GAN-MECHANICS |
| 6 distillation | (no deltas; reads only) | Distillations are markdown, not deltas |
| 7 audit | ADD adversarial_critique × M | High-severity findings |
| 8 freeze | (no deltas; lock state) | Final compile + lint |

---

## Composition with brennerbot beads

The delta protocol and the bead system are **two views of the same state**:

- **Delta:** the *operation* applied to the artifact
- **Bead:** the *resulting artifact element* (H-NNN, T-NNN, A-NNN, AN-NNN, C-NNN, EV-NNN — note: anomaly bead is `AN-` per BEADS-SCHEMA.md; the 7-section artifact's in-section label is `X`)

Workflow:

```
agent_message[role:investigator]
  → contains ```delta {ADD ...} ```
    → parser → bead created (H-005)
      → linter (per ARTIFACT-LINTER-RULES.md)
        → if pass: artifact updated
        → if fail: error mail to sender
```

Not all bead types come from deltas — `EV-NNN` evidence beads (per EVIDENCE-PACK-PROTOCOL.md) and `audit-finding` beads (per Phase 7) are filed via `br create` directly. The delta protocol covers the 7-section artifact items.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Inline JSON without fence | Parser extracts 0 blocks; silent drop |
| Use `````json` fence instead of `````delta` | Lenient parser warns; better to use canonical |
| Mix prose explanation inside the JSON block | Breaks parser |
| Multiple deltas in one fence | Parser splits but error-prone; one fence per delta |
| `target_id` non-null for ADD | Validator rejects |
| `target_id` null for EDIT/KILL | Validator rejects |
| KILL without `payload.reason` | Validator rejects |
| `section` not in canonical list | Validator rejects |
| `confidence: very high` (free-form value) | Schema validates enum: low/medium/high |
| Field aliases the parser doesn't know (`hypothesis_id` instead of `target_id`) | Lenient parser warns; agent should learn canonical |

---

## Diagnose-deltas CLI

Per pilot retrospective Change 3: **CLI command for delta-parse diagnostics.**

```bash
brenner session diagnose --thread-id RS-... --check deltas --json
```

Output (machine-readable):

```json
{
  "thread_id": "RS-...",
  "diagnostics": [
    {
      "msg_id": "msg-7c3a",
      "sender": "BlueLake",
      "issue": "inline_json_without_fence",
      "fence_count": 0,
      "json_block_count": 1,
      "remediation": "Wrap JSON in ```delta ... ``` fence"
    }
  ],
  "summary": { "errors": 1, "warnings": 0 }
}
```

Operators run this BEFORE Phase 6 distillation to catch silent-drop bugs early. Per Phase 4 tick cadence (per OBSERVABILITY.md), every 3-5 ticks.

---

## Cross-references

- [ARTIFACT-7-SECTION-SCHEMA.md](ARTIFACT-7-SECTION-SCHEMA.md) — what deltas modify
- [ARTIFACT-LINTER-RULES.md](ARTIFACT-LINTER-RULES.md) — post-merge validation
- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — KILL drives FSM transitions
- [BEADS-SCHEMA.md](BEADS-SCHEMA.md) — bead-level view
- [BRENNERBOT-DOCTOR-RUBRIC.md](BRENNERBOT-DOCTOR-RUBRIC.md) — Pillar 1 detects 0-block messages
- [PILOT-RETROSPECTIVE-PROTOCOL.md](PILOT-RETROSPECTIVE-PROTOCOL.md) — operational lessons format
- /dp/brenner_bot/specs/delta_output_format_v0.1.md — spec source
- /dp/brenner_bot/specs/artifact_delta_spec_v0.1.md — spec source
- /dp/brenner_bot/specs/pilot_retrospective_v0.1.md — failure-mode source
