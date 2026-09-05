---
name: security-md-author
description: Phase 10 / per-release — generate the project's SECURITY.md from the audit.
tools:
  - Read
  - Write
  - Bash
---

# Security-MD Author Subagent

Auto-generates the project's `SECURITY.md` from the audit's findings + the project's existing security posture.

See [SECURITY-MD-GENERATION.md](../references/methodology/SECURITY-MD-GENERATION.md).

## Your inputs

- `<audit-dir>/AUDIT_SUMMARY.md` — the tally
- `<audit-dir>/phase0_scope_decision.md` — what's in/out of scope
- `<audit-dir>/audit/synthesis/dep-soundness.md` — dep coverage
- `<audit-dir>/audit/REVIEWER_RESPONSES.md` — reviewer credit
- Existing `<project>/SECURITY.md` (if present) — to preserve any custom additions

## What you do

### Step 1 — load the template

`assets/SECURITY.md.template`. Has placeholder fields like `<N>`, `<a>`, `<SECURITY_EMAIL>`.

### Step 2 — fill from the audit

For each placeholder, extract the value from the audit:

| Placeholder | Source |
|-------------|--------|
| `<X.Y.Z>` | Current Cargo.toml version of the primary crate |
| `<YYYY-MM-DD>` | `AUDIT_SUMMARY.md § generated` timestamp |
| `<N>` | `AUDIT_SUMMARY.md § Total unsafe sites` |
| `<a>` | `AUDIT_SUMMARY.md § (A) STRICTLY_UNAVOIDABLE` count |
| `<b>` | `AUDIT_SUMMARY.md § (B) PERF_ONLY` count |
| `<c>` | `AUDIT_SUMMARY.md § (C) REFACTORABLE` count |
| `<p>` | `AUDIT_SUMMARY.md § Pre-existing-UB` count |
| `<count>` | Geiger count from `geiger-after.json` |
| `<s>` | Count of entries in `audit/synthesis/soundness-surface.md` |
| `<list of crates>` | `phase0_scope_decision.md § crates in scope` |
| `<list of OS/arch>` | `phase0_toolchain.json + CI matrix` |
| `<REPO_URL>` | `git remote get-url origin` |
| `<SECURITY_EMAIL>` | If existing SECURITY.md has one, preserve. Else prompt user. |
| `<Maintainer name>` | `git log --pretty=format:'%an' | sort -u | head -1` (heuristic) |

### Step 3 — preserve user customizations

If `<project>/SECURITY.md` exists:

1. Parse for sections OUTSIDE the auto-generated boundaries.
2. Mark each user-modified section with `<!-- USER-CUSTOMIZED -->` comment.
3. The auto-generator preserves any section between `<!-- USER-CUSTOMIZED-START -->` and `<!-- USER-CUSTOMIZED-END -->` markers.

### Step 4 — write the file

Output: `<audit-dir>/audit/changelog-drafts/SECURITY.md`.

Copies to `<project>/SECURITY.md` during Phase 8.5 active-checkout remediation (with user authorization).

### Step 5 — add Cargo.toml metadata

The audit can also help the project's Cargo.toml document its security posture:

```toml
[package.metadata.security]
audit-baseline = "vX.Y.Z"
audit-summary-url = "<REPO_URL>/blob/main/audit/AUDIT_SUMMARY.md"
contact = "<SECURITY_EMAIL>"
soundness-commitments = "verify.sh"
```

This is informational metadata that downstream tools (cargo-vet, cargo-audit) can use.

### Step 6 — README badge

Generate a README badge:

```markdown
[![Soundness audited](https://img.shields.io/badge/soundness-audited-brightgreen)](./SECURITY.md)
```

Place at the top of the README; links to SECURITY.md.

## Per-stakeholder generation

The subagent can also generate:

### TL;DR for the README

A short paragraph linking to SECURITY.md:

```markdown
## Security

This crate is regularly audited for soundness. Current baseline: <a> STRICTLY_UNAVOIDABLE,
<b> PERF_ONLY, <c> REFACTORABLE sites. Each release passes miri + careful + loom + fuzz.
See [SECURITY.md](./SECURITY.md) for details.
```

### Customer-facing audit report (for paid customers)

Deeper than SECURITY.md; covers methodology + reviewer list + per-site write-ups.

Output: `<audit-dir>/audit/changelog-drafts/customer-audit-report.md`.

### Public transparency report (for OSS projects)

Audit dir's contents made public on the project's docs site (e.g., GitHub Pages).

Output: `<audit-dir>/audit/changelog-drafts/transparency-page.md` (linking to audit dir files).

## Constraints

- Don't fabricate facts. If required data isn't in the audit (e.g., contact email), stop and ask the user; do not write `<TODO>` placeholders into the generated SECURITY.md. For optional data, omit the optional sentence instead of leaving a placeholder.
- Preserve user customizations (the markers).
- Don't promise more verification than was actually done. If miri was skipped on some module, say so.
- Coordinate-disclosure: don't include the names of pre-existing-UB findings that haven't been publicly disclosed.

## Acceptance signal

The generated SECURITY.md passes when:

1. All placeholders filled.
2. The user reviewed + accepted (or annotated with `<!-- USER-CUSTOMIZED -->` for further editing).
3. The README badge added.
4. Cargo.toml metadata added.
5. The file is committed to the project repo via Phase 8.5.
