# FAILURE-TABLE.md — Failure-Code Catalog with Diagnosis + Recovery

<!-- TOC: Phase 1 Failures | Phase 2 Failures | Phase 3 Failures | Phase 4 Failures | Phase 5 Failures | Phase 6 Failures | Phase 7 Failures | Phase 8 Failures | Phase 9 Failures | Phase 10 Failures | Cross-Phase Stuck-Pane Failures -->

Compact in SKILL.md; full in this file. Every failure code F-### entry has: **Phase**, **Symptom**, **Diagnosis**, **Recovery moves**, **Escalation path**, **Operator card** (if a stuck-pane class).

---

## Phase 1 Failures

### F-101 — Question is too broad

**Symptom:** `intake/question_of_record.md § Falsifier` is empty or vague ("when we know the answer"), or the operator can't articulate what observation would invalidate the question.

**Diagnosis:** The user's raw ask has not yet been compiled into a research-grade question. Common forms: "design the future of X", "figure out the best way to Y", "explore the design space for Z."

**Recovery:**

1. Re-run `MO-01-frame-question.md` with explicit `<SCOPE>` and `<OUT_OF_SCOPE>` placeholders filled.
2. Force the operator to state a measurable falsifier: "If observation O occurs, the question becomes (a) trivially answered or (b) malformed."
3. If still vague after 2 rounds: split into ≥2 sub-questions, each framed individually.

**Escalation:** Abort and re-frame with the user; do not waste a swarm on a malformed question.

### F-102 — Corpus drift mid-session

**Symptom:** A bead or evidence pack cites a corpus location, but at next read the corpus content has changed (file edited, paper revised, code commit pushed).

**Diagnosis:** Corpus was not pinned at Phase 1.

**Recovery:**

1. Pin corpus *now*: record content-hash for every `corpus/ingested/<id>` file in `corpus/corpus_index.md`.
2. For code-investigation mode, record `git rev-parse HEAD` of the target codebase + dirty status.
3. Flag in `RESUME.md § corpus_drift_at: <timestamp>` so future resumes know.

**Escalation:** If drift invalidates >25% of evidence, escalate to a Phase 1 reframe.

### F-103 — No falsifier specified

**Symptom:** A `H-*` bead has empty or missing `falsifier:` field.

**Diagnosis:** The hypothesis isn't actually a hypothesis — it's a statement of preference or definition.

**Recovery:**

1. Reject the bead at Phase 3 triage.
2. Dispatch the proposer pane back to `MO-03a-propose.md` with explicit "produce falsifier or kill the bead" directive.

**Escalation:** None — this is a hard invariant.

---

## Phase 2 Failures

### F-201 — Pane stuck at zsh, no agent process

**Symptom:** `tmux list-panes -F '#{pane_current_command}'` shows `zsh` instead of `claude` / `codex` / `gemini`. Pane appears alive but no agent is running.

**Diagnosis:** Agent CLI exited silently (often after compaction or rate-limit timeout). `--robot-tail` shows old buffer content; `--robot-attention` / `--robot-wait` reports action-required or no live work; pane looks dead.

**Recovery:**

1. Per `/vibing-with-ntm` OC-026: pid audit. `tmux list-panes -t <session> -F '#{pane_index} #{pane_pid} #{pane_current_command}'`. Confirm zsh.
2. Per `/vibing-with-ntm` OC-027: two-step relaunch.
   ```bash
   ntm --robot-restart-pane=<session> --panes=<N> --restart-prompt="$(cat MO-resume.md)"
   ```

**Escalation:** `/vibing-with-ntm` autonomous unstick if the relaunch itself fails.

### F-202 — Mail register times out

**Symptom:** `register_agent` MCP call hangs or returns "server unavailable". MCP Agent Mail tools or `ntm --robot-tools` report degraded mail/reservation visibility.

**Diagnosis:** MCP Agent Mail server isn't running or is unreachable.

**Recovery:**

