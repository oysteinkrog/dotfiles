# RELEASE-GATING.md — Audit Verdict Gates A Release

<!-- TOC: Why gate releases | Three gating models | Per-milestone audit | Pre-tag audit | Post-tag tripwire | Rollback if regression | CI examples -->

> A release that ships with false-closed beads is shipping a *known* lie about what's in it. Release-gating ties the release pipeline to the audit verdict: if any bead in the release's milestone is false-closed, block the release.

---

## Why gate releases

| Failure without gating | What gating prevents |
|------------------------|---------------------|
| Ship a "v1.5 includes feature X" while X is theater | Marketing claims a feature that doesn't work |
| Ship a "we fixed CSRF" when the regression test was `assert true` | The CSRF bug recurs in v1.5+1; users blame the team |
| Ship a "schema migration v1.5 adds users table" with no rollback | Production deploy crashes; can't roll back |
| Ship a "performance optimization" that misses its budget | Metrics go red right after deploy |

Release gating turns the audit from a *retrospective* into a *prospective* check.

---

## Three gating models

### Model 1 — Per-milestone audit (recommended)

Beads are tagged with a release milestone label (`release-v1.5`, `milestone-Q2-2026`, etc.). The release pipeline audits only those beads.

```bash
# Pre-release: audit just the v1.5 beads
br --db .beads/*.db list --label=release-v1.5 --status=closed --limit 0 --json \
  | jq -r '.issues[].id' > /tmp/v1.5_beads.txt

for bead_id in $(cat /tmp/v1.5_beads.txt); do
  ~/.claude/skills/.../scripts/run-pass.sh <project> \
    --mode single-bead --bead-id "$bead_id" \
    --threshold 700 --policy report-only
done

# Roll up: any false-closed → block release
FC=$(grep -l 'FALSE-CLOSED' <project>/beads_compliance_audit/passes/*/beads/*/scorecard.md \
     | xargs -I{} basename $(dirname {}))
if [ -n "$FC" ]; then
  echo "BLOCKED: false-closed beads in release milestone:" >&2
  echo "$FC" >&2
  exit 1
fi
```

### Model 2 — Pre-tag audit (full project)

Run a full audit on the project state immediately before tagging the release. If any bead — anywhere in the project — is false-closed, surface it; the team decides whether to block.

```bash
~/.claude/skills/.../scripts/run-pass.sh <project> \
  --threshold 700 --policy report-only --mode standard

FC=$(jq '.bead_counts.false_closed // 0' <project>/beads_compliance_audit/manifest.json)
if [ "$FC" -gt 0 ]; then
  echo "WARNING: $FC false-closed beads detected. Manual review required." >&2
  read -p "Proceed with release? [y/N] " ans
  [ "$ans" = "y" ] || exit 1
fi
```

### Model 3 — Post-tag tripwire

Tag the release. Then audit. If any bead used in the release is false-closed, immediately revoke / yank the release.

```bash
# Tag the release
git tag v1.5.0 && git push --tags

# Audit immediately
~/.claude/skills/.../scripts/run-pass.sh <project> --threshold 700 --policy report-only

# If false-closed, yank the release
FC=$(jq '.bead_counts.false_closed // 0' <project>/beads_compliance_audit/manifest.json)
if [ "$FC" -gt 0 ]; then
  echo "Auto-yanking v1.5.0 due to $FC false-closed beads" >&2
  gh release delete v1.5.0 --yes
  git push --delete origin v1.5.0
  # Notify
  echo "Release v1.5.0 yanked: $FC false-closed beads. See REPORT.md." | \
    gh issue create --title "Release v1.5.0 yanked" --label "release,audit" --body -
fi
```

Use Model 3 only if you have **fast distribution** — i.e., yanking a release before users download is feasible. Crates.io and npm registries don't support fast yank.

---

## CI integration: GitHub Actions

```yaml
# .github/workflows/release-audit.yml
name: Release audit gate
on:
  push:
    tags: ['v*']

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }

      - name: Install beads CLI
        run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh | bash

      - name: Install audit skill
        run: |
          curl -fsSL https://jeffreys-skills.md/install.sh | bash
          jsm install beads-compliance-and-completion-verification

      - name: Identify release milestone beads
        id: beads
        run: |
          MILESTONE="${GITHUB_REF#refs/tags/}"
          br --db .beads/*.db list --label="release-${MILESTONE}" \
              --status=closed --limit 0 --json \
            | jq -r '.issues[].id' > /tmp/release_beads.txt
          echo "count=$(wc -l < /tmp/release_beads.txt)" >> $GITHUB_OUTPUT

      - name: Per-bead audit
        run: |
          FAILED=()
          for bead_id in $(cat /tmp/release_beads.txt); do
            ~/.claude/skills/.../scripts/run-pass.sh . \
              --mode single-bead --bead-id "$bead_id" \
              --threshold 700 --policy report-only \
              || FAILED+=("$bead_id")
          done
          if [ "${#FAILED[@]}" -gt 0 ]; then
            echo "::error::Release blocked: ${#FAILED[@]} false-closed beads"
            printf '%s\n' "${FAILED[@]}"
            exit 1
          fi

      - name: Upload audit artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: release-audit-${{ github.ref_name }}
          path: beads_compliance_audit/

      - name: Notify Slack on failure
        if: failure()
        run: |
          curl -X POST "${{ secrets.SLACK_WEBHOOK }}" \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"🚨 Release ${{ github.ref_name }} blocked by audit. Check workflow logs.\"}"
```

