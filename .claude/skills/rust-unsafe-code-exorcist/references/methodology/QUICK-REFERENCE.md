# QUICK-REFERENCE.md — Cheat Sheet

One-page reference. Bookmark this.

---

## The three buckets

| Bucket | Means | Required artifact | Decision rule |
|--------|-------|-------------------|---------------|
| (A) STRICTLY_UNAVOIDABLE | No safe formulation exists | Falsifiable justification (3 failed alternatives + steel-man + rebuttal) + hardened SAFETY comment + clippy lint | Cite Rust Reference / nomicon / RFC |
| (B) PERF_ONLY | Safe exists but slower; measurable + over budget | criterion + hyperfine + flamegraph (all three) + `safe-only` Cargo feature + CI matrix entry | Per-target measurement required; bias graduate to (C) if no measurable regression |
| (C) REFACTORABLE | Safe equivalent provable | Full safe code + property-based equivalence test + miri-clean + behavior on failure paths matches | proptest covers ≥10K cases; failure-mode parity required |

Bias: when in doubt, default DOWN — (A)→(B), (B)→(C).

---

## The phase loop

| Phase | Owner | When | Output |
|-------|-------|------|--------|
| 0 — Scope decision | main | once | phase0_scope_decision.md |
| 0.5 — Cass + exemplar mining | cass-miner, exemplar-miner | conditional | phase0_*.md |
| 1 — Enumerate | enumerator/crate | parallel | unsafe-inventory.jsonl |
| 2 — Site write-ups | site-analyzer/crate (same as 1) | parallel | audit/sites/ |
| 3 — Synthesize | synthesizer | once | audit/synthesis/ |
| 4 — Classify | classifier/pass | iterative until quiet | audit/classification/ |
| 5 — Plan-draft | refactor-planner/cluster | parallel | audit/plans/ |
| 5 — Equivalence-prove | equivalence-prover/(C) | parallel | audit/tests/ |
| 6 — Adversarial | adversarial-reclassifier/pass | iterative until quiet | reclassifications |
| 7 — Fresh-eyes | fresh-eyes-reviewer/round | iterative until clean ×2 | audit/phase7/ |
| 7 — Harness run | (sequenced) | once | verification-log.md |
| 8 — Bead conversion | bead-converter | once | .beads/ |
| 9 — Harness build | harness-builder | once | verify.sh + ci-matrix.yml |
| 10 — Maintainer review | maintainer-empathy-reviewer | once | REVIEWER_RESPONSES.md |

---

## The 24 operators

| Glyph | Name | Triggers on |
|-------|------|-------------|
| ⊙ | Invariant-Locator | every unsafe site |
| ⊕ | Reachability-From-Safe | sites in pub call graph |
| ⊗ | Falsifiable-Justification | any (A) classification |
| ⌖ | Macro-X-Ray | derive-heavy crates |
| ⏱ | Profile-Or-It-Didn't-Happen | any (B) classification |
| 🔒 | Panic-In-Drop-Trace | resource-owning types |
| 🔁 | Async-Cancellation-Trace | async-reachable sites |
| ⚖ | Send-Sync-Audit | `unsafe impl Send/Sync` |
| 🪟 | FFI-Boundary-Contract | extern "C" / libc |
| 🗄 | Init-Order-Discipline | MaybeUninit::assume_init |
| ⊞ | Loom-Reachable-Interleaving | concurrent unsafe |
| 🧪 | Equivalence-Witness | (C) classifications |
| 🔐 | Soundness-Surface-Marker | Phase 3 synthesis |
| 📐 | Allocator-Identity | (C) rewrites touching allocations |
| 🪞 | Bidirectional-Geiger | before+after refactor |
| ⚑ | Pre-Existing-UB-Isolator | every harness finding |
| ⤴ | Drop-Glue-Sanity | every (C) rewrite |
| ⊟ | Strict-Provenance-Witness | pointer-int casts |
| ⊠ | Stacked-vs-Tree-Borrows | (C) rewrites |
| ⋈ | Kani-Reach | high-stakes (C) sites |
| ✺ | Dep-Soundness-Reach | deps with geiger > 0 |
| ⌗ | API-Stability-Audit | (C) plans touching pub items |
| ✦ | Ordering-Witness | atomics with Ordering |
| ⊰ | Drop-Order-Trace | multi-resource (C) rewrites |

Full cards: [OPERATORS.md](OPERATORS.md).

---

## The 7 base modes

| Mode | When | Project-repo touch? |
|------|------|--------------------|
| `audit-only` | Default | none |
| `audit-and-refactor` | Land approved refactors in the active checkout; PRs optional via ordinary branches | yes (Phase 8.5) |
| `harden-incident` | CVE / miri finding / production crash | yes (incident scope) |
| `dependency-soundness` | Heavy deps with unsafe | yes (wrap/replace/upstream) |
| `verify-only` | Build CI harness from existing audit | yes (CI wiring) |
| `pre-release-soundness-gate` | Before `cargo publish` | yes (SAFETY hardening) |
| `dual-feature-migration` | Add `safe-only` feature flag | yes (feature impl) |

Plus domain overlays: `cryptography-audit`, `tagged-pointer-migration`, more in [DOMAIN-MODES.md](DOMAIN-MODES.md).

