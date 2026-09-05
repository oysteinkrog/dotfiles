# 20-SIMD-AND-PERF.md — SIMD, get_unchecked, and the safe-only Feature Flag

This is the (B) bucket's canonical playbook. SIMD and other perf-motivated unsafe gets:

1. A safe alternative gated behind `--features safe-only`.
2. Measured before/after perf on every target the crate ships.
3. A CI matrix entry building both feature combinations.
4. A graduation rule: if the perf delta is within budget, the site moves to (C) and the unsafe is deleted.

---

## The cascade of safe alternatives

For any SIMD-style perf-unsafe site, try in order:

1. **`std::simd` (portable SIMD).** Nightly-only currently, but portable across targets.
2. **`wide` crate.** Stable, covers x86_64 + aarch64 + wasm32 SIMD.
3. **`packed_simd_2` / `safe_arch`.** Limited surfaces, stable.
4. **Autovectorization-friendly safe loop.** No SIMD intrinsics; trust LLVM to vectorize.
5. **Algorithmic improvement** that eliminates the hot loop.

Stop at the first that meets the perf budget. The unsafe `std::arch::*` version stays behind `#[cfg(not(feature = "safe-only"))]`.

---

## The safe-only feature flag

In `Cargo.toml`:

```toml
[features]
default = []                    # perf path on by default
safe-only = []                  # opt-in: zero unsafe in the perf code
```

In code:

```rust
#[cfg(not(feature = "safe-only"))]
pub fn parse_u64_decimal(bytes: &[u8]) -> Option<u64> {
    // Hand-rolled SIMD; the (B) site.
    parse_u64_decimal_simd(bytes)
}

#[cfg(feature = "safe-only")]
pub fn parse_u64_decimal(bytes: &[u8]) -> Option<u64> {
    // Safe alternative via std::simd or autovec.
    parse_u64_decimal_safe(bytes)
}
```

Both functions live in the same source file (next to each other) so reviewers see them as a pair. The unsafe one's SAFETY comment cites the safe alternative as the fallback.

---

## Per-target bench protocol (mandatory for (B))

A (B) classification requires measurements on EVERY target the crate ships. The minimum target set for a SIMD-heavy crate:

- `x86_64-unknown-linux-gnu` with `target-cpu=x86-64-v2` (AVX, SSE4.2)
- `x86_64-unknown-linux-gnu` with `target-cpu=x86-64-v3` (AVX2)
- `x86_64-unknown-linux-gnu` with `target-cpu=x86-64-v4` (AVX-512) — when shipped
- `aarch64-unknown-linux-gnu` (NEON)
- `aarch64-apple-darwin` (Apple silicon)
- `wasm32-unknown-unknown` with `target-feature=+simd128` — when shipped

Run for each target:

```bash
# criterion (microbench)
cargo bench --bench parse_u64 -- --output-format bencher \
  > bench/criterion-<target>-<features>.txt

# hyperfine (end-to-end)
hyperfine --warmup 5 --runs 20 \
  './target/release/myapp --workload canonical' \
  --export-json bench/hyperfine-<target>-<features>.json

# flamegraph (where on the path are we spending time?)
cargo flamegraph --bin myapp --output bench/flame-<target>-<features>.svg \
  -- --workload canonical
```

Aggregate into `audit/plans/site-<id>.md § Per-target bench results`:

| Target | criterion mean (default) | criterion mean (safe-only) | hyperfine (default) | hyperfine (safe-only) | Δ (end-to-end) |
|--------|--------------------------|---------------------------|---------------------|----------------------|----------------|
| x86_64-v2 | 142 ns | 198 ns | 1.42 s | 1.71 s | +20.4% |
| x86_64-v3 | 102 ns | 109 ns | 1.32 s | 1.36 s | +3.0% |
| x86_64-v4 | 78 ns | 88 ns | 1.21 s | 1.24 s | +2.5% |
| aarch64 (Linux) | 156 ns | 164 ns | 1.51 s | 1.55 s | +2.6% |
| aarch64 (macOS) | 152 ns | 159 ns | 1.49 s | 1.52 s | +2.0% |
| wasm32 | 489 ns | 521 ns | n/a | n/a | +6.5% |

Then the budget check:

