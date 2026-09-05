# Commit Message Templates

Templates for the commit-message-author subagent. See `references/COMMIT-MESSAGE-CRAFT.md` for full guidelines.

---

## Phase 6 — Move category

```
chore: move {{category-name}} into {{dest-dir}}/ + update load-bearing path references

{{N}} long-form documents at the workspace root were {{category-purpose}}
artefacts. They retain lasting value as a record of {{reason}}, but
their natural home is under {{dest-dir}}/.

Moved ({{N}}):
{{#each files}}
- {{path}} ({{size}}) → {{dest-dir}}/{{basename}}
{{/each}}

{{#if reference_rewrites}}
Updated load-bearing path references in {{M}} files:
{{#each reference_rewrites}}
- {{file}}:{{line}} ({{kind}})
{{/each}}
{{/if}}

Verified: {{test-command}} passes; no stale path refs found via grep.
```

---

## Phase 7 — Delete category

```
chore: remove {{category-name}} from repo root

{{N}} files at the workspace root were {{category-purpose}}:

{{#each files}}
- {{basename}}: {{description}}
{{/each}}

Verified: {{test-command-or-no-impact-statement}}
```

---

## Phase 8 — `.gitignore` update

```
chore(gitignore): forbid {{category}} at repo root

After Phase 7 removed {{N}} files matching these smells, codify the prevention:

{{#each pattern_groups}}
- {{name}} ({{M}} patterns): {{patterns}}
   {{description}}
{{/each}}

Verified via SHADOWING-AUDIT: no currently-tracked files match any of the
new patterns. Verified via `git check-ignore -v <fake-paths>`: every pattern
fires correctly on its target shape.
```

---

## Secret-leak playbook commit (Step 10)

```
security: prevent private-key commits — broader .gitignore + .githooks/pre-commit + AGENTS.md

A real {{secret-type}} ({{path}}) was committed in {{introducing-sha}}
"{{introducing-commit-message}}" despite .gitignore already containing
{{pre-existing-rule}}. The leak was force-added with `git add -f`,
bypassing .gitignore. To prevent recurrence:

- Broaden .gitignore: add {{new-patterns}}
- Install .githooks/pre-commit that scans staged paths against
  secret-smells (cannot be bypassed by `git add -f`)
- Document the hook in AGENTS.md so contributors know how to install
  it on their clones (`git config core.hooksPath .githooks`)

After this commit:
- New users clone normally
- core.hooksPath needs to be set per-clone:
    git config core.hooksPath .githooks

Cross-reference: incident reported {{incident-date}}; key rotated; history
rewritten via filter-repo + force-with-lease push to {{branch}} and {{synonym}}.
```
