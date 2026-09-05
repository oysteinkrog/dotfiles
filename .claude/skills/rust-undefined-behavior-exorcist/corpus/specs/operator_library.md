# Operator Library (Marker-Bounded, Extractable)

This is the canonical, programmatically-extractable form of the operator library. The narrative version lives in [references/OPERATOR-LIBRARY.md](../../references/OPERATOR-LIBRARY.md).

Extract a single operator via:
```bash
awk '/<!-- OPERATOR-START id=SUSPECT/,/<!-- OPERATOR-END id=SUSPECT/' operator_library.md
```

---

<!-- OPERATOR-START id=SUSPECT symbol=★ -->
## ★ SUSPECT — flag a candidate UB site

**Trigger:** SAFETY comment is missing/weak; manual unsafe impl Send/Sync without visible synchronization; FFI call with pointer of unclear provenance; clippy lint matches but the linter alone isn't enough.

**Prompt module:**
```
Read <file:line> and the 20 lines on each side. Is the unsafe operation actually
sound? Specifically:
  (1) What invariant does it depend on?
  (2) Where is that invariant enforced?
  (3) What happens if the invariant breaks?

If you can't answer all three confidently in two sentences each, mark this site
as ★ SUSPECT and add a row to phase2_findings_<bucket>.md.
```

**Exit criterion:** A row exists in `phase2_findings_<bucket>.md` with severity (MUST-BE-UB / LIKELY-UB / SUSPICIOUS / CONTRACTUAL-BUT-DEFENSIBLE).

**Failure modes:**
- Marking everything SUSPICIOUS — destroys the signal-to-noise ratio. Reserve SUSPICIOUS for sites where you have a specific reason but can't yet articulate it.
- Skipping SAFETY comments in the audit — comments are the primary documentation of invariants.

**Composes with:** ✦ ISOLATE (next step when SUSPECT graduates past triage), ⊙ DEBOUNCE-FALSE-POSITIVE (when SUSPECT closes as NO_EVIDENCE).

**Anchors:** Q-002, Q-008.
<!-- OPERATOR-END id=SUSPECT -->

<!-- OPERATOR-START id=ISOLATE symbol=✦ -->
## ✦ ISOLATE — reduce to a minimal reproducer

**Trigger:** A ★ SUSPECT site has graduated past triage; we want to prove the hypothesis.

**Prompt module:**
```
Build the smallest standalone Rust program that exercises only the suspect
operation. Strip every dependency. Strip every unrelated field. Strip every loop.
The reducer is done when removing any further line either breaks the build or
removes the suspect operation. Save it to experiments/<exp-id>/repro.rs.
```

**Exit criterion:** `experiments/<exp-id>/repro.rs` exists and is ≤30 lines.

**Failure modes:**
- "Minimal" reproducers that import the whole crate — defeats minimization.
- Reducers that lose the UB during reduction — a sign the reduction is too aggressive; back off one step.

