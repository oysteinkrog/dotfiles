# Artifacts — Workspace File Shapes, Parsing Contracts, Merge Rules

Per `/operationalizing-expertise` Track B: artifacts are the structured output of the methodology. They must be **deterministically parseable** so a successor agent (or a CI job) can extract structured data.

This file documents every artifact the skill produces.

---

## Canonical workspace tree

```
<source>/.ub-exorcism/<run-id>/
├── phase0_run.json                    # run metadata (id, mode, partition)
├── phase0_toolchain_inventory.json    # what's installed + what was installed this run
├── phase0_partition.json              # the section partition
├── phase1_unsafe_surface_inventory.md # all unsafe sites, taxonomy-tagged
├── phase1_notes/
│   ├── <module-1>.md                  # per-module digest
│   └── ...
├── phase2_findings_<bucket>.md        # one per project-relevant bucket
├── phase2_summary.md                  # rollup
├── phase3_dynamic_findings.md         # miri/sanitizer/loom/fuzz findings
├── phase3_raw/
│   ├── miri_default.log
│   ├── miri_tree_borrows.log
│   ├── miri_strict_provenance.log
│   ├── miri_symbolic_alignment.log
│   ├── asan.log
│   ├── tsan.log
│   ├── msan.log                       # optional
│   ├── lsan.log
│   ├── loom.log
│   ├── shuttle_<primitive>.log        # one per primitive
│   ├── fuzz_<target>.log              # one per target
│   └── fuzz_artifacts/<target>/       # crash corpora
├── phase4_unified_findings.md         # the master findings table
├── UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md  # experiment registry (every UB hypothesis lives here)
├── experiments/
│   └── <exp-id>/
│       ├── repro.rs
│       └── Cargo.toml                 # only if standalone
├── phase5_experiment_results/
│   └── <exp-id>.log
├── phase6_idea_wizard.md              # round 1
├── phase6_idea_wizard_round_<N>.md    # rounds 2+
├── phase7_findings_snapshot_round_<N>.txt    # for diff against next round
├── phase7_needs_refinement_round_<N>.txt
├── phase7_convergence_round_<N>.json  # the gate
├── phase7_convergence_summary.md      # round-by-round counts
├── phase8_remediation_plan.md         # per-finding rewrite candidates + rubric
├── phase9_beads_log.md
├── phase10_fresh_eyes_log.md
├── phase11_soak_designs.md            # Exhaustive only
├── phase11_artifacts/
│   └── <campaign-id>/
├── FINAL_UB_REPORT.md
├── UB_RUNBOOK.md
├── phase13_remediation_log.md         # Phase 13 only (opt-in auto-remediation; one entry per bead processed; parse with awk per VALIDATION.md)
└── corpus/                            # /operationalizing-expertise Track A
    ├── primary_sources/
    │   ├── cass_quotes.md             # Q-NNN anchored
    │   └── exemplar_anchors.md        # E-NN anchored
    ├── quote_bank/
    │   └── quote_bank.md              # consolidated, marker-bounded
    ├── distillations/
    │   ├── opus/notes.md
    │   ├── codex/notes.md
    │   └── gemini/notes.md
    └── specs/
        ├── triangulated_kernel.md     # KERNEL-START/KERNEL-END markers
        ├── operator_library.md        # OPERATOR-START/OPERATOR-END markers
        └── session_kickoff.md
```

---

## Parsing contracts

### `phase0_run.json`

```json
{
  "run_id": "2026-05-14-frankensqlite-1",
  "started_at": "2026-05-14T00:00:00Z",
  "mode": "Standard",
  "source_path": "/data/projects/frankensqlite",
  "workspace_path": "/data/projects/frankensqlite/.ub-exorcism/2026-05-14-frankensqlite-1",
  "partition": [
    {"section": "vfs",   "source_subpath": "crates/fsqlite-vfs/src",   "subagent_id": "A"},
    ...
  ],
  "offload": "local | rch",
  "helper_skills_available": ["beads-workflow", "idea-wizard", "cass"]
}
```

### `phase0_toolchain_inventory.json`

See `scripts/install-toolchain.sh` — the script writes this file.

### `phase1_unsafe_surface_inventory.md`

Markdown table; one row per site. Parser: split by line, regex `^\| F-\d+ \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|`.

### `phase2_findings_<bucket>.md`

Each finding is a `## F-NNN: <title>` heading with bolded fields. Parser uses headings as anchors.

### `phase4_unified_findings.md`

