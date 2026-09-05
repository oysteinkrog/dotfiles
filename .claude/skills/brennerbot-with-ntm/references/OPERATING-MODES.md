# OPERATING-MODES.md — Mode Definitions, Exit Criteria, Required Artifacts

<!-- TOC: Mode fresh-question | Mode code-investigation | Mode corpus-distillation | Mode resume-session | Mode methodology-drift-check | Mode incident-investigation | Mode comparison table | Mode-specific kickoff prompts | Auto-detect heuristics -->

The skill ships 6 modes. The phase loop is the same; the **phases run, exit criteria, and required artifacts** differ.

---

## Mode: `fresh-question`

**Use when:** new research question, no prior workspace, no specific target codebase or corpus.

**Phases run:** All 10.

**Required artifacts** at session close:

- `intake/question_of_record.md` with non-empty Falsifier
- `corpus/corpus_index.md` (may have ≥0 rows; corpus is built up by Phase 4 if minimal)
- ≥3 `H-*` beads with ≥1 `origin:third_alternative`
- ≥1 confirmed `H-*` with ≥1 DEBATE-* survivability
- `distillations/by_<family>.md` × N model families
- `distillations/meta_synthesis.md` + non-empty `disagreement_register.md`
- Phase 7 audit converged ≥2 clean rounds
- `RESUME.md`, `HANDBACK.md`, `DRIFT-CHECK.md`

**Default tier:** Squad (5 panes).

---

## Mode: `code-investigation`

**Use when:** target is a codebase; questions revolve around its design space, weaknesses, alternatives.

**Phases run:** All 10. **Phase 1 special:** invoke `/codebase-archaeology` and `/codebase-report` to produce `intake/target_inventory.md`.

**Additional Phase-1 outputs:**

- `intake/target_inventory.md` — repo structure + claimed features
- `corpus/ingested/git-log.txt` — full git log
- `corpus/ingested/key-files/` — top 20 most-touched files (from `git log --pretty=format: --name-only | sort | uniq -c | sort -rn | head -20`)
- `corpus/corpus_index.md § code_pin:` — `git rev-parse HEAD` of target codebase + dirty status

**Phase 4 special:** evidence packs cite `<file_path>:<line_range>` and commit SHAs.

**Phase 7 special:** include `/reality-check-for-project` audit if target has README/plan claims.

**Default tier:** Squad (5 panes).

---

## Mode: `corpus-distillation`

**Use when:** target is a directory of papers/transcripts/markdown.

**Phases run:** All 10. **Phase 1 special:** ingest corpus into `corpus/ingested/<source-id>/` with `§`-anchor scheme (one anchor per logical section — typically section heading or paragraph).

**Anchor-scheme template:**

```markdown
# corpus_index.md
| Source ID | Title | Authors | Date | Path | Hash | Anchor scheme |
|-----------|-------|---------|------|------|------|---------------|
| S-001 | "Optimal On-Disk Formats for Append-Only Logs" | Smith et al. | 2024 | corpus/ingested/S-001/main.md | sha256:... | §-per-section |
| S-002 | "Event Sourcing in Practice" | Jones | 2023 | corpus/ingested/S-002/main.md | sha256:... | §-per-paragraph |
```

**Phase 4 special:** evidence excerpts mandatory verbatim with `§`-anchors.

**Phase 6 special:** distillations include `## Verbatim quotes` section with `§`-anchored citations.

**Default tier:** Squad or Swarm depending on corpus size.

---

## Mode: `resume-session`

**Use when:** prior `RESUME.md` exists; user wants another pass.

**Phases run:** Skip Phase 1 framing. Re-enter at the phase indicated by `RESUME.md § next_loop_recommendation.phase`.

**Required artifacts** before resume:

- `RESUME.md` parses cleanly (`scripts/resume-session.sh --dry-run` exits 0)
- All hashes verify against current workspace state
- `ntm checkpoint` archive exists (or operator authorizes re-spawn)

**At resume close:** updated `RESUME.md`, possibly updated distillations / handback / drift-check.

**Resume sub-modes** (selected by `RESUME.md § mode_to_resume`):

- `fresh-pass` — re-enter at `last_phase_completed + 1`; full new round
- `targeted-investigation` — re-enter Phase 4 only on specific H-IDs in `open_threads`
- `distillation-only` — re-enter Phase 6; assume Phases 1–5 frozen
- `audit-only` — re-enter Phase 7 only; produce another audit pass
- `drift-check` — skip to Phase 10 only

---

## Mode: `methodology-drift-check`

**Use when:** compare past session trajectory to canonical Brenner.

**Phases run:** Phase 10 only. Read-only over prior `session-logs/`, `RESUME.md`, beads.

**Inputs:** path to a prior workspace.

