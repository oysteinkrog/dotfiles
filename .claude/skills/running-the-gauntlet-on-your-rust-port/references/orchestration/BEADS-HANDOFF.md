# Beads Handoff (Phase 13)

Phase 13 takes the Phase 12 remediation plan (markdown plan with per-pillar gap → isomorphic-rewrite rubric scoring) and converts it into a polished bead graph ready for swarm execution.

The phase has three sub-steps:
1. **Plan → beads** via the `/beads-workflow` conversion prompt.
2. **Polish loop** (4-5 rounds) until steady state.
3. **Dependency validation** — every remediation bead has test + bench + docs dependencies.

Output: `<target>/.beads/beads.db` (and `.beads/beads.jsonl`) with no cycles, no orphans, every remediation bead closable on concrete evidence. The gauntlet workspace keeps the Phase-13 summaries and validator reports; the target repo owns the executable remediation graph.

---

## The EXACT Plan-to-Beads Conversion Prompt

Verbatim from `/beads-workflow`'s "Plan to Beads Conversion" section. Use without modification.

```
You are converting a remediation plan into a beads dependency graph.

INPUT: a markdown plan with per-gap remediation entries. Each entry has:
- Gap description (1-3 sentences)
- Isomorphic-rewrite alternatives (2+)
- Rubric scoring (Impact × Confidence / Effort, EV-style)
- Selected alternative + rationale
- Acceptance criteria (test + bench + docs evidence)

OUTPUT: br-CLI compatible beads spec, one bead per node, with full dependency graph.

DISCIPLINE:
1. Every remediation bead MUST have at least one test-bead dependency (oracle / metamorphic / sanitizer / fuzz / property / golden-snapshot).
2. Every remediation bead MUST have at least one benchmark-bead dependency (criterion / hyperfine / comprehensive-bench).
3. Every remediation bead MUST have at least one documentation-bead dependency (update // SAFETY: comments / # Safety doc sections / docs/contracts/*.toml declarations / spec-document section / AGENTS.md guidance).
4. Test, bench, and doc beads can be shared across multiple remediation beads. Many test beads cover N remediation beads.
5. NO bead may be closable without producing a named evidence artifact (e.g., `tests/artifacts/<bead-id>/proof_pack/`).
6. Title convention: `<verb> <object> <evidence-driver>` — e.g., "Promote IsNull opcode and verify MT8 attribution drop".
7. Body must include: hypothesis, expected_signal, one_line_invocation, falsifiability_criteria, closure_predicate (one of the 8 retry-vocabulary forms).
8. Per-bead labels: `pillar:perf|conformance|surface`, `kind:remediation|test|bench|doc`, `priority:p0|p1|p2|p3` (p0 = blocks release).
9. Per-bead dependencies: explicit `depends_on: [<bead-id>, <bead-id>, ...]`.

Convert the input plan now. Output ONLY the JSONL beads spec. No preamble.
```

### Example (one remediation bead converted)

Input plan entry:
```
GAP: IsNull VDBE opcode contributes 0.51% MT8 self-time; siblings SCopy/IfNot already promoted with +30%-ish wins.

Isomorphic-rewrite alternatives:
  A. Promote IsNull into try_execute_hot_opcode (Pattern 1).
  B. Inline the IsNull branch at every step() call site.
  C. Replace IsNull with a JIT-compiled version.

Rubric:
  A: Impact 4 × Confidence 5 / Effort 1 = 20
  B: Impact 3 × Confidence 4 / Effort 3 = 4
  C: Impact 5 × Confidence 2 / Effort 5 = 2

Selected: A. Rationale: Pattern 1 is proven; siblings have keep entries.

Acceptance criteria:
  - test: oracle E2E for IsNull predicates passes (CONF-0001 covers)
  - bench: comprehensive-bench + mt-mvcc-bench both improved; .bench-history updated
  - docs: PART XIII pattern catalog references the new opcode promotion
```

