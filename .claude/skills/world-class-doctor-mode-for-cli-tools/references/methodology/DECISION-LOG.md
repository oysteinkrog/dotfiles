# Decision Log — Why the Skill Looks the Way It Does

Per `/operationalizing-expertise`, decisions in a methodology should be auditable: a future maintainer must be able to trace any choice to its motivation. This file logs the major design decisions, the alternatives considered, and the reasoning that picked the chosen path.

Reading order: chronological. The earliest decisions are foundational; later ones are refinements.

---

## D-001 — Sibling workspace, not in-tree workspace

**Decided:** the doctor's workspace lives at `<repo>__doctor_workspace/`, sibling to the target.

**Alternatives:**
- (A) In-tree at `<repo>/.doctor_workspace/`.
- (B) In `~/.cache/<tool>-doctor/<repo-hash>/` (XDG cache).

**Why this:** workspace contains baseline snapshots, scorecards, and analysis artifacts that shouldn't pollute the target's git history. Sibling makes the boundary explicit. Per-run artifacts (`.doctor/runs/<id>/`) DO live in-tree because they're per-invocation forensic records the user expects to find.

**Trade-off accepted:** the user has to remember the workspace exists. We mitigate by symlinking from `<repo>/.doctor/workspace -> <sibling>` (proposed; not yet implemented).

**Citation:** original [SKILL.md "Inputs" section](../../SKILL.md).

---

## D-002 — Worktree, not separate clone

**Decided:** code changes during a pass land on a `git worktree` of the target, not a fresh clone.

**Alternatives:**
- (A) `git clone` to `<workspace>/worktree/`.
- (B) Edit in-place on the target.

**Why this:** worktrees share the parent's `.git/`, so all branches and refs are one source-of-truth. Separate clones would diverge; in-place editing would conflict with the user's working state.

**Citation:** [SKILL.md "Operating location"](../../SKILL.md).

---

## D-003 — Per-run artifact directory IS in-tree (`.doctor/runs/`)

**Decided:** every doctor invocation creates `<repo>/.doctor/runs/<run-id>/`, gitignored.

**Alternatives:**
- (A) `~/.cache/<tool>/runs/`.
- (B) `<workspace>/runs/`.

