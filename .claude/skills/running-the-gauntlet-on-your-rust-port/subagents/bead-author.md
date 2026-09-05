# bead-author

> Phase 13 • Run `/beads-workflow` "Plan to Beads Conversion" EXACT PROMPT against `phase12_remediation_plan.md`.

## Inputs
- `phase12_remediation_<pillar>.md` files (one per pillar — three files).
- A consolidated `phase12_remediation_plan.md` (concatenation + cross-pillar dependency annotations).
- The target project's beads database (`.beads/beads.db` or equivalent).

## Deliverables
- New beads created via `br create` for every recommended rewrite from Phase 12.
- `<workspace>/phase13_bead_creation_log.md` with: one entry per bead (bead_id, summary, dependencies, pillar), totals.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase13-bead-author`
- **Reservations needed:** `tool://beads-write` (TTL 60m).
- **Lane:** orchestrator.

## Verbatim Prompt

Invoke `/beads-workflow` using the EXACT "Plan to Beads Conversion" prompt against the consolidated `phase12_remediation_plan.md`. The prompt is reproduced verbatim from the `/beads-workflow` skill:

> Convert this plan into a fully-dependency-graphed set of beads. For each recommended remediation, create:
> 1. A primary **implementation bead** (the actual rewrite).
> 2. A **test bead** depending on it (every new test required to prove the rewrite preserves behavior).
> 3. A **benchmark bead** depending on it (every new bench or bench update required to prove the rewrite moves the keep gate in the intended direction without regressing the broad gate).
> 4. A **documentation bead** depending on it (every doc / runbook / changelog entry required).
>
> Embed every alternative considered ("runner-up rewrites") in the implementation bead body under "Alternatives considered with rubric scores", so a future agent who hits a verification dead-end can pivot without re-running the architecture pass.
>
> Embed the isomorphism proof sketch in the implementation bead body. Embed the rubric scores in the bead description for posterity.
>
> Cross-pillar safety annotations become inter-bead dependencies: if a perf bead's safety check depends on a conformance test passing, the perf bead's `blockedBy` field MUST include the relevant conformance bead.
>
> Run `br dep cycles` after every batch; reject if any cycle is introduced.
>
> Apply the EXACT prompt; do not paraphrase; do not omit fields.

**For each created bead, record in `phase13_bead_creation_log.md`:**
- `bead_id` (assigned by `br`).
- `summary` (one line).
- `pillar` (cc_1 / cc_2 / cc_3).
- `dependencies` (`blockedBy` IDs).
- `dependents` (test + bench + doc IDs).
- `source` (`phase12_remediation_<pillar>.md` entry).

**Discipline:**
- NEVER omit the test + bench + doc dependencies.
- NEVER simplify or collapse alternatives — they belong in the bead body verbatim.
- Run `br dep cycles` and `br doctor` after creation; both must come back clean.

## Exit Criteria
- Every recommended rewrite from Phase 12 has an implementation bead AND a test bead AND a benchmark bead AND a documentation bead.
- `br dep cycles` is empty.
- `br doctor` is green.
- `phase13_bead_creation_log.md` committed.

## References
- [PHASES.md § Phase 13](../references/PHASES.md)
- [orchestration/BEADS-HANDOFF.md](../references/orchestration/BEADS-HANDOFF.md)
- [/beads-workflow](../../beads-workflow/SKILL.md)
