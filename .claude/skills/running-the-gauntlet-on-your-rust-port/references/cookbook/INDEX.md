# Gauntlet Cookbook — Index

Recipes for the 12 recurring motions of a mature gauntlet run. Each entry composes operator glyphs (see [../methodology/OPERATORS.md](../methodology/OPERATORS.md)) into a paste-ready pipeline, names the specific scripts to invoke, fixes a bead-naming convention, and lists the anti-patterns that look like progress but aren't.

Read this index when triaging a fresh signal; jump straight to the recipe when the signal matches one you've seen before.

## Reading the table

- **Operator pipeline** is the canonical glyph sequence. Each glyph is a cognitive move, not a script; the recipe maps glyphs onto literal commands.
- **Scripts** lists the gauntlet shell scripts that implement each step (all live in `<workspace>/scripts/`).
- **Bead naming** is the `br create --title` prefix every recipe uses, so the dependency graph stays grep-able.
- **Wall-time** is the median resolution time for a maintainer who already knows the recipe; if a triage takes 4x the listed time, something is wrong with the recipe and the maintainer should escalate.

## The twelve default motions

| # | Motion | Trigger | Operator pipeline | Scripts | Bead naming | Wall-time (median) |
|---|---|---|---|---|---|---|
| 1 | [perf-regression-triage](perf-regression-triage.md) | `apply-ratchet.sh` returns `Block`/`Quarantine` on a perf field | `⚠ → 🗄 → ⬡ → ⤴ → ⟁ → 🧪 → ⊕ → ⚖ → 🪟` | `run-bench-matrix.sh`, `mine-ledger.sh`, `run-narrow-benches.sh`, `apply-ratchet.sh` | `perf-regression-<workload>` | 45 min |
| 2 | [oracle-divergence-triage](oracle-divergence-triage.md) | New `TrueDivergence` in the differential corpus | `⊙ → ⌘ → ⚠ → 🧪 → ⊕ → ⚖` | `run-conformance-suite.sh`, `compute-mismatch-signature.sh`, `replay-failure.sh` | `oracle-div-<signature>` | 90 min |
| 3 | [surface-gap-found](surface-gap-found.md) | FeatureUniverse reports `Missing` (or `Partial`) on a release-blocking item | `✦ → 🧪 → ⊕ → ⚖` | `compute-feature-coverage.sh`, `run-conformance-suite.sh` | `surface-gap-<feature-id>` | varies (hours to weeks) |
| 4 | [cv-pct-flake](cv-pct-flake.md) | A microbench reports `cv_pct > 5` | `⟁ → ⬡ → 🗄 → 🧪` | `run-narrow-benches.sh`, `mine-ledger.sh` | `flake-<bench>-cv` | 30 min |
| 5 | [e-process-rejection](e-process-rejection.md) | E-value for invariant `INV-X` crossed `1/α` (Ville rejection) | `⚠ → ⌘ → ⊙ → 🧪 → ⊕` | `run-conformance-suite.sh`, `replay-failure.sh` | `eproc-reject-<INV-X>` | 2 hr |
| 6 | [bocpd-shift-detected](bocpd-shift-detected.md) | `BOCPD` regime → `ShiftDetected` mid-soak | `⊞ → ⚠ → ⌘ → 🧪` | `run-soak-campaign.sh --resume`, `mine-ledger.sh` | `bocpd-shift-<stream>` | 4 hr |
| 7 | [ratchet-block](ratchet-block.md) | `apply-ratchet.sh` emitted `Block` for a category | `⚖ → 📐 → 🗄 → ⊕` | `apply-ratchet.sh`, `update-ratchet-state.sh`, `subagents/waiver-author.md` | `ratchet-block-<category>` | 60 min |
| 8 | [mt8-attribution-flat](mt8-attribution-flat.md) | Top-10 MT8 frames all `< 0.1%` self-time | `⤴ → ⟁ → ⊕ → 🧪` | mt8-attribution-profiler subagent, `run-narrow-benches.sh` | `mt8-flat-<workload>` | 90 min |
| 9 | [dependency-version-bump](dependency-version-bump.md) | Reference moved (e.g., `sqlite-3.52 → 3.53`) | `★ → ✦ → ◐ → 🧪 → ⚖` | `init-workspace.sh`, `oracle-preflight-doctor.sh` | `refbump-<old>-<new>` | 6-24 hr |
| 10 | [new-fault-class-discovered](new-fault-class-discovered.md) | Real-world failure not reproducible under existing FaultKinds | `⚠ → ⌘ → ⊞ → 🧪` | `run-fault-injection-matrix.sh`, fault-injector-author subagent | `fault-class-<name>` | 4 hr |
| 11 | [cross-pillar-regression](cross-pillar-regression.md) | Closing perf bead caused conformance regression (or vice versa) | `⊕ → ⚖ → 🪟 → 📐` | `compute-parity-score.sh`, fresh-eyes pass | `crosspillar-<source>-<sink>` | 3 hr |
| 12 | [fresh-onboardee-trust-tier-up](fresh-onboardee-trust-tier-up.md) | Onboardee completed week-4 milestone | (no operators; trust-ladder workflow) | knowledge-transfer subagent | `onboardee-<name>-week<N>` | 30 min |