**Outputs:** `<workspace>/deliverables/DRIFT-CHECK.md` with rubric per [DRIFT-RUBRIC.md](DRIFT-RUBRIC.md).

**Required artifacts:**

- DRIFT-CHECK.md with all rubric sections populated
- ≥1 `references/` file in *this* skill updated OR new entry added to `OPERATORS.md`

**Default tier:** Solo (1 fresh agent, not the original swarm).

**Special rule:** the drift-check agent must NOT be one of the original swarm panes. Use a fresh `general-purpose` Agent.

---

## Mode: `incident-investigation`

**Use when:** production incident; rapid hypothesis triage under time pressure.

**Phases run:** Compressed Phase 1, Phase 3, Phase 4 inline with Phase 5, and Phase 7 only. Skip formal Phase 2 bootstrap plus Phases 6, 8, 9, and 10 unless explicitly asked.

**Compressed Phase 1:**

- Question of record: "What is the root cause of incident X?"
- Falsifier: "If observation O is found, root cause is not X."
- Skip corpus assembly; use whatever logs/dashboards/metrics are immediately accessible.

**Compressed Phase 3:**

- 2–4 candidate root causes (≥1 third-alternative).
- Each with `falsifier:` from immediately observable evidence.

**Compressed Phase 4 (inline with Phase 5):**

- Each root cause hypothesis tested in parallel against immediately observable evidence.

**Phase 5 (full):**

- Adversarial debate on the surviving causes.

**Phase 7 (compressed):**

- Single fresh-eyes pass on the verdict; ≥1 reviewer must be from a different model family than the lead investigator.

**Skip 6, 8, 9, 10:** no methodology distillation; the verdict is the artifact.

**Hard time budget:** 30–60 min.

**Default tier:** Pair (2 panes — one investigator, one devil's-advocate).

**Output:** `deliverables/INCIDENT-VERDICT.md` (not `HANDBACK.md`):

- Root cause (with EV-NNN citations)
- Killed alternatives (with falsifier-fired EV-NNN)
- Recommended remediation
- Open questions (deferred to next post-mortem)

---

## Mode comparison table

| Mode | Phases run | Default tier | Min wall time | Corpus needed | Final artifact |
|------|-----------|--------------|---------------|---------------|----------------|
| fresh-question | 1–10 | Squad | 3–5h | optional | HANDBACK + DRIFT |
| code-investigation | 1–10 (Phase 1 special) | Squad | 4–6h | code repo | HANDBACK + DRIFT |
| corpus-distillation | 1–10 (Phase 1 ingestion) | Squad/Swarm | 4–8h | corpus dir | HANDBACK + DRIFT |
| resume-session | varies | inherits prior | 1–4h | inherits prior | updated RESUME + HANDBACK |
| methodology-drift-check | 10 only | Solo | 30–60min | prior workspace | DRIFT-CHECK |
| incident-investigation | 1, 3, 5(with 4 inline), 7 (compressed) | Pair | 30–60min | none required | INCIDENT-VERDICT |

---

## Mode-specific kickoff prompts

For each mode, the operator dispatches a different kickoff. The kickoff prompts live in [MARCHING-ORDERS.md](MARCHING-ORDERS.md):

| Mode | Kickoff template | Onboarding template |
|------|------------------|---------------------|
| fresh-question | MO-01-frame-question.md | MO-02-onboarding.md |
| code-investigation | MO-01-frame-question.md (with `<MODE>=code-investigation`) | MO-02-onboarding.md (code variant) |
| corpus-distillation | MO-01-frame-question.md (with `<MODE>=corpus-distillation`) | MO-02-onboarding.md (corpus variant) |
| resume-session | (none — `resume-session.sh` handles) | MO-resume.md |
| methodology-drift-check | (none) | (operator hands subagents/drift-auditor.md to fresh Agent) |
| incident-investigation | MO-01-frame-question.md (with `<MODE>=incident-investigation`) | MO-02-onboarding.md (incident variant) |

---

## Auto-detect heuristics

`bootstrap-session.sh` auto-detects mode from inputs:

```bash
# Pseudocode:
if [ -f "$WORKSPACE/deliverables/RESUME.md" ]; then
  MODE=resume-session
elif [ "$TARGET_TYPE" = "code-repo" ]; then
  MODE=code-investigation
elif [ "$TARGET_TYPE" = "corpus-dir" ]; then
  MODE=corpus-distillation
elif [ "$INPUT" =~ "drift" ] || [ "$INPUT" =~ "compare" ]; then
  MODE=methodology-drift-check
elif [ "$INPUT" =~ "incident" ] || [ "$INPUT" =~ "outage" ]; then
  MODE=incident-investigation
else
  MODE=fresh-question
fi
```

The operator can always override the auto-detected mode at the up-front confirmation step.
