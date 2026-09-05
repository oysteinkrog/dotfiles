# BEADS-WORKFLOW-CHEATSHEET.md — Concrete `br` Commands Per Phase

<!-- TOC: Why a cheatsheet | Phase 1 br commands | Phase 2 br commands | Phase 3 br commands | Phase 4 br commands | Phase 5 br commands | Phase 6 br commands | Phase 7 br commands | Phase 8 br commands | Phase 9 br commands | Phase 10 br commands | Cross-cutting br commands | Common br pitfalls | jq snippets | What pane scripts can run vs operator-only -->

The `/beads-br` skill covers the full beads CLI. This cheatsheet shows **brennerbot-specific patterns**: which `br` invocations land where in the phase loop, with copy-paste-ready examples.

For agents working a session, this is the lookup. The full `/beads-br` reference is for understanding *why*; this is for *doing*.

---

## Why a cheatsheet

Beads commands are simple individually but compose nontrivially. Phase 4 needs to query Hs, file new EVs, link them, update H states based on EV reach — that's 4 distinct `br` invocations per round per H. Without a cheatsheet, operators (or panes via dispatch) reinvent the patterns each time.

Per BEADS-SCHEMA.md, brennerbot beads have these label conventions:

| Label | Public ref prefix | Lifetime |
|-------|---------------|----------|
| `q-of-record` | Q-NNN | Phase 1; 1 per session |
| `hypothesis` | H-NNN | Phases 3-7; state machine |
| `evidence` | EV-NNN | Phases 3-7; W-scored |
| `test` | T-NNN | Phase 4; per-H test plan |
| `assumption` | A-NNN | Phase 4-7; tracked separately |
| `critique` | C-NNN | Phases 4-5; severity-tagged |
| `debate` | DEBATE-NNN | Phase 5 |
| `audit-finding` | AF-NNN | Phase 7 |
| `distillation` | D-NNN | Phase 6 (disagreement entries) |
| `anomaly` | AN-NNN | Phases 4-7 |

These prefixes are human public refs, not guaranteed raw `br` IDs. Current `br`
generates actual IDs; use `--external-ref <PUBLIC_REF> --silent`, keep the
returned ID in a shell variable, and pass that actual ID to `br show`, `br
update`, and `br close`.

```bash
id_by_ref() {
  br list --all --json \
    | jq -r --arg ref "$1" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' \
    | head -1
}

require_id_by_ref() {
  local ref="$1" id
  id="$(id_by_ref "$ref")"
  [ -n "$id" ] || { echo "No bead found for public ref: $ref" >&2; return 1; }
  printf '%s\n' "$id"
}
```

---

## Phase 1 br commands

```bash
# Initialize the beads database (idempotent)
br init

# File the question of record (the only Q bead per session)
q_ref="Q-001"
q_id="$(br create "$q_ref: <one-line question>" \
    --type=question --labels=q-of-record --priority=0 \
    --slug="$q_ref" --external-ref="$q_ref" --silent \
    --description="$(cat intake/question_of_record.md)")"

# Verify Q-001 exists
br list --label=q-of-record --json | jq '.issues | length'  # → 1

# Close Q-001 at end of Phase 1 (it's "framed", not "answered")
br close "$q_id" --reason="Framing complete"

# Sync to JSONL (do this at every phase exit so git can pick up)
br sync --flush-only
git add .beads/ && git commit -m "Phase 1 beads"
```

---

## Phase 2 br commands

```bash
# Phase 2 is mostly ntm/Agent-Mail; few bead operations.
# Just sync at end:
br sync --flush-only
```

---

## Phase 3 br commands

