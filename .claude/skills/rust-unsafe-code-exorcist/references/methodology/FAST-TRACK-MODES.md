# FAST-TRACK-MODES.md — Quick Variants

The base 7 modes ([OPERATING-MODES.md](OPERATING-MODES.md)) cover the full audit lifecycle. Fast-track variants trade depth for speed when you don't need the full discipline.

---

## When to use a fast-track

| Situation | Fast-track |
|-----------|-----------|
| "Just enumerate unsafe; I'll classify myself." | `--mode triage` |
| "Spot-check a dep before adopting." | `--mode triage --target <dep>` |
| "Quick audit before a sprint plan." | `--mode audit-only --quick` |
| "Just regenerate the dashboard." | `--mode dashboard-only` |
| "Just diff vs last week." | `--mode drift-check` |
| "Just run the harness." | `--mode verify-only` |

When NOT to fast-track:
- Pre-release: use `--mode pre-release-soundness-gate` (full).
- Incident response: use `--mode harden-incident` (full).
- First audit of a project: use `--mode audit-only` (full).

---

## `triage` — 60-second mode

Enumerate + risk-score. No write-ups, no classification, no plans. Just "where's the unsafe and what's high-risk."

```bash
# /rust-unsafe-code-exorcist <project> --mode triage
```

Equivalent to:

```bash
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"
$SKILL/scripts/enumerate-unsafe.sh <project> <audit-dir>
node $SKILL/scripts/generate-inventory.mjs <audit-dir>
# (skip classification)
# Bootstrap minimal phase0_scope_decision.md
node $SKILL/scripts/compute-risk-score.mjs <audit-dir>
```

Output:
- `<audit-dir>/unsafe-inventory.jsonl` — the list.
- `<audit-dir>/risk-scores.json` — risk-scored.
- `<audit-dir>/audit/synthesis/risk-summary.md` — top sites + Pareto recommendation.

Time: 60–120 seconds for a typical project.

Use when: you want to know IF you have a soundness problem before committing to a full audit.

---

## `audit-only --quick` — 10-minute mode

Skip Phase 5 detailed planning + Phase 7 fresh-eyes detailed review + Phase 10 maintainer-empathy. Just produce the classification + the bead skeletons.

```bash
# /rust-unsafe-code-exorcist <project> --mode audit-only --quick
```

Trade-off:
- Classification quality is lower (single-pass Phase 4 instead of iterative).
- No per-site detailed plans.
- No equivalence-prover tests authored.
- No Phase 7 toolchain harness.

Output:
- Full inventory.
- Single-pass classification (lower confidence).
- Bead skeletons (titles only).
- No verify.sh.

Time: ~10 min for small project, ~30 min for medium.

Use when: you need the audit's STRUCTURE quickly but will refine later.

---

## `dashboard-only` mode

Regenerate the soundness-debt dashboard from existing audit data. Useful for periodic refresh without re-running the audit.

```bash
# /rust-unsafe-code-exorcist <audit-dir> --mode dashboard-only
```

Equivalent to:

```bash
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"
node $SKILL/scripts/compute-risk-score.mjs <audit-dir>
# Regenerate dashboard from updated risk-summary + git log + cron logs
# (subagent: dashboard-regenerator; reads existing artifacts; rewrites dashboard)
```

Time: ~30 seconds.

Use when: stakeholder asked for the latest dashboard; nothing else changed.

---

## `drift-check` mode

Just run today's drift check. No new audit, no full enumeration; only the delta vs baseline.

```bash
# /rust-unsafe-code-exorcist <audit-dir> --mode drift-check
```

Equivalent to:

```bash
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"
bash $SKILL/scripts/cron-drift-check.sh <audit-dir> <project>
```

Time: 5–10 minutes (enumerate + diff + harness re-run + (conditional) bead filing).

Use when: you want a manual drift check rather than waiting for the cron.

---

## `verify-only` mode (built-in)

Already covered in [OPERATING-MODES.md](OPERATING-MODES.md). Builds the CI harness from existing audit data; doesn't redo the audit itself.

---

## Comparing modes by time + output

| Mode | Time | Inventory | Classification | Plans | Verify | Beads | Dashboard | PR-ready |
|------|------|-----------|----------------|-------|--------|-------|-----------|----------|
| `triage` | 60s | ✓ | — | — | — | — | partial | — |
| `dashboard-only` | 30s | (reuses) | — | — | — | — | ✓ | — |
| `drift-check` | 5-10m | (delta only) | — | — | partial | drift only | partial | — |
| `audit-only --quick` | 10-30m | ✓ | single-pass | sketch | — | skeleton | partial | — |
| `audit-only` (full) | hours | ✓ | iterative | ✓ | ✓ | ✓ | ✓ | — |
| `audit-and-refactor` | hours+ | ✓ | iterative | ✓ | ✓ | ✓ | ✓ | ✓ |
| `pre-release-soundness-gate` | day+ | ✓ | iterative + adversarial | ✓ | ✓ + extra strict | ✓ | ✓ | ✓ |

---

## Promoting from fast-track to full

Each fast-track produces a subset of the full audit's artifacts. To promote:

```bash
# Start with triage
# /rust-unsafe-code-exorcist <project> --mode triage

# Decide the result warrants a full audit; promote
# /rust-unsafe-code-exorcist <project> --mode audit-only --resume <existing-audit-dir>
```

The full audit reuses the triage's inventory + risk scores, then runs Phases 2-10. Time: full audit time MINUS the time spent in the triage step.

---

## Continuous-mode integration

The fast-tracks compose with continuous mode:

- **Nightly cron**: `drift-check` mode runs.
- **Weekly schedule**: `dashboard-only` mode regenerates + emails.
- **Monthly**: `triage` mode on the project's biggest sub-crate (if workspace) for trend tracking.
- **Pre-release**: `pre-release-soundness-gate` (full).

---

## Anti-patterns

- **"Just always use triage."** Fine for spot checks; bad for production. The classification is the audit's value; triage skips it.
- **"audit-only --quick before incident response."** Incidents need full. The --quick mode's lower-confidence classification can miss the failure mode.
- **"dashboard-only forever."** Dashboard reflects last-audit data. Without periodic re-audit, the dashboard is fiction.

---

## Acceptance signal

A fast-track is healthy when:

1. It produces the documented subset of artifacts.
2. The audit dir's `mode` field reflects the fast-track variant.
3. The user is explicit about what they're NOT getting (e.g., "no full classification; just triage").
4. The promotion path is clear (when to re-run full).
