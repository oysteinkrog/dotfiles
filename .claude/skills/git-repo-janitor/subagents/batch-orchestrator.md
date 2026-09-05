# Subagent: batch-orchestrator

**Phase:** Across many repos (BATCH-MODE)
**Spawn:** Once per batch run.

## Role

Orchestrate cleanup across multiple repos per BATCH-MODE.md.

## Prompt

You are orchestrating a batch cleanup across multiple repos.

Inputs:
- The user's repo list (from interview Stage 2 / BATCH-MODE.md, or auto-discovery via `gh repo list`).
- Per-repo skip-list (from `~/.claude/MEMORY.md` and per-repo AGENTS.md).
- Default mode for the batch (from interview).

Steps:

### Phase batch-0: Skip-list-first

Per Axiom 23, decide which whole repos are EXCLUDED before any per-file work:

1. Read `~/.claude/MEMORY.md` for explicit user policies (external-primary-dev, frozen archives, etc.).
2. Read each repo's `AGENTS.md` for repo-level policies.
3. Run `git-doctor.sh` per repo; refuse repos in mid-rebase / mid-merge / etc.
4. Detect third-party forks via `git config remote.origin.url` not matching the user's GitHub username.
5. Detect submodule-only repos (the parent of `/data/projects/rust/` etc.)

Output: `<workspace>/batch_skip_list.md` with reasons per excluded repo.

### Phase batch-1: Disk-pressure pre-flight

Run `bash scripts/check-disk-pressure.sh`:

```bash
df -h / /tmp /var/tmp /home
for cache in /tmp/rch /tmp/cargo* /tmp/sccache /tmp/uv-cache ~/.cargo/registry ~/.cache/pip ~/.cache/yarn; do
    [[ -d "$cache" ]] && du -sh "$cache" 2>/dev/null
done
```

If any /tmp bucket >5GB OR any mount point >85% full, HALT and ask user to clean before batch run.

### Phase batch-2: Branch-policy detection

Per repo, detect the branch policy (main only, main:master mirror, master only, etc.). Build `<workspace>/batch_branch_policy.yaml`. Surface ambiguities to user.

### Phase batch-3: Per-repo execution

For each non-excluded repo, in user-prioritized order (default: highest-stargazer first):

1. Run `git-doctor.sh` (re-check; concurrent agents may have changed state).
2. Run `discover-project.sh` per archetype.
3. Run the skill in the user-chosen mode (default: `triage-only` first, escalate to `full` per-repo).
4. Capture per-repo handoff in `<workspace>/batch/round_<N>/per_repo_results.tsv`.
5. Apply per-repo branch policy to push commands.
6. Continue to next repo.

### Phase batch-4: Multi-round detection

Per BATCH-MODE.md "concurrent-agent reality": multi-agent VPS will dirty repos faster than a single agent can commit. After all repos in round-1 are processed:
- Re-scan all included repos for newly-dirty state
- If new candidates found, queue round-2
- Continue until convergence (no new dirty work)

### Phase batch-5: Push script generation

Generate `batch_push_commands.sh` (NOT auto-executed). User reviews and runs manually.

### Phase batch-6: Final handoff

Generate `<workspace>/batch_handoff_report.md`:

```markdown
## Batch handoff — 2026-05-08

**Repos processed:** 12 of 15 included (3 excluded per skip list)
**Total candidates triaged:** 487
**Total commits authored:** 38
**Total wall time:** 4h 32m
**Disk-pressure incidents:** 0
**Secret-leak escalations:** 1 (mcp_agent_mail; rotated; rewritten; pushed)

### Per-repo summary

| Repo | Mode | Outcome | Candidates | Commits | Bundle |
|------|------|---------|-----------:|--------:|--------|
| frankensqlite | full | success | 87 | 8 | /data/projects/frankensqlite-repo... |
| ...

### Excluded repos (skip-list)
- asupersync (external-primary-dev per MEMORY.md)
- rust/ (submodule-only)
- ub_for_devs_fork (third-party fork)

### Push instructions
Run `<workspace>/batch_push_commands.sh` after review.
```

## Output

- `<workspace>/batch_skip_list.md`
- `<workspace>/batch_branch_policy.yaml`
- `<workspace>/batch/round_<N>/per_repo_results.tsv` per round
- `<workspace>/batch_push_commands.sh`
- `<workspace>/batch_handoff_report.md`
- Per-repo workspaces unchanged (each repo has its own `.repo_janitor_workspace/`)

## Tools used

Read, Bash, Edit. Spawns sub-skills (one per repo) via the Task tool.

## Time budget

Hours to days for large batches. Always resumable per BATCH-MODE.md "Resumability across batches".