```bash
# Per Proposer pane (via dispatch): file each H bead
h_ref="H-001"
h_id="$(br create "$h_ref: <claim summary>" \
    --type=task --labels=hypothesis --priority=2 \
    --slug="$h_ref" --external-ref="$h_ref" --silent \
    --description="$(cat <<'EOF'
claim: <one-line>
mechanism: <how it would work>
falsifier: <observable that, if found, refutes>
expected_evidence: <what we expect to see if the H is true>
state: active
confidence: medium  # default; updated as evidence accumulates
origin: proposer | third_alternative | anomaly_spawned | fork
proposed_at: <ISO>
proposed_by: <PANE_N>
EOF
)")"

# Triage: deduplicate. If H-002 is a duplicate of H-001, mark superseded:
h1_id="$(require_id_by_ref H-001)"
h2_id="$(require_id_by_ref H-002)"
old_desc="$(br show "$h2_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""')"
new_desc="$(
  printf '%s\n' "$old_desc" | awk '
    BEGIN { done = 0 }
    /^state:/ && !done { print "state: superseded"; done = 1; next }
    { print }
    END { if (!done) print "state: superseded" }
  '
)"
br update "$h2_id" --description="$(
  printf '%s\n' "$new_desc" | awk '
    BEGIN { saw_parent = 0; saw_reason = 0 }
    /^parent:/ { if (!saw_parent) { print "parent: H-001"; saw_parent = 1 } ; next }
    /^superseded_reason:/ { if (!saw_reason) { print "superseded_reason: duplicate of H-001"; saw_reason = 1 } ; next }
    { print }
    END {
      if (!saw_parent) print "parent: H-001"
      if (!saw_reason) print "superseded_reason: duplicate of H-001"
    }
  '
)"
br dep add "$h2_id" "$h1_id"  # H-002 is blocked by H-001 (parent reference)

# Force a third-alternative if missing (per F-301):
br list --label=hypothesis --json \
  | jq '.issues[]? | select((.description // "") | contains("origin: third_alternative"))' \
  | jq -s 'length'
# → 0 means F-301 violation; dispatch MO-03c-third-alternative.md

# Ready check at end of Phase 3:
br list --label=hypothesis --status=open --json | jq '.issues | length'
# → ≥3 expected
```

---

## Phase 4 br commands

```bash
ev_ref="EV-014"
ev_id="$(br create "$ev_ref: <one-line claim from source>" \
    --type=task --labels=evidence --priority=2 \
    --slug="$ev_ref" --external-ref="$ev_ref" --silent \
    --description="$(cat <<'EOF'
type: paper | observation | code_artifact | regulatory
source: <URL or file path>
source_id: S-NNN
relevance: <why this evidence matters>
imported_at: <ISO>
imported_by: <PANE_N>
verified: false
W_source: 0.85
W_verification: 0.6
W_independence: 0.5
W_recency: 0.9
W_domain_fit: 0.7
W_composite: 0.16
W_strength: weak
supports: [H-001]    # OR refutes: [H-002]    OR informs: [H-003]
session: <SESSION_ID>

## Excerpts
- E1 (verbatim from §3.2): "<exact quote>"
EOF
)")"

# Compute W_composite for an EV (uses scripts/score-ev.sh)
./scripts/score-ev.sh "$ev_id"

# Promote EV's confidence after independent verification
./scripts/score-ev.sh "$ev_id"  # re-runs after operator updates W_verification

# Query: per-H supporting EVs. Use a bracket-scoped word-boundary regex so
# multi-H lists like `supports: [H-001, H-007]` are matched for both H-IDs;
# the older `contains("supports: [\($h)]")` form only matched single-H lists
# and silently dropped multi-H supports.
br list --label=evidence --json \
  | jq --arg h "H-001" '.issues[]? | select((.description // "") | test("supports:[[:space:]]*\\[[^\\]]*\\b" + $h + "\\b[^\\]]*\\]"))'

# Query: per-H refuting EVs (same bracket-scoped regex).
br list --label=evidence --json \
  | jq --arg h "H-001" '.issues[]? | select((.description // "") | test("refutes:[[:space:]]*\\[[^\\]]*\\b"  + $h + "\\b[^\\]]*\\]"))'

# Update H confidence based on accumulated W (operator decides; per CONFIDENCE-SCORING.md)
h1_id="$(require_id_by_ref H-001)"
br update "$h1_id" --description="$(br show "$h1_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' \
    | sed -E 's/^confidence: [a-z]+$/confidence: high/')"

# When falsifier fires (per MO-falsifier-fired.md):
h2_id="$(require_id_by_ref H-002)"
br update "$h2_id" --description="$(br show "$h2_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' \
    | sed -E 's/^state: [a-z]+$/state: refuted/' \
    | awk '1; END { print "refuted_by: EV-018" }')"

# Round-end convergence check
./scripts/convergence-check.sh --phase=4

# Phase 4 invariants check
./scripts/audit-bead-invariants.sh --check=phase4_round
```

