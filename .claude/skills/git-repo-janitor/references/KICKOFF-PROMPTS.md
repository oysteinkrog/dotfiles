# Kickoff Prompts

Verbatim prompts to start a run. Copy-paste-ready.

> **Vocabulary reminder**: a **variant** (Quick / Standard / Comprehensive) sets orchestration depth — worker count, fresh-eyes round count. A **mode** (one of 9 named modes; see OPERATING-MODES.md) decides which phases run and what's allowed. Variant and mode are orthogonal — pick both. The kickoff phrasing below uses "in <Variant> + <mode>" so the agent sets up correctly.

---

## Quick variant (5–24 candidates)

```
Run the repo-janitor skill on /data/projects/<repo> in Quick variant + full mode.

Profile + secret-scan + bundle, then triage all candidates with a single agent.
Show me the categorized plan; I'll review before any moves or deletes.
Recovery branch: repo-janitor-<DATE>. Bundle: in .repo_janitor_workspace/recovery-bundle-<DATE>.
```

## Standard variant (25–149 candidates)

```
Run the repo-janitor skill on /data/projects/<repo> in Standard variant + full mode.

Use 2–4 parallel triage workers. Build the categorized plan
(letter-categories per WORKED-EXAMPLES.md). Run gates after every commit.
Don't push.
```

## Comprehensive variant (150+ candidates)

```
Run the repo-janitor skill on /data/projects/<repo> in Comprehensive variant + full mode.

Spawn 5+ parallel triage workers. For "looks important but mislocated" rows,
spawn the archaeologist subagent. Run multi-model triangulation on borderline
verdicts (confidence 0.5–0.7). Three fresh-eyes rounds.

Don't push the recovery branch. Print the push command in the handoff.
```

## Triage-only

```
Run the repo-janitor skill on /data/projects/<repo> in TRIAGE-ONLY mode.

I want the categorized plan and the bundle, but no commits. I'll decide
what to do after I see the plan.
```

## Move-only

```
Run the repo-janitor skill on /data/projects/<repo> in MOVE-ONLY mode.

Triage normally, but skip Phase 7 (deletes) and Phase 8 (gitignore).
Just relocate the move candidates and rewrite references.
```

## Delete-only

```
Run the repo-janitor skill on /data/projects/<repo> in DELETE-ONLY mode.

Triage normally, but skip Phase 6 (moves). Only do the gated cleanup of
clear junk. The gitignore phase still runs (Phase 8).
```

## Resume after interruption

```
Resume the repo-janitor run on /data/projects/<repo>. There's a
.repo_janitor_workspace directory from the previous run; pick up from
the last successful state.
```

## Dry-run a specific archetype

```
Profile /data/projects/<repo>. Detect the archetype, build commands,
protected globs, and probable smell categories. Don't actually run any
of Phases 2 onward — I just want to see what the skill would propose.
```

## Secret-leak triage only

```
Run only Phase 0 + Phase 1 + Phase 2 + Phase 2.5 on /data/projects/<repo>.
I want to know if there are committed secrets before I decide whether
to do a full cleanup or just rotate keys.
```
