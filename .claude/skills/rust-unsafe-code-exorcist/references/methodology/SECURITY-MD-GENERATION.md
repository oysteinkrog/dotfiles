# SECURITY-MD-GENERATION.md — Auto-Generated SECURITY.md

After an audit completes, the project should have a SECURITY.md that tells users:

- How to report soundness concerns.
- What the project's soundness baseline is (current audit's findings).
- What soundness commitments the project makes (verify.sh runs on every release; SAFETY comments on every (A); etc.).
- What's known to be unaudited (the limitations).

The audit auto-generates this artifact from the AUDIT_SUMMARY + the project's existing security posture.

---

## What's in SECURITY.md

The skill ships a template ([assets/SECURITY.md.template](../../assets/SECURITY.md.template)) that the security-md-author subagent fills in.

Structure:

```markdown
# Security Policy

## Reporting

[How to report]

## Soundness commitments

[What the project promises]

## Audit baseline

[Current audit findings — at-a-glance]

## What's audited

[The audit's scope]

## What's NOT audited (limitations)

[Honest acknowledgment of gaps]

## Verification

[How users can verify our claims]

## Acknowledgments
```

---

## How the audit fills the template

### Section: Reporting

Copied from a project's existing convention (if any) or filled with defaults:

```markdown
## Reporting

If you suspect a soundness issue in this crate:

1. **Do not file a public issue.** Email <security@example.com> (or use GitHub's "Report security advisory" feature).
2. **Include a reproducer.** Minimal Rust code + `cargo +nightly miri test` output (or equivalent).
3. **Expect a response within 72 hours.**

For non-soundness security issues (DoS, credential leak, etc.), see <separate process>.
```

### Section: Soundness commitments

Filled from the audit's `AUDIT_SUMMARY.md § verification` section:

```markdown
## Soundness commitments

Each release of this crate:

- Has been audited by the rust-unsafe-code-exorcist methodology.
- Passes `cargo +nightly miri test` (default + strict-provenance + tree-borrows modes).
- Passes `cargo +nightly careful test`.
- Passes `loom` for every concurrency-touching code path.
- Passes `cargo fuzz` smoke test (60s per target).
- Has hardened SAFETY comments on every remaining `unsafe`.
- Has clippy lint coverage where the obligation is lintable.

These commitments are enforced via CI; see `.github/workflows/soundness.yml`.
```

### Section: Audit baseline

Filled from `AUDIT_SUMMARY.md § Tally`:

```markdown
## Audit baseline (as of vX.Y.Z, audited <date>)

- Total `unsafe` sites: <N>
- STRICTLY_UNAVOIDABLE: <a> (all with falsifiable justification)
- PERF_ONLY: <b> (all with `safe-only` feature flag for downstream opt-in)
- REFACTORABLE: <c> (in progress; see https://<repo>/issues?label=soundness)
- Pre-existing UB beads (tracked separately, address timeline varies): <p>

Full audit summary: `audit/AUDIT_SUMMARY.md` in the repo.
```

### Section: What's audited

Filled from `phase0_scope_decision.md`:

```markdown
## What's audited

The audit covers:

- All crates in this workspace (or: lists which crates).
- All `unsafe` blocks, `unsafe fn`, `unsafe impl`, `unsafe trait`, `extern` blocks, `asm!`.
- All public API paths reaching `unsafe`.
- Macro-generated `unsafe` (verified via `cargo expand`).
- Dependency-side `unsafe` reachable from our public API (per [DEP-SOUNDNESS-PROTOCOL.md]).
```

### Section: What's NOT audited (limitations)

Filled from `phase0_scope_decision.md § not-doing list` + `phase9_toolchain_skips.md`:

```markdown
## What's NOT audited

For transparency, here's what the audit doesn't cover:

- **FFI peer behavior.** We audit the Rust↔C boundary; we don't audit the C library itself.
- **OS-level guarantees.** We rely on libc / POSIX / kernel docs without re-verifying them.
- **External crates' soundness.** We audit our use of them; we don't re-audit their internals (we trust the well-known ones; see Cargo.lock for versions).
- **Inverse-fuzzing on every pub fn.** We fuzz <list>; we don't fuzz <list>.
- **Formal verification.** Most sites use property tests + miri; only <list> have kani proofs.

These limitations are intentional. To extend coverage, contact <security@example.com>.
```

### Section: Verification

Anyone can verify the project's soundness claims:

```markdown
## Verification

To reproduce the audit's findings:

```bash
git clone <repo>
cd <repo>
bash <audit-dir>/verify.sh
```

This runs miri + careful + loom + fuzz + mutants + geiger + the full test suite under default AND `safe-only` features. Expected runtime: 30-60 minutes.

The audit dir contains:
- `unsafe-inventory.jsonl` — every unsafe site with metadata.
- `audit/sites/` — per-site write-ups.
- `audit/classification/` — bucket assignments + justifications.
- `audit/plans/` — refactor plans (in progress).
- `audit/synthesis/` — global views (soundness surface, invariants, refactor clusters).
- `audit/REVIEWER_RESPONSES.md` — maintainer-empathy review.
- `audit/AUDIT_SUMMARY.md` — single-line summary.
```

### Section: Acknowledgments

Auto-filled from the audit's reviewer list + reporter list:

```markdown
## Acknowledgments

This audit was reviewed by:
- <human reviewer 1> (project maintainer)
- <agent / model> (multi-model triangulation per the rust-unsafe-code-exorcist methodology)

Soundness issues previously reported + addressed:
- CVE-2026-NNNN reported by <reporter>; fixed in vX.Y.Z+1.
- <other public credit>.
```

---

## Generation cadence

- **Initial audit completes.** Author the first SECURITY.md.
- **Each release.** Update the "Audit baseline" + "Verification" sections to reference the new version.
- **Each drift event of severity ≥ medium.** Add a note to the limitations or update commitments.
- **Each incident.** Update the Acknowledgments section + the "What's NOT audited" if the incident revealed a gap.

---

## Per-stakeholder versions

A single SECURITY.md serves all audiences, but the audit can ALSO emit:

- **TL;DR for the README.** A short paragraph linking to SECURITY.md.
- **Customer-facing audit report.** Deeper than SECURITY.md; covers methodology + reviewer + verification reproducibility.
- **Auditor-facing transparency report.** Full audit dir made public on the project's docs site.

The skill's defaults emit the SECURITY.md + a README badge; extended versions are opt-in.

---

## SECURITY.md vs CHANGELOG

| Document | Purpose | Cadence |
|----------|---------|---------|
| SECURITY.md | How to report; current commitments; baseline | Per-release |
| CHANGELOG.md § Security | Changes since last release | Per-release |
| `audit/SOUNDNESS-LOG.md` | Full audit history over project lifetime | Per-audit (lifecycle) |

Each fills a different niche; the audit generates all three.

---

## Acceptance signal

The SECURITY.md is healthy when:

1. Auto-generated from `AUDIT_SUMMARY.md` (no hand-editing required).
2. All sections filled (no `<placeholder>` text left).
3. Reporting channel is configured and tested.
4. Verification commands are paste-runnable.
5. Linked from the project's README + Cargo.toml metadata.

The artifact ships with every release.
