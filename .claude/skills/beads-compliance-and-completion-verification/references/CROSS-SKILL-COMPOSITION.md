# CROSS-SKILL-COMPOSITION.md — Composing Audit With Other Skills

<!-- TOC: The 5 composition patterns | Audit + reality-check | Audit + security-audit-for-saas | Audit + post-mortem chain | Audit + idea-wizard ambition rounds | Audit + multi-agent-swarm-workflow | Worked compositions -->

> The audit's value compounds when chained with other skills. This file documents 5 high-value compositions.

---

## The 5 composition patterns

### Pattern A: Audit + reality-check (alignment + truthfulness)

`/reality-check-for-project` answers "are we shipping the README's promises?" This skill answers "are the beads we said we shipped actually shipped?"

Together: both *aspirational* and *empirical* check.

```bash
# Step 1: reality-check identifies vision gaps
> Run /reality-check-for-project on /data/projects/myproject
# Outputs Vision Checklist + bead coverage gaps

# Step 2: This skill verifies the closed beads
> Run beads-compliance-and-completion-verification on /data/projects/myproject
# Outputs false-closed list

# Step 3: Cross-reference
# Vision-gap-no-bead OR vision-gap-but-bead-is-false-closed → high priority
```

Combined output: a "true reality" matrix:
| Vision goal | Has bead? | Bead closed? | Bead actually done? |
|-------------|:---------:|:------------:|:-------------------:|
| Auth | ✓ | ✓ | ✓ → Truly done |
| Billing | ✓ | ✓ | ✗ → False-closed; high-pri remediation |
| Reports | ✗ | n/a | n/a → Vision gap; create bead |

---

### Pattern B: Audit + security-audit-for-saas (defense in depth)

`/security-audit-for-saas` finds attack surfaces in current code. This skill verifies that beads claiming to fix security issues actually did.

```bash
# Step 1: security-audit finds vulnerable surfaces
> Run /security-audit-for-saas on /data/projects/myproject
# Outputs vulnerability list

# Step 2: For each vulnerability, find the bead that should have prevented it
br --db .beads/*.db search "CSRF" --json > /tmp/csrf-beads.json
# Or use cass: cass search "CSRF closed" --robot

# Step 3: Audit those beads in single-bead mode
for bead in $(jq -r '.[].id' /tmp/csrf-beads.json); do
  ~/.../scripts/run-pass.sh /data/projects/myproject \
    --mode single-bead --bead-id "$bead" --threshold 800
done

# Step 4: Cross-reference vulnerability ↔ bead score
```

If `security-audit-for-saas` says "you have CSRF risk on /api/admin/X" AND this skill says "the CSRF bead bd-csrf-mw scored 580 (false-closed)" — that's the smoking gun. The bead was closed but the protection isn't actually in place.

---

### Pattern C: Audit + post-mortem chain

When a production incident happens, chain:

1. `/security-audit-for-saas` (or appropriate per-domain auditor) confirms the incident's class.
2. This skill's POST-MORTEM-MODE finds beads that should have prevented it.
3. CONTRIBUTING-PATTERNS.md flow adds the new theater pattern to the catalog.
4. Next pass on this and other projects catches the same class going forward.

The chain converts each incident into a permanent improvement to the audit's vocabulary.

---

### Pattern D: Audit + idea-wizard ambition rounds

After Phase 9 creates completion-debt beads, invoke `/idea-wizard` ambition rounds to make those beads better:

```bash
# Round 1: "comprehensive" pass
> /idea-wizard apply 3 ambition rounds to all beads with label="audit-debt"

# Round 2: "test depth" pass
> /idea-wizard "for each audit-debt bead, what testing techniques from
   /testing-fuzzing, /testing-conformance-harnesses, /testing-metamorphic
   would catch the original gap if applied? Add those test requirements."

# Round 3: "cross-reference" pass
> /idea-wizard "for each audit-debt bead, what other beads silently depend on
   it being correct? Add those as `depends_on` reverse edges."
```

The outcome: completion-debt beads are 2-3× richer than the audit alone produces.

---

### Pattern E: Audit + multi-agent-swarm-workflow

For very large projects (1000+ closed beads), use `/multi-agent-swarm-workflow` to fan out the audit across many panes:

```bash
# Spawn an audit swarm
ntm spawn audit-swarm-myproject \
  --agents claude-code,codex,gemini \
  --weights 0.6,0.3,0.1 \
  --pane-count 12 \
  --command-template '~/.claude/skills/.../scripts/run-pass.sh {repo} \
    --threshold 700 --policy report-only --mode single-bead --bead-id {bead}'

# Each pane handles a slice of the closed-bead universe
# Orchestrator collects results, runs Phase 7-10 itself
```

This is Squad / Swarm tier — only worth it for truly large workspaces.

---

## Worked composition: SOC2 quarterly evidence collection

The full chain:

