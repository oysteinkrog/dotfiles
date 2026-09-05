# WORKSPACE-LAYOUT.md — Directory Discipline + Ownership

<!-- TOC: Top-level layout | Per-directory ownership | Cross-cutting rules | When the layout breaks | Layout invariants enforced by audit script -->

Every artifact has exactly one owner role. Multiple panes editing the same file requires explicit coordination via Agent Mail file reservations (or `assignee` in fallback mode).

---

## Top-level layout

```
<workspace>/
├── intake/                 # Phase 1 inputs
├── corpus/                 # Phase 1 corpus + index
├── evidence/               # Phase 4 outputs
├── distillations/          # Phase 6 outputs
├── deliverables/           # Final artifacts
├── analyses/               # Cross-cutting grades, source logs, external reviews
├── session-logs/           # Per-tick + per-round operator notes
├── .brenner_workspace/     # Internal session state (flags, scope, inventory)
├── .ntm/                   # ntm pipeline + project local config
├── .beads/                 # beads_rust state
└── .git/
```

---

## Per-directory ownership

### `intake/`

**Owner role:** operator (Phase 1 only).

**Files:**

- `question_of_record.md` — Brenner Step-0 framing. Sole owner: operator at Phase 1; never edited after Phase 1 close (any change requires Phase 1 reframe).
- `target_inventory.md` — what's being investigated. Operator-owned.
- `session_history.md` — cumulative log across resumes. Operator-owned; appended-only after each session close.

**No other role writes here.**

### `corpus/`

**Owner role:** operator (Phase 1) + investigators (Phase 4 read-only).

**Files:**

- `corpus_index.md` — content-hash + anchor scheme per source. Operator-owned at Phase 1; investigators may *append* new sources discovered mid-session.
- `ingested/<source-id>/...` — primary source content. Read-only after Phase 1 (corpus is pinned).
- `search_log.md` — every corpus search by any pane + result count. Append-only by all panes.

**Investigators NEVER edit `ingested/`.** If they need to add a new source, they file a `corpus-update` request in `INVEST-coord` thread; operator pulls and updates `corpus_index.md`.

### `evidence/`

**Owner role:** investigators (Phase 4) + devil's-advocates (Phase 4).

**Files:**

- `packs/EV-pack-H-NNN.md` — per-hypothesis evidence pack. **One owner pane per H** at any time, claimed via Agent Mail file reservation `evidence/packs/EV-pack-H-NNN.md`.
- `excerpts/<source-id>/...` — verbatim excerpts with `§`-anchors. Append-only by investigators.
- `verification_log.md` — every EV's verification step + outcome. Append-only by all panes.

**File reservation example:**

```
file_reservation_paths(
  project_key="<workspace-path>",
  agent_name="<agent-mail-name-for-pane>",
  paths=["evidence/packs/EV-pack-H-007.md"],
  ttl_seconds=3600,
  exclusive=true,
  reason="RS-...-H-007"
)
```

If a pane releases the reservation mid-edit, others wait until `ttl` expires.

### `distillations/`

**Owner role:** synthesizers (Phase 6).

**Files:**

- `by_cc.md` — owned by the cc Synthesizer pane. Exclusive write.
- `by_cod.md` — owned by the cod Synthesizer pane.
- `by_gmi.md` — owned by the gmi Synthesizer pane.
- `meta_synthesis.md` — owned by the Meta-synthesizer (different family from dominant).
- `disagreement_register.md` — owned by the Meta-synthesizer; can be appended-to by other synthesizers via mail thread `RS-...-META-DISTILL`.

**Cross-distillation editing prohibited.** If the cc synthesizer disagrees with cod's distillation, file in `disagreement_register.md` — don't edit `by_cod.md`.

### `deliverables/`

**Owner role:** Synthesizer or operator (Phase 8 / 9 / 10).

**Files:**

- `ARTIFACT.md` — the canonical 7-section research artifact. Compiled from beads + distillations at Phase 8 by `MO-08-freeze.md`.
- `RESUME.md` — Phase 8 freeze; operator + dump-script-generated.
- `HANDBACK.md` — Phase 9 one-pager; Synthesizer pane.
- `DRIFT-CHECK.md` — Phase 10 audit; fresh agent (NOT a swarm pane).
- `scripts/*.sh` — Investigator-built quick scripts (per 🔧 DIY). Owned by their author.