```
User's perf budget: 5%
Targets within budget: x86_64-v3 (+3.0%), x86_64-v4 (+2.5%), aarch64-linux (+2.6%),
                       aarch64-macos (+2.0%) — 4 of 6
Targets over budget:   x86_64-v2 (+20.4%), wasm32 (+6.5%) — 2 of 6

Decision: KEEP unsafe behind feature flag for x86_64-v2 and wasm32; GRADUATE to (C)
for x86_64-v3+ and aarch64 (safe alternative is within budget).
```

This is the common outcome: SIMD wins on older / less-vectorized targets, ties on newer ones. The safe-only feature ships the safe version everywhere; the default feature picks the unsafe only where it matters.

---

## CI matrix entry

The harness builder emits `assets/ci-matrix.yml.template`. The crucial bits:

```yaml
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-14, macos-13]
        rust: [stable, nightly]
        feature: [all-features, safe-only]
        rustflags:
          - "-C target-cpu=x86-64-v2"
          - "-C target-cpu=x86-64-v3"
          # add v4 if the project supports AVX-512
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - run: rustup default ${{ matrix.rust }}
      - run: |
          if [ "${{ matrix.feature }}" = "safe-only" ]; then
            cargo test --no-default-features --features safe-only
          else
            cargo test --all-features
          fi
        env:
          RUSTFLAGS: ${{ matrix.rustflags }}

  soundness:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: rustup default nightly
      - run: rustup component add miri rust-src
      - run: cargo +nightly miri test --features safe-only
```

The matrix grows quickly (3 OS × 2 rust × 2 features × 3 rustflags = 36 jobs). For larger projects, scope down the rustflags to just the targets the project ships.

---

## Common SIMD refactors

### Refactor S-1: `_mm_loadu_si128` → `std::simd::u8x16`

```rust
// Before
use core::arch::x86_64::*;
fn count_byte_unsafe(haystack: &[u8], needle: u8) -> usize {
    let mut count = 0;
    let needle_v = unsafe { _mm_set1_epi8(needle as i8) };
    for chunk in haystack.chunks_exact(16) {
        // SAFETY: chunk is 16 bytes; SSE4 loadu doesn't require alignment.
        let chunk_v = unsafe { _mm_loadu_si128(chunk.as_ptr() as *const __m128i) };
        let cmp = unsafe { _mm_cmpeq_epi8(chunk_v, needle_v) };
        let mask = unsafe { _mm_movemask_epi8(cmp) };
        count += mask.count_ones() as usize;
    }
    // tail
    count + haystack.chunks_exact(16).remainder().iter()
                                                  .filter(|&&b| b == needle).count()
}

// After (safe-only path)
#![feature(portable_simd)]    // nightly
use std::simd::u8x16;
use std::simd::cmp::SimdPartialEq;
fn count_byte_safe(haystack: &[u8], needle: u8) -> usize {
    let needle_v = u8x16::splat(needle);
    let mut count = 0usize;
    for chunk in haystack.chunks_exact(16) {
        let chunk_v = u8x16::from_slice(chunk);
        count += chunk_v.simd_eq(needle_v).to_bitmask().count_ones() as usize;
    }
    count + haystack.chunks_exact(16).remainder().iter()
                                                  .filter(|&&b| b == needle).count()
}
```

