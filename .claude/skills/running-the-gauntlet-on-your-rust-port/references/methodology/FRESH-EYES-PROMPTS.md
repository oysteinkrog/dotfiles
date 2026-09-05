# Fresh-Eyes Prompts — Verbatim

Phase 14 runs three calibrated prompts in sequence. Each is verbatim — DO NOT paraphrase or tighten. The phrasing IS the discipline; the same words have been validated across hundreds of FrankenSQLite review cycles to surface the specific class of bug each one targets.

These prompts are also installed in `subagents/fresh-eyes-reviewer-{a,b,c}.md` for orchestrator dispatch.

---

## Prompt A — "You just wrote this"

```
great, now I want you to carefully read over all of the new code you just wrote
and other existing code you just modified with "fresh eyes" looking super
carefully for any obvious bugs, errors, problems, issues, confusion, etc.
Carefully fix anything you uncover.
```

**Targets:** authoring-mode blind spots. The agent who just wrote 600 lines of `metamorphic.rs` has the highest baseline confidence in those 600 lines — and the most rationalization invested. Re-reading after a small context shift surfaces 20-40% of the bugs that final-review would otherwise catch.

**Use when:** you've just finished a substantive chunk of new code OR a substantive edit to existing code. NOT just for Phase 14; also use mid-phase before claiming a bead is closable.

---

## Prompt B — "Random exploration + AGENTS.md compliance"

```
I want you to sort of randomly explore the code files in this project, choosing
code files to deeply investigate and understand and trace their functionality
and execution flows through the related code files which they import or which
they are imported by. Once you understand the purpose of the code in the larger
context of the workflows, I want you to do a super careful, methodical, and
critical check with "fresh eyes" to find any obvious bugs, problems, errors,
issues, silly mistakes, etc. and then systematically and meticulously and
intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and
ensure that any code you write or revise conforms to the best practice guides
referenced in the AGENTS.md file.
```

**Targets:** unfamiliarity-driven oversight. Forces the agent to wander into code it didn't write, build a mental model of the larger architecture, then check the parts. Surfaces:
- Implicit assumptions that broke after a refactor.
- Inconsistencies between files written by different sessions.
- AGENTS.md violations (e.g., `git reset --hard` snuck into a script, file proliferation patterns, missing fresh-eyes pass on a prior change).
- Best-practice drift (e.g., a new file doesn't follow the per-class checklist in `assets/per-class-checklists/`).

**Use when:** mid-iteration in a long-running phase, OR when joining a workspace mid-flight (fresh-cold-start agent).

---

## Prompt C — "Review your fellow agents' work"

```
Ok can you now turn your attention to reviewing the code written by your fellow
agents and checking for any issues, bugs, errors, problems, inefficiencies,
security problems, reliability issues, etc. and carefully diagnose their
underlying root causes using first-principle analysis and then fix or revise
them if necessary? Don't restrict yourself to the latest commits, cast a wider
net and go super deep!
```

**Targets:** cross-agent quality drift. The most common bug class in multi-agent swarms: agent A's contract assumption doesn't match agent B's implementation; agent A's `// SAFETY:` comment cites an invariant agent C silently broke; agent B's bench result was on a different platform than agent A's bench-history baseline. The "first-principle analysis" framing forces re-derivation of why each piece exists, not pattern-matching against what looks right.

**Use when:** late in Phase 14, after the prior two prompts have run. Also use ad-hoc whenever you notice cross-agent friction.

---

## Application against the multi-target surface

Phase 14 applies each prompt against ALL of:
- the remediation plan (`phase12_remediation_*.md`)
- the bead graph (`.beads/issues.jsonl`)
- the experiment-design markdown files (`*_HYPOTHESIS_LEDGER.md`, `GAUNTLET_EXPERIMENT_DESIGNS.md`)
- the harness Rust code (`crates/<port>-harness/src/*.rs`, `crates/<port>-e2e/src/bin/*.rs`)
- the contracts (`docs/contracts/*.toml`, `docs/canonical_parity_contract.md`)
- the negative ledger (`PERF_NEGATIVE_RESULTS.md`, `CONFORMANCE_NEGATIVE_RESULTS.md`, `SURFACE_DEFERRALS.md`)

Iterate until two consecutive passes come up clean except for trivial changes (whitespace, typo-level). Then run the static gates:
- `ubs` (if installed)
- `cargo check --all-targets`
- `cargo clippy --all-targets -- -D warnings`
- `cargo fmt --check`
- `cargo test --workspace` (with `--profile release-perf` for the bench-binary targets)
- `cargo +nightly miri test` against harness-internal logic

Fix any findings meticulously and optimally, preserving all content, features, and functionality.

Output: `phase14_fresh_eyes_diff.md` with the cumulative diff across all rounds.

---

## When to STOP iterating

Two consecutive rounds where:
- Static gates green
- Each fresh-eyes prompt produces ≤3 lines of material change (typos / formatting / comment fixes only)

If you can't reach this state after 10 rounds, the iteration coordinator escalates: the remediation plan or the harness has a structural problem that fresh-eyes can't close. Loop back to Phase 12 for a deeper redesign.

## When to ADD a new round (after triangulation)

If `subagents/triangulator.md` (Phase 14 T3+) returns a CRITICAL or full-agreement HIGH finding, that's a Phase-14 reopen — the static gates passing don't override a multi-model agreement that something is wrong. Add a 4th round (or 5th, etc.) until triangulation comes up clean.

## Why these EXACT words

The phrasing has been validated across hundreds of FrankenSQLite review cycles. Slight rewrites lose specific catches:

- "super carefully" — without "super", agents skim.
- "obvious bugs, errors, problems, issues, confusion" — the 5-noun enumeration matches all 5 classes; reducing to "bugs and issues" misses confusion / silly mistakes.
- "sort of randomly" — without it, agents follow the import graph too systematically and miss the wide net.
- "comply with ALL rules in AGENTS.md" — without ALL, agents follow only the ones they remember.
- "cast a wider net and go super deep" — both halves; either alone loses signal.

If you find a class of bug these prompts miss, propose a new prompt rather than tightening an existing one. The pattern is "more lenses, each calibrated", not "more constraints in one lens".

## Cross-references

- [`subagents/fresh-eyes-reviewer-a.md`](../../subagents/fresh-eyes-reviewer-a.md)
- [`subagents/fresh-eyes-reviewer-b.md`](../../subagents/fresh-eyes-reviewer-b.md)
- [`subagents/fresh-eyes-reviewer-c.md`](../../subagents/fresh-eyes-reviewer-c.md)
- [`subagents/triangulator.md`](../../subagents/triangulator.md) (multi-model T3+ supplement)
- [`subagents/red-team-attacker.md`](../../subagents/red-team-attacker.md) (adversarial T3+ supplement)
- [`pattern:85-ADVERSARIAL-SEARCH`](../patterns/85-ADVERSARIAL-SEARCH.md)
