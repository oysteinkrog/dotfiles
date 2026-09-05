---
name: git-stash-janitor
description: >-
  Safely mine a repo's accumulated git stashes for content worth landing on the
  primary branch. Use when a project has piled up stashes ("*N" in the prompt),
  "clean up my stashes", "stash archaeology", "are any of these stashes worth
  keeping", or when an agent swarm has left dozens of WIP stashes behind.
---

<!-- TOC: Quickref | Inputs | What This Produces | Workspace Layout | Up-Front Confirmations | Skill Bootstrap | The Phase Loop | Mode Variants | Parallelism | Operator Library | The Polish Bar | Failure Modes | Anti-Patterns | When NOT to Use | Pre-Flight Checklist | Reference Index | Scripts | Subagents | Self-Test -->

# Git Stash Janitor — Mine, Verify, Recover, Drop

> **The One Rule.** Every stash drop must be reversible **byte-for-byte** at the moment it's authorized. Backup refs in `refs/stash-backup/*` are the gold standard; per-stash unified diffs in the recovery bundle are the human-readable backstop. If both aren't in place and verified, no destructive action runs. Period.

> **Scope.** A pile of `git stash` entries — typically 20 to 500 of them, accumulated by an agent swarm or a developer who used stash as scratch space — needs to be triaged into `superseded | garbage | novel | partially-novel | novel-but-stale`, the genuinely useful pieces folded into the primary branch as focused commits, and the rest dropped only after the user has explicitly authorized the verbatim commands.

---

## THE STASH-JANITOR KERNEL (Universal Axioms)

<!-- KERNEL_START v1.0 -->

Almost every serious stash-janitor decision should be stress-tested against these axioms. They are default truths, not mindless scripts: if an edge case seems to break one, explain why before treating it as an exception.

**Axiom 0 — A stash is just a commit with extra parents.**
`git stash push` creates a *merge commit* whose first parent is HEAD, second parent is an "index commit" (the staged changes), and (with `-u`) third parent is an "untracked-files commit". Every triage and recovery operation downstream is a property of this commit graph. `git stash show -p --binary` is the authoritative diff because it walks the right parents and includes tracked binary payloads; `git format-patch` walks the wrong parent. **The bundle is built on `git stash show -p --binary`. Always.**

**Axiom 1 — One coherent recovery story is told by every artifact.**
Backup refs (`refs/stash-backup/<NNN>`) + per-stash diffs (`<bundle>/diffs/<NNN>.diff`) + meta files + index TSV + README must point at the same SHAs, in the same order, with byte-equality verified. Silos produce the deepest failures: a diff that disagrees with the backup ref it claims to back up is worse than no backup at all.

**Axiom 2 — Plan for irreversibility first, classification second.**
The `⬡ BUNDLE` operator (Phase 3) is a hard gate before any destructive logic runs. An incorrect verdict is recoverable; an unrecorded drop is not. Build the safety net first, then triage.

**Axiom 3 — Beneficiary-style coherence: all four layers tell the same story.**
The four reversibility layers (backup ref + bundle diff + meta + index entry) must all reflect the same stash's content. If a Phase 3 byte-equality check disagrees on even one stash, the run is unsafe — halt.

**Axiom 4 — `main` is not the universal default.**
Many projects use `master`, `develop`, `trunk`, `default`. Detect the primary branch via `git symbolic-ref refs/remotes/origin/HEAD` first, then `git config init.defaultBranch`, then a heuristic against the actual ref list. Never assume.

**Axiom 5 — Indexes shift after every drop.**
`stash@{N}` is a stack position, not a stable id. Drop highest-index-first within each verdict bucket. Re-resolve the message before each drop and halt if it shifted unexpectedly.

**Axiom 6 — `git format-patch -1 stash@{N}` is the canonical footgun.**
It is not the stash recovery diff. A stash is a merge commit, and format-patch can emit a tiny, empty, or unrelated patch depending on the merge parents; it also never materializes untracked files. **Always** use `git stash show -p --binary stash@{N}` for the tracked/index recovery diff, and copy `stash@{N}^3` separately when the stash has untracked files. Document the footgun in every recovery README so future readers don't waste time.

**Axiom 7 — Concurrent agents' working-tree changes are normal.**
Per AGENTS.md, never stash, revert, or overwrite changes made by parallel agents. Snapshot once at Phase 0; re-snapshot before each Phase 6 apply; treat all observed drift as "you committed it" and proceed. Don't ask the user about drift you didn't cause.

**Axiom 8 — `git stash pop` and `git stash apply` are forbidden.**
Both mutate state without going through the bundle's verified diff. On conflict, both leave the working tree dirty AND the stash still in the list AND no clean recovery path. The skill operates on `<bundle>/diffs/<n>.diff` via `git apply --3way`. Always.

**Axiom 9 — Per-apply gates are non-negotiable.**
Run the project's actual `test`, `typecheck`, `lint`, `ubs` after every Phase 6 / Phase 7 apply, not just at the end. Compounding errors across recoveries are an order of magnitude harder to debug than per-keeper failures.

**Axiom 10 — Authorization is per-plan, verbatim, recorded.**
Every destructive phase requires the user to type a phrase that quotes a literal command from the plan (per AGENTS.md "Mandatory explicit plan"). The verbatim text is recorded in `cleanup_authorization.txt` with a UTC timestamp. If that file doesn't exist, the action did not happen.

**Axiom 11 — The user owns deployment and bundle lifecycle.**
The skill never pushes the recovery branch; the user pushes. The skill never deletes the bundle; the user manages it. Both are deliberate: the recovery story has to outlive the run.

**Axiom 12 — Same-name on main is not always supersession.**
A function `lock_until` on the stash and on main may have different signatures (`Instant` vs `Duration`). Always sample same-signature on a few introduced symbols before classifying `superseded`. When ≥30% of sampled signatures diverge, flip the verdict and surface to user.

**Axiom 13 — Drop the bundle only at the user's pace.**
DCG correctly blocks `rm -rf` on the bundle. The skill is *designed* never to need this command. Bundle deletion is a manual decision after the user is sure nothing was lost (typically 1–4 weeks).

<!-- KERNEL_END v1.0 -->

