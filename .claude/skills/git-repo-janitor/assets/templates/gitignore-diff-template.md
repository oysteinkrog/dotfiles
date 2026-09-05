# Gitignore Plan Template

Used by the gitignore-author at Phase 8 to present the plan + shadowing audit.

---

```markdown
# .gitignore Plan — {{run-id}}

## Proposed additions

{{#each pattern_groups}}
### {{group-name}} ({{count}} patterns)

{{description}}

{{#each patterns}}
**`{{pattern}}`** — {{rationale}}
- Glob effect: {{glob-effect}}
- Test pattern fires: `git check-ignore -v {{test-path}}` → {{result}}
- Shadowing audit: `git ls-files {{pattern}}` → {{shadow-result}}
{{#if shadowed-files}}
  - **WARNING: shadows tracked files:**
    {{#each shadowed-files}}
    - `{{path}}` ({{action-needed}})
    {{/each}}
{{/if}}
{{/each}}

{{/each}}

## Order of execution

1. {{#each shadowed-removals}}`git rm --cached {{path}}` → untrack but keep on disk
{{/each}}
2. Edit-tool to append new patterns to `.gitignore` thematically
3. Run quality gates
4. Single commit (per `references/COMMIT-MESSAGE-CRAFT.md § Phase 8 template`)

## Verbatim authorization required

{{#if shadows-tracked}}
Because the additions would shadow tracked files, this commit needs your verbatim auth:

```
yes I understand and want to untrack and ignore {{shadowed-list}} per the plan above
```
{{else}}
No tracked files would be shadowed; this commit can proceed with the standard "go" authorization.
{{/if}}
```