---

## Phase 5 br commands

```bash
# Generate debate-pair rows for the Phase 5 operator loop:
# DEBATE-001|H-001|H-005|%1|%4
# Champion panes come from .brenner_workspace/h-pane-mapping.json first, then
# bead metadata (`owner_pane`, `champion_pane`, `assignee`) as a fallback.
./scripts/generate-debate-pairs.sh > /tmp/debates.pairs

# Executable pipelines normally use this wrapper instead of hand-copying the loop:
./scripts/run-phase5-debate-loop.sh --workspace="$WORKSPACE" --session="$SESSION_ID" --round=1

# File a debate bead
debate_ref="DEBATE-001"
debate_id="$(br create "$debate_ref: H-001 vs H-005 cross-exam" \
    --type=task --labels=debate --priority=2 \
    --slug="$debate_ref" --external-ref="$debate_ref" --silent \
    --description="$(cat <<'EOF'
debate_ref: DEBATE-001
pair: H-001 vs H-005
champions: {H-001: p1, H-005: p4}
adjudicator: p3(cod)
state: open
rounds: 3
session: RS-YYYYMMDD-slug
mail_thread: RS-YYYYMMDD-slug-DEBATE-H-001-vs-H-005
falsifier_fired: null
adjudication: null
EOF
)")"

# After adjudication
br update "$debate_id" --status=closed --description="$(br show "$debate_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' \
    | awk '1; END {
        print "verdict: H-005 wins"
        print "falsifier_fired: EV-019"
        print "rationale_path: deliverables/debate-001-rationale.md"
        print "closed_at: <ISO>"
    }')"

# Apply † Theory-Kill on the loser (or defer if equipoise)
h1_id="$(require_id_by_ref H-001)"
br update "$h1_id" --description="$(br show "$h1_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' \
    | sed -E 's/^state: active/state: deferred/')"

# File a critique
c_ref="C-007"
c_id="$(br create "$c_ref: <claim severity>" \
    --type=task --labels=critique --priority=2 \
    --slug="$c_ref" --external-ref="$c_ref" --silent \
    --description="$(cat <<'EOF'
target: H-001
attack: <specific>
severity: serious
evidence_to_confirm: <observable>
filed_by: <PANE_N>
filed_at: <ISO>
EOF
)")"
```

---

## Phase 6 br commands

```bash
# File disagreement-register entries (D-NNN)
# These don't go through br directly; they're entries in distillations/disagreement_register.md
# But you may file companion D-NNN beads for tracking:
d_ref="D-001"
d_id="$(br create "$d_ref: cc vs gmi on operational complexity" \
    --type=question --labels=distillation --priority=2 \
    --slug="$d_ref" --external-ref="$d_ref" --silent \
    --description="...")"

# Lint disagreement register
./scripts/disagreement-register-lint.sh
```

---

## Phase 7 br commands

```bash
# Audit panes file findings
af_ref="AF-001"
af_id="$(br create "$af_ref: <one-line finding>" \
    --type=task --labels=audit-finding --priority=$([ "$severity" = "critical" ] && echo 0 || echo 1) \
    --slug="$af_ref" --external-ref="$af_ref" --silent \
    --description="$(cat <<'EOF'
severity: critical | high | medium | low
target_artifact: meta_synthesis.md § 3.2
recommendation: <specific fix>
evidence: <which content of target is wrong>
methodology_violation: F-602 OR ∿ Dephase failure
filed_by: <PANE_N>
filed_at: <ISO>
EOF
)")"

# Address findings
# (After operator + panes apply fixes)
br close "$af_id" --reason="Addressed: meta_synthesis.md § 3.2 corrected to cite EV-018"

# Convergence check
./scripts/convergence-check.sh --phase=7

# Run six-layer validation
./scripts/check-six-layer-validation.sh --workspace=.
```

---

## Phase 8 br commands

```bash
# Pre-freeze: sync everything
br sync --flush-only
git add .beads/ && git commit -m "Phase 8 beads sync"

# Verify ledger advances stopped
br list --status=in_progress --json | jq '.issues | length'  # → 0 expected
```

