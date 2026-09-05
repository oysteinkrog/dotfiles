# CI-TRIPWIRE.md — Continuous Compliance Verification

<!-- TOC: Cadence | Tripwire mode contract | GitHub Actions example | Cron + /loop | systemd timer | Notification integrations (Slack/email/GH issue) | Pre-merge audit hook | Convergence dashboard | Tripwire failure modes | What to do when tripwire fires | Metrics worth alerting on -->

Once an audit converges, the audit dir becomes a **tripwire**: a baseline against which every subsequent state of the project can be checked. Periodic re-verification catches regressions early — agents start drifting, false-closed rate creeps up, the bead graph quietly desynchronizes from reality.

> **Operating principle.** The first audit takes hours. Every subsequent tripwire pass takes minutes. The compounding value is that you find drift *while it's small*, not after 50 beads have accumulated.

---

## Cadence recommendations

| Project state | Cadence | Mode |
|---------------|---------|------|
| Active development (multiple beads/day) | Daily | Tripwire |
| Steady-state development | Weekly | Tripwire |
| Maintenance | Monthly | Standard |
| Pre-release | Per-release | Comprehensive |
| Post-incident | Once after the incident bead lands | Single-bead on the incident bead |

---

## Tripwire mode contract

The tripwire mode (`mode=tripwire` in manifest.json) is designed for autonomous CI execution:

- **No human input required.**
- **Exit code is the gate**: `0` = converged; non-zero = regression detected.
- **No bead writes** (policy auto-set to `report-only`).
- **No test execution** (Phase 4 skipped — too slow for daily CI; rely on the standard test pipeline for that).
- **Outputs**: REPORT.md, convergence.json, and a one-line summary suitable for Slack/email.

```bash
# Exit code semantics for CI
0   converged: no new false-closed, max delta within ±10
1   not converged: investigate
2   bead store unhealthy: hand off to /fixing-beads-problems
3   audit infrastructure broken: investigate the audit itself
```

---

## GitHub Actions example

```yaml
# .github/workflows/beads-tripwire.yml
name: Beads Compliance Tripwire

on:
  schedule:
    - cron: '0 6 * * *'   # Daily at 06:00 UTC
  workflow_dispatch:

jobs:
  tripwire:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # Need full history for git_xref

      - name: Restore audit dir
        uses: actions/cache@v4
        with:
          path: ${{ github.workspace }}/beads_compliance_audit
          key: beads-audit-${{ github.repository_id }}

      - name: Install br + bv + jq
        run: |
          curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh | bash
          curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh | bash

      - name: Install jsm + the audit skill
        run: |
          curl -fsSL https://jeffreys-skills.md/install.sh | bash
          jsm install beads-compliance-and-completion-verification

      - name: Run tripwire pass
        id: audit
        run: |
          ~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh \
            "${{ github.workspace }}" \
            --threshold 700 \
            --policy report-only
        continue-on-error: true

      - name: Upload audit artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: beads-audit-${{ github.run_number }}
          path: ${{ github.workspace }}/beads_compliance_audit/

      - name: Save audit dir back to cache
        if: always()
        uses: actions/cache/save@v4
        with:
          path: ${{ github.workspace }}/beads_compliance_audit
          key: beads-audit-${{ github.repository_id }}

      - name: Fail if not converged
        if: steps.audit.outcome == 'failure'
        run: |
          AUDIT_DIR="${{ github.workspace }}/beads_compliance_audit"
          echo "::error::Beads compliance audit detected regression. See REPORT.md for details."
          head -25 "$AUDIT_DIR/REPORT.md"
          exit 1
```

---

## Cron + /loop example (local / personal machine)

```bash
# Run via Claude Code's /loop skill every 4 hours
# (in your Claude Code session)
/loop 4h /beads-compliance-and-completion-verification re-verify in tripwire mode on /data/projects/myproject

# Or via system cron
0 */4 * * * cd /data/projects/myproject && /home/ubuntu/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh . --threshold 700 --policy report-only 2>&1 | tee /tmp/audit-tripwire-$(date -u +\%Y\%m\%d-\%H).log
```

---

## systemd timer example (long-running server)

```ini
# /etc/systemd/system/beads-tripwire@.service
[Unit]
Description=Beads compliance tripwire for %i

[Service]
Type=oneshot
WorkingDirectory=/data/projects/%i
ExecStart=/home/ubuntu/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh /data/projects/%i --threshold 700 --policy report-only
StandardOutput=append:/var/log/beads-tripwire/%i.log
StandardError=append:/var/log/beads-tripwire/%i.log

# /etc/systemd/system/beads-tripwire@.timer
[Unit]
Description=Daily beads compliance tripwire for %i

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

Enable per project:

```bash
sudo systemctl enable --now beads-tripwire@frankensqlite.timer
sudo systemctl enable --now beads-tripwire@beads_rust.timer
```

---

## Notification integrations

The tripwire's exit code drives notifications.

### Slack (via webhook)

```bash
# Append to run-pass.sh wrapper for tripwire mode:
EXIT_CODE=$?
if [ "$EXIT_CODE" -ne 0 ] && [ -n "${SLACK_WEBHOOK:-}" ]; then
  REPORT="$AUDIT_DIR/REPORT.md"
  SUMMARY=$(awk '/Executive summary/,/^## / { if (!/^## Executive/) print }' "$REPORT" | head -10)
  curl -X POST "$SLACK_WEBHOOK" -H 'Content-Type: application/json' --data "$(jq -n \
    --arg text "🚨 Beads compliance regression in $PROJECT" \
    --arg summary "$SUMMARY" \
    '{text: $text, blocks: [{type: "section", text: {type: "mrkdwn", text: $summary}}]}')"
