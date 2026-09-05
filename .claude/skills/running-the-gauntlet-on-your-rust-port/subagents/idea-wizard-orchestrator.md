# idea-wizard-orchestrator

> Phase 10 • Invoke `/idea-wizard` Phase 2 prompt verbatim to generate clever non-obvious gauntlet techniques for this specific port; winnow 30 → 5 → 10 more; promote into experiments.

## Inputs
- Phase 9 baseline outputs (perf, conformance, surface).
- `GAUNTLET_EXPERIMENT_DESIGNS.md` (current open hypotheses).
- `<workspace>/docs/progress/perf-negative-results.md` (avoid rediscovering known dead-ends).
- The three pillar ledgers.

## Deliverables
- `<workspace>/phase10_idea_wizard_round_<round>.md` with the 30 raw candidates, the top-5 winnowed picks, the 10 deeper picks, and one experiment-design entry per promoted technique.
- `<workspace>/GAUNTLET_EXPERIMENT_DESIGNS.md` appended with new entries.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase10-idea-wizard`
- **Reservations needed:** `tool://idea-wizard` (TTL 90m).
- **Lane:** cross-cutting (orchestrator).

## Verbatim Prompt

Invoke `/idea-wizard` against the gauntlet workspace using the Phase 2 prompt verbatim:

> 30 clever non-obvious gauntlet techniques for THIS specific port — perf attribution moves, conformance corner cases, surface-coverage blind spots — then winnow to top 5, then 10 more.

After /idea-wizard completes, for each of the top 5 picks AND each of the 10 deeper picks, file an experiment-design entry into `GAUNTLET_EXPERIMENT_DESIGNS.md` using the template at `../assets/experiment-design-template.md`. Each entry needs:

- **Hypothesis** — one sentence, falsifiable.
- **Minimal repro** — exact one-line invocation.
- **Expected signal** — what the bench / oracle / fuzz / e-process output would look like if the hypothesis is true.
- **Falsifiability** — what output would refute the hypothesis.
- **One-line invocation** — `cargo bench --bench <X>` or `cargo test --test <Y> -- <Z>` or `cargo fuzz run <T>`.
- **Results inline** — left empty for the experiment runner to fill.
- **Open hypothesis status** — `OPEN` initially; later becomes `CONFIRMED_GAP | NO_EVIDENCE | NEEDS_REFINEMENT | NEW_HYPOTHESIS_SPAWNED`.

**Discipline rules:**
- Do NOT propose techniques already in the negative-evidence ledgers as resolved. Check `perf-negative-results.md` first; cite the entry if revisiting (and only revisit if the entry's retry-condition predicate is satisfied).
- "Clever non-obvious" means: a technique that would surprise an engineer who already understands the obvious approach. Not "use criterion"; rather "exploit the algebraic redundancy between counter A and counter B to halve the hot-path counter cost".
- Bias toward techniques that produce structured evidence (a new counter, a new metamorphic relation, a new e-process invariant, a new fault profile) rather than ad-hoc one-shot fixes.

For each of the 10 deeper picks, write a one-paragraph rationale explaining what makes the technique non-obvious AND high-leverage for the gauntlet (not just for the port).

Document the round in `phase10_idea_wizard_round_<round>.md`. The iteration coordinator increments `<round>` and re-invokes you on each loop iteration.

## Exit Criteria
- `phase10_idea_wizard_round_<round>.md` exists with 30 raw candidates, top-5, 10-more, and rationale per deeper pick.
- `GAUNTLET_EXPERIMENT_DESIGNS.md` appended with ≥5 new entries (the top-5) AND optionally up to 10 more (the deeper picks).
- Each new entry has every field in the experiment-design template populated.
- No promoted technique duplicates a resolved entry in `perf-negative-results.md` without citing the prior entry and satisfying its retry-condition predicate.

## References
- [PHASES.md § Phase 10](../references/PHASES.md)
- [experiments/EXPERIMENT-DESIGNS-TEMPLATE.md](../references/experiments/EXPERIMENT-DESIGNS-TEMPLATE.md)
- [methodology/RETRY-CONDITION-VOCABULARY.md](../references/methodology/RETRY-CONDITION-VOCABULARY.md)
- [assets/experiment-design-template.md](../assets/experiment-design-template.md)
