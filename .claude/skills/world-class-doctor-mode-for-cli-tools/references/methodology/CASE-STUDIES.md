# Case Studies — Doctor-Saved (or Could-Have-Saved) Incidents

Narrative postmortems of real failure modes the doctor methodology addresses. Some are actual incidents distilled from cass mining; others are constructed examples illustrating canonical patterns.

Each case study: the incident, the time-cost without a doctor, what a `<tool> doctor` would have caught/fixed, the FM ID it maps to, and the lift it took (or would take) to add the relevant detector + fixer.

---

## Case 1 — The midnight database migration that lost three days

**Incident.** A user upgraded from `<tool>` v0.4.6 to v0.4.7. The new version had a schema migration. The user ran an action that triggered a migration mid-write. The user's terminal got disconnected. The migration left the DB in a partial state: half the tables at v8, half at v7. The user, unable to read state, ran `<tool> reset --all` — which the user's intent meant "reset my settings" but actually meant "clear all data". Three days of issue updates lost.

**Time cost without doctor:** 4 hours of investigation; 2 hours of restoring from a 3-day-old backup; uncountable hours of data manually re-entered.

**What `<tool> doctor` would have caught:**
- **Detector** `fm-schemas-db-version-mismatch` (P0): on first invocation post-upgrade, `<tool> doctor` reads `schema_version` per table, detects inconsistency, emits a P0 finding.
- **Fixer**: refuses to auto-fix (this is a complex DB recovery; manual remediation pointing at `<tool> doctor recover --schema-mismatch`).
- **Refusal to allow `<tool> reset --all` from a partial state:** an additional invariant — pre-1.0 destructive subcommands SHOULD call `doctor health` first and refuse if state is unhealthy, with a clear "run `<tool> doctor --fix` first" message.

**Map to FM:** `fm-schemas-db-version-mismatch` (P0).

**Lift to add:** ~1 day. Detector is easy (read schema_version per table; compare). Fixer is genuinely complex but already exists in `fixing-beads-problems` skill — Pattern 10 (absorb-playbook) automates it.

---

## Case 2 — The lockfile that survived a kernel panic

**Incident.** A user's machine kernel-panicked (BSOD-equivalent) while `<tool> sync` was running. After reboot, `<tool>` refused to start: "lock held by PID 12345" (which no longer exists). User googled, found a forum post, manually `rm .beads/.beads.lock`. Worked. But the user's intent in deleting was reasonable; the cost was 15 minutes of friction and a moment of "am I about to break something?"

**Time cost without doctor:** 15 minutes; user uncertainty.

**What `<tool> doctor` would have caught:**
- **Detector** `fm-concurrency-primitives-stale-doctor-lock` (P1): reads the lockfile, checks PID liveness with `kill(pid, 0)`, emits a finding.
- **Fixer**: quarantines via `Op::Rename` to `<run-dir>/quarantine/locks/`. Doesn't delete. The user can later inspect or remove.

**Map to FM:** `fm-concurrency-primitives-stale-doctor-lock` (P1).

**Lift to add:** ~1 hour. The detector + fixer are ~30 lines of code each.

---

## Case 3 — The deploy that nuked the wrong environment

**Incident.** A user's `wrangler.toml` had `[env.production]` and `[env.staging]`. They ran `wrangler deploy --env=production` from their dev branch. Production deployed code from the dev branch instead of main. Customers saw experimental feature flags. Postmortem revealed: the user's local checkout was on a feature branch; `wrangler` doesn't refuse to deploy from non-main without `--allow-non-main`.

**Time cost without doctor:** 90 minutes (deploy revert + customer comms + RCA writeup + re-test + redeploy).

**What `<tool> doctor` would have caught:**
- **Detector** `fm-vendor-drift-deploying-from-non-main-branch` (P0, distributed-CLI Pattern 9): reads current git branch, reads target environment from CLI args, refuses if branch != main AND env IS production.
- **Fixer**: refuses (can't auto-fix; user's intent ambiguous). Manual remediation: "switch to main, OR pass `--allow-non-main` if you really mean it."

**Map to FM:** `fm-vendor-drift-deploying-from-non-main-branch` (P0).

**Lift to add:** ~3 hours. Project-specific (tightly coupled to the deploy command). Most valuable as a **pre-deploy hook** that runs the relevant doctor detectors and refuses to proceed.

