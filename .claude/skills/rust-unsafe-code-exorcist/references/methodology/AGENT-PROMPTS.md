# AGENT-PROMPTS.md — Verbatim Subagent Prompts

These are the exact prompts the orchestrator sends to each subagent. They are calibrated. Use verbatim.

Every prompt references the agent's purpose, inputs, outputs, and the operators it must apply. Cross-references to [PHASES.md](PHASES.md) and [OPERATORS.md](OPERATORS.md).

---

## Phase 0 / 0.5

### `cass-miner`

```
You are mining prior agent-session history for unsafe-refactor patterns relevant to the
project at <project-path>. The user has these remote hosts indexed under cass: css, csd,
ts1, ts2 — query all of them in addition to localhost.

Run these query packs against each host (see references/methodology/CASS-MINING.md for
the full pack):

1. "unsafe to safe" --robot --limit 30
2. "Pin::new_unchecked refactor" --robot --limit 20
3. "transmute zerocopy migration" --robot --limit 20
4. "MaybeUninit::assume_init refactor" --robot --limit 20
5. "miri stacked borrows" --robot --limit 20
6. "loom test interleaving" --robot --limit 20
7. "safe-only feature flag" --robot --limit 20
8. "unsafe impl Send Sync removal" --robot --limit 20
9. "FFI shim hardening" --robot --limit 20
10. "cargo expand unsafe macro" --robot --limit 20

For each hit:
- Extract the prompt the user gave AND the action the agent took.
- Tag by unsafe-class (FFI, SIMD, Pin, transmute, MaybeUninit, Send/Sync, allocator).
- Save to <audit-dir>/phase0_cass_findings.md.

Then write <audit-dir>/phase0_cass_findings_summary.md with: top 5 patterns we should
look for in this project's audit, based on what worked in past sessions.

Do NOT modify the project repo. Do NOT modify anything outside the audit dir.
```

### `exemplar-miner`

```
You are mining the exemplar Rust repos for canonical safe-by-default patterns:

  /dp/asupersync
  /dp/beads_rust
  /dp/mcp_agent_mail_rust
  /dp/pi_agent_rust
  /dp/rich_rust
  /dp/frankensqlite
  /dp/frankentui
  /dp/franken_engine
  /dp/frankenlibc
  /dp/frankenfs

For EACH repo:
1. Read README.md and any AGENTS.md.
2. Run `git log --all --grep='unsafe\|miri\|loom\|UB\|soundness' --oneline` and follow
   the top 20 commits. Capture: what was removed, what was added, what the SAFETY
   comment now says.
3. Run `br list --status closed --json | jq '.[] | select(.title | test("unsafe|safety|miri|loom"; "i"))'`
   to find beads about unsafe work. Read their resolution notes via `br show <id>`.
4. Run `ast-grep run -l Rust -p 'unsafe { $$$ }' --json` to find present-day unsafe
   sites and read the SAFETY comments.

Distill into <audit-dir>/phase0_exemplar_patterns.md with one section per repo, listing:
- Canonical unavoidable patterns (the (A) bucket they ship today)
- Canonical perf-only sites (the (B) bucket — note which have a `safe-only` feature)
- Canonical refactor moves that worked (raw ptr → NonNull → Pin → owned; transmute →
  zerocopy; manual Send → newtype with audited Send; etc.)
- Patterns we explicitly REJECTED (with the bead ID / commit hash that explains why)

Target length: 1000–2500 words per repo. This file is the canonical reference for
the rest of the audit. Save fully.
```

---

## Phase 1

### `enumerator` (one per crate)

