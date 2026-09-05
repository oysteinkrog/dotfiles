# Troubleshooting

Common failures + diagnostic recipes.

---

## Miri

### "unsupported operation: clock_gettime" (or other host syscall)

Miri's default sandbox blocks host syscalls. Any project using `chrono::Utc::now`, `std::time::SystemTime::now`, `getrandom`, `std::fs::*`, etc. hits this immediately. The fix is to disable Miri's isolation **for the audit run** (this does not turn off Miri's UB detection — only its sandbox):

```bash
MIRIFLAGS="-Zmiri-disable-isolation" cargo +nightly miri test --lib
```

`scripts/run-miri-matrix.sh` defaults to having `-Zmiri-disable-isolation` on every axis (use `--strict-isolation` only when you specifically want to audit `no_std` sandbox conformance).

### "unsupported operation: can't call foreign function"

Miri doesn't run real FFI. Either:
- Add a Miri-only shim:
  ```rust
  #[cfg(miri)] fn call_c() -> i32 { 0 }
  #[cfg(not(miri))] extern "C" { fn call_c() -> i32; }
  ```
- Skip the FFI-heavy test under Miri:
  ```rust
  #[cfg(not(miri))]
  #[test]
  fn integration_via_ffi() { … }
  ```
- For libc functions like `getrandom`, set `MIRIFLAGS="-Zmiri-disable-isolation"` (or use the default matrix flag).

### "memory access failed: pointer must be in-bounds at offset N, but is outside bounds"

Either:
- The pointer arithmetic is genuinely UB (good catch — confirm in an experiment).
- The allocation was freed earlier; Miri caught a UAF.
- A `Vec::set_len` extended length past initialized region.

### Miri takes forever

- Drop to a single test: `cargo +nightly miri test test_suspect`
- Use `--lib` instead of `--all-targets` (skips slow integration tests)
- Increase isolation: `MIRIFLAGS="-Zmiri-disable-isolation"` (less spew, faster)
- Offload to `rch`: `rch exec -- env MIRIFLAGS="..." cargo +nightly miri test`

---

## ThreadSanitizer (TSan)

### "ThreadSanitizer: data race ... in libstd"

Likely a TSan false positive due to std atomic usage. Diagnose:
1. Confirm by running the same test under Miri tree-borrows. If Miri is clean and TSan flags std code, it's probably a false positive.
2. Suppress with `TSAN_OPTIONS="suppressions=tsan.supp"`:
   ```
   race:std::sync::atomic
   ```
3. If the race is in *your* code that uses an atomic correctly, double-check the `Ordering` you used. Relaxed atomics don't establish happens-before; if TSan flags one, you probably need `Acquire`/`Release`.

### TSan reports nothing but you expect a race

- Run with `--test-threads=1` (otherwise tests race each other, not your code)
- Increase iteration count in the test to surface rare schedules
- Move to loom for exhaustive search of a small model

### Build fails with "linker not found"

- Install: `sudo apt-get install lld` or `brew install llvm`
- Pin via `~/.cargo/config.toml`:
  ```toml
  [target.x86_64-unknown-linux-gnu]
  linker = "clang"
  rustflags = ["-C", "link-arg=-fuse-ld=lld"]
  ```

---

## Loom

### Loom test takes forever

- Reduce thread count to 2 or 3 (loom's exhaustive search is O(states^threads))
- Reduce loop counters inside the model
- Switch to shuttle for probabilistic schedule sampling

### "loom assertion failed" on a test that passes natively

This is the point of loom — it catches schedules native execution doesn't reach. Read the schedule trace; the failing schedule is exactly the bug.

### Loom complains about non-deterministic operations

- Don't use system time / system RNG / external state inside the loom model
- Use `loom::cell::Cell` for thread-local mutability
- Don't mix `std::sync` with `loom::sync` in the same test

---

## Sanitizer build errors

### "the option `Z` is only accepted on the nightly compiler"

You're running stable. Switch:
```bash
rustup default nightly
# or per-invocation:
cargo +nightly ...
```

### "could not find `std`"

For MSan / `-Z build-std`, ensure rust-src is installed:
```bash
rustup component add rust-src --toolchain nightly
```

### ASan + Rust panic = strange output

ASan + Rust's unwind interact awkwardly. Switch to abort-on-panic:
```bash
RUSTFLAGS="-Zsanitizer=address -C panic=abort" cargo +nightly test
```

---

## Fuzzing

### libFuzzer reports "WARNING: timeout"

Either:
- The fuzz target is too slow (parsing a multi-MB input). Cap input size: `fuzz_target!(|data: &[u8]| { if data.len() > 4096 { return; } … });`
- The target has an infinite loop on certain inputs. That's its own bug.

### Crash file isn't reproducible

- Run with the same seed: `cargo +nightly fuzz run target -- -seed=12345 path/to/crash`
- Make sure `RUST_BACKTRACE=1` is set
- Some crashes only repro under exact libfuzzer reorderings; export the crash to Miri:
  ```rust
  #[test]
  fn repro_crash_001() {
      let data = include_bytes!("../fuzz/artifacts/fuzz_parse/crash-abc123");
      parse(data);
  }
  ```
  Then `cargo +nightly miri test repro_crash_001`.

---

## cargo-geiger

### `error: Io NotFound: <path>/<unrelated-crate>/src/lib.rs`

cargo-geiger walks the dependency tree using cargo metadata. On machines that have *other* path-dependency Rust projects checked out elsewhere (or stale `Cargo.lock` entries referencing absent paths), geiger can resolve a transitive path-dep to a directory that does not exist and crash mid-scan. Observed on multi-project workstations.

**Fallback** — manual unsafe-in-deps inventory via `rg`:

```bash
# Build a list of every dependency source directory:
cargo metadata --format-version 1 --no-deps=false 2>/dev/null \
  | jq -r '.packages[] | select(.source != null) | .manifest_path | sub("/Cargo\\.toml$"; "")' \
  | sort -u > /tmp/dep-paths.txt

# Per-dep unsafe-line count (rough proxy):
while read -r p; do
    n=$(rg -c '\bunsafe\b' "$p" --type rust 2>/dev/null | wc -l)
    [ -n "$n" ] && [ "$n" -gt 0 ] && printf '%6d  %s\n' "$n" "$p"
done < /tmp/dep-paths.txt | sort -rn | head -50
```

This loses geiger's syntactic-vs-comment distinction but is robust to broken path-deps. Document the fallback in the audit's `phase3_raw/cargo_geiger_fallback.md`.

**Also acceptable:** skip the geiger pass entirely if the project is `#![forbid(unsafe_code)]` — geiger's job is to count unsafe-in-deps; for a forbid-unsafe crate the answer is "all of it is in the deps", which we already know from the dependency tree. Document the skip with rationale.

---

## Beads / `br` / `bv`

### `br dep cycles` reports a cycle

Read the cycle output; the offending edges are listed. Decide which edge is wrong (usually one of them is a *should-have-been-an-implies* not a *depends-on*). Remove it:
```bash
br dep remove "<child>" "<parent>"
```

Re-run `br dep cycles` until empty.

### `bv --robot-insights` returns nothing

You're probably in the wrong directory or `.beads/beads.jsonl` is empty. Run `br sync --flush-only` first.

### `br` commands fail with sync-branch errors

This is a Beads sync-branch configuration issue, not permission to create git worktrees. Create a dedicated sync branch:
```bash
git branch beads-sync main
git push -u origin beads-sync
br config set sync-branch beads-sync
```

---

## Agent Mail

### `FILE_RESERVATION_CONFLICT`

Another subagent is currently holding the reservation. Either:
- Wait and retry (TTL is usually 1h max)
- Force-release if you know the other agent died: `force_release_file_reservation(...)`
- Use a finer-grained reservation (e.g., `tool://miri/<config>` instead of `tool://miri`)

### `from_agent not registered`

Run `register_agent(project_key, agent_name, program="claude", model="opus-4-7")` first.

---

## Workspace / Compaction

### Resuming after compaction picks up the wrong phase

The orchestrator's resume protocol (see [ORCHESTRATION.md](ORCHESTRATION.md)) reads the highest `phase7_convergence_round_*.json` and the verdict counts in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`. If those are stale (e.g., a subagent crashed mid-write), the orchestrator may resume in the wrong phase.

Manual fix:
1. `ls -la <workspace>/phase*` and find the most-recently-modified phase file
2. Read its header to identify the round
3. Manually delete or move-aside (with permission!) any malformed half-written file
4. Tell the orchestrator: "Resume Phase X Round Y"

### `convergence-tracker.sh` reports `quiet: false` indefinitely

Causes:
- A new ast-grep pattern keeps surfacing the same shape across iterations
- A flaky Miri test produces intermittent CONFIRMED_UB / NO_EVIDENCE
- A new fuzz seed generates a fresh "finding" that's actually the same bug

Diagnose with `jq '.new_findings' phase7_convergence_round_*.json`; if the count plateaus around 1–2, you're in the consolidation case — see [CONVERGENCE.md §When To Manually Override](CONVERGENCE.md).

---

## `rch` offload

### `rch exec` hangs

- Check `rch status` — workers might be down
- The rch skill has its own troubleshooting; see `/rch`'s SKILL.md
- Fall back to local: prepend `RCH_DISABLE=1` and the command runs locally

### Output trapped on the remote worker

```bash
rch sync --pull   # pull worker artifacts back to local
```

---

## "It still finds new UB after Round 15"

Either:
1. The codebase genuinely has more UB than expected — keep going
2. The dynamic tools are picking up flaky races (TSan especially) — switch to loom for the suspect primitive
3. New fuzz seeds keep hitting the same root cause — consolidate per [CONVERGENCE.md §When To Manually Override](CONVERGENCE.md)
4. A Phase-2 sweeper is adding new findings on every iteration (e.g., its ast-grep pattern matches the same site twice). Audit the sweeper.

If you're stuck: surface the situation to the user, share the convergence CSV, and ask whether to declare convergence with a documented override.
