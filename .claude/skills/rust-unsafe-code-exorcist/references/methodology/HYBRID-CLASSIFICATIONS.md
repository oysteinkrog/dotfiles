# HYBRID-CLASSIFICATIONS.md — Sites That Mix Buckets

Real audits surface sites that don't fit cleanly into a single (A) / (B) / (C) bucket. The classic shape: a thin FFI shim (which is (A) because the C ABI is outside Rust's type system) contains inside it an `unsafe { *slice.get_unchecked(i) }` call (a (B) decision for a perf-only bounds-check elision). Two distinct soundness arguments live in the same site.

[CLASSIFICATION-RUBRIC.md](CLASSIFICATION-RUBRIC.md) requires every site to belong to **exactly one** bucket. That rule still holds; what this file adds is the protocol for when a site's secondary characteristic carries its own deliverable.

---

## The rule, restated

> Classify every site by its **primary** unsafe-justification. The primary justification is the *reason this unsafe exists at all*. If you removed every other unsafe characteristic, would there still be a reason for this site to be unsafe? That residual reason is the bucket.

The secondary characteristics — perf-only inner code, refactorable adjacent code — DON'T change the bucket, but they MAY still require the deliverables of their own bucket.

---

## Examples

### Example H-1 — (A) FFI shim containing (B) perf code

```rust
/// Sound wrapper around `libc::pwrite` with vectored-IO optimization.
///
/// SAFETY: see SAFETY comment inside.
pub fn pwrite_vec(fd: RawFd, iov: &[IoSlice]) -> io::Result<usize> {
    // SAFETY: `iov` is a Rust slice (valid for reads); `iov.len()` fits in libc's int range
    // (caller-side validation in IoSlice constructor). The slice elements are repr(C)-compatible.
    // The (A) is the FFI itself; libc::pwritev is outside Rust's type system.
    let n = unsafe {
        // (B): get_unchecked here for the iov[0] dereference, perf-only.
        let first_ptr = iov.get_unchecked(0).as_ptr();
        libc::pwritev(fd, first_ptr as *const _, iov.len() as i32)
    };
    if n < 0 { return Err(io::Error::last_os_error()); }
    Ok(n as usize)
}
```

**Primary bucket:** (A) — the `libc::pwritev` call is the irreducible unsafe; removing it would require reimplementing the kernel side.

**Secondary characteristic:** (B) — the `get_unchecked` is a perf optimization that has a safe alternative (`iov[0].as_ptr()` with bounds check).

**Required deliverables:**

- (A): hardened SAFETY comment + proof obligation lint, as for any (A).
- (B): the inner `get_unchecked` must independently satisfy (B)'s deliverables — criterion bench showing the safe `[0]` lookup is over budget, `safe-only` feature flag, CI matrix entry. If the bench shows no measurable delta, the inner `get_unchecked` graduates to (C); rewrite to use safe indexing while keeping the outer (A) FFI.

The site is classified as (A) (its primary bucket), tracked in `audit/classification/site-NNNN.md` as `(A) + (B)-inner`, with both deliverables landing in the plan.

---

### Example H-2 — (A) signal handler with (C)-refactorable adjacent setup

```rust
extern "C" fn handler(sig: c_int) {
    // (A) — async-signal-safe code only inside this fn; the body MUST stay unsafe-aware
    // even though there's no `unsafe { }` block (the body is unsafe by being a signal handler).
    let _ = unsafe { libc::write(STDERR_FILENO, ERROR_MSG.as_ptr() as _, ERROR_MSG.len()) };
}

fn install_handler() {
    // (C)-refactorable — could use `signal-hook` crate, which would eliminate this unsafe.
    let mut act: libc::sigaction = unsafe { core::mem::zeroed() };
    act.sa_sigaction = handler as usize;
    unsafe { libc::sigaction(libc::SIGINT, &act, core::ptr::null_mut()); }
}
```

**Primary bucket of `install_handler`:** Looks like (C) — signal-hook exists.

**However:** `signal-hook` itself uses unsafe internally + allocates inside the handler context, which can deadlock or trigger UB if the handler interrupts an allocator critical section. See [R-009] in [REJECTED-PATTERNS.md](REJECTED-PATTERNS.md). The (C) recommendation is wrong; the site stays at (A) for the handler, (A) for the install (the sigaction call), because the alternative isn't actually sound for the project's constraints.

**Classification:** Both sites (A); the apparent (C) opportunity is rejected per [R-009].