```
You are the enumerator for crate <crate-name> at <crate-path> as part of the
rust-unsafe-code-exorcist audit at <audit-dir>.

Run these tools and merge their output into the inventory:

1. ast-grep — enumerate every unsafe-shape:
   ast-grep run -l Rust -p 'unsafe { $$$ }' --json
   ast-grep run -l Rust -p 'unsafe fn $NAME($$$ARGS) $$$BODY' --json
   ast-grep run -l Rust -p 'unsafe impl $$$ for $$$ { $$$ }' --json
   ast-grep run -l Rust -p 'unsafe trait $NAME $$$' --json
   ast-grep run -l Rust -p 'extern $$$ { $$$ }' --json
   ast-grep run -l Rust -p 'core::arch::asm!($$$)' --json
   ast-grep run -l Rust -p 'std::arch::asm!($$$)' --json

2. cargo-geiger — per-crate unsafe counts:
   cargo +nightly geiger --output-format Json > phase1/<crate>__geiger.json

3. cargo expand — macro-generated unsafe (CRITICAL: this is where hidden unsafe lives):
   cargo expand --crate <crate-name> > phase1/<crate>__expand.rs
   ast-grep run -l Rust -p 'unsafe $$$' phase1/<crate>__expand.rs --json

4. rustdoc JSON — trait/impl topology:
   cargo +nightly rustdoc -- -Z unstable-options --output-format json
   mv target/doc/<crate>.json phase1/<crate>__rustdoc.json

5. ubs — additional pattern checks:
   ubs --only=rust src/ > phase1/<crate>__ubs.txt

Cross-reference rustdoc JSON to determine public-API exposure:
- For each unsafe site, find the enclosing `pub` item (function, type, impl).
- If reachable from any `pub` item via the rustdoc call graph, set `public_api_exposed: true`.

Emit ONE JSONL row per site in <audit-dir>/phase1/<crate>__inventory.jsonl with the
schema in references/methodology/PHASES.md § Phase 1.

DO NOT classify yet. DO NOT propose refactors. Enumeration only.
```

### `enumerator` end-of-phase merge (main agent)

```
Merge every <audit-dir>/phase1/<crate>__inventory.jsonl into a single
<audit-dir>/unsafe-inventory.jsonl sorted by (crate, file, line_start). Assign stable
IDs of the form site-NNNN starting at 0001. Save the ID mapping in
<audit-dir>/phase1/id-mapping.json so subsequent re-runs preserve IDs.

Also produce <audit-dir>/phase1/cargo-tree.txt via `cargo tree --all-features` and
<audit-dir>/phase1/cargo-tree-soundness.md flagging deps with cargo-geiger counts > 0
whose APIs are reachable from this project's pub surface (see
scripts/cargo-tree-soundness.sh).
```

---

## Phase 2

### `site-analyzer` (same agent as enumerator for that partition)

```
You are the per-site analyzer for crate <crate-name>. For every row in
<audit-dir>/phase1/<crate>__inventory.jsonl, produce a write-up at
<audit-dir>/audit/sites/<crate>/<file-slug>__<line_start>.md using the template in
assets/site-writeup-template.md.

For each site, apply the operators in order: ⊙ Invariant-Locator → ⊕ Reachability-From-Safe
→ ⌖ Macro-X-Ray (if macro-origin) → 🔒 Panic-In-Drop-Trace → 🔁 Async-Cancellation-Trace
(if async-reachable) → 🪟 FFI-Boundary-Contract (if FFI) → ⚖ Send-Sync-Audit (if
unsafe impl Send/Sync).

Each write-up must answer:
1. What does this `unsafe` block actually do? (in plain language, 1 paragraph)
2. What invariants does it assume? (in the form "sound IFF [condition]"; cite the
   specific code that establishes [condition])
3. Where does the data come from (caller / kernel / FFI peer)?
4. Who else touches the same memory or atomic?
5. What does the existing SAFETY comment claim? Trace the call graph — is the claim
   still true today? If not, what changed?
6. What breaks under panic-in-Drop? Async cancellation? Unwinding through FFI?

DO NOT classify yet (that's Phase 4). Write-up ONLY.

Constraints:
- Cite specific line numbers for invariant-enforcement code.
- Macro-origin sites must reference phase1/<crate>__expand.rs:<line>, not the macro
  invocation in source.
- Do NOT modify project code. Do NOT modify anything outside <audit-dir>/audit/sites/.

Target: 300–800 words per write-up. Longer for FFI / async / lock-free; shorter for
simple bounds-check-elision sites.
```

---

## Phase 3

### `synthesizer`

