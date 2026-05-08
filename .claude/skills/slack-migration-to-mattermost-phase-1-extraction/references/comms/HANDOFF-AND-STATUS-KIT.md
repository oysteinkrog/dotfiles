# Phase 1 Handoff And Status Kit

## Status Update Template

```markdown
Phase 1 status for `<workspace>`

- Branch: `<official-export|slackdump-primary|grid-split|delta>`
- Authoritative source: `<zip path>`
- Raw artifacts hashed: yes/no
- Enrichment complete: yes/no
- JSONL semantic validation: pass/fail
- Known gaps: `<count>`
- Ready for Phase 2 intake: yes/no
```

## Handoff Cover Note

```markdown
Phase 1 complete for `<workspace>`.

Authoritative bundle:
- ZIP: `<path>`
- SHA256: `<sha256>`

Required Phase 2 inputs:
- `handoff.json`
- manifests
- verification reports
- sidecar inventory

Do not begin staging or production import until `validate-phase2-intake.py` passes.
```

## Escalation Trigger Language

Use this when blocking issues appear:

```markdown
Phase 1 is blocked because `<reason>`.

Impact:
- authoritative export is not yet trustworthy
- downstream staging/import must not proceed

Needed owner decision:
- `<approval / token / source-of-truth / gap-acceptance>`
```