---

## Phase 9 br commands

```bash
# Surface unresolved Hs/EVs for HANDBACK with next-action. Do not use raw
# Beads `--status=open` as the definition of "still open"; terminal H states
# stay bead-open until closeout so Phase 6/7/9 can still read them.
br list --label=hypothesis --status=open --json \
  | jq -r '
      .issues[]?
      | select((.description // "") | test("(^|\\n)state:[[:space:]]*(active|proposed|deferred)([[:space:]]|$)"))
      | "- \(.id): \(.title)"
    ' >> deliverables/HANDBACK.md
br list --label=evidence --status=open --json \
  | jq -r '
      .issues[]?
      | select((.description // "") | test("(^|\\n)verified:[[:space:]]*false([[:space:]]|$)"))
      | "- \(.id): \(.title)"
    ' >> deliverables/HANDBACK.md

# Audit for next-action tags
./scripts/audit-bead-invariants.sh --check=handback_open_thread_tags
```

---

## Phase 10 br commands

```bash
# Mostly read-only at this phase. List final session state:
br list --json | jq '[group_by(.labels[0])[] | {label: .[0].labels[0], count: length}]'

# Sync final state
br sync --flush-only
git add .beads/ && git commit -m "Phase 10 final beads sync"
```

---

## Cross-cutting br commands

### Find ready work for a pane (per /beads-br skill)

```bash
br ready --label=hypothesis --json | jq '.[0]'  # top-priority unblocked
```

### Show full bead detail (operator inspecting state)

```bash
h_id="$(require_id_by_ref H-001)"
br show "$h_id" --json | jq
```

### Filter by state field embedded in description

```bash
br list --label=hypothesis --json \
  | jq '.issues[]? | select((.description // "") | contains("state: active"))' \
  | jq -s 'length'  # active H count
```

### Add a dependency (per BEADS-SCHEMA invariants)

```bash
h_id="$(require_id_by_ref H-001)"
t_id="$(require_id_by_ref T-002)"
br dep add "$h_id" "$t_id"  # H-001 is blocked until discriminative test T-002 is resolved
```

### Bulk-close terminal Hs at session closeout

```bash
# Use only at session closeout, after Phase 9/10 artifacts no longer need to
# query terminal Hs via `--status=open`.
br list --label=hypothesis --json \
  | jq -r '
      .issues[]?
      | select((.description // "") | test("(^|\\n)state:[[:space:]]*(confirmed|refuted|superseded)([[:space:]]|$)"))
      | .id
    ' \
  | xargs -I{} br close {} --reason="Terminal H state closed at session closeout"
```

### Filter by author / pane

```bash
br list --label=evidence --json \
  | jq --arg p "p3" '.issues[]? | select((.description // "") | contains("imported_by: \($p)"))'
```

### Search descriptions for specific text

```bash
br list --json | jq -r '.issues[]? | select((.description // "") | contains("scale_physics")) | .id'
```

---

## Common br pitfalls

| ✗ | Why it bites |
|---|--------------|
| `br create ... --description=$(cat ...)` (unquoted) | Multi-line/special-char content breaks; ALWAYS quote |
| Edit `.beads/*.jsonl` directly | Per AGENTS.md, only via `br`; if drift, escalate to `/fixing-beads-problems` |
| Forget `br sync --flush-only` before commit | Beads state in DB only; jsonl is stale; downstream automation breaks |
| Use `br update` to add fields without `br show ... | jq` to preserve | Description is wholesale-replaced, not patched; you'll lose existing fields |
| `br create` with same title repeatedly | New beads each time; check for existing first via list+grep |
| `br list` without `--json` | TUI output isn't parseable; always `--json` for automation |
| `--priority=4` for load-bearing Hs | Beads with priority 4 (backlog) often skipped by `br ready` |
| Use string `"true"`/`"false"` for booleans in description | Inconsistent later; use lowercase `true`/`false` per beads convention |

---

## jq snippets per phase

### Per-H supporting/refuting EV count (Phase 4 dashboard)