**Why this:** the user runs `<tool> doctor undo latest` from the project root; the artifact must be discoverable from cwd. XDG cache would require the doctor to know the user's identity (it doesn't); sibling workspace would require the user to know the workspace path (most users don't).

**Trade-off accepted:** projects must add `.doctor/` to `.gitignore`. The doctor adds it on first run via `mutate()`.

---

## D-004 — `mutate(path, op)`, not `mutate(operation)` or `mutate(diff)`

**Decided:** the chokepoint signature is `mutate(ctx, path, op)` where `path` is the target and `op` describes the operation.

**Alternatives:**
- (A) `mutate(diff)` where diff is a structured patch (one mutate call per coherent change).
- (B) `mutate(operation)` where the operation embeds path + op as a compound type.

**Why this:** `path` is universally meaningful; `op` is the action. Per-call cardinality of 1 path-1-op makes the audit log granular. A single fixer doing 5 things issues 5 mutate calls; each gets its own actions.jsonl line.

**Trade-off accepted:** verbosity. Multi-path operations (e.g., a transactional rename of a directory tree) require multiple mutate() calls. We accept this for the granularity benefit.

---

## D-005 — Backup is verbatim, NOT canonicalized

**Decided:** `cp --preserve mode,timestamps` (or equivalent) for backups. NO content normalization.

**Alternatives:**
- (A) Backup canonicalized JSON (sorted keys, normalized whitespace).
- (B) Backup gzipped to save space.

**Why this:** byte-identicality is more strict than logical equivalence. Downstream tools (other agents, checksums, signatures) may key off byte-stability. Compression would invalidate the `cmp -s` invariant.

**Trade-off accepted:** disk usage. Backups can grow large. Mitigation: per-run gc (operator-controlled, never auto).

**Citation:** [Axiom 2 motivation in FIRST-PRINCIPLES.md](FIRST-PRINCIPLES.md).

---

## D-006 — `actions.jsonl`, not `actions.json` (single file)

**Decided:** append-only newline-delimited JSON.

**Alternatives:**
- (A) Single `actions.json` with an array; rewritten on each action.
- (B) Per-action file `actions/<seq>.json`.

**Why this:** append-only is crash-safe (no torn writes when SIGKILLed mid-write). NDJSON is streamable (agents can `tail -f`). Single-file rewriting is fragile; per-action files have inode overhead.

---

## D-007 — Run-id is content-derived, not random

**Decided:** `run_id = sha256(target_sha + iso8601_utc_seconds)[..6]`.

**Alternatives:**
- (A) UUIDv4 random.
- (B) Monotonic counter `runs/0001/`, `runs/0002/`.
- (C) ULID time-sortable random.

**Why this:** content-derived means concurrent runs in the same second naturally collide; the second waits. Monotonic counter requires global state. UUIDv4 is non-deterministic and unfriendly for replay. ULID is closer but still has random bits.

**Trade-off accepted:** 6 hex chars = 24 bits = 16M possible IDs per second. Across an entire fleet of agents, collision probability is non-zero but vanishingly small for our workload (max ~10 doctor invocations per second per project).

**Citation:** [Axiom 13](KERNEL.md).

---

## D-008 — `--json` and `--robot` are aliases (mostly)

**Decided:** `--json` produces stable JSON; `--robot` is `--json` plus a structured envelope (per Q-014 caam pattern).

**Alternatives:**
- (A) Single `--json` flag covers both.
- (B) `--robot` is significantly different (e.g., NDJSON streaming).

**Why this:** `--json` is the user-facing convention; `--robot` adds the `Suggestions[]` and `Timing` fields that agents specifically want. Both produce parseable output.

---

## D-009 — Exit codes 4 (refused) vs. 5 (concurrency_lost)

**Decided:** distinct exit codes for "I refused for safety" vs. "Another doctor was already running".

**Alternatives:**
- (A) Single exit 4 covers both.
- (B) Exit 4 for unsafe; exit 1 for concurrency.

**Why this:** an agent should retry exit 5 (after a wait); should NOT retry exit 4 (the unsafe state needs investigation). Distinct codes mean distinct response strategies.

**Citation:** [CLI-SURFACE.md exit-code dictionary](CLI-SURFACE.md).

---

## D-010 — Refuse-with-redirect, not best-effort

**Decided:** when the doctor can't be 100% sure of the right action, REFUSE with a precise reason and a safe alternative. Don't best-effort.

**Alternatives:**
- (A) Heuristic best-effort with a warning.
- (B) Skip the offending FM silently.

**Why this:** agents trust refusals more than warnings. A refusal forces the user (or agent) to make an explicit decision. A heuristic best-effort that occasionally goes wrong erodes trust permanently.

**Citation:** [Axiom 22 in KERNEL.md](KERNEL.md).

---

## D-011 — `Op::DeletePath` is FORBIDDEN

**Decided:** the Op enum has no `DeletePath` variant. Quarantine via `Op::Rename` to `<run-dir>/quarantine/` is the doctor's "delete" semantics.

**Alternatives:**
- (A) Allow `DeletePath` for files clearly safe to delete (e.g., temp files).
- (B) Allow `DeletePath` only with `--force --yes`.

**Why this:** AGENTS.md RULE 1 is absolute. There are no "clearly safe to delete" cases — even temp files might contain the user's manual debugging state.

**Citation:** [Q-001 (AGENTS.md RULE 1) in QUOTE-BANK.md](QUOTE-BANK.md).

---

## D-012 — Detector tiering (`quick | default | deep | online`)

**Decided:** four tiers; `health` runs only `quick`; `--quick` flag runs only quick; `default` is the bare doctor; `deep` requires explicit `--include-deep`; `online` requires `--online`.

**Alternatives:**
- (A) Two tiers: fast / slow.
- (B) No tiers; user controls via `--only`.

**Why this:** four tiers map cleanly to four canonical use cases (oncall liveness, pre-commit, manual interactive, deep audit). Two tiers would conflate; `--only`-based control puts cognitive load on the user.

**Citation:** [PERFORMANCE.md detector tiering](PERFORMANCE.md).

---

## D-013 — One scorecard, multiple per-pass historical scorecards

**Decided:** `<workspace>/scorecard.md` is the latest; `scorecard_pass_<N>.md` per pass.

**Alternatives:**
- (A) Single mutable file.
- (B) Per-pass directory `passes/<N>/scorecard.md`.

**Why this:** the latest is the action signal; the historical files are the trend. Per-pass directories add hierarchy noise; flat naming is searchable.

---

## D-014 — Phase 7 fresh-eyes uses VERBATIM prompts

**Decided:** the three Phase 7 prompts are calibrated and used WITHOUT paraphrasing.

**Alternatives:**
- (A) Templated prompts with project-specific substitutions.
- (B) Reviewer-author writes their own prompts each time.

**Why this:** the prompts have been refined over many user sessions; paraphrasing degrades effectiveness. The user's transcript history shows specific wording recurring across projects with high signal.

**Citation:** Q-023, Q-024, Q-025 in QUOTE-BANK.md.

---

## D-015 — 17 + 7 = 24 axioms, not 17

**Decided:** add stretch axioms 17–23 to the kernel.

**Alternatives:**
- (A) Stop at 17 (universal only).
- (B) Add to 30+ (anything anyone might want).

**Why this:** universal axioms apply to ALL doctors; stretch axioms apply at Stage 6+ (mature doctors). The split is real (some axioms genuinely don't apply to a Stage 1 diagnose-only doctor) and the line is at 17 because that's where universality breaks.

**Citation:** Round-3 expansion (this work).

---

## D-016 — Phase 2.5 (spec review) is optional at Solo tier

**Decided:** spec review is mandatory at Pair+, optional at Solo.

**Alternatives:**
- (A) Always mandatory.
- (B) Always optional.

**Why this:** at Solo tier the same agent that wrote the spec also implements; review-by-self adds little. At Pair+ the implementer is different from the author; review catches divergence.

---

## D-017 — Cookbook stops at 15 patterns (for now)

**Decided:** 15 patterns covering the user's common cases.

**Alternatives:**
- (A) Continue to 25-30 patterns.
- (B) Reduce to 5 broad patterns.

**Why this:** 15 covers ~95% of CLI projects encountered; further patterns are diminishing returns. Five would conflate distinct shapes; agents would have to invent the per-shape adjustments themselves.

---

## How to add a decision

When you make a non-trivial design choice during a pass:

1. Allocate the next D-NNN.
2. Write the section here: Decided / Alternatives / Why this / Trade-off accepted / Citation.
3. Cite from any other file that reflects the decision.

Future maintainers will thank you. The decision log is the doctor's institutional memory.

---

## Decisions deliberately NOT made

To avoid analysis paralysis, the skill defers some choices to the project:

- **Specific JSON serializer.** Project's choice (serde / encoding/json / pydantic / zod / Jackson).
- **Specific lockfile primitive.** Project's choice (`fs2`, `flock`, `portalocker`, `proper-lockfile`, `FileChannel.tryLock`).
- **Specific test runner.** Project's existing one.
- **Specific CI provider.** GitHub Actions / GitLab CI / Buildkite / project's choice.
- **Specific telemetry sink.** Datadog / Honeycomb / Prometheus / none.

The skill's contract is medium-agnostic; the implementations are language-and-project-specific.