Output JSONL beads:
```jsonl
{"id":"bd-p13-r17-1","title":"Promote IsNull opcode and verify MT8 attribution drop","body":"hypothesis: Pre-matching IsNull in try_execute_hot_opcode produces ≥5% MT8 throughput improvement and removes the 0.51% IsNull frame from top-10 self-time table.\nexpected_signal: ≥5% throughput on mt_mvcc_bench --threads=8; IsNull frame ≤0.1% in candidate flamegraph.\none_line_invocation: cargo bench --bench mt_mvcc --profile release-perf -- --threads=8 --iters=3\nfalsifiability_criteria: Gain <0.1% (noise) OR IsNull frame ≥0.5%.\nclosure_predicate: Retry condition not applicable — gain is structural per Pattern 1.","labels":["pillar:perf","kind:remediation","priority:p1"],"depends_on":["bd-p13-r17-2","bd-p13-r17-3","bd-p13-r17-4"]}
{"id":"bd-p13-r17-2","title":"Confirm IsNull predicate oracle E2E remains green after promotion","body":"hypothesis: Oracle E2E for NULL/IS NULL/IS NOT NULL predicates passes both before and after IsNull promotion.\nrun: cargo test -p fsqlite-e2e --test null_semantics_oracle_e2e\nartifact: tests/artifacts/conformance/CONF-0001/oracle_replies.json","labels":["pillar:conformance","kind:test","priority:p1"],"depends_on":[]}
{"id":"bd-p13-r17-3","title":"Capture mt_mvcc_bench + comprehensive_bench post-promotion baselines","body":"run: cargo bench --bench mt_mvcc --profile release-perf -- --threads=8 --iters=3 && cargo bench --bench comprehensive_bench --profile release-perf\nartifact: .bench-history/mt-mvcc-bench.latest.json + .bench-history/comprehensive_bench.latest.json","labels":["pillar:perf","kind:bench","priority:p1"],"depends_on":[]}
{"id":"bd-p13-r17-4","title":"Update PART XIII pattern catalog to reference IsNull promotion","body":"Edit COMPREHENSIVE_BREAKDOWN... PART XIII or analogous doc to add IsNull to the SCopy/IfNot promotion list with proof numbers.\nartifact: docs/part_xiii_pattern_catalog.md","labels":["pillar:perf","kind:doc","priority:p2"],"depends_on":[]}
```

---

## Polish Loop (4-5 Rounds)

Verbatim from `/beads-workflow`'s polish prompt:

```
You are polishing a beads dependency graph.

INPUT: a JSONL beads file produced by the previous round.

CONSTRAINTS:
1. DO NOT OVERSIMPLIFY. A bead that lacks falsifiability_criteria or closure_predicate is NOT simpler — it's broken. Add the missing fields.
2. DO NOT LOSE FEATURES. If the input has a bead with a label, preserve the label. If a dependency exists, preserve unless cycle-breaking requires moving it.
3. Identify near-duplicate beads. Merge ONLY if hypothesis text identical AND closure_predicate identical.
4. Identify orphan beads (no edges in or out). Either link to a parent remediation bead or delete with explicit rationale.
5. Identify cycles. Break by promoting one bead's dependency to a "blocks" comment and removing the back-edge.
6. Identify beads missing test/bench/doc dependencies. Add the missing ones.
7. Identify beads with empty body or stub title. Fail loudly; do NOT silently delete.
8. Priority recalibration: any bead labeled p0 that depends on a p2 bead is misclassified; either upgrade the dep or downgrade the remediation.

Output: polished JSONL. No preamble.
```

### How to run the polish loop

```bash
# Round 1 → 2 → 3 → 4 → 5
for round in 1 2 3 4 5; do
  cp <workspace>/.beads/round-${round}.jsonl /tmp/in.jsonl
  cat polish-prompt.md /tmp/in.jsonl | claude --model opus > /tmp/out.jsonl
  diff /tmp/in.jsonl /tmp/out.jsonl | tee <workspace>/.beads/polish-diff-${round}.txt
  cp /tmp/out.jsonl <workspace>/.beads/round-$((round + 1)).jsonl
done
```

The polish drafts live in `<workspace>/.beads/` so the gauntlet's own git repo
captures every revision. When the final round is steady, import the final JSONL
into `<target>/.beads/` and run `br sync --import-only --rebuild` from
`<target>`; worker agents execute the remediation graph from the target repo.

**Steady state:** the polish loop is done when `diff` between rounds N and N+1 is empty or all changes are whitespace/ordering. Typically 4-5 rounds; sometimes 7-8 for large graphs.

**"DO NOT OVERSIMPLIFY; DO NOT LOSE FEATURES"** — this discipline is non-negotiable. The polish loop is for catching missing fields, broken dependencies, and orphans. It is NOT for deleting beads or trimming text.

---

## Dependency Validation Rules

Every remediation bead MUST have, before close:

| Dependency | Form |
|---|---|
| **Test** | At least one of: oracle E2E test, metamorphic test, sanitizer-clean run, fuzz target, property test, golden-snapshot test. |
| **Benchmark** | At least one of: criterion microbench, hyperfine timing, comprehensive-bench full matrix. |
| **Documentation** | At least one of: `// SAFETY:` comment block, `# Safety` rustdoc section, `docs/contracts/*.toml` declaration update, spec-document section, AGENTS.md guidance, PART XIII pattern catalog addition. |

### Validation script

`scripts/bead-graph-validator.sh` runs:

```bash
br dep cycles                        # must output empty (no cycles)
bv --robot-insights | jq '(.Cycles // []) | length == 0'
br list --label kind:remediation --json | jq -r '(.issues // .)[]?.id' | while read bead; do
  deps=$(br show --json "$bead" | jq -r '.dependencies[]?.id // .dependencies[]? // empty')
  has_test=$(echo "$deps" | xargs -r -I{} br show {} --json | jq -r 'select((.labels // []) | index("kind:test")) | .id' | head -1)
  has_bench=$(echo "$deps" | xargs -r -I{} br show {} --json | jq -r 'select((.labels // []) | index("kind:bench")) | .id' | head -1)
  has_doc=$(echo "$deps" | xargs -r -I{} br show {} --json | jq -r 'select((.labels // []) | index("kind:doc")) | .id' | head -1)
  test -n "$has_test" || echo "FAIL: $bead missing test dep"
  test -n "$has_bench" || echo "FAIL: $bead missing bench dep"
  test -n "$has_doc" || echo "FAIL: $bead missing doc dep"
done
```