A table with columns `F-ID | file:line | bucket | severity | static tools | dynamic tools | status`. Headings `## F-NNN: <title>` repeated below the table with full details.

### `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` — **the registry every UB hypothesis lives in**

Each experiment is a `## EXP-NNN: <title>` block with strictly-formatted fields:

```
**Finding ref:** F-NNN in phase4_unified_findings.md
**Bucket:** <one of the 25>
**Severity (Phase 2):** MUST-BE-UB | LIKELY-UB | SUSPICIOUS | CONTRACTUAL-BUT-DEFENSIBLE
**Hypothesis:** <falsifiable, one sentence>
**Minimal reproducer:** ```rust ... ``` (≤30 lines)
**Expected signal:** <specific tool diagnostic>
**Falsifiability:** <what evidence would refute>
**Invocation:** ```bash ... ```
**Verdict:** OPEN | CONFIRMED_UB | NO_EVIDENCE | NEEDS_REFINEMENT | DEFERRED
**Notes:** <free text, filled by experiment-executor>
```

**Parser invariants:**
- Verdict is *exactly one* of the 5 strings (no decoration). `convergence-tracker.sh` greps for `\*\*Verdict:\*\* {STRING}`.
- A single block has *exactly one* `**Verdict:**` line. Multiple = corruption.
- Follow-ups have IDs `EXP-NNN-a`, `EXP-NNN-b`, ... with `**Follow-up of:** EXP-NNN`.

### `phase7_convergence_round_<N>.json`

```json
{
  "round": 7,
  "verdicts": {"OPEN": 0, "CONFIRMED_UB": 12, "NO_EVIDENCE": 18, "NEEDS_REFINEMENT": 1, "DEFERRED": 2},
  "new_findings": 2,
  "new_needs_refinement": 1,
  "quiet": false,
  "prev_quiet": false
}
```

### `phase8_remediation_plan.md`

One section per CONFIRMED_UB finding. Structure:

```markdown
## R-NNN: Remediate F-NNN — <UB shape>

**Finding ref:** F-NNN
**UB shape:** <from REMEDIATION-PATTERNS.md or new>
**Proves UB:** EXP-NNN
**Proves remediation sound:** EXP-NNN-r (regression experiment, may need authoring)

### Candidate A: <title>
- Description
- Rubric: correctness=X, perf=Y, blast=Z, review=W, maint=V
- Tradeoffs

### Candidate B: <title>
... (same shape)

### Decision
**Chosen:** {A | B | C | ...}
**Rationale:** <why this beat the runner-up on the dominant axis>
**Runners-up retained for future revisit:** {A, B, ...}

### Triangulation (if high-stakes)
(consensus + dissent from /multi-model-triangulation)
```

---

## Merge rules

When the orchestrator re-enters a phase after a crash or compaction:

### Phase 2 merge

If `phase2_findings_<bucket>.md` exists for a bucket: read it; the next sweeper run for that bucket *appends* findings, never overwrites. Duplicates (same F-NNN) get a `## F-NNN (re-confirmed in round N)` note rather than a second row.

### Phase 4 merge

Re-synthesis re-reads everything. The unified-findings table is *rewritten* (deterministic from inputs). The `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` is *amended* — existing EXP-NNN blocks are preserved (including their verdicts); new ones append.

### Phase 5 merge

Verdicts are written *in place*. Concurrent writers conflict on the file reservation — use the `path://EXPERIMENT-DESIGNS.md` lock.

### Phase 8 merge

If a finding's `## R-NNN` block already exists, re-running Phase 8 amends the existing block (adds new candidates if rubric scoring suggests) rather than overwriting.

---

## Marker-bounded sections (extractable artifacts)

Per `/operationalizing-expertise` Track A, some artifacts have marker-bounded sections so they can be programmatically extracted.

### Triangulated kernel — `corpus/specs/triangulated_kernel.md`

```markdown
<!-- KERNEL-START -->
# UB-Exorcism Triangulated Kernel

## Invariant 1: <name>
...

## Invariant N: <name>
...
<!-- KERNEL-END -->
```

Extraction: `awk '/^<!-- KERNEL-START -->$/,/^<!-- KERNEL-END -->$/' triangulated_kernel.md`.

### Operator library — `corpus/specs/operator_library.md`

```markdown
<!-- OPERATOR-START id=SUSPECT symbol=★ -->
## ★ SUSPECT

**Trigger:** ...
**Prompt module:**
```
...
```
**Exit criterion:** ...
**Failure modes:** ...
<!-- OPERATOR-END id=SUSPECT -->

<!-- OPERATOR-START id=ISOLATE symbol=✦ -->
...
<!-- OPERATOR-END id=ISOLATE -->
```

