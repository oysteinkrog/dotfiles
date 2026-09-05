# Integration With Beads, Agent Mail, bv, dcg, slb

The skill plugs into the project's broader agent ecosystem. None of these integrations is *required* — every one has a graceful skip path that records `<tool>_skipped: true` in the handoff and continues. But on a healthy fleet they make the run auditable, conflict-free, and discoverable from outside the workspace.

Adapted from [git-stash-janitor's INTEGRATION.md](../../git-stash-janitor/references/INTEGRATION.md). Departures from the sibling skill are noted inline.

> **Why integrate at all?** Per [SKILL.md "Up-Front Confirmations" point 11](../SKILL.md#up-front-confirmations-ask-before-starting): "If yes, run `agent-mail file_reservation_paths(... [".git/worktrees/**", ".git/refs/heads/**"], reason="branch-rationalization-<run-id>")` advisory-only." A run that mutates 80 branches and 20 worktrees needs to be *visible* to other agents on the same project; otherwise a parallel `br ready` worker may pick a task whose branch you're about to delete.

---

## 1. Beads (`br`) — the run-id origin

Beads is the project's local-first issue tracker. Per AGENTS.md ("Beads (br) — Dependency-Aware Issue Tracking"), the issue id becomes the **run-id** for everything else in this run.

### 1.1 At Phase 0.5 (handoff to inventory) — create the issue

```bash
command -v br >/dev/null 2>&1 || { echo "br not available; recording beads_skipped" ; echo beads_skipped=true >> "$WS/integration.log" ; exit 0; }

# Counts captured at intake:
W=$(git -C "$PROJECT" worktree list --porcelain | grep -c '^worktree ')
W_NON_MAIN=$((W - 1))                     # exclude the main repo entry
B=$(git -C "$PROJECT" branch | wc -l | tr -d ' ')

BASENAME=$(basename "$PROJECT")
RUN_ID=$(br create \
  --title "branch+worktree rationalization on $BASENAME ($B branches, $W_NON_MAIN worktrees)" \
  --type=task \
  --priority=4 \
  --json \
  | jq -r '.id')
echo "$RUN_ID" > "$WS/run_id.txt"
br update "$RUN_ID" --status=in_progress
```

> **Why:** Per AGENTS.md "Mapping Cheat Sheet": "Mail `thread_id` = `beads-###`; Mail subject = `[beads-###] ...`; File reservation `reason` = `beads-###`; Commit messages: include `beads-###` for traceability." The run-id is the universal join key.

The skill writes the run-id into:

| Artifact | Field |
|---|---|
| `<workspace>/run_id.txt` | The id, single-line, no whitespace |
| `<workspace>/integration.log` | `run_id=<id>` |
| `<bundle>/README.md` | "Run id: `<id>`" header |
| Every keeper commit message in Phase 8 | Trailer: `Beads-Issue: <id>` |

### 1.2 Per-phase status updates

Beads' coarse status field doesn't have per-phase granularity, so the skill uses status transitions only at Phase 0.5 (`in_progress`) and Phase 11 (`closed`). For finer-grained progress, use Agent Mail messages on the same thread (Section 2.3).

### 1.3 At Phase 11 (handoff) — close the issue

```bash
RUN_ID=$(cat "$WS/run_id.txt")
br close "$RUN_ID" --reason "Triaged $B branches + $W_NON_MAIN worktrees; recovered $K keeper commits on $RATIONALIZATION_BRANCH; bundle at <path>; cleanup completed (worktrees: $WT_REMOVED, branches: $BR_DELETED)."
```

If Phase 10 cleanup did not run (`apply-only` or `triage-only` mode), close with `--reason "triage-only run; no cleanup performed"` and leave the rationalization branch + bundle for the user.

### 1.4 Sync at end of session

Per AGENTS.md ("Landing the Plane"):

```bash
br sync --flush-only       # writes .beads/beads.jsonl from the SQLite db
git add .beads/
git commit -m "sync beads after branch rationalization run on $BASENAME

Beads-Issue: $RUN_ID"
```

> **Why:** Per AGENTS.md note on `br`: "br is non-invasive and never executes git commands. After syncing, you must manually commit the `.beads/` directory." If the skill skips this step, the run-id won't appear in `git log` and future archaeology can't connect the rationalization commit cluster to the issue.

### 1.5 Failure modes

| Symptom | Diagnosis | Action |
|---|---|---|
| `br create` fails with "database locked" | Parallel `br` process holds the SQLite lock | Wait 5s and retry; if still locked, set `beads_skipped=true` in `integration.log` and continue with `RUN_ID=branch-rationalization-$(date -u +%Y%m%dT%H%M%S)-$BASENAME` (a synthetic id good enough for thread-keying) |
| `br update <id> --status=...` rejects the transition | The id was created at a different priority/state by a prior run with the same workspace | Read the issue: `br show "$RUN_ID" --json`; if the issue is closed, create a new one |
| `.beads/beads.db` is missing | beads not initialized in this project | Run `br init` if user opted in; otherwise skip |
| `.beads/beads.jsonl` doesn't exist after `br sync --flush-only` | beads version too old | The skill records the failure; commit only `.beads/` directory if it has any content |

These map to incident codes I9 (database locked) and I20 (general failure). See [INCIDENT-PLAYBOOK.md](INCIDENT-PLAYBOOK.md) (forthcoming) once authored; for now, the in-line fallback above is authoritative.

---

## 2. Agent Mail (MCP) — the coordination thread

Agent Mail provides multi-agent coordination via MCP tools. The skill uses it for: (a) registering visibility, (b) reserving the file surface mid-run, (c) announcing milestones, (d) detecting conflicts with parallel agents.

### 2.1 Identity and project registration

```
ensure_project(project_key="<abs-path-of-project-root>")
register_agent(project_key="<abs-path>", program="claude-code", model="opus-4-7")
```

> **Why:** Per AGENTS.md "Common Pitfalls": `"from_agent not registered"`: Always `register_agent` in the correct `project_key` first. Skipping this step makes every later `send_message` and `file_reservation_paths` fail.

The macro `macro_start_session` does both in one call. Prefer it — it's faster and atomic.

### 2.2 File reservations — the load-bearing surface

The skill operates on three different file surfaces. Reserve all three at Phase 0.5:

```
file_reservation_paths(
  project_key="<abs-path>",
  agent_name="<from register_agent>",
  paths=[
    ".git/worktrees/**",                                            # worktree admin metadata (Pass A inventory)
    ".git/refs/heads/**",                                           # branch refs (Pass B inventory + Phase 10 deletes)
    ".worktree_branch_rationalization_workspace/triage/**",         # parallel triage worker outputs (Phase 5)
    ".worktree_branch_rationalization_workspace/conflicts/**"       # conflict context (Phase 8)
  ],
  ttl_seconds=3600,
  exclusive=true,
  reason="branch-rationalization-<run-id>"
)
```

| Field | Value | Why |
|---|---|---|
| `paths` | The four globs above | Covers everything the skill mutates: branch refs, worktree admin, triage outputs, conflict context |
| `ttl_seconds` | `3600` | Phases 0–6 typically complete inside an hour; the cleanup-conductor extends per Section 2.4 |
| `exclusive` | `true` | The skill needs sole ownership of the branch-and-worktree namespace during destructive phases |
| `reason` | `branch-rationalization-<run-id>` | The run-id derived from beads. Visible to other agents looking at the leases |

The macro `macro_file_reservation_cycle` handles acquire + heartbeat + release with TTL refresh. Use it whenever the run will exceed the initial TTL.

> **Why these four globs and not just `.git/**`?** Per [Axiom 0](../SKILL.md#the-rationalization-kernel-universal-axioms): "Worktrees are filesystem checkouts; branches are refs. They have different smells, different inventories, different removal mechanics." Reserving `.git/**` would also lock out `.git/objects/` (which other agents legitimately read during commits) and `.git/index` (which other agents write on every staging operation). The four globs are the precise *destructive* surface.

### 2.3 Phase milestones — announcement + handshake

Use the run-id as the thread_id; prefix subjects with `[<run-id>]`. Send messages at:

| Phase | Subject | Body sketch |
|---|---|---|
| 0.5 | `[<run-id>] Start: branch rationalization on <basename> (B branches, W worktrees)` | Counts, mode, rationalization-branch name, bundle path |
| 3 (bundle verified) | `[<run-id>] Phase 3 complete: bundle verified at <bundle-path>` | byte-equality + bundle-round-trip results |
| 6 (triage frozen) | `[<run-id>] Phase 6: triage frozen — N novel-and-accretive, M superseded, K garbage` | Summary table from `triage_decision.md` |
| 7 (harmonization plan ready for review) | `[<run-id>] Phase 7: harmonization plan ready (F contested files; per-file synthesis proposed)` | Link to `harmonization_plan.md`; `ack_required=true` if the user has a coordinating agent |
| 8 (apply complete) | `[<run-id>] Phase 8: K keepers landed on <rationalization-branch>` | List of (branch, strategy, new-sha) |
| 10 (cleanup complete) | `[<run-id>] Phase 10: removed W worktrees + deleted B branches` | Counts per bucket |
| 11 (handoff) | `[<run-id>] Completed: branch rationalization` | Full handoff summary; release reservations |

The macro `macro_contact_handshake` is the right primitive for the start-of-run announcement when other agents may be active on the project — it sends the message AND fetches their inbox to detect conflicts in one round-trip.

### 2.4 Refreshing TTL on long Comprehensive runs

A Comprehensive run can exceed the default 3600s TTL. The cleanup-conductor extends by 3600s before Phase 10:

```
file_reservation_paths(
  project_key="<abs-path>",
  agent_name="<self>",
  paths=[".git/refs/heads/**", ".git/worktrees/**"],
  ttl_seconds=3600,
  exclusive=true,
  reason="branch-rationalization-<run-id>-cleanup-extension"
)
```

### 2.5 Release at handoff

```
release_file_reservations(
  project_key="<abs-path>",
  agent_name="<self>",
  paths=[
    ".git/worktrees/**",
    ".git/refs/heads/**",
    ".worktree_branch_rationalization_workspace/triage/**",
    ".worktree_branch_rationalization_workspace/conflicts/**"
  ]
)
```

### 2.6 Common pitfalls

Per AGENTS.md "Common Pitfalls":

| Symptom | Cause | Fix |
|---|---|---|
| `"from_agent not registered"` | Skipped Section 2.1 | Run `register_agent` in the correct `project_key` first |
| `"FILE_RESERVATION_CONFLICT"` | Another agent has overlapping `exclusive=true` lease | Wait for expiry, switch to `exclusive=false` advisory-only, or coordinate with the other agent's run-id (their lease's `reason` field tells you who) |
| `JWT auth error: missing bearer / wrong kid` | If JWT+JWKS enabled, include bearer token with matching `kid` | Refresh credentials; the macro `macro_start_session` does this implicitly |
| Messages send but `fetch_inbox` returns empty | Agent name registered under different project_key | Verify `project_key` is the absolute path; never relative |

---

## 3. bv — graph-aware follow-up at handoff

`bv` is the graph-aware triage engine for Beads projects. The skill uses it at Phase 11 to surface follow-up items the recovered commits unblock and to detect priority misalignment created by the harmonization.

```bash
# At Phase 11 — only if .beads/ exists in the project:
if [ -d "$PROJECT/.beads" ] && command -v bv >/dev/null 2>&1; then
  bv --robot-triage --json > "$WS/post_run_bv_triage.json"
  bv --robot-priority --json > "$WS/post_run_bv_priority.json"
fi
```

| Output | What to look for |
|---|---|
| `post_run_bv_triage.json` (`.recommendations[]`) | Issues whose blockers depended on a now-recovered keeper landing — surface in the handoff under "Newly unblocked beads" |
| `post_run_bv_priority.json` (`.misalignments[]`) | Priorities recomputed after the rationalization branch lands — flag any P1 issues that became higher-confidence-actionable as a result |
| `post_run_bv_triage.json:.quick_ref` | Counts; goes into the handoff as a one-liner |

> **Why:** Per AGENTS.md "bv — Graph-Aware Triage Engine": "**`bv --robot-triage` is your single entry point.** It returns: `quick_ref`, `recommendations`, `quick_wins`, `blockers_to_clear`, `project_health`, `commands`." The branch rationalization typically unblocks several issues whose depended-on commit was sitting on a now-deleted branch — `bv` finds them automatically.

**Skip if `.beads/` doesn't exist.** Many projects won't have beads; the skill records `bv_skipped: true` and continues.

**Never run bare `bv` from inside the skill.** Per AGENTS.md: "**CRITICAL: Use ONLY `--robot-*` flags. Bare `bv` launches an interactive TUI that blocks your session.**"

---

## 4. dcg (Destructive Command Guard) — the design-around

DCG is a hook that blocks destructive commands. Per [SKILL.md Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms): "DCG blocks `rm -rf` and we don't fight it. `git worktree remove <path>` refuses on dirty worktrees — that refusal is a feature." The skill is *designed not to need* the commands DCG blocks.

| DCG-blocked | Skill alternative |
|---|---|
| `rm -rf <worktree-path>` | `git worktree remove <path>` (structured op; refuses on dirty; archives the dirty state in the bundle first) |
| `rm -rf <bundle>/` | The skill never deletes the bundle — bundle lifecycle is the user's. Per Axiom 18: "Drop the bundle only at the user's pace." |
| `git reset --hard` | All apply rollbacks go through `git cherry-pick --abort` / `git merge --abort` (the structured operations) |
| `git clean -fdx` | The skill never cleans the working tree |
| `git push --force` / `git push --delete` | Per Axiom 15: "Remote cleanup is out of scope by default. The skill never runs `git push --delete`, `git push --force`, or any remote-mutating command." |
| `git branch \| xargs git branch -D` | Per Axiom 10: forbidden; iterate one entry at a time, restate verbatim before each |
| `find /data/projects -name "*-wt-*" -exec rm -rf` | Per Axiom 10 + Axiom 11 — both forbidden in combination |

### 4.1 If DCG blocks something the skill expected to run — that's a bug

The skill is designed to be DCG-clean. If a DCG block fires, treat as an internal incident:

1. **Halt the phase.** Do not retry, do not work around DCG.
2. **Spawn the incident-responder subagent** (`subagents/incident-responder.md`) with `INCIDENT_CODE=I20` (unauthorized destructive action — internal bug).
3. **Surface the DCG-blocked command verbatim** in `halt_reason.txt` plus the phase that triggered it.
4. **File a beads issue** (separate from the run-id) titled "skill bug: DCG block in branch-rationalization Phase {N}" with priority=2.
5. **Wait for user direction.** The user decides whether to override DCG (rare) or fix the skill (preferred).

> **Why this is a bug:** Per [SKILL.md "What This Skill Produces"](../SKILL.md#what-this-skill-produces): "The skill **never**: Runs `rm -rf` (DCG would block it; the skill is designed not to need it)." If DCG blocks something, either DCG was updated with a new pattern the skill triggers OR the skill has drifted into using a forbidden primitive. Either way, the user's investigation is more valuable than the work-around.

Cross-link: future [INCIDENT-PLAYBOOK.md § I20](INCIDENT-PLAYBOOK.md) when authored.

---

## 5. slb (Simultaneous Launch Button) — optional two-person rule for Phase 10

`slb` is an optional skill that requires peer review before destructive operations (`/slb` description: "Two-person rule for destructive commands"). The skill **does not require** slb; the verbatim-authorization gate (Axiom 14) is sufficient under the current safety model. But for production-critical or security-sensitive runs, the user can opt into slb at Phase 10 for an additional layer of review.

### 5.1 Opt-in at Phase 0

The intake (`assets/intake-prompt.md`) asks:

```
Phase 10 cleanup mode?
  - [default] verbatim authorization (single user types the literal commands)
  - [opt-in] verbatim authorization + slb peer review (two-person rule via /slb)
  - [opt-in] verbatim authorization + slb per-bucket peer review (one slb call
    per cleanup bucket: worktrees, garbage, superseded, ...)
```

If the user chose either slb option, write `slb_mode: per_run | per_bucket` to `project_profile.json`.

### 5.2 At Phase 10 — request peer review before each cleanup operation

The cleanup-conductor (`subagents/cleanup-conductor.md`) checks `slb_mode` and, if set, invokes:

```bash
# Before each worktree removal:
slb request \
  --command "git worktree remove $WT_PATH" \
  --reason "branch-rationalization-$RUN_ID phase 10 worktree removal" \
  --reviewer "<user-or-agent-handle>" \
  --timeout 300

# After receiving approval, proceed:
git worktree remove "$WT_PATH"
```

For `slb_mode=per_bucket`, request approval once per bucket (worktrees, garbage, superseded, already-merged, novel-stale, divergent-refactor, applied-keepers) and execute the bucket's commands as a unit upon approval.

### 5.3 If slb is not installed

Skip the slb integration; record `slb_skipped: true` in `integration.log`. The verbatim-authorization gate in Phase 10 still runs (it's the baseline; slb is the *additional* layer).

> **Why this is opt-in, not default:** The skill is already gated by Axiom 14 (per-plan verbatim authorization). Adding slb is double-gating — useful when the user wants a second human in the loop on production-critical content, but unnecessary on an agent-swarm-aftermath cleanup where one person is the sole reviewer.

---

## 6. Other skills (cross-references)

The skill references these skills in its prose. They're all optional fallbacks — every one has an inline fallback in [SKILL.md](../SKILL.md) or in this `references/` dir.

| Skill | Used for | Inline fallback |
|---|---|---|
| `/operationalizing-expertise` | Operator card format | Inline operator cards in [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) |
| `/codebase-archaeology` | Phase 1 reconnaissance | Direct read of AGENTS.md / README.md / sample files via `scripts/discover-project.sh` |
| `/codebase-report` | Phase 1 architecture summary | Inline 200-word prose summary |
| `/agent-mail` | Section 2 above | Skip; record in handoff |
| `/beads-br` | Section 1 above | Skip; record in handoff |
| `/beads-bv` | Section 3 above | Skip; the rationalization branch is informative on its own |
| `/ubs` | Phase 8 + Phase 9 quality gate | Skip; rely on test/typecheck/lint only |
| `/idea-wizard` | Phase 12 user-lens review (optional) | Skip — Phase 12 is optional anyway |
| `/multi-pass-bug-hunting` | Phase 9 fresh-eyes structure | Inline three-prompt rotation (verbatim — see [FRESH-EYES-PROMPTS.md](FRESH-EYES-PROMPTS.md)) |
| `/multi-model-triangulation` | Phase 5 + Phase 7 + Phase 9 (Council tier) | Single-model verdict accepted with `confidence < 0.7` surfaced to user |
| `/dcg` | Section 4 above (awareness) | Inline awareness — design around DCG |
| `/slb` | Section 5 above (opt-in only) | Skip; verbatim-authorization is sufficient |
| `/cass` | Section 7 — Phase 0.5 mining | Skip; the run proceeds without prior-run context. See [CASS-MINING.md](CASS-MINING.md) |

If any helper skill isn't installed and `jsm` is available, offer `jsm install <name>`. Don't block a phase if a polish skill is missing — note it and proceed with the inline fallback.

---

## 7. Hooks

Pre-commit hooks (husky, lefthook, pre-commit, project-specific) run as part of `git commit` and ARE the project's quality gates. The skill never bypasses them with `--no-verify`.

> **Why:** Per AGENTS.md "Code Editing Discipline": the user's gates exist for a reason. Per [SKILL.md "Anti-Patterns"](../SKILL.md#anti-patterns-never-do): "Bypass pre-commit hooks (`--no-verify`) — The user's gates exist for a reason."

If a hook fails on a Phase 8 commit:

1. The commit doesn't land.
2. The skill surfaces the hook output to the user.
3. The user decides: adapt the recovered code (via Edit), accept the failure (skip the keeper), or fix the underlying issue and retry.

The keeper-applier subagent treats hook failures as I7 (`conflict during apply that can't be safely resolved`). See `subagents/incident-responder.md`.

---

## 8. Multi-Agent Concurrency — see [MULTI-AGENT-COORDINATION.md](MULTI-AGENT-COORDINATION.md)

NTM and other swarm tools are optional — the skill's default is single-session execution with parallel Task subagents (see [SKILL.md "Parallelism Model"](../SKILL.md#parallelism-model)). The full coordination protocol — pre-run handshake, during-run reservations, pause-and-resume — is in [MULTI-AGENT-COORDINATION.md](MULTI-AGENT-COORDINATION.md).

---

## 9. CASS — see [CASS-MINING.md](CASS-MINING.md)

If `cass` is installed and indexed, Phase 0.5 mines prior agent sessions for: prior runs of this skill on the same project, prior manual rationalization sessions, past collisions on the same files (informs the harmonization plan), branch-creation context (informs intent attribution). Full protocol in [CASS-MINING.md](CASS-MINING.md).

---

## 10. What This Skill Does NOT Integrate With

- **GitHub PR creation** — the skill prints the push command for the rationalization branch; the user opens the PR.
- **CI/CD trigger** — pushing the rationalization branch may trigger CI; the skill doesn't manage that.
- **Slack / email notifications** — the handoff report is on disk; the user shares it.
- **Code review tools** — the skill doesn't request reviews; users open PRs and request reviews themselves.
- **Remote cleanup** — per [Axiom 15](../SKILL.md#the-rationalization-kernel-universal-axioms): out of scope by default. With `--prepare-remote-list`, the skill emits the list of `git push --delete origin <branch>` commands; the user runs them themselves.

These are out-of-scope deliberately. The skill's surface is the local repo; integration with external systems happens via the user.
