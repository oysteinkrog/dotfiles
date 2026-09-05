# Skill Card — World-Class Doctor Mode for CLI Tools

One-page elevator pitch. Print this if you're trying to decide whether to run the skill.

---

## What it does

You point this skill at a CLI tool repo (Rust, Go, Python, TS/Node, Bun, Deno, Ruby, C/C++, Zig, Elixir, Bash). The skill **adds** or **dramatically upgrades** that tool's `doctor` subcommand until it satisfies a 24-axiom kernel (17 universal + 7 stretch axioms) and scores ≥ 700 on a 10-dimension rubric — automated, safe-by-default, idempotent, reversible, backup-aware, agent-ergonomic.

Every run leaves a persistent, schema-versioned scoring artifact at `.doctor/runs/<ISO8601>__<run-id>/` so the next pass can measure uplift.

---

## The pitch in three lines

1. **A doctor is a contract with a future agent who has no context.** Every output, error, and flag exists to answer "what's wrong?" and "what's the next move?" — without forcing the agent to guess.
2. **Detect-then-fix; mutations flow through ONE chokepoint.** `mutate(path, op)` is the only function that touches disk under `--fix`. Get this right and reversibility, idempotence, observability, crash-recovery, and concurrency-safety come almost for free.
3. **Plans atrophy on contact with reality; pass after pass.** A doctor is never finished. The skill is re-entered idempotently; aggregate-score regressions > 50 pts are hard-stops; trends are tracked in `.doctor/scorecard_history.jsonl`.

---

## What you get out of one full pass

| Artifact | Lives at | Audience |
|----------|----------|----------|
| `<tool> doctor` (default subcmd: `diagnose`) | target repo, on `doctor-mode-pass-<N>` branch | every agent + user |
| `<tool> doctor --fix` with backups + undo | target repo | every agent + user |
| `<tool> doctor capabilities --json` | runtime-emitted | agents, CI |
| `<tool> doctor robot-docs` | runtime-emitted | agents |
| `<tool> doctor health` (< 200 ms) | runtime-emitted | CI scheduling |
| `<tool> doctor --robot-triage` (mega-command) | runtime-emitted | agents |
| `<tool> doctor undo <run-id>` | runtime-emitted | agents + user |
| `tests/doctor_fixtures/<fm-id>/{corrupt.sh,assert.sh}` × N | target repo | CI |
| `.doctor/runs/<id>/{report.json,actions.jsonl,backups/,undo.sh}` per run | target repo | postmortem |
| `<workspace>/scorecard_pass_<N>.md` + `heatmap.svg` | sibling workspace | trend tracking |
| `<workspace>/HANDOFF.md` | sibling workspace | next-pass agent |

---

## Six-line invocation

```
> Apply world-class-doctor-mode-for-cli-tools to /dp/<your-project>.

> Mode: upgrade (existing diagnostic surface detected).
> Operating location: worktree (default; doctor-mode-pass-1 branch).
> Triangulation: multi-model.
> CASS: deep.
> Online: offline-only.
```

That's it. The skill walks you through Phase 0 confirmations, then runs the 10-phase loop autonomously.

---

## Six things the skill will never do

1. Delete a file. (AGENTS.md RULE 1; quarantine via `Op::Rename` instead.)
2. Run `rm -rf` / `git reset --hard` / `git clean -fd` / any forbidden destructive shell. (Implemented in code, scoped, recorded.)
3. Push to `main` / `master`. (Always feature branch; merge with explicit user approval.)
4. Probe the network without `--online`. (Offline-by-default; opt-in.)
5. Write outside `capabilities::write_scopes`. (`mutate()` enforces.)
6. Mutate state when the project's lock is held. (Refuses with exit 5; never compounds damage.)

---

## When to use

- "Add a `doctor` subcommand to this CLI." (Mode: `add`.)
- "Upgrade `<tool>`'s doctor — make it world-class." (Mode: `upgrade`.)
- "Score this CLI's doctor against the rubric — no code changes." (Mode: `audit-only`.)
- "Convert `fixing-beads-problems` (or other manual playbook) into automated `<tool> doctor --fix`." (Mode: `absorb-playbook`.)
- "Re-run the doctor build on `<tool>` and tell me what improved since pass-N." (Mode: `re-score-only`.)
- "I just changed one fixer; what's its new score?" (Mode: `single-failure-mode-rescore`.)

---

## When NOT to use

- The CLI is a toy / pre-1.0 prototype with zero recurring incidents. (Build the doctor when you find yourself running the same recovery commands twice.)
- The CLI is a third-party tool you can't modify. (See [Pattern 8](../references/methodology/COOKBOOK.md): a wrapper doctor still works, but the upstream's `--help` is the contract you're working against.)
- You want a 5-minute fix. (The skill is designed for production-quality outcomes; 1–4 hours typical wall time at Pair tier; 4–8h at Squad; 8–16h at Swarm.)

---

## Time budget

| Tier | Wall time per pass | Cost | Triangulation |
|------|---------------------|------|---------------|
| Solo | 1–2 h | 1× | none |
| Pair | 2–4 h | 2.5× | peer-claude |
| Squad | 4–8 h | 6× | peer-claude or multi-model |
| Swarm | 8–16 h | 12×+ | multi-model |

Termination thresholds (median uplift < 25 pts, no regression > 50 pts, two clean fresh-eyes rounds) usually take 1–3 passes for `add` mode, 1–2 passes for `upgrade`.

---

## Read me first

If you have 5 minutes: read SKILL.md's "One Rule" + "Mode Router" + "The Phase Loop".
If you have 30 minutes: read SKILL.md fully + skim KERNEL.md + COOKBOOK.md.
If you have 2 hours and want to run it: read all of the above + WORKED-EXAMPLE.md + the recipe matching your project's language.

The skill's entry point is SKILL.md. Every other file is a pull-when-needed reference.