This is a hybrid CASE that resolves to single-bucket via consulting [REJECTED-PATTERNS.md](REJECTED-PATTERNS.md). The classifier's write-up cites [R-009] as the reason the (C) candidate is rejected.

---

### Example H-3 — (B) SIMD path with (C)-refactorable fallback

```rust
#[cfg(target_feature = "avx2")]
pub fn parse_chunk(input: &[u8]) -> Result<Frame, ParseError> {
    // (B) — SIMD intrinsics; safe alternative is std::simd OR scalar.
    unsafe { parse_chunk_avx2(input) }
}

#[cfg(not(target_feature = "avx2"))]
pub fn parse_chunk(input: &[u8]) -> Result<Frame, ParseError> {
    // (C) refactor target — the scalar fallback can be rewritten without unsafe.
    unsafe { parse_chunk_scalar_unchecked(input) }
}
```

**Primary bucket per cfg-arm:** different.

- The AVX2 arm is (B): SIMD intrinsics, measurable perf gain.
- The scalar arm is (C): scalar parse with unsafe (probably hand-rolled bounds-check elision) can be rewritten with safe `slice::iter()` + `try_into()`.

**Classification:** Two sites, two buckets. The classifier emits `site-NNNN-avx2.md` (B) and `site-NNNN-scalar.md` (C). The deliverables match each.

This is NOT a hybrid; it's two distinct sites that happen to share a function name via cfg. The audit treats them independently.

---

## When the protocol applies

Hybrid (A)+(B) appears when:

- The site's primary justification is (A), but inside the same unsafe block there's a (B)-style optimization that has a safe alternative.
- Removing the inner optimization wouldn't make the site safe (the outer reason is irreducible) but it WOULD make the inner code simpler.

Hybrid (A)+(C) appears when:

- The site is (A) for its primary reason, but adjacent code (same module, same `impl` block) is (C)-refactorable.

In both cases, the protocol is: split the deliverables, but classify by the primary.

---

## When the protocol does NOT apply

The hybrid protocol is the rare case, not the common case. Most sites are cleanly single-bucket. Apply it only when:

1. The site genuinely has two separable unsafe characteristics.
2. Each characteristic has its own deliverable shape.
3. Splitting the deliverables actually helps the maintainer.

If the split feels forced, the site is single-bucket. Pick the primary bucket and move on.

---

## Audit-time discipline

When the classifier sees a hybrid candidate:

1. Write the per-site classification file as `<bucket-primary>` (e.g., `(A)`).
2. Add a `## Secondary characteristic` section naming the inner pattern and its bucket.
3. List the deliverables required for BOTH buckets.
4. In the Phase 5 plan, address each deliverable in its own paragraph (so the plan reader can apply them independently).

Example fragment from a hybrid (A)+(B) classification file:

```markdown
## Classification

**Primary bucket.** (A) STRICTLY_UNAVOIDABLE.

**Secondary characteristic.** Contains a `(B)` perf-only `get_unchecked` for the iov[0]
dereference.

## Justification (A)

...standard (A) justification per CLASSIFICATION-RUBRIC § A...

## Justification (B)-inner

...standard (B) justification for the inner perf-only code...

## Required deliverables

- (A): hardened SAFETY + clippy lint per CLASSIFICATION-RUBRIC § (A) acceptance.
- (B)-inner: criterion bench + safe-only feature implementation per § (B) acceptance.
  Graduation rule: if the bench shows no measurable delta, graduate to (C)
  inside the (A) wrapper — keep the outer (A), make the inner safe.
```

The Phase 6 adversarial reviewer reads both justifications independently.

---

## What this is NOT

- Not a license to classify every site as "(A) + something else" to defer hard decisions. The default is always single-bucket.
- Not a substitute for the bias-downward rule. If the inner code is (B) and graduating is plausible on measurement, do that.
- Not a way to inflate the deliverable count to make the audit look thorough.

The protocol exists for the rare case where the soundness argument is genuinely two-part. Use it precisely.

---

## Cross-references

- [CLASSIFICATION-RUBRIC.md](CLASSIFICATION-RUBRIC.md) — the primary classification rule (every site has exactly one bucket).
- [REJECTED-PATTERNS.md](REJECTED-PATTERNS.md) — refactor proposals that look like hybrid opportunities but were rejected upon analysis.
- [50-SEND-SYNC-IMPLS.md § reachable-perf](../patterns/50-SEND-SYNC-IMPLS.md) — the previous home of the hybrid-mention; this file is the formalized protocol.
- [POLISH-BAR.md](POLISH-BAR.md) — what "every deliverable present" actually means at audit-close.
