# ANTI-PATTERNS.md — Catalog with Bead/Failure-Code/Operator-Card Mapping

<!-- TOC: Methodology anti-patterns | Operational anti-patterns | Soft anti-patterns | Anti-pattern lookup queries -->

Each anti-pattern entry has: **Pattern**, **Why it's bad**, **F-code (if it triggers a phase failure)**, **Operator card (if it violates one)**, **Fix**, **Source-corpus evidence**.

---

## Methodology anti-patterns (Brenner-method violations)

### AP-M01 — Frame the question without a falsifier

**Pattern:** Phase 1 produces a question of record without a `Falsifier` section.

**Why it's bad:** Per Brenner §147 + Axiom 2, a question without a falsifier is a mood, not research. The whole skill cannot deliver value because there's nothing to kill against.

**F-code:** F-101.
**Operator card violated:** ✂ Exclusion-Test.
**Fix:** Re-run `MO-01-frame-question.md` with mandatory `Falsifier` section.
**Source:** §147 ("exclusion is always a tremendously good thing in science"); §69 (forbidden adjacent amino-acid pairs).

---

### AP-M02 — Generate hypotheses without third-alternative guard

**Pattern:** Phase 3 ends with a 2-hypothesis slate. Per Brenner §103, this is a false binary.

**Why it's bad:** "Both could be wrong" is the operational guard against false dichotomies. Without it, the swarm wastes effort adjudicating between two wrong choices.