**Composes with:** ◐ REPRO (wrap as a runnable test), ⌗ DECOMPOSE (split into independent reducers when one isn't enough).

**Anchors:** Q-009.
<!-- OPERATOR-END id=ISOLATE -->

<!-- OPERATOR-START id=REPRO symbol=◐ -->
## ◐ REPRO — wrap as a runnable test

**Trigger:** ✦ ISOLATE produced a reducer; now make it executable under a chosen tool.

**Prompt module:**
```
Wrap the reducer as either:
  (a) a #[test] runnable under cargo +nightly miri test, or
  (b) a #[cfg(loom)] #[test] runnable under loom, or
  (c) a fuzz_target! runnable under cargo fuzz run.

Add the test to a Cargo manifest at experiments/<exp-id>/Cargo.toml if standalone.
```

**Exit criterion:** A single shell command runs the reproducer and produces a verdict.

**Failure modes:**
- Non-deterministic reproducers (system time, RNG without seed) — fix before recording the verdict.

**Composes with:** ⬡ INSTRUMENT (when ◐ REPRO runs clean but the failure is real).

**Anchors:** Q-006.
<!-- OPERATOR-END id=REPRO -->

<!-- OPERATOR-START id=INSTRUMENT symbol=⬡ -->
## ⬡ INSTRUMENT — add flags / tracing to surface the failure

**Trigger:** ◐ REPRO runs clean. The failure is real but hidden.

**Prompt module:**
```
Add MIRIFLAGS / RUSTFLAGS / tracing / eprintln! that maximize visibility into
the suspect operation. Specifically:
  - For aliasing — add -Zmiri-tree-borrows
  - For provenance — add -Zmiri-strict-provenance
  - For alignment — add -Zmiri-symbolic-alignment-check
  - For data races — switch to TSan with --test-threads=1
  - For invalid enum/scalar values — run plain Miri; modern Miri checks
    value validity by default. Do not add -Zmiri-check-number-validity:
    current nightlies reject that obsolete flag.
  - For uninit memory — switch to MSan when plain Miri is not enough
Re-run.
```

**Exit criterion:** The failure manifests with a useful diagnostic, OR the finding is downgraded to NO_EVIDENCE after instrumenting every relevant tool.

**Failure modes:**
- Treating a single tool's clean run as proof. Run the whole MIRIFLAGS matrix before concluding NO_EVIDENCE.

**Composes with:** ⚠ ESCALATE (when INSTRUMENT can't decide).

**Anchors:** Q-003, Q-010, Q-015.
<!-- OPERATOR-END id=INSTRUMENT -->

<!-- OPERATOR-START id=ESCALATE symbol=⚠ -->
## ⚠ ESCALATE — recruit a second opinion

**Trigger:** ⬡ INSTRUMENT can't decide; conflicting signals; or the finding is high-stakes (custom allocator, lock-free DS, public-API unsafe).

**Prompt module:**
```
Invoke /multi-model-triangulation with the finding row, the reproducer, the
instrumented run outputs, and the question:

  "Is this UB? If yes, which Rustonomicon bucket? If no, what additional
   experiment would refute the hypothesis?"

Cross-reference responses; record consensus + dissent in
UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md.
```

**Exit criterion:** Triangulation verdict recorded.

**Failure modes:**
- Treating triangulation as a vote — listen to the dissent.

**Composes with:** ⊢ PROVE (when triangulation suggests formal verification would settle it).

**Anchors:** Q-022.
<!-- OPERATOR-END id=ESCALATE -->

<!-- OPERATOR-START id=REWRITE symbol=⊕ -->
## ⊕ REWRITE — enumerate isomorphic rewrites + pick

**Trigger:** Finding is CONFIRMED_UB. Phase 8.

**Prompt module:**
```
For this CONFIRMED_UB site, enumerate at least two isomorphic rewrites that
eliminate the UB while preserving behavior. Consult references/REMEDIATION-PATTERNS.md.
Score each candidate 0-4 on:
  - correctness margin
  - performance delta
  - diff blast radius
  - reviewability
  - maintainability
Pick the winner. Record runners-up with their tradeoffs.
```

**Exit criterion:** `phase8_remediation_plan.md` entry with chosen rewrite + runners-up + rubric scores + cross-reference to the proving experiment AND the future regression experiment.

**Failure modes:**
- Picking the first rewrite that compiles. The rubric exists to force a tradeoff conversation.
- Strawman runners-up. Real, plausible alternatives only.

**Composes with:** ⌘ REDUCE (when the chosen rewrite passes correctness but loses perf).

**Anchors:** Q-021, Q-201 (frankensqlite mmap-SHM rewrite is the in-corpus exemplar).
<!-- OPERATOR-END id=REWRITE -->

<!-- OPERATOR-START id=DEBOUNCE symbol=⊙ -->
## ⊙ DEBOUNCE-FALSE-POSITIVE — confirm NO_EVIDENCE stays NO_EVIDENCE

**Trigger:** A finding came back NO_EVIDENCE. Verify the negative.

**Prompt module:**
```
Re-run the experiment in a fresh workspace (no cached corpora, no warm fuzz
coverage map). Re-run with the *complete* MIRIFLAGS matrix, not just the one
used in Phase 3. Re-run with an inverted assertion (assert the UB *did* happen —
does it fail clean?) to make sure the test would actually catch the bug.
```

**Exit criterion:** Finding closes as NO_EVIDENCE only after two fresh-eyes runs confirm absence; otherwise upgrade to NEEDS_REFINEMENT.

**Failure modes:**
- Trusting a single Miri-clean run. Miri's coverage isn't exhaustive.

**Composes with:** ⊞ SOAK (when DEBOUNCE on a stochastic tool like fuzz needs more confidence).

**Anchors:** A12 (anti-pattern).
<!-- OPERATOR-END id=DEBOUNCE -->

<!-- OPERATOR-START id=SOAK symbol=⊞ -->
## ⊞ SOAK — long-running campaign

**Trigger:** Phase 11. The remediation candidate or the original UB needs proof at scale.

**Prompt module:**
```
Design a 24-hour fuzz campaign / multi-day Miri run / 10⁴-iteration loom model
for this finding. Specify:
  (a) corpus seed
  (b) wall-time budget
  (c) success criterion (e.g., "zero crashes in 24h")
  (d) checkpoint cadence (where intermediate state lands)
Dispatch via rch exec --.
```

**Exit criterion:** `phase11_soak_designs.md` entry exists; rch job dispatched and tracked.

**Failure modes:**
- Running locally instead of via rch.

**Composes with:** ◇ TRIAGE (if soak surfaces new findings).

**Anchors:** Q-024.
<!-- OPERATOR-END id=SOAK -->

<!-- OPERATOR-START id=REDUCE symbol=⌘ -->
## ⌘ REDUCE — shrink the safe shell when the remediation is too costly

**Trigger:** A ⊕ REWRITE remediation passes correctness but the perf delta is unacceptable.

**Prompt module:**
```
The chosen rewrite is correct but slower. Identify the smallest unsafe core
that captures the perf-critical path, then wrap it in the safest possible API.
The unsafe core must:
  (a) have a 3+ line SAFETY comment naming every invariant
  (b) be unit-tested under the full MIRIFLAGS matrix
  (c) be loom-modeled if concurrent
  (d) be fuzzed if it parses bytes
Document the runtime cost of each safety layer you added vs. removed.
```

**Exit criterion:** Revised `phase8_remediation_plan.md` entry; rubric scores updated.

**Failure modes:**
- Expanding the unsafe shell rather than shrinking it.

**Composes with:** ⊢ PROVE (when the unsafe core is small enough that formal verification becomes feasible).

**Anchors:** Q-201 (frankensqlite mmap-SHM is the in-corpus "smallest unsafe shell" exemplar), /extreme-software-optimization skill.
<!-- OPERATOR-END id=REDUCE -->

<!-- OPERATOR-START id=TRIAGE symbol=◇ -->
## ◇ TRIAGE — assess severity at first contact

**Trigger:** A new finding arrives (Phase 1, Phase 3, Phase 11 soak, incident report). Before fan-out, classify rapidly.

**Prompt module:**
```
For this finding, answer in ≤4 sentences each:
  (1) Which UB-taxonomy bucket(s) does it belong to?
  (2) What's the severity (MUST-BE-UB / LIKELY-UB / SUSPICIOUS / CONTRACTUAL-BUT-DEFENSIBLE)?
  (3) Is this incident-grade (needs immediate Phase-8 design) or audit-grade (queue for normal Phase 5)?
  (4) What's the smallest reproducer you can imagine, in 1-2 lines of pseudocode?

Output: a 4-line block ready to paste into phase4_unified_findings.md.
```

**Exit criterion:** Finding has bucket + severity + audit/incident tag + reproducer sketch.

**Failure modes:**
- Treating every finding as incident-grade — burns out the bandwidth.

**Composes with:** ★ SUSPECT (if triage yields SUSPICIOUS, route to ★ SUSPECT for the slower analysis).

**Anchors:** Q-016.
<!-- OPERATOR-END id=TRIAGE -->

<!-- OPERATOR-START id=STRESS symbol=⊛ -->
## ⊛ STRESS — increase load to surface rare schedules

**Trigger:** A concurrent test passes 1000 times in a row but you suspect a rare race. Or a fuzz target hasn't crashed in 1h but coverage is plateauing.

**Prompt module:**
```
Scale up the test to surface rare schedules:
  - For TSan: bump --test-threads to the machine's core count
  - For loom: increase the model's inner iter count by 10x
  - For shuttle: bump to 10⁵+ random schedules
  - For fuzz: extend the campaign to 24h via rch
  - For Miri: enable -Zmiri-preemption-rate=0 on the suspect test

Don't stress the whole test suite — pick the test most likely to surface the
suspected schedule.
```

**Exit criterion:** Either a new finding surfaces, or two consecutive stressed runs come up clean (then close as NO_EVIDENCE).

**Failure modes:**
- Stressing without targeting — burns compute without yielding signal.

**Composes with:** ⊞ SOAK (when stressing locally isn't enough; offload).

**Anchors:** Q-005.
<!-- OPERATOR-END id=STRESS -->

<!-- OPERATOR-START id=INVALIDATE symbol=✕ -->
## ✕ INVALIDATE — actively try to break the hypothesis

**Trigger:** A finding is CONFIRMED_UB. Before designing the remediation, try harder to refute the diagnosis.

**Prompt module:**
```
Pretend you're a peer reviewer who thinks this finding is wrong. Construct the
strongest argument that:
  (a) the reproducer is non-representative of real callers
  (b) the diagnosis confuses correlation with causation
  (c) the bucket is misidentified
  (d) the UB is conditionally OK in the calling context (rare but real)

Then design one experiment per argument that would prove the reviewer right.
Run the experiments. If any succeed, downgrade the finding's severity.
```

**Exit criterion:** Finding survives the invalidation attempt OR is downgraded with rationale.

**Failure modes:**
- Going through the motions of invalidation without actually trying. The exercise is only useful if the reviewer-persona is genuinely adversarial.

**Composes with:** ⚠ ESCALATE (if ✕ INVALIDATE surfaces a tie, recruit a third party).

**Anchors:** general adversarial-review practice.
<!-- OPERATOR-END id=INVALIDATE -->

<!-- OPERATOR-START id=PROVE symbol=⊢ -->
## ⊢ PROVE — formal verification for highest-stakes findings

**Trigger:** A CONFIRMED_UB site has catastrophic consequences (custom allocator, kernel module FFI, crypto primitive) AND the unsafe core is small enough (<200 LOC).

**Prompt module:**
```
Invoke Kani / Prusti / Creusot directly per the matrix below, or escalate
to /lean-formal-feedback-loop for theorem-prover-grade proofs.

For Kani (bounded model checking):
  - Author a #[kani::proof] fn that asserts the invariants
  - Run cargo kani --harness <proof>
  - If the proof succeeds, attach the cbmc trace to the remediation as evidence

For Lean (theorem proving):
  - Translate the soundness obligation to Lean
  - Prove the theorem; commit the proof alongside the remediation

For Prusti/Creusot:
  - Annotate the function with pre/post conditions and invariants
  - Run the verifier; attach the report
```

**Exit criterion:** A formal proof artifact exists in `experiments/<exp-id>/proof/`.

**Failure modes:**
- Reaching for ⊢ PROVE on every finding — engineering cost is high, payoff diminishes on ordinary code.

**Composes with:** ⌘ REDUCE (the shrinking of the unsafe shell makes formal proof feasible).

**Anchors:** Kani / Prusti / Creusot / Aeneas tooling invoked directly; /lean-formal-feedback-loop skill for theorem-prover proofs.
<!-- OPERATOR-END id=PROVE -->

<!-- OPERATOR-START id=ORTHOGONALIZE symbol=⟂ -->
## ⟂ ORTHOGONALIZE — separate confounding variables

**Trigger:** A finding shows ambiguous signal (e.g., Miri TB flags a violation AND TSan flags a race at the same site — are they the same bug or two?).

**Prompt module:**
```
For each potentially-confounding variable in the finding (aliasing, race,
provenance, alignment, validity), design an experiment that isolates that
variable from the others. Concretely:
  - To isolate aliasing from race: single-threaded reproducer under Miri TB
  - To isolate race from aliasing: multi-threaded reproducer with serialized
    access via mutex (race goes away, aliasing might persist)
  - ... etc.

If isolation succeeds, you have separate findings; if the variables can't be
isolated, the finding is genuinely multi-bucket.
```

**Exit criterion:** Each variable's experiment has run; the finding is either split into N separate findings or confirmed multi-bucket.

**Failure modes:**
- Forcing isolation when the bug is genuinely multi-causal.

**Composes with:** ⌗ DECOMPOSE (when ⟂ ORTHOGONALIZE confirms multi-bucket, decompose into separate remediations).

**Anchors:** advanced debugging practice.
<!-- OPERATOR-END id=ORTHOGONALIZE -->

<!-- OPERATOR-START id=COUNTER symbol=♦ -->
## ♦ COUNTER — local-invariant counter-example

**Trigger:** A function or module has many sites that follow the same pattern; suspicion centers on the *one site that's different*.

**Prompt module:**
```
Read <file>. Identify the invariant that holds at every call site EXCEPT one
or a few. State the invariant explicitly. Then point at the violator(s) and
explain why their divergence is a bug, not an intentional design choice.

Examples of invariants to look for:
  - Every IfNot call uses p3=1 (except UPSERT at L4612 which uses p3=0)
  - Every fcntl call checks ret < 0 (except line K which doesn't)
  - Every Arc::from_raw is paired with into_raw/forget (except site X)
  - Every &str access uses chars().nth() (except site Y using as_bytes()[n])

This is the corpus-mined "local-invariant counter-example" ritual (cass Q-008,
Q-020). It's a faster, more reliable bug-finder than open-ended review.
```

**Exit criterion:** Either the violator is confirmed (file a finding) or the divergence is justified (record rationale).

**Failure modes:**
- Treating the *uniform* sites as authority. The N-1 majority can themselves be the bug; verify the invariant is actually intended before classifying the odd one out as the violator.
- Stopping at the first divergence. There may be multiple violators of the same invariant.

**Composes with:** ★ SUSPECT (when COUNTER identifies the site, SUSPECT classifies severity).

**Anchors:** Q-008, Q-020, Q-023, Q-034.
<!-- OPERATOR-END id=COUNTER -->

<!-- OPERATOR-START id=SAFETY-NOTES-FIRST symbol=☣ -->
## ☣ SAFETY-NOTES-FIRST — write invariants before any code

**Trigger:** A remediation requires `unsafe { ... }` (e.g., FFI surface, mmap pointer, atomic ordering across a non-Rust boundary). Writing the SAFETY contract *before* the implementation is far cheaper than retrofitting it after.

**Prompt module:**
```
Before writing any code, write the SAFETY contract for the unsafe operation:

  ### CRITICAL SAFETY NOTES:
  - <invariant 1: bounds, alignment, validity, lifetimes, etc.>
  - <invariant 2>
  - <invariant 3>
  - <platform-specific notes if applicable>
  - <what must NOT be affected by this change>

Only after the SAFETY notes are written, design the implementation. Every
unsafe block in the implementation cites one or more of the SAFETY notes
above by reference.

This is the corpus-mined ritual (cass Q-004) that produced the frankensqlite
mmap-SHM commit b810842 — the single best UB exemplar in the corpus.
```

**Exit criterion:** SAFETY notes are written *and* every unsafe block in the implementation references them.

**Failure modes:**
- Writing the implementation first and the SAFETY comment as an afterthought.
- SAFETY notes that say "this is safe because X" without explaining what X enforces.

**Composes with:** ⊢ PROVE (for the highest-stakes cases), ⊞ SOAK (to confirm the SAFETY contract holds at scale).

**Anchors:** Q-004.
<!-- OPERATOR-END id=SAFETY-NOTES-FIRST -->

<!-- OPERATOR-START id=READ-ONLY-DELTA symbol=⊳ -->
## ⊳ READ-ONLY-DELTA — frame a change-set before acting

**Trigger:** Any UB-adjacent task that begins with "what changed?". Acts as a scope-fence before any fix pass.

**Prompt module:**
```
This is a READ-ONLY investigation. Do NOT edit any files.

Run:
  1. git -C <repo> diff --stat
  2. git -C <repo> diff (full)
  3. git -C <repo> log --oneline -5

Identify:
  - What functional surface changed (TLS, arena, mmap, fcntl, atomic, ...)
  - Whether the change introduces new unsafe / FFI / SAFETY-contract sites
  - Whether the change touches a previously-audited UB-sensitive surface

If high-UB-risk surface is in the diff, propose follow-up: run cargo +nightly
miri test on the affected modules; loom-model any new concurrency primitive.
```

**Exit criterion:** A summary of the change-set + a recommendation for the next UB action.

**Failure modes:**
- Sliding into edits during the diff read. The "do NOT edit" constraint exists because mixing read with write loses the scope-fence and a follow-up reviewer can't reconstruct what was inferred from the diff vs. invented during the fix.
- Reading only `--stat` and skipping the full hunks. The dangerous changes hide in the bodies, not the file count.

**Anchors:** Q-013, Q-014, Q-024, Q-025.
<!-- OPERATOR-END id=READ-ONLY-DELTA -->

<!-- OPERATOR-START id=DECOMPOSE symbol=⌗ -->
## ⌗ DECOMPOSE — split a finding into independent parts

**Trigger:** A single F-NNN turns out to cover multiple buckets / multiple sites / multiple shapes; remediation would be cleaner per-part.

**Prompt module:**
```
Split F-NNN into F-NNN-a, F-NNN-b, ... where each part is independently
remediable. Record the parent-child relationship in phase4_unified_findings.md.
Each part gets its own EXP-MMM with falsifiable hypothesis.

The parent F-NNN stays in the table as a "consolidated finding" with cross-refs
to the children.
```

**Exit criterion:** N independent findings each with their own experiment.

**Failure modes:**
- Decomposing artificially — a single root cause split into N reports inflates the finding count without adding clarity.

**Composes with:** ⊕ REWRITE (each part gets its own remediation candidates).

**Anchors:** Q-027.
<!-- OPERATOR-END id=DECOMPOSE -->

---

## Operator composition pipelines (the well-trodden sequences)

```
MUST-BE-UB:           ◇ TRIAGE → ★ SUSPECT → ✦ ISOLATE → ◐ REPRO → (CONFIRMED) → ✕ INVALIDATE → ⊕ REWRITE
LIKELY-UB:            ◇ TRIAGE → ★ SUSPECT → ✦ ISOLATE → ◐ REPRO → ⬡ INSTRUMENT → verdict → (if CONFIRMED) ⊕ REWRITE
SUSPICIOUS:           ◇ TRIAGE → ★ SUSPECT → ⬡ INSTRUMENT (lightweight) → either ✦ ISOLATE (graduate) or ⊙ DEBOUNCE (close)
CONTRACTUAL:          ◇ TRIAGE → ★ SUSPECT → contract review → close as NO_EVIDENCE with rationale OR upgrade
Multi-bucket finding: ⟂ ORTHOGONALIZE → ⌗ DECOMPOSE → per-part pipeline
High-stakes:          ⊕ REWRITE → ⚠ ESCALATE → ⊢ PROVE (if applicable) → ⊞ SOAK
Perf regression:      ⊕ REWRITE → ⌘ REDUCE → re-bench → repeat
Stochastic NO_EVIDENCE: ⊙ DEBOUNCE → ⊛ STRESS → ⊞ SOAK → if still NO_EVIDENCE, close
```
