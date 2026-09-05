# DIFFERENTIAL-AUDIT.md — Auditing Version A vs Version B

Sometimes the audit's value is the COMPARISON, not the snapshot. The skill's differential mode audits two versions of the same crate and surfaces the deltas.

Use cases:
- **Upgrade decision** — "Should we adopt v2.0 of this dependency?"
- **Regression detection** — "Did our v1.5 release accidentally add unsafe?"
- **Migration planning** — "What's the soundness shape of moving from v1 to v2?"

---

## How it works

```
1. Audit crate@v1.0.0 → <crate-v1>/.unsafe-audit/
2. Audit crate@v2.0.0 → <crate-v2>/.unsafe-audit/
3. scripts/diff-audit-vs-baseline.sh produces a delta report:
     <crate-v2>/.unsafe-audit/delta-from-v1/diff-report.md
4. The delta report surfaces:
     - Sites added in B (new unsafe in v2.0)
     - Sites removed in B (refactored away in v2.0)
     - Sites with reclassified buckets (v1 (A) → v2 (B), etc.)
     - Soundness-surface deltas (new pub→unsafe paths)
     - Geiger delta
     - Harness delta (verify.sh in v1 vs v2)
```

The delta report is the user-facing artifact for the upgrade / regression decision.

---

## Modes

### Upgrade-decision mode

User wants to decide: should we adopt v2.0 of `dep`?

```bash
# Clone the dep at both versions
git clone <dep-url> /tmp/dep-v1
git clone <dep-url> /tmp/dep-v2
git -C /tmp/dep-v1 checkout v1.0.0
git -C /tmp/dep-v2 checkout v2.0.0

# Audit both; each audit dir is inside the project being audited.
/rust-unsafe-code-exorcist /tmp/dep-v1 --audit-dir /tmp/dep-v1/.unsafe-audit --mode audit-only --quick
/rust-unsafe-code-exorcist /tmp/dep-v2 --audit-dir /tmp/dep-v2/.unsafe-audit --mode audit-only --quick

# Diff
bash scripts/diff-audit-vs-baseline.sh /tmp/dep-v1/.unsafe-audit /tmp/dep-v2/.unsafe-audit /tmp/dep-v2/.unsafe-audit/delta-from-v1
```

The delta report includes:
- **Soundness regressions** — sites that got WORSE (A in v1, A in v2 with stale SAFETY; or B in v1, B in v2 with worse perf).
- **Soundness improvements** — sites that got BETTER (C refactor landed; A hardened SAFETY).
- **New unsafe** — caller-side proof obligations the user must now handle.
- **Net recommendation** — adopt / don't adopt / adopt-with-mitigation.

### Regression-detection mode

User wants to know: did our recent release accidentally regress soundness?

```bash
# Audit last release + HEAD
git -C <project> checkout v1.4.0
/rust-unsafe-code-exorcist <project> --audit-dir <project>/.unsafe-audit-v1.4 --mode audit-only --quick

git -C <project> checkout main
/rust-unsafe-code-exorcist <project> --audit-dir <project>/.unsafe-audit-head --mode audit-only --quick

bash scripts/diff-audit-vs-baseline.sh <project>/.unsafe-audit-v1.4 <project>/.unsafe-audit-head <project>/.unsafe-audit-head/delta-from-v1.4
```

If any soundness regression: file `regression-<id>` bead. The user decides whether to release-or-fix.

### Migration-planning mode

User is migrating from `dep-a` (their current dep) to `dep-b` (alternative). Audit both; surface the soundness-shape differences.

```bash
/rust-unsafe-code-exorcist /tmp/dep-a-clone --audit-dir /tmp/dep-a-clone/.unsafe-audit --mode audit-only --quick
/rust-unsafe-code-exorcist /tmp/dep-b-clone --audit-dir /tmp/dep-b-clone/.unsafe-audit --mode audit-only --quick

bash scripts/diff-audit-vs-baseline.sh /tmp/dep-a-clone/.unsafe-audit /tmp/dep-b-clone/.unsafe-audit /tmp/dep-b-clone/.unsafe-audit/delta-from-dep-a --label-a "dep-a v1.0" --label-b "dep-b v2.0"
```

The migration plan uses the delta as input.

---

## What the delta script computes

Per `scripts/diff-audit-vs-baseline.sh`:

### 1. Site-level diff

```
ADDED:    sites in B inventory but not in A inventory.
REMOVED:  sites in A inventory but not in B inventory.
MODIFIED: sites in both inventories but with changed source_excerpt OR kind.
```

The diff pairs sites by `(file, line range, kind)`. A site that moved lines but kept the same source is "MOVED" (a sub-type of MODIFIED).

### 2. Classification diff

For sites in both versions:

```
RECLASSIFIED:  bucket changed (A→B, A→C, B→C, etc.).
```