```
You are the Phase 3 synthesizer. Read every per-site write-up under
<audit-dir>/audit/sites/. Produce three global-view files:

1. <audit-dir>/audit/synthesis/invariants.md — cluster sites by shared invariant. For
   each cluster: name, member sites, the safe wrapper that could subsume them. Aim for
   clusters that, if a single safe wrapper is built, would let multiple sites share it.

2. <audit-dir>/audit/synthesis/soundness-surface.md — enumerate every pub API path
   that reaches `unsafe`. Per entry:
       PUB API: <fully-qualified path>
       REACHES: <site-NNNN> (kind), <site-NNNN> (kind), ...
       INVARIANTS THE CALLER MUST UPHOLD: <list>
       CURRENTLY ENFORCED BY: <list of in-crate functions / type invariants / docs>
       SOUND? (yes/no/needs-investigation)

3. <audit-dir>/audit/synthesis/refactor-clusters.md — refactor clusters: groups of
   sites that should be addressed together (shared invariant, shared safe wrapper,
   shared API change). Per cluster: name, member sites, proposed safe wrapper, risk,
   API impact.

For unsafe impl Send/Sync specifically, walk EVERY field of the impl-targeted type
and trace whether the field's Send/Sync-ness is provided by auto-derive or by the
manual impl. Document field-level dependencies in invariants.md.

Constraints:
- Do not classify yet.
- Identify gaps (sites whose write-ups are missing details) and list them at the end
  of invariants.md under `## Open questions`.

DO NOT touch the project repo. Write only into <audit-dir>/audit/synthesis/.
```

---

## Phase 4

### `classifier`

```
You are the classifier for pass <N>. Read the per-site write-ups under
<audit-dir>/audit/sites/ AND the synthesis under <audit-dir>/audit/synthesis/.

For EVERY inventory row, decide (A) / (B) / (C) per references/methodology/CLASSIFICATION-RUBRIC.md.

For each site, produce <audit-dir>/audit/classification/site-<id>.md with the
mandatory write-up form for its bucket (rubric § (A) / (B) / (C) sections).

If pass > 1, you MUST NOT read the prior pass's classification before producing your
own. Only after writing your decision can you compare against the prior pass.

Apply the operator sequence from references/methodology/OPERATORS.md § Composition
cheat-sheet for the site's shape.

Special cases:
- If the operator sequence cannot complete (e.g., (B) without `cargo bench` numbers
  to cite), mark the site as `bucket: NEEDS_PHASE_5_ARTIFACT` and continue. Phase 5
  will produce the missing artifact, then Phase 4 will re-run.
- If a site appears reachable from `pub` but Phase 3's soundness-surface.md doesn't
  list it, mark it as `bucket: NEEDS_PHASE_3_REVISIT` and continue.

Emit <audit-dir>/audit/classification/pass<N>_summary.jsonl with `{id, bucket,
confidence, reasoning_excerpt}` per site.

DO NOT modify the project repo.
```

### `classifier` convergence check (main agent)

```
After pass <N> completes, run:

  diff <audit-dir>/audit/classification/pass<N-1>_summary.jsonl \
       <audit-dir>/audit/classification/pass<N>_summary.jsonl \
       > <audit-dir>/audit/classification/pass<N>_diff.txt

Compute the flip ratio (sites that changed bucket / total sites). If < 5% AND zero
(A)→(C) flips for TWO CONSECUTIVE passes, declare convergence. Otherwise, spawn pass
<N+1>.

Also: list every site marked NEEDS_PHASE_5_ARTIFACT or NEEDS_PHASE_3_REVISIT. Resolve
each before re-classifying (run Phase 5 partial, or Phase 3 revisit, then re-classify).
```

---

## Phase 5

### `refactor-planner` (parallel per cluster)

```
You are the refactor planner for cluster <cluster-name> from
<audit-dir>/audit/synthesis/refactor-clusters.md. Produce a plan per member site at
<audit-dir>/audit/plans/site-<id>.md using assets/refactor-plan-template.md.

For (C) sites:
- Write the FULL safe replacement code (not pseudocode). Paste it into the plan.
- Identify the property-based / metamorphic test that will prove equivalence (path,
  test name, what inputs it exercises).
- Identify the loom model test (if concurrency-touching) — path, what threads /
  interleavings it models.
- Identify the miri command — exact invocation.
- Estimate risk (Low / Medium / High) and any public-API change with migration path.

For (B) sites:
- Write the `safe-only` feature implementation. Show the `#[cfg(feature = "safe-only")]`
  block AND the perf-path `#[cfg(not(feature = "safe-only"))]` block.
- Write the CI matrix entry for .github/workflows/.
- Specify the bench harness that will measure the perf delta (criterion + hyperfine
  + flamegraph).

For (A) sites:
- Write the hardened SAFETY comment naming the proof obligation the caller MUST
  uphold.
- Write a clippy lint rule (if expressible via clippy.toml or clippy::restriction)
  that catches caller-side violations.

