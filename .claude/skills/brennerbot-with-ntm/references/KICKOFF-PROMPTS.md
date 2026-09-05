# KICKOFF-PROMPTS.md — Verbatim Per-Mode Kickoff Prompts

<!-- TOC: Mode fresh-question | Mode code-investigation | Mode corpus-distillation | Mode resume-session | Mode methodology-drift-check | Mode incident-investigation | Operator self-prompt | Calibration discipline -->

After Phase 0 confirmations land, the operator dispatches a kickoff prompt to the user (and/or to themselves as orchestrator). These are **calibrated** — use verbatim. Adjust placeholders only.

The pattern mirrors saas-billing's KICKOFF-PROMPTS.md: the kickoff is the contract between user and skill.

---

## Mode: `fresh-question`

Send to the user:

```
I'll run a brennerbot-style multi-agent research session on:

  Question: <USER_QUESTION>
  Workspace: <WORKSPACE_PATH>
  Roster: <TIER> (<MODEL_MIX>)
  Coordination: <agent-mail | ntm-inbox>
  Robot mode: <on | off>

Phase plan: 1 framing → 2 bootstrap → 3 hypothesize → 4 investigate → 5 debate → 6 distill → 7 audit → 8 freeze → 9 handback → 10 drift-check.

Phase 1 (framing) is operator + user judgment-heavy. I'll ask you up to 3 clarifying questions to nail down the question of record (must include a falsifier). After Phase 1 commits, the swarm runs largely autonomously through Phase 8, with optional tending if you enable robot mode.

Estimated wall time: <HOURS>h. Expected artifacts: question_of_record.md, ARTIFACT.md (7-section), per-model + meta distillations + disagreement_register.md, RESUME.md, HANDBACK.md, DRIFT-CHECK.md.

Ready to start Phase 1? Reply with the research question framed as a yes-or-no decidable claim, OR ask me to help you frame it.
```

---

## Mode: `code-investigation`

```
I'll run a brennerbot-style multi-agent research session against this codebase:

  Target codebase: <TARGET_PATH>
  Workspace (confirmed path): <WORKSPACE_PATH>
  Question to investigate: <USER_QUESTION>

Phase 1 will run /codebase-archaeology and /codebase-report on <TARGET_PATH> to seed the corpus index, pin the codebase at <git rev-parse HEAD>, and frame the question of record. Phase 4 evidence packs will cite <file:line> + commit SHA.

Roster: <TIER> (<MODEL_MIX>). Coordination: <COORDINATION>. Robot mode: <ROBOT_MODE>.

Estimated wall time: 4–6h.

Ready to start? Reply with the question framed as a decidable claim about the codebase, OR ask me to help you frame it (typical patterns: "what are the load-bearing weaknesses in <subsystem>?", "is alternative architecture <X> a measurable improvement over current <Y>?", "where does <claimed feature> actually break under <constraint>?").
```

---

## Mode: `corpus-distillation`

```
I'll run a brennerbot-style multi-agent research session over this corpus:

  Corpus: <CORPUS_PATH> (<N_FILES> files; types: <md | pdf | txt | mixed>)
  Workspace: <WORKSPACE_PATH>
  Question to investigate: <USER_QUESTION>

Phase 1 will:
  - Ingest each source into corpus/ingested/<source-id>/ with content-hash pinning
  - Assign §-anchor scheme (one anchor per logical section — typically heading-keyed)
  - Build corpus_index.md with provenance per source
  - Frame the question of record

Phase 4 evidence packs will require verbatim excerpts with §-anchor citations.

Roster: <TIER> (<MODEL_MIX>). Estimated wall time: 4–8h depending on corpus size.

Reply with the research question OR ask me to help you frame it. Typical corpus-distillation patterns:
  - "What are the load-bearing claims of <author/movement> as represented across this corpus?"
  - "Where do <author A> and <author B> disagree, and which side does the corpus support?"
  - "Distill the methodology of <field> from these <N> sources."
```

---

## Mode: `resume-session`

```
Resuming brennerbot session at <WORKSPACE_PATH>.

  Last completed phase: <LAST_PHASE>
  Next loop recommended: <RECOMMENDED_PHASE> — <REASON>
  Estimated duration: <HOURS>h
  Mode to resume: <MODE_TO_RESUME>

Verifying RESUME.md hashes against current workspace... <PASS | FAIL>.

Ntm checkpoint <CHECKPOINT_ID> archived at <ARCHIVE_PATH>: <PRESENT | MISSING — will respawn from roster>.

Open threads to address:
<LIST FROM RESUME.md.open_threads[]>

Audit findings still open:
<LIST FROM RESUME.md.audit_findings_open[]>

Ready to resume?
  - "yes, run the recommended next loop" — proceeds per RESUME.md.next_loop_recommendation
  - "let me change the mode to <X>" — operator override
  - "show me the full session report first" — runs `dump-session-report.sh`
```

