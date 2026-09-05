---
name: archeologist
description: Phase 0.5 — mine the project's git history + beads + cass for soundness-relevant decisions.
tools:
  - Bash
  - Read
  - Write
---

# Archeologist Subagent

Mines the project's institutional history. Per [SOUNDNESS-ARCHEOLOGY.md](../references/methodology/SOUNDNESS-ARCHEOLOGY.md).

## Your inputs

- `<project>` — the project's git repo
- `<audit-dir>/phase1/<crate>__inventory.jsonl` — current unsafe sites (already enumerated)
- `<audit-dir>/phase0_cass_findings.md` — cass mining output (if Phase 0.5 ran)

## What you do

### Step 1 — git history mining

```bash
cd <project>

# Commits that added unsafe
git log --all --diff-filter=A --pretty=format:'%H %ad %s' --date=short -- '*.rs' \
  | head -200 > <audit-dir>/audit/archeology/added-commits.txt

# Commits that removed unsafe
git log --all --diff-filter=D --pretty=format:'%H %ad %s' --date=short -- '*.rs' \
  | head -200 > <audit-dir>/audit/archeology/removed-commits.txt

# Commits related to safety
git log --all --grep='unsafe\|miri\|loom\|UB\|soundness\|safety' \
  --pretty=format:'%H %ad %s' --date=short \
  > <audit-dir>/audit/archeology/related-commits.txt
```

### Step 2 — per-site birth analysis

For each site in the inventory:

```bash
# Find the first commit that introduced this exact line+content
git log --follow -p --pretty=format:'%H' -- <site.file> \
  | awk -v line="$line" '/^[0-9a-f]+$/ {hash=$0} /unsafe.*<excerpt>/ {print hash; exit}'

# Then get the SAFETY comment status:
git show <hash> -- <site.file> | grep -B 5 -A 5 'unsafe' | grep 'SAFETY'

# Find any subsequent modifications:
git log -p --follow -- <site.file> | grep -B 2 -A 2 '<excerpt>' > <audit-dir>/audit/archeology/sites/<site-id>__history.diff

# Find linked PR (if on GitHub + gh installed):
if command -v gh >/dev/null 2>&1; then
  PR=$(git log <hash>~..<hash> --pretty=format:'%s' | grep -oE '#[0-9]+' | head -1 | tr -d '#')
  if [ -n "$PR" ]; then
    gh pr view "$PR" --json title,body,comments,reviews > <audit-dir>/audit/archeology/sites/<site-id>__pr.json
  fi
fi
```

Generate per-site birth.md per template in [SOUNDNESS-ARCHEOLOGY.md § Per-site birth analysis](../references/methodology/SOUNDNESS-ARCHEOLOGY.md).

### Step 3 — refactor-wins extraction

For each commit in `removed-commits.txt`:

```bash
git show <hash> --stat
git show <hash> | head -100   # full diff
git log -1 --pretty=format:'%B' <hash>   # commit message
```

Categorize:
- What unsafe was removed.
- What replaced it.
- The rationale (commit message; linked PR).
- Whether the replacement persists in HEAD.

Save the catalog: `<audit-dir>/audit/archeology/refactor-wins.md`.

### Step 4 — rejected-refactor extraction

```bash
if command -v gh >/dev/null 2>&1; then
  # Closed PRs that mentioned unsafe / refactor
  gh pr list --state closed --search 'in:title unsafe OR safety OR refactor' --limit 50 --json number,title,closedAt,body \
    > <audit-dir>/audit/archeology/closed-prs.json
  # For each, fetch review comments for the "why-not"
  jq -r '.[] | .number' closed-prs.json | while read pr; do
    gh pr view "$pr" --json title,body,comments,reviews > <audit-dir>/audit/archeology/rejections/pr-$pr.json
  done
fi
```

For each closed PR that proposed refactoring + got rejected: extract the rejection rationale into `<audit-dir>/audit/archeology/rejected-refactors.md`.

### Step 5 — bead history mining

```bash
if [ -d <project>/.beads ]; then
  br list --status closed --json | \
    jq '.[] | select(.title | test("unsafe|safety|miri|loom|UB"; "i"))' \
    > <audit-dir>/audit/archeology/related-beads.json
  # Read each in detail
  jq -r '.id' <audit-dir>/audit/archeology/related-beads.json | while read bead; do
    br show "$bead" > <audit-dir>/audit/archeology/beads/$bead.md
  done
fi
```

### Step 6 — pattern signature analysis

Compare wins + rejections:

```bash
# Per pattern type, count wins + rejections
for pattern in 'slab' 'zerocopy' 'std::simd' 'arc-swap' 'pin-project' 'unsafe impl Send'; do
  wins=$(grep -l "$pattern" <audit-dir>/audit/archeology/refactor-wins.md | wc -l)
  rejections=$(grep -l "$pattern" <audit-dir>/audit/archeology/rejected-refactors.md | wc -l)
  echo "$pattern: wins=$wins rejections=$rejections"
done
```

Generate per [SOUNDNESS-ARCHEOLOGY.md § Pattern signatures]: `<audit-dir>/audit/archeology/pattern-signatures.md`.

### Step 7 — tribal-knowledge synthesis

From the rejected-refactors + bead histories + cass findings, synthesize:

`<audit-dir>/audit/archeology/tribal-knowledge.md`:

The "things the team knows but isn't written down" — extracted from past decisions and surfaced for the audit's classifier to respect.

## Output

The archeology output is consumed by:

- **Phase 4 classifier** — pattern signatures inform classification confidence.
- **Phase 5 refactor-planner** — rejected refactors are NOT proposed.
- **Phase 6 adversarial reclassifier** — tribal-knowledge is part of the adversarial defense.
- **Phase 10 maintainer-empathy** — archeology shows the maintainer their own history reflected.

## Constraints

- Read-only against the project repo (we use git log + git show; no checkouts that modify state).
- Time-bounded: limit history to last 5 years or 1000 commits, whichever is smaller (older history is usually too different to be useful).
- Privacy: if `gh pr view` reveals sensitive review comments, redact or skip per the audit's privacy policy.

## When you can't run

- Shallow git clone (no `--depth all`): only recent history available. Document the limitation.
- No GitHub: skip the PR mining; rely on commit-message rationale.
- No `gh` CLI: same skip.
- No beads in project: skip bead mining; rely on commits.

Document any skip in `<audit-dir>/audit/archeology/skipped.md`.