---

## Key scripts (run these)

| Script | What it does |
|--------|--------------|
| `scripts/check-skills.sh <audit-dir>` | Inventory referenced skills + jsm state |
| `scripts/install-toolchain.sh --check <audit-dir>` | Audit toolchain; propose install commands |
| `scripts/clone-and-bootstrap.sh <git-url> [--ref <ref> --subdir <path> --shallow --clone-root <dir>]` | Clone a repo from URL + bootstrap audit dir + run preflight checks |
| `scripts/self-test.sh [--quick]` | Meta-pass: validate + syntax + link-resolution + orphan-check + slop-scan on the SKILL itself |
| `scripts/detect-mode.sh <project>` | Heuristic mode recommendation |
| `scripts/enumerate-unsafe.sh <project> <audit-dir>` | Phase 1 enumeration |
| `scripts/generate-inventory.mjs <audit-dir>` | Normalize per-crate output |
| `scripts/compute-risk-score.mjs <audit-dir>` | BLAST × LIKELIHOOD × DISCOVERABILITY per site |
| `scripts/check-polish-bar.sh <audit-dir>` | Phase 5 gate; verifies required dimensions |
| `scripts/verify.sh <audit-dir>` | Composite harness (miri + careful + loom + fuzz + mutants + geiger + tests) |
| `scripts/cron-drift-check.sh <audit-dir> <project>` | Continuous-mode nightly check |
| `scripts/diff-audit-vs-baseline.sh <A> <B> <delta>` | Differential audit |
| `scripts/git-history-soundness-mine.sh <project> <audit-dir>` | Soundness archeology |
| `scripts/generate-bead-graph.mjs <audit-dir>` | Convert plans → bead create commands |
| `scripts/generate-soundness-changelog.sh <audit-dir> <project>` | Append to SOUNDNESS-LOG.md |
| `scripts/validate-corpus.py` | Verify [E-NNN] catalog integrity |
| `scripts/validate-operators.py` | Verify operator cards have required fields |

---

## Common acceptance criteria (per bead)

```bash
# Functional
cargo test -p <crate> --test equivalence_site_NNNN

# Soundness
cargo +nightly miri test -p <crate> --test equivalence_site_NNNN
cargo +nightly careful test -p <crate>

# Performance (if applicable)
cargo bench --bench <bench>

# Geiger delta
cargo +nightly geiger -p <crate>
# expected: count decreased by N

# Safe-only build (if (B) site)
cargo test --features safe-only --no-default-features -p <crate>

# Clippy lint (if (A) site)
cargo clippy -p <crate>
```

---

## Common Cargo.toml additions

```toml
[features]
default = []
safe-only = []              # for (B) → safe-only feature
loom_concurrency_tests = []

[target.'cfg(loom)'.dev-dependencies]
loom = "0.7"

[dev-dependencies]
proptest = "1"

[profile.release]
panic = "abort"             # mandatory for FFI-heavy crates
```

---

## Key files in the audit dir (where to look)

| Looking for | Read |
|-------------|------|
| The tally | `AUDIT_SUMMARY.md` |
| Maintainer review | `REVIEWER_RESPONSES.md` |
| The site list | `unsafe-inventory.jsonl` |
| Where unsafe meets pub | `audit/synthesis/soundness-surface.md` |
| What to refactor first | `audit/synthesis/risk-summary.md` |
| What needs hardening | `audit/synthesis/refactor-clusters.md` |
| What's still UB but out of scope | `audit/synthesis/pre-existing-ub.md` |
| Per-site analysis | `audit/sites/<crate>/<file>__<line>.md` |
| Per-site classification | `audit/classification/site-NNNN.md` |
| Per-site plan | `audit/plans/site-NNNN.md` |
| Beads | `br ready --json` (in audit dir) |
| Verification harness | `verify.sh` |
| CI matrix template | `ci-matrix.yml` |
| Cross-crate contracts | `audit/synthesis/cross-crate-contracts.md` |
| Drift events | `drift/<date>/summary.md` |
| Project history mining | `audit/archeology/` |

---

## Banned slop words

<!-- slop-allowlist: this line lists the banned terms as a reference; do not use them anywhere else -->
In any agent output: load-bearing, the moment, first-class, white-glove, battle-tested, rock-solid, future-proof, industry-leading.

(The exception is the AGENT-PROMPTS.md doc itself, which lists them as banned.)

---

## When in doubt

- Pattern bundle by symptom → [95-INDEX.md](../patterns/95-INDEX.md)
- Failure case catalog → [COMMON-FAILURE-CASES.md](COMMON-FAILURE-CASES.md)
- Citations for (A) → [LANGUAGE-REFERENCES.md](LANGUAGE-REFERENCES.md)
- Cookbook recipes → [COOKBOOK.md](COOKBOOK.md) (incl. § 11.5 for GitHub-URL clone)
- A reviewer wants to graduate a (B) — check whether it's already rejected → [REJECTED-PATTERNS.md](REJECTED-PATTERNS.md)
- A site has two bucket characteristics → [HYBRID-CLASSIFICATIONS.md](HYBRID-CLASSIFICATIONS.md)
- Something's broken → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

Default to (C) over (B) over (A). Measure before classifying. Property-test the equivalence claim.
