---
name: commit-message-author
description: Phase 6 — rewrite auto-generated commit messages into focused, why-explaining recovery commit messages per COMMIT-MESSAGE-CRAFT.md.
---

# Commit Message Author

Spawned by the keeper-applier after each successful Phase 6 / Phase 7 commit. Replaces the auto-generated message via `git commit --amend` (the only valid `--amend` use in the skill, and only on the recovery branch's tip while not yet pushed).

## Inputs

- `{PROJECT}` — absolute path
- `{N}` — stash index
- `{NEW_SHA}` — the auto-generated commit's SHA (the one to rewrite)
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path

## Workflow

1. **Gather inputs:**
   - The diff applied: `<bundle>/diffs/<NPAD>.diff`
   - Stash metadata: `<bundle>/meta/<NPAD>.txt`
   - Triage row: `awk -F'\t' '$1 == <N>' <workspace>/triage.tsv`
   - Apply log row: `awk -F'\t' '$1 == <N>' <workspace>/apply_log.tsv`
   - Forensic report (if exists): `<workspace>/forensic_<NPAD>.md`
   - Conflict context (if exists): `<workspace>/conflicts/stash_<NPAD>.context.md`
   - Project's commit-message convention from `<workspace>/project_profile.json`
   - Beads issue (if message contains a ticket id): `br show <ticket-id>`

2. **Author the message** following `references/COMMIT-MESSAGE-CRAFT.md`:
   - Subject (≤72 chars): present-tense verb + concrete object
   - Body — three required sections:
     - **Context:** what was lost, why it matters
     - **Why it didn't already land:** the developmental path that left it stashed
     - **How it was recovered:** the mechanism + any conflict resolution
   - Citation: stash ref, original SHA, original date, bundle diff path
   - NO `Co-Authored-By` lines

3. **Convention compliance:**
   - Conventional Commits: prefix `feat:`, `fix:`, `test:`, `perf:`, etc.
   - Ticket-id projects: prefix with the relevant ticket
   - Gitmoji: appropriate emoji
   - Freeform: just follow the body discipline

4. **Amend the commit:**
   ```bash
   echo "<authored message>" > <workspace>/commit_msg_<NPAD>.txt
   git -C {PROJECT} commit --amend -F <workspace>/commit_msg_<NPAD>.txt
   ```

5. **Update apply_log.tsv** with the new SHA (amend changes the SHA):
   - Replace `new_commit_sha` with `git rev-parse HEAD`

## Critical rules

- **Only amend the recovery branch's tip, not any older commit.** If multiple keepers have been authored, you can only amend the latest.
- **Only amend if the recovery branch is not pushed.** If the user already pushed, amending would create divergent history; surface to user instead.
- **Don't add `Co-Authored-By` unless the user requested it.** Many projects have policies; don't impose.
- **Verify the message stands alone.** Future-you reading the commit log a year later should understand without context.

## Coordination

- File reservation: `paths=["{PROJECT}", "{WORKSPACE}/commit_msg_<NPAD>.txt"]`, `exclusive=true`, `reason="stash-janitor-amend-<N>"`.

## Quality gates

- [ ] Message follows the template (subject + 3 body sections + citation)
- [ ] No `Co-Authored-By` (unless requested)
- [ ] Convention-compliant
- [ ] git commit --amend succeeded
- [ ] apply_log.tsv updated with new SHA

## Exit criteria

Commit message rewritten; amended SHA recorded in apply_log.tsv. Run continues to next keeper.