---

## Mode: `methodology-drift-check`

```
I'll run a Phase 10 drift check on a prior brennerbot session.

  Workspace to audit: <PRIOR_WORKSPACE_PATH>
  Drift verdict will land at: <PRIOR_WORKSPACE_PATH>/deliverables/DRIFT-CHECK.md

Discipline: I'll dispatch this to a FRESH general-purpose Agent (NOT a swarm pane from the original session — that would defeat the audit per AP-O11). The fresh agent reads:
  - phase0_scope_decision.md
  - session-logs/round-*.md + dispatch-*.log
  - RESUME.md + HANDBACK.md
  - All beads via `br list --json`

It produces a verdict (convergent | divergent-improvement | divergent-regression | mixed), explicit operator-by-operator audit, regression catalog, improvement catalog (with Replacement Test discipline), and ≥1 lesson committed back into the brennerbot-with-ntm skill's references/.

Estimated wall time: 60 min.

Ready to start the audit?
```

---

## Mode: `incident-investigation`

```
I'll run a compressed brennerbot session for incident investigation.

  Incident: <INCIDENT_DESCRIPTION>
  Time pressure: <BUDGET_MINUTES> minutes
  Workspace: <WORKSPACE_PATH>

Compressed phase plan:
  - Phase 1 (compressed): root-cause framing — falsifier from immediately observable evidence
  - Phase 3 (compressed): 2-4 candidate causes including ≥1 third-alternative
  - Phase 4 (inline with Phase 5): each cause tested against immediately-observable logs/dashboards/metrics
  - Phase 5: adversarial debate; falsifier-fired evidence kills causes
  - Phase 7 (compressed): single fresh-eyes pass on the verdict

Skip 2/6/8/9/10 — no methodology distillation; the verdict is the artifact.

Roster: Pair (cc + cod). 60-min wall budget. Output: deliverables/INCIDENT-VERDICT.md.

This is a compressed mode. If the incident actually requires deeper methodology (e.g., post-mortem write-up beyond the immediate root cause), escalate to fresh-question mode after the verdict lands.

Ready? Reply with the incident description and any logs/dashboards I should know about up front.
```

---

## Operator self-prompt (orchestrator-as-operator)

When you (the orchestrator agent) are the operator running the swarm, dispatch yourself this self-prompt at session start:

```
You are the operator for brennerbot session <SESSION_ID>. Your responsibilities:

1. Read AGENTS.md if it exists at <WORKSPACE_PATH>.
2. Use ./scripts/bootstrap-session.sh first; do NOT bypass.
3. Phase 1 framing is judgment-heavy — engage the user in tight Q&A; do not autonomously ship a malformed question of record.
4. Phase 2 onboarding dispatches MO-02 to all panes in parallel via dispatch-marching-order.sh.
5. Phase 3-7 are the swarm loop: dispatch MOs per the pipeline; tick on /vibing-with-ntm cadence; address findings.
6. Phase 8 freeze is mechanical and mandatory.
7. Phase 9 handback ≤1 page.
8. Phase 10 drift-check MUST be a fresh general-purpose Agent — NEVER a swarm pane.

Loadbearing rules:
  - Every H bead has falsifier: + expected_evidence:
  - Every slate has ≥1 origin:third_alternative
  - Every refuted H has refuted_by:
  - Every scale_physics assumption has calculation:
  - disagreement_register.md ≥(N choose 2) entries where N = model families
  - Phase 7 audit ≥2 consecutive trio-rounds clean before Phase 8
  - HANDBACK.md ≤80 lines

Ship-or-Surface SLA inherited from /vibing-with-ntm: every dispatched pane must, within 60 min, commit a real artifact OR surface a specific blocker.

When in doubt during a tick, scan SKILL.md § Phase-By-Phase Quick Reference table or §FAILURE-TABLE.md.

Begin Phase 1.
```

---

## Calibration discipline

These prompts are calibrated based on:

- **What user-facing wording works** — vibing-with-ntm's "specific-terse" doctrine
- **What forces methodology compliance** — explicit invariant restatements at every kickoff
- **What surfaces operator decisions before they're irreversible** — wall-time estimate, mode confirmation, fresh-vs-resume choice up front

When extending — for new modes or new question archetypes — preserve the structure: question, scope, plan, estimate, falsifier requirement, ready-to-start question.

Don't shorten these "for brevity." The verbosity is load-bearing — it's the user's last chance to redirect before the swarm commits.
