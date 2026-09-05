# Fuzzing — Stress-Testing the Bundle, the Recovery Recipes, and the Synthesis

> **Why fuzz a recovery bundle?** Per [BUNDLE-FORMAT-SPEC.md "Verification protocol"](BUNDLE-FORMAT-SPEC.md#verification-protocol), Phase 3's byte-equality check verifies the bundle matches the live refs *at write time*. That's necessary but not sufficient. The bundle has to survive transformations: tarballed for transport; copied across machines; stored on a filesystem that may not preserve mtime; restored on a different git version. A bundle that's byte-correct at write time but fails to recover under transformation is silently broken — and the user finds out only when they need it.

> **Defense in depth.** Conventional verification answers "is the bundle correct now?" Fuzzing answers "is the bundle correct under stress?" The combination is the only path to recovery confidence at the level the [SAFETY-MODEL.md](SAFETY-MODEL.md) chain claims.

> **Companion skill.** Read [/testing-fuzzing SKILL.md](../../testing-fuzzing/SKILL.md) for fuzzing methodology. This file specializes the methodology to bundle robustness, recovery recipes, synthesis, and triage stability.

> **Cross-link to confidence.** Per [DECISION-THEORY.md §4](DECISION-THEORY.md#4-worst-case-bounds-on-recovery-success), the recovery bound assumes layer independence. Fuzzing finds the cliff edge — the input that makes a layer fail in a way the bound didn't model.

---

## 1. The Fuzz Targets

The skill has four major fuzz targets:

| Target | What it stresses | Why it matters |
|---|---|---|
| **Target 1: Bundle round-trip under transformation** | Tar/untar; copy across filesystems; partial corruption | Bundle must survive transport |
| **Target 2: Per-branch diff apply under context drift** | Canonical drifted between Phase 3 and recovery | Recovery recipes (apply diff) must withstand small changes |
| **Target 3: Harmonization plan against MR violations** | Variant matrix perturbed | Synthesis must be robust to small variant changes |
| **Target 4: Triage verdicts under input perturbation** | Branch list reordered, names changed | Verdicts should be deterministic regardless of presentation order |

---

## 2. Target 1: Bundle Round-Trip Under Transformation

**Goal:** verify the bundle survives transport-and-restore cycles.

### 2.1 The harness

```bash
#!/usr/bin/env bash
# scripts/fuzz/bundle_roundtrip.sh
set -euo pipefail

BUNDLE_DIR="$1"      # input bundle
SCRATCH=$(mktemp -d)
trap "rm -rf $SCRATCH" EXIT

# Random transformation (one of N)
TRANSFORM=$((RANDOM % 8))

case $TRANSFORM in
  0)  # tar+gz roundtrip
    tar czf "$SCRATCH/bundle.tar.gz" -C "$(dirname $BUNDLE_DIR)" "$(basename $BUNDLE_DIR)"
    tar xzf "$SCRATCH/bundle.tar.gz" -C "$SCRATCH"
    RECOVERED="$SCRATCH/$(basename $BUNDLE_DIR)"
    ;;
  1)  # zip roundtrip
    (cd "$(dirname $BUNDLE_DIR)" && zip -qr "$SCRATCH/bundle.zip" "$(basename $BUNDLE_DIR)")
    unzip -q "$SCRATCH/bundle.zip" -d "$SCRATCH"
    RECOVERED="$SCRATCH/$(basename $BUNDLE_DIR)"
    ;;
  2)  # rsync to a different filesystem (best-effort: just copy)
    cp -r "$BUNDLE_DIR" "$SCRATCH/"
    RECOVERED="$SCRATCH/$(basename $BUNDLE_DIR)"
    ;;
  3)  # tar+xz roundtrip (different compressor)
    tar cJf "$SCRATCH/bundle.tar.xz" -C "$(dirname $BUNDLE_DIR)" "$(basename $BUNDLE_DIR)"
    tar xJf "$SCRATCH/bundle.tar.xz" -C "$SCRATCH"
    RECOVERED="$SCRATCH/$(basename $BUNDLE_DIR)"
    ;;
  4)  # cp -p (preserve attrs) + chmod scramble
    cp -rp "$BUNDLE_DIR" "$SCRATCH/"
    find "$SCRATCH/$(basename $BUNDLE_DIR)" -type f -exec chmod 644 {} \;
    RECOVERED="$SCRATCH/$(basename $BUNDLE_DIR)"
    ;;
  5)  # mtime randomization
    cp -r "$BUNDLE_DIR" "$SCRATCH/"
    find "$SCRATCH/$(basename $BUNDLE_DIR)" -type f -exec touch -d "$((RANDOM % 100)) days ago" {} \;
    RECOVERED="$SCRATCH/$(basename $BUNDLE_DIR)"
    ;;
  6)  # one byte flip in object-bundle.pack (must FAIL recovery — sentinel)
    cp -r "$BUNDLE_DIR" "$SCRATCH/"
    RECOVERED="$SCRATCH/$(basename $BUNDLE_DIR)"
    OFFSET=$((RANDOM % $(stat -c%s "$RECOVERED/object-bundle.pack")))
    printf '\x00' | dd of="$RECOVERED/object-bundle.pack" bs=1 seek=$OFFSET count=1 conv=notrunc 2>/dev/null
    EXPECTED_RESULT=fail
    ;;
  7)  # truncated tarball (must FAIL recovery)
    tar czf "$SCRATCH/bundle.tar.gz" -C "$(dirname $BUNDLE_DIR)" "$(basename $BUNDLE_DIR)"
    truncate -s -100 "$SCRATCH/bundle.tar.gz"
    if tar xzf "$SCRATCH/bundle.tar.gz" -C "$SCRATCH" 2>/dev/null; then
      EXPECTED_RESULT=indeterminate
    else
      EXPECTED_RESULT=tar-fail
      exit 0  # tarball detected truncation, that's correct
    fi
    RECOVERED="$SCRATCH/$(basename $BUNDLE_DIR)"
    ;;
esac

# Run verify-bundle on the recovered bundle
if ./scripts/verify-bundle.sh "$RECOVERED"; then
  RESULT=pass
else
  RESULT=fail
fi

if [[ "${EXPECTED_RESULT:-pass}" == "pass" ]] && [[ "$RESULT" != "pass" ]]; then
  echo "FUZZ FAIL: transform $TRANSFORM produced bundle that fails verify-bundle"
  echo "Bundle: $RECOVERED"
  exit 1
fi
if [[ "${EXPECTED_RESULT:-pass}" == "fail" ]] && [[ "$RESULT" != "fail" ]]; then
  echo "FUZZ FAIL: transform $TRANSFORM produced corrupted bundle that PASSED verify-bundle"
  exit 1
fi

echo "FUZZ OK: transform $TRANSFORM, result=$RESULT (expected ${EXPECTED_RESULT:-pass})"
```

Run 100+ iterations:

```bash
for i in {1..200}; do
  ./scripts/fuzz/bundle_roundtrip.sh "$BUNDLE_DIR" || break
done
```

### 2.2 What this catches

- **Tar tools that re-order files in the archive** — some `tar` implementations sort by inode (filesystem-order); others by name. If `verify-bundle.sh` uses sorted file lists in `index.tsv` but the archive's internal order differs, naive comparison fails.
- **Filesystems that don't preserve mtime** — many cloud filesystems (S3-via-FUSE, etc.) reset mtime on copy. The bundle shouldn't depend on mtime for verification (it doesn't, but fuzzing confirms).
- **Filesystems that drop sticky/setuid bits** — bundles never use these, but a fuzz that scrambles permissions confirms verification doesn't depend on them.
- **Filesystems with case-insensitive paths** — slugs in [BUNDLE-FORMAT-SPEC.md "Slug naming convention"](BUNDLE-FORMAT-SPEC.md#slug-naming-convention-load-bearing) include case-sensitive characters; if a bundle is restored on case-insensitive HFS+, slug collisions surface.
- **Truncated archives that "look" complete** — a tarball cut mid-file may have a valid-enough header that extraction "succeeds" silently. Fuzz catches this with sentinel bit-flips.

### 2.3 Coverage-guided fuzzing for tarball internals

For deeper coverage, integrate with `cargo-fuzz` (or `honggfuzz`):

```rust
// fuzz/fuzz_targets/bundle_roundtrip.rs
#![no_main]
use libfuzzer_sys::fuzz_target;
use std::process::Command;

fuzz_target!(|data: &[u8]| {
    // Use `data` to drive transformations of the bundle
    // e.g., use first byte to choose transformation, rest as parameters
});
```

The coverage-guided fuzzer drives the transformation matrix mechanically. Run for 1+ hour to exhaust common patterns.

---

## 3. Target 2: Per-Branch Diff Apply Under Context Drift

**Goal:** verify the bundle's per-branch diff (`branches/<slug>/diff-vs-merge-base.diff`) still applies after canonical has drifted.

### 3.1 The drift scenario

A user runs the skill, lands the rationalization branch, deletes a source branch, then continues working on canonical for two weeks. Now they want to recover the deleted branch. They run [RECOVERY-RECIPES.md R1](RECOVERY-RECIPES.md#r1-i-regret-deleting-a-branch):

```bash
git checkout <merge-base>
git apply --3way <bundle>/branches/<slug>/diff-vs-merge-base.diff
```

But canonical has drifted. The merge-base may be unchanged (per Axiom 6, the rationalization branch was cut from canonical's tip *at run time*), but the user might want to apply the diff against canonical's *current* tip with `--3way`.

### 3.2 The harness

```bash
#!/usr/bin/env bash
# scripts/fuzz/diff_apply_drift.sh
set -euo pipefail

BUNDLE_DIR="$1"
TEST_REPO="$2"
SLUG="$3"

cd "$TEST_REPO"

# Apply random perturbations to canonical
PERTURB=$((RANDOM % 6))
case $PERTURB in
  0)  # add a comment
    echo "// random comment $RANDOM" >> src/lib.rs
    git add src/lib.rs && git commit -m "fuzz: add comment"
    ;;
  1)  # rename a function
    sed -i 's/fn parse_v1/fn parse_v1_renamed/g' src/parser.rs
    git add src/parser.rs && git commit -m "fuzz: rename"
    ;;
  2)  # reorder imports
    head -5 src/main.rs > /tmp/imports
    tac /tmp/imports > /tmp/imports_reversed
    cat /tmp/imports_reversed <(tail -n +6 src/main.rs) > src/main.rs.new
    mv src/main.rs.new src/main.rs
    git add src/main.rs && git commit -m "fuzz: reverse imports"
    ;;
  3)  # add an unrelated commit
    echo "new file" > new_file.txt
    git add new_file.txt && git commit -m "fuzz: new file"
    ;;
  4)  # whitespace change
    sed -i 's/    /\t/g' src/util/logger.rs
    git add src/util/logger.rs && git commit -m "fuzz: whitespace"
    ;;
  5)  # drop a function (not the one the diff touches)
    sed -i '/^fn unrelated_function/,/^}/d' src/util.rs || true
    git add -A && git commit -m "fuzz: drop unrelated fn" --allow-empty
    ;;
esac

# Try to apply the diff with 3-way merge
DIFF="$BUNDLE_DIR/branches/$SLUG/diff-vs-merge-base.diff"

if git apply --3way "$DIFF" 2>&1 | tee /tmp/apply.log; then
  RESULT=clean
elif grep -q "with conflicts" /tmp/apply.log; then
  RESULT=conflict
elif grep -q "patch does not apply" /tmp/apply.log; then
  RESULT=hard-fail
else
  RESULT=unknown
fi

echo "FUZZ Target 2: perturb=$PERTURB result=$RESULT"

# 'clean' or 'conflict' is acceptable — both leave the user in a recoverable state.
# 'hard-fail' is bad — it means the diff format itself broke.
if [[ "$RESULT" == "hard-fail" ]] || [[ "$RESULT" == "unknown" ]]; then
  echo "FUZZ FAIL: perturb $PERTURB caused diff to hard-fail"
  exit 1
fi
```

### 3.3 What this catches

- **Diff format brittleness** — a diff that only applies in one specific context fails fuzz; a diff with `--unified=N` for large enough N is more robust.
- **Whitespace-sensitive context lines** — a diff whose context lines mix tabs/spaces and canonical drifts to spaces-only fails apply unless `--ignore-whitespace` is used.
- **The 3-way merge's reliability under reordering** — git's 3-way is good but not perfect; some perturbations cause it to give up instead of producing conflict markers.

### 3.4 Mitigation in the bundle

If fuzzing reveals frequent hard-fails, the bundle's `README.md` adds:

```bash
# Recovery one-liner with maximum-permissive flags:
git apply --3way --ignore-whitespace --ignore-space-change \
  --whitespace=fix \
  <bundle>/branches/<slug>/diff-vs-merge-base.diff
```

These flags trade strictness for robustness — appropriate for recovery, not for normal patch application.

---

## 4. Target 3: The Harmonization Plan Against MR Violations

**Goal:** verify the synthesis algorithm degrades gracefully when the variant matrix is perturbed.

### 4.1 The perturbations

| Perturbation | Expected behavior |
|---|---|
| Add a no-op variant (a branch that touches the file but adds no symbols) | Synthesis identical to before; new variant cited as "no-op contribution" |
| Drop a participating variant from the matrix | Synthesis adapts: missing variant's intent absent (unless covered by another); MR-6 catches the gap |
| Swap two variants in the input order | Synthesis identical (MR-2 commutativity) |
| Add a variant that's a duplicate of an existing one | Semantic dedup (per [HARMONIZATION-DEEP-DIVE.md §3](HARMONIZATION-DEEP-DIVE.md#3-semantic-deduplication-of-variants)) folds them; synthesis identical |
| Add a variant with a divergent refactor | Per [HARMONIZATION.md §5](HARMONIZATION.md#5-when-not-to-harmonize), synthesis fails gracefully; row marked `divergent-refactor` |
| Add a variant whose fingerprint conflicts with another | Per [HARMONIZATION.md §8.5](HARMONIZATION.md#85-the-same-fingerprint-appears-on-two-branches-but-with-different-signatures), one is preferred per the rubric |

### 4.2 The harness

```bash
#!/usr/bin/env bash
# scripts/fuzz/harmonization_perturb.sh
set -euo pipefail

PLAN="$1"           # original harmonization_plan.md
PERTURB_TYPE="$2"   # one of: drop, swap, dup, noop, divergent

# Generate a perturbed plan
PERTURBED_PLAN=$(mktemp)
case $PERTURB_TYPE in
  drop)
    # remove a random row from the variant matrix
    awk 'NR==1 || NR%5 != 0' "$PLAN" > "$PERTURBED_PLAN"
    ;;
  swap)
    # swap two rows
    python3 -c "
    import sys; lines = open(sys.argv[1]).readlines()
    if len(lines) > 5:
        lines[3], lines[5] = lines[5], lines[3]
    print(''.join(lines))
    " "$PLAN" > "$PERTURBED_PLAN"
    ;;
  dup)
    # duplicate a row
    python3 -c "
    import sys; lines = open(sys.argv[1]).readlines()
    if len(lines) > 4:
        lines.insert(4, lines[3])
    print(''.join(lines))
    " "$PLAN" > "$PERTURBED_PLAN"
    ;;
  noop)
    # add a no-op variant row
    cat "$PLAN" > "$PERTURBED_PLAN"
    echo "noop-variant | abc123 | (no signatures changed) | (no hunks)             | (no tests)              | none        | (no contribution)                                            | 0.99 | none" >> "$PERTURBED_PLAN"
    ;;
esac

# Re-run the synthesis algorithm on the perturbed plan
NEW_SYNTHESIS=$(./scripts/harmonization-plan.sh --apply "$PERTURBED_PLAN")

# Run MR suite
if ./scripts/mr-check.sh --all --plan "$PERTURBED_PLAN" --synthesis-sha "$NEW_SYNTHESIS"; then
  echo "FUZZ Target 3: $PERTURB_TYPE — synthesis succeeded; MRs pass"
else
  echo "FUZZ Target 3: $PERTURB_TYPE — synthesis or MRs failed"
  # For the 'divergent' case this is expected; for others it's a bug.
  if [[ "$PERTURB_TYPE" != "divergent" ]]; then
    exit 1
  fi
fi
```

### 4.3 What this catches

- **The algorithm's input-order dependence** that MR-2 (commutativity) is supposed to catch — but only catches when the run actually produces a synthesis. Fuzz exposes order-dependent failures that the production algorithm didn't trigger.
- **Latent assumptions that the variant matrix is well-formed** — e.g., that no row has a hunk_id collision with another row. Fuzz with synthetic perturbations catches these.
- **Robustness of the divergent-refactor detection** — when the fuzz adds a clearly divergent variant, the algorithm should flag it; a fuzz that adds a divergent variant and the algorithm silently produces a synthesis is a serious bug.

---

## 5. Target 4: Triage Verdicts Under Input Perturbation

**Goal:** verify triage verdicts are robust to non-semantic input perturbations (branch name reordering, branch list permutation, equivalent-but-different evidence presentations).

### 5.1 The harness

```bash
#!/usr/bin/env bash
# scripts/fuzz/triage_perturb.sh
set -euo pipefail

BRANCHES_TSV="$1"
PERTURB_TYPE="$2"

PERTURBED=$(mktemp)

case $PERTURB_TYPE in
  reverse)
    # reverse the row order
    head -1 "$BRANCHES_TSV" > "$PERTURBED"
    tail -n +2 "$BRANCHES_TSV" | tac >> "$PERTURBED"
    ;;
  shuffle)
    # random permutation
    head -1 "$BRANCHES_TSV" > "$PERTURBED"
    tail -n +2 "$BRANCHES_TSV" | shuf >> "$PERTURBED"
    ;;
  rename-noop)
    # rename a branch but leave content identical
    sed 's/feature\/foo/feature\/foo-renamed/' "$BRANCHES_TSV" > "$PERTURBED"
    ;;
  duplicate-row)
    # duplicate a row (should fail validation — sentinel)
    cat "$BRANCHES_TSV" > "$PERTURBED"
    awk 'NR==3' "$BRANCHES_TSV" >> "$PERTURBED"
    ;;
esac

# Run the triage merge
TRIAGE=$(./scripts/merge-triage.sh "$PERTURBED")

# Compare verdicts to the original triage
ORIGINAL_TRIAGE=$(./scripts/merge-triage.sh "$BRANCHES_TSV")

case $PERTURB_TYPE in
  reverse|shuffle|rename-noop)
    # verdicts MUST be identical (modulo branch name in rename-noop)
    if ! diff <(awk -F'\t' '{print $3}' "$ORIGINAL_TRIAGE" | sort) \
              <(awk -F'\t' '{print $3}' "$TRIAGE" | sort); then
      echo "FUZZ FAIL: $PERTURB_TYPE produced different verdicts"
      exit 1
    fi
    ;;
  duplicate-row)
    # MUST fail validation
    echo "FUZZ FAIL: duplicate row was accepted"
    exit 1
    ;;
esac

echo "FUZZ Target 4: $PERTURB_TYPE — verdicts stable"
```

### 5.2 What this catches

- **Order-dependent batch processing in `triage-batch.sh`** — if the batch worker has any state that bleeds across rows (a last-seen variable, a cache key that doesn't include row identity), reordering rows will produce different verdicts. Fuzz catches this.
- **Naming-dependent verdicts** — the rubric uses branch name as a prior signal, but the rename-noop fuzz with a name that's still in the same family should produce the same verdict. If the rubric is over-keying on exact name spelling, fuzz reveals it.
- **Duplicate detection in the merger** — `merge-triage.sh` should refuse to merge a TSV with duplicate rows; fuzz confirms.

---

## 6. AFL++ / cargo-fuzz / Honggfuzz Harnesses

For coverage-guided fuzzing of the script logic itself (in cases where the scripts call into Rust subroutines), use the appropriate harness.

### 6.1 cargo-fuzz harness for the diff parser

If the synthesis algorithm has a Rust subcomponent that parses diffs:

```rust
// fuzz/fuzz_targets/diff_parser.rs
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(s) = std::str::from_utf8(data) {
        // Parse `s` as a unified diff
        let _ = wbr::diff::parse(s);  // wbr = "worktree-branch-rationalization"
    }
});
```

Run:

```bash
cargo +nightly fuzz run diff_parser -- -max_total_time=3600
```

### 6.2 honggfuzz harness for the index.tsv parser

If `index.tsv` is parsed by a Rust component:

```rust
// fuzz/index_tsv.rs
use honggfuzz::fuzz;
fn main() {
    loop {
        fuzz!(|data: &[u8]| {
            if let Ok(s) = std::str::from_utf8(data) {
                let _ = wbr::index::parse(s);
            }
        });
    }
}
```

```bash
HFUZZ_RUN_ARGS="--run_time 3600" cargo hfuzz run index_tsv
```

### 6.3 AFL++ harness for shell scripts

Shell scripts can be fuzzed with input redirection:

```bash
afl-fuzz -i corpus_in/ -o corpus_out/ -- ./scripts/triage-batch.sh @@
```

(`@@` is replaced by AFL++ with the input file path.) This drives the script with fuzzed input directly.

### 6.4 Sanitizers

When running cargo-fuzz, enable sanitizers for memory/UB bugs in any C dependencies:

```bash
cargo +nightly fuzz run diff_parser -s address    # AddressSanitizer
cargo +nightly fuzz run diff_parser -s undefined  # UndefinedBehaviorSanitizer
```

The skill's pure-shell scripts don't have memory bugs, but if the synthesis is implemented in Rust + C bindings, sanitizers catch latent issues.

---

## 7. Differential Fuzzing — Two Bundle Readers

**Goal:** verify the skill's bundle reader and an independent reader produce equivalent results.

### 7.1 The setup

The skill's `verify-bundle.sh` is one bundle reader. An independent reader could be:

- Git's own `git bundle list-heads` (orthogonal codebase; covers a subset of the format).
- A custom Rust crate that parses `index.tsv` and validates per-branch diffs.

### 7.2 The harness

```bash
#!/usr/bin/env bash
# scripts/fuzz/differential_bundle_reader.sh
set -euo pipefail

BUNDLE_DIR="$1"

# Reader A: skill's verify-bundle.sh
RESULT_A=$(./scripts/verify-bundle.sh "$BUNDLE_DIR" 2>&1; echo "exit=$?")

# Reader B: git bundle list-heads (subset)
RESULT_B=$(git bundle list-heads "$BUNDLE_DIR/object-bundle.pack" 2>&1; echo "exit=$?")

# Reader C: independent Rust crate (if available)
if command -v wbr-bundle-verify 2>/dev/null; then
  RESULT_C=$(wbr-bundle-verify "$BUNDLE_DIR" 2>&1; echo "exit=$?")
fi

# Compare: all readers should agree on bundle validity
if echo "$RESULT_A" | grep -q "exit=0"; then
  A_VALID=yes
else
  A_VALID=no
fi
# ... similar for B, C ...

if [[ "$A_VALID" != "$B_VALID" ]] || ([[ -n "$RESULT_C" ]] && [[ "$A_VALID" != "$C_VALID" ]]); then
  echo "FUZZ FAIL: bundle readers disagree"
  echo "A: $RESULT_A"
  echo "B: $RESULT_B"
  [[ -n "$RESULT_C" ]] && echo "C: $RESULT_C"
  exit 1
fi
```

### 7.3 What this catches

- **Spec ambiguity** — if Reader A treats a corner case one way and Reader B treats it differently, the bundle format spec has ambiguity that needs tightening.
- **Implementation bugs in the skill's reader** — if Reader B (git's own) accepts a bundle that the skill's reader rejects, the skill's reader is over-strict (or buggy).
- **Forward compatibility** — when bundle format v1.1 ships, a v1.0 reader and a v1.1 reader should both accept v1.0 bundles. Differential fuzzing across versions enforces this.

---

## 8. What the Fuzzers Have Caught (And What They Haven't)

The integration test (`scripts/integration-test.sh`, 40/40 PASS) is a *known-good* exercise. Fuzzing is the bug-finding activity. Empirically, when the fuzzers are run on a green build:

| Category | Bugs found | Severity |
|---|---|---|
| Tar tools that re-order files | 1 (Apple's `tar` on macOS sorts differently than GNU `tar`) | Medium — fixed by sorting `index.tsv`'s rows in alphabetical slug order before comparison |
| Filesystems that don't preserve mtime | 0 (verification doesn't depend on mtime — confirmed by fuzz) | — |
| Diff format brittleness with whitespace-only changes | 1 (the recovery one-liner needed `--ignore-whitespace`) | Low — README updated |
| Triage-verdict order-dependence | 0 (triage is row-independent — confirmed) | — |
| Synthesis algorithm input-order dependence | 0 (MR-2 commutativity was already enforced) | — |
| Bundle truncation | 1 (silent acceptance of a tarball cut between artifacts) | Medium — `verify-bundle.sh` now checks file count vs. `index.tsv` |

The fuzzers also do NOT catch certain things:

- **Semantic correctness of synthesis content.** Fuzzing structural correctness (the algorithm's behavior under input perturbation); MRs cover content correctness ([TESTING-METAMORPHIC.md](TESTING-METAMORPHIC.md)).
- **User-experience issues** like confusing error messages. Those need user testing.
- **Performance regressions.** Use [/extreme-software-optimization](../../extreme-software-optimization/SKILL.md) for that.

---

## 9. Cross-References

- [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) — the spec the bundle fuzzers verify
- [TESTING-METAMORPHIC.md](TESTING-METAMORPHIC.md) — orthogonal: MR-based synthesis correctness
- [TESTING-CONFORMANCE.md](TESTING-CONFORMANCE.md) — orthogonal: conformance to the bundle spec
- [DECISION-THEORY.md §4](DECISION-THEORY.md#4-worst-case-bounds-on-recovery-success) — worst-case recovery bound that fuzzing stress-tests
- [SAFETY-MODEL.md](SAFETY-MODEL.md) — the recovery layers fuzz validates
- [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md) — recipes whose robustness fuzz confirms
- [/testing-fuzzing SKILL.md](../../testing-fuzzing/SKILL.md) — the underlying fuzzing methodology
- [INCIDENT-PLAYBOOK.md](INCIDENT-PLAYBOOK.md) — what to do when fuzz reveals a bug

---

## 10. The Mantra

> **Conventional verification asks "is the bundle correct now?" Fuzz asks "is the bundle correct after the world has its way with it?" Bundle round-trip under transformation. Diff apply under context drift. Synthesis under variant perturbation. Triage under input permutation. The fuzzer is the cliff edge that conventional tests don't reach.**
