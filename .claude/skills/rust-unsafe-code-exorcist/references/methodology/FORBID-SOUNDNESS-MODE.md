# FORBID-SOUNDNESS-MODE.md — Mode Overlay for `#![forbid(unsafe_code)]` Projects

Some Rust projects already enforce zero internal unsafe via crate-level `#![forbid(unsafe_code)]` and have made that part of the project's contract. The standard audit kernel still applies, but the value shifts:

- **(A) / (B) / (C) classification is mostly trivial** — there's no internal unsafe to classify, so the audit's first 6 phases collapse to "verify the forbid is consistent."
- **The dependency surface becomes the entire audit** — every unsafe item the project transitively reaches is OUTSIDE the project's source, and the soundness contract lives in the dep wrappers.
- **CI gating shifts emphasis** — the audit's job is to make sure no future PR turns the forbid off in a sub-module.

This file is the protocol for the `forbid-soundness` overlay. It's a thin specialization of `dependency-soundness` mode with the forbid-consistency checks bolted on.

---

## When to use

Activate `forbid-soundness` mode when ANY of:

1. The project's top-level `lib.rs` / `main.rs` has `#![forbid(unsafe_code)]`.
2. The project's `Cargo.toml` advertises "100% safe Rust" / "no unsafe" in its description.
3. The project's CI explicitly checks `! grep -r "unsafe" src/`.
4. The user requests "audit my zero-unsafe Rust project."

Activation can be auto-detected by `scripts/detect-mode.sh` (added behavior — see below).

---

## What the overlay changes

### Phase 1 — Enumerate

Same as default mode, but ALSO:

- Run `ast-grep -p '#![forbid(unsafe_code)]'` and `#![allow(unsafe_code)]` across the source tree.
- Run `ast-grep -p '#![deny(unsafe_code)]'` (a softer cousin — track separately).
- Identify any module that overrides the crate-level forbid via inner attributes.

Output addition: `<audit-dir>/phase1/forbid-attribute-map.md` — every file's effective unsafe-policy.

### Phase 2 — Per-site write-up

Most projects in this mode have **zero** sites; Phase 2 produces no per-site write-ups. If sites DO exist (someone disabled the forbid in a module), each one is a high-priority audit target.

### Phase 3 — Synthesize

The synthesizer's invariants.md is mostly empty. The soundness-surface.md is the heart: **every** dep with `cargo +nightly geiger > 0` AND reachable from a `pub` API gets an entry.

### Phase 4 — Classify

For project-side sites (if any exist), apply the standard rubric.

For dep-side sites, the classification is per-dep, not per-site. Three buckets at the dep level:

| Bucket | Meaning |
|--------|---------|
| **dep-(A)** | Dep's unsafe is required for the dep's purpose (e.g., `libc`, `windows-sys`, `core-foundation`). The project inherits the dep's contract. |
| **dep-(B)** | Dep uses unsafe for perf reasons that may not apply to this project's usage. Investigate whether a safer alternative dep exists. |
| **dep-(C)** | Dep's unsafe could be eliminated by an upstream refactor. File an upstream issue (per `upstream-issue-filer.md`). |

### Phase 5 — Plan-Draft

For project-side: identical to default mode.

For dep-side:
- **dep-(A):** document the inherited contract in `audit/synthesis/inherited-contracts.md`. Add a `// SAFETY:` comment to every project-side wrapper of the dep API.
- **dep-(B):** evaluate a swap to a safer alternative. If swap is feasible, plan it (Cargo.toml diff + behavior-equivalence test). If not, document the rejection per `REJECTED-PATTERNS.md`.
- **dep-(C):** draft the upstream issue (PR if feasible) per `upstream-issue-filer.md`.

### Phase 6 — Adversarial reclassification

Per dep, attack the project's claim that the inherited contract is upheld. Look for:
- Public API paths that reach dep internals via a side channel.
- Caller-side proof obligations that aren't enforced.
- Allocator-identity assumptions the dep makes (e.g., dep expects `GlobalAlloc`; project uses `bumpalo`).

