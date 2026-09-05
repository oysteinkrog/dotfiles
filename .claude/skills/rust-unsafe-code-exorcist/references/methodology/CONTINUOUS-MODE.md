# CONTINUOUS-MODE.md — Drift Detection + Ongoing Audit

The skill's most accretive mode. A one-shot audit is a snapshot; continuous mode turns it into an ongoing partnership with the project.

---

## The cadence

```
Baseline audit (one-shot, `audit-only` or `audit-and-refactor`)
       │
       ▼
   <audit-dir>/baseline/   (snapshotted inventory, classification, harness state)
       │
       ▼
   Nightly cron:  scripts/cron-drift-check.sh <audit-dir> <project>
       │
       ▼
   <audit-dir>/drift/<date>/   (delta vs baseline)
       │
       ▼
   If drift detected:
     - File drift-<N> beads for new unsafe sites, modified unsafe sites, geiger increases, or harness regressions
     - Write drift/<date>/summary.md with links to diff.json, verify.log, and the new inventory
   If clean:
     - Append <date> to drift/clean-streak.log
       │
       ▼
   Weekly: emit <audit-dir>/drift/weekly-report.md (one page; the user reads it)
   Monthly: emit <audit-dir>/drift/monthly-report.md (longer; for the SECURITY.md update cadence)
```

---

## What "drift" means

A finding is drift iff:

| Signal | Drift type |
|--------|-----------|
| New `unsafe` site that didn't exist at baseline | `drift-new-site` |
| Existing site's SAFETY comment changed | `drift-safety-comment-changed` |
| Existing site's enclosing function changed | `drift-context-changed` |
| New `pub` item reaches an unsafe that wasn't on the soundness surface | `drift-soundness-surface-expanded` |
| `cargo geiger` count increased | `drift-geiger-up` |
| `cargo geiger` count decreased (good — refactor landed) | `drift-geiger-down` |
| Toolchain version moved (nightly bumped) | `drift-toolchain-pin-changed` |
| New dep added whose geiger > 0 | `drift-new-unsafe-dep` |
| `verify.sh` started failing where it was green | `drift-harness-regression` |
| `verify.sh` started passing where it was failing | `drift-harness-recovery` |

Each drift type triggers a different downstream action — see below.

---

## Configuration

Per-project config at `<audit-dir>/continuous-mode.toml`:

```toml
[continuous]
enabled = true
cadence = "nightly"   # one of: "nightly", "weekly", "on-push", "on-pr"

[continuous.thresholds]
geiger_increase_alarm = 1           # reports/CI policy; cron reports any positive delta
geiger_decrease_log_only = true     # decreases are logged but don't fire alarms
soundness_surface_expanded_alarm = 1  # surface-analysis policy; cron does not compute it directly
toolchain_pin_movement_alarm = true   # full-audit policy; cron does not inspect pins directly

[continuous.notifications]
channel = "github-issue"            # or "mail", "slack", "stdout"
gh_label = "soundness:drift"
mail_to = ""
slack_webhook = ""

[continuous.gates]
fail_on_geiger_regression = true    # CI fails if PR's geiger > main's
fail_on_new_unsafe_without_safety_comment = true
fail_on_soundness_surface_expansion = false  # log only; some projects expand intentionally

[continuous.budget]
max_unsafe_sites = 250              # reports/CI policy; cron does not gate on it directly
max_unsafe_in_safe_only_path = 0    # safe-only feature must stay unsafe-free
```

This file is the project's policy document. The current cron script honors `enabled = false` directly and files beads for the drift signals it can compute from the inventory diff, geiger output, and `verify.sh`; the remaining fields document the intended CI/reporting policy for the audit maintainers and templates.

---

## The drift script

`scripts/cron-drift-check.sh <audit-dir> <project>`:

```bash
1. Re-enumerate the project (scripts/enumerate-unsafe.sh).
2. Diff the new inventory vs <audit-dir>/baseline/unsafe-inventory.jsonl.
3. Re-run verify.sh; record pass/fail in <audit-dir>/drift/<date>/verify.log.
4. Compare cargo-geiger totals against the baseline when geiger data exists.
5. For detected drift conditions (`added`, `modified`, positive geiger delta, harness failure), attempt to file drift-<N> beads via br create from the audit dir.
6. Write <audit-dir>/drift/<date>/summary.md with drift-event counts, bead-filing counts, and links to diff.json, verify.log, and the new inventory.
7. Append to <audit-dir>/drift/clean-streak.log only on days with zero drift events.
```

Run nightly via cron, systemd timer, GitHub Actions schedule, or `cargo make` task.

---

## The drift bead shape

Drift beads follow this template:

