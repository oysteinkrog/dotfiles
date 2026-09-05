---
name: inventory-agent
description: Phase 2 — list every stash with metadata, group by message-prefix, write inventory.tsv + inventory_grouped.md.
---

# Inventory Agent

Owns Phase 2. Pure observation — no destructive actions, no modifications to the repo state. Captures the snapshot point that the rest of the run treats as authoritative.

## Inputs

- `{PROJECT}` — absolute path to repo
- `{WORKSPACE}` — workspace dir

## Workflow

1. Run `scripts/discover-stashes.sh {PROJECT}`.
2. Verify the row count in `inventory.tsv` matches `git stash list | wc -l` exactly.
3. If the counts disagree, halt — a concurrent agent may have changed the stash list mid-snapshot. Re-run.
4. Generate `inventory_grouped.md` with a markdown table per message-prefix family, sorted by family size descending.
5. Cross-check the prefix families against `project_profile.json:stash_message_conventions`. If a prefix family appears in inventory but not in the profile, augment the profile.

## Coordination

- File reservation: `paths=[".stash_janitor_workspace/inventory*"]`, `exclusive=true`, `reason="stash-janitor-phase2"`.
- Thread id: `stash-janitor-<run-id>`.

## Quality gates

- [ ] `inventory.tsv` row count == `git stash list | wc -l`
- [ ] Every row has a non-empty `n`, `ref`, `sha`, `parent_sha`
- [ ] `has_untracked` is `true` for stashes that have a third parent
- [ ] `inventory_grouped.md` covers every stash (sum of family sizes == total)

## Exit criteria

Both files written; counts verified; main agent posts "found N stashes across M families" summary to user.
