# Batch Mode — Multi-Repo Orchestration

**Source axiom:** Axiom 23. The user has ~162 repos in `/data/projects`; running cleanup across many at once is a real workflow (cass sessions A and B documented 13- and 20-repo batch runs in February 2026).

This reference codifies the orchestration patterns those sessions surfaced.

---

## When to use batch mode

- 5+ repos to clean
- Repos share an organization (the user's ~162 repos in `/data/projects`)
- Per-repo `full` runs would be sequential and tedious
- Tooling (NTM, Agent Mail, beads) is available for coordination

When you have one repo: just run the skill normally. Batch mode is overhead unless you have 5+ targets.

---

## Skip-list first principle

The cardinal rule: **decide which repos are EXCLUDED before deciding which categories within remaining repos**. Trying to opportunistically cleanup an excluded repo is the root cause of many bad outcomes.

### What to exclude

| Reason | Example | Source |
|--------|---------|--------|
| External-primary-development | `asupersync` (per the user's MEMORY.md: "primary dev happens on another machine") | cass session B finding |
| Submodule-only repos | `rust/` (the Rust compiler vendored as a sub-repo) | cass session A finding |
| Third-party forks | Any repo whose `git config remote.origin.url` is not under the user's GitHub org | cass session A finding |
| Mid-rebase / mid-merge | Any repo where `git status` shows "rebase in progress" | git-doctor.sh |
| Dirty submodules with uncommitted work | Any repo with `-dirty` markers in submodule status | git-doctor.sh + Phase 0 |
| Frozen archives | Any subdir/repo the user marks "do not touch" in MEMORY.md | user policy |
| Known broken (recovery in progress) | Any repo currently being recovered from a previous bad cleanup | per-run state |

The skill consults:
- `~/.claude/MEMORY.md` (user-level policies)
- Per-repo `AGENTS.md` (repo-level policies)
- `ru-multi-repo-workflow` skill if installed (it has its own skip-list)

The first phase of a batch run produces `batch_skip_list.md`:

```markdown
## Skip list — batch run 2026-05-08

### Excluded (will not run)
- `asupersync` — external-primary-development per ~/.claude/MEMORY.md:42
- `rust/` — submodule-only; out of scope per Axiom 23
- `ub_for_devs_fork/` — third-party fork (origin not user's)
- `frozen_archive_2024/` — user MEMORY.md says "do not touch"

### Included (will run)
- `frankensqlite`, `ntm`, `beads_viewer`, `mcp_agent_mail`, ...
- (full list in batch_inclusion.tsv)
```

---

## Per-repo branch-policy registry

The cass session B finding: not every repo follows `main:master` mirror. The skill maintains a registry:

```yaml
# batch_branch_policy.yaml
default_branch: main
sync_to:
  master: true   # main:master mirror is default
exceptions:
  ultimate_bug_scanner:
    default_branch: master
    sync_to: {}  # no sync; master IS the primary
  toon_rust:
    default_branch: master
    sync_to: {}
  sqlmodel_rust:
    default_branch: master
    sync_to: {main: true}  # opposite mirror direction
  some_repo:
    sync_to: {develop: true}  # also push to develop
```

When the skill processes a repo, it looks up the policy. The push instructions in the handoff report use the right pair.

The skill detects most policies automatically (via `git config remote.origin.HEAD` + branch existence checks); explicit overrides live in `~/.claude/batch_branch_policy.yaml`.

---

## Disk-pressure pre-flight

The cass session B finding: a 49 GB cache in `/tmp/rch/<project>` filled `/tmp` and broke 13 repos at once because they couldn't allocate temp objects.

Before any batch run:

```bash
echo "=== disk pressure pre-flight ==="
df -h / /tmp /var/tmp /home  # all key mount points

# Check for known caches that bloat
for cache in /tmp/rch /tmp/cargo* /tmp/sccache /tmp/uv-cache ~/.cargo/registry ~/.cache/pip ~/.cache/yarn; do
    if [[ -d "$cache" ]]; then
        size=$(du -sh "$cache" 2>/dev/null | awk '{print $1}')
        echo "$cache: $size"
    fi
done

# Warn if any single bucket >5GB
```

If `/tmp` is >85% full or any cache is >5GB, the batch run halts and asks the user to clean up first. The skill outputs a `disk_pressure_report.md` with explicit `du -sh` per bucket.

---

## Per-repo orchestration

For each included repo, the batch orchestrator:

1. Run `git-doctor.sh` (refuse if hard-fail; warn on soft conditions).
2. Run `discover-project.sh` to detect archetype + branch policy.
3. Run the skill in the user-chosen mode (`triage-only` first by default; user can escalate to `full` per repo).
4. Capture the per-repo handoff in `batch_per_repo_results.tsv`.
5. Apply the per-repo branch policy for any push.
6. Continue to next repo.

Between repos, re-run the disk-pressure check (especially if Phase 6 / Phase 9 used a lot of /tmp).

---

## Per-repo result schema

`batch_per_repo_results.tsv`:

```
repo            mode_run        outcome    candidates  commits  duration_s  bundle_path                          handoff_path
frankensqlite   full            success    87          8        9842        /data/projects/frankensqlite/.repo_janitor_workspace/recovery-bundle-... /data/projects/frankensqlite/.repo_janitor_workspace/handoff_report.md
mcp_agent_mail  harden-secret-leak success 1           4        7203        /tmp/mcp_agent_mail-backup-...        /data/projects/mcp_agent_mail/.repo_janitor_workspace/handoff_report.md
ntm             triage-only     success    36          0        1842        /data/projects/ntm/.repo_janitor_workspace/recovery-bundle-...   /data/projects/ntm/.repo_janitor_workspace/handoff_report.md
beads_viewer    full            success    31          5        4129        /data/projects/beads_viewer/.repo_janitor_workspace/recovery-bundle-...  /data/projects/beads_viewer/.repo_janitor_workspace/handoff_report.md
asupersync      skip            external-primary-dev   N/A     N/A          (none)                                (none)
rust/           skip            submodule-only         N/A     N/A          (none)                                (none)
```

---

## Push policy

After all repos are processed, the skill emits a single `batch_push_commands.sh` script (NOT auto-executed; user reviews and runs):

```bash
#!/usr/bin/env bash
# batch_push_commands.sh — review before running

set -e

# frankensqlite (main → master mirror)
cd /data/projects/frankensqlite
git push origin repo-janitor-2026-05-08
git push origin repo-janitor-2026-05-08:master

# mcp_agent_mail (main only after secret-leak rewrite)
cd /data/projects/mcp_agent_mail
git push --force-with-lease origin main
git push --force-with-lease origin main:master

# ntm (triage-only mode; no commits to push)
# (skipped)

# beads_viewer (main → master mirror)
cd /data/projects/beads_viewer
git push origin repo-janitor-2026-05-08
git push origin repo-janitor-2026-05-08:master

echo "Batch push complete."
```

The user reads, may modify, and runs.

---

## Concurrent-agent reality

Per cass session B: a multi-agent VPS will dirty repos faster than a single agent can commit them. The orchestrator must do **multiple commit rounds**, not one.

Pattern:

```
Round 1: process repos in initial set
Round 2: re-scan all included repos for newly-dirty state; process delta
Round 3 (if needed): same
Round N: stop when delta is empty (no new dirty work)
```

Each round writes a numbered subdir in the workspace:

```
.repo_janitor_workspace/batch/
├── round_1/
│   ├── per_repo_results.tsv
│   └── disk_pressure_report.md
├── round_2/
│   ├── per_repo_results.tsv
│   └── newly_dirty.tsv
└── round_3/
    └── per_repo_results.tsv
```

The orchestrator can be interrupted between rounds and resume.

---

## Tooling integration

### NTM (multi-pane tmux orchestrator)

When the user has NTM installed, batch mode can spawn one pane per repo:

```bash
ntm spawn /data/projects 12 cc
ntm broadcast 'cd /data/projects/<repo> && /git-repo-janitor mode=triage-only'
```

Each pane runs the skill on one repo. The orchestrator collects results from each pane via NTM's inbox.

### Agent Mail

Coordination across panes uses Agent Mail with thread-id `repo-janitor-batch-<DATE>-<RUN-ID>`. Each per-repo agent reports completion via:

```python
send_message(
  thread_id="repo-janitor-batch-2026-05-08-001",
  subject="[batch][repo:<name>] phase 5 complete; 16 candidates triaged",
  ...
)
```

### Beads

A single beads issue tracks the batch:

```bash
br create --title "Repo janitor batch run 2026-05-08 (12 repos)" --type=task --priority=4
```

Sub-issues per-repo: `br create --title "[<repo>] cleanup pass" --depends-on=<batch-id>`. After all sub-issues close, the parent closes.

### bv (graph-aware triage)

After the batch completes, run `bv --robot-triage` to surface follow-ups across the now-cleaner repo set.

---

## "Top 5 dirty repos" pattern

Sometimes the user wants priority order. The cass session A finding suggests the criterion: stargazer count × recent push activity. The batch orchestrator can run:

```bash
gh repo list <user> --limit 200 --visibility public \
   --json name,pushedAt,stargazerCount \
   | jq -r 'sort_by(.stargazerCount) | reverse | .[:20] | .[] | "\(.stargazerCount)\t\(.pushedAt[:10])\t\(.name)"'
```

Then ranks by candidate count (the bigger the candidates list, the more cleanup-bang-per-buck). The first 5 get `full` mode; the rest get `triage-only` for now.

---

## Batch-specific anti-patterns

1. **Never run the same destructive operation across all repos in one shot.** Per-repo verbatim authorization is still required for `harden-secret-leak`, `git rm` in critical files, etc.

2. **Don't share a single `cleanup_authorization.txt` across repos.** Each repo gets its own; the user types verbatim auth for each repo separately. The batch orchestrator queues these requests and presents them in order.

3. **Don't skip the per-repo `git-doctor`.** A repo mid-rebase or with phantom deletions is dangerous; per-repo health-check is non-negotiable.

4. **Don't mass-update `.gitignore` patterns across repos.** Each repo's archetype + history is unique. The batch orchestrator may share *suggested* patterns but the user reviews per-repo before applying.

5. **Don't push all repos at once.** The push script is generated but the user controls execution. If the user has CI cost considerations or branch-protection rules, they may stage pushes.

---

## Worked example: the Apr-27 cleanup that motivated this skill

(From the cass mining; same session as the canonical `git-repo-janitor` example.)

User invocation: "ok start with the public repos with the most commits and recent activity since they're obviously the most important to fix."

Processing order (by GitHub stargazer count):
1. `frankensqlite` (157 stars, 109 → 45 root files, 8 commits, 90 min)
2. `coding_agent_session_search` (CASS, 717 stars, 46 → 18, 5 commits, 60 min)
3. `pi_agent_rust` (801 stars, 41 → 16, 5 commits, 70 min)
4. `ntm` (no stargazer count provided, 36 → 21, 4 commits, 55 min)
5. `beads_viewer` (1480 stars, 31 → 18, 3 commits, 45 min)
6. `mcp_agent_mail` (1900 stars, 29 → 24 + secret-leak escalation, 9 commits across two modes, 180 min)
7. `asupersync` — DEFERRED ("primary development happens on another machine, large changes risk conflicts")

Total time: 8.3 hours including the secret-leak incident. Total root file reduction: 292 → 142 files (~50% reduction across 6 repos). One secret rotated. Lessons captured in INCIDENT-PLAYBOOK and FAILURE-MODES.

---

## Resumability across batches

A batch run can be resumed across days:

- Each round's results are in `<workspace>/batch/round_N/`.
- A `batch_state.json` tracks `currently_processing`, `completed`, `pending`, `failed`.
- Re-entry: read state, start from `pending`.

If a per-repo run is interrupted mid-Phase, that repo's state is captured in its own `<repo>/.repo_janitor_workspace/run_state.json` (per OPERATING-MODES.md resumability). The batch orchestrator just resumes both layers.

---

## When NOT to use batch mode

- Single repo
- Repos that span different orgs / different access policies
- Repos under active development by a non-skill operator (you'll fight them)
- When user attention is the bottleneck, not skill throughput (batch mode requires user attention per repo gate)

For these cases, run the skill normally per repo.
