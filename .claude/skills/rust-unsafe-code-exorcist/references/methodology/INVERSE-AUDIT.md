# INVERSE-AUDIT.md — Fuzz-Guided From Public API

The forward audit starts from `unsafe { ... }` and asks "who calls this?" The inverse audit starts from `pub fn ...` and asks "what input would trigger UB through this?"

The two directions are complementary:
- **Forward** finds sites and classifies them. Comprehensive on the unsafe surface.
- **Inverse** finds bugs without knowing where the unsafe lives. Comprehensive on the public-API attack surface.

A site the forward audit missed AND inverse exercises is a finding. A site forward classified as (A) AND inverse can't break is a SOFT confirmation. Both directions strengthen the audit.

---

## When to invoke inverse audit

- **Pre-release-gate** — strongest verification before `cargo publish`.
- **High-stakes crate** — auth, crypto, sandbox, runtime — fuzzers earn their cost.
- **After a forward audit completes** — use the forward audit's pub-API inventory as the inverse audit's input.
- **Independently** — for projects where forward audit can't run (no nightly, embedded targets, etc.), inverse audit on a sibling-but-fuzzable target.

---

## The protocol

```
1. Enumerate the public API.
   - From rustdoc JSON; per-crate `pub` items.
   - Filter to fn-like items (pub fn, pub method on a pub type).

2. Generate fuzz targets.
   - One target per pub fn (or per cluster of related fns).
   - Use cargo-fuzz + the `arbitrary` crate for structured inputs.
   - Skip fns with un-fuzzable signatures (e.g., callback-taking).

3. Configure the fuzzers.
   - Bound input sizes (1KB - 1MB per call).
   - Provide a corpus of seed inputs (from existing tests + property-test outputs).
   - Set per-target time budget (60s in CI; 1 hour for nightly runs).

4. Run the fuzzers.
   - Track: panics, miri-detected UB, allocator-pressure spikes, async-cancellation leaks.
   - Any finding is a candidate for either:
     - A forward-audit gap (file a new bead), or
     - A wrong-classification (the forward audit said (A); inverse breaks the (A) claim).

5. Triage findings.
   - Each finding maps to a forward-audit site (via stack trace) OR is a new finding.
   - Cross-reference with audit/synthesis/soundness-surface.md.
   - File appropriate bead.

6. Continuous integration.
   - Add the fuzz targets to verify.sh.
   - Add them to CI's fuzz-smoke job.
   - Persist the corpus + crashing inputs as the project's regression suite.
```

---

## Fuzz target template

The `inverse-auditor` subagent generates per-pub-fn fuzz targets:

```rust
// fuzz/fuzz_targets/inverse_parse_jwt.rs
#![no_main]
use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;

#[derive(Debug, Arbitrary)]
struct JwtInput<'a> {
    token: &'a [u8],
    public_key: &'a [u8],
}

fuzz_target!(|input: JwtInput| {
    // Inverse audit: drive arbitrary input at the pub API.
    // Any UB / panic / hang here is a finding.
    let _ = std::panic::catch_unwind(|| {
        let _ = mycrate::parse_jwt(input.token, input.public_key);
    });
});
```

Key features:
- `arbitrary` for structured input (avoids un-parseable garbage that wastes fuzz time).
- `catch_unwind` so a panic doesn't kill the fuzzer; we record the panic + continue.
- Output discarded — we only care about whether the call SUCCEEDED, PANICKED, or PRODUCED UB.

---

## What counts as a finding

| Symptom | Interpretation | Action |
|---------|----------------|--------|
| Panic on input X | Documented as expected panic | OK (assuming the doc says so). |
| Panic on input X | Not documented | FINDING — file bead; either document the panic or fix the input handling. |
| Miri UB on input X | Real UB | FINDING — critical; the forward audit's site classification is suspect. |
| Hang / timeout on input X | DoS-ish | FINDING — at least file as performance-issue; check whether the function should reject early. |
| Allocator panic on input X | OOM via parser-allocation | FINDING — `arbitrary` produced a very-large input; check whether the function should reject. |

---

## Cost discipline

Fuzzing is expensive. Per [TRIANGULATION.md § cost discipline](TRIANGULATION.md) idea:

- Budget per audit: top-10 highest-risk pub fns get full-target fuzzing (1 hour each); next 20 get 60-second smoke.
- Cumulative project budget: ~10-20 fuzz-hours per release.
- Continuous mode: 60-second per target nightly; promote to longer when a finding surfaces.

---

## Cross-referencing with forward audit

When inverse finds a finding:

```bash
# Extract the file:line of the suspect site from the fuzz output's stack trace
suspect_site=$(echo "$fuzz_output" | grep -oE '[a-z_/.]+\.rs:[0-9]+' | head -1)

# Cross-reference with forward audit's inventory
jq --arg site "$suspect_site" '.[] | select(.file + ":" + (.line_start|tostring) == $site)' \
   <audit-dir>/unsafe-inventory.jsonl
```

If the suspect site IS in the forward inventory:
- The forward audit knew about it.
- The classification might be wrong (e.g., it's (A) but inverse can break it).
- Update the classification + file a re-audit bead.

If the suspect site is NOT in the forward inventory:
- The forward audit missed the site.
- File a new audit bead.
- Update the inverse-discovered-sites doc.

---

## Inverse-discovered findings doc

`<audit-dir>/audit/inverse-findings.md`:

```markdown
# Inverse Audit Findings

Generated by inverse-auditor on <date>.

## Total findings: <N>

### Finding #1 — parse_jwt panics on empty token
- Pub fn: `mycrate::parse_jwt`
- Fuzz target: fuzz/fuzz_targets/inverse_parse_jwt.rs
- Reproducer: `let _ = parse_jwt(&[], &[1, 2, 3]);` panics with `slice index out of bounds`
- Forward audit said: site-0142 (in parse_jwt) is (C) and refactored.
- Resolution: The (C) refactor didn't handle empty input. Updating audit/plans/site-0142.md.

### Finding #2 — read_config UB on truncated input
- Pub fn: `mycrate::read_config`
- Fuzz target: fuzz/fuzz_targets/inverse_read_config.rs
- Reproducer: <verbatim miri output>
- Forward audit said: site-0421 (in read_config) is (A) with claim "input length pre-validated".
- Resolution: The validation has a hole. Either fix the validation OR reclassify the site. Bead filed.

...
```

The doc grows with each fuzz session. It's the inverse-direction's record of work.

---

## When inverse audit can't run

- **No nightly toolchain.** `cargo-fuzz` requires nightly.
- **No `libfuzzer-sys`-compatible target** (e.g., wasm32, embedded). Use `arbitrary` + property tests instead.
- **No pub API** (binary crate with internal-only fns). The "inverse" is then "fuzz the main fn / CLI"; still useful.

Document the skip in `<audit-dir>/audit/inverse-skipped.md` with explanation.

---

## Acceptance signal

An inverse audit pass succeeds when:

1. Every pub fn (or pub fn cluster) has a fuzz target.
2. Each fuzz target runs the configured time budget without producing UB / unhandled panic.
3. Found findings are triaged (in-scope: update plan; out-of-scope: file pre-existing-ub).
4. The corpus is preserved (becomes regression-test scaffold).
5. CI runs the targets on every PR (60-second smoke).

Inverse + forward + harness is the soundness triad.