Non-empty output = validation failure = Phase 13 is not complete; loop back to polish.

---

## `br dep cycles` Empty

The fundamental graph invariant: a beads graph with cycles cannot terminate. Every cycle must be broken.

### How to compute

```bash
br dep cycles --json | jq '.cycles'
```

Output is an array. Empty array = no cycles.

### How to fix a non-empty cycle

A cycle `A → B → A` typically means two beads incorrectly mutually depend. Common patterns:

1. **Test bead depends on remediation bead AND vice versa.** Fix: the test bead should depend on the *artifact* of the remediation, not the remediation itself. Remove one edge; add a doc comment "blocks-after `<bead>`".
2. **Doc bead depends on remediation, remediation depends on doc.** Fix: doc beads have no remediation dependencies. Remove the remediation→doc edge.
3. **Two remediation beads mutually depend.** Fix: extract the shared work into a third "preparatory" bead that both depend on.

The polish loop catches most cycles in round 2.

---

## `bv --robot-insights` Cycles Empty

`bv` (beads-visualizer) provides a different cycle-detection path. Run alongside `br dep cycles` for cross-validation.

```bash
bv --robot-insights --json > /tmp/bv.json
jq '(.Cycles // []) | length == 0' /tmp/bv.json
jq '.OrphanBeads' /tmp/bv.json  # must be empty
jq '.Stats.MaxDepth' /tmp/bv.json  # warn if >7 (graph too deep; consider hierarchy refactor)
```

---

## Per-Bead Acceptance Criteria

A bead is closable when ALL of:

1. **Proof artifact uploaded.** `tests/artifacts/<bead-id>/proof_pack/` exists and contains the baseline + candidate evidence (flamegraphs, samply.json, criterion CSV, FailureBundle on negative, etc.).
2. **Ratchet lower-bound non-regressed.** `apply-ratchet.sh` returns `Allow` (not `Block`, `Quarantine`, or `Waiver`). The per-category conformal lower bound did not drop.
3. **FailureBundle empty for affected scenarios.** No `FailureBundle v1.0.0` files exist for the scenarios this bead claims to fix.
4. **Test dependency green.** Test bead's `one_line_invocation` returns 0.
5. **Bench dependency green.** Bench bead's artifact (`*.latest.json`) committed and within the gate thresholds.
6. **Doc dependency green.** Doc edit committed; if updating a contract TOML, loader passes.

`scripts/can-close-bead.sh <bead-id>` returns 0 iff all 6 hold.

---

## Bead Naming Convention

From FrankenSQLite (which uses `BEAD_ID-per-module` discipline):

| Pattern | Example | Meaning |
|---|---|---|
| `bd-NNNN` | `bd-4ndk2` | Short opaque IDs (default). |
| `bd-NNNN.M.K` | `bd-1dp9.1.2` | Hierarchical: parent `bd-1dp9`, sub-tree `.1`, leaf `.2`. |
| `bd-pNN-rNN-N` | `bd-p13-r17-1` | Phase + Run + Sequence (gauntlet-internal). |

The gauntlet uses `bd-p<phase>-r<run>-<seq>` for beads it creates; for beads the target project owns, use whatever the target's convention is.

### Hierarchical pattern (recommended for large remediation sets)

```
bd-p13-r17-1           "Cluster: VDBE opcode promotions"
bd-p13-r17-1.1         "Promote IsNull (Pattern 1)"
bd-p13-r17-1.2         "Promote IfNullRow (Pattern 1)"
bd-p13-r17-1.3         "Promote NotExists (Pattern 1)"
bd-p13-r17-1.99.test   "Shared test bead for cluster 1"
bd-p13-r17-1.99.bench  "Shared bench bead for cluster 1"
bd-p13-r17-1.99.doc    "Shared doc bead for cluster 1"
```

The `.99.*` convention reserves the high end for shared support beads; the `.1`, `.2`, `.3` are the work items.

---

## See Also

- [ORCHESTRATION.md](ORCHESTRATION.md) — fan-out + lane assignment + reservations
- [SKILL-BOOTSTRAP.md](SKILL-BOOTSTRAP.md) — Phase 0.5 detail
- [../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md](../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md) — the hypothesis-ledger primitive that remediation beads draw from
- [../remediation/REMEDIATION-PATTERNS.md](../remediation/REMEDIATION-PATTERNS.md) — the 10 patterns most remediations land on
- [../remediation/ISOMORPHISM-PROOF-TEMPLATE.md](../remediation/ISOMORPHISM-PROOF-TEMPLATE.md) — the 5-line proof every remediation bead's commit must include
