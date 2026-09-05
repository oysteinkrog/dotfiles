# BADGE.md — GitHub README Badges For Audit Status

<!-- TOC: The 4 badges | Static badge format | Dynamic shield.io endpoint | CI integration | Anti-patterns -->

> A picture (or 4) is worth 1000 words on a project's README. Badges surface convergence + false-closed count at a glance.

---

## The 4 badges

| Badge | What it signals |
|-------|-----------------|
| **Audit converged** | green / red — has the bead graph stabilized? |
| **False-closed count** | yellow / orange / red — how much bead-graph drift exists? |
| **Score median** | numeric — overall bead quality |
| **Last audit** | date — is the audit current? |

---

## Static badge format (manual update)

For projects updating README manually:

```markdown
[![Audit converged](https://img.shields.io/badge/beads--audit-converged-success)](./BEADS_COMPLIANCE_REPORT.md)
[![False-closed](https://img.shields.io/badge/false--closed-3-yellow)](./BEADS_COMPLIANCE_REPORT.md)
[![Score median](https://img.shields.io/badge/score--median-820-green)](./BEADS_COMPLIANCE_REPORT.md)
[![Last audit](https://img.shields.io/badge/audited-2026--05--06-informational)](./BEADS_COMPLIANCE_REPORT.md)
```

Color thresholds:

- **Audit converged:** `success` (green) if converged, `critical` (red) if not.
- **False-closed:** 0 = `success`, 1-3 = `yellow`, 4-10 = `orange`, 11+ = `red`.
- **Score median:** 900+ = `brightgreen`, 800-899 = `green`, 700-799 = `yellowgreen`, 600-699 = `yellow`, 500-599 = `orange`, <500 = `red`.

---

## Dynamic shield.io endpoint (auto-updating)

shields.io can render a badge from a JSON endpoint. Host the JSON wherever (GitHub Pages, S3, your CI artifact storage):

`audit-badge.json`:

```json
{
  "schemaVersion": 1,
  "label": "beads-audit",
  "message": "converged",
  "color": "success"
}
```

Badge URL:
```
https://img.shields.io/endpoint?url=https%3A%2F%2Fyour-host%2Faudit-badge.json
```

In README:
```markdown
[![Beads audit](https://img.shields.io/endpoint?url=https%3A%2F%2Fyour-host%2Faudit-badge.json)](./AUDIT_REPORT.md)
```

---

## CI integration: auto-publish badge JSON

In your tripwire workflow:

```yaml
# After audit pass
- name: Publish audit badge
  run: |
    AUDIT_DIR="${GITHUB_WORKSPACE}/beads_compliance_audit"

    CONVERGED=$(jq -r '.convergence.is_converged // false' "$AUDIT_DIR"/manifest.json)
    FC=$(awk '/^## False-closed list/{f=1;next} /^## /{f=0} f && /^\| `/{n++} END{print n+0}' "$AUDIT_DIR"/REPORT.md)
    SCORES=$(grep -hoP 'Score:\s+\K\d+' "$AUDIT_DIR"/passes/*/beads/*/scorecard.md)
    MEDIAN=$(echo "$SCORES" | sort -n | awk '{a[NR]=$1} END {if (NR>0) print (NR%2==1) ? a[(NR+1)/2] : int((a[NR/2]+a[NR/2+1])/2); else print 0}')

    # Convergence badge
    if [ "$CONVERGED" = "true" ]; then COLOR=success; MSG=converged; else COLOR=critical; MSG=drifting; fi
    cat > convergence-badge.json <<EOF
    {"schemaVersion":1,"label":"beads-audit","message":"$MSG","color":"$COLOR"}
EOF

    # False-closed badge
    if [ "$FC" -eq 0 ]; then COLOR=success
    elif [ "$FC" -le 3 ]; then COLOR=yellow
    elif [ "$FC" -le 10 ]; then COLOR=orange
    else COLOR=red; fi
    cat > false-closed-badge.json <<EOF
    {"schemaVersion":1,"label":"false-closed","message":"$FC","color":"$COLOR"}
