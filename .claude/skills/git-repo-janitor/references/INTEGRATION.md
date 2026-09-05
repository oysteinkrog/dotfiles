# Integration — Beads + Agent Mail + bv

How the skill coordinates with the standard agentic-coding tool ecosystem.

---

## Beads (`br`) — issue tracking

The skill files a beads issue at Phase 10 to track follow-ups:

```bash
br create \
  --title "repo janitor pass on <project> (<N> candidates)" \
  --type=task \
  --priority=4
```

Then it pins the run's metadata in the issue body:
- Recovery branch name
- Bundle path
- Counts per verdict
- Any deferred categories
- Any surface-to-user items the user said "later" on

The beads issue id becomes the thread id for Agent Mail.

If `br` is unavailable (no beads installed) or the database is locked, the skill records `beads_skipped: true` in the handoff report; the run still succeeds.

---

## Agent Mail — multi-agent coordination

The skill uses Agent Mail when available for two purposes:

1. **File reservations** during Phase 4 parallel triage:
   ```python
   file_reservation_paths(
     project_key=<project-abs-path>,
     agent_name=<worker-id>,
     paths=[".repo_janitor_workspace/triage/batch_NNN.tsv"],
     ttl_seconds=3600,
     exclusive=true,
     reason="repo-janitor-<run-id>"
   )
   ```
   Workers reserve their batch tsv path so two workers don't collide on the same range.

2. **Coordination thread** for the run:
   ```python
   send_message(
     thread_id="repo-janitor-<run-id>",  # = beads issue id once filed
     subject="[repo-janitor-<run-id>] Phase 6 complete — 16 moves landed",
     ...
   )
   ```
   The main agent posts a message at each phase boundary; the user (or other agents) can read the thread for the run's progress.

When Agent Mail isn't available: the main agent serializes worker invocations and skips coordination-thread updates.

---

## bv — graph-aware triage engine

At Phase 10, if `bv` is available:

```bash
bv --robot-triage > <workspace>/post_cleanup_bv_triage.json
```

This surfaces follow-ups: items that are now unblocked because a moved/deleted file no longer blocks them, items that may have new dependencies because of the structural changes, etc.

The handoff report links to the bv output for the user to peruse after the run.

---

## /multi-model-triangulation skill

Optional. Used at Phase 4 (Comprehensive variant) for borderline verdict adjudication and at Phase 9 (round 3) for fresh-eyes diversity.

When invoked, the triangulator subagent passes the borderline rows to the multi-model skill, which fans out to Claude + Codex + Gemini and consolidates verdicts.

When unavailable: the triangulator subagent uses same-session multi-stance Task subagents instead (Literal / Skeptical / Forensic / Adversarial). Less diversity but still catches a useful subset.

---

## /idea-wizard skill

Optional. Used at Phase 11 (user-lens review) for skill-feedback synthesis.

The skill never auto-invokes idea-wizard during a normal run; only when the user explicitly asks "review this run from a user perspective."

---

## /codebase-archaeology + /codebase-report

Optional. Used at Phase 1 by the project-profiler subagent for archetype detection and existing-dir discovery.

Inline fallback: if these skills aren't installed, the profiler does a minimal version (read AGENTS.md + README.md + ls top-level dirs).

---

## /cass — session search

Used at Phase 0.5 (optional) by the cass-miner subagent for context from prior runs:

```bash
cass search "<repo-basename> cleanup" --robot --limit 10 --fields minimal --days 90
cass search "<repo-basename> repo janitor" --robot --limit 10 --fields minimal --days 90
```

If a prior run found a known protected file or escalated a secret-leak: the lessons are extracted into `<workspace>/cass_findings.md` and inform the current run.

---

## DCG (Destructive Command Guard)

The skill is designed never to need DCG bypassing. Specifically:

- Never runs `rm -rf` (DCG would block).
- Never runs `git reset --hard`, `git clean -fd`, `git stash clear`.
- Uses `git rm` and `git rm --cached` exclusively.
- Uses `git filter-repo --invert-paths` only in the secret-leak playbook with verbatim user authorization.

If DCG ever blocks a command the skill issued: it's a bug. Surface to user; do not bypass.

---

## UBS (Ultimate Bug Scanner)

The skill runs `ubs <changed-files>` as part of per-commit gates when the project has UBS configured (detected by `.ubsignore` presence at Phase 1). UBS findings are treated like other lint findings — must be resolved before commit, or pre-approved by user as known pre-existing.

---

## Pre-existing pre-commit hooks

If the user has `.git/hooks/pre-commit` or `core.hooksPath` set:

- Phase 6/7/8 commits go through the hook.
- If the hook fails: surface to user; never `--no-verify`.
- The secret-leak playbook installs ITS pre-commit hook at `.githooks/pre-commit` and sets `core.hooksPath=.githooks`. If the user has an existing different `core.hooksPath`, the skill surfaces the conflict and asks how to chain.

The mcp-agent-mail guard system uses a Python chain-runner pattern (`hooks.d/<hook>/*` directory with numbered scripts) — the skill's pre-commit hook can integrate with that pattern as `hooks.d/pre-commit/30-secret-scan.py` if the user's project has it.
