# Contributing

Welcome. This project has been adopted by the gauntlet
(`/running-the-gauntlet-on-your-rust-port`) and ships with a Subject/Oracle/
Comparator harness, a three-pillar evidence bundle, and a negative-ledger
discipline. The rules below are how we keep the gates honest and the
remediation loop converging.

Replace each `<port>` / `<reference>` placeholder with the real project
names when you copy this file into a port's repo root.

---

## Kernel axioms (the 12 K-N rules)

The full kernel lives at `assets/cc-axioms.md` (paste-ready) and at
`references/methodology/KERNEL.md` (annotated with verbatim source quotes).
Paste the paste-ready block into your `AGENTS.md` and the top of every
agent-onboarding doc.

### The recital exercise

Before any maintainer reviews their first remediation PR — and before any
new contributor's third merged PR — they recite the 12 axioms in a draft
PR comment, naming for each one a concrete artifact in **this** port that
the axiom governs. Sample recital:

> K-1 (Subject vs Oracle vs Comparator IS the engine).
> Subject: `crates/<port>/src/lib.rs::Connection`.
> Oracle: `crates/<port>-e2e/src/oracle/<reference>.rs::ReferenceClient`.
> Comparator: `crates/<port>-harness/src/oracle.rs::normalize_value` +
> `oracle_compare`. All three named in one paragraph and grep-able.

The point isn't memorization. It's the test of whether the contributor
can locate every axiom in this port's tree. If they can't, no axiom-touching
PR ships.

---

## Trust tiers

Mined from `subagents/knowledge-transfer.md`. Every
contributor lands in a tier; tier-up requires evidence, not tenure.

| Tier | Privilege | Earned by |
|---|---|---|
| **T0 — Observer** | Reads `<workspace>/`, opens issues, no PR-merge rights | Joining the project |
| **T1 — Patch contributor** | PRs accepted into perf-T3 / surface-T3 lanes only | Pass the recital + one merged conformance PR with a proof-pack |
| **T2 — Lane operator** | PRs in any single lane (cc_1 / cc_2 / cc_3 / cc_4); may close beads in that lane | Three merged PRs across the lane; one negative-ledger entry authored with retry-condition predicate |
| **T3 — Cross-lane** | PRs in any lane; may rewrite a pillar's harness; required reviewer for any pillar-touching PR | Six merged PRs across at least 2 lanes; one polished idea-wizard round produced; one Phase 14 fresh-eyes pass owned |
| **T4 — Maintainer** | All of T3 + CODEOWNERS entry; may sign the strict-conformant-release.v1 certificate | Two T3 contributors vouch; one full gauntlet round shepherded end-to-end |

A tier-up is a PR against this file that names the evidence.

---

## Claiming a bead

We run the swarm through beads. Workflow:

```bash
br ready                                    # find ready-to-work beads in your lane
br update bd-<id> --claim                   # take it; sets assignee + in_progress
# ... do the work in a branch named bd-<id>-<one-line-slug> ...
br close bd-<id> --reason "merged"          # only after the PR merges
```

If a bead lacks a clean acceptance criterion, **do not start work**.
Comment on the bead asking for the criterion; if it's stale, add a
`needs-criterion` label and move on. Beads that close without a proof-pack
get re-opened by the Phase 14 fresh-eyes review.

---

## Writing a proof-pack

Every closed bead in the conformance / perf / surface lanes carries a
proof-pack at `artifacts/{bead_id}/proof_pack/`. Skeleton lives at
`assets/proof-pack-skeleton/`. Required files:

| File | Purpose |
|---|---|
| `README.md` | One paragraph: what changed, what invariant class it touches, why it's safe |
| `baseline_profile.flame.svg` | `cargo flamegraph` snapshot BEFORE the change (perf beads) |
| `baseline_profile.samply.json` | `samply` snapshot BEFORE the change (perf beads) |
| `selections_byte_identical.txt` | Per-scenario selection counters; subject vs oracle (conformance + perf) |
| `concurrent_mode_default_guard.txt` | Or per-class equivalent — feature-default proof |
| `rollback.md` | Exact commands to revert; named negative-ledger entry if revert happens |
| `cv_pct.json` | For perf beads: coefficient of variation per timed measurement; `>5%` blocks keep |

Without the proof-pack the bead does NOT close, even if the code is
merged. The proof-pack IS the gate.

---

## Negative-ledger discipline