fi
```

### Email (via msmtp/sendmail)

```bash
if [ "$EXIT_CODE" -ne 0 ]; then
  mail -s "Beads compliance regression: $PROJECT" you@example.com < "$AUDIT_DIR/REPORT.md"
fi
```

### GitHub issue

```bash
if [ "$EXIT_CODE" -ne 0 ]; then
  gh issue create \
    --title "Beads compliance regression detected ($(date +%Y-%m-%d))" \
    --body-file "$AUDIT_DIR/REPORT.md" \
    --label "audit,regression"
fi
```

---

## Pre-merge audit hook

Beyond periodic tripwire, run the audit on a **single bead** as part of the PR pipeline that closes that bead:

```yaml
# .github/workflows/pre-merge-bead-audit.yml
name: Pre-merge bead audit

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  audit-closing-beads:
    if: contains(github.event.pull_request.title, 'closes bd-') ||
        contains(github.event.pull_request.body, 'closes bd-')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Extract closed bead IDs from PR
        id: extract
        run: |
          IDS=$(echo "${{ github.event.pull_request.title }} ${{ github.event.pull_request.body }}" \
                | grep -oP 'bd-[a-z0-9]+' | sort -u)
          echo "ids=$IDS" >> $GITHUB_OUTPUT

      - name: Run single-bead audit per closed bead
        run: |
          for ID in ${{ steps.extract.outputs.ids }}; do
            ~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh \
              . --threshold 700 --policy report-only --mode single-bead --bead "$ID"
            SCORE=$(jq -r ".score" .audit/passes/*/beads/"$ID"/score-summary.json)
            if [ "$SCORE" -lt 700 ]; then
              echo "::error::Bead $ID would be false-closed by this PR (score: $SCORE)"
              exit 1
            fi
          done
```

This **prevents the false-close from happening in the first place**: if the bead would score below threshold once merged, the PR is blocked.

---

## Convergence dashboard

Over time, the `trends.md` file becomes a real dashboard. A simple post-pass step generates a chart:

```bash
# scripts/dashboard.py emits an HTML chart from trends.md
python3 ~/.claude/skills/beads-compliance-and-completion-verification/scripts/dashboard.py \
  "$AUDIT_DIR" \
  --output "$AUDIT_DIR/dashboard.html"

# View
xdg-open "$AUDIT_DIR/dashboard.html"
```

The dashboard shows:
- Score median over passes (line chart).
- False-closed count over passes (bar chart).
- Per-bead trajectories (small multiples for the worst offenders).
- Per-agent close-quality (if `closed_by_session` is populated).
- Convergence indicator (green check / red exclaim).

---

## Tripwire failure modes

| Failure | Cause | Action |
|---------|-------|--------|
| Exit 1, no new false-closed, max delta < 10 | Convergence delta is too tight; bumping noise | Loosen `delta_threshold` in rubric.md |
| Exit 1, multiple new false-closed every pass | Real drift; agents are status-flipping | Investigate `closed_by_session` and intervene |
| Exit 2, br doctor fails | Bead store corruption | `/fixing-beads-problems` |
| Exit 3, audit script crashes | Audit infrastructure broken (br version drift, jq missing, etc.) | Re-bootstrap; check `manifest.json#tools` for missing entries |
| Tripwire takes > 30 min in tripwire mode | Phase 4 was accidentally enabled | Confirm `mode=tripwire` in manifest |
| GitHub Actions cache miss every run | Cache key changed | Pin `key: beads-audit-${{ github.repository_id }}-${{ runner.os }}` |
| Slack notification fires but report is empty | Bead store drift but no actual code change | This is OK — bead-graph drift IS the regression |

---

## What to do when tripwire fires

1. **Don't panic.** A tripwire failure is a *signal*, not a *fix order*.
2. **Read the convergence.json#next_pass_tasks**.
3. **Read the new false-closed list.** Compare to prior. New entries are the suspects.
4. **Investigate the most recent commits to the project**. Cross-reference with closed-since-prior-pass beads.
5. **Run a Standard or Comprehensive mode pass** (not tripwire) to get the full picture.
6. **Remediate** per `REMEDIATION-PATTERNS.md`.
7. **Re-run tripwire** to confirm the regression is resolved.

---

## Tripwire metrics worth alerting on

| Metric | Alert threshold | Why |
|--------|----------------:|-----|
| `convergence.json#new_false_closed_beads.length` | > 0 | A bead was just falsely closed |
| `convergence.json#max_score_delta_observed` | > 30 | Significant regression on at least one bead |
| `manifest.json#bead_counts.closed` weekly delta | > 50 | Spike in close rate; audit may be lagging |
| `REPORT.md` median score | < prior_median - 20 | Project-wide quality drop |
| Tripwire exit time | > 10 min in tripwire mode | Performance regression in audit infrastructure |
