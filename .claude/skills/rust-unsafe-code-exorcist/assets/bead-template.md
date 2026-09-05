# Bead Template

Pasted into `br create --description "$(cat <<'EOF' ... EOF)"` by the `bead-converter` subagent.

---

**Plan reference.** `audit/plans/site-NNNN.md` (or `cluster-R-NNN.md`)

**Bucket.** `(A) STRICTLY_UNAVOIDABLE | (B) PERF_ONLY | (C) REFACTORABLE`

**Pattern.** <FFI | Pin | allocator | SIMD | pointer migration | uninit | transmute | Send/Sync>

**Expected diff size.** `small (< 50 lines) | medium (50–250) | large (> 250)`

**Soundness surface.** `yes | no`

**Risk.** `Low | Medium | High`

---

## What this bead does

<1-2 sentence description of the change>

## Why

<1-2 sentence reason, citing the per-site write-up>

## Acceptance criteria

Copy-paste verbatim:

```bash
# Functional correctness
cargo test -p <crate> --test equivalence_site_NNNN
  # expected: tests pass

# Soundness
cargo +nightly miri test -p <crate> --test equivalence_site_NNNN
  # expected: 0 errors, no UB reports

# Performance (where applicable)
cargo bench --bench <bench>
  # expected: criterion mean within <N>% of baseline; see bench-site-NNNN.json

# Geiger delta
cargo +nightly geiger -p <crate>
  # expected: count decreased by <delta> (or unchanged for (A))

# (B) only:
cargo test --features safe-only --no-default-features -p <crate>
  # expected: tests pass under safe-only build

# (B) only — CI matrix:
# the .github/workflows/soundness.yml matrix must build/test all (OS, features, rustflags) tuples
```

## Dependencies

- Parent epic: `<EPIC-id>` (cluster)
- Prerequisite beads: `<bead-id>, <bead-id>` (if any)

## Back-references

- Per-site write-up: `audit/sites/<crate>/<file>__<line>.md`
- Classification: `audit/classification/site-<id>.md`
- Refactor plan: `audit/plans/site-<id>.md`
- Equivalence test: `audit/tests/equivalence_site_NNNN.rs`
- Exemplar precedent: `EXEMPLAR-CATALOG.md § <E-NNN>`

## Implementer notes

- Per AGENTS.md: incremental edits only; no destructive rewrites; no file deletion without permission.
- Run the acceptance criteria after every meaningful change; don't batch.
- If a tool finding surfaces outside the refactor's scope → file a `pre-existing-ub-N` bead, do NOT widen this bead.
- After acceptance criteria pass:
  ```
  br close <bead-id> --reason "see audit/plans/site-NNNN.md"
  ```