EOF

    # Score median badge
    if [ "$MEDIAN" -ge 900 ]; then COLOR=brightgreen
    elif [ "$MEDIAN" -ge 800 ]; then COLOR=green
    elif [ "$MEDIAN" -ge 700 ]; then COLOR=yellowgreen
    elif [ "$MEDIAN" -ge 600 ]; then COLOR=yellow
    elif [ "$MEDIAN" -ge 500 ]; then COLOR=orange
    else COLOR=red; fi
    cat > score-median-badge.json <<EOF
    {"schemaVersion":1,"label":"score-median","message":"$MEDIAN","color":"$COLOR"}
EOF

    # Last audit badge
    DATE=$(date -u +%Y-%m-%d)
    cat > last-audit-badge.json <<EOF
    {"schemaVersion":1,"label":"audited","message":"$DATE","color":"informational"}
EOF

- name: Publish to GitHub Pages branch
  uses: peaceiris/actions-gh-pages@v3
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: .
    publish_branch: gh-pages
    keep_files: true
    destination_dir: audit-badges
```

Then in README:
```markdown
[![Audit](https://img.shields.io/endpoint?url=https%3A%2F%2Fyour-org.github.io%2Fyour-repo%2Faudit-badges%2Fconvergence-badge.json)](./AUDIT_REPORT.md)
[![False-closed](https://img.shields.io/endpoint?url=https%3A%2F%2Fyour-org.github.io%2Fyour-repo%2Faudit-badges%2Ffalse-closed-badge.json)](./AUDIT_REPORT.md)
[![Score median](https://img.shields.io/endpoint?url=https%3A%2F%2Fyour-org.github.io%2Fyour-repo%2Faudit-badges%2Fscore-median-badge.json)](./AUDIT_REPORT.md)
[![Last audit](https://img.shields.io/endpoint?url=https%3A%2F%2Fyour-org.github.io%2Fyour-repo%2Faudit-badges%2Flast-audit-badge.json)](./AUDIT_REPORT.md)
```

---

## All-in-one badge

For projects that want a single badge:

```bash
if [ "$CONVERGED" = "true" ] && [ "$FC" -eq 0 ]; then
  MSG="✓ verified ($MEDIAN/1000)"
  COLOR=brightgreen
elif [ "$CONVERGED" = "true" ]; then
  MSG="$FC false-closed ($MEDIAN/1000)"
  COLOR=yellow
else
  MSG="✗ drifting ($FC false-closed)"
  COLOR=red
fi
cat > beads-audit-badge.json <<EOF
{"schemaVersion":1,"label":"beads-audit","message":"$MSG","color":"$COLOR"}
EOF
```

---

## Per-environment badges

Multiple badges for prod / staging / dev:

```markdown
[![Prod audit](https://img.shields.io/endpoint?url=...prod...)](./PROD_AUDIT_REPORT.md)
[![Staging audit](https://img.shields.io/endpoint?url=...staging...)](./STAGING_AUDIT_REPORT.md)
```

---

## Anti-patterns

- **Badge that lies.** Don't manually edit the badge JSON to look better; let CI publish reality.
- **Stale badges.** If "last audit" is > 30 days, the project isn't tripwiring; the badge encourages false confidence.
- **Too many badges.** 4 max; more becomes noise in the README header.
- **Color schemes that aren't accessible.** Use shields.io's pre-defined colors (success / yellow / orange / red); they're tested for color-blindness.

---

## Adding to your README

Best position: at the top of README.md after the title and before the description, in a single horizontal row:

```markdown
# My Project

[![Beads audit](.../convergence-badge.json)](./AUDIT_REPORT.md)
[![False-closed](.../false-closed-badge.json)](./AUDIT_REPORT.md)
[![Last audit](.../last-audit-badge.json)](./AUDIT_REPORT.md)

My project does X, Y, Z.

...
```

The audit badges sit alongside CI / coverage / version badges and tell visitors at a glance: "this project takes bead-graph integrity seriously."