```bash
# 1. Snapshot project state
COMMIT_SHA=$(git -C /data/projects/myproject rev-parse HEAD)

# 2. Pre-flight checks
~/.claude/skills/.../scripts/preflight.sh /data/projects/myproject || exit 1

# 3. Time-machine audit AS-OF the SOC2 cutoff date (e.g., end of last quarter)
LAST_QUARTER_END=$(date -d "last quarter" +%Y-%m-%d)
QUARTER_SHA=$(git -C /data/projects/myproject log --until "$LAST_QUARTER_END" --format=%H | head -1)

~/.claude/skills/.../scripts/run-pass.sh /data/projects/myproject \
  --threshold 800 --policy report-only --mode time-machine \
  --as-of "$QUARTER_SHA"

# 4. Apply security-audit-for-saas to verify the audit caught security beads
> Use /security-audit-for-saas to scan the project; cross-reference with audit's false-closed list

# 5. Build the SOC2 evidence pack
COMPLIANCE_GPG_KEY=audit@example.com \
  ~/.claude/skills/.../scripts/build-compliance-pack.sh \
  /data/projects/myproject/beads_compliance_audit \
  $(ls /data/projects/myproject/beads_compliance_audit/passes/ | sort | tail -1) \
  soc2

# 6. Upload to immutable storage
aws s3 cp myproject__compliance__soc2__*.zip s3://compliance-evidence/SOC2-2026-Q1/ \
  --object-lock-mode COMPLIANCE \
  --object-lock-retain-until-date "$(date -u -d '+5 years' --iso-8601=seconds)"

# 7. Notify auditor with download link
echo "SOC2 Q1 evidence pack ready: s3://compliance-evidence/SOC2-2026-Q1/" \
  | mail -s "SOC2 Q1 evidence" auditor@external-firm.com
```

The chain: pre-flight + time-machine audit + security cross-reference + signed pack + immutable storage + delivery. Quarterly cadence; ~30 min wall time.

---

## Worked composition: pre-merge bead verification

```yaml
# .github/workflows/pre-merge.yml
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  pre-merge-bead-audit:
    if: contains(github.event.pull_request.body, 'closes')
    steps:
      - uses: actions/checkout@v4

      - name: Extract bead IDs from PR
        id: ids
        run: |
          BEAD_IDS=$(echo "${{ github.event.pull_request.body }}" \
            | grep -oE '(closes |fixes |resolves )([a-z][a-z0-9_-]*-[a-z0-9]+)' \
            | awk '{print $2}' | sort -u)
          echo "ids=$BEAD_IDS" >> $GITHUB_OUTPUT

      - name: Single-bead audit per closing bead
        run: |
          for ID in ${{ steps.ids.outputs.ids }}; do
            ~/.claude/skills/.../scripts/run-pass.sh . \
              --mode single-bead --bead-id "$ID" \
              --threshold 700 --policy report-only
          done

      - name: bead-author-feedback subagent
        run: |
          # Run bead-author-feedback on the PR's bead IDs to predict if they'll
          # be auditable AFTER the PR lands
          for ID in ${{ steps.ids.outputs.ids }}; do
            invoke_subagent bead-author-feedback "$ID" > "feedback-$ID.md"
            cat "feedback-$ID.md"
          done

      - name: Block merge if any bead would be false-closed post-merge
        run: |
          FAILED=()
          for ID in ${{ steps.ids.outputs.ids }}; do
            SCORE=$(jq -r '.score' .audit/passes/*/beads/"$ID"/score-summary.json)
            if [ "$SCORE" -lt 700 ]; then
              FAILED+=("$ID (score $SCORE)")
            fi
          done
          if [ "${#FAILED[@]}" -gt 0 ]; then
            echo "::error::Pre-merge audit blocks PR:"
            printf '  - %s\n' "${FAILED[@]}"
            exit 1
          fi
```

The chain: extract bead IDs from PR → audit each → bead-author-feedback for spec quality → block if any would be false-closed.

---

## Worked composition: portfolio dashboard for many projects

```bash
# Daily cron
PARENT=/data/projects

# 1. Run portfolio audit
~/.claude/skills/.../scripts/portfolio-audit.sh "$PARENT" 4 24

# 2. Build cross-project metrics
for ad in "$PARENT"/*/beads_compliance_audit; do
  ~/.claude/skills/.../scripts/metrics-export.sh "$ad" \
    /var/lib/node_exporter/textfile_collector/$(basename "$ad" | tr -dc '[:alnum:]_').prom
done

# 3. Per-project trauma reports (weekly cadence)
if [ "$(date +%u)" = "1" ]; then
  for ad in "$PARENT"/*/beads_compliance_audit; do
    ~/.claude/skills/.../scripts/trauma-guard.sh "$ad"
  done
fi

# 4. Cross-project rollup
python3 ~/.claude/skills/.../scripts/portfolio-rollup.py "$PARENT" \
  > "$PARENT/__audit_portfolio_summary.md"

# 5. Slack notification on convergence regression
PORTFOLIO_CONVERGED=$(jq -s '[.[].convergence.is_converged] | all' \
  "$PARENT"/*/beads_compliance_audit/manifest.json)
if [ "$PORTFOLIO_CONVERGED" = "false" ]; then
  curl -X POST "$SLACK_WEBHOOK" -H 'Content-Type: application/json' \
    -d "{\"text\":\"🚨 Portfolio audit: not all projects converged today. See $PARENT/__audit_portfolio_summary.md\"}"
fi
```

Chain: per-project audit → metrics export → trauma guard → portfolio rollup → notification. Daily cron, weekly trauma. ~15 min wall time for a 10-project portfolio.

---

## Composition anti-patterns

| Don't | Why |
|-------|-----|
| Run all 5 composition patterns simultaneously | Cost balloons; no single source of truth |
| Skip pre-flight in compositions | Compositions amplify pre-flight failures |
| Compose with skills that themselves modify the project | The audit's "pure verification" property is lost |
| Compose without recording chain in manifest.json | Future audits can't reproduce |
| Use compositions to compensate for poor rubric | Tighten the rubric instead |

---

## When NOT to compose

- Tripwire mode (single-skill, fast).
- Onboarding pass (CASS-mining is the only composition needed).
- Single-bead deep-dive (no benefit from chaining).
- Resource-constrained CI (cost grows linearly with composition).

For most day-to-day audits, this skill standalone is sufficient. Compositions are for special-purpose workflows (compliance, post-mortem, release-gating).
