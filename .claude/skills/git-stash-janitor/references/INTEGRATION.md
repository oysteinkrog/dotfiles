# Integration With Beads, Agent Mail, and Other Skills

The skill plugs into the project's broader agent ecosystem.

---

## Beads (`br`)

Beads is the project's local-first issue tracker. Per AGENTS.md, the workflow is:

1. **At run start (Phase 1):** check if beads is available:
   ```bash
   command -v br >/dev/null 2>&1 && br ready --json | head -1
   ```

2. **At run start (Phase 1):** create a beads issue for the run:
   ```bash
   RUN_ID=$(br create \
     --title "stash janitor pass on <project> (<N> stashes)" \
     --type=task \
     --priority=4 \
     --json \
     | jq -r '.id')
   echo "$RUN_ID" > $WORKSPACE/run_id.txt
   br update $RUN_ID --status=in_progress
   ```

   The issue ID becomes the **thread_id** for Agent Mail and the **reason** for file reservations.

3. **At handoff (Phase 10):** close the beads issue with a summary:
   ```bash
   br close $RUN_ID --reason "Triaged $N stashes; recovered $K commits on stash-recovery-<DATE>; bundle at <path>"
   ```

4. **`br sync --flush-only`** before ending the session (per AGENTS.md "Landing the Plane"). Then `git add .beads/ && git commit -m "sync beads after stash janitor run"`.

If `br` isn't available, skip these steps and record `beads_skipped: true` in the handoff report.

---

## Agent Mail (MCP)

Agent Mail provides multi-agent coordination. Per AGENTS.md:

1. **At run start:** register identity, reserve `.git/` advisory:
   ```
   ensure_project(project_key="<abs-path>")
   register_agent(project_key, program="claude-code", model="opus-4-7")

   file_reservation_paths(
     project_key,
     agent_name,
     paths=[".git/**", ".stash_janitor_workspace/**"],
     ttl_seconds=3600,
     exclusive=false,           # advisory; don't block other agents
     reason="<beads-id>"
   )
   ```

   The advisory reservation tells other agents "I'm running stash-janitor here" without blocking them. They can still work — but a parallel stash-janitor invocation would notice.

2. **Send announcement:**
   ```
   send_message(
     thread_id="<beads-id>",
     subject="[<beads-id>] Start: stash janitor on <project> (N stashes)",
     body="Triaging N stashes; will create recovery branch stash-recovery-<DATE>",
     ack_required=false
   )
   ```

3. **Phase-by-phase progress** — optional; for long Comprehensive runs:
   ```
   send_message(
     thread_id="<beads-id>",
     subject="[<beads-id>] Phase 6 progress: 5/12 keepers applied",
     body="..."
   )
   ```

4. **At handoff:** final reply + release reservations:
   ```
   send_message(
     thread_id="<beads-id>",
     subject="[<beads-id>] Completed: stash janitor",
     body="<handoff summary>"
   )
   release_file_reservations(project_key, agent_name, paths=[".git/**", ".stash_janitor_workspace/**"])
   ```

If Agent Mail isn't reachable, skip and record in handoff.

---

## bv

`bv` is the project's graph-aware triage engine. Used at Phase 10 to surface follow-ups:

```bash
bv --robot-triage > "$WORKSPACE/post_run_bv_triage.json"
```

This often reveals: the recovered commit unblocks a beads issue (because the issue depended on that fix landing). The handoff report includes a "Newly unblocked beads" section in this case.

---

## ubs (Ultimate Bug Scanner)

If `project_profile.json:ubs_available=true`, Phase 6 / Phase 7 / Phase 8 all run UBS as part of the quality gates:

```bash
ubs <changed-files>   # Per-apply check (Phase 6/7)
ubs .                 # Project-wide (Phase 8 fresh-eyes)
```

Exit 0 = pass. Exit >0 = fix or skip the keeper.

---

## DCG (Destructive Command Guard)

DCG is a hook that blocks destructive commands. The skill is **designed to never need** the commands DCG blocks:

| DCG-blocked | Why the skill doesn't need it |
|-------------|-------------------------------|
| `rm -rf` | Bundle lifecycle is the user's responsibility |
| `git reset --hard` | Reverts via `git apply -R <bundle>/diffs/<n>.diff` |
| `git clean -fd` | The skill never cleans the working tree |
| `git push --force` | The skill never pushes |

If DCG blocks something the skill expected to run, that's a bug — open an issue against the skill, not against DCG.

---

## Other Skills (Cross-References)

The skill references these skills in its prose. They're all optional; fallbacks have inline alternatives.

| Skill | Used for | Inline fallback |
|-------|----------|-----------------|
| `/operationalizing-expertise` | Operator card format | Inline operator cards in OPERATOR-LIBRARY.md |
| `/codebase-archaeology` | Phase 1 reconnaissance | Direct read of AGENTS.md / README.md / sample files |
| `/codebase-report` | Phase 1 architecture summary | Inline 200-word prose summary |
| `/agent-mail` | Multi-agent coordination | Skip; record in handoff |
| `/beads-br` (beads) | Issue tracking | Skip; record in handoff |
| `/beads-bv` | Post-run triage | Skip; recovery commits unblock work organically |
| `/ubs` | Bug scanning | Skip; rely on test/typecheck/lint only |
| `/idea-wizard` | Phase 11 user-lens review (optional) | Skip — Phase 11 is optional anyway |
| `/multi-pass-bug-hunting` | Phase 8 fresh-eyes structure | Inline three-prompt round (verbatim) |
| `/dcg` | Awareness of blocked commands | Inline awareness — design around DCG |

If any helper skill isn't installed, the skill notes the absence and uses the inline fallback. Never blocks the run.

---

## Hooks

Pre-commit hooks (husky, lefthook, pre-commit, project-specific) run as part of `git commit` and ARE the project's quality gates. The skill never bypasses them with `--no-verify`.

If a hook fails on a Phase 6 commit:
1. The commit doesn't land.
2. The skill surfaces the hook output to the user.
3. The user decides: adapt the recovered code, accept the failure, or skip the keeper.

---

## Multi-Agent Concurrency

**NTM and other swarm tools are optional** — the skill's default is single-session execution with parallel Task subagents (see ORCHESTRATION.md § "Default Execution Model"). The notes below apply only when the user is *already* running a swarm.

If `vibing-with-ntm` or another swarm tool is running concurrently:

- The advisory file reservation on `.git/**` tells the orchestrator "stash-janitor active here".
- Other agents shouldn't kick off competing stash-janitor runs (the orchestrator should coordinate).
- Concurrent agents working on the project's normal code are FINE — the working-tree-state guidance handles them.

---

## CASS

If `cass` is installed and indexed, Phase 1 can mine prior sessions:

```bash
cass search "stash janitor" --robot --limit 5
cass search "<project>" --robot --limit 5
```

This surfaces:
- Prior runs of this skill on this project (good — informs Phase 0 about expected stash patterns)
- Prior incidents where stashes were lost (good — informs the user about historical concerns)
- Patterns the user prefers (e.g., "always run in Comprehensive mode")

If `cass` isn't installed, skip.

---

## What This Skill Does NOT Integrate With

- **GitHub PR creation** — the skill prints the push command; the user opens the PR.
- **CI/CD trigger** — pushing the recovery branch may trigger CI; the skill doesn't manage that.
- **Slack / email notifications** — the handoff report is on disk; the user shares it.
- **Code review tools** — the skill doesn't request reviews; users open PRs and request reviews themselves.

These are out-of-scope deliberately. The skill's surface is the local repo; integration with external systems happens via the user.
