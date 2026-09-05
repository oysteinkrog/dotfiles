# The Doctor Kernel — Universal Axioms

> Per `/operationalizing-expertise`: a skill's *kernel* is the small set of universal truths every artifact in the domain must respect. The kernel is the lens through which every later decision is made. If a proposed change conflicts with an axiom, it's the change that's wrong — not the axiom.

These axioms apply to every doctor on every CLI in every language. They're stress-tested against the canonical exemplars (`xf doctor`, `br doctor`, `caam doctor`, `caam robot`, `cm doctor`, `cass health`, `dcg explain`, `mcp_agent_mail`) and against the AGENTS.md compliance surface. If an axiom appears to break in an edge case, **explain why before treating it as an exception**, and consider whether the axiom needs sharpening or whether the edge case is actually a Polish Bar violation in disguise.

<!-- DOCTOR_KERNEL_START v1.0 -->

## Axiom 0 — A doctor is a contract with a future agent who has no context

The agent invoking `<tool> doctor` is not the engineer who wrote the tool. It's a fresh subagent (Claude / Codex / Gemini / Cursor / a human under stress at 3am) with one shot to make the tool work again. Every output, every error, every flag, every JSON field exists to serve that agent's two questions:

1. **What's wrong?** — answered by `diagnose --json`'s findings, each with `file:line` evidence and a pasteable remediation command.
2. **What's the next move?** — answered by `next_steps[]`, `--robot-triage::recommended_command`, `<tool> doctor explain <id>`, and the negative-space spec in `robot-docs`.

If the doctor's output forces the agent to *guess* about either question, the doctor has failed.

## Axiom 1 — Detect-then-fix; mutations flow through one chokepoint

The detector reads, the fixer mutates, and `mutate(path, op)` is the **only** function in the entire doctor module that touches disk under `--fix`. The chokepoint is the load-bearing invariant: get this right and reversibility, idempotence, observability, crash-recovery, and concurrency-safety come almost for free. Get it wrong — even once, even "just to flush a small status file" — and you cannot prove anything about the doctor's behavior.

The validator (`scripts/validate-doctor.sh`) enforces this invariant in CI. Refusing-to-merge a violation is preferable to "fixing" it later.

## Axiom 2 — Backup is verbatim, immediate, and witnessed before the mutation begins

Every `mutate(path, op)` call starts by:
1. Acquiring a per-path advisory lock.
2. Computing `before_hash = sha256(read_or_empty(path))`.
3. Validating preconditions (`path ∈ write_scopes`, `op ∈ allowed_ops`).
4. **Writing a verbatim backup** to `.doctor/runs/<run-id>/backups/<rel-path>` and asserting `cmp -s live_file backup` succeeds at the moment of backup.
5. *Only then* planning and executing the mutation.

If steps 1–4 fail, no mutation has occurred and no `actions.jsonl` line is written; the system is unchanged. The hash + verbatim backup combo means the inverse pair (`<tool> doctor undo <run-id>`) can prove byte-for-byte restoration.

## Axiom 3 — Every fix has a recorded inverse; gc is the only deletion surface

Per AGENTS.md RULE 1, `doctor --fix` never deletes files. The `Op` enum has no `DeletePath` variant under `--fix`. Quarantine is implemented as `Op::Rename` to `<run-dir>/quarantine/`. The user can later inspect and delete; the fixer never makes that call.

The one deletion-capable surface is retention cleanup: `<tool> doctor gc --before <date> --yes`. It is not a fixer, never runs implicitly, and exists only to prune old `.doctor/runs/` directories after the user explicitly names the cutoff and accepts losing undo capability for those runs.

`<tool> doctor undo <run-id>` reads `actions.jsonl` in reverse, restores from `backups/`, and verifies post-restore hash matches `before_hash`. **Strict mode (default) refuses if any backup is missing or hash-mismatched.** Loose mode (`--no-strict`) is opt-in and discouraged.

If a fixer creates a file that didn't exist before, undo restores the pre-existence state by `Op::Rename`-ing the created file to quarantine — never by `unlink`.