Three ledgers, all under `docs/progress/`:

- `perf-negative-results.md`
- `conformance-negative-results.md`
- `surface-deferrals.md`

**Before** starting any perf work, you grep all three for related prior
attempts and inspect the last 60 days of session history via `cass`
(`scripts/mine-ledger.sh` does both in one shot). If a related rejection
exists, you EITHER:

1. Cite it in your bead description and explain what's different about
   this attempt (new evidence, expanded scope, broader workload), OR
2. Add a fresh "do not retry until <retry-condition>" entry yourself
   and step away.

Every closed entry MUST carry a `retry-condition predicate` — a
falsifiable, mechanical predicate that names exactly when the rejection
becomes worth revisiting. Templates: `references/methodology/RETRY-CONDITION-VOCABULARY.md`.

The forbidden retry conditions:

> "later", "if it seems important", "TBD", "when we get around to it",
> "maybe", "possibly", "could revisit"

A ledger entry with one of those is a bug, not an entry. Open a bead to
fix it.

---

## Forbidden phrases in this project

A short, ugly list. We catch these in PR review; CI doesn't (yet).

| Forbidden | Why | Use instead |
|---|---|---|
| "should be faster" | Unfalsifiable | "increases throughput by N% measured by `<bench>` on `<workload>`" |
| "looks correct" | Untested | "passes the per-behavior-class oracle test at `<test path>`" |
| "minor cleanup" | Hides scope | Name each touched file + each touched invariant |
| "trust me" | Anti-K-2 | "harness `<file>` enforces this; see line N" |
| "in my testing" | Cherry-pick risk | "in run `<run_id>`, host `<host>`, git sha `<sha>`" |
| "we'll add tests later" | Anti-K-3 | Open a bead; cite it inline; assign it before merging |
| "TODO(fix this)" | Untracked debt | Open a bead with a retry-condition predicate |

Banned in user-facing copy (skill kernel rule): "load-bearing", "the moment",
"first-class", "white-glove", "battle-tested", "rock-solid", "future-proof",
"industry-leading". These are AI-slop tells; they don't help the reader.

---

## The AGENTS.md mandate paragraph

Every agent-driven session begins by reading `AGENTS.md`. Drop this
paragraph (verbatim) into your `AGENTS.md`:

> Before starting any performance work in this repository, mine the three
> negative-result ledgers at `docs/progress/{perf,conformance,surface}-negative-results.md`
> AND the last 60 days of cass session history for failure terms
> (`rejected, reverted, abandoned, slower, regressed, didn't help, within noise,
> no improvement, failed to improve, rolled back, backed out, not a keep,
> keep gate` + the project-specific terms from `taxonomy/PROJECT-CLASSES.md`).
> `scripts/mine-ledger.sh` + `scripts/mine-cass-cross-machine.sh` do both
> in one shot. If `cass` or any ledger is unavailable, RECORD A BLOCKER
> ENTRY rather than silently skipping. Every proposed perf change names
> an invariant class from `references/remediation/ISOMORPHISM-PROOF-TEMPLATE.md`
> in its 5-line proof; every rejected candidate becomes a negative-ledger
> entry with a `retry-condition predicate` per
> `references/methodology/RETRY-CONDITION-VOCABULARY.md`.

That paragraph is the contractual mouth-of-the-cave. Anything inside the
cave (the rest of `AGENTS.md`, the per-pillar docs, the lane assignments)
assumes it's been read.

---

## Branch + PR conventions

- Branch names: `bd-<id>-<one-line-slug>` (mirrors the bead).
- PR title: `bd-<id>: <one-sentence summary>` (must contain the bead id).
- PR description: link the bead, link the proof-pack directory, recite
  which invariant class the change touches.
- Squash on merge.
- Two-reviewer rule for any pillar-touching PR; one reviewer must be at
  least T3.

---

## Cross-references

- Skill source: `running-the-gauntlet-on-your-rust-port`
  (`/<workspace>/SKILL.md`)
- Pillar decomposition: `references/THREE-PILLARS.md`
- Kernel axioms (paste-ready): `assets/cc-axioms.md`
- Operator library: `references/methodology/OPERATORS.md`
- Retry-condition vocabulary: `references/methodology/RETRY-CONDITION-VOCABULARY.md`
- Polish bar: `SKILL.md § The Polish Bar`
- Anti-patterns: `references/methodology/ANTI-PATTERNS.md`