This one is also a great Cookbook Pattern 9 (distributed-CLI) example: combining auth-status + branch-vs-env validation gates in one `<tool> doctor predeploy` mega-command.

---

## Case 4 — The `wrangler dev` server that wedged on a port collision

**Incident.** User started `wrangler dev` (Pattern 4 daemon CLI). Port 8787 was already in use (forgotten previous instance). The new `wrangler dev` printed something like `Error: EADDRINUSE` and exited 1. User read no further; assumed something deeper was broken; spent 45 minutes debugging the wrong thing (deleted `node_modules`, reinstalled, restarted).

**Time cost without doctor:** 45 minutes.

**What `<tool> doctor` would have caught:**
- **Detector** `fm-daemon-state-port-conflict` (P1, daemon Pattern 4): on `<tool> doctor --running`, probes the configured port, identifies the holder PID via `lsof -i :8787`.
- **Fixer**: refuses (killing another process is the user's call). Manual remediation: "Process X (PID Y) is on port 8787. Run `<tool> stop` or `kill X` first."

**Map to FM:** `fm-daemon-state-port-conflict` (P1).

**Lift to add:** ~2 hours.

---

## Case 5 — The `acfs install` that left stale shell config

**Incident.** User upgraded `acfs` from 0.2 to 0.3. The 0.3 install adds `acfs init.sh` sourcing to `~/.zshrc`. User had a custom `acfs init.sh` from a prior manual install; the new line referenced `~/.acfs/init.sh` which now didn't exist (the new path was `~/.config/acfs/init.sh`). Every new shell printed `~/.zshrc: line 87: /Users/foo/.acfs/init.sh: No such file or directory`. User googled, edited `~/.zshrc`, learned to commit shell config to dotfiles to avoid this in the future.

**Time cost without doctor:** 20 minutes.

**What `<tool> doctor` would have caught:**
- **Detector** `fm-userland-state-shell-rc-broken-source` (P1, installer Pattern 11): reads `~/.zshrc`, finds `source` lines referring to nonexistent paths, emits a finding per offending line.
- **Fixer**: refuses (auto-rewriting shell config is too invasive). Manual remediation: cites file:line of the offender, suggests the corrected path.

**Map to FM:** `fm-userland-state-shell-rc-broken-source` (P1).

**Lift to add:** ~3 hours.

---

## Case 6 — The credential file that was world-readable

**Incident.** User's `~/.config/<tool>/credentials` had mode 0644 because they `cp`-ed it from a backup with `cp` (not `cp -p`). On a shared system, another user could `cat` the credentials. Discovered three weeks later by an internal audit. No leak confirmed but the credentials were rotated and the postmortem took 2 days.

**Time cost without doctor:** 2 days of postmortem + rotation friction.

**What `<tool> doctor` would have caught:**
- **Detector** `fm-secrets-perms-too-permissive` (P1): stats credential files, emits a finding if mode allows group/other read.
- **Fixer**: chmod 0600 via `mutate(... Op::Chmod)`. Verbatim backup is the original-mode-as-was (the bytes don't change; the metadata does — `mutate()` records mode in the backup metadata).

**Map to FM:** `fm-secrets-perms-too-permissive` (P1).

**Lift to add:** ~30 minutes. Trivial detector + fixer.

---

## Case 7 — The DB-family backup that missed `.db-journal`

**Incident.** User wrote a custom backup script that copied `.beads/beads.db` and `.beads/beads.db-wal`. Forgot `.beads/beads.db-journal`. After a restore from this backup, SQLite tried to roll back an uncommitted transaction using the journal, which didn't exist, and corrupted the DB. Three days of issues lost (different from Case 1; same lesson).

**Time cost without doctor:** 6 hours.

**What `<tool> doctor` would have caught:**
- **Detector** `fm-state-files-db-family-partial-presence` (P0): reads all four sidecar files, alerts if WAL exists without primary, or SHM exists without WAL.
- **Fixer** (limited): quarantines orphan SHM (the only safe auto-fix). For missing primary with present WAL: refuses; manual recovery via `sqlite3` is required.

**Map to FM:** `fm-state-files-db-family-partial-presence` (P0).

**Lift to add:** ~4 hours (well-defined detector; refusing fixer is the cautious choice).

This case maps directly to the `fixing-beads-problems` skill's ABSORB-PLAYBOOK target. The doctor doesn't need to write the recovery — it just needs to fail-loud and point at the playbook.

---

## Case 8 — The agent that ran `<tool> doctor --fix` against the wrong project

**Incident.** A multi-agent swarm had agents working on multiple projects. One agent's CWD drift caused it to invoke `<tool> doctor --fix` from inside `~/projects/wrong-project/`. The doctor's `target` defaulted to cwd. Wrong-project's state was modified.

**Time cost without doctor's safeguards:** 30 minutes (revert from git).

**Time cost WITH the doctor we're building:** ~0 minutes — `<tool> doctor undo latest` reverts byte-for-byte. The agent realizes immediately, runs undo, moves on.

**Lift:** Already in scope. This is what reversibility BUYS.

---

## Case 9 — The flaky pre-commit hook

**Incident.** A pre-commit hook ran `<tool> verify` (the project's existing verify command). On a slow CI runner, `verify` took 8s per commit. Users disabled the hook. Two weeks later, a commit landed that broke the project's invariants — the kind of thing the hook had caught before.

**Time cost without doctor:** ongoing (the hook is now disabled; bugs slip through).

**What `<tool> doctor` would have given:**
- A `<tool> doctor --quick` mode (Stage 6 / detector tiering) bounded < 200 ms.
- Pre-commit uses `--quick`; full `--fix` is for explicit invocation.
- Users keep the hook enabled because it's fast.

**Lift:** ~2 hours (just classify each detector by tier; pre-existing detectors).

---

## Case 10 — The doctor itself had a bug

**Incident.** A doctor pass-2 introduced a fixer with a subtle TOCTOU between detect and fix. The fixer corrupted state on an exotic concurrent-edit scenario. The user noticed, ran `<tool> doctor undo latest`, and the workspace was restored. The bug was filed, the next pass added a fixture for the TOCTOU, fixed the fixer, added an adversarial-review test. No data lost.

**This is the meta-case.** The doctor's own bugs are real; the kernel's invariants (mutate-chokepoint, verbatim backup, undo) are what catch them. The methodology IS the protection — not perfect detectors, not perfect fixers, but the DISCIPLINE that means even when a fixer is buggy, the user can revert.

This is why the kernel has 17 universal axioms plus 7 stretch axioms, not 7 total. The redundant invariants (backup-before + hash-witnessed + cmp-strict + reversible + idempotent + ...) make any single bug recoverable.

---

## Case 11 — The doctor that detected its own corruption

**Incident.** Pass-3 added a meta-doctor (Pattern 12). The first run of the meta-doctor found a broken cross-reference in the doctor's own SKILL.md (a link to a removed reference file). The fix was a one-line edit. Without the meta-doctor, the broken link would have lived in the skill for months.

**Map to:** [META-DOCTOR.md](META-DOCTOR.md). The recursion (a doctor for the doctor) is the natural completion.

**Lift:** Already documented; just needs implementation.

---

## How to use these case studies

In Phase 1 archaeology: read these as priors. Real failure modes recur across projects, and the case studies are pre-built reasoning. When the archaeologist's mining for `state_files` finds a similar pattern in cass, Case 1 or Case 7 is likely the right analog.

In Phase 10 cold-prober: include "Case N replication" as canonical tasks for the prober to attempt. (E.g., "construct the conditions of Case 5 in this project; verify the doctor catches it.")

In Phase 8 integration-wirer: cite case studies in the related-skill demotion ("`fixing-beads-problems` content remains for the unusual-Case-7-style scenarios that automated remediation refuses").

In agent-facing `robot-docs`: case studies aren't appropriate for the agent's handbook (too narrative). They live here for human readers (developers, writers, reviewers).

---

## Adding new case studies

When a real incident occurs in a project that runs the doctor methodology:

1. Write a 1-paragraph postmortem.
2. Map it to the FM (existing or new).
3. Add it to this file at the next available case number.
4. If the FM didn't exist before, that's an archaeology gap from a prior pass — file as a P1 bead for the next pass.

The case-study list grows over time. Future maintainer: when you're tempted to delete an old case ("we don't have this problem anymore"), don't — per AGENTS.md no-delete, archived cases inform new agents about the failure modes the project HAS already addressed.
