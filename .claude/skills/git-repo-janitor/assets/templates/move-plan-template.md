# Move Plan Template

Used by the triage-merger at Phase 5 for the per-category move plan. Each MOVE category gets one section.

---

```markdown
# Move Plan — {{run-id}}

## Category {{cat-letter}}: {{category-name}}

**Destination dir:** `{{dest-dir}}` ({{exists-or-will-create}})
**Count:** {{N}} files
**Total size:** {{total-size-MB}} MB

### Per-file plan

{{#each files}}
#### {{path}} → {{dest-dir}}/{{basename}}

- Size: {{size}}
- Smell: {{smell-tags}}
- Inbound refs: {{ref-count}}

##### References to rewrite ({{rewrite-count}}):
{{#each rewrites}}
- `{{ref-path}}:{{line}}` ({{kind}})
  - Old: `{{old-string}}`
  - New: `{{new-string}}`
  - Eligibility: {{eligibility}}
{{/each}}

##### References to surface (no auto-rewrite):
{{#each surface-only}}
- `{{ref-path}}:{{line}}`
  - Context: `{{context-line}}`
  - Reason: {{why-not-auto}}
{{/each}}

{{/each}}

### Order of execution

1. Create dest dir if needed: `mkdir -p {{dest-dir}}`
2. For each file: `git mv {{path}} {{dest-dir}}/{{basename}}`
3. Edit-tool rewrite each ref (logged in reference_rewrite_log.tsv)
4. Run quality gates
5. Single commit per category (per `references/COMMIT-MESSAGE-CRAFT.md § Phase 6 template`)

### Risks

{{#each risks}}
- {{risk}}: {{mitigation}}
{{/each}}
```
