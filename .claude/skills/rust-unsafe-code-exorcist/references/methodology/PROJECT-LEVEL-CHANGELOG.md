# PROJECT-LEVEL-CHANGELOG.md — Lifetime Soundness Log

Beyond per-release CHANGELOG entries, the project benefits from a DEDICATED soundness log that accumulates every audit's findings + outcomes over the project's lifetime.

The file: `audit/SOUNDNESS-LOG.md` in the project repo.

---

## What it is

The soundness log is a single, append-only file documenting the project's soundness journey:

- Each audit's findings (date, scope, results).
- Each incident's RCA + fix.
- Each refactor wave's outcomes.
- Cumulative metrics (geiger count over time, harness uptime, etc.).
- Cross-references to specific commits / PRs / advisories.

The file grows ~1KB per audit + ~5KB per incident. Over 5 years of a project's life, it accumulates to ~50-100KB — manageable, valuable.

---

## Why this matters

A per-release CHANGELOG mentions soundness only when it changed in that release. A soundness log surfaces the BIGGER PICTURE:

- "We've done 8 audits over the project's lifetime; 4 (C) refactor waves landed."
- "Two incidents (CVE-2024-NNNN, CVE-2025-MMMM); both fixed within 72h."
- "Geiger count went from 342 to 91 between v0.5 and v1.0."
- "Continuous mode caught 23 drift events; 0 resulted in shipped UB."

This is the kind of context customers / downstream users care about. It builds trust beyond any single release.

---

## Template structure

`audit/SOUNDNESS-LOG.md`:

```markdown
# Soundness Log

Append-only record of this project's soundness journey, maintained per the
rust-unsafe-code-exorcist methodology.

Latest summary at top of each section; full history in append order.

---

## Project metadata

- Project: <name>
- First audit: <YYYY-MM-DD>
- Methodology: rust-unsafe-code-exorcist (<version>)
- Current verifier: `verify.sh` (last green: <date>)
- Current geiger count: <count>
- Open soundness debt: <total risk-pts>

---

## Audit history (newest first)

### Audit #N — <YYYY-MM-DD> — v<release>

**Mode:** audit-and-refactor (or whichever).
**Scope:** <crates in scope>.
**Duration:** <hours/days>.
**Result:** verify.sh GREEN; <count> sites refactored.

**Tally:**
| Bucket | Count |
|--------|-------|
| (A) STRICTLY_UNAVOIDABLE | <a> |
| (B) PERF_ONLY | <b> |
| (C) REFACTORABLE | <c> closed; <open> remaining |
| pre-existing-UB | <p> filed |

**Delta from previous audit:**
- (A) count: was <prev_a>; now <a> (<delta>).
- (B) count: was <prev_b>; now <b>.
- (C) count: was <prev_c>; now <c> (<closed> closed in this wave).
- Geiger: was <prev_g>; now <g>.

**Key clusters refactored:**
- Cluster R-001 (5 sites; `arc-swap` adoption).
- Cluster R-007 (3 sites; zerocopy migration).

**Reviewer.** <reviewer> with confidence <H/M/L>.

**Artifacts.**
- Audit dir: `<audit-dir>/audit-N/`
- PR: #1234
- Bead chain: br-2001 through br-2034.

---

### Audit #N-1 — <YYYY-MM-DD> — v<earlier release>

...

---

## Incident history (newest first)

### Incident #M — <YYYY-MM-DD> — CVE-<NNNN>

**Severity:** High.
**Symptom:** Use-after-free in `parse_jwt` on empty token.
**RCA:** `audit-N/incident-rca.md`.
**Fix:** v<version>+1.
**Advisory:** RUSTSEC-2026-NNNN.
**Reporter:** <name>.
**Response time:** 48h (acknowledge) + 5d (fix shipped).
**Regression test:** `tests/regression_cve_2026_NNNN.rs`.
**Forward propagation:** found 2 sibling sites with similar invariant; filed beads `<id>` and `<id>`.

---

### Incident #M-1 — ...

---

## Refactor wave summary

### Wave 4 — Q1 2026
- Sites refactored: 47
- Risk-pts closed: 1,200
- Beads closed: br-2001 to br-2047
- Highlight: `arc-swap` migration eliminated 6 unsafe impls.

### Wave 3 — Q4 2025
- Sites refactored: 28
- Risk-pts closed: 720
- Beads: br-1801 to br-1828
- Highlight: pin-project-lite adoption.

### Wave 2 — Q3 2025
- Sites refactored: 19
- Risk-pts closed: 410
- Beads: br-1501 to br-1519

### Wave 1 — Q2 2025 (initial audit)
- Sites refactored: 35
- Risk-pts closed: 950
- Beads: br-1001 to br-1035
- Highlight: First full audit; baseline established.

---

## Continuous-mode highlights

- Total drift events caught: <N>
- Drift handled within 24h: <K>
- False-positive drift bead rate: <%>
- Clean-streak record: <X days>
- Current clean streak: <Y days>

---

## Cumulative metrics

| Metric | At baseline | Now | Trend |
|--------|-------------|-----|-------|
| Geiger count | 342 | 91 | ▼ -73% |
| Audit risk-pts total | 8200 | 1800 | ▼ -78% |
| Soundness surface entries | 87 | 34 | ▼ -61% |
| (A) sites with hardened SAFETY | 12% | 100% | ▲ +88pp |
| `safe-only` feature exists | NO | YES (since v0.8) | — |
| `verify.sh` clean streak | n/a | 142 days | — |

---

## How to contribute to the soundness log

- The skill auto-appends after each audit + incident.
- Manual additions allowed for context (e.g., "we adopted policy X because of past incident Y").
- Append-only — old entries are NOT modified (preserves history).
- Format: each entry has a date + section header + structured content.
```

---

## Generation cadence

- **At baseline audit completion.** Initial entry.
- **At each subsequent audit.** Append "Audit #N" entry.
- **At each incident.** Append "Incident #M" entry.
- **At each refactor wave's completion.** Append to "Refactor wave summary".
- **Monthly.** Continuous-mode summary appended.

The auto-generation produces a draft; user reviews + commits.

---

## Cross-reference with other artifacts

The soundness log doesn't duplicate; it CROSS-REFERENCES:

- Per-site analysis lives in audit dirs.
- Per-incident RCA lives in audit dirs.
- This log is the INDEX + the lifetime narrative.

A reader of the log can drill into any audit/incident by following the cross-reference.

---

## Privacy considerations

The soundness log is PUBLIC (lives in the project repo). It does NOT include:

- Specific reporter names without permission.
- CVE details before public disclosure date.
- Internal customer info.

Sensitive data lives in private audit dirs or coordinator-only channels; the log references it WITHOUT exposing it.

---

## Acceptance signal

A healthy soundness log:

1. Auto-appended after every audit + incident.
2. Cumulative metrics are computed correctly (e.g., geiger trend).
3. Each entry has a date + scope + outcome.
4. Cross-references resolve (e.g., the audit-dir paths exist or are archived).
5. The user reviews before commit; no unexpected content.

The log is the project's institutional memory made visible.