Extraction: per operator via `awk '/<!-- OPERATOR-START id=NAME/,/<!-- OPERATOR-END id=NAME/'`.

### Quote bank — `corpus/quote_bank/quote_bank.md`

```markdown
<!-- Q id=001 source=cass tag=miri-tree-borrows project=frankensqlite -->
> verbatim quote here
**Citation:** <session path>:<line>:<date>
<!-- /Q id=001 -->
```

Extraction: `awk '/<!-- Q id=NNN/,/<!-- \/Q id=NNN/'`.

---

## Post-fan-out verification

After every parallel fan-out (Phase 1 RECON, Phase 2 STATIC, Phase 3 DYNAMIC, Phase 5 EXPERIMENT, Phase 6 IDEA-WIZARD), the orchestrator MUST verify every declared output file actually exists on disk. Subagents occasionally complete without writing (e.g., wrong `subagent_type=Explore` silently breaks file output — see [AGENT-PROMPTS.md §Subagent type matrix](AGENT-PROMPTS.md#subagent-type-matrix-read-first)). A "completed" subagent whose output file is missing is a phase-completion BLOCKER.

```bash
# Phase 1 example:
for module in $(jq -r '.partition[].section' phase0_run.json); do
    test -f "phase1_notes/${module}.md" || {
        echo "MISSING: phase1_notes/${module}.md (subagent reported done but file not on disk)" >&2
        exit 1
    }
done
test -s phase1_unsafe_surface_inventory.md  # also non-empty

# Phase 2 example:
for bucket in $(jq -r '.applicable_buckets[]' phase0_run.json); do
    test -f "phase2_findings_${bucket}.md" || exit 1
done

# Phase 6 example (multi-round):
TOTAL_ROUNDS=$(jq -r '.mode' phase0_run.json | grep -q exhaustive && echo 3 || echo 2)
for r in $(seq 1 $TOTAL_ROUNDS); do
    test -f "phase6_idea_wizard_round_${r}.md" || exit 1
done
test -f phase6_idea_wizard_rollup.md  # final round generates this
```

If a file is missing, the subagent's response text usually contains the findings — the orchestrator should transcribe them into the expected file **and** flag the run for the failure mode (Explore vs general-purpose mis-typing is the #1 cause). Then re-spawn the subagent with the correct `subagent_type` for any work that needs to be redone with real source-reads.

A handy one-liner for the orchestrator at end-of-phase:

```bash
./scripts/verify-phase-artifacts.sh "$WORKSPACE" "$PHASE_NUMBER"
```

Keep this tool simple — it's a tripwire that reports missing artifacts so the
orchestrator can re-spawn the affected subagent, not a fix-it that tries to
synthesize the artifact itself.

---

## Validation scripts

`scripts/validate-corpus.py` — checks every quote has a citation; checks every kernel invariant cites ≥2 distillation sources; checks every operator has triggers + prompt module + exit criteria.

`scripts/validate-operators.py` — checks operator-library markers are well-formed (start/end matched, no nesting).

`scripts/extract-kernel.py` — extracts the kernel between markers, validates each invariant.

`scripts/lint-experiment-designs.py` — checks every `## EXP-NNN` block has all required fields; verdict is one of the 5 exact strings; reproducer is ≤30 lines.

These are *artifact validators*, separate from the writing-skills validator (`scripts/validate-skill.py`).

---

## Compaction-survival contract

A successor orchestrator must be able to resume from disk alone. The contract:

1. The skill never relies on in-memory state across phases.
2. Every phase's output is a marker-recognizable file.
3. Phase progress is determined by reading the files in `<workspace>/`:
   - If `phase1_unsafe_surface_inventory.md` missing or empty → resume Phase 1.
   - If any `phase2_findings_<bucket>.md` missing → resume Phase 2.
   - If `phase4_unified_findings.md` missing → resume Phase 4.
   - If `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` has any `**Verdict:** OPEN` line → resume Phase 5.
   - If highest `phase7_convergence_round_<N>.json` shows `"quiet": false` → re-run Phase 2-6.
   - If `phase8_remediation_plan.md` missing → resume Phase 8.
   - ... etc.

The orchestrator's resume protocol is in [ORCHESTRATION.md §Compaction Survival](ORCHESTRATION.md#compaction-survival).
