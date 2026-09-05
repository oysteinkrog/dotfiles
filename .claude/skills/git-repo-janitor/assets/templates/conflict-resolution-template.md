# Conflict Resolution Template

Used by the move-applier and delete-applier when a move/delete cannot proceed automatically (per `references/INCIDENT-PLAYBOOK.md`).

---

```markdown
# Conflict — Phase {{N}} on candidate id={{id}}

## Triggering condition

{{condition}} — e.g., "git mv collision: destination exists"

## Context

- Candidate: `{{path}}`
- Proposed action: {{action}}
- Smell tags: {{smells}}
- Verdict: {{verdict}} (confidence {{confidence}})
- Inbound refs: {{ref-count}}

## What happened

{{narrative}}

For `git mv` collision:
- Source: `{{src}}` (sha: {{src-sha}})
- Destination: `{{dst}}` (already exists; sha: {{dst-existing-sha}})
- Content comparison: {{same-or-different}}

## Proposed resolutions

### Option A: {{option-a-label}}
{{option-a-description}}
```bash
{{option-a-commands}}
```

### Option B: {{option-b-label}}
{{option-b-description}}
```bash
{{option-b-commands}}
```

### Option C: Skip this candidate
- Mark `conflict-skipped` in apply_log.tsv
- Continue with the remaining candidates in this batch
- The user can re-run the skill later or handle this candidate manually

## Recommendation

{{recommendation}} — based on {{reasoning}}

## Awaiting your decision

Pick A / B / C, or describe your own resolution.
```