These 14 axioms compose: Axiom 2 + Axiom 3 produce the byte-equality gate; Axiom 5 + Axiom 10 produce the highest-index-first verbatim-confirm pattern; Axiom 6 + Axiom 8 produce the "operate on the bundle's diff, never the live stash" rule; Axiom 7 + Axiom 9 produce the per-apply working-tree-snapshot + gates pattern. When you find yourself wanting to break one, slow down and check whether you've actually identified an exception or whether the kernel is right.

---

## Decision Tree — Should the Skill Run?

```
git stash list | wc -l   →  N

├── N < 5
│     └── Suggest manual inspection (`git stash list -v`); skill is overkill
│
├── 5 ≤ N < 10
│     └── Quick mode (single-agent, ~15-30 min)
│
├── 10 ≤ N < 80
│     └── Standard mode (Pair or Squad tier; ~1-3 h)
│
├── 80 ≤ N < 300
│     └── Comprehensive mode (Squad/Swarm; ~3-8 h)
│
└── N ≥ 300
      └── Comprehensive + Council tier (12+ workers, multi-model triangulation)

Pre-conditions (refuse if any fail):
  - git work tree (not bare)
  - has commits
  - not mid-rebase / merge / cherry-pick / revert / bisect
  - writable filesystem

Soft-warnings (proceed but flag):
  - detached HEAD (need recovery branch base)
  - working tree non-empty (concurrent agents per AGENTS.md — don't disturb)
  - no remote (push instructions degrade gracefully)
  - very old git (<2.20)
```

See [WHEN-NOT-TO-USE.md](references/WHEN-NOT-TO-USE.md) for the full refusal matrix and `scripts/git-doctor.sh` for the automated check.

---

## Quickref

| Input | Effect | Guarantees |
|-------|--------|------------|
| **Project path** (cwd, absolute path, or git URL → clone to `/tmp/`) | Skill reads `AGENTS.md` / `CLAUDE.md` / `README.md`, detects primary branch, build/test/lint commands, branch model, message conventions; all written to `project_profile.json` | No assumptions — `main` is **not** assumed; primary branch is detected from `git symbolic-ref refs/remotes/origin/HEAD` first, then `git config init.defaultBranch`, then a fallback heuristic against the actual ref list |
| **Stash count** (`git stash list \| wc -l`) reported up front | User confirms before any work; mode auto-selects (manual-default warning for <5, Quick 5–9, Standard 10–80, Comprehensive 80+) | The user always knows the magnitude before the run starts (the asupersync user thought `*127` meant 127 commits, not 127 stashes) |
| **Recovery bundle** — `refs/stash-backup/<NNN>` + `diffs/NNN.diff` + `meta/NNN.txt` + `index.tsv` + `stashed-untracked/NNN/` (when `-u`) + `README.md` at `<project-parent>/<basename>-stash-archive-<YYYY-MM-DD>/` | Every stash captured before any classification touches the working tree; byte-equality verified across all backup refs against live stash | After Phase 3 tracked/index changes are reversible via `git cherry-pick -m 1 refs/stash-backup/NNN` (stash backup refs are merge commits — `-m 1` selects HEAD-at-stash) or `git apply <bundle>/diffs/NNN.diff`; untracked files are recovered from `<bundle>/stashed-untracked/NNN/` |
| **Triage TSV** (`triage.tsv`) — one row per stash with verdict, evidence, confidence | User reviews, may override individual verdicts; only then does Phase 6 run | No stash is dropped without the user signing off on its verdict |
| **Per-keeper commit** — `git apply --3way` → run real project gates (`cargo test`, `bun tsc --noEmit`, `pytest`, etc.) → focused commit | Quality gates run on **every** apply, not at the end; reapplied keepers re-fingerprint downstream candidates so already-superseded ones flip verdict | Compounding errors across recoveries are caught per-apply, not at the end (lesson from the asupersync run) |
| **Destructive cleanup** (gated on explicit verbatim authorization) | `git stash drop stash@{N}` per stash, in order garbage → superseded / superseded-by-newer-stash → novel-but-stale → applied-keeper | No `git stash clear`, no `rm -rf`, no `git reset --hard` — ever. `refs/stash-backup/*` and the bundle survive |
| **Handoff** — counts, recovered SHAs, bundle path, verbatim recovery recipes | Skill never pushes; user pushes | The user gets a complete recovery story even after a clean run |

---

## What This Skill Produces

Either:

1. **A clean stash list** plus N focused commits on a recovery branch (default `stash-recovery-<YYYY-MM-DD>`), every commit traceable to a specific stash via `refs/stash-backup/*`, every dropped stash backed up in the bundle, and a final report showing what landed and what didn't.
2. **An audit report only** (when run in `triage-only` mode) — the recovery bundle plus `triage.tsv` plus a markdown decision table; no commits, no drops.

The skill **never**:

- Runs `git stash clear`, `git stash drop` without explicit user authorization
- Runs `rm -rf`, `git reset --hard`, `git clean -fd` (DCG would block them anyway; the skill is designed not to need them)
- Pushes to a remote
- Modifies `.git/` directly
- Stashes, reverts, or overwrites changes from other agents in the working tree (per AGENTS.md "Note for Codex/GPT-5.5")

---

## Inputs

