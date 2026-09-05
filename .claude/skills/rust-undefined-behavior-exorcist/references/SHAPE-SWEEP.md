# Shape Sweep — Same-Shape Multi-Site Heuristic

When a UB pattern is found at one site, the user's recurring practice is to **immediately scan for the same shape across the codebase** and fix all sites in the same commit. This is operator `≣ SHAPE-SWEEP`.

Anchor: cass Q-801 — float-modulo bug appeared in *two* code paths (VDBE `engine.rs::sql_rem` and MVCC `index_regen.rs::numeric_rem`) and the user fixed both in the same fresh-eyes pass.

---

## When to invoke shape-sweep

After every CONFIRMED_UB finding, before designing the remediation, ask: **what's the shape of this bug, and where else does that shape live?**

Examples of shapes:
- Float `%` where integer `%` was intended → grep for `%` on float types
- `as_bytes()[i]` indexing → grep for `as_bytes()` followed by `[`
- `Arc::from_raw` without paired `into_raw` → grep for `from_raw`, audit each
- `Box::from_raw` on libc-allocated pointer → grep for `Box::from_raw`, trace origin
- `mem::zeroed::<T>()` for non-zero-valid T → ast-grep for the pattern with type-arg inspection
- `Drop` impls that may panic → grep for `unwrap`/`expect`/`?` inside `impl Drop`
- `unsafe impl Send` without SAFETY comment → ast-grep + the `data_races` syn-walker
- `as_ptr() as *mut _` const-stripping cast → ast-grep `const-mutation-cast.yml`

---

## The shape-sweep workflow

```
1. Confirm: this is real UB at file:line X (operator ◐ REPRO done)
2. Identify the shape:
     - What's the syntactic pattern?
     - What's the semantic intent that went wrong?
3. Sweep:
     - rg / ast-grep / semgrep across the full workspace
     - Filter to sites where the same intent applies
4. Validate each sweep hit:
     - Does it actually have the same bug?
     - Is it intentionally different (record as known)?
5. Bundle the remediation:
     - Phase 8 designs the rewrite ONCE for the shape
     - Phase 9 produces ONE bead with N sub-beads (one per site)
6. Commit:
     - Same-shape fixes ship together
     - Test exercises each site independently
```

---

## Tools per shape category

| Shape | Tool |
|---|---|
| Lexical (`as_bytes()[i]`) | `rg -n 'as_bytes\(\)\['` |
| Syntactic (any cast → *mut) | `ast-grep -p '$EXPR as *const $T as *mut $T'` |
| Type-level (`mem::zeroed::<T>()` for non-zero-valid T) | syn-walker `validity.rs` |
| Dataflow (raw ptr escapes scope) | syn-walker `escape.rs` or semgrep cross-fn |
| Behavioral (panic from Drop) | grep + manual audit; can't fully automate |
| Semantic (float-mod-instead-of-int) | hard to grep; rely on fresh-eyes to spot, then sweep |

---

## Why bundle the same-shape fixes?

Three reasons mined from the corpus:

1. **Atomicity of intent.** If site A is fixed but site B isn't, a reviewer rightfully asks "why these and not those?". The same-shape commit answers preemptively.
2. **Cognitive economy.** Reviewers learn one pattern + see it applied N times. Faster than learning N micro-fixes.
3. **Regression-proofing.** A test that asserts "no `as_bytes()[i]` pattern" in `src/` catches all N sites at once. One test, N protections.

---

## When NOT to bundle

- The sites have semantically different intent that just happens to share syntactic shape (e.g., float `%` in physics calculations is fine; only the SQL VALUES path was wrong)
- The fix differs per site (each requires different remediation candidates)
- One site is in a stable API and another is unreleased — release-train timing forces them apart

Document the reason in `phase8_remediation_plan.md` if you split a shape across multiple review units, branches, or PRs.

---

## Tooling: `scripts/shape-sweep.sh` (proposed)

```bash
#!/usr/bin/env bash
# shape-sweep.sh — given a finding, find all sites with the same shape.
#
# Usage: shape-sweep.sh <source-dir> <pattern> [--tool=rg|ast-grep|semgrep]
set -euo pipefail

SOURCE="$1"
PATTERN="$2"
TOOL="${3:---tool=ast-grep}"

case "${TOOL#--tool=}" in
  rg)        rg -n "$PATTERN" "$SOURCE" ;;
  ast-grep)  ast-grep run -l Rust -p "$PATTERN" "$SOURCE" ;;
  semgrep)   semgrep --config="$PATTERN" "$SOURCE" ;;
esac
```

---

## Composition with the bead ladder

The 5-step bead ladder (see [UB-BEAD-LADDER.md](UB-BEAD-LADDER.md)) is the natural execution form for shape-sweep:

```
br-201 [audit]       Document the shape: <pattern>; sweep results (N sites)
  br-202 [core]      Fix site A (the originally-found site)
  br-203 [ancillary] Fix sites B, C, D (the sweep-discovered sites)
  br-204 [test]      Regression test asserting no <pattern> remains in src/
  br-205 [e2e]       End-to-end test exercising at least one fixed path
```

`bv --robot-diagnose` should show this as a connected sub-graph with no cycles.

---

## Cross-references

- Operator card: [OPERATOR-LIBRARY.md §♦ COUNTER](OPERATOR-LIBRARY.md) (related — but COUNTER finds the *one* violator; SHAPE-SWEEP finds *all* same-shape sites)
- [UB-BEAD-LADDER.md](UB-BEAD-LADDER.md) — execution form
- cass Q-801, Q-802 — verbatim source
