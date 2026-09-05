# Metamorphic Testing — Verifying the Synthesis Without an Oracle

> **The oracle problem in harmonization.** When three variants of `src/util/logger.rs` are synthesized into one, the "correct" synthesis isn't knowable in advance — there's no reference output to compare against. Conventional unit testing fails: you can't write `assert_eq!(synthesis, expected)` because `expected` is exactly what the synthesis is trying to produce.

> **The metamorphic relation move.** Instead of asking "is this output correct?", ask "does this output preserve known relationships under known input transformations?" If `H(A, B)` is the synthesis of variants A and B, certain identities must hold (`H(A, A) = A`; `H(A, B) = H(B, A)` after canonical-form normalization; etc.). These metamorphic relations (MRs) are the oracle-free verification path.

> **Companion skill.** Read [/testing-metamorphic SKILL.md](../../testing-metamorphic/SKILL.md) for the underlying methodology. This file specializes the methodology to the synthesis-correctness problem.

> **Cross-link to confidence.** Per [DECISION-THEORY.md §7](DECISION-THEORY.md#7-metamorphic-relations-as-confidence-boosters), MR-pass results boost the harmonization-planner's confidence on a synthesis row; MR-fail results decisively flag the synthesis as wrong.

---

## 1. Why MR Testing Belongs Here

The skill makes oracle-free decisions in three places:

1. **Triage verdicts** — there's no oracle for "is this branch garbage?" — the rubric in [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md) approximates an oracle via signals + Bayesian posterior (per [DECISION-THEORY.md](DECISION-THEORY.md)). Verifiable post-hoc by user review.

2. **Harmonization synthesis** — there's no oracle for "is this synthesis correct?" The synthesis is the output. We can't verify it against a reference — but we can verify it against MRs that the synthesis must satisfy.

3. **Bundle byte-equality** — IS oracle-grounded (per [BUNDLE-FORMAT-SPEC.md "Verification protocol"](BUNDLE-FORMAT-SPEC.md#verification-protocol)). Conventional verification suffices; MR is overkill.

This file focuses on (2): MRs for synthesis correctness.

---

## 2. The Metamorphic Relations

Seven MRs cover the synthesis-correctness space. Each MR is a property that any *correct* synthesis must satisfy. Failure of any MR is decisive evidence the synthesis is wrong.

### 2.1 MR-1: Identity

> **Relation:** Synthesizing a single variant against canonical produces that variant unchanged (modulo canonical-form normalization).

```
H(canonical, V) = canonical + V
```

**Why this MR:** if the synthesis can't reproduce a single variant when only one variant is contesting, it certainly can't reconcile multiple. This is the simplest sanity check.

**Verification:** for each variant V in the harmonization plan, run the synthesis algorithm with only V and canonical as inputs. The result must be byte-equal (after `cargo fmt` / `prettier` / etc.) to V's content for the contested file.

**Test:**

```bash
./scripts/mr-check.sh --mr=identity \
  --variant feature/redact-secrets \
  --file src/util/logger.rs

# Expected output:
# MR-1 Identity PASS — synthesis(canonical, feature_redact-secrets) byte-equal to feature_redact-secrets after rustfmt
```

### 2.2 MR-2: Commutativity

> **Relation:** Synthesizing A then B (over canonical) produces the same result as synthesizing B then A.

```
H(canonical, A, B) = H(canonical, B, A)   (after canonical-form normalization)
```

**Why this MR:** the synthesis algorithm in [HARMONIZATION-DEEP-DIVE.md](HARMONIZATION-DEEP-DIVE.md) is supposed to be order-independent for compatible variants. If A and B compose, the order of composition shouldn't matter. If it does matter, either (a) the variants don't actually compose (the algorithm should have flagged `divergent-refactor` instead), or (b) the algorithm has an order-dependent bug.

**Verification:** for each pair of variants (A, B) participating in a synthesis, run the algorithm with input order (A, B) and (B, A). Compare results.

**Test:**

```bash
./scripts/mr-check.sh --mr=commutativity \
  --variants agent-cleanup-pass-3,feature/length-cap \
  --file src/util/logger.rs

# Expected output:
# MR-2 Commutativity PASS — order (A,B) and (B,A) produce byte-equal output after rustfmt
```

**When commutativity legitimately fails:** when one variant is a refactor and the other a feature (per [HARMONIZATION-DEEP-DIVE.md §5](HARMONIZATION-DEEP-DIVE.md#5-refactor-vs-feature-distinction)). Refactor must apply first; feature on top. The MR-2 algorithm should detect this and skip MR-2 for refactor-feature pairs (the dependency graph in [HARMONIZATION-DEEP-DIVE.md §1](HARMONIZATION-DEEP-DIVE.md#1-the-hunk-dependency-graph) imposes order; commutativity does not apply).

### 2.3 MR-3: Idempotence

> **Relation:** Re-running the harmonization plan on the synthesized commit produces no new changes.

```
H(H(canonical, V₁, V₂, ..., Vₙ), V₁, V₂, ..., Vₙ) = H(canonical, V₁, V₂, ..., Vₙ)
```

**Why this MR:** if synthesis is correct, applying the same plan to the same starting state should be a no-op the second time. If re-running produces additional changes, the synthesis was incomplete (didn't fully capture the variants' intent the first time).

**Verification:** apply the synthesis. Then re-apply. The second apply must touch zero lines.

**Test:**

```bash
./scripts/mr-check.sh --mr=idempotence \
  --plan harmonization_plan.md \
  --file src/util/logger.rs

# Expected output:
# MR-3 Idempotence PASS — re-applying plan to synthesized state produces 0 line changes
```

### 2.4 MR-4: Intent Preservation

> **Relation:** For each variant's stated intent (per the [HARMONIZATION.md §3](HARMONIZATION.md#3-intent-taxonomy) intent taxonomy), the synthesis preserves it.

```
For each variant V with intent set I_V:
  ∀ intent_check c ∈ I_V :  c(synthesis) = true
```

**Why this MR:** the whole point of harmonization is to preserve intents. If a synthesis drops an intent (a defensive check, a test, a fixture), it's a regression vs. the variant.

**Verification:** for each variant V, identify V's intent-test (e.g., the test V added that exercises the intent). Run that test against the synthesis. It must pass.

For variants without an intent-test (rare — most defensive intents have tests; see [HARMONIZATION.md §4.1 "Tested"](HARMONIZATION.md#41-preserve-the-strongest-example-of-each-intent)), construct a minimal test from the intent description.

**Test:**

```bash
./scripts/mr-check.sh --mr=intent-preservation \
  --variant agent-cleanup-pass-3 \
  --intent-test tests/log_null.rs::test_log_rejects_empty \
  --synthesis-sha d4e5f678

# Expected output:
# MR-4 Intent Preservation PASS — test_log_rejects_empty (from agent-cleanup-pass-3) passes on synthesis d4e5f678
```

### 2.5 MR-5: No Regression

> **Relation:** Every test that passed on canonical's HEAD also passes on the synthesis.

```
For each test t in canonical's test suite where t passes on canonical's HEAD:
  t passes on the synthesis
```

**Why this MR:** the synthesis should be strictly additive — adding intents, not removing them. A test that passed before should pass after. If a canonical test breaks, the synthesis introduced a regression.

**Verification:** run canonical's full test suite on the synthesized commit. Every test that passed on canonical (`HEAD` of canonical at Phase 0) must still pass.

**Test:**

```bash
./scripts/mr-check.sh --mr=no-regression \
  --canonical-sha 2c8e9d04 \
  --synthesis-sha d4e5f678

# Expected output:
# MR-5 No Regression PASS — 247 tests passed on canonical (sha 2c8e9d04); 247 still pass on synthesis d4e5f678
```

**Subtlety:** if a variant's intent is to *change* a canonical behavior (e.g., reject inputs that canonical accepts), the variant's test may FAIL on canonical's HEAD and PASS on the synthesis — that's intent-preservation, not regression. Distinguish via the variant's intent classification: `defensive` and `type-narrowing` intents are *expected* to change behavior on edge cases; `refactor` intents are NOT expected to change behavior (a refactor that breaks tests is a divergent refactor, which shouldn't have been auto-synthesized).

### 2.6 MR-6: Fingerprint Coverage

> **Relation:** Every fingerprint introduced by a participating variant appears in the synthesis (modulo canonical-form normalization).

```
For each variant V with fingerprint set F_V (functions, types, tests, fixture strings):
  F_V ⊆ fingerprint(synthesis)   (modulo formatter normalization)
```

**Why this MR:** if the synthesis dropped a function or type that a variant introduced, the variant's intent is incomplete. The synthesis should at minimum include every novel symbol the variants introduced (excluded only for the rare case where a refactor explicitly subsumed a function — and that should be in the harmonization plan as documented).

**Verification:** for each variant V, extract V's fingerprint per [TRIAGE-RUBRIC.md "FINGERPRINT Heuristics"](TRIAGE-RUBRIC.md#fingerprint-heuristics). For each symbol in V's fingerprint, search the synthesis. Each symbol should be found OR the variant matrix's `proposed synthesis` column for that variant should explicitly state "subsumed by other-variant's refactor."

**Test:**

```bash
./scripts/mr-check.sh --mr=fingerprint-coverage \
  --variants agent-cleanup-pass-3,feature/length-cap,feature/redact-secrets \
  --synthesis-sha d4e5f678

# Expected output:
# MR-6 Fingerprint Coverage PASS — all 6 fingerprint symbols from 3 variants present in synthesis:
#   agent-cleanup-pass-3 fingerprints (1): null_arg_guard ✓
#   feature/length-cap fingerprints (2): MAX_LOG_MSG_BYTES ✓, length-cap test ✓
#   feature/redact-secrets fingerprints (2): redact_secrets ✓, redact test ✓
```

### 2.7 MR-7: Dependency Closure

> **Relation:** If a variant introduces symbol X used by another variant's synthesis, the synthesis includes X.

```
If variant A introduces symbol X, and variant B uses X (directly or transitively),
then synthesis(A, B) includes X.
```

**Why this MR:** symbol dependencies must transitively close in the synthesis. A common synthesis bug is to include B's call site without A's definition, producing code that doesn't compile.

**Verification:** for each variant pair (A, B) where B uses a symbol introduced by A, check that A's symbol is present in the synthesis. Equivalent to MR-6 but specifically for cross-variant symbol use.

This is the symbol dependency in [HARMONIZATION-DEEP-DIVE.md §1.2](HARMONIZATION-DEEP-DIVE.md#12-what-an-edge-is). MR-7 is the run-time check that the dependency graph's "include all upstream" property is preserved in the actual synthesis.

**Test:**

```bash
./scripts/mr-check.sh --mr=dependency-closure \
  --plan harmonization_plan.md \
  --synthesis-sha d4e5f678

# Expected output:
# MR-7 Dependency Closure PASS — 6 cross-variant symbol deps verified, all closed:
#   feature_length-cap uses MAX_LOG_MSG_BYTES (introduced by self) ✓
#   feature_redact-secrets uses redact_secrets (introduced by self) ✓
#   ...
```

---

## 3. The Per-MR Test Harness

`scripts/mr-check.sh` runs each MR. Per-MR exit codes:

| Exit | Meaning |
|---|---|
| 0 | MR passed |
| 1 | MR failed (decisive — synthesis is wrong) |
| 2 | MR not applicable (e.g., MR-2 commutativity for refactor-feature pairs) |
| 3 | Could not run (missing inputs) |
| 4 | Inconclusive (e.g., test didn't terminate within timeout) |

The integration with Phase 8: per-apply gates ([SKILL.md Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms)) include the MR suite for `harmonized-synthesis` strategy applies. If any MR returns exit 1, the synthesis is reverted and the row's confidence drops.

### 3.1 The full MR run

```bash
./scripts/mr-check.sh --all \
  --plan harmonization_plan.md \
  --file src/util/logger.rs \
  --synthesis-sha d4e5f678

# Output:
# MR-1 Identity              PASS
# MR-2 Commutativity         PASS
# MR-3 Idempotence           PASS
# MR-4 Intent Preservation   PASS (3 intent-tests, all pass)
# MR-5 No Regression         PASS (247 canonical tests, all still pass)
# MR-6 Fingerprint Coverage  PASS (6/6 symbols)
# MR-7 Dependency Closure    PASS (6/6 cross-variant deps)
#
# All 7 MRs PASS. Synthesis confidence escalation: 0.91 → 0.999 (per DECISION-THEORY.md §7).
```

### 3.2 Per-MR runtime cost

| MR | Runtime (typical) | Cost driver |
|---|---|---|
| MR-1 Identity | seconds | Re-runs synthesis algorithm; canonical-form comparison |
| MR-2 Commutativity | seconds | Two algorithm runs; comparison |
| MR-3 Idempotence | seconds | One synthesis re-application |
| MR-4 Intent Preservation | minutes | Runs the variant's tests on synthesis |
| MR-5 No Regression | minutes-to-tens-of-minutes | Runs canonical's full test suite |
| MR-6 Fingerprint Coverage | seconds | Symbol-presence checks |
| MR-7 Dependency Closure | seconds | Symbol-presence checks |

The expensive MRs (4, 5) are *required* per-synthesis. The cheap MRs (1, 2, 3, 6, 7) can run on every synthesis without budget concerns.

### 3.3 Selective MR application

For Quick mode runs, the cheap MRs run; the expensive ones gate behind explicit user opt-in. For Comprehensive/Council mode, all 7 MRs run.

| Mode | MRs run by default |
|---|---|
| Quick | MR-1, MR-3, MR-6, MR-7 |
| Standard | MR-1, MR-2, MR-3, MR-6, MR-7 |
| Comprehensive | All 7 |
| Council | All 7, with MR-2 and MR-3 each run twice (for adversarial verification) |

---

## 4. Phase 9 Fresh-Eyes Integration

Phase 9 ([PHASES.md](PHASES.md)) verifies the run with three fresh-eyes prompts ≥2 rounds. The MR suite is run as an additional verification step.

### 4.1 The integration point

In Phase 9 round N (for N ≥ 2), `subagents/fresh-eyes.md` runs the MR suite for every harmonized synthesis from Phase 8. The MR results feed into the SPRT termination test from [DECISION-THEORY.md §5](DECISION-THEORY.md#5-sequential-testing-for-fresh-eyes-termination-sprt) — an MR failure counts as a `n_findings += 1`.

### 4.2 The harmonization-plan revision mechanism

If Phase 9 reveals an MR failure that Phase 8's per-apply gates missed (because MR-5 takes longer than per-apply gates allot, or the failure is a slow-emerging test):

1. The synthesis commit is reverted on the rationalization branch via `git revert <sha>` (NOT `git reset --hard`; revert preserves history).
2. The harmonization plan's row for that file is regenerated with the failure context.
3. Phase 7 re-runs for that file.
4. Phase 8 re-applies the revised synthesis.
5. Phase 9 re-runs the MR suite.

The cycle terminates when MRs pass OR the user surfaces the row as `divergent-refactor` (no synthesis possible).

### 4.3 Why MRs in Phase 9 not just Phase 8

Per-apply gates (Phase 8) check the synthesis against the project's test suite — that's MR-5 (No Regression). The other MRs are *internal coherence* checks that don't fit the project's existing test infrastructure. Phase 9's fresh-eyes context is the right place for them — the reviewer can see the MR failure and reason about WHY.

---

## 5. Worked Example — Logger.rs Synthesis Tested Against MR-1 to MR-7

Continuing the example from [HARMONIZATION-DEEP-DIVE.md §8](HARMONIZATION-DEEP-DIVE.md#8-the-loggerrs-synthesis--full-derivation-step-by-step). The synthesis is at SHA `d4e5f678`.

### 5.1 MR-1 Identity

Run synthesis with only `agent-cleanup-pass-3` and canonical:

```rust
// Result: canonical's logger.rs + null-arg guard
pub fn log(level: Level, msg: &str) -> Result<()> {
    if msg.is_empty() {
        return Err(LoggerError::EmptyMessage);
    }
    write_log_entry(level, msg)
}
```

Compare to `agent-cleanup-pass-3`'s content for `src/util/logger.rs` after `cargo fmt`. **Byte-equal. PASS.**

Repeat for `feature/length-cap` and `feature/redact-secrets`. Both **PASS**.

### 5.2 MR-2 Commutativity

Run synthesis in order (V1, V2) where V1 = `agent-cleanup-pass-3`, V2 = `feature/length-cap`. Result S₁₂.

Run synthesis in order (V2, V1). Result S₂₁.

```rust
S₁₂:
pub fn log(level: Level, msg: &str) -> Result<()> {
    if msg.is_empty() { return Err(LoggerError::EmptyMessage); }
    if msg.len() > MAX_LOG_MSG_BYTES { return Err(LoggerError::MessageTooLong(msg.len())); }
    write_log_entry(level, msg)
}

S₂₁:
pub fn log(level: Level, msg: &str) -> Result<()> {
    if msg.is_empty() { return Err(LoggerError::EmptyMessage); }
    if msg.len() > MAX_LOG_MSG_BYTES { return Err(LoggerError::MessageTooLong(msg.len())); }
    write_log_entry(level, msg)
}
```

The defensive-stage ordering rule (per [HARMONIZATION-DEEP-DIVE.md §6](HARMONIZATION-DEEP-DIVE.md#6-synthesis-dependency-order--defensive-checks)) says null-arg (Stage 2) precedes length-cap (Stage 3) regardless of input order. **Byte-equal. PASS.**

### 5.3 MR-3 Idempotence

Apply the harmonization plan to canonical → produces synthesis (commit `d4e5f678`).

Apply the *same plan* to `d4e5f678` (i.e., the synthesized state). The plan's per-hunk operations all become no-ops (the symbols already exist; the function body already has the guards). **0 line changes. PASS.**

### 5.4 MR-4 Intent Preservation

The three variants have intent-tests:

- `agent-cleanup-pass-3` → `tests/log_null.rs::test_log_rejects_empty`
- `feature/length-cap` → `tests/log_length.rs::test_log_rejects_too_long`
- `feature/redact-secrets` → `tests/log_redact.rs::test_log_redacts_secrets`

Run each on the synthesis at `d4e5f678`. **All 3 PASS. PASS.**

### 5.5 MR-5 No Regression

Canonical's full test suite at HEAD = 247 tests, all passing. Run on synthesis. **All 247 still pass. PASS.**

### 5.6 MR-6 Fingerprint Coverage

Variants' fingerprints:

```
agent-cleanup-pass-3:
  functions: []
  tests: [test_log_rejects_empty]

feature/length-cap:
  constants: [MAX_LOG_MSG_BYTES]
  tests: [test_log_rejects_too_long]

feature/redact-secrets:
  functions: [redact_secrets]
  tests: [test_log_redacts_secrets]
```

Search synthesis for each:

```bash
$ rg -tn '\bredact_secrets\b' src/util/logger.rs    # ✓
$ rg -tn '\bMAX_LOG_MSG_BYTES\b' src/util/logger.rs # ✓
$ rg -tn '\btest_log_rejects_empty\b' tests/log_null.rs  # ✓
$ rg -tn '\btest_log_rejects_too_long\b' tests/log_length.rs  # ✓
$ rg -tn '\btest_log_redacts_secrets\b' tests/log_redact.rs   # ✓
```

**5/5 fingerprint symbols present. PASS.**

### 5.7 MR-7 Dependency Closure

Cross-variant symbol uses:

- The synthesized `log()` uses `MAX_LOG_MSG_BYTES` (introduced by `feature/length-cap`) — present in synthesis. ✓
- The synthesized `log()` uses `redact_secrets` (introduced by `feature/redact-secrets`) — present in synthesis. ✓
- Both `tests/log_null.rs` and `tests/log_length.rs` use `LoggerError::EmptyMessage` and `LoggerError::MessageTooLong` — both present in canonical's `LoggerError` enum (extended by the synthesis if needed). ✓

**3/3 cross-variant deps closed. PASS.**

### 5.8 Confidence escalation

Per [DECISION-THEORY.md §7.4](DECISION-THEORY.md#74-composition-of-mrs):

```
prior 0.91 (planner's initial confidence)
all 7 MRs pass with P(pass | correct) = 0.99, P(pass | wrong) = 0.20

posterior ≈ 0.91 × 0.99⁷ / (0.91 × 0.99⁷ + 0.09 × 0.20⁷)
         ≈ 0.91 × 0.93 / (0.91 × 0.93 + 0.09 × 1.3 × 10⁻⁵)
         ≈ 0.999
```

The synthesis is decisively correct. Phase 8's per-apply gates already confirmed it; Phase 9 confirms it with the MR suite; the user can merge with high confidence.

---

## 6. When Metamorphic Testing Isn't Enough

MRs are powerful but not omnipotent. There are failure modes the MRs don't catch.

### 6.1 The oracle-blind trap

MR-7 (Dependency Closure) verifies that symbols used are defined. But MR-7 cannot detect *semantic* correctness of those symbols. Suppose `redact_secrets` is supposed to strip API keys but actually only strips one specific format and leaves others through. MR-7 sees the function present and the call site reachable; the synthesis passes. But the synthesis is silently wrong.

**Mitigation:** MR-4 (Intent Preservation) catches this IF the variant has a test that exercises the missed format. If the variant's tests are insufficient (the variant's author missed a format), MR-4 also misses it.

**Beyond MRs:** for security-sensitive synthesis (Council mode), additionally run [/testing-fuzzing](../../testing-fuzzing/SKILL.md) on the synthesized code to find inputs that the variant tests didn't cover. See [TESTING-FUZZING.md](TESTING-FUZZING.md) for synthesis-targeting fuzz harnesses.

### 6.2 The empty-test variant

If a variant introduces a defensive check but has no test for it, MR-4 (Intent Preservation) has no test to run. The MR returns "n/a" — neither pass nor fail.

**Mitigation:** the harmonization-planner subagent generates a minimal test for any intent that lacks one. The generated test is part of the synthesis. The user reviews it during Phase 7.

### 6.3 The composition-emergent regression

Two variants both pass their individual tests. The synthesis composes them. The composition introduces a new behavior that NEITHER variant tested for (because neither variant alone produced that behavior). MR-5 (No Regression) verifies canonical's tests pass; MR-4 verifies each variant's tests pass; but neither catches the composition-emergent behavior.

**Mitigation:** MR-1 + MR-3 + MR-6 + MR-7 together constrain the synthesis tightly enough that emergent behaviors are rare. For Council mode, the harmonization-planner subagent additionally generates "composition tests" — tests that exercise the composition's new behavior — and includes them in the synthesis. The composition tests are a synthesis-specific contribution beyond the variants' content.

### 6.4 The user must review

Per [HARMONIZATION.md §6.3](HARMONIZATION.md#63-the-harmonization-plan-is-a-user-reviewable-artifact-before-any-synthesis-commit-lands), the harmonization plan is *always* user-reviewed before Phase 8 runs. MRs are confidence boosters; user review is the ultimate oracle. A run that passes all 7 MRs but the user says "this isn't what I want" should not land — Phase 7's `⚠ CONFIRM` gate respects user judgment over MR results.

---

## 7. Cross-References

- [HARMONIZATION.md](HARMONIZATION.md) — the synthesis discipline this file verifies
- [HARMONIZATION-DEEP-DIVE.md](HARMONIZATION-DEEP-DIVE.md) — the algorithm whose output the MRs check
- [DECISION-THEORY.md §7](DECISION-THEORY.md#7-metamorphic-relations-as-confidence-boosters) — Bayesian update from MR results
- [TESTING-FUZZING.md](TESTING-FUZZING.md) — fuzzing the synthesis where MRs aren't enough
- [TESTING-CONFORMANCE.md](TESTING-CONFORMANCE.md) — conformance harness for the bundle (orthogonal to MR)
- [PHASES.md Phase 9](PHASES.md) — the fresh-eyes phase where MRs run
- [FRESH-EYES-PROMPTS.md](FRESH-EYES-PROMPTS.md) — the review prompts MRs supplement
- [/testing-metamorphic SKILL.md](../../testing-metamorphic/SKILL.md) — the underlying methodology

---

## 8. The Mantra

> **The synthesis has no oracle. The MRs are the oracle proxy. Identity, commutativity, idempotence, intent preservation, no-regression, fingerprint coverage, dependency closure: each MR is a property the synthesis must satisfy. All seven pass → confidence near 1.0. Any one fails → the synthesis is wrong; revert and re-plan.**