DO NOT modify the project repo. Do NOT introduce a new branch. Write only into
<audit-dir>/audit/plans/.

Constraints:
- The rewrite code MUST preserve allocator identity (see operator 📐 Allocator-Identity).
- The rewrite code MUST handle every panic / error path the original handled.
- No `unwrap()` / `expect()` in rewrites unless documented in a SAFETY-style comment
  (yes, even on safe code — the audit's standard is higher than the project's).
```

### `equivalence-prover`

```
You are the equivalence prover. For every (C) site in
<audit-dir>/audit/classification/, author a proptest in <audit-dir>/audit/tests/
equivalence_<site_id>.rs.

The test must:
1. Use `proptest` or `quickcheck` with at least 10,000 cases for primitive inputs,
   1,000 for structural inputs.
2. Cover the failure modes the original `unsafe` handled (panics, errors, edge
   cases). For each, assert `panic_of_unsafe == panic_of_safe` and `error_of_unsafe
   == error_of_safe`.
3. Be runnable under `cargo test --release` AND `cargo +nightly miri test`.
4. Include a metamorphic invariant where applicable (form: `f(transform(x)) ==
   transform(f(x))` for some non-trivial `transform`).

Save the test file. Add a "Property Test" section to the corresponding
<audit-dir>/audit/plans/site-<id>.md with the test path and the strategy used.

DO NOT modify the project repo. The tests live in the audit dir until Phase 8.5.
```

---

## Phase 6

### `adversarial-reclassifier`

```
You are the adversarial reclassifier for pass <M>. You have NOT seen the prior
classification — read it ONLY after you've produced your own.

For EVERY site:
- If currently classified (A): construct a steel-man for a safe alternative. Try
  three different angles. If any survives the falsification block in the original
  (A) write-up, reclassify to (B) or (C). Document your attack in the site's
  classification file under `## Phase 6 adversarial attack`.
- If currently classified (B): hunt for a missed perf-equivalent safe pattern.
  Look in arc-swap, crossbeam, indexmap, dashmap, wide, std::simd (with explicit
  target_feature), portable_simd. If found, document the alternative; trigger a
  perf-bench rerun via scripts/bench-before-after.sh. If within budget, graduate
  to (C).
- If currently classified (C): construct an input the proposed safe rewrite would
  handle DIFFERENTLY from the original unsafe. Try edge cases: empty input, max-size
  input, panic-injecting iterator, double-aliased slice, zero-sized type. If you
  find one, document it; the rewrite must be refined OR the site reclassified.

Emit <audit-dir>/audit/classification/pass<M>_summary.jsonl per the classifier
contract. Convergence rule is identical.

Use multi-model triangulation if available (Codex / Gemini / Grok via
/multi-model-triangulation) for the highest-risk (C) sites and the largest (A)
sites — independent reads catch what a single model misses.
```

---

## Phase 7

### `fresh-eyes-reviewer`

```
You are the fresh-eyes reviewer for round <R>. You are reading the proposed safe
rewrites in <audit-dir>/audit/plans/ AND the test code in <audit-dir>/audit/tests/.

Use these prompts verbatim, in order. Each one is a separate review pass:

Prompt 1: "Carefully read over all of the new code you just wrote and other existing
code you just modified with 'fresh eyes' looking super carefully for any obvious
bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover."

Prompt 2: "I want you to sort of randomly explore the proposed-rewrite files in this
audit, choosing some to deeply investigate and trace their interaction with the
surrounding crate, then do a super careful, methodical, and critical check with
'fresh eyes' to find any obvious bugs, dropped error paths, lifetime sloppiness,
panics-in-Drop, accidental allocator changes, async cancellation leaks, missing
Drop-glue, or silent O() regressions, then systematically and intelligently correct
them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you
write or revise conforms to the best practice guides referenced in the AGENTS.md
file."

Prompt 3: "Ok can you now turn your attention to reviewing the rewrites written by
your fellow agents and checking for any issues, bugs, errors, problems,
inefficiencies, security problems, reliability issues, etc. and carefully diagnose
their underlying root causes using first-principle analysis and then fix or revise
them if necessary? Don't restrict yourself to the latest commits, cast a wider net
and go super deep!"

Emit <audit-dir>/audit/phase7/review-pass-<R>.md per prompt with findings + the fixes
applied to the plan files.

Repeat passes until two consecutive rounds produce only trivial changes (typo,
comment polish).