## Axiom 4 — Run twice = run once

A successful `<tool> doctor --fix` followed immediately by another `<tool> doctor --fix` reports `actions_taken: 0` and exits 0. Idempotence is non-negotiable because:
- A wedged agent retrying after a transient failure must not compound damage.
- A pre-commit hook running on every commit must not write each time.
- A fresh-eyes review running detectors twice must produce the same answer.

The detector is *pure*: same disk state in → same finding out. The fixer short-circuits when the detector returns `None`. If the second run reports any non-zero `actions_taken`, the detector is mutating a side channel — fix that.

## Axiom 5 — Crash mid-fix never produces torn writes

Every disk write inside `mutate()` uses temp-file + atomic rename (or DB transaction). The temp file lives in the same directory as the target so `rename(2)` is just a directory entry swap. If the process is `SIGKILL`ed at any point, the worst case visible to the next reader is:
- An orphan `.doctor.tmp.<pid>` file in the parent directory (the next run's recovery detector quarantines).
- An incomplete `actions.jsonl` line at the end of the file (the next run's reader truncates at the last newline).

No half-written target file. No torn JSON. No corrupt DB family.

## Axiom 6 — Concurrent doctors serialize via the project's lock primitive

Two `<tool> doctor --fix` invocations on the same workspace must serialize: one wins, the other refuses with exit 5 (`concurrency_lost`) and a finding identifying the holder when discoverable. The lock is acquired at `mutate()` entry, released on function exit (even on panic). If the project already has a primary lock (e.g., `.beads/.git-like-lock`), the doctor uses it; otherwise the doctor introduces `.<tool>/.doctor.lock`.

## Axiom 7 — Read-only by default

`<tool> doctor` (no flags) **never** mutates the project. The only writes a detect-mode run produces are:
- `.doctor/runs/<run-id>/{report.json, report.md, scorecard.json, stderr.log, stdout.json}` — all newly-created files inside the per-run artifact directory.
- The atomic update of the `.doctor/latest` symlink.

These are *adjacent* to the project, not modifications of project state. `--fix` is opt-in. `--dry-run --fix` prints the plan without executing.

## Axiom 8 — Stdout is data, stderr is progress

`<tool> doctor --json | jq` works without grep-filtering log lines. ANSI escapes, spinners, and progress bars belong on stderr. They auto-disable when stdout is non-TTY, when `NO_COLOR=1` is set, or when `--robot` / `--json` is passed. **The agent's job is to parse stdout; making it grep is a Polish Bar violation.**

## Axiom 9 — Exit codes are a documented dictionary, not ad-hoc

The exit code dictionary is in `<tool> doctor capabilities --json::exit_codes` and is stable across releases (additive changes only; never repurpose a code). Common codes:

| Code | Meaning |
|------|---------|
| 0 | success / healthy / fix complete / undo complete |
| 1 | findings present (no `--fix`) |
| 2 | fix partial |
| 3 | fix failed and rolled back |
| 4 | refused: unsafe state |
| 5 | concurrency: another doctor holds the lock |
| 6 | online required |
| 64 | usage error |

Non-zero exits are first-class signals: an agent can pattern-match on them without parsing JSON.

## Axiom 10 — Errors teach

Every error message names:
- WHAT failed (specific predicate, not generic prose)
- WHERE (file:line / row+table / json-pointer / hash)
- WHICH FLAG fixes it (paste-ready remediation command)
- WHEN to use the safe alternative (named explicitly, e.g., "use `--dry-run --fix` first")

`See --help` is **not** an acceptable answer. The remediation field in JSON findings is the structured equivalent of these four answers; `<tool> doctor explain <finding-id>` expands to the full evidence basis.

## Axiom 11 — The doctor describes itself reflectively

`<tool> doctor capabilities --json` declares: `schema_version`, `tool_version`, `doctor_contract_version`, subsystems, detectors, fixers, exit codes, env vars, write scopes, run-artifact schema URL. The capabilities document is *generated from the live registry of detectors and fixers* — never hand-maintained — so it cannot drift from reality. `scripts/verify-capabilities.sh` round-trips: every declared item is invocable.

`<tool> doctor robot-docs` prints a paste-ready agent handbook that includes capabilities + the negative-space spec ("things this doctor will NEVER do"). This is what makes an agent willing to run the doctor unsupervised in a sandbox.

## Axiom 12 — Offline by default; online is opt-in and gated

The doctor must run in a sandbox with no network. Detectors that require network calls are marked `online_required: true` in capabilities and are skipped unless `--online` is set. When skipped, they emit a `findings_only_offline` finding describing what they would have checked.

This axiom protects against the most common doctor failure mode — the doctor wedges in CI, in a Docker build, or in an air-gapped environment because someone added a "license check" detector that calls home.

## Axiom 13 — Run artifacts are append-only and content-addressable

`.doctor/runs/<ISO8601>__<run-id>/` is created fresh on every invocation and never edited afterward. `actions.jsonl` is append-only with `fsync` after each line. The `latest` symlink updates atomically (symlink-to-temp + rename). Run-id is `sha256(target_sha + iso8601_utc_seconds)[..6]` — deterministic up to the second so concurrent runs naturally collide and the second waits.

The append-only invariant means an agent can read a run artifact at any time without locking and trust what it sees.

## Axiom 14 — Bounded blast radius, disclosed in dry-run

`capabilities::write_scopes` lists every path the doctor may write to. The union of `fixers[*].writes_to` is a strict subset. `--dry-run --fix` prints every path that would be touched, in advance, with the estimated bytes affected. Out-of-scope writes are physically impossible — `mutate()` refuses with exit 4.

The agent can disk-budget, the user can review, and a Phase 7 fresh-eyes can confirm the doctor doesn't reach beyond its declared scope.

## Axiom 15 — Every fixer has a fixture; every fixture round-trips

`tests/doctor_fixtures/<fm-id>/{corrupt.sh, assert.sh, README.md}` per failure mode. `corrupt.sh` reproduces the broken state deterministically. `assert.sh` asserts post-fix health. The CI gate runs the round-trip: corrupt → fix → assert → undo → cmp-strict against the corrupted snapshot. **Pass-N+1 cannot tell "fixed" from "regressed-back" without the fixture.** No fixture = no fixer.

## Axiom 16 — Plans atrophy on contact with reality; pass after pass

A doctor is never finished. The fixture suite catches yesterday's bugs, but new ones arrive: the project adds a subsystem, a vendor changes an API, a library bumps a major version. The skill's pass-N → pass-N+1 cycle (re-mine cass, re-inventory FMs, re-score) is how the doctor stays useful. Aggregate-score regressions > 50 pts are hard-stops requiring explicit ACK; trends are tracked in `.doctor/scorecard_history.jsonl`.

A scorecard from 18 months ago is a snapshot, not a verdict. The methodology IS the persistence.

<!-- DOCTOR_KERNEL_CORE_END v1.0 -->

---

## Stretch axioms (load-bearing for mature doctors)

The 17 axioms above are universal — every doctor must respect them. The seven below are "stretch axioms": they catch a long tail of subtler issues that show up at Stage 6+ ([GROWTH-LADDER.md](GROWTH-LADDER.md)). They're stretch in the sense that a Stage 1-3 doctor doesn't strictly need them, but a Stage 7+ doctor cannot reach world-class without them.

## Axiom 17 — Provenance: every cached value carries `live | fallback | unavailable`

Per Q-007 (`bv` two-phase analysis pattern), any cached or derived value the doctor returns to the agent carries a provenance marker:

- `live` — computed this run from current state.
- `fallback` — computed last run; this run couldn't (timeout / online failure / out of budget).
- `unavailable` — could not compute and refuses to render a stale value as if it were current.

A reader that sees `provenance: "fallback"` knows the value may be stale and can choose to wait for a re-run or accept the staleness. A reader that sees `provenance: "unavailable"` MUST NOT treat the field as if it had a value.

This is what `bv` does for its async metrics; the doctor adopts the pattern for any field whose computation has cost (online detectors, expensive scans, memo-reads).

## Axiom 18 — Bidirectional coverage: every detector has a fixture and every fixture has a detector

A detector without a fixture is theoretical. A fixture without a detector is dead code. The bidirectional invariant: `set(detectors) ≡ set(fixtures)` (modulo manual_remediations, which are detector-only by design).

`scripts/verify-coverage.sh` (proposed; future enhancement) walks both sides and fails CI if either is incomplete.

## Axiom 19 — Cardinality: a fixer mutates ≤ K paths per invocation, where K is bounded and disclosed

Default K=10 paths per fixer per invocation. A fixer that wants to mutate more must set `cardinality: "high"` in its capabilities entry. Agents reading capabilities can plan accordingly; large mutations are surfaced in `--dry-run` early.

Bounded cardinality protects against the "the doctor went berserk and rewrote 200 files" failure mode. If the fixer's logic genuinely needs unbounded scope, it's probably the wrong abstraction — split into a chain of bounded fixers.

## Axiom 20 — The doctor is a closed system under its own contract

Every JSON shape the doctor emits is in `capabilities --json`'s schema URLs. Every error code is in the exit-code dictionary. Every flag is in `--help`. There are NO undocumented surfaces — the agent's mental model can be complete from `capabilities --json` + `robot-docs` alone.

If a code path emits something the agent can't predict from the contract, that's a contract violation; bump `doctor_contract_version`.

## Axiom 21 — Failure modes have priorities; priorities have decay

A FM's priority decays as evidence accumulates that the project's mitigation worked. After 90 days of zero invocations of a fixer, the FM's `frequency` weight halves; after 365 days, the fixer is a candidate for retirement (per [OPS-RUNBOOK.md § "When to retire a fixer"](OPS-RUNBOOK.md)).

This prevents the doctor from accumulating dead detectors over years. Retirement preserves history (per AGENTS.md no-delete) but removes the runtime cost.

## Axiom 22 — Refusal IS the doctor's most useful behavior in unsafe states

When the project's state is genuinely unsafe, the doctor REFUSES with a precise exit code that distinguishes the kind of obstacle:
- **exit 4** (`refused_unsafe`) — schema in an unknown version, out-of-scope path detected, missing precondition (other than lock).
- **exit 5** (`concurrency_lost`) — lock held by another process. Distinct from 4 so an agent knows to retry-after-wait.
- **exit 6** (`online_required`) — a network probe is required but `--online` was not passed.

This is not a failure of the doctor — it's the doctor working correctly.

A doctor that "best-efforts" through an unsafe state is a doctor that occasionally corrupts. A doctor that refuses with a precise reason and a safe alternative is a doctor that earns trust.

The corollary: do not score `automation_degree` based on what the doctor REFUSES. Refusals are first-class manual_remediations; they're a feature, not a gap.

## Axiom 23 — Doctor's own observability matters for trust

Every fixer logs its own decision trail. Every refusal cites the precondition that fired. Every backup records its source mtime + mode + permissions. Every action records before/after hashes. The agent reading the run-artifacts MUST be able to reconstruct what the doctor saw, decided, and did — without consulting the source code.

The artifact trail IS the doctor's argument for trustworthiness. A doctor whose actions can't be traced cannot be trusted enough to run unsupervised.

<!-- DOCTOR_KERNEL_STRETCH_END v1.0 -->

<!-- DOCTOR_KERNEL_END v1.0 -->

---

## How to use the kernel

When evaluating a proposed change to a doctor (a new fixer, a new flag, a change to `mutate()`), check it against each axiom in turn. The first axiom it conflicts with is the change's defect. If you can't find a conflict but you still feel the change is wrong, you're missing an axiom — propose adding it (with reasoning) before merging the change.

When stuck on a hard design choice, the kernel is also a triage tool. Most doctor design dilemmas resolve to "which axiom protects the user better here?" Pick that one; it almost always picks itself.