**F-code:** F-301.
**Operator card violated:** ⊘ Level-Split (the third alternative is often a level-split that wasn't seen).
**Fix:** `MO-03c-third-alternative.md` mandatory.
**Source:** §103 ("both could be wrong").

---

### AP-M03 — Investigators only file confirming evidence

**Pattern:** Round of Phase 4 produces only `EV-*.supports[]`, never `EV-*.refutes[]`.

**Why it's bad:** Per §147, exclusion is the engine. Pure confirmation produces additive evidence (raises confidence) without subtractive evidence (lowers it on rivals). The hypothesis space doesn't shrink.

**F-code:** F-403.
**Operator card violated:** ✂ Exclusion-Test, † Theory-Kill.
**Fix:** `MO-mode-flip-investigator-to-advocate.md`. Mandatory: ≥1 attempted falsifier per H per round.
**Source:** §147; §62 (exclusion → "10^7-fold difference"); §69.

---

### AP-M04 — Synthesize by averaging the model-family distillations

**Pattern:** `meta_synthesis.md` reads as an average of cc/cod/gmi distillations with no disagreements registered.

**Why it's bad:** The whole point of multi-model triangulation is to surface disagreement (and force resolution). Averaging silently is the worst case — it loses information without revealing where models diverge.

**F-code:** F-601, F-603.
**Operator card violated:** ⊘ Level-Split (across model perspectives), 🤝 GAN.
**Fix:** Mandatory `disagreement_register.md`; reject empty registers.
**Source:** Cross-model triangulation principle; §103.

---

### AP-M05 — Adjudicator decides debates on rhetoric

**Pattern:** Adjudication notes cite "well argued" or "compelling case" without referencing specific `EV-*` or `T-*`.

**Why it's bad:** Per §62 ("seven-cycle log paper"), the only thing that should decide a debate is whether a falsifier fired. Rhetoric is for posterior-shaping, not posterior-collapse.

**F-code:** F-503.
**Operator card violated:** † Theory-Kill (won't fire on rhetoric); ✂ Exclusion-Test.
**Fix:** Adjudicator rejects rhetoric posts; mandatory `EV-NNN` citation per adjudication.
**Source:** §62; §147.

---

### AP-M06 — Run Phase 7 audit on the same model family that did Phase 6

**Pattern:** Phase 7 fresh-eyes panes are the same model family that did Phase 6 distillation.

**Why it's bad:** Loses the cross-model fresh-eyes value. The audit can't catch the synthesizer's blind spots if it's looking through the same lens.

**F-code:** F-701 often co-fires.
**Operator card violated:** ∿ Dephase, ⊙ Productive-Ignorance.
**Fix:** Mandatory model-family rotation between Phase 6 and Phase 7. If only one family in roster (Solo), use kill+respawn to simulate.
**Source:** §63 (productive ignorance); §143 (out of phase).

---

### AP-M07 — Skip Phase 8 freeze

**Pattern:** Session ends after Phase 7 without producing `RESUME.md`, committing, or exporting checkpoint.

**Why it's bad:** The session is not done until it's resumable. Skipping Phase 8 means the next session can't resume — all the methodology depth is throwaway.

**F-code:** F-801, F-802, F-803.
**Operator card violated:** none directly; this is a discipline failure.
**Fix:** Pre-flight checklist requires Phase 8 artifacts. Phase 9 cannot start without `phase_8_complete.flag`.
**Source:** none directly; engineering discipline.

---

### AP-M08 — Rationalize methodology drift as improvement

**Pattern:** Phase 10 produces "we did it differently and it worked better" without passing the replacement test in DRIFT-RUBRIC.md.

**Why it's bad:** Drift looks like improvement from the inside. Without the explicit replacement test (which Brenner principle was replaced; what's the metric; what number proves it), every deviation will be rationalized.

**F-code:** F-1001.
**Operator card violated:** ∿ Dephase (asking the wrong question).
**Fix:** Strict DRIFT-RUBRIC.md replacement test.
**Source:** §229 (kill theories early); §229 (Occam's broom).

---

### AP-M09 — Block on "perfect" corpus before starting

**Pattern:** Operator delays Phase 2 to "fully ingest" the corpus.

**Why it's bad:** Per §65, "the best thing to do a heroic voyage is just start. Don't equip yourself." Over-preparation defers feedback indefinitely.

**F-code:** none directly — this is a delay failure.
**Operator card violated:** 🔧 DIY (use whatever corpus you have); ⊙ Productive-Ignorance.
**Fix:** Allow Phase 4 to surface corpus gaps; ingest more in next round. The minimum corpus is whatever lets Phase 1 produce a question of record.
**Source:** §65 ("don't equip yourself"); §192 (opening game).

---

### AP-M10 — Treat anomalies as patches to the main theory

**Pattern:** New observation that conflicts with active H gets quietly added to the H description as a special case.

**Why it's bad:** Per §110–§111, anomalies belong in `anomaly_register`, not in the main theory. Patching produces a brittle theory that "explains" everything but predicts nothing.

**F-code:** F-402 often signals this.
**Operator card violated:** ΔE Exception-Quarantine.
**Fix:** Phase 4 + 7 audit catches; mandatory `anomaly` bead, not H-description amendment.
**Source:** §110; §111 ("we put them in an appendix").

---

### AP-M11 — Use a single pane (Solo) for triangulation

**Pattern:** Operator runs Solo tier and expects Phase 6 disagreement_register to surface useful disagreement.

**Why it's bad:** Single model family produces single distillation. The disagreement register is by definition empty. The operator is using the methodology in a degraded mode without acknowledging it.

**F-code:** none — Solo tier is degraded by design.
**Operator card violated:** 🤝 GAN.
**Fix:** Skill exits with explicit warning when Solo tier produces only one distillation. Encourage escalation to Pair tier minimum.
**Source:** Multi-model triangulation principle.

---

## Operational anti-patterns (operator-loop violations)

### AP-O01 — Use `ntm view` from a marching order

**Pattern:** A marching order tells a pane to run `ntm view`.

**Why it's bad:** Per `/ntm` gotchas, `ntm view` retiles the operator's tmux layout and returns nothing to automation. It's an interactive surface for humans only.

**Fix:** Use `ntm --robot-tail=<session>`, `ntm --robot-snapshot`, and the attention loop (`ntm --robot-attention --attention-session=<session> --attention-cursor=<cursor>`) instead.

---

### AP-O02 — Edit `.beads/*.jsonl` directly

**Pattern:** Operator or pane writes directly to `.beads/issues.jsonl` / `.beads/beads.db` to "fix" something.

**Why it's bad:** `br` is the only sanctioned editor. Direct edits cause DB drift, broken indices, and silent corruption.

**Fix:** Always use `br` commands. If drift detected, escalate to `/fixing-beads-problems`.

---

### AP-O03 — Allow new review-bead creation when backlog > 100

**Pattern:** Phase 7 audit panes file new audit-finding beads while existing audit-finding count > 100.

**Why it's bad:** Per `/vibing-with-ntm` review-bead inflation pattern (AP-30 there). Open beads grow unboundedly while the swarm feels productive.

**Fix:** Switch to close-the-backlog rotation. Block new audit-finding creation until count drops below 100. Use `/vibing-with-ntm` close-prompt.

---

### AP-O04 — Run hard-deletes on the workspace

**Pattern:** Operator runs `rm -rf`, `git reset --hard`, `git clean -fd` on the workspace.

**Why it's bad:** Per AGENTS.md RULE 1 + IRREVERSIBLE GIT rules — destroys session memory, possibly other agents' work. Always ask explicit user permission first.

**Fix:** Preserve the current tree, make file copies if needed, and use targeted follow-up commits or explicit operator-approved rollback steps. Never auto-clean, stash peer work, or run broad resets.

---

### AP-O05 — Free-write a marching order mid-session

**Pattern:** Operator types a custom prompt into `ntm send` instead of using `MO-*.md` template.

**Why it's bad:** Loses operator-algebra discipline; unreproducible at resume; bypasses the operator-card validators that the templates ship.

**Fix:** Always pick a template; parameterize via `dispatch-marching-order.sh`. If no template fits, *first* add one to `assets/marching-orders/`, *then* use it.

---

### AP-O06 — Dispatch without `<SESSION_ID>` parameter

**Pattern:** A marching-order dispatch omits the session ID parameter.

**Why it's bad:** Beads filed by the pane will not link back to the session; resume breaks; cross-pane coordination fails.

**Fix:** `dispatch-marching-order.sh` validates required params; refuses to dispatch without `<SESSION_ID>`.

---

### AP-O07 — Use Phase 7 audit to reopen Phase 4 questions

**Pattern:** Audit findings include "I think H-005 should be revisited; let me investigate further."

**Why it's bad:** Audit is meta-level (find errors in the artifact); investigation is content-level (find evidence). Mixing them collapses Phase 7 into Phase 4 and produces an audit loop.

**Fix:** Audit findings are findings, not investigations. If a finding warrants reopen, the operator decides; a new `T-*` test is filed; a Phase 4 round is dispatched. The audit doesn't directly investigate.

---

### AP-O08 — Sub-3-minute polling

**Pattern:** Operator runs `--robot-snapshot` every 60 seconds during Phase 4.

**Why it's bad:** Burns context window without new information. The swarm produces useful output on minute-scale, not second-scale.

**Fix:** Per `/vibing-with-ntm` cadence: 4 min during nucleation, 10–17 min steady state, 30 min during deep work. Use `--robot-wait --wait-until=attention` for event-driven instead of polling.

---

### AP-O09 — Silently downgrade roster mid-session without recording it

**Pattern:** Squad tier was chosen at Phase 0; mid-session a pane was killed (rate limit, machine reboot) and the operator continued without re-attaching.

**Why it's bad:** RESUME.md will lie about the roster; Phase 10 drift-check will mis-classify the trajectory.

**Fix:** Always record roster changes in `phase0_scope_decision.md § roster_changes:` log. Re-attach when possible; if not, reduce roster intentionally and record.

---

### AP-O10 — Re-create Agent Mail threads with new IDs after resume

**Pattern:** After `resume-session.sh`, panes open new threads `RS-...-fresh-pN` instead of resuming `RS-...-onboard-pN`.

**Why it's bad:** Breaks thread continuity; resume doesn't actually resume — it forks.

**Fix:** Reuse original thread IDs from `RESUME.md § agent_mail § threads_open:`. The MO-resume.md template handles this.

---

### AP-O11 — Run Phase 10 drift-check from a swarm pane

**Pattern:** Operator dispatches the drift-check to one of the existing swarm panes.

**Why it's bad:** The pane has been steeped in the session's local minimum; it can't audit the methodology because it *is* the methodology. Drift check requires fresh perspective.

**Fix:** Spawn a fresh `general-purpose` Agent (Agent tool) outside the swarm session; hand it `subagents/drift-auditor.md`.

---

## Soft anti-patterns (warnings, not hard failures)

### AP-S01 — Spending Phase 4 on a hypothesis that's likely refuted

**Symptom:** Operator continues investigating an H whose falsifier looks ready to fire.

**Better:** Apply ⤴ "quickie" — run the cheapest decisive experiment first. If it fires the falsifier, kill in 30 minutes instead of 3 hours.
**Source:** §99 (quickies).

### AP-S02 — Letting one model family dominate proposer pool

**Symptom:** Phase 3 proposers are all cc; the other families only investigate.

**Better:** Mix proposers. Different families generate different priors. Even one cod or gmi proposer raises the diversity dramatically.
**Source:** §63, §192 (productive ignorance).

### AP-S03 — Running Phase 6 with only 2 model families when 3 are available

**Symptom:** Roster has cc + cod + gmi but only cc and cod produced distillations.

**Better:** Use all available families. Phase 6 is the *one* phase where fewer voices is strictly worse.
**Source:** Triangulation principle.

### AP-S04 — Treating `H-*.confidence` as monotonic

**Symptom:** Confidence only goes up over rounds, never down (because investigators only file supports).

**Better:** Confidence-degrading is some progress (you've narrowed the prior). The 0.5-weight in convergence-check.sh's kill_rate reflects this. Encourage panes to file `EV-*.refutes[]`.

---

## Anti-pattern lookup queries

```bash
# Find AP-M01 (no falsifier):
br list --label=hypothesis --json | \
  jq -r '.issues[]? | select((.description // "") | contains("falsifier:") | not) | .id'

# Find AP-M02 (no third alternative):
br list --label=hypothesis --json | \
  jq '[.issues[]? | select((.description // "") | contains("origin: third_alternative"))] | length'

# Find AP-M03 (confirmation-only):
br list --label=evidence --json | \
  jq '[.issues[]? | select((.description // "") | contains("refutes:"))] | length'   # if 0, confirmation only

# Find AP-M07 (skipped Phase 8):
test -f <workspace>/.brenner_workspace/phase_8_complete.flag || echo "Phase 8 not done"

# Find AP-O02 (direct .beads edits):
git log -p --since="<session-start>" -- .beads/ | grep -E '^[+-]' | head -20

# Find AP-O09 (unrecorded roster changes):
diff <(jq '.roster | length' <workspace>/phase0_scope_decision.md) \
     <(ntm --robot-snapshot | jq '.sessions[] | select(.name == "RS-YYYYMMDD-<slug>") | .panes | length')
```

These queries can be wrapped into `scripts/audit-bead-invariants.sh` for periodic checks.