On x86_64-v3, this is typically within 1.05× of the hand-rolled SIMD. On x86_64-v2, the gap can be wider (LLVM doesn't always emit the optimal AVX path).

### Refactor S-2: SIMD via the `wide` crate (stable)

When `std::simd` isn't available (stable toolchain), `wide` covers most cases:

```rust
use wide::u8x16;
fn count_byte_wide(haystack: &[u8], needle: u8) -> usize {
    let needle_v = u8x16::splat(needle);
    haystack.chunks_exact(16).map(|chunk| {
        let chunk_v = u8x16::new([
            chunk[0], chunk[1], chunk[2], chunk[3],
            chunk[4], chunk[5], chunk[6], chunk[7],
            chunk[8], chunk[9], chunk[10], chunk[11],
            chunk[12], chunk[13], chunk[14], chunk[15],
        ]);
        chunk_v.cmp_eq(needle_v).move_mask().count_ones() as usize
    }).sum::<usize>()
    + haystack.chunks_exact(16).remainder().iter()
                                            .filter(|&&b| b == needle).count()
}
```

`wide` covers x86_64 + aarch64 + wasm32 with one source. Stable-toolchain-safe.

### Refactor S-3: autovectorization-friendly safe loop

For simple data parallel operations, LLVM can autovectorize:

```rust
fn sum_u32(xs: &[u32]) -> u64 {
    // LLVM will autovectorize this if -C opt-level=3 and target-cpu enables SIMD.
    xs.iter().map(|&x| x as u64).sum()
}
```

Verify with `cargo asm` (the `cargo-show-asm` crate). The autovec works when:
- The loop body is simple (no early-return, no panicking arithmetic).
- The data type maps to a SIMD register (u8/u16/u32/u64/f32/f64).
- The operation has a SIMD-friendly reduction or map.

Doesn't work when:
- The loop has data-dependent branches.
- The reduction is order-dependent (e.g., f32 sum where order changes result).
- The data is gather-load (non-contiguous).

### Refactor S-4: `slice::get_unchecked` in inner loop

For bounds-check elision in hot loops:

```rust
// Before
fn dot_product_unsafe(a: &[f32], b: &[f32]) -> f32 {
    debug_assert_eq!(a.len(), b.len());
    let mut acc = 0.0;
    for i in 0..a.len() {
        // SAFETY: a and b have equal length per debug_assert_eq.
        acc += unsafe { *a.get_unchecked(i) * *b.get_unchecked(i) };
    }
    acc
}

// After (safe alternative — uses iterator combinators)
fn dot_product_safe(a: &[f32], b: &[f32]) -> f32 {
    a.iter().zip(b).map(|(&x, &y)| x * y).sum()
}
```

The iterator version is usually within 0.95–1.0× of the unsafe one — LLVM has good iterator-loop autovectorization. Measure and graduate to (C) if it ties.

When `slice::get_unchecked` STAYS as (B): when the index is computed in a way LLVM can't prove in-bounds (e.g., `xs[hash(key) & mask]` for a power-of-two hash table). In that case, bounds-check elision is worth the unsafe.

---

## Anti-patterns specific to SIMD

- **Benching only on the dev machine's target.** A pattern that wins on x86_64-v3 may lose on aarch64. Bench every target the crate ships.
- **Benching only criterion (microbench).** Microbench wins don't always propagate to wall-clock. Run hyperfine on a representative binary.
- **`std::simd` for AVX-512.** AVX-512 has known issues with thermal throttling on some Intel CPUs; benchmark carefully on the workload's actual deployment.
- **Comparing against `cargo bench --release` without `target-cpu` set.** Default target-cpu is conservative (x86_64). Set `RUSTFLAGS="-C target-cpu=native"` for representative benches; document the target-cpu in the result file.

---

## Graduation: when (B) becomes (C)

A (B) site graduates to (C) when:

- The safe alternative's perf delta is within the user's budget on EVERY shipped target.
- No reviewer raises a "this is folklore" objection in Phase 6 / 10.
- The benches are repeatable (3 runs within 2% of each other).

After graduation:

- Delete the unsafe code path.
- Delete the `#[cfg(...)]` branches; the safe path is unconditional.
- Update `Cargo.toml` to remove the `safe-only` feature if no other (B) site uses it.
- Update the CHANGELOG noting the soundness improvement.

---

## When the bench machine is the only available test target

Sometimes the audit machine is the only available target (e.g., an x86_64 dev box, no aarch64 hardware). Options:

- **GitHub Actions runners.** Use `macos-14` for aarch64-darwin, `ubuntu-latest-arm64` for aarch64-linux.
- **QEMU.** Run aarch64 binaries via `qemu-aarch64`; bench numbers are approximate but useful for ordering.
- **Cross-compile + statically analyze.** `cargo asm` to inspect the generated SIMD; doesn't give perf numbers but reveals whether autovec is happening.
- **Document the gap.** The plan says "benched on x86_64-v3 only; aarch64 bench deferred; assume safe alternative is within budget; revisit in CI when aarch64 runner is available."

Document the deferred bench as a `pre-existing-ub`-style follow-up bead so it's tracked.

---

## Acceptance signal

A SIMD (B) classification passes when:

1. The safe alternative path is implemented behind `#[cfg(feature = "safe-only")]`.
2. Per-target bench numbers are filled in (criterion + hyperfine + flamegraph).
3. The CI matrix entry is added to `audit/ci-matrix.yml`.
4. The budget check is explicit per target.
5. If any target is within budget, the graduation-to-(C) decision is documented (graduate this target's path; keep unsafe only for the targets where it's needed).
6. The `cargo +nightly geiger` delta is accounted for.