```
br create --title "drift-<N>: <one-line summary> [DRIFT]" \
          --type bug --priority 2 \
          --description "$(cat <<'EOF'
**Detected.** $(date -u +%Y-%m-%dT%H:%M:%SZ)

**Drift type.** drift-new-site

**Change since baseline.**
- Baseline date: <date>
- Baseline commit: <hash>
- Drift commit: <hash>
- Sites added: 3 (site-2031, site-2032, site-2033)
- Sites modified: 1 (site-2034)
- Sites removed: 0

**Affected files.** src/new_feature.rs (added), src/foo.rs (modified)

**Recommendation.** Spawn a scoped audit for the new sites:
   /rust-unsafe-code-exorcist --mode harden-incident --scope drift-1

**Cross-references.**
- Baseline inventory: <audit-dir>/baseline/unsafe-inventory.jsonl
- Drift summary: <audit-dir>/drift/<date>/summary.md
- Drift diff: <audit-dir>/drift/<date>/diff.json
EOF
)"
```

The drift bead doesn't classify the new sites — it triggers a SCOPED FOLLOW-UP audit. The skill stays out of "I'll just classify this" mode by default.

---

## Weekly + monthly reports

Auto-generated from the drift logs.

**Weekly report** (one page; `<audit-dir>/drift/weekly-<date>.md`):

```markdown
# Weekly drift report — <date_range>

## Summary
- Total drift events: 12
- New unsafe sites: 3 (filed: drift-1, drift-2, drift-3)
- Closed sites: 5 (from in-progress refactors)
- Soundness surface delta: +0 (no new pub→unsafe paths)
- Toolchain pins: stable (no nightly bumps)
- Geiger count: 247 → 245 (-2)
- Harness: green all 7 days

## Top items needing attention
1. drift-1: new unsafe in src/auth.rs (P0 — soundness surface)
2. drift-2: new unsafe in src/cache.rs (P2 — internal)
3. drift-3: new unsafe in src/parser.rs (P1 — pub-API-reachable)

## Compared to last week
- Soundness debt: -3 (good direction)
- Refactor velocity: 5 (C) closed; on track for 20/month

## Action items
- Address P0 drift-1 this week.
- Continue (C) cluster from baseline audit.
```

**Monthly report** (`<audit-dir>/drift/monthly-<date>.md`):

A longer summary suitable for stakeholder communication / SECURITY.md update. Includes trend lines (geiger over time, harness pass rate, refactor velocity).

---

## Integration with the bead workflow

Drift beads integrate naturally with `br ready` / `bv --robot-triage`:

```bash
br ready --json | jq '.[] | select(.title | contains("[DRIFT]")) | .id'
```

The orchestrator surfaces drift beads alongside refactor beads. The user prioritizes via the risk score (see [RISK-SCORING.md](RISK-SCORING.md)).

---

## What continuous mode is NOT

- **Not a replacement for the periodic full audit.** Continuous mode catches drift; periodic audits catch accumulated issues + revisit classification decisions.
- **Not an autonomous-mutation system.** Drift beads are filed but NOT auto-implemented. The user (or a Phase 8.5 active-checkout implementer) decides what to land.
- **Not a CI gate by default.** The CI integration ([CI-INTEGRATION.md](CI-INTEGRATION.md)) is a separate, opt-in choice. Continuous mode can run alongside CI gates or by itself.

---

## Bootstrapping continuous mode

After a baseline audit completes:

```bash
# 1. Snapshot the baseline
mkdir -p <audit-dir>/baseline
cp -r <audit-dir>/{unsafe-inventory.jsonl,audit/classification,phase1} <audit-dir>/baseline/
cp <audit-dir>/geiger-after.json <audit-dir>/baseline/cargo-geiger.json

# 2. Configure
cp assets/continuous-mode.toml.template <audit-dir>/continuous-mode.toml
# (edit the toml; set channel, thresholds, budgets)

# 3. Schedule
crontab -e
# Add: 0 6 * * * /path/to/scripts/cron-drift-check.sh /path/to/audit-dir /path/to/project

# 4. (Optional) Add the GH Actions workflow
cp assets/gh-actions-auditor.yml.template <project>/.github/workflows/soundness-drift.yml
```

The first cron run captures any drift since the baseline. From there, the cadence sustains.

---

## When to disable

Continuous mode is opt-in. Disable when:

- The project is in a refactor wave (lots of drift expected; not actionable yet).
- The project is in maintenance mode (low velocity; quarterly audits suffice).
- The audit dir has been archived (the project moved to a new audit).

The config's `enabled = false` switches off the cron + the notifications; the data is preserved.

---

## Acceptance signal

Continuous mode is healthy when:

1. The cron runs daily without failure (check `<audit-dir>/drift/cron.log`).
2. Drift beads are filed within 24h of the drift event.
3. The weekly report is auto-generated; the user reviews it.
4. The soundness-debt dashboard reflects the current state.
5. The clean-streak log shows long runs of "no drift" punctuated by handled drift events.

The skill's value compounds over time.