### `analyses/`

**Owner role:** operator + specialist subagents.

**Files:**

- `official-source-log.md` — source-level verification events for volatile sources. Append-only.
- `*/...` — specialist analysis outputs such as evidence grades, falsifier grades, replication attempts, and pre-publication review notes.

Append here when the artifact is analysis about the session rather than a final user-facing deliverable.

### `session-logs/`

**Owner role:** operator + auto-append by `dispatch-marching-order.sh`.

**Files:**

- `round-N.md` — per-round operator notes. One file per round.
- `dispatch-<TIMESTAMP>.log` — automatic log of every dispatch.
- `tick_history.jsonl` — append-only log of operator-tick decisions (which card applied, which pane was nudged, etc.).
- `ntm-pipeline-runs/<run-id>/...` — captured pipeline outputs.

**Read-only for panes.** Operator owns this directory.

### `.brenner_workspace/`

**Owner role:** operator + bootstrap script.

**Files:**

- `phase0_scope_decision.md` — operator-owned. Records mode, roster, model mix, parallelism, robot-mode, included/skipped phases. Updated when roster changes mid-session.
- `phase0_skill_inventory.json` — produced by `check-skills.sh`. Read-only after Phase 0.5.
- `phase_*_complete.flag` — written by `dump-session-report.sh` when each phase exits.

**No pane writes here.** Operator-only.

### `.ntm/`, `.beads/`, `.git/`

Standard tool directories. Don't hand-edit.

---

## Cross-cutting rules

### Pre-commit guard

When MCP Agent Mail is available, install `am guard install .`. The guard prevents commits to files currently reserved by other panes.

### Commit cadence

- Commit at every phase exit: `git add . && git commit -m "Phase N: <summary>"`.
- Beads sync before commit: `br sync --flush-only`.
- Push after Phase 8 freeze (or after Phase 9 if no freeze yet).

### Branch strategy

Workspace runs on `main`. No feature branches. Sessions are isolated by their workspace directory, not by git branch.

### `.gitignore`

```
.ntm/checkpoints/*.tar.gz       # only the latest is meaningful
.brenner_workspace/tick_history.jsonl   # large, regenerable
session-logs/ntm-pipeline-runs/  # regenerable
node_modules/
*.swp
.DS_Store
```

The Phase 8 freeze produces a checkpoint archive *outside* `.gitignore` (we do want it pinned to a commit).

### Backups

Before any destructive operation (rare; should never happen), the operator copies the workspace to `<workspace>.backup-<timestamp>/`. The skill never automatically deletes; per AGENTS.md RULE 1.

---

## When the layout breaks

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Two panes editing same evidence pack | File reservation expired or fallback mode no-coordination | `INVEST-coord` thread; oldest claim wins; loser flips to devil's advocate |
| `.beads/` drift | Multiple agents committing concurrently | `br sync --flush-only` + `/fixing-beads-problems` |
| `corpus/ingested/` modified mid-session | Investigator went around process | Diff vs Phase 1 SHA; if unauthorized, stop and ask the operator before any rollback |
| `phase_*_complete.flag` created without phase actually done | Operator manually created flag | Do not delete it automatically; request explicit written approval before removing or renaming the flag, then re-run the exit gate |
| `RESUME.md` written before Phase 8 finished | Premature dispatch | Re-run `MO-08-freeze.md` |

---

## Layout invariants enforced by audit script

`scripts/audit-bead-invariants.sh § layout_invariants` checks:

- `intake/question_of_record.md` exists if Phase 1 complete
- `corpus/corpus_index.md` exists if Phase 1 complete
- `evidence/packs/EV-pack-H-NNN.md` exists for every confirmed/active H if Phase 4 complete
- `distillations/by_<model>.md` exists for every model family in roster if Phase 6 complete
- `distillations/disagreement_register.md` exists if Phase 6 complete
- `deliverables/RESUME.md` exists if Phase 8 complete
- `deliverables/HANDBACK.md` exists if Phase 9 complete
- `deliverables/DRIFT-CHECK.md` exists if Phase 10 complete (or skipped reason recorded)
- `phase_<N>_complete.flag` matches the actual exit gate (cross-checks artifacts above)

Violations are F-### codes and abort the next phase entry.