DO NOT modify the project repo. All fixes are to <audit-dir>/audit/plans/ and
<audit-dir>/audit/tests/.
```

### Toolchain harness (main agent, sequenced)

```
Run scripts/run-miri.sh, then run-careful.sh, then run-loom.sh, then run-fuzz.sh,
then run-mutants.sh, then run-geiger.sh — in that exact order. Each script tees its
output to <audit-dir>/audit/phase7/verification-log.md.

After each tool, classify findings via operator ⚑ Pre-Existing-UB-Isolator:
- IN-SCOPE findings: open the relevant plan file, refine the rewrite, re-test.
- OUT-OF-SCOPE findings: file a pre-existing-ub-N bead with reproduction; do NOT
  modify code as part of this refactor pass.

The harness exits clean when every tool is green OR every finding is documented and
either resolved (in-scope) or filed separately (out-of-scope).
```

---

## Phase 8

### `bead-converter`

```
You are the bead converter. Read <audit-dir>/audit/plans/INDEX.md and the per-cluster
plans. Emit <audit-dir>/phase8_bead_commands.sh — a bash script that creates the bead
graph via `br create` + `br dep add`.

Bead shape:
- One parent epic per cluster from synthesis/refactor-clusters.md. Type `epic`.
- One implementation bead per (C) site. Type `task`. The parent epic depends on
  this bead; the site bead only depends on real technical prerequisites named in the plan.
- One feature-flag-+-CI-matrix bead per (B). Type `feature`. The parent epic
  depends on this bead. The bead may depend on a global `b-safe-only-ci-matrix`
  bead if shared infrastructure must land first.
- One "harden SAFETY comment + proof-obligation lint" bead per (A). Type `task`.
  The parent epic depends on this bead.
- One `pre-existing-ub-N` bead per OUT-OF-SCOPE finding from Phase 7/9. Type `bug`.
  Priority 1. Marked `[NOT IN REFACTOR SCOPE]` in the title.

Per bead:
- Title: `[<cluster>] <one-line action>`
- Description: link to <audit-dir>/audit/plans/site-<id>.md AND the exact `cargo`
  acceptance criteria.
- Priority: P0 (soundness regression risk in (A)), P1 ((C) on the soundness surface),
  P2 ((C) off the soundness surface), P3 ((B) safe-only feature).
- Expected diff size: small / medium / large (from the plan).

After emitting the script, the main agent runs it inside the audit repo, then `br
sync --flush-only`, then commits .beads/ + audit/ + phase*.

DO NOT push to remote. The user commits to their own remote when they're ready.
```

---

## Phase 9

### `harness-builder`

```
You are the harness builder. Produce two files:

1. <audit-dir>/verify.sh — the composite harness. Template at assets/verify.sh.template.
   It must run, in order:
       cargo +nightly miri test
       cargo +nightly miri run --bin <each binary>      # only if miri can execute
       cargo +nightly careful test
       RUSTFLAGS="--cfg loom" cargo test --features loom_concurrency_tests
       cargo fuzz run <each target> -- -max_total_time=60
       cargo mutants --in-place=false
       cargo +nightly geiger
       cargo test                                       # default features
       cargo test --features safe-only                  # safe-only features
   Each step tee's to verify.log; the script exits 0 only if all steps exit 0.

2. <audit-dir>/ci-matrix.yml — GitHub Actions matrix entry. Template at
   assets/ci-matrix.yml.template. Adds a job per (default, safe-only) × OS-target
   matrix, plus a separate `soundness` job that runs verify.sh on Linux nightly.

Wire any tool prerequisites:
- Add `[dev-dependencies] loom = "0.7"` to Cargo.toml of every crate that has a
  concurrency-touching rewrite (gated under `[target.'cfg(loom)']`).
- Add `[features] safe-only = []` to Cargo.toml of every crate with a (B) site.
- Add `fuzz/` subdirectory per crate with cargo-fuzz targets for every new/widened
  public surface from (C) rewrites.

DO NOT write these into the project repo yet — write them into <audit-dir>. The
user authorizes the actual project-repo wiring in Phase 8.5 (if the run mode is
`audit-and-refactor` or later).
```

---

## Phase 10

### `maintainer-empathy-reviewer`

```
You are a fresh agent reading this audit for the first time. You have NOT seen the
prior phases — read in this order ONLY:

1. <audit-dir>/phase0_scope_decision.md
2. <audit-dir>/unsafe-inventory.jsonl (skim — counts, kinds)
3. <audit-dir>/audit/synthesis/invariants.md
4. <audit-dir>/audit/synthesis/soundness-surface.md
5. <audit-dir>/audit/synthesis/refactor-clusters.md
6. A random sample of 5 audit/plans/site-<id>.md files (cover at least one (A), one (B),
   one (C) on soundness surface, one (C) off surface, one pre-existing-ub bead if any)
7. <audit-dir>/audit/phase7/verification-log.md

Now answer, AS IF YOU WERE THE PROJECT'S MAINTAINER preparing to merge:

1. Would I land these as-is? If yes — what's my confidence level (Low/Medium/High)?
2. Where am I unconvinced? List specific plans by site-id with the precise objection.
3. What evidence am I missing? List the additional tests, benches, or arguments I'd
   want before clicking merge.
4. What's the riskiest plan in the audit, and is the risk worth the gain?
5. What's the cheapest 20% of the work that captures 80% of the soundness improvement?
6. Are there refactor strategies the audit MISSED? Use /idea-wizard's perspective:
   alternative wrappers, safer dep crates, etc.
7. For (A) classifications: am I convinced of the falsification justification, or does
   the steel-man attack feel under-explored?
8. For (B) classifications: are the perf numbers credible? Were they measured on the
   right workload?
9. For (C) classifications: do the property tests cover the failure modes I care about?

Write <audit-dir>/REVIEWER_RESPONSES.md per assets/reviewer-responses-template.md.

DO NOT modify the plans yourself — file each concern so the original planner agent
can revise. After your responses are written, spawn the revision agent for each
revised plan.
```

### `idea-generator`

```
You are running /idea-wizard against this audit. Read the synthesis files and the
classification summary. For each refactor cluster, brainstorm 3 alternative safe
strategies the original audit MIGHT have missed:

- Different crate choice (e.g., bytes vs zerocopy vs bytemuck for repr-cast)
- Different abstraction (e.g., visitor pattern instead of unsafe pointer walk)
- Different ownership model (e.g., Cow<'_, T> instead of borrow-with-lifetime-trickery)
- Different concurrency primitive (e.g., arc-swap instead of RwLock; flume instead of
  std::sync::mpsc)
- Different lifetime strategy (e.g., generic Lifetime parameter with explicit dropck
  marker instead of raw pointer)
- Different perf strategy (e.g., precomputation instead of get_unchecked; SoA instead
  of AoS)

For each idea: write 1-paragraph sketch, name the crates involved, estimate the perf
trade-off, and rate the simplicity vs the original plan.

Save to <audit-dir>/audit/phase10/idea-wizard-output.md. The original planner agent
should compare against the plan and either incorporate or file a counterargument.
```

### `multi-model-triangulator`

```
You are running /multi-model-triangulation on the highest-risk N sites (default N=5,
configurable). Risk-rank by: (a) soundness-surface reachability, (b) classification
confidence < 0.7, (c) diff size in the plan = large.

For each selected site, send the per-site write-up + classification + plan to:
- Codex (GPT-5.5 / latest)
- Gemini Ultra (latest)
- Grok (latest)

Ask each: "Independently — without seeing the other models' answers — read this site
write-up and proposed safe rewrite. Do you agree with the (A) / (B) / (C)
classification? Do you spot any soundness issue in the proposed safe rewrite? Do you
spot any silent allocator change, panic-in-Drop hazard, async cancellation leak, or
behavior-on-failure mismatch?"

Save each model's response. Then synthesize: where do all three agree? Where does one
dissent, and why? Update the per-site plan with the consensus + dissent notes.

Save to <audit-dir>/audit/phase10/triangulation-output.md.
```

---

## Cross-agent conventions

- **Every agent reads SKILL.md + the rubric file relevant to its phase BEFORE acting.**
- **No agent modifies the project repo until the user authorizes Phase 8.5.**
- **No agent deletes files** (per AGENTS.md Rule 1).
- **No destructive rewrites** (per AGENTS.md feedback memory).
- **Banned slop words** in any agent output: load-bearing, the moment, first-class, white-glove, battle-tested, rock-solid, future-proof, industry-leading.
- **Coordination via MCP Agent Mail** with thread id `unsafe-exorcist-<run-id>-<phase>-<partition>`.
- **File reservations** before editing any file under `<audit-dir>/audit/` to prevent two agents from clobbering each other.
