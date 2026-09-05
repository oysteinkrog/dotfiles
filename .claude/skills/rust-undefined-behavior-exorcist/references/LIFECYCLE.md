# Lifecycle — What Happens After The Audit

Phase 12 produces `FINAL_UB_REPORT.md` and `UB_RUNBOOK.md`. The audit is "done" but the runbook is alive. This file describes the post-audit life of the project — how the runbook is maintained, how new findings get integrated, how the audit gets refreshed.

For the convergence-and-ship part, see [PHASES.md §Phase 12](PHASES.md#phase-12-final-artifacts). This file picks up *after* Phase 12.

---

## Phase 13 (implicit): Run

The user's team takes the bead graph and implements the remediations. Each remediation bead has:
- The proving experiment (the EXP-NNN that confirmed the UB)
- The regression experiment (the EXP-NNN that should pass after the fix)
- The chosen rewrite candidate (from `phase8_remediation_plan.md`)
- The runners-up + rubric scores (for revisit if the chosen one doesn't pan out)

Typical timeline: 1-4 weeks for a moderate audit's bead graph (50-100 beads).

**Skill role during Phase 13:** Passive. The skill produced the artifacts; the team owns execution. The skill can be re-invoked if the team gets stuck on a specific bead — see "Spot-audit" below.

---

## Phase 14 (implicit): Land

As beads close, the team merges PRs. The `UB_RUNBOOK.md`'s CI gates fire on every PR; new UB shouldn't sneak in.

**Gates that the runbook installs:**

```yaml
# .github/workflows/ub.yml
on:
  pull_request:
  schedule:
    - cron: '0 0 * * *'  # nightly full sweep
jobs:
  miri-quick:
    # on every PR: Miri default + tree-borrows on changed crates
  miri-full:
    # nightly: full MIRIFLAGS matrix on the whole tree
  sanitizers:
    # nightly: ASan + TSan + LSan
  loom:
    # nightly: all loom models
  fuzz-smoke:
    # on every PR: 60-second fuzz run per target
  fuzz-soak:
    # weekly: 1-hour fuzz per target
```

**Skill role during Phase 14:** Provides the CI YAML excerpts. The `ub-runbook-author` subagent produces them in Phase 12.

---

## Phase 15: Drift detection

Over time, the codebase changes. Some changes are UB-neutral; some are UB-introducing. Drift detection asks: are we still UB-free?

### Continuous drift signals

These should trigger a re-audit (or at least a spot-audit):

| Signal | Severity | Action |
|---|---|---|
| New `unsafe` block landed without SAFETY comment | HIGH | Spot-audit the bead, file a finding |
| Existing `unsafe` block modified | HIGH | Spot-audit, re-run the EXP-NNN that proved soundness |
| `Cargo.toml` adds a new dep with unsafe surface | MEDIUM | Run dependency-soundness mode on the new dep |
| Bump of Rust nightly toolchain | LOW | Re-run Miri full matrix to detect tool-version drift |
| Bump of a major dep | MEDIUM | Re-run Phase 3 dynamic sweep against the bumped dep |
| New `extern "C"` block | HIGH | Re-run Phase 1 RECON + Phase 2 FFI bucket |
| New `loom`-shaped sync primitive | HIGH | Re-author a loom model; add to `tests/<primitive>_loom.rs` |

### Tooling for drift detection

- **`cargo audit` weekly** — catches new RustSec advisories
- **`cargo update` + diff** — catches dep bumps
- **`scripts/drift-monitor.sh` (if installed)** — compares current `phase1_unsafe_surface_inventory.md` against committed baseline and reports new sites

---

## Spot-audit (between full audits)

A spot-audit is a Phase-3-and-5 only run focused on a specific module or finding. Use cases:
- A new feature lands; spot-audit just the new module
- A reported bug is suspected UB; spot-audit the affected path
- Pre-release for a minor version; spot-audit the diff from the previous tag

Spot-audit duration: 1-3 hours.

Invocation:
```bash
/rust-undefined-behavior-exorcist spot <project> --scope crates/mvcc --since v1.3.0
```

The skill scopes Phase 1 inventory to the change-set, runs Phase 3 dynamic sweep on the scoped paths, and reports any findings.

---

## Full re-audit cadence

How often to run the *full* 12-phase audit:

| Project tier | Cadence |
|---|---|
| Pre-1.0 / early development | Every 3-6 months |
| Stable 1.x library | Annually + before every major release |
| Production-critical / OSS with downstream users | Every 6 months + on significant refactors |
| Security-critical / cryptographic | Every 3 months + Phase 11 soak after every release |

The `UB_RUNBOOK.md` should document the cadence the maintainer commits to.

---

## When the runbook becomes stale

A runbook is stale when:
- The Miri config matrix is older than the current Miri's recommended matrix
- The CI YAML uses deprecated GitHub Actions syntax
- New UB-taxonomy buckets have been discovered (e.g., the Rustonomicon adds a new section) that aren't covered
- The fuzz corpora referenced are missing or moved
- The exemplar projects cited (Q-NNN anchors) have moved or changed

Refresh the runbook at:
- Every full re-audit (mandatory)
- When a *new* UB shape is found in the codebase (the runbook gains a new "if you change X, re-run EXP-Y" recipe)
- When tooling significantly changes (e.g., Tree Borrows becomes default; the matrix needs to be updated)

---

## Lifecycle of individual findings

A finding's lifecycle:
```
[Phase 1] surfaced as F-NNN (OPEN)
   ↓
[Phase 2] tagged with bucket(s), severity (LIKELY-UB)
   ↓
[Phase 4] consolidated, experiment EXP-NNN designed
   ↓
[Phase 5] experiment run → verdict CONFIRMED_UB
   ↓
[Phase 8] remediation candidates designed, winner chosen (R-NNN)
   ↓
[Phase 9] beads br-XXX through br-XXY filed
   ↓
[Phase 13/14] beads closed, authorized diffs landed
   ↓
[Phase 15] regression test in CI; drift detection watches
   ↓
[indefinitely] runbook entry "if you change X, re-run EXP-NNN"
```

When the finding's regression test breaks in CI 6 months later, the team has the EXP-NNN + R-NNN + chosen rewrite + runners-up — all preserved in `phase8_remediation_plan.md`. No re-derivation needed.

---

## Runbook ownership

Who owns `UB_RUNBOOK.md`? It's part of the project's documentation.
- **Crate maintainer:** Final authority. Decides which gates are mandatory vs advisory.
- **CI/release engineer:** Operationalizes the CI YAML.
- **Security team (if applicable):** Reviews CVSS scoring on findings, owns disclosure timeline.

A good runbook names its owners at the top. Example:

```markdown
# UB Runbook — frankensqlite

**Owners:**
- Soundness: @Dicklesworthstone (filed bugs, reviews PRs touching unsafe)
- CI: @Dicklesworthstone (maintains .github/workflows/ub.yml)
- Disclosure: @Dicklesworthstone (handles RUSTSEC advisories)

**Cadence:** full re-audit every 6 months; spot-audit on any PR touching `unsafe`.
**Last audited:** 2026-05-14 (run-id: 2026-05-14-frankensqlite-1)
**Next scheduled:** 2026-11-14
```

---

## Skill-side maintenance

The skill itself evolves. Maintainer concerns:
- New UB shapes discovered → add to [UB-TAXONOMY.md](UB-TAXONOMY.md)
- New tools → add to [TOOLING.md](TOOLING.md) + scripts
- New rituals from cass mining → add to [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) + [corpus/quote_bank/quote_bank.md](../corpus/quote_bank/quote_bank.md)
- New project archetypes → add to [PROJECT-TYPES.md](PROJECT-TYPES.md)

The `kernel-keeper` subagent runs at the end of every audit to keep the corpus + kernel + operator library consistent.

---

## Audit history archive

After Phase 12, the workspace `<source>/.ub-exorcism/<run-id>/` should be archived for posterity:
- Commit or tag the source repo with the audit artifacts included, if the user wants the artifacts versioned there: `git tag ub-exorcism/<run-id>/final`
- Push to the project's intended private or public remote according to the user's disclosure policy
- Reference the archive's URL or source tag in `UB_RUNBOOK.md` ("see audit-2026-05-14 for full reproducer files")

Future runs can compare against this archive to measure drift and progress.

---

## End-of-life

When the project itself is end-of-lifed:
- The runbook's CI gates can be turned off
- The audit archive can be made public (with `unsafe` reproducers gated for trusted readers if any are CVSS-bearing)
- The advisory database (RustSec) is the source of truth for any unpatched issues; document them clearly in the project's deprecation notice
