# Handoff Report Template

Used by the handoff-reporter at Phase 10.

---

```markdown
# Repo Janitor — Handoff Report

**Project:** `{{project}}`
**Run date:** {{run-date}}
**Mode:** {{mode}}
**Recovery branch:** `{{recovery-branch}}`
**Bundle path:** `{{bundle-path}}`

## Counts
- Initial tracked top-level files: {{initial}}
- Final tracked top-level files: {{final}} ({{reduction-pct}}% reduction)
- Candidates triaged: {{candidates}}
  - move: {{count-move}} (applied)
  - delete-and-gitignore: {{count-dag}} (applied + .gitignore updated)
  - delete-no-gitignore: {{count-dng}} (applied)
  - gitignore-only: {{count-go}} (.gitignore updated)
  - keep-in-place: {{count-keep}}
  - protected: {{count-prot}}
  - surface-to-user: {{count-stu}} (resolved per user input)
- Recovery commits authored: {{commit-count}} on `{{recovery-branch}}`

## Per-commit summary

| sha | category | counts |
|-----|----------|-------:|
{{#each commits}}
| `{{sha-short}}` | {{description}} | {{count}} |
{{/each}}

## Skipped categories

{{#each skipped}}
- **{{cat-letter}} ({{category}}, {{count}} files)** — {{reason}}.
{{/each}}

## Recovery recipes

If you regret any move/delete, every candidate is recoverable:

```bash
# By backup ref (preferred)
git checkout refs/repo-janitor-backup/{{date}}-pre-cleanup -- <path>
git add <path>
git commit -m "restore: <path>"

# By bundle copy
cp {{bundle-path}}/working-tree-copies/<path> {{project}}/<path>

# Bundle index:
cat {{bundle-path}}/index.tsv
```

See `references/RECOVERY-RECIPES.md` for the full guide.

## Push instructions

The skill never pushes. To land the recovered work:

```bash
git push origin {{recovery-branch}}
# Then open a PR against {{primary-branch}} for review
{{#if synonyms}}
# Synonym pushes (this repo mirrors {{primary-branch}} → {{synonyms}}):
git push origin {{recovery-branch}}:{{synonym}}
{{/if}}
```

## Bundle lifecycle

The bundle lives at `{{bundle-path}}`. Keep it for at least one release cycle. Once you're sure nothing was accidentally lost, move it to your normal archive/trash location with `mv`. The skill never advises bypassing DCG or deleting the bundle itself.

## Polish bar

{{polish-bar-results}}

## Follow-ups

{{#if beads-issue}}
- Beads issue filed: {{beads-id}}
{{/if}}
{{#if bv-triage}}
- bv triage of newly-unblocked work attached as `{{workspace}}/post_cleanup_bv_triage.json`
{{/if}}

## Reminder

**Push when ready:**
```bash
git push origin {{recovery-branch}}
```
```
