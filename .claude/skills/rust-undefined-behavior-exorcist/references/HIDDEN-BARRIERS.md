# Hidden Barriers — "Looked Benign, Was A Soundness Bug" Pattern Catalog

A bestiary of bugs that *look* like style/perf nits but are actually soundness violations. Mined from cass Q-102, Q-103, Q-401, Q-402.

Use this catalog in Phase 2 review when an audit reaches "everything looks fine". Often something in the codebase matches a hidden-barrier pattern.

---

## HB-1: Noop synchronization primitive

**Cass anchor:** Q-102. frankensqlite's `shm_barrier()` was implemented as `// no-op` because earlier in-process locks didn't need it. After the move to `MAP_SHARED`, the noop became a cross-process visibility bug.

**Pattern:**
```rust
pub fn shm_barrier(&self) {
    // no-op
}
```

**Why it's hidden:** The function has the right signature and the right name. Code reviewers see the call site and assume the implementation is fine.

**How to find:**
```bash
rg -n 'fn.*barrier|fn.*sync|fn.*fence' --type rust src/
# For each: read the body. Is the body actually empty / noop?
```

**Remediation:** Replace with `std::sync::atomic::fence(SeqCst)` or stronger. Add a regression test that explicitly relies on the fence (e.g., cross-process write→fence→read).

---

## HB-2: AWK END-block overrides pattern-block exit

**Cass anchor:** Q-102 ("AWK END block override"). A guard script's `exit 0` in a pattern block was overridden by `exit 1` in the END block, making the guard never fire.

**Pattern:**
```awk
in_section && /command/ { exit 0 }
END { exit 1 }
```

**Why it's hidden:** AWK's END always runs last. The `exit 0` from the pattern block sets the exit code, but the END block re-overrides.

**Remediation:**
```awk
BEGIN { found = 0 }
in_section && /command/ { found = 1 }
END { exit (found ? 0 : 1) }
```

This isn't Rust UB *directly*, but it's in the catalog because the *consequence* of the AWK bug is that an audit-guard never fires — soundness gates silently disabled.

**How to find:** Any AWK/script-driven UB-gate in CI; manually trace what the gate's exit code actually depends on.

---

## HB-3: Missing `cx: &Cx` on a sync-syscall function

**Cass anchor:** Q-103. SOCKS5 connector lacked `cx` parameter; was uncancellable. Fixed by adding `cx: &Cx` to all 12 public HttpClient methods + 5 `check_cx(cx)?` calls.

**Pattern:**
```rust
pub fn connect_via_socks5(&self, addr: SocketAddr) -> io::Result<Conn> {
    let proxy_conn = TcpStream::connect(self.proxy)?;
    perform_socks5_handshake(&proxy_conn, addr)?;
    Ok(Conn::new(proxy_conn))
}
```

**Why it's hidden:** No `cx` parameter means no cancellation. If the caller's `Cx` is cancelled, this function continues blocking until the syscall returns naturally — minutes or hours.

**Why it's "UB" in this codebase's vocabulary:** asupersync treats concurrency soundness as a memory-safety-grade obligation. A leaked-task / uncancellable-connection is the asupersync equivalent of a memory leak.

**Remediation:**
```rust
pub fn connect_via_socks5(&self, cx: &Cx, addr: SocketAddr) -> Result<Conn, ClientError> {
    check_cx(cx)?;                                    // pre-DNS
    let proxy_conn = TcpStream::connect(self.proxy)?;
    check_cx(cx)?;                                    // pre-handshake
    perform_socks5_handshake(&proxy_conn, addr, cx)?;
    check_cx(cx)?;                                    // post-handshake
    Ok(Conn::new(proxy_conn))
}
```

**How to find:** Every `pub fn` that performs network/file/process syscalls; audit whether `cx` is in the parameter list. See [CANCEL-CORRECTNESS.md](CANCEL-CORRECTNESS.md).

---

## HB-4: Float `%` where integer `%` was intended (same shape in 2 sites)

**Cass anchor:** Q-402. Both frankensqlite VDBE `sql_rem` and MVCC `index_regen::numeric_rem` used floating-point `%` for what should have been integer modulo (SQL `REM` operator).

**Pattern:**
```rust
let fa = dividend.to_float();
let fb = divisor.to_float();
if fb == 0.0 { return Null; }
let result = fa % fb;
if result.is_nan() { Null } else { Float(result) }
```

**Why it's hidden:** SQL `%` is defined as integer modulo. Float modulo silently rounds. The test suite passes because most cases divide cleanly.

**Why it's "UB-adjacent":** Not strictly Rust UB, but produces silent corruption (wrong query results, breaking downstream invariants). In the user's vocabulary, this is "the wrong answer at scale" which is soundness-grade.

**Remediation:**
```rust
let ia = dividend.to_integer();
let ib = divisor.to_integer();
if ib == 0 { return Null; }
let result = match ia.checked_rem(ib) {
    Some(r) => r,
    None => 0, // i64::MIN % -1 = 0, documented edge case
};
SqliteValue::Float(result as f64)
```

**How to find:** Domain-specific. For SQL: any operator that conceptually returns an integer (`%`, `&`, `|`, `^`) implemented via float. Use `cargo expand` + grep, or fresh-eyes review.

**Same-shape sweep:** When found in one site, IMMEDIATELY scan the codebase for the same pattern. See [SHAPE-SWEEP.md](SHAPE-SWEEP.md).

---

## HB-5: Unchecked truncating cast on FFI-derived value

**Cass anchor:** frankenfs commit `35610ffd`. Bare `as u16` / `as u32` casts on values from ext4 disk format, where the source could exceed the target type's range.

**Pattern:**
```rust
let extent_len: u16 = raw_extent.length as u16;
```