```bash
H="H-001"
# Bracket-scoped word-boundary regex so `supports: [H-001, H-007]` counts for
# both H-IDs, and so a sibling `refutes: [H-001]` does NOT inflate the supports
# count when the same description has any other supports list.
br list --label=evidence --json | jq --arg h "$H" '
  [.issues[]? | select((.description // "") | test("supports:[[:space:]]*\\[[^\\]]*\\b" + $h + "\\b[^\\]]*\\]"))] | length,
  [.issues[]? | select((.description // "") | test("refutes:[[:space:]]*\\[[^\\]]*\\b"  + $h + "\\b[^\\]]*\\]"))] | length
'
# Outputs: support_count, refute_count
```

### Aggregate W_composite per H (Phase 6 input)

```bash
H="H-001"
br list --label=evidence --json | jq --arg h "$H" '
  [.issues[]?
    | select((.description // "") | test("supports:[[:space:]]*\\[[^\\]]*\\b" + $h + "\\b[^\\]]*\\]"))
    | (try ((.description // "") | capture("W_composite:[[:space:]]*(?<w>[0-9.]+)") | .w | tonumber) catch 0)]
  | add // 0
'
# Outputs: total support W
```

### List anomalies that share a feature (per ΔE clustering)

```bash
br list --label=anomaly --json | jq -r '
  [.issues[]? | . + {feature: (try ((.description // "") | capture("feature:[[:space:]]*(?<f>\\S+)") | .f) catch "")}]
  | group_by(.feature)[]
  | select(.[0].feature != "")
  | select(length >= 2)
  | { feature: .[0].feature,
      anomalies: [.[].id] }
'
# Outputs: clusters of ≥2 anomalies sharing a feature
```

### List Hs with weak falsifiers (per subagents/falsifier-grader.md feedback)

```bash
br list --label=hypothesis --json | jq -r '.issues[]?
  | (.description // "") as $d
  | { id: .id,
      grade: (($d | capture("falsifier_grade:[[:space:]]*(?<g>\\w+)")? | .g) // "ungraded") }
  | select(.grade == "Poor" or .grade == "Weak")
'
```

### Find unresolved disagreements (Phase 6 → Phase 7 input)

```bash
grep -E '^## D-[0-9]+' distillations/disagreement_register.md \
  | wc -l
# Should equal at least (n-families choose 2)
```

---

## What pane scripts can run vs operator-only

Some commands are safe for panes (via dispatched MOs); others must be operator-only:

| Command | Safe for panes? | Reason |
|---------|-----------------|--------|
| `br create` | yes | Each pane files their own beads |
| `br update <own-bead>` | yes | Per pane, on beads they own |
| `br update <other-pane's>` | NO | Operator/Adjudicator only |
| `br dep add` | yes | Cross-bead links |
| `br close` | NO (operator) | Closure is a methodology decision |
| `br sync --flush-only` | yes (idempotent) | But operator commits |
| `br ready` | yes | Each pane queries their own work |
| Direct edit of `.beads/*.jsonl` | NEVER | Both panes and operator forbidden |

Pane MOs (per `assets/marching-orders/MO-*.md`) typically run `br create` and `br update` on the bead they own. The operator is the only one who runs `br close` (closing is a methodology decision).

---

## Composition with other skills

- `/beads-br` — full beads CLI reference (read this when uncertain about flags)
- `/beads-bv` — graph-aware triage on bead state (find bottleneck Hs, critical-path EVs)
- `/fixing-beads-problems` — when `br show` or `br doctor` fails
- `/cass` — search across prior brennerbot sessions for related beads

---

## Cross-references

- [BEADS-SCHEMA.md](BEADS-SCHEMA.md) — full schema with mandatory fields per bead type
- [EVIDENCE-WEIGHTING-TAXONOMY.md](EVIDENCE-WEIGHTING-TAXONOMY.md) — W axes for EV beads
- [CONFIDENCE-SCORING.md](CONFIDENCE-SCORING.md) — H confidence rubric
- [scripts/score-ev.sh](../scripts/score-ev.sh) — automates W axis aggregation
- [scripts/audit-bead-invariants.sh](../scripts/audit-bead-invariants.sh) — schema invariant check
- [/beads-br](../../beads-br/SKILL.md) — full beads CLI skill
