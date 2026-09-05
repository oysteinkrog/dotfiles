# 100-CRYPTOGRAPHY-AUDIT.md — Cryptography-Specific Soundness

Crypto crates have failure modes most projects don't worry about:

- **Constant-time.** Secret data must not influence branch / load / store timing.
- **Secret-zeroing.** Secret-bearing memory must be zeroed before Drop.
- **Side-channel.** Cache lines, branch prediction, micro-op layout can leak.
- **Canonical encoding.** Different encodings of the "same" value can produce different MACs/signatures.
- **Memory disclosure.** Returned errors must not contain pointer-sized info that an attacker could correlate.

The standard audit's bar is a floor; this bundle TIGHTENS it for crypto.

---

## Domain-specific operators

### ⊠ Constant-Time-Witness

**Trigger.** Any unsafe site OR safe site that handles secret material (private keys, plaintext, intermediate computation values).

**Question.** Is this operation constant-time? (No data-dependent branches; no data-dependent memory access patterns.)

**Failure modes.**
- `if secret == 0 { return Err(...) }` — branch on secret data.
- `array[secret_index]` — load address depends on secret.
- `match secret_value { ... }` — branches depend on secret.
- Early-return on first byte mismatch — timing leak.
- `Vec::push(secret_data)` — allocation pattern depends on secret length.

**Prompt module.**
> For this site: identify which inputs / values are SECRET. For each, trace whether their value affects (a) control flow, (b) memory addresses accessed, (c) instruction-cache behavior. If yes to any, the site is NOT constant-time. Use `subtle::ConstantTimeEq`, `subtle::Choice`, or hand-rolled CT logic to fix.

**Fix section.** This file § Constant-time patterns.

### ⌗ Secret-Zeroing-Check

**Trigger.** Any type carrying secret material (PrivateKey, Plaintext, IntermediateValue, etc.).

**Question.** Does the type's `Drop` impl zero the secret? Is the zeroing protected against compiler elimination?

**Failure modes.**
- No `Drop` impl; secret stays in freed memory.
- `Drop` writes zero with regular `*p = 0` — compiler may eliminate as dead code.
- `Drop` zeroes some fields but not others.
- `Drop` allocates a new buffer instead of zeroing in place.
- Copy types that get duplicated through stack frames; zeroing one doesn't zero copies.

**Prompt module.**
> Check the type's `Drop` impl. If absent, add one. If present, verify it uses `zeroize::Zeroize` (or equivalent `volatile_write`). Verify every field carrying secret data is zeroed. Add `#[derive(ZeroizeOnDrop)]` where applicable. For Copy types, mark as `!Copy` if they shouldn't be duplicated.

**Fix section.** This file § Secret-zeroing patterns.

### ⊳ Canonical-Encoding-Witness

**Trigger.** Any operation that hashes / MACs / signs data.

**Question.** Does the operation accept only the CANONICAL encoding of the value, or are multiple encodings possible?

**Failure modes.**
- Big-endian vs little-endian inconsistency.
- Trailing zeros allowed in some paths, rejected in others.
- Variant tag encoding inconsistent across versions.