**Why it's hidden:** The compiler accepts it. The test suite passes for small files. Production hits a 64-MB file and the truncation produces a wrong length, silently corrupting the file system layout.

**Remediation:**
```rust
pub fn clamp_to_u16(v: usize) -> u16 {
    v.try_into().unwrap_or(u16::MAX)
}

let extent_len: u16 = clamp_to_u16(raw_extent.length);
```

Or, when the truncation is genuinely fatal, return `Err(...)` instead of silently clamping.

**How to find:** `rg ' as u(8|16|32)' --type rust` and audit each. Clippy `cast_possible_truncation` (off by default; turn on for soundness-critical code).

---

## HB-6: Sentinel value matches a valid value

**Pattern:**
```rust
const SENTINEL: u32 = 0xFFFF_FFFF;
fn find(map: &HashMap<u32, &str>, key: u32) -> &str {
    map.get(&key).copied().unwrap_or(SENTINEL_STR)
}
```

**Why it's hidden:** Works for 99.999% of inputs. If the key happens to be `0xFFFF_FFFF`, lookup succeeds with a real value, but downstream code treats it as the sentinel.

**Remediation:** Use `Option<T>` instead of in-band sentinel values; or pick a sentinel outside the input domain (e.g., signed where the data is unsigned).

**How to find:** Grep for `MAX`, `0xFF*`, `!0`, `-1` used as default; trace whether each is exclusive of the data domain.

---

## HB-7: Default-derived `Hash` on a manually-implemented `Eq`

See exemplar Case Study 3 in [CASE-STUDIES.md](CASE-STUDIES.md#case-study-3-beads_rust-hasheq-inconsistency-correctness-invariant).

**Pattern:**
```rust
#[derive(Hash)]
struct BeadId { prefix: String, id: u64 }

impl PartialEq for BeadId {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id  // ignores prefix!
    }
}
```

**Why it's hidden:** Compiles fine. Most tests pass because `prefix` is usually consistent. Production hits two beads with same `id` but different `prefix` → `HashMap` can miss a logically equal key. This is a correctness bug by itself, not UB unless unsafe code relies on that lookup invariant.

**Remediation:** Derive both `Hash`, `Eq`, `PartialEq` from the same fields. Or use a newtype wrapper.

**How to find:** Clippy `derive_hash_xor_eq` (catches this exactly). Also the syn-walker that checks for mismatched derives.

---

## HB-8: `Drop` order issue between containing type and contained resource

**Pattern:**
```rust
struct Backing {
    fd: RawFd,
    mmap_ptr: *mut c_void,
    mmap_len: usize,
}

impl Drop for Backing {
    fn drop(&mut self) {
        unsafe {
            libc::close(self.fd);                    // BUG: close before munmap
            libc::munmap(self.mmap_ptr, self.mmap_len);
        }
    }
}
```

**Why it's hidden:** Compiles fine. POSIX mostly tolerates close-before-munmap (munmap doesn't strictly need the fd). Some platforms reuse the fd immediately; if the second mmap happens during the window, you've leaked or corrupted.

**Remediation:** munmap before close:
```rust
unsafe {
    libc::munmap(self.mmap_ptr, self.mmap_len);
    libc::close(self.fd);
}
```

Or use `OwnedFd` + `MmapBacking` as separate types with documented Drop order.

---

## HB-9: Atomic ordering downgrade between init and access

**Pattern:**
```rust
// Initialization (correct, Release):
state.store(Ready, Ordering::Release);

// Later access (downgraded, Relaxed):
let s = state.load(Ordering::Relaxed);
if s == Ready { /* use data */ }
```

**Why it's hidden:** Compiles fine. On x86 it usually works because x86 has strong ordering. On AArch64 it fails non-deterministically.

**Remediation:** Acquire matched to Release:
```rust
let s = state.load(Ordering::Acquire);
```

**How to find:** ast-grep `atomic-relaxed-load-store.yml`. Plus careful audit of every `Relaxed` use case — is the producer using `Release`? Are you reading data that was written before the producer's `Release`?

---

## HB-10: Implicit-conversion-via-`From` that's lossy

**Pattern:**
```rust
impl From<HighPrecision> for LowPrecision {
    fn from(h: HighPrecision) -> Self {
        // Lossy conversion; silently rounds
        LowPrecision { val: h.val as f32 }
    }
}

// Caller:
fn make_low(h: HighPrecision) -> LowPrecision {
    h.into()  // Looks innocent
}
```

**Why it's hidden:** `From`/`Into` are usually assumed lossless. The `.into()` reads like an identity transform.

**Remediation:** Don't impl `From` for lossy conversions. Use `TryFrom` or a custom method (`h.lossy_to_low()`).

**How to find:** Grep `impl From<.*> for` and audit each for losslessness.

---

## Using this catalog

In Phase 2, the static-bucket-sweeper for the relevant bucket should grep for each HB pattern relevant to the project's archetype:

| Project archetype | Relevant HB patterns |
|---|---|
| P7 FFI | HB-1, HB-2, HB-5, HB-8 |
| P6 Async runtime | HB-3, HB-9 |
| P10 Database / storage | HB-1, HB-4, HB-8 |
| P1 Library | HB-6, HB-7, HB-10 |

For each match, file as `F-NNN` in the appropriate bucket's findings file with severity `LIKELY-UB` and a draft experiment.

---

## Cross-references

- cass Q-102, Q-103, Q-401, Q-402 — verbatim sources
- [INVARIANT-CATALOG.md](INVARIANT-CATALOG.md) — the invariants that get violated
- [SHAPE-SWEEP.md](SHAPE-SWEEP.md) — same-shape sweep heuristic
- [FALSE-POSITIVES.md](FALSE-POSITIVES.md) — the complement (true-positives that look like false-positives)