---

## Per-bead-type override

Some beads in a release milestone are docs / chore / question — relaxed thresholds may apply. Override per type:

```yaml
# .github/release-audit-config.yml
per_type_threshold:
  feature: 800     # tighter than default
  bug: 800         # bug fixes need higher confidence in regression test
  docs: 600        # docs are less likely to break things
  chore: 700       # default
  question: skip   # questions don't have measurable claims
```

The CI invokes `run-pass.sh --threshold-by-type-config /path/to/config.yml`.

---

## Soft-block vs hard-block

Two policies for "what to do when false-closed in release":

| Policy | Behavior | When to use |
|--------|----------|-------------|
| **Hard-block** | CI fails; release tag isn't created | High-stakes releases (paid product, security-sensitive) |
| **Soft-block** | CI warns; team manually approves | Low-stakes / pre-launch / iteration releases |

Configure via `--gate-policy hard|soft` in the wrapper.

---

## Rollback if regression detected post-release

If a release ships and a *new* false-closed appears in the next tripwire pass that maps to a release-milestone bead:

```bash
# Detect the new false-closed beads
NEW_FC=$(jq -r '.criteria.new_false_closed_beads[]' \
  <audit-dir>/passes/<UTC>/convergence.json)

# Cross-reference with release milestone
for bead in $NEW_FC; do
  if br --db .beads/*.db show "$bead" --format json | jq -e '.labels[] | contains("release-")' >/dev/null; then
    echo "Release milestone bead $bead newly false-closed"
    echo "Consider rollback to last known-good release"
  fi
done
```

If a milestone bead regresses, two options:
1. **Hot-fix** the bead and re-cut a patch release.
2. **Rollback** to the prior release tag.

---

## Pre-merge audit hook (per-PR, not per-release)

A finer-grained version: audit *one bead* every time a PR claims to close it.

```yaml
# .github/workflows/pre-merge-bead-audit.yml
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  audit:
    if: contains(github.event.pull_request.title, 'closes bd-') ||
        contains(github.event.pull_request.body, 'closes bd-')
    steps:
      - uses: actions/checkout@v4
      - name: Extract closed bead IDs
        id: beads
        run: |
          IDS=$(echo "${{ github.event.pull_request.title }} ${{ github.event.pull_request.body }}" \
                | grep -oE '[a-z][a-z0-9_-]*-[a-z0-9]+' | sort -u)
          echo "ids=$IDS" >> $GITHUB_OUTPUT

      - name: Single-bead audit per closed bead
        run: |
          for ID in ${{ steps.beads.outputs.ids }}; do
            ~/.claude/skills/.../scripts/run-pass.sh . \
              --mode single-bead --bead-id "$ID" \
              --threshold 700 --policy report-only
            SCORE=$(jq -r '.score' .audit/passes/*/beads/"$ID"/score-summary.json)
            if [ "$SCORE" -lt 700 ]; then
              echo "::error::Bead $ID would be false-closed by this PR (score: $SCORE)"
              exit 1
            fi
          done
```

This **prevents the false-close from happening in the first place** — the audit runs at PR time, not at release time.

---

## Anti-patterns in release gating

| Don't | Why |
|-------|-----|
| Skip the audit "just this once" because the release is urgent | The audit's value is consistency; one skip teaches the team it's optional |
| Lower the threshold to make the audit pass | Document the threshold change explicitly; don't sneak it in |
| Tag the release first, then audit | Use Model 1 or Model 2; Model 3 is for projects with fast yank |
| Audit only release-labeled beads when the project has long-running upstream betas | Audit the whole project periodically; release-label audit is supplementary |
| Use audit results as performance reviews of agents | The audit is graph-truth maintenance, not performance management |

---

## Worked example: shipping v1.5

```bash
# 1. Tag the release candidate
git checkout -b release-1.5
git tag v1.5.0-rc1

# 2. Audit the release-tagged beads
br --db .beads/*.db list --label=release-v1.5 --status=closed --limit 0 --json \
  | jq -r '.issues[].id' > /tmp/v15_beads.txt
echo "$(wc -l < /tmp/v15_beads.txt) beads in v1.5 milestone"

# 3. Per-bead audit
for bead in $(cat /tmp/v15_beads.txt); do
  ~/.claude/skills/.../scripts/run-pass.sh . \
    --mode single-bead --bead-id "$bead" \
    --threshold 700 --policy report-only
done

# 4. Read the verdict
FC=$(grep -l 'FALSE-CLOSED' /data/projects/myproject/beads_compliance_audit/passes/*/beads/*/scorecard.md | wc -l)
echo "$FC false-closed beads in v1.5 milestone"

# 5. If 0, tag final
if [ "$FC" -eq 0 ]; then
  git tag v1.5.0 && git push --tags
else
  echo "Block release. Review false-closed list:"
  cat /data/projects/myproject/beads_compliance_audit/REPORT.md | head -40
fi
```

The release pipeline doesn't tag v1.5.0 until every milestone bead is verified. This is the discipline that prevents v1.5.0 from being a marketing claim that doesn't survive contact with users.