**Prompt module.**
> For each value passed to a hashing function, document the canonical encoding rule. Verify the safe wrapper enforces it (e.g., explicit `to_be_bytes()` everywhere; reject inputs that don't match the canonical form). Cross-validate with the spec (e.g., RFC, paper, NIST documentation).

**Fix section.** This file § Canonical-encoding discipline.

---

## Pattern CR-1 — Constant-time comparison

```rust
// UNSAFE (branches on secret)
fn verify_mac(provided: &[u8], expected: &[u8]) -> bool {
    if provided.len() != expected.len() { return false; }
    for i in 0..provided.len() {
        if provided[i] != expected[i] { return false; }  // early return on mismatch
    }
    true
}

// SAFE (constant-time)
use subtle::ConstantTimeEq;
fn verify_mac(provided: &[u8], expected: &[u8]) -> bool {
    if provided.len() != expected.len() { return false; }   // length compare is OK
    provided.ct_eq(expected).into()
}
```

`subtle::ConstantTimeEq` is the canonical constant-time crate. Use it.

---

## Pattern CR-2 — Secret-zeroing

```rust
// UNSAFE (no zeroing; secret in freed memory after drop)
struct PrivateKey {
    bytes: [u8; 32],
}

// SAFE
use zeroize::{Zeroize, ZeroizeOnDrop};

#[derive(Zeroize, ZeroizeOnDrop)]
struct PrivateKey {
    bytes: [u8; 32],
}

// Or for fine-grained control:
impl Drop for PrivateKey {
    fn drop(&mut self) {
        self.bytes.zeroize();   // volatile-write zero, not eliminable by compiler
    }
}
```

The `zeroize` crate uses `volatile_write` internally so the compiler can't eliminate the zeroing as dead code.

---

## Pattern CR-3 — Constant-time choice

```rust
// UNSAFE (branch on secret)
fn select_branch(secret: u8, a: u32, b: u32) -> u32 {
    if secret == 0 { a } else { b }
}

// SAFE (constant-time)
use subtle::{Choice, ConditionallySelectable};
fn select_branch(secret: u8, a: u32, b: u32) -> u32 {
    let choice: Choice = (secret != 0).into();
    u32::conditional_select(&a, &b, choice)
}
```

`subtle::Choice` + `ConditionallySelectable` is the canonical bit-trick for constant-time selection.

---

## Pattern CR-4 — Canonical encoding for hashing

```rust
// UNSAFE (multiple encodings accepted)
fn hash_message(msg: &Message) -> [u8; 32] {
    let mut hasher = Hasher::new();
    hasher.update(&msg.timestamp.to_be_bytes());   // OK: big-endian
    hasher.update(msg.recipient.as_bytes());        // FRAGILE: encoding of String?
    hasher.update(&msg.amount.to_le_bytes());       // INCONSISTENT: little-endian!
    hasher.finalize()
}

// SAFE (canonical encoding enforced)
fn hash_message(msg: &Message) -> [u8; 32] {
    let canonical = msg.to_canonical_bytes();   // single deterministic encoding
    let mut hasher = Hasher::new();
    hasher.update(&canonical);
    hasher.finalize()
}

impl Message {
    fn to_canonical_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        buf.extend(self.timestamp.to_be_bytes());
        buf.extend(self.recipient.as_bytes());       // String UTF-8 is canonical
        buf.extend(self.amount.to_be_bytes());       // big-endian, consistently
        buf
    }
}
```

The canonical encoding is enforced in ONE place; the hasher only ever sees the canonical bytes.

---

## Pattern CR-5 — Side-channel-aware memory layout

```rust
// SUBTLE (data-dependent memory access)
fn lookup(secret_idx: usize, table: &[u32; 256]) -> u32 {
    table[secret_idx]   // load address depends on secret; cache-line leak
}

// MITIGATED (constant-time table lookup)
fn lookup(secret_idx: usize, table: &[u32; 256]) -> u32 {
    use subtle::ConstantTimeEq;
    let mut result = 0u32;
    for i in 0..256 {
        let mask = u32::from((i as u8).ct_eq(&(secret_idx as u8)).unwrap_u8());
        result |= table[i] * mask;
    }
    result
}
```

The mitigated version touches every entry; cache leak resolved (but slower; assess vs your threat model).

---

## Audit checklist for crypto crates

For each unsafe site:

- [ ] Identify secret data flowing through this site.
- [ ] Verify the operation is constant-time (or document the side-channel acceptance).
- [ ] Verify secret-bearing types have `Drop` + `Zeroize`.
- [ ] Verify canonical encoding is enforced.
- [ ] Run `dudect` or `ct-verif` for empirical constant-time validation (if applicable).
- [ ] Run miri with `-Zmiri-tag-gc=0` to detect potential lifetime leaks.

For each `pub fn` in the crypto API:

- [ ] Document the threat model (what attacker can observe).
- [ ] Document the constant-time guarantee (yes / no / partial).
- [ ] Add a `# Side channels` section to the rustdoc.

---

## Anti-patterns specific to crypto

| ✗ | Why | Fix |
|---|-----|-----|
| Using `==` to compare secrets | Early-return on mismatch leaks length / position | `subtle::ConstantTimeEq` |
| Using `if secret > threshold` | Branch on secret | `subtle::Choice` + arithmetic |
| Returning `Result<T, Error>` where Error carries data about why | Error variant leaks which check failed | Single `Error::Invalid` variant |
| `[u8; N]` for keys without Drop | Secret in freed memory | `#[derive(ZeroizeOnDrop)]` |
| `Vec<u8>` for keys | Heap-allocated; can be reallocated leaving copies | Fixed-size `[u8; N]` with Drop |
| Allowing trailing zeros / multiple encodings | Hash domain not canonical | Enforce canonical encoding upstream |

---

## Exemplar precedents

- `[E-100-1]` — `dalek-cryptography` family of crates: constant-time scalar arithmetic via `subtle`; key-zeroing via `zeroize`. Reference implementation for crypto Rust.
- `[E-100-2]` — `ring` crate: heavy use of `assert!(buf.len() == X)` to constrain inputs to canonical sizes. Strict input discipline.
- `[E-100-3]` — `argon2` reference implementation: documented timing characteristics + bounded by `dudect` empirical checks.

---

## Acceptance signal

A crypto-audited site passes when:

1. Operator ⊠ Constant-Time-Witness has been applied; result documented.
2. Operator ⌗ Secret-Zeroing-Check applied; result documented.
3. Operator ⊳ Canonical-Encoding-Witness applied (if relevant); result documented.
4. The crate's docs include a "Side channels" section per pub-API documented threat model.
5. `cargo test` exercises constant-time properties (or `dudect` is configured + run).
6. miri + standard harness pass per usual.