Each reclassification is interesting:
- A→B: site was strictly-unavoidable in v1; got reclassified to perf-only in v2. Probably means a new safe alternative emerged.
- A→C: site got refactored. Strong positive signal.
- C→B: site was supposed to be refactored but reclassified as perf-only instead. Mild positive or neutral.
- C→A: site was supposed to be refactored but reclassified as strictly unavoidable. Worth investigating; possibly a missed pattern.

### 3. Soundness-surface diff

```
SURFACE_EXPANDED:  new pub→unsafe paths.
SURFACE_REDUCED:   pub→unsafe paths that closed.
```

Surface expansion is a yellow-flag; reduction is green.

### 4. Geiger delta + harness delta

```
GEIGER:  count_A → count_B (delta)
HARNESS: result_A → result_B (per tool)
```

### 5. SAFETY-comment drift

For each (A) site in both versions: did the SAFETY comment change?

```
SAFETY_REFINED:  comment more specific (good).
SAFETY_DRIFTED:  comment less specific or stale (bad).
SAFETY_DELETED:  comment removed entirely (very bad).
```

---

## The diff report

`<delta-dir>/diff-report.md`:

```markdown
# Audit Diff Report

- **Version A.** <label-a> (commit <hash-a>, audited <date>)
- **Version B.** <label-b> (commit <hash-b>, audited <date>)
- **Generated.** <YYYY-MM-DD HH:MM UTC>

## Summary

| Metric | A | B | Delta |
|--------|---|---|-------|
| Total unsafe sites | <a> | <b> | <delta> |
| (A) STRICTLY_UNAVOIDABLE | <a_A> | <b_A> | <delta_A> |
| (B) PERF_ONLY | <a_B> | <b_B> | <delta_B> |
| (C) REFACTORABLE (open) | <a_C> | <b_C> | <delta_C> |
| Soundness surface entries | <a_s> | <b_s> | <delta_s> |
| Geiger count | <a_g> | <b_g> | <delta_g> |
| `verify.sh` | <a_v> | <b_v> | <delta_v> |

## Net recommendation

**<ADOPT | ADOPT-WITH-MITIGATION | DON'T-ADOPT | INVESTIGATE>**

Rationale: <paragraph synthesizing the deltas>

## Sites added in B

| Site | File | Class | Risk | Notes |
|------|------|-------|------|-------|
| ... |

## Sites removed in B (refactored away in v2)

| Site | File | Was in A as | Notes |
|------|------|-------------|-------|
| ... |

## Reclassifications

| Site | File | v1 class | v2 class | Direction | Notes |
|------|------|---------|---------|-----------|-------|
| ... |

## SAFETY-comment drift

| Site | Status | Note |
|------|--------|------|
| ... |

## Soundness-surface deltas

| Surface entry | v1 | v2 |
|---------------|----|----|
| `crate::Foo::bar` | EXISTS | EXISTS |
| `crate::Baz::quux` | NEW (added in v2) | — |
| ... |

## Action items (if adopting v2)

1. **Address new soundness obligations.** Sites added in B that are reachable from our pub API.
2. **Verify SAFETY-drift.** Sites with drifted SAFETY comments — manually verify the claim is still true.
3. **Re-baseline.** Once v2 is adopted, re-run baseline audit so continuous mode picks up.

## Diff artifacts

- Per-site diff JSON: <delta-dir>/site-diffs.json
- Raw inventory A: <audit-dir-a>/unsafe-inventory.jsonl
- Raw inventory B: <audit-dir-b>/unsafe-inventory.jsonl
```

---

## Pairing heuristics

Pairing sites between two audits requires care because sites move (line numbers change; functions rename).

The script uses a multi-pass pairing:

1. **Exact match.** Same `(file, line_start, kind, source_excerpt[0:100])`. Strong match.
2. **Line-fuzzy match.** Same `(file, kind, source_excerpt[0:200])` within ±30 lines. Likely the same site, moved.
3. **Source-text match.** Same `source_excerpt[0:200]` anywhere in the file. Possible rename / function-extraction.
4. **No match.** Site is unpaired → ADDED or REMOVED.

For sites with manually-curated `id`-mappings (e.g., user has tagged "this is the same site"), the manual mapping overrides.

---

## Quick mode

For fast comparison without the full audit (e.g., used in continuous-mode regression checks), the differential can run with `--quick`:

- Skips Phase 5 plan-drafting + Phase 7 fresh-eyes.
- Just enumerates + classifies + diffs.
- Takes ~5-10 minutes per version.

The diff report is less rich (no plan-level reclassifications) but covers the key deltas.

---

## Acceptance signal

A differential audit passes when:

1. Both versions have a complete inventory.
2. The pairing heuristic produces stable matchups (>90% of sites paired).
3. The diff report categorizes every delta (no "unknown" entries).
4. The net recommendation is supported by the data.
5. Action items are concrete + bounded.

The diff IS the deliverable.