### Phase 7 — Fresh-eyes review of the FORBID consistency

The fresh-eyes pass focuses on:
1. **No `#![allow(unsafe_code)]` in modules** — if any exists, it's a soundness leak in a "no unsafe" project.
2. **No `unsafe` in build scripts** — `build.rs` doesn't inherit crate-level forbid; check separately.
3. **No `unsafe` in proc-macro emitted code** — `cargo expand` is the verifier; even forbid-marked crates can be subverted by their derive macros.
4. **CI enforces the forbid** — verify a CI step blocks `unsafe` in PRs.

### Phase 8 — Bead conversion

- One bead per dep-(B) swap candidate.
- One bead per dep-(C) upstream issue.
- One bead per `#![allow(unsafe_code)]` module that needs the allow justified or removed.
- The standard pre-existing-UB beads for any harness findings.

### Phase 9 — Verification harness

`verify.sh` for a forbid-soundness project includes:

```bash
# Standard tools (most run trivially clean because no project unsafe)
cargo +nightly miri test --workspace
cargo +nightly careful test --workspace
cargo +nightly geiger
# Expected: project's own count is 0 OR the audit lists the exact sites.

# Forbid-consistency check (the key check for this mode)
if grep -rn "allow(unsafe_code)" src/; then
  echo "WARN: forbid override found in src/"
fi
if ! grep -q "forbid(unsafe_code)" src/lib.rs 2>/dev/null && \
   ! grep -q "forbid(unsafe_code)" src/main.rs 2>/dev/null; then
  echo "FAIL: top-level forbid missing"
  exit 1
fi
```

### Phase 10 — Maintainer-empathy review

The reviewer's question for this mode is: "If I were a downstream user choosing this dep, would the audit's soundness posture make me comfortable depending on this for production?"

The answer should reference the inherited-contracts.md document.

---

## Detection heuristic

`scripts/detect-mode.sh` should recommend `forbid-soundness` when:

```bash
# At project root:
if grep -lqE '^[[:space:]]*#!\[forbid\(unsafe_code\)\]' src/lib.rs src/main.rs 2>/dev/null; then
  echo "Detected: #![forbid(unsafe_code)] — recommend forbid-soundness mode"
fi
```

(Manual override always wins.)

---

## Acceptance criteria

A `forbid-soundness` audit passes when:

| Criterion | How to verify |
|-----------|---------------|
| Top-level `#![forbid(unsafe_code)]` present | `grep -E '^#!\[forbid\(unsafe_code\)\]' src/{lib,main}.rs` |
| No `#![allow(unsafe_code)]` overrides in submodules | `! grep -rn 'allow(unsafe_code)' src/` (or each occurrence is documented + bead-filed) |
| Every dep with `cargo geiger > 0` has an entry in `inherited-contracts.md` | manual inspection |
| Every dep-(B) candidate has a swap evaluation or rejection rationale | `<audit-dir>/audit/plans/dep-NNN.md` |
| Every dep-(C) candidate has a drafted upstream issue | `<audit-dir>/audit/changelog-drafts/upstream-issues/dep-NNN.md` |
| CI enforces the forbid | `.github/workflows/` has a step that fails on `unsafe` in source |
| Build scripts (`build.rs`) audited separately | `<audit-dir>/audit/synthesis/build-script-soundness.md` |

---

## Cross-references

- [OPERATING-MODES.md](OPERATING-MODES.md) — overall mode catalog; `forbid-soundness` is a thin overlay on `dependency-soundness`.
- [DEP-SOUNDNESS-PROTOCOL.md](DEP-SOUNDNESS-PROTOCOL.md) — the parent protocol.
- [REJECTED-PATTERNS.md](REJECTED-PATTERNS.md) — record dep-swap rejections here.
- [subagents/upstream-issue-filer.md](../../subagents/upstream-issue-filer.md) — drafts upstream issues for dep-(C) cases.