1. Check server: `am` alias OR `cd <agent-mail-install>/mcp_agent_mail && bash scripts/run_server_with_token.sh`.
2. If server can't be brought up, fall back to ntm-inbox per [AGENT-MAIL-FALLBACKS.md](AGENT-MAIL-FALLBACKS.md).
3. Record fallback in `phase0_scope_decision.md`.

**Escalation:** `/agent-mail` skill for server health debugging.

### F-203 — Two panes claim same role

**Symptom:** `phase0_scope_decision.md § roster:` lists two panes with the same role, or a Phase 5 dispatch fires the same pane as both Champion and Adjudicator.

**Diagnosis:** Onboarding misdispatch or operator typo in roster setup.

**Recovery:**

1. Read each pane's last ack message: `ntm mail inbox <session> --json | jq -r '.messages[]? | select((.subject // "") | test("onboard|ready"; "i")) | [.from_agent, .subject] | @tsv'`. The first to ack keeps the role; the second is reassigned.
2. Re-dispatch `MO-02-onboarding.md` to the loser with the new role.
3. Update `phase0_scope_decision.md`.

**Escalation:** If pattern repeats, the pipeline definition has the bug — fix the YAML.

---

## Phase 3 Failures

### F-301 — False-binary slate (no third alternative)

**Symptom:** `br list --label=hypothesis --status=open --json | jq '[.issues[]? | select((.description // "") | contains("origin: third_alternative"))] | length'` returns 0.

**Diagnosis:** Per Brenner §103 ("Both could be wrong"), every hypothesis slate must include an explicit third alternative. Without it, the swarm is committed to a false binary.

**Recovery:**

1. Detect the binary from existing H beads: which two H-IDs are mutual exclusives, with no overlap, no third option?
2. Dispatch `MO-03c-third-alternative.md` to the Triage pane with `<H_A_ID>`, `<H_B_ID>`, `<H_A_CLAIM>`, and `<H_B_CLAIM>` set from the strongest two sides of the false binary.
3. The Triage pane proposes 1–3 hypotheses with `origin:third_alternative` — they don't have to all survive, but at least one must enter the slate.

**Escalation:** Phase 3 cannot exit without ≥1 `origin:third_alternative` H. Hard invariant.

### F-302 — Hypothesis duplication

**Symptom:** Triage detects two `H-*` beads with materially the same `claim:` and `mechanism:`.

**Diagnosis:** Either two Proposers landed on the same hypothesis, or the wording differs but the content is identical.

**Recovery:**

1. Apply ⊘ Level-Split: are they actually claims about *different roles* (program vs interpreter)?
2. If yes, sharpen each bead's wording to make the role explicit; keep both.
3. If no, merge: `br update <child> --description="$(... add 'parent: <winner>')"`. The loser becomes a refinement bead.

**Escalation:** None — this is normal triage.

### F-303 — Unfalsifiable hypothesis

**Symptom:** A `H-*.falsifier` is non-empty but not actually decidable ("if math broke", "if reality changed").

**Diagnosis:** The proposer wrote a placeholder falsifier, not a real one.

**Recovery:**

1. Reject the bead at Phase 3 triage.
2. Dispatch the proposer back: "Your falsifier is not observable. Rewrite as: 'Observation O at time/place/source X, if seen, kills this hypothesis.' If you can't, the hypothesis is unfalsifiable; kill it."

**Escalation:** None.

---

## Phase 4 Failures

### F-401 — Evidence inflation without H state changes

**Symptom:** `convergence-check.sh` reports `add_rate ≥ kill_rate` for ≥2 consecutive rounds. Evidence count grows; H count doesn't shrink.

**Diagnosis:** Investigators are accumulating supportive citations rather than probing falsifiers. Per ✂ Exclusion-Test, this is anti-Brenner.

**Recovery:**

1. For each `EV-*` filed in the round, ask: "did this fire any H's falsifier?"
2. If no EV fired any falsifier in the round, dispatch `MO-mode-flip-investigator-to-advocate.md` to ≥1 investigator: flip to Devil's-Advocate role for next round.
3. Re-emphasize ⌂ Materialize: investigators must produce evidence about the *expected_evidence* AND the *falsifier* — not just supportive snippets.

**Escalation:** If still inflated after the flip, escalate to `MO-04b-devils-advocate.md` swarming the top H.

### F-402 — Contradictory evidence loop

**Symptom:** Same evidence (same `EV.source`) is cited as both `supports[H-X]` and `refutes[H-X]` by different panes.

**Diagnosis:** Panes disagree on the *interpretation* of the evidence, not the evidence itself.

**Recovery:**

1. Open `RS-...-INVEST-coord` thread: "Disagreement on EV-NNN interpretation. Investigator says X; Devil's-Advocate says Y."
2. Force resolution: each pane posts its interpretation with verbatim quote and reasoning. Adjudicator rules.
3. If neither interpretation is decisive, the evidence becomes an `anomaly` (per ΔE) until clarifying evidence arrives.

**Escalation:** Phase 5 escalation — the disagreement might be a debate-worthy hypothesis split.

### F-403 — Confirmation-only bias

**Symptom:** All `EV-*.supports[]` are populated; none have `refutes[]` for any H.

**Diagnosis:** Investigators are confirming, not probing. ✂ operator is missing.

**Recovery:**

1. Dispatch `MO-mode-flip-investigator-to-advocate.md` to one investigator: their next round explicitly searches for the *falsifier* of the H they were investigating.
2. Or: dispatch a fresh Devil's-Advocate pane on the top H.

**Escalation:** Escalation to next round; if 2 rounds in a row of pure confirmation, halt and reframe.

### F-404 — Test missing potency check

**Symptom:** A `T-*` bead has empty `potency_check:` field.

**Diagnosis:** Per Brenner §50 (chastity vs impotence), every test must distinguish "intervention failed" from "hypothesis wrong".

**Recovery:**

1. Reject the test bead.
2. Dispatch the proposer: "Add the potency check. What positive control or null hypothesis distinguishes 'we couldn't observe' from 'the hypothesis is wrong'?"

**Escalation:** None — hard invariant.

---

## Phase 5 Failures

### F-501 — Adjudicator never kills any H

**Symptom:** Across multiple debates, the Adjudicator pane has flipped 0 hypotheses to `refuted`.

**Diagnosis:** Adjudicator is risk-averse, attached to compromise verdicts, or inheriting consensus.

**Recovery:**

1. Rotate Adjudicator immediately (per role rotation rule). The *next* Adjudicator must explicitly look for falsifier-fired evidence.
2. If still 0 kills after 2 different Adjudicators, the underlying issue is Phase 4: no falsifiers actually fired. Escalate.

**Escalation:** Phase 7 audit will catch this; flag in DRIFT-CHECK.md.

### F-502 — Adjudicator favors model family

**Symptom:** All adjudications by pane N (model family X) flip in favor of hypotheses championed by panes of family X.

**Diagnosis:** Model-family bias.

**Recovery:**

1. Re-adjudicate the same debates via a different model family pane. If the new verdict differs, the original verdict was biased.
2. Update `phase0_scope_decision.md § adjudicator_rotation_log` with the bias note.

**Escalation:** Phase 10 drift-check will surface this.

### F-503 — Debate stuck on rhetoric

**Symptom:** Debate thread has 5+ posts, all without `## Evidence cited` blocks or `EV-*` references. Just rhetoric.

**Diagnosis:** Champions are arguing semantics, not evidence.

**Recovery:**

1. Adjudicator auto-rejects rhetoric posts (per AGENT-MAIL-CONVENTIONS.md): "Post requires ≥1 EV-NNN citation. Resubmit."
2. If both champions can't produce evidence after 2 rejections, Adjudicator rules: hypothesis lacks evidential basis → flip to `deferred` or `refuted` per default.

**Escalation:** None — the discipline is the fix.

---

## Phase 6 Failures

### F-601 — Distillations agree by averaging

**Symptom:** `distillations/disagreement_register.md` has 0 entries despite multiple per-model distillations.

**Diagnosis:** Meta-synthesizer is rubber-stamping consensus, defeating the purpose of multi-model triangulation.

**Recovery:**

1. Reject the meta-synthesis output.
2. Re-dispatch `MO-06b-meta-synthesize.md` with explicit directive: "Find at least one disagreement per pair of model-family distillations. Even small disagreements count. If the per-family distillations agree on everything, surface ≥1 *uncertainty* the meta-synthesis cannot resolve."
3. If second attempt also produces empty register, the per-family distillations may be too thin. Escalate.

**Escalation:** Phase 6 cannot exit without `disagreement_register.md` populated.

### F-602 — Single model family dominates

**Symptom:** `distillations/meta_synthesis.md` cites cc's `by_cc.md` for 80%+ of points; cod and gmi distillations barely appear.

**Diagnosis:** Meta-synthesizer is from the dominant family AND/OR the per-family distillations are imbalanced (one is much longer/deeper).

**Recovery:**

1. Re-dispatch meta-synthesis to a *different* model family pane (per role rotation rule).
2. If per-family imbalance is the cause, re-run the thin distillations with explicit "produce ≥3 invariants and ≥3 disagreements with peers" directive.

**Escalation:** Phase 10 drift-check.

### F-603 — Disagreement register missing

**Symptom:** `distillations/disagreement_register.md` doesn't exist after Phase 6 supposedly converged.

**Diagnosis:** Hard invariant violation.

**Recovery:**

1. Phase 6 cannot exit. Re-dispatch meta-synthesis with `MO-06b-meta-synthesize.md` and explicit "produce the disagreement register".

**Escalation:** None — hard invariant.

---

## Phase 7 Failures

### F-701 — Audit accepts everything ("LGTM × 5")

**Symptom:** All panes' audit findings file as `severity:low` or empty. Trio-round produces no `severity:critical|high` findings.

**Diagnosis:** Either the artifact is genuinely clean (rare for round 1) OR the audit panes are exhibiting convergence-language false positive (per `/vibing-with-ntm` AP-32).

**Recovery:**

1. Verify with Liveness Truth Stack: are panes actually reading? `tmux capture-pane -p` on each audit pane to see if they cite specific files/beads.
2. Run `convergence-check.sh --phase=7` — does it match the panes' verdict?
3. If panes are not citing specifics, re-dispatch with explicit "every finding must cite a file path and a bead id" directive.

**Escalation:** `/vibing-with-ntm` OC-016 convergence verification.

### F-702 — Audit reopens settled questions on rhetoric

**Symptom:** Audit findings include "I disagree with the H-005 confirmation" but cite no new EV-*.

**Diagnosis:** Audit pane is offering opinion, not evidence-based finding.

**Recovery:**

1. Reject vibes-only audits: "Findings must cite specific EV-NNN, T-NNN, or assumption-NNN that supports the finding. Vibes-only findings will not be addressed."
2. The pane must either find evidence or withdraw the finding.

**Escalation:** None — discipline is the fix.

### F-703 — UBS warnings ignored

**Symptom:** `deliverables/scripts/` contains code; `ubs <files>` exits non-zero; Phase 8 about to run anyway.

**Diagnosis:** Hard invariant: code in deliverables must pass `ubs` before Phase 8.

**Recovery:**

1. Hard-block Phase 8: do not write `phase_7_complete.flag`.
2. Dispatch `/multi-pass-bug-hunting` or fix manually.
3. Re-run `ubs` until exit 0.

**Escalation:** Use `/ubs` skill directly.

---

## Phase 8 Failures

### F-801 — RESUME.md missing required tokens

**Symptom:** `scripts/resume-session.sh --dry-run` reports missing fields.

**Diagnosis:** `MO-08-freeze.md` was incomplete or failed mid-write.

**Recovery:** Re-run `MO-08-freeze.md`; verify output includes every field in [RESUME-PROTOCOL.md](RESUME-PROTOCOL.md) schema.

### F-802 — Bead drift between `.beads/beads.db` and JSONL

**Symptom:** `br doctor` reports drift; `br show` fails.

**Diagnosis:** DB and JSONL store diverged.

**Recovery:** Use `/fixing-beads-problems` skill.

### F-803 — ntm checkpoint missing pane state

**Symptom:** `ntm checkpoint show <session> <id>` lists fewer panes than `ntm --robot-snapshot` shows.

**Diagnosis:** Checkpoint was saved before all panes were attached, or some panes were detached at save time.

**Recovery:** `ntm checkpoint save <session> -m "Phase 8 freeze v2"`; verify with `ntm checkpoint show <session> <id>`.

---

## Phase 9 Failures

### F-901 — Handback exceeds 1 page

**Symptom:** `wc -l deliverables/HANDBACK.md` > 80 lines.

**Diagnosis:** Compress.

**Recovery:** Re-dispatch `MO-09-handback.md` with explicit "≤80 lines" reminder; if persistent, the synthesizer pane should produce a summary-of-summary.

### F-902 — Unresolved-thread tags missing

**Symptom:** Some `H-*`, `EV-*`, `AF-*`, or `D-*` listed under "What's still open" lacks a `next-action:` in HANDBACK.md.

**Diagnosis:** Hard invariant.

**Recovery:** Reject; require every listed unresolved thread to be tagged. Use `scripts/audit-bead-invariants.sh § handback_open_thread_tags`.

### F-903 — No recommendation for next loop

**Symptom:** `HANDBACK.md § Recommended next loop` is empty or absent.

**Diagnosis:** Hard invariant — the user needs a recommendation, even if "stop here, no next loop needed."

**Recovery:** Dispatch handback writer with explicit directive to produce one of: `phase 4 (more investigation)`, `phase 6 (more distillation)`, `phase 10 (drift-check only)`, or `none — session converged`.

---

## Phase 10 Failures

### F-1001 — Drift rationalized as improvement

**Symptom:** `DRIFT-CHECK.md § Improvements` lists deviations as improvements without passing the [DRIFT-RUBRIC.md § Replacement Test](DRIFT-RUBRIC.md#the-replacement-test).

**Diagnosis:** Drift auditor is biased toward justifying the operator's choices.

**Recovery:** Re-run the drift check with a *different* fresh agent. If the second auditor agrees with the first on all "improvements," they're real. If not, surface the disagreement.

### F-1002 — Missing baseline anchor

**Symptom:** `DRIFT-CHECK.md` lacks `§`-anchors to the source corpus or canonical operator names.

**Diagnosis:** Drift auditor wasn't given the baseline.

**Recovery:** Re-dispatch with `KERNEL.md` and `OPERATORS.md` as required reads.

### F-1003 — Lessons not fed back

**Symptom:** Phase 10 marked complete but no `references/` file was updated.

**Diagnosis:** Hard invariant.

**Recovery:** The operator must commit ≥1 lesson to a ref file. Phase 10 cannot exit without it.

---

## Cross-Phase Stuck-Pane Failures (handled by `/vibing-with-ntm`)

For pane-state issues independent of phase content (rate limits, stuck buffers, OAuth expiry, codex paste limbo, broken context, etc.), defer to `/vibing-with-ntm`:

- Pane stuck at zsh → OC-026 + OC-027
- Rate-limited pane → OC-001 ping-probe + OC-002 rotate
- Identical tail ≥3 ticks → OC-003 stuck-pane ladder
- Prose-without-commits → OC-004 Ship-or-Surface
- Saturated context → OC-009 handoff-then-restart
- File reservation conflict → OC-008 force-release
- "Ready for validation" handoff failure → OC-036
- Cargo registry contention → OC-031 zombie sweep
- Bead DB lock → OC-031 + RECOVERY.md `--no-db` bypass

For each of these, escalate to `/vibing-with-ntm` rather than reinventing the recovery move here. This skill stays focused on *methodology* failures; `/vibing-with-ntm` covers *operator-loop* failures.
