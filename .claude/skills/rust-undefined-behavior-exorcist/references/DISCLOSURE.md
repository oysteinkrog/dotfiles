# Disclosure — When The UB Is In A Public Crate

If the audit surfaces UB in code that's been shipped to crates.io, the response is not just a code fix — it's a coordinated security disclosure. This file is the playbook.

---

## When does a finding cross the disclosure threshold?

| Finding shape | Crosses threshold |
|---|---|
| `MUST-BE-UB` or `LIKELY-UB`, shipped in a `>= 0.1.0` release | YES — file with RustSec |
| `MUST-BE-UB`, in `< 0.1.0` and marked unstable | Disclose to maintainer; RustSec optional |
| `MUST-BE-UB`, in your own private crate | Just fix it; no disclosure |
| `MUST-BE-UB`, behind a feature flag never enabled in published releases | Document; no public disclosure |
| `CONTRACTUAL-BUT-DEFENSIBLE` requiring caller cooperation | Document the contract more clearly; no disclosure |

Use the [Common Vulnerability Scoring System (CVSS)](https://www.first.org/cvss/) v3.1 to score severity. Anything CVSS ≥ 7.0 is mandatory disclosure; 4.0–6.9 is recommended; < 4.0 is documentation-grade.

---

## The disclosure timeline

Standard practice (modeled on [`rustsec/advisory-db`](https://github.com/RustSec/advisory-db)):

| Day | Action |
|---|---|
| 0 | Skill produces `CONFIRMED_UB` finding for a public-crate function |
| 0 | Author a private reproducer (`experiments/EXP-NNN/repro.rs`); confirm under Miri matrix + sanitizers |
| 0 | Determine if the UB is reachable from safe public API |
| +1 | Contact crate maintainer privately (email per `Cargo.toml` `[package.authors]`, or `security.txt`, or via Mastodon DM) |
| +1 | Provide: reproducer, Miri/sanitizer output, your CVSS score, proposed remediation (or note that you're available to help) |
| +7 | If no response: contact RustSec coordinator at `security@rustsec.org` to begin coordinated disclosure |
| +14 | If maintainer responsive but no patch: agree on extension or RustSec disclosure date |
| +30..90 | Patch lands in a new version; advisory posted on `advisory-db` |
| +30..90 | If maintainer unresponsive: RustSec posts advisory anyway; consider forking |

The clock can be compressed for "trivially exploitable in safe code from a million downstream users". The clock can be extended for "requires unsafe in calling code to trigger".

---

## What to send the maintainer

A good first email:

```
Subject: [security/private] UB in <crate> via <function/feature> — disclosure planned

Hi <maintainer>,

I'm doing a UB audit (via /rust-undefined-behavior-exorcist) of crates in
my project's dependency tree. I found an unsoundness in <crate> at
<file:line> that I believe is reachable from safe public API.

Attached: reproducer (Rust + Cargo.toml), Miri trace, draft RustSec advisory.

Summary:
  - Crate: <name>, versions: <range>
  - Function: <pub fn name or trait impl>
  - Bucket (per Rustonomicon): <e.g., aliasing — TB violation>
  - Reachability: <"safe API directly" / "requires unsafe caller but standard usage" / etc.>
  - CVSS v3.1: <score> (<vector>)

I'd like to coordinate a disclosure timeline with you. RustSec
recommends 30 days but I can be flexible. If you'd like help with the
patch, I'm available.

I'll hold off on filing the RustSec advisory until <date+30> unless you
indicate a different timeline.

Thanks,
<name>
```

Three principles:
1. **Private first.** Don't post the reproducer on a public issue tracker.
2. **Specific.** Cite Miri output, not vague claims.
3. **Generous.** Offer to help; agree to reasonable extensions.

---

## CVSS v3.1 quick reference for Rust UB

Scoring vector mnemonic: AV/AC/PR/UI/S/C/I/A.

| Attribute | Likely value for typical Rust UB |
|---|---|
| AV (Attack Vector) | `L` (local) for most; `N` (network) if reachable via deserialization of attacker bytes |
| AC (Attack Complexity) | `L` (low) — if Miri reproduces in <30 lines |
| PR (Privileges Required) | `N` (none) — if reachable from safe API |
| UI (User Interaction) | `N` (none) — for parsers / deserializers |
| S (Scope) | `U` (unchanged) for in-process UB; `C` (changed) for kernel modules |
| C (Confidentiality) | `L`/`H` — depends on what bytes leak |
| I (Integrity) | `H` (high) — UB typically means writable corruption |
| A (Availability) | `H` (high) — UB typically means process crash |

Typical Rust UB CVSS lands in 7.0–9.0 range. Use the [calculator](https://www.first.org/cvss/calculator/3.1).

---

## RustSec advisory format

`advisory-db` accepts TOML files at `crates/<name>/RUSTSEC-YYYY-NNNN.md`. Template:

```toml
[advisory]
id = "RUSTSEC-2026-XXXX"
package = "<crate-name>"
date = "2026-MM-DD"
title = "Use-after-free in <function>"
description = """
<concise description of the UB, the trigger condition, and the impact>

Reproducer:
```rust
<<<minimal reproducer from EXP-NNN>>>
```
"""
url = "https://github.com/<owner>/<repo>/issues/N"
categories = ["memory-corruption"]
keywords = ["use-after-free", "<bucket>"]
cvss = "CVSS:3.1/AV:L/AC:L/PR:N/UI:N/S:U/C:L/I:H/A:H"

[affected]
patched_versions = [">= X.Y.Z"]
unaffected_versions = ["< A.B.C"]
```

The body markdown can include the full Miri trace + the remediation strategy. RustSec coordinators review before merging.

---

## When the maintainer is unresponsive

You've waited 7 days with no reply. Options:

1. **Try alternate channels:** GitHub Sponsors page DM, Twitter/Mastodon DM, Discord (`#rust-lang` server has a `#code-of-conduct-help` channel that knows escalation paths).
2. **Check if the project is abandoned:** `cargo-outdated --workspace` against the crate's repo; look at last commit date. If > 12 months, it's probably abandoned.
3. **Fork:** publish `<crate>-patched-soundness` to crates.io with the fix. Cite the original repo and the unresponsive-disclosure record. This is a last resort.
4. **File RustSec anyway:** the coordinator has authority to publish even without maintainer cooperation, with a note that the maintainer didn't respond.

---

## When the UB is in your own published crate

Different playbook. You don't need to wait — but you do need to:

1. **Yank the affected versions.** `cargo yank --vers X.Y.Z` for each impacted version.
2. **Publish a patched version.** Bump the version per semver (patch bump if internal change, minor bump if API change to fix the soundness).
3. **File RustSec advisory yourself.** Same template as above, but you don't need to wait — file alongside the patched release.
4. **Tweet/announce.** A short post saying "yanked X.Y.Z, please upgrade to X.Y.Z+1, advisory at RUSTSEC-...".
5. **Update CHANGELOG.md.** Explicitly call out the soundness fix; downstream users searching for "soundness" should find it.

---

## When the UB is in a transitive dependency you can't update

Sometimes you find UB in `<crate>` v1.2 used by `<other-crate>` v3.0 that requires v1.2 exactly. You can't bump.

Options:
1. **Wrap at the boundary.** Your code never invokes the buggy function directly; it invokes a safe wrapper that pre-checks the conditions that would trigger UB.
2. **Fork the intermediate.** Maintain `<other-crate>-patched` that uses `<crate>` v1.3 (with the fix).
3. **Patch via `[patch.crates-io]`** in `Cargo.toml`:
   ```toml
   [patch.crates-io]
   buggy-crate = { git = "https://github.com/you/buggy-crate-fork", branch = "soundness-fix" }
   ```
4. **Document and live with it.** Sometimes the UB is unreachable from your usage pattern. Add a `phase8_remediation_plan.md` entry that says "depends on `<crate>` v1.2 which has UB in `<fn>`; our usage path doesn't trigger it because <reason>". File a finding to revisit if usage changes.

---

## Disclosure for kernel modules / unsafe-ABI crates

Some Rust crates expose `unsafe extern "C"` that *requires* callers to satisfy preconditions. If the documentation is missing, that's a SAFETY-comment audit problem, not a CVE. But if the docs *claim* the function is safe to call when it isn't — that's a CVE.

Use [SECURITY.md](https://docs.github.com/en/code-security/getting-started/adding-a-security-policy-to-your-repository) in the crate's repo as the canonical contact. If none, treat like an unresponsive maintainer.

---

## After disclosure

Once the patched version lands:

1. **Update your downstream `Cargo.toml`** to require the patched version.
2. **Add to your project's UB_RUNBOOK.md** as a "previously found vulnerability".
3. **Add the regression test** from the disclosure to your project's test suite — even if not in the dependency itself, the regression test belongs in *your* CI.
4. **Search for similar patterns.** If `<crate>` had this UB, do other crates with similar code patterns also have it? Run a fresh Phase 6 idea-wizard round with the shape as input.

---

## Templates

`scripts/disclosure-template-author.sh` (Phase 8 helper) generates a draft `RUSTSEC-YYYY-XXXX.md` from an EXP-NNN block. Use it as a starting point; manually fill in CVSS, contact log, timeline.

For the maintainer-email template, see `assets/disclosure-email-template.md`.