- **Target path** (default: cwd) — absolute path to a git repo, OR a git URL we clone into `/tmp/<basename>` and operate against.
- **Mode** — auto-detected from stash count (Quick / Standard / Comprehensive); user-overridable.
- **Output mode** — `full` (default: triage + apply keepers + gated cleanup) | `triage-only` (Phases 1–5 then stop) | `apply-only` (skip cleanup; leave stashes intact).
- **Recovery branch name** — default `stash-recovery-<YYYY-MM-DD>`. The skill creates this branch from the primary branch and lands keeper commits there, leaving the user to merge or cherry-pick onto the primary.
- **Bundle directory** — default `<project-parent>/<project-basename>-stash-archive-<YYYY-MM-DD>/` (placed next to the repo, not inside it, so it won't show up as untracked content during the run).

---

## Workspace Layout

A single run creates two directories: the workspace inside the repo (transient, .gitignored) and the recovery bundle outside the repo (persistent, user-managed).

```
<project-root>/
└── .stash_janitor_workspace/                   ← transient, in repo, .gitignored
    ├── project_profile.json                    ← Phase 1 output
    ├── inventory.tsv                           ← Phase 2 output
    ├── inventory_grouped.md                    ← Phase 2 — by message-prefix family
    ├── wt_phase0.txt                           ← Phase 0 `snapshot-tree.sh` baseline
    ├── bundle_path.txt                         ← absolute path to the recovery bundle
    ├── bundle_verification.log                 ← Phase 3 byte-equality results
    ├── triage/
    │   ├── batch_001.tsv                       ← Phase 4 worker output
    │   ├── batch_002.tsv
    │   └── ...
    ├── triage.tsv                              ← Phase 4/5 merged decision table
    ├── triage_decision.md                      ← Phase 5 — user-facing markdown table
    ├── user_overrides.tsv                      ← Phase 5 — verdicts the user overrode
    ├── apply_log.tsv                           ← Phase 6 — what landed, with SHA
    ├── conflicts/
    │   ├── stash_034.context.md                ← Phase 6 — surfaced conflict + proposed fix
    │   └── ...
    ├── partial_split_log.tsv                   ← Phase 7 — split-apply outcomes
    ├── fresh_eyes_log.md                       ← Phase 8 — review rounds
    ├── cleanup_authorization.txt               ← Phase 9 — verbatim user-typed authorization
    ├── cleanup_log.tsv                         ← Phase 9 — what got dropped, in order
    ├── handoff_report.md                       ← Phase 10 — final report
    └── skill_feedback.md                       ← Phase 11 (optional) — improvement notes

<project-parent>/<basename>-stash-archive-<YYYY-MM-DD>/   ← persistent recovery bundle
├── README.md                                   ← recovery recipes + footgun warnings
├── index.tsv                                   ← n  sha  parent  date  message  shortstat
├── meta/
│   ├── 000.txt                                 ← message, parent, author, date, untracked-flag
│   └── ...
├── diffs/
│   ├── 000.diff                                ← `git stash show -p --binary <inventory-sha>` output
│   └── ...
└── stashed-untracked/                          ← optional — only when stash had -u files
    ├── 000/
    │   └── path/to/untracked-file.ext
    └── ...
```

Backup refs live inside `.git/`:

```
.git/refs/stash-backup/000        ← byte-identical to live stash@{0} (verified Phase 3)
.git/refs/stash-backup/001
...
```

The bundle is **outside** the repo on purpose: it survives `git clean -fdx` (which the skill never runs but the user might), it doesn't pollute `git status` while running, and it's trivially shareable via `tar`.

---

## Up-Front Confirmations (Ask Before Starting)

Use the intake template at `assets/intake-prompt.md` verbatim. The summary:

1. **Target path?** Confirm absolute path. If a git URL, ask whether to clone to `/tmp/<basename>`. Refuse to operate on a path that isn't a git work tree.
2. **Stash count up front.** Run `git -C <path> stash list | wc -l` and tell the user the count *before* asking them to commit time. >50 stashes is rare enough that users genuinely don't know they have that many. (The motivating session: user thought `*127` in the zsh prompt meant "127 commits ahead". It was 127 stashes.)
3. **Mode?** Auto-detect from stash count (manual-default warning for <5, Quick 5–9, Standard 10–80, Comprehensive 80+). User can override.
4. **Output mode?** `full` | `triage-only` | `apply-only`. Default `full`.
5. **Recovery branch name?** Default `stash-recovery-<YYYY-MM-DD>`. The skill never lands keeper commits directly on the primary branch.
6. **Bundle path?** Default `<project-parent>/<basename>-stash-archive-<YYYY-MM-DD>/`. Confirm OK.
7. **Resuming a prior run?** If `.stash_janitor_workspace/` already exists, offer (a) resume from saved state, (b) archive old workspace under a timestamped suffix and start fresh, or (c) abort.
8. **Concurrent agents?** Ask whether other agents are working in this repo right now. If yes, run `agent-mail file_reservation_paths(... ".git/**", reason="stash-janitor-<run-id>")` advisory-only so a parallel agent doesn't kick off a competing run. The working tree may show changes from other agents during the run — per AGENTS.md, treat them as if you made them.
9. **Quality gates?** Confirm the auto-detected `cargo test` / `bun tsc --noEmit` / `pytest` / `go test ./...` etc. is correct for this project. Default: run them on every Phase 6 apply.

If any helper skill referenced here is missing (`/operationalizing-expertise`, `/codebase-archaeology`, `/codebase-report`, `/agent-mail`, `/beads-br`, `/beads-bv`, `/ubs`, `/idea-wizard`, `/multi-pass-bug-hunting`, `/dcg`): if `jsm` is installed and authenticated, offer `jsm install <name>` for each missing one. Don't block a phase if a polish skill is missing — note it and proceed with the inline fallback.

---

## Skill Bootstrap (Phase 0.5 — right after inputs, before partition)

```bash
./scripts/check-skills.sh .stash_janitor_workspace
# Detects helper skills + jsm state; writes phase0_skill_inventory.json

./scripts/discover-project.sh <project-path>
# Detects primary branch, build/test/lint commands, message conventions, CI gates;
# writes .stash_janitor_workspace/project_profile.json itself.
```

If skills are missing and `jsm` is installed + authenticated:

```bash
./scripts/install-referenced-skills.sh .stash_janitor_workspace
```

The skill **never blocks** on a missing helper skill — every reference has an inline fallback in this SKILL.md or in `references/`.

---

## The Phase Loop (Mandatory)

```
Phase 1   PROJECT RECONNAISSANCE   AGENTS.md, README.md, archaeology → project_profile.json
Phase 2   STASH INVENTORY          list, capture metadata, group by message-prefix → inventory.tsv
Phase 3   RECOVERY BUNDLE          backup refs + diffs + meta + index + byte-equality verify
Phase 4   TRIAGE FAN-OUT           parallel workers (~20 stashes each) → triage.tsv
Phase 5   TRIAGE MERGE & CONFIRM   present decision table to user; user may override verdicts
Phase 6   APPLY KEEP CANDIDATES    sequential; `git apply --3way` → quality gates → focused commit
Phase 7   PARTIAL-NOVEL SPLIT      novel hunks only; the most error-prone phase, gets its own subagent
Phase 8   FRESH-EYES VERIFICATION  three review prompts × ≥2 rounds; full test suite + linters
Phase 9   DESTRUCTIVE CLEANUP      gated on verbatim user authorization; `git stash drop` per stash
Phase 10  HANDOFF & FOLLOW-UPS     final report, beads issue, recovery recipes; user pushes
Phase 11  USER-LENS REVIEW         (optional, off by default) skill self-improvement notes
```

**Phases 4 and 8 are reapply-until-quiet** — keep spawning passes until an entire pass produces only trivial findings (typos, marginal wording). Phase 8's two clean rounds are the explicit termination gate before Phase 9 may run.

**Phases 3, 5, 9 are gates.** Phase 3 must complete with byte-equality verified before any classification logic runs. Phase 5 must end with explicit user go-ahead before Phase 6 starts. Phase 9 must end with explicit user-typed verbatim authorization (per AGENTS.md "Mandatory explicit plan" rule) before any `git stash drop` executes.

Full per-phase playbook with exit criteria + exact subagent prompts: **[PHASES.md](references/PHASES.md)** and **[AGENT-PROMPTS.md](references/AGENT-PROMPTS.md)**.

### Mode Variants

| Mode | Stash count | Wall time | Triage | Phase 8 | When |
|------|-------------|-----------|--------|---------|------|
| **Quick** | 5–9 by default; <5 only after warning override | 10–20 min | Single agent reads each stash | One round | Hand-curated; user often already knows roughly what's there |
| **Standard** | 10–80 | 30–90 min | 2–4 parallel triage workers | ≥2 rounds | Typical agent-swarm aftermath |
| **Comprehensive** | 80+ or stash references deleted/renamed files | 2–6 h | 5+ parallel workers; archaeology subagent for each "novel-but-stale" candidate | ≥3 rounds, multi-model triangulation if available | The asupersync 127-stash case |

Mode is recorded in `project_profile.json` at Phase 1. Phase gates (especially Phase 8 termination) adjust based on mode.

---

## Parallelism Model

Inventory and bundle creation are serial (one source of truth). Triage is the large parallelizable phase. Apply is sequential (each apply changes the 3-way base for later applies).

```
┌─────────────────────────────────────────────────────────────┐
│  Phase 1 PROFILE  +  Phase 2 INVENTORY  +  Phase 3 BUNDLE   │ serial
│  (single agent — these establish the source of truth)       │
└────────────────────────┬────────────────────────────────────┘
                         │
            ┌────────────┴────────────┐
            ▼                         ▼
     ┌──────────────┐           ┌──────────────┐
     │ Triage A     │   ...     │ Triage N     │   parallel, ~20 stashes each
     │ stashes 0-19 │           │ stashes 100+ │
     └──────┬───────┘           └───────┬──────┘
            │                           │
            └─────────────┬─────────────┘
                          ▼
              ┌─────────────────────────┐
              │ Phase 5 MERGE & CONFIRM │   single agent; reads all batches
              │ (USER GATE)             │
              └──────────┬──────────────┘
                         ▼
              ┌─────────────────────────┐
              │ Phase 6 APPLY KEEPERS   │   sequential; quality gates per apply
              │ Phase 7 PARTIAL SPLIT   │
              └──────────┬──────────────┘
                         ▼
              ┌─────────────────────────┐
              │ Phase 8 FRESH-EYES      │   parallel review prompts
              └──────────┬──────────────┘
                         ▼
              ┌─────────────────────────┐
              │ Phase 9 CLEANUP (GATED) │
              │ Phase 10 HANDOFF        │
              └─────────────────────────┘
```

**Default execution: single Claude Code session.** The main agent uses the `Task` tool to spawn parallel subagents for Phase 4 (triage) and Phase 8 (fresh-eyes). No external orchestration is required. Sequential phases (3, 6, 7, 9) run in the main agent. This works in any environment that has Claude Code's Task tool — no NTM, no tmux, no extra setup.

**Coordination** — when [`/agent-mail`](../agent-mail/SKILL.md) is available, use file reservations on `.stash_janitor_workspace/triage/**` so triage workers don't stomp each other (thread id: `stash-janitor-<run-id>`, = the beads issue id once filed). When Agent Mail isn't available, the main agent serializes worker invocations to avoid races.

**Orchestration tier** — pick based on stash count and stakes (full matrix + per-tier wall-time in [ORCHESTRATION.md](references/ORCHESTRATION.md)):

| Tier | Workers (Phase 4) | Default execution | When |
|------|-------------------|-------------------|------|
| Solo | 1 | Main agent only, no Task fan-out | <10 stashes; routine cleanup |
| Pair | 2 | 2 parallel Task subagents | 10–40 stashes |
| Squad | 4–6 | 4–6 parallel Task subagents | 40–150 stashes |
| Swarm | 8–12 | 8–12 parallel Task subagents | 150–300 stashes |
| Council | 12+ | Task subagents + multi-model triangulation (requires `/multi-model-triangulation` skill OR NTM) | 300+ stashes; production-critical; security-sensitive content |

The default execution at every tier uses Claude via the Task tool. Multi-model triangulation (Codex / Gemini in addition to Claude) is **opt-in** at any tier and required for Council; see Triangulation tier below. NTM swarm panes are an optional alternative orchestration topology useful when the user already runs NTM; see [ORCHESTRATION.md § Optional: NTM Swarm Topology](references/ORCHESTRATION.md#optional-ntm-swarm-topology).

**Triangulation tier (optional)** — when verdict ambiguity is high or work is high-stakes, ambiguity-band rows can be re-evaluated by multiple independent reads. Three submission paths in priority order:

- **Path A (preferred):** `/multi-model-triangulation` skill if installed — true multi-model (Claude + Codex + Gemini) from a single Claude Code session.
- **Path B (fallback):** same-session multi-stance Task subagents — same Claude model, different reading stances (Literal / Skeptical / Forensic / Adversarial). Prompt diversification, not model diversification, but catches a useful subset.
- **Path C (optional):** NTM panes if the user runs that.

The skill never *requires* multiple models; high-confidence single-model verdicts proceed without triangulation. See [MULTI-MODEL-TRIANGULATION.md](references/MULTI-MODEL-TRIANGULATION.md).

**Modes-of-reasoning composition** — even on a single-model single-stance run, the agent can vary stance per phase (Literal in Phase 4 triage; Forensic in Phase 6 commit-message authoring; Adversarial in Phase 8 round 3). See [MODES-OF-REASONING.md](references/MODES-OF-REASONING.md).

---

## Operator Library — The Cognitive Moves

Each operator is a reusable verb with explicit triggers, a prompt module, and exit criteria. These are *what to think about*, not just *what to do*. Adapted from [`operationalizing-expertise`](../operationalizing-expertise/SKILL.md) Track A.

| Glyph | Name | Question / Action | When to Apply |
|-------|------|------------------|---------------|
| `★` | **INVENTORY** | Capture every stash's ref, parent, message, shortstat into one TSV; never trust the index alone | Phase 2 — once, the source of truth |
| `✦` | **FINGERPRINT** | Identify the symbols this stash introduces: function names, type names, fixture strings, test names, file paths | Phase 4, per-stash, before any "is it on main?" check |
| `◐` | **VERIFY-ON-MAIN** | Grep / ast-grep the primary branch for the fingerprint; if every fingerprint resolves on main with the same semantics, the stash is **superseded** | Phase 4, immediately after FINGERPRINT |
| `⬡` | **BUNDLE** | Materialize backup ref + diff + meta + untracked-files for every stash; verify byte-equality before allowing destructive phases | Phase 3 — the irreversibility gate |
| `⚠` | **CONFIRM** | Restate the destructive command verbatim; wait for explicit user OK in the same message; record the authorization text | Phases 5, 9 |
| `✧` | **APPLY-3WAY** | `git apply --3way --check` first (dry-run); only on clean check do we actually apply; never `git stash pop` or `git stash apply` | Phase 6 |
| `⇄` | **SPLIT-HUNKS** | For partially-novel stashes, keep only explicitly identified novel hunks in a copy of the diff, then apply that smaller diff | Phase 7 |
| `⊕` | **RECOVER** | Run the project's actual quality gates (`cargo test`, `bun tsc --noEmit`, `pytest`) on every apply; catch compounding errors per-keeper, not at the end | Phase 6, after every successful apply |
| `⊙` | **DROP** | Drop a stash by **highest** index first within each verdict bucket (indexes shift after each drop); restate the verbatim command before each `git stash drop`; backup ref stays | Phase 9 |
| `⌘` | **HANDOFF** | Final report with: counts per verdict, recovered commit SHAs, bundle path, verbatim recovery recipe; never push | Phase 10 |
| `⊞` | **RE-FINGERPRINT** | After every successful Phase 6 apply, re-run FINGERPRINT/VERIFY-ON-MAIN on downstream keep candidates; some now flip to `superseded` | Phase 6, between applies |
| `↺` | **WORKING-TREE-DRIFT** | Before each Phase 6 apply, re-snapshot `git status` + `git diff`; if changes appear from other agents, treat as if you made them; never stash/revert/overwrite | Phase 6, every iteration |

Full operator cards (with prompt modules, failure modes, quote-bank anchors): **[OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md)**.

---

## The Polish Bar (Non-Negotiable)

A "successful stash janitor run" is not "the stashes are gone." Every keeper-commit must satisfy:

| Dimension | Test |
|-----------|------|
| **Recovery completeness** | Every stash has a backup ref AND a diff in the bundle AND an index entry; byte-equality verified before any destructive phase |
| **Verdict evidence** | Every triage row cites concrete evidence on the primary branch — `file.rs:317` showing the symbol exists, or grep-empty proving it doesn't |
| **No phantom keepers** | No stash is marked "novel" without FINGERPRINT proving its symbols don't appear on main; "I think it's novel" is never acceptable |
| **Per-apply gates** | Every Phase 6 commit has run the project's full test/typecheck/lint suite, and they all pass; no "we'll fix it at the end" |
| **Focused commit messages** | Each keeper-commit explains *why* this hunk is being recovered: not "apply stash@{34}" but "recover defensive MySQL OK-packet length-cap from WIP stash; fail-closed test was authored but never landed" |
| **Order of drops** | `garbage` → `superseded` / `superseded-by-newer-stash` → `novel-but-stale` → `applied-keeper`, **highest index first within each bucket** (indexes shift after each drop) |
| **Verbatim authorization** | Phase 9 only runs after the user types the literal commands (or an authorization phrase that quotes them); recorded in `cleanup_authorization.txt` |
| **Idempotent on a clean repo** | Re-running on a freshly-cleaned repo produces no commits and reports "nothing to do" |
| **Resumable** | If interrupted mid-Phase 6, re-running picks up from the last successful commit using `apply_log.tsv` + git log |

If a run can't satisfy these, it has not "completed successfully" — it has half-finished and needs to flow back through whichever phase failed.

Full rubric, per-phase checklists, verification queries: **[POLISH-BAR.md](references/POLISH-BAR.md)**.

---

## Failure Modes Table — The Asupersync Footguns

Every entry below was learned the hard way during the motivating asupersync 127-stash session. Treat them as known-quantity hazards.

| Symptom | Cause | What to do |
|---------|-------|------------|
| `git format-patch -1 stash@{N}` produces a tiny, empty, or unrelated patch that misses stash content | A stash is a merge commit; format-patch is not the stash-show diff and does not materialize untracked files | Use `git stash show -p --binary stash@{N}` for live inspection; during bundle build, use `git stash show -p --binary <inventory-sha>` and `<inventory-sha>^3` for untracked files. **Never** ship `git format-patch` output as the bundle's recovery diff |
| `git stash apply` or `git stash pop` reports conflicts and dirties the working tree | Both mutate state; if the apply fails midway, you're stuck cleaning up | **Always** `git apply --3way --check <bundle>/diffs/NNN.diff` first; only apply the diff (not the stash directly) on clean check |
| `git stash drop stash@{N}` shifts every higher-index entry down by one | Stash indexes are stack positions, not stable IDs | Drop by **highest** index first within each verdict bucket; restate the verbatim ref before each drop; never trust an index from an earlier inventory |
| Stash content's line numbers no longer match main | Stash predates a refactor; main moved by ~hundreds of lines | `git apply --3way` will hunt for the moved context; if it gives up, escalate to user with surrounding-code context — don't force the apply |
| `git apply --3way` succeeds but produces a syntactically-broken file | Refactor changed structural form (e.g., `if/else if` → `match`); apply preserved old form inside new form | Re-read the affected file; manually port the stash's intent into the new structure with the Edit tool; never sed/awk the fix |
| Working tree shows changes from other agents mid-run | Concurrent agents in the same repo (per AGENTS.md "Note for Codex/GPT-5.5") | Treat as if you made them. Never stash, revert, or overwrite. Re-snapshot `git status` before each Phase 6 apply |
| `rm -rf <bundle>/patches/` blocked by DCG | Destructive Command Guard hook | Don't fight it. The skill **never deletes the bundle** — the user manages bundle lifecycle. Design around DCG, don't try to bypass it |
| Stash `@{N}`'s parent SHA isn't reachable from any branch | Branch was deleted after the stash was made | The stash itself is still valid (commit objects don't disappear); the diff-vs-parent works fine; record the orphan-parent fact in `meta/NNN.txt` |
| `lock_until` (or whatever symbol the stash introduces) already exists on main but with different semantics | Stash predates an unrelated landing that took the same name | Read both implementations carefully; if they're functionally equivalent, mark `superseded`; if the stash's version is genuinely better, mark `novel` and surface the conflict to the user |
| Two stashes introduce the same fingerprint | Common when the stash list represents many parallel agent attempts at the same task | Mark all but the most recent as `superseded-by-newer-stash`; only Phase 6-apply the most recent if it's actually accretive over main |
| `git stash list` count differs between two runs | Concurrent agent created or dropped a stash between snapshots | Re-run Phase 2; never act on a stale inventory. The bundle's `index.tsv` is authoritative for that *snapshot point* |
| Beads database unwritable during the run | `.beads/beads.db` locked by a parallel `br` process | Skip the beads-issue creation; record `beads_skipped: true` in the handoff report; the run still succeeds |

Full diagnostic playbook with reproductions: **[FAILURE-MODES.md](references/FAILURE-MODES.md)**.

---

## Anti-Patterns (Never Do)

| ✗ | Why | Fix |
|---|-----|-----|
| Use `git format-patch -1 stash@{N}` for the bundle's recovery diff | It is not the stash recovery diff and can be empty or wrong | Use `git stash show -p --binary <inventory-sha>` plus `<inventory-sha>^3` for untracked files |
| Run `git stash pop` or `git stash apply` directly | Both mutate state and dirty the working tree on conflict | Use `git apply --3way` against the bundle's diff |
| Run `git stash clear` (mass drop) | Drops everything at once; if any apply later turns out to have been wrong, recovery is per-stash through the bundle | Drop individually with `git stash drop stash@{N}` after each is verified |
| Assume `main` is the primary branch | Many projects use `master`, `develop`, `trunk`, `default` — guessing wrong burns time | Detect via `git symbolic-ref refs/remotes/origin/HEAD` first |
| Drop in stash-list order (lowest index first) | Indexes shift after each drop; you'll drop the wrong stash | Drop **highest index first** within each verdict bucket; restate the verbatim ref before each drop |
| `rm -rf` the bundle after a successful run | DCG blocks it AND the user owns bundle lifecycle | Leave the bundle in place; report its path in handoff |
| Skip Phase 3 byte-equality verification | If the bundle is wrong, the entire run is unsafe | Phase 3 is a hard gate — refuse to proceed if even one ref doesn't match |
| Run a script over source files to "fix up" conflicts | Brittle regex transforms create more problems (per AGENTS.md "No Script-Based Changes") | Manual Edit-tool resolution only; surface conflict context to the user |
| Stash, revert, or overwrite changes from other agents in the working tree | Per AGENTS.md "Note for Codex/GPT-5.5" — those are concurrent agents' work | Treat as if you made them; never disturb |
| Push the recovery branch on the user's behalf | Like the documentation-website skill, deployment is the user's call | Print the suggested `git push` command and stop |
| Bypass pre-commit hooks (`--no-verify`) | The user's gates exist for a reason | If a hook fails, fix the underlying issue; if you can't, surface to user |
| Land keeper commits directly on the primary branch | Even with verification, mass-applied recoveries deserve user review | Land on `stash-recovery-<DATE>` branch; user merges/cherry-picks |

Full anti-pattern catalogue with worked examples: **[ANTI-PATTERNS.md](references/ANTI-PATTERNS.md)**.

---

## When NOT to Use This Skill

- **Fewer than 5 stashes.** Just `git stash list` and inspect manually. The recovery-bundle overhead doesn't pay off.
- **Stash-as-clipboard workflow.** Some developers (rare) use `git stash` as a copy-paste primitive between branches. Don't triage their working state out from under them — ask first.
- **CI checkout with stashes.** A CI host should have zero stashes; if it has any, the stashes are evidence of something else wrong (a broken hook, a leftover from a debug session). Investigate the cause, don't triage the symptom.
- **Mid-rebase / mid-merge.** `git status` shows `interactive rebase in progress` or unmerged paths — finish the operation first; the skill needs a clean checkout state to snapshot from.
- **Detached HEAD with no recovery branch base.** The skill needs a primary branch to land keepers onto; if the user is in detached-HEAD state, ask them to check out a branch first.
- **Stashes in a worktree.** Stashes are per-repo, not per-worktree, so this works fine — but warn the user that other worktrees against the same repo may see ref changes.

Full conditions and rationale: **[WHEN-NOT-TO-USE.md](references/WHEN-NOT-TO-USE.md)**.

---

## Pre-Flight & End Checklist

- [ ] Target path confirmed; primary branch detected (NOT assumed `main`)
- [ ] Stash count reported to user up front; mode selected
- [ ] Output mode confirmed (full / triage-only / apply-only)
- [ ] Recovery branch name confirmed; bundle path confirmed
- [ ] Working tree state snapshotted (`wt_phase0.txt`)
- [ ] Phase 1 produced `project_profile.json` with primary branch + quality-gate commands
- [ ] Phase 2 produced `inventory.tsv` covering every stash
- [ ] Phase 3 bundle exists with backup refs + diffs + meta + index + README; byte-equality verified
- [ ] Phase 4 triage workers all completed; `triage.tsv` is one row per stash
- [ ] Phase 5 user reviewed and confirmed the verdict table (or applied overrides)
- [ ] Phase 6 keeper commits all have a passing test/typecheck/lint run on top
- [ ] Phase 7 partial-split commits each apply only the novel hunks
- [ ] Phase 8 fresh-eyes ran ≥2 rounds clean; full test suite green; UBS clean (if available)
- [ ] Phase 9 cleanup_authorization.txt contains the verbatim user-typed authorization
- [ ] Phase 10 handoff_report.md emitted; beads issue filed; recovery recipes verified
- [ ] User informed they need to push (`git push origin stash-recovery-<DATE>`)
- [ ] Bundle path reported; left in place; not deleted

---

## Source Corpus

Every Anti-Pattern, Failure Mode, Operator card, and Stash Smell in this skill traces back to a real session or a verified git-internals quirk. The kernel is empirical, not aspirational.

| Source | Contribution |
|--------|--------------|
| Asupersync 127-stash session (2026-05-01) | The motivating worked example; the canonical `git format-patch` footgun; the refactor-conflict pattern; the highest-index-first drop discipline; 7 of 20 Anti-Patterns; 7 of 20 Failure Modes |
| AGENTS.md "Note for Codex/GPT-5.5" | The working-tree-drift discipline (Axiom 7) |
| AGENTS.md "Mandatory explicit plan" | The verbatim authorization gates (Axiom 10, ⚠ CONFIRM) |
| AGENTS.md "RULE NUMBER 1: NO FILE DELETION" | The bundle-lifecycle rule (Axiom 13); the "skill never deletes" principle |
| Pro Git §7 (stash internals) | Axiom 0 — stash as a 2-or-3-parent merge commit |
| Linus on the reflog | SAFETY-MODEL §Layer 1 (backup refs survive gc) |
| documentation-website-for-software-project | Phase loop structure; modes-of-reasoning; fresh-eyes prompt rotation; orchestration tiers |
| wills-and-estate-planning-skill | Universal-axioms kernel; verification-first overlay; mode router |
| saas-billing-patterns-for-stripe-and-paypal | Per-phase artifact manifest; polish-bar discipline; kickoff-prompt template |
| operationalizing-expertise (Track A) | Operator card structure; quote-bank pattern; cognitive-move taxonomy |

When extending this skill, every new card needs a source citation. New patterns without traceable provenance are speculation, not knowledge.

---

## Reference Index

### Core playbooks
| Need | File |
|------|------|
| Phase-by-phase playbook with exit criteria | [PHASES.md](references/PHASES.md) |
| Exact prompts for each parallel subagent | [AGENT-PROMPTS.md](references/AGENT-PROMPTS.md) |
| Per-stash triage rubric (fingerprinting, verdicts, evidence) | [TRIAGE-RUBRIC.md](references/TRIAGE-RUBRIC.md) |
| Polish Bar — what "successful" means | [POLISH-BAR.md](references/POLISH-BAR.md) |
| Verbatim kickoff prompts per mode | [KICKOFF-PROMPTS.md](references/KICKOFF-PROMPTS.md) |
| Per-phase SLOs and quality metrics | [MEASUREMENT.md](references/MEASUREMENT.md) |

### Methodology
| Need | File |
|------|------|
| Cognitive moves: operator cards + prompt modules | [OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md) |
| Reading stances: literal / skeptical / forensic / adversarial / etc. | [MODES-OF-REASONING.md](references/MODES-OF-REASONING.md) |
| Orchestration tiers + fan-out (default = single-session Task subagents; NTM optional) | [ORCHESTRATION.md](references/ORCHESTRATION.md) |
| Multi-model triangulation (Claude+Codex+Gemini) | [MULTI-MODEL-TRIANGULATION.md](references/MULTI-MODEL-TRIANGULATION.md) |
| Anti-pattern catalogue with worked examples | [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md) |
| Failure modes & diagnostic playbook | [FAILURE-MODES.md](references/FAILURE-MODES.md) |
| Incident playbook — when things go wrong | [INCIDENT-PLAYBOOK.md](references/INCIDENT-PLAYBOOK.md) |
| Quote bank — distilled invariants | [KEY-INSIGHTS.md](references/KEY-INSIGHTS.md) |
| Aspirational examples from world-class git workflows | [EXEMPLARS.md](references/EXEMPLARS.md) |

### Stash craft
| Need | File |
|------|------|
| Taxonomy of "stash smells" — wip, autostash, pre-push, etc. | [STASH-SMELLS.md](references/STASH-SMELLS.md) |
| Per-language fingerprint patterns | [LANGUAGE-PROFILES.md](references/LANGUAGE-PROFILES.md) |
| Repo-archetype adjustments (monorepo, worktree, submodule, LFS) | [REPO-ARCHETYPES.md](references/REPO-ARCHETYPES.md) |
| Commit-message craft for recovery commits | [COMMIT-MESSAGE-CRAFT.md](references/COMMIT-MESSAGE-CRAFT.md) |
| Evidence citation style guide | [EVIDENCE-CITATIONS.md](references/EVIDENCE-CITATIONS.md) |
| Timeline reconstruction from reflog and history | [TIMELINE-RECONSTRUCTION.md](references/TIMELINE-RECONSTRUCTION.md) |
| Working-tree-state guidance during the run | [WORKING-TREE-STATE.md](references/WORKING-TREE-STATE.md) |
| Fresh-eyes prompt extended library | [FRESH-EYES-PROMPTS.md](references/FRESH-EYES-PROMPTS.md) |
| When NOT to use this skill | [WHEN-NOT-TO-USE.md](references/WHEN-NOT-TO-USE.md) |

### Worked examples + recovery
| Need | File |
|------|------|
| The asupersync 127-stash session, annotated with operators | [WORKED-EXAMPLES.md](references/WORKED-EXAMPLES.md) |
| Recovery recipes — how to undo every kind of drop | [RECOVERY-RECIPES.md](references/RECOVERY-RECIPES.md) |
| Advanced recovery (gc-pruned, force-push, lost branches) | [ADVANCED-RECOVERY.md](references/ADVANCED-RECOVERY.md) |
| Bundle format spec (for tooling that consumes the bundle) | [BUNDLE-FORMAT-SPEC.md](references/BUNDLE-FORMAT-SPEC.md) |

### Operations
| Need | File |
|------|------|
| Safety model — every destructive action's reversibility chain | [SAFETY-MODEL.md](references/SAFETY-MODEL.md) |
| Beads + Agent Mail integration | [INTEGRATION.md](references/INTEGRATION.md) |
| Mining prior agent sessions via /cass | [CASS-MINING.md](references/CASS-MINING.md) |
| Glossary of skill-specific terms | [GLOSSARY.md](references/GLOSSARY.md) |

---

## Scripts

### Pipeline scripts
| Script | Phase | Purpose |
|--------|-------|---------|
| `scripts/check-skills.sh` | 0 | Detect helper skills + jsm state; write inventory JSON |
| `scripts/install-referenced-skills.sh` | 0 | Bulk-install missing skills via jsm |
| `scripts/git-doctor.sh` | 0 | Pre-flight repo health check (mid-rebase, bare, detached, etc.) |
| `scripts/snapshot-tree.sh` | 0 / 6 | Capture working-tree state for drift detection |
| `scripts/cass-mine.sh` | 0.5 | Mine prior agent sessions for context |
| `scripts/discover-project.sh` | 1 | Detect primary branch, build/test/lint commands, conventions |
| `scripts/discover-stashes.sh` | 2 | List stashes with metadata, group by message-prefix |
| `scripts/prefix-classifier.sh` | 2 | Classify stash messages into smell-categories |
| `scripts/build-bundle.sh` | 3 | Create backup refs + diffs + meta + index |
| `scripts/verify-bundle.sh` | 3 | Byte-equality check (gate before destructive phases) |
| `scripts/bundle-audit.sh` | 3 / 9 | Deep audit beyond byte-equality |
| `scripts/recovery-test.sh` | 3 | Verify recovery recipes actually work on a sample stash |
| `scripts/triage-batch.sh` | 4 | Worker — fingerprint + verify-on-main + verdict |
| `scripts/merge-triage.sh` | 5 | Merge batch tsvs; build user-facing decision table |
| `scripts/verdict-stats.sh` | 5 / 10 | Generate triage statistics for measurement |
| `scripts/apply-keeper.sh` | 6 | Apply → gates → commit (one keeper) |
| `scripts/partial-split.sh` | 7 | Split partially-novel diff into novel-hunks-only diff |
| `scripts/drop-confirmed.sh` | 9 | Drop one stash with hard `confirm=YES_DROP_<N>` flag |
| `scripts/handoff-report.sh` | 10 | Emit final report |
| `scripts/polish-bar-check.sh` | 10 | Verify run satisfied all 10 Polish Bar dimensions |
| `scripts/archive-workspace.sh` | 10+ | Archive workspace as tarball at end-of-run |

Scripts are resume-aware, log to the workspace, and exit non-zero on any irreversible failure (the run halts; the user investigates). Recovery-bundle creation is fail-closed: a non-empty bundle is reused only after verification, or a fresh `BUNDLE_OVERRIDE` path is chosen.

---

## Subagents

### Pipeline subagents
| Subagent | Phase | Purpose |
|----------|-------|---------|
| `subagents/project-profiler.md` | 1 | Project reconnaissance (codebase-archaeology + codebase-report) |
| `subagents/cass-miner.md` | 0.5 | Mine prior agent sessions for context (optional) |
| `subagents/inventory-agent.md` | 2 | Stash listing + metadata + grouping |
| `subagents/bundle-builder.md` | 3 | Backup refs + diffs + meta + verify |
| `subagents/audit-conductor.md` | 3 / 9 / 10 | Deep bundle audit at three checkpoints |
| `subagents/triage-worker.md` | 4 | Per-batch fingerprint + verify-on-main + verdict |
| `subagents/language-specialist.md` | 4 | Language-specific fingerprinting (Comprehensive only) |
| `subagents/archaeologist.md` | 4 | Forensic intent reconstruction for novel-but-stale rows |
| `subagents/triangulator.md` | 4 / 6 / 8 | Multi-model independent verification (Comprehensive only) |
| `subagents/triage-merger.md` | 5 | Merge batches, present decision table, capture overrides |
| `subagents/keeper-applier.md` | 6 | Apply each keeper, run gates, commit |
| `subagents/commit-message-author.md` | 6 / 7 | Rewrite auto-generated commit messages with proper craft |
| `subagents/partial-splitter.md` | 7 | Split-apply for partially-novel stashes |
| `subagents/fresh-eyes.md` | 8 | Three review prompts × ≥2 rounds |
| `subagents/cleanup-conductor.md` | 9 | Gated drops in correct order |
| `subagents/handoff-reporter.md` | 10 | Final report + beads issue + recovery recipes |
| `subagents/idea-wizard-reviewer.md` | 11 | User-lens skill-feedback review (optional) |
| `subagents/incident-responder.md` | * | Mid-run incident triage (any phase) |

## Asset Templates

| Template | Used by |
|----------|---------|
| `assets/intake-prompt.md` | Phase 0 up-front confirmations |
| `assets/templates/commit-message-template.md` | commit-message-author (Phase 6) |
| `assets/templates/triage-decision-template.md` | merge-triage.sh (Phase 5) |
| `assets/templates/conflict-resolution-template.md` | keeper-applier (Phase 6 conflicts) |
| `assets/templates/handoff-report-template.md` | handoff-reporter (Phase 10) |
| `assets/templates/forensic-report-template.md` | archaeologist (Phase 4 novel-but-stale) |

---

## Self-Test

Trigger phrases that should activate this skill:

- "Clean up my git stashes in `<path>`"
- "I have 200 stashes, are any worth keeping?"
- "Mine my stashes for useful work"
- "Stash archaeology on `/data/projects/foo`"
- "What's in my stashes?"
- "Triage these stashes — which are superseded?"
- "Recover useful WIP from my stash pile and drop the rest"
- "I see `*127` in my prompt — is that 127 commits ahead?" (the asupersync prompt)
- "Help me figure out what to do with my stashes"
- "An agent swarm left a bunch of stashes — clean them up safely"

Full trigger list + end-to-end smoke test on a 3-stash dummy repo: [SELF-TEST.md](SELF-TEST.md).
