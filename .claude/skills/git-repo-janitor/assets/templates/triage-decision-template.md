# Triage Decision — Categorized Plan Template

Used by the triage-merger subagent at Phase 5. Fill in counts, file lists, and category-letter labels.

---

```markdown
## Audit summary: {{total-candidates}} candidates in `{{project}}`

### A. KEEP IN ROOT — standard project files ({{count-A}})
{{file-list-A-inline}}

(All confirmed referenced by `package.json` build, README, or already pinned in `.gitignore` comments as intentionally tracked.)

### B. MOVE to `docs/planning/` — long-form planning & spec docs ({{count-B}})
| id | path | refs (in-repo) | proposed action |
|----|------|----------------|-----------------|
{{#each candidates-B}}
| {{id}} | {{path}} | {{refs-summary}} | move to {{dest}} |
{{/each}}

### C. MOVE to `docs/contracts/` — DEFERRED  (when applicable)
{{file-list-C-inline}}

These are load-bearing config referenced by {{M}}+ Rust files and shell scripts via repo-root-relative path strings. Moving them is doable but a significantly larger surgery; they're config not docs, and at root they're at worst neutral. **Default: leave at root.** Let me know if you want me to tackle those separately.

### D. MOVE to `docs/progress/` — bead-keyed progress reports ({{count-D}})
{{file-list-D-summary}}

### E. MOVE to `scripts/visualization/` — viz pipeline ({{count-E}})
{{file-list-E-inline}}

### F. MOVE to `scripts/` — deploy / verify scripts ({{count-F}})
{{file-list-F-inline}}

### G. DELETE — ephemeral / scratch ({{count-G}})
| id | path | reason | action |
|----|------|--------|--------|
{{#each candidates-G}}
| {{id}} | {{path}} | {{evidence}} | git rm |
{{/each}}

### H. `.gitignore` ADDITIONS  ({{count-H}} patterns)
| pattern | rationale | shadowing |
|---------|-----------|-----------|
{{#each gitignore-patterns}}
| {{pattern}} | {{rationale}} | {{shadow-status}} |
{{/each}}

### MANUAL — surface-to-user ({{count-MANUAL}})
| id | path | reason | proposed action |
|----|------|--------|-----------------|
{{#each candidates-MANUAL}}
| {{id}} | {{path}} | {{evidence}} | {{proposed}} |
{{/each}}

---

**Reminder:** Phase 6 (moves) needs your "go" / "proceed" / "approved" / "sounds good" to start. Phase 7 (deletes) and Phase 8 (gitignore changes that shadow tracked files) need a verbatim authorization phrase before any destructive command runs.

**Type "go" to proceed with categories B, D, E, F (moves) or override individual verdicts before continuing.**
```
