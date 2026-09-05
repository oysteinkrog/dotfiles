# Beads Seed

Paste-ready seed for a fresh gauntlet bead graph. For a real remediation campaign, copy `issues.jsonl` into `<target>/.beads/` and run `br sync --import-only --rebuild` from `<target>` so worker agents see the graph in the repo they are editing. For workspace-only planning, the same seed can be loaded into `<workspace>/.beads/`.

## What this gives you

23 root beads covering Phases 0-9 (the floor every gauntlet adopts). The dependency graph is acyclic (`br dep cycles` returns empty) and every bead carries:

- `pattern:NN-NAME` prefix in the title (so the graph stays grep-able)
- `priority`: 1 (kernel/critical) / 2 (substantial) / 3 (optional but recommended)
- `labels`: at least `["gauntlet", <pillar>, <subtopic>]`
- `description` cross-referencing the relevant pattern in `references/patterns/`
- `depends_on` + `blocks` arrays expressing the build order

## Dependency graph (textual)

```
bd-gauntlet-001 (kernel axioms)
├── bd-gauntlet-002 (reference pinning)
│   ├── bd-gauntlet-003 (engine identity)
│   │   ├── bd-gauntlet-005 (differential v2)
│   │   │   ├── bd-gauntlet-007 (metamorphic)
│   │   │   └── bd-gauntlet-009 (fixture root contract)
│   │   └── bd-gauntlet-006 (scenario template)
│   │       └── bd-gauntlet-008 (mismatch minimizer)
│   ├── bd-gauntlet-004 (preflight doctor)
│   │   └── bd-gauntlet-009
│   ├── bd-gauntlet-015 (comprehensive-bench)
│   │   ├── bd-gauntlet-016 (bench-history ratchet)
│   │   └── bd-gauntlet-017 (hot-path counters)
│   │       └── bd-gauntlet-019 (MT8 attribution)
│   └── bd-gauntlet-020 (FeatureUniverse)
│       └── bd-gauntlet-022 (verification contract)
└── bd-gauntlet-023 (negative ledger + AGENTS.md mandate)

bd-gauntlet-007 + bd-gauntlet-008 → bd-gauntlet-010 (FailureBundle)
bd-gauntlet-010 → bd-gauntlet-012 (first-failure explainer)
bd-gauntlet-009 → bd-gauntlet-011 (FaultSpec) → bd-gauntlet-013 (crash boundaries) → bd-gauntlet-014 (e-processes) → bd-gauntlet-018 (Bayesian conformal) → bd-gauntlet-021 (ratchet wired in CI)
```

## Verification

After seeding:

```bash
br dep cycles --json | jq '(.cycles // []) | length == 0'
bv --robot-insights | jq '(.Cycles // []) | length == 0'
bv --robot-triage                          # next-pick top picks should align with priority 1
./scripts/bead-graph-validator.sh <target> --output-root <workspace>  # asserts every remediation bead has test+bench+doc deps (n/a here — these are SEED beads, not remediation; the gate doesn't apply)
```

## Adding remediation beads on top of seed

When Phase 12 produces remediation beads, they must DEPEND on the seed beads (you can't remediate an oracle divergence before the oracle exists). Convention:

- Remediation bead title: `remediate:<pillar>:<gap-id>` (e.g., `remediate:perf:p-024-vdbe-dispatch`)
- Add label `kind:remediation` so `scripts/bead-graph-validator.sh` checks the bead.
- Add `depends_on: ["bd-gauntlet-006", "bd-gauntlet-015"]` (or whichever floor beads are prerequisites)
- Add `blocks: []` until follow-on remediations are spawned

## Round-N additions

When iteration round N spawns new beads, name them `bd-round-N-<seq>` to keep the timeline traceable. The polished bead graph at Phase 13 will have hundreds; the seed is just the floor.
