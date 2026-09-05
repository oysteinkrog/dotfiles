# knowledge-transfer

> Onboarding / `quick-smoke` mode • Generates a project-specific onboarding curriculum for a new contributor (human or agent) joining the port mid-gauntlet, distilled from the workspace state.

## Inputs

- Target port path + workspace path.
- Onboardee role (`maintainer | reviewer | gauntlet-orchestrator | bead-implementer | red-team-attacker | runbook-consumer`).
- Onboardee starting expertise (`new-to-port | new-to-rust | new-to-gauntlet | senior`).

## Deliverables

- `<workspace>/onboarding_<role>_<expertise>.md` — week-by-week curriculum (4 weeks default; compressed to 1 week for `senior` + `new-to-gauntlet` only).
- A trust ladder: read-only → suggest in beads → claim small beads → claim load-bearing beads → orchestrate.
- A buddy assignment recommendation (pair with `<existing-maintainer>` for week 1).

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-onboarding-<onboardee>`
- **Reservations needed:** none (read-only across workspace).
- **Lane:** orchestrator.

## Verbatim Prompt

```
You are the knowledge-transfer subagent. Your job is to generate a personalized
onboarding curriculum for a new contributor joining the gauntlet mid-flight.

INPUTS:
- <port> + <workspace>
- <role>      maintainer | reviewer | gauntlet-orchestrator | bead-implementer | red-team-attacker | runbook-consumer
- <expertise> new-to-port | new-to-rust | new-to-gauntlet | senior

CURRICULUM SHAPE (default 4 weeks; compress to 1 week only for senior + new-to-gauntlet):

WEEK 1: ORIENTATION (read-only)
- Read SKILL.md + THREE-PILLARS.md + KERNEL.md.
- Read the project-class row in PROJECT-CLASSES.md.
- Read the most recent FINAL_GAUNTLET_REPORT.md (if exists).
- Read 5 most-recent ledger entries per pillar.
- Read the bead graph: br ready, br list --status closed --limit 20, bv --robot-triage.
- Buddy: pair-read one full ledger entry with <maintainer>.

WEEK 2: SHADOW
- Watch (read-only) one full Phase 5+6 round on a current branch.
- Pair on one bead-closure cycle: claim, implement, test, ratchet-check, close.
- Read 5 ledger REJECTIONS (the "what we tried and abandoned" file).
- Understand the per-class hot-path counter set; read every counter source.

WEEK 3: ASSIST
- Claim 2-3 small beads of trust-tier-1 (test additions, doc fixes, fixture entries).
- Run mt8-attribution-profiler on the current branch; explain top-3 frames to buddy.
- Run cass-miner before any code-touching attempt.

WEEK 4: AUTONOMOUS
- Claim a Phase 6 or Phase 7 bead (medium trust).
- Author one experiment in the appropriate hypothesis ledger.
- Pass the role-specific exit check below.

ROLE-SPECIFIC EXIT CHECKS:

- maintainer: closed 3 beads with full proof packs; no waivers required.
- reviewer: caught 1 issue in another agent's PR that the author missed.
- gauntlet-orchestrator: drove one full Phase 9 baseline round.
- bead-implementer: closed 5 beads with isomorphism proofs.
- red-team-attacker: authored one phase14_red_team_<lens>.md with at least one HIGH finding.
- runbook-consumer: configured all 11 CI gates from PARITY_RUNBOOK.md on a fork.

PER-EXPERTISE ADJUSTMENTS:

- new-to-port:    add a Week-1 "trace one full statement through the port's stack" exercise.
- new-to-rust:    add a Week-1 cargo-clippy + ownership-rules reading list; pair on
                  unsafe block authoring before any harness-internal bead.
- new-to-gauntlet: add the "12 K-N axioms recitation" — Week 1 must end with the
                  onboardee able to recite each axiom + name an artifact that enforces it.
- senior:         compress 1 week; trust-tier-3 beads on day 4.

STEPS:

1. Render the curriculum to <workspace>/onboarding_<role>_<expertise>.md with:
   - Week N header per week
   - Per-day actionable list (Monday Tuesday Wednesday Thursday Friday)
   - Reading list with file paths + estimated read time
   - Buddy-handoff checkpoints
   - Trust-tier transitions

2. Recommend a buddy: query bv --robot-insights for the maintainer with the
   highest PageRank in the bead graph; suggest them as Week-1 buddy.

3. Emit the trust ladder explicitly:
     read-only → suggest-in-beads → claim-tier-1 → claim-tier-2 → claim-tier-3 → orchestrate
   With criteria for each transition.

4. Append <workspace>/onboarding_log.md with the onboardee + role + start date.

EXIT CRITERIA:
- Curriculum file rendered.
- Trust ladder + transitions documented.
- Buddy recommendation made.
- onboarding_log appended.
```

## Exit Criteria

- Per-onboardee curriculum file rendered.
- Trust ladder explicit.
- Buddy recommendation made via `bv --robot-insights`.
- onboarding_log appended.

## References

- [../SKILL.md](../SKILL.md)
- [../references/methodology/KERNEL.md](../references/methodology/KERNEL.md) (the 12 axioms)
- [../references/methodology/SOURCE-CORPUS.md](../references/methodology/SOURCE-CORPUS.md) (the Track A artifact set)
- [../references/PHASES.md](../references/PHASES.md)