## Operator key (compressed)

| Glyph | Name | One-line |
|---|---|---|
| `★` | Pin-Reference-Version | Every artifact names the reference version. |
| `✦` | Enumerate-Surface | `present\|partial\|missing\|n/a\|excluded` for every pub item. |
| `◐` | Wire-Oracle | In-process bridge + `EngineIdentity` distinct. |
| `⬡` | Instrument-Hot-Path | Counter ≥ 0.1% self-time before touching the loop. |
| `⚠` | Escalate-To-Fresh-Repro | FailureBundle with seed + schedule + repro command. |
| `⊕` | Isomorphic-Rewrite | 2+ behavior-preserving alternatives. |
| `⊙` | Debounce-False-Positive | Classify as one of 5 mismatch classes (or TrueDivergence). |
| `⊞` | Soak | Full soak duration (24h fuzz / multi-day miri / etc). |
| `⌘` | Reduce/Minimize | Delta-debug to 1-minimal with schema preservation. |
| `⟁` | Triangulate-Profile | ≥2 profilers agree on the top frames. |
| `⤴` | Attribute-To-MT8 | Named frame ≥0.1% self-time. |
| `🔁` | Pass-Over-Pass-Gate | Focused + broad gates same run window. |
| `⚖` | Ratchet-Lower-Bound | Conformal lower bound, not point estimate. |
| `🪟` | Fresh-Eyes | Three calibrated reviewers, two clean rounds. |
| `🗄` | Ledger-Retire | Retry-condition predicate, not "later". |
| `🧪` | Experiment-Design | Hypothesis/repro/expected-signal/falsifiability/one-line/results-inline. |
| `📐` | Conformal-Band | Distribution-free band, LOWER bound for release. |
| `🎚` | Raise-ULP-Tolerance | Per-op only, capture `gradcheck_max_rel_error`. |
| `🪞` | Engine-Identity-Guard | `assert_ne!(subject_identity, reference_identity)` at every entry. |

## When the recipe doesn't fit

If the motion doesn't match any of the twelve:

1. Check `references/methodology/OPERATORS.md § Composition Cheat-Sheet` — the listed pipelines cover variations.
2. Check the per-project `<workspace>/cookbook/PROJECT-SPECIFIC-MOTIONS.md` (rendered by the cookbook-author subagent at Phase 16).
3. If still no match, write the recipe yourself: pick the operators, draft the script invocations, file the bead, and ask the next cookbook-author run to add it.

## See also

- [../methodology/OPERATORS.md](../methodology/OPERATORS.md) — full operator card library.
- [../methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md) — what kept evidence must look like.
- [../patterns/00-INDEX.md](../patterns/00-INDEX.md) — pattern library cross-referenced from every recipe.
- [../../assets/parity-runbook-template.md](../../assets/parity-runbook-template.md) — 11 CI gates that catch most of these motions automatically.
