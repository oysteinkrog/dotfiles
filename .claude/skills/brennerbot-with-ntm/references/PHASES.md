# PHASES.md — Per-Phase Playbook

<!-- TOC: Phase 1 — Target Framing & Corpus Assembly | Phase 2 — Swarm Bootstrap | Phase 3 — Hypothesis Generation | Phase 4 — Investigation | Phase 5 — Cross-Examination & Adversarial Debate | Phase 6 — Synthesis & Distillation | Phase 7 — Fresh-Eyes Audit | Phase 8 — Session Resumability & Artifact Freezing | Phase 9 — Operator Handback | Phase 10 — Methodology Drift Check | Reapply-Until-Quiet Discipline | Cross-Phase Invariants -->

Each phase is documented as: **Goal → Pre-conditions → Steps → Operator order → Beads written/read → Mail threads → Parallelism → Failure modes → Exit gate**.

Read the phase entry *before* dispatching any pane in that phase.

---

## Phase 1 — TARGET FRAMING & CORPUS ASSEMBLY

**Goal:** Turn the user's raw research request into a Brenner-style "question of record" with mandatory falsifier and scope, and stand up the workspace + beads schema. Ingest source material (codebase / corpus / prior session) into a queryable `corpus/` directory with content-hash anchors.

**Pre-conditions:** workspace path confirmed; `bootstrap-session.sh` ran; `phase0_scope_decision.md` written.

**Steps:**

1. (operator) Run `MO-01-frame-question.md` against the user's raw ask. The output is `intake/question_of_record.md` with required sections: **Question**, **Paradox**, **Falsifier**, **Scope**, **Out-of-scope**, **Mode**, **Provenance** (where the question came from).
2. (operator) Apply ◊ Paradox-Hunt: identify ≥2 well-attested facts in tension. The paradox seeds the first hypothesis bead.
3. (operator) Ingest corpus into `corpus/ingested/`:
   - **Codebase mode:** `git log --oneline > corpus/ingested/git-log.txt`; check out specific tree at SHA; record SHA + dirty status in `corpus/corpus_index.md`.
   - **Corpus-distillation mode:** copy markdown / PDF text into `corpus/ingested/<source-id>/`; assign `§`-anchor scheme (one anchor per logical section); record content-hash + anchor scheme in `corpus_index.md`.
   - **Fresh-question mode:** corpus may be empty — that's fine; Phase 4 will surface what's needed.
4. (operator) `br create` the seed beads:
   - `Q-001` — question of record (label `q-of-record`)
   - `H-000` — the paradox itself, as the first hypothesis bead with `origin: anomaly_spawned` and `state: proposed`
5. (operator) Optional: invoke `/cass` via `subagents/cass-miner.md` to mine prior agent sessions for related work. If hits found, file as `evidence` beads with `type:prior_session`.
6. (operator) `git add intake/ corpus/corpus_index.md .beads/ && git commit -m "Phase 1: question of record + corpus index"`. Mark `phase_1_complete.flag`.

**Operator order:** ◊ → ⌂ → ✂.

**Beads written:** `Q-001` (closed at end of phase), `H-000` (proposed), zero or more `EV-*` (`type:prior_session`) from cass mining.

**Beads read:** none.

**Mail threads:** none yet (no swarm spawned).

**Parallelism:** mostly sequential. Corpus chunk-ingest can fan out to subagents if corpus is large (>1GB).

**Failure modes:**

- F-101 question too broad → re-run MO-01 with tighter scope/out-of-scope
- F-102 corpus drift → pin SHA / content hash in `corpus_index.md`
- F-103 no falsifier → reject; the question is not yet a research question

**Exit gate:**

- `intake/question_of_record.md` exists with non-empty `Falsifier` section
- `corpus/corpus_index.md` has ≥1 row OR explicitly records `mode:fresh-question` with no corpus
- `Q-001` bead created and closed; `H-000` (paradox) bead created
- `phase_1_complete.flag` written

---

## Phase 2 — SWARM BOOTSTRAP

**Goal:** Spawn the ntm pane roster, assign roles per `ROSTER-PLANS.md`, wire Agent Mail (or fall back to ntm-inbox), install pre-commit guard, dispatch onboarding marching orders.

**Pre-conditions:** Phase 1 complete; `phase0_scope_decision.md` records `roster_tier`, `model_mix`, `coordination`.

**Steps:**

1. (operator) Spawn the ntm session, then run the chosen pipeline against it:
   ```bash
   ntm spawn RS-YYYYMMDD-slug --cc=<n> --cod=<m> --gmi=<k>
   ntm pipeline run .ntm/pipelines/brennerbot-<tier>.yaml \
     --session RS-YYYYMMDD-slug \
     --var session_id=RS-YYYYMMDD-slug
   ```
   Or, if not using a pipeline, stop after:
   ```bash
   ntm spawn RS-YYYYMMDD-slug --cc=<n> --cod=<m> --gmi=<k>
   ```
2. (operator) Verify `ntm --robot-snapshot` shows N panes alive.
3. (operator) Per pane, register Agent Mail identity:
   - If MCP Agent Mail available: `ensure_project(human_key=<workspace-path>)`, then `register_agent(project_key=<workspace-path>, ...)`.
   - If unavailable: fall back to ntm-inbox per [AGENT-MAIL-FALLBACKS.md](AGENT-MAIL-FALLBACKS.md). Flag in `phase0_scope_decision.md`.
4. (operator) Install MCP Agent Mail pre-commit guard (optional, recommended): `am guard status .`. If not installed, `am guard install .`.
5. (operator) Open the main session thread `RS-<YYYYMMDD>-<slug>` and per-role threads (one per pane).
6. (operator) Dispatch `MO-02-onboarding.md` to each pane in parallel via `ntm --robot-send`. Each pane gets:
   - Its assigned role
   - The question of record (`intake/question_of_record.md`) verbatim
   - The list of peer panes + their roles
   - The thread-id schema
   - Coordination mode (Agent Mail or ntm-inbox)
   - The ⊙ Productive-Ignorance directive (only for the designated ignorance pane)
7. (operator) Wait for each pane to ack via `ntm mail inbox <session> --json`. Each pane must reply with: "I am pane N, role X, ready."
8. `git commit -m "Phase 2: swarm bootstrapped"`. Mark `phase_2_complete.flag`.

**Operator order:** ⊙ Productive-Ignorance (role assignment).

**Beads written:** none.

**Beads read:** `Q-001`, `H-000` (paranthesised — included in onboarding briefing).

**Mail threads:** opens `RS-<YYYYMMDD>-<slug>` (main session); per-pane onboarding threads `RS-...-onboard-pN`.

**Parallelism:** onboarding dispatch is fully parallel across panes.

**Failure modes:**

- F-201 pane stuck at zsh → `/vibing-with-ntm` OC-026 + OC-027
- F-202 mail register times out → fall back to ntm-inbox per AGENT-MAIL-FALLBACKS.md
- F-203 two panes claim same role → adjudicator reassigns; if no adjudicator yet, operator hand-resolves

**Exit gate:**

- `ntm --robot-snapshot` shows expected pane count
- Every pane has acked onboarding (visible in `mail inbox` or ntm tail)
- `phase_2_complete.flag` written

---

## Phase 3 — HYPOTHESIS GENERATION (parallel)

**Goal:** Generate ≥3 distinct hypotheses with mandatory third-alternative; triage dedupes/clusters/ranks.

**Pre-conditions:** Phase 2 complete; all panes acked onboarding.

**Steps:**

1. (operator) Dispatch `MO-03a-propose.md` in parallel to all Proposer panes. Each pane emits 3–7 candidate `H-*` beads with required fields: `claim`, `mechanism`, `falsifier`, `expected_evidence`, `category`, `origin`, `confidence`. Optionally invoke `/idea-wizard` via `subagents/idea-generator.md` for breadth.
2. (operator) Wait for each Proposer to file beads (`br list --label=hypothesis --json`, then verify each expected pane filed an H bead with `origin: proposed`).
3. (operator) Dispatch `MO-03b-triage.md` to one Triage pane (rotating role). Triage:
   - Reads all proposed `H-*`
   - Applies ⊘ Level-Split: are any "rivals" actually different roles?
   - Applies 𝓛 Recode: do they disagree under any encoding?
   - Dedupes by marking the duplicate `state: superseded`, adding `parent: <canonical H>`, and linking it to the canonical H with `br dep add <duplicate> <canonical>` while keeping Beads status `open` until session closeout
   - Clusters and ranks by initial confidence
4. (operator) Apply `MO-03c-third-alternative.md`: if the surviving slate has fewer than 3 hypotheses, or none with `origin:third_alternative`, force-inject one. The Triage pane proposes "both could be wrong" hypotheses based on the false-binary it detected.
5. (operator) Run `scripts/audit-bead-invariants.sh` to confirm every `H-*` has `falsifier:` and `expected_evidence:` fields.
6. `git commit -m "Phase 3: hypothesis slate"`. Mark `phase_3_complete.flag`.

**Operator order:** 𝓛 → ⊘ → ⌂ → ✂ (third-alternative guard).

**Beads written:** `H-001..H-NNN` with `state: proposed → active`.

**Beads read:** `Q-001`, `H-000`.

**Mail threads:** per-hypothesis threads opened `RS-...-H-NNN` (one per surviving H).

**Parallelism:** Proposers fully parallel. Triage sequential after.

**Failure modes:**

- F-301 false-binary slate (no third alternative) → MO-03c
- F-302 hypothesis duplication → triage merge
- F-303 unfalsifiable → reject; back to MO-03a

**Exit gate:**

- ≥3 distinct active hypotheses
- ≥1 with `origin:third_alternative`
- All `H-*` have non-empty `falsifier:` and `expected_evidence:` (per `audit-bead-invariants.sh`)
- `phase_3_complete.flag` written

---

## Phase 4 — INVESTIGATION (heavily parallel; reapply-until-quiet)

**Goal:** Each surviving hypothesis is filled in with verbatim-cited evidence (supports + refutes); devil's advocates attack the strongest in parallel; iterate until kill_rate ≥ add_rate for the round.

**Pre-conditions:** Phase 3 complete; ≥3 active hypotheses.

**Steps (per round; expect 2–6 rounds):**

1. (operator) Assign each active `H-*` to one Investigator pane via `ntm --robot-send` with `MO-04a-investigate.md`. The MO mandates:
   - First action: produce a verbatim quote / file path / bench output that confirms or denies `H-*.expected_evidence`
   - Choose a proxy via ⟂ Object-Transpose; record the proxy choice
   - Apply ↑ Amplify: prefer high-contrast, binary, or ≥10× signals
   - File `EV-*` beads with `supports[]`, `refutes[]`, `informs[]` linking to `H-*`
   - Render `evidence/packs/EV-pack-H-NNN.md` from EV beads via `scripts/render-evidence-pack.sh`
   - Apply 🔧 DIY when tooling missing
2. (operator) Assign 1–2 Devil's-Advocate panes to the **highest-confidence** `H-*`s via `MO-04b-devils-advocate.md`. The MO mandates:
   - Attack the hypothesis (not the proposer)
   - File `C-*` (critique) beads with `target:H-NNN`, `attack`, `severity`, `evidence_to_confirm`
   - File counter-`EV-*` beads
3. (operator) Apply ΔE Exception-Quarantine: anomalies that don't fit any active H file as `anomaly` beads. Cluster check: ≥2 anomalies sharing a feature trigger a new `H-*` with `origin:anomaly_spawned`.
4. (operator) Run `scripts/convergence-check.sh` at end of round to measure kill_rate vs add_rate. If kill_rate < add_rate, dispatch another round. If kill_rate ≥ add_rate, exit Phase 4.
5. `git commit -m "Phase 4 round N: investigation"`.

**Operator order:** ⟂ → ↑ → ⌂ → ⊞ → ≡ → ΔE → 🔧.

**Beads written:** `EV-*` (mostly), `C-*`, `T-*`, `assumption-*`, `anomaly-*`, possibly new `H-*` with `origin:anomaly_spawned`.

**Beads read:** all active `H-*`.

**Mail threads:** per-hypothesis `RS-...-H-NNN` (Investigator + Devil's-Advocate post here); `RS-...-INVEST-coord` for cross-pane handoffs.

**Parallelism:** **heavily parallel** — one investigator per active H, devil's advocates running independently.

**Failure modes:**

- F-401 evidence inflation without H state changes → apply ✂ to every EV
- F-402 contradictory evidence loop → adjudication thread; force interpretation alignment
- F-403 confirmation-only bias → flip pane mode via `MO-mode-flip-investigator-to-advocate.md`
- F-404 missing potency check → reject the test bead

**Exit gate:**

- `convergence-check.sh` reports kill_rate ≥ add_rate for ≥1 round
- Every active `H-*` has ≥1 `EV-*` supporting it AND ≥1 attempted falsifier (which may have hit or missed)
- Every kill (`state: refuted`) has a citing `EV-*` or `T-*` in `refuted_by`
- `phase_4_complete.flag` written

---

## Phase 5 — CROSS-EXAMINATION & ADVERSARIAL DEBATE

**Goal:** Pairwise adversarial debate on surviving hypotheses; adjudicator scores; H states finalized.

**Pre-conditions:** Phase 4 converged; ≥1 surviving active `H-*`.

**Steps:**

1. (operator) Generate the debate pair list: for each surviving H, pair it with its strongest rival (often the one whose `falsifier` is closest to the other's `expected_evidence`).
2. (operator) Open one debate thread per pair: `RS-...-DEBATE-<H_I>-vs-<H_J>` (public H refs interpolated verbatim, e.g. `RS-...-DEBATE-H-001-vs-H-002`). File a debate bead with `DEBATE-*` as the public ref / `external_ref`, and use the actual generated `br` ID for later updates.
3. (operator) Dispatch `MO-05a-cross-exam.md` to two panes (one championing each H, ideally from different model families — apply 🤝 GAN). Format: `[opening]` → `[rebuttal]` → `[counter-rebuttal]` → `[adjudication]`. Max 3 rounds.
   - Executable pipelines dispatch Round 1 through `scripts/run-phase5-debate-loop.sh --round=1`, freezing `.brenner_workspace/debate-pairs.pairs`; rounds 2-3 reuse that frozen pair file with `--round=2` / `--round=3`. `generate-debate-pairs.sh` reads `.brenner_workspace/h-pane-mapping.json` for champion panes before falling back to bead metadata. Round 3 marks `phase_5_debate_rounds_complete.flag` after successful dispatch. If fewer than two active Hs survive, the helper writes an empty resolved-pairs file and marks that gate complete because there is no pairwise debate to run.
4. (operator) Dispatch `MO-05b-adjudicate.md` to a rotating Adjudicator pane (never the same pane two debates in a row). Adjudicator:
   - Reads the debate thread + cited evidence packs
   - Applies † Theory-Kill if any falsifier fired
   - Updates the description-level `state:` field to `confirmed`, `refuted`, `superseded`, or `deferred`
   - Files adjudication notes in the thread
5. (operator) For surviving Hs, scale-check via ⊞: every `assumption.type:scale_physics` must have a `calculation:` block.
6. `git commit -m "Phase 5: adversarial debate complete"`. Mark `phase_5_complete.flag`.

**Operator order:** 🤝 → †.

**Beads written:** `DEBATE-*`; updates to `H-*` description `state:` fields; possibly new `EV-*` (counter-evidence surfaced in debate).

**Beads read:** `H-*`, all `EV-*` linked to debating Hs, `T-*` if cited.

**Mail threads:** `RS-...-DEBATE-<H_I>-vs-<H_J>` (one per pair; bead IDs interpolated); `RS-...-ADJUDICATE` (consolidated).

**Parallelism:** parallel across hypothesis pairs. Adjudicators rotate.

**Failure modes:**

- F-501 adjudicator never kills → rotate adjudicator; flag in Phase 7 audit
- F-502 adjudicator favors model family → re-adjudicate via different model family
- F-503 debate stuck on rhetoric → reject responses without `EV-*` citations

**Exit gate:**

- Every `H-*` description `state:` is now in `{confirmed, refuted, superseded, deferred}` (no `active` left)
- Every debate has a recorded adjudication
- Every `state: confirmed` H has survived ≥1 debate with rebuttals on record
- `phase_5_complete.flag` written

---

## Phase 6 — SYNTHESIS & DISTILLATION (reapply-until-quiet)

**Goal:** One distillation per model family in the swarm; meta-synthesizer reconciles them and produces `disagreement_register.md`.

**Pre-conditions:** Phase 5 complete; ≥1 confirmed/superseded H.

**Steps:**

1. (operator) For each model family present in the swarm (cc, cod, gmi):
   - Assign a Synthesizer pane of that family
   - Dispatch `MO-06a-distill.md` (per-model-family distillation)
   - The MO mandates: read the question of record + all surviving H + evidence packs + debate adjudications; produce `distillations/by_<model>.md` with sections (Two-Axiom restatement adapted to question; Generative loop; Operator algebra adapted; Required Failure Modes; Bayesian substrate; one-page summary)
2. (operator) Wait for all per-model distillations to complete.
3. (operator) Dispatch `MO-06b-meta-synthesize.md` to a meta-synthesizer pane (operator's choice; should be a different model family than the dominant one). The MO mandates:
   - Read every `distillations/by_*.md`
   - Identify points of agreement (these go into `meta_synthesis.md`)
   - Identify points of disagreement (these go into `disagreement_register.md` with both readings + chosen synthesis)
   - **Mandatory: ≥1 disagreement entry per pair of distillations.** If the meta-synthesizer produces an empty disagreement register, reject the output and re-dispatch with explicit "find at least one disagreement per pair" directive.
4. (operator) Run `scripts/disagreement-register-lint.sh` to verify.
5. (operator) Optional: invoke `/multi-model-triangulation` directly via Agent tool to generate a third independent reconciliation; cross-check with meta-synthesizer's output.
6. (operator) If meta-synthesis produces only trivial edits in the second round → exit Phase 6. Otherwise iterate.
7. `git commit -m "Phase 6: distillations + meta-synthesis"`. Mark `phase_6_complete.flag`.

**Operator order:** ≡ → ⊘.

**Beads written:** `D-*` (one per distillation; `by_model: cc|cod|gmi|meta`).

**Beads read:** all surviving `H-*`, all linked `EV-*`, `DEBATE-*`.

**Mail threads:** `RS-...-META-DISTILL`.

**Parallelism:** per-model distillations are parallel. Meta-synthesis is sequential.

**Failure modes:**

- F-601 distillations agree by averaging silently → reject; mandate ≥1 explicit disagreement per pair
- F-602 single-family dominance → re-dispatch with explicit weight rule
- F-603 disagreement register missing → mandatory artifact

**Exit gate:**

- `distillations/by_*.md` × N model families exist
- `distillations/meta_synthesis.md` exists
- `distillations/disagreement_register.md` non-empty (per `disagreement-register-lint.sh`)
- Two consecutive meta-synthesis passes produce only trivial edits
- `phase_6_complete.flag` written

---

## Phase 7 — FRESH-EYES AUDIT (reapply-until-quiet, ≥2 clean rounds)

**Goal:** Three calibrated review prompts × 2 clean rounds; fix every finding; run `ubs` on any code in deliverables.

**Pre-conditions:** Phase 6 complete.

**Steps (per trio-round; expect 2–4 trio-rounds):**

1. (operator) Dispatch `MO-07a-fresh-eyes.md` to each pane in parallel (or, if Phase 6 saturated panes, kill+respawn fresh panes). The MO contains the verbatim trio of fresh-eyes prompts. Each pane runs all three.
2. (operator) Audit findings file as `audit-finding` beads with `severity` and `target_artifact`.
3. (operator) Apply ⊞ Scale-Check: re-verify every `assumption.type:scale_physics` calculation.
4. (operator) Apply ∿ Dephase: ask "is our top H just inheriting consensus?" If yes, audit must explicitly justify why consensus is correct.
5. (operator) Re-verify ✂ falsifiers: every `state: confirmed` H should still have a falsifier that *could* have fired.
6. (operator) For any code/scripts in `deliverables/scripts/`: run `/ubs`; fix every warning. Optionally invoke `/multi-pass-bug-hunting`.
7. (operator) If the trio-round produces only trivial edits AND the previous trio-round also did → exit Phase 7. Otherwise iterate.
8. `git commit -m "Phase 7: fresh-eyes audit converged"`. Mark `phase_7_complete.flag`.

**Operator order:** ⊞ → ∿ → ✂ (re-verify).

**Beads written:** `audit-finding-*`; possibly state changes on `H-*` if findings warrant.

**Beads read:** everything.

**Mail threads:** per-pane `RS-...-AUDIT-pN`.

**Parallelism:** parallel across panes.

**Failure modes:**

- F-701 audit accepts everything → verify with `/vibing-with-ntm` OC-016 convergence check before believing
- F-702 audit reopens settled questions on rhetoric → reject vibes-only audits; require `EV-*` citations
- F-703 ubs warnings ignored → hard-block Phase 8

**Exit gate:**

- 2 consecutive trio-rounds produce only trivial edits
- `ubs` clean on any code in `deliverables/scripts/`
- All `audit-finding-*` beads either `addressed` or explicitly `deferred` with reason
- `phase_7_complete.flag` written

---

## Phase 8 — SESSION RESUMABILITY & ARTIFACT FREEZING

**Goal:** Write `RESUME.md`, freeze artifacts, commit, export ntm checkpoint, ensure session is fully resumable.

**Pre-conditions:** Phase 7 audit converged ≥2 clean rounds.

**Steps:**

1. (operator) Compute hashes for `intake/question_of_record.md`, `distillations/disagreement_register.md`, `corpus/corpus_index.md`.
2. (operator) Dispatch `MO-08-freeze.md` to one pane (operator-typically). The MO produces `deliverables/RESUME.md` per the schema in [RESUME-PROTOCOL.md](RESUME-PROTOCOL.md).
3. (operator) `br sync --flush-only`. Verify clean (`git status` for `.beads/`).
4. (operator) `ntm checkpoint save <SESSION_ID> -m "Phase 8 freeze"`.
5. (operator) `ntm checkpoint export <SESSION_ID> <id> --output=.ntm/checkpoints/<id>.tar.gz` — produces a portable archive in `.ntm/checkpoints/`.
6. (operator) `git add . && git commit -m "Phase 8: session frozen — RESUME.md ready"`.
7. (operator) Verify `git status` clean and `RESUME.md` parseable by `scripts/resume-session.sh --dry-run`.
8. Mark `phase_8_complete.flag`.

**Operator order:** none (mechanical).

**Beads written:** none new.

**Beads read:** all (for hashes).

**Mail threads:** none.

**Parallelism:** sequential.

**Failure modes:**

- F-801 RESUME.md missing required tokens → re-run MO-08
- F-802 bead drift → `/fixing-beads-problems`
- F-803 ntm checkpoint missing pane state → re-save

**Exit gate:**

- `deliverables/RESUME.md` exists, hashes verify, `resume-session.sh --dry-run` clean
- `git status` clean
- `ntm checkpoint show <SESSION_ID> <id>` confirms checkpoint metadata and the exported archive exists at `.ntm/checkpoints/<id>.tar.gz`
- `phase_8_complete.flag` written

---

## Phase 9 — OPERATOR HANDBACK

**Goal:** Produce a one-page `HANDBACK.md` briefing for the user with what was found and what's still open, tagged for next-loop priority.

**Pre-conditions:** Phase 8 complete.

**Steps:**

1. (operator) Dispatch `MO-09-handback.md` to one pane (Synthesizer or operator-as-pane). The MO mandates:
   - Read `meta_synthesis.md` + `disagreement_register.md` + every `H-*` description `state:` + unresolved `EV-*` and `audit-finding-*`
   - Produce `deliverables/HANDBACK.md` with sections: **TL;DR (3 sentences)**, **What we found (bullet list, ≤8)**, **What's still open (bullet list, each with `next-action:`)**, **Recommended next loop (Phase 4 / 6 / 10 + duration estimate)**, **Risk register (≤3 items)**.
   - Hard limit: 1 page (≤80 lines). If longer, compress.
2. (operator) Verify every unresolved `H-*` and `EV-*` listed in "What's still open" has a `next-action:` in HANDBACK.md. Do not treat every bead with `--status=open` as unresolved; terminal H states stay bead-open until closeout.
3. (operator) Offer the user: "Run another loop?" Show `/vibing-with-ntm` tending command if they want it.
4. `git commit -m "Phase 9: handback briefing"`. Mark `phase_9_complete.flag`.

**Operator order:** ≡ (one final pass).

**Beads written:** none.

**Beads read:** everything (read-only).

**Mail threads:** none.

**Parallelism:** sequential, single agent.

**Failure modes:**

- F-901 handback >1 page → compress
- F-902 missing next-action tags → reject; require every listed unresolved thread tagged
- F-903 no recommendation for next loop → require explicit choice

**Exit gate:**

- `deliverables/HANDBACK.md` ≤1 page
- Every unresolved `H-*`/`EV-*` listed in "What's still open" has `next-action:`
- `phase_9_complete.flag` written

---

## Phase 10 — METHODOLOGY DRIFT CHECK

**Goal:** A *fresh agent* (not in the original swarm) compares actual session trajectory to canonical Brenner; flags improvements/regressions; feeds lessons back into `references/` for next session.

**Pre-conditions:** Phase 9 complete.

**Steps:**

1. (operator) Spawn a fresh `general-purpose` Agent (or use `/idea-wizard`). Hand it `subagents/drift-auditor.md` plus the workspace path.
2. (operator) The drift auditor reads `session-logs/`, `phase0_scope_decision.md`, every `phase_*_complete.flag`'s timestamp, all dispatched marching orders, and compares to the [DRIFT-RUBRIC.md](DRIFT-RUBRIC.md).
3. (operator) The drift auditor produces `deliverables/DRIFT-CHECK.md` with sections:
   - **Operators applied vs operators canonical** (which of the 15 fired? which didn't?)
   - **Phase ordering vs canonical** (any phase skipped, compressed, or reordered?)
   - **Marching-order modifications** (did the operator deviate from any MO template? why?)
   - **Improvements** (with explicit replacement of a Brenner principle by something measurably stronger)
   - **Regressions** (with the F-### code or anti-pattern matched)
   - **Lessons** (what should change in `references/` for next session?)
4. (operator) If lessons surface, update `references/OPERATORS.md` (new operator entry), `references/MARCHING-ORDERS.md` (new template), or other refs as appropriate.
5. (operator) `git commit -m "Phase 10: drift check + lessons fed back"`. Mark `phase_10_complete.flag`.

**Operator order:** ∿ → ◊.

**Beads written:** none new (drift findings live in `DRIFT-CHECK.md`, not beads).

**Beads read:** none required (drift is meta-level).

**Mail threads:** optional `RS-...-DRIFT` thread.

**Parallelism:** single fresh agent.

**Failure modes:**

- F-1001 drift rationalized as improvement → require explicit replacement test (replaced operator + measurable improvement)
- F-1002 missing baseline anchor → cite specific Brenner operators / §-anchors
- F-1003 lessons not fed back → Phase 10 not done until ≥1 ref file updated

**Exit gate:**

- `deliverables/DRIFT-CHECK.md` exists with all sections populated
- ≥1 `references/` file updated OR new entry added to `OPERATORS.md`
- `phase_10_complete.flag` written

---

## Reapply-Until-Quiet Discipline

Phases 4, 6, 7 are *reapply-until-quiet*. The discipline:

1. Define the phase's exit criterion as a **measurable** signal:
   - Phase 4: `kill_rate ≥ add_rate` (via `convergence-check.sh`)
   - Phase 6: two consecutive meta-synth passes produce only trivial edits
   - Phase 7: two consecutive trio-rounds produce only trivial edits
2. After each round, **measure**. Don't rely on vibes.
3. If criterion met → exit; if not → dispatch another round.
4. Hard cap: 6 rounds for Phase 4, 4 for Phase 6, 4 for Phase 7. If hard cap hit without convergence, escalate to Phase 10 drift-check or operator hand-decision.

Reapply discipline is the same as `/documentation-website-for-software-project` Phases 4 + 6 + 7. The pattern is load-bearing: it's the only way to know when to stop.

---

## Cross-Phase Invariants

These hold *across all phases*:

- **Mandatory falsifier** on every `H-*` (per ✂ operator)
- **Mandatory expected_evidence** on every `H-*` (per ⌂ operator)
- **Mandatory third-alternative** on the slate (per ⊘ operator + Brenner §103)
- **Mandatory scale_physics calculation** on every load-bearing assumption (per ⊞ operator)
- **Mandatory disagreement register** on Phase 6 output (per triangulation principle)
- **Mandatory next-action tag** on every unresolved `H-*`/`EV-*` listed in the Phase 9 "What's still open" section
- **Two consecutive clean rounds** before Phases 4/6/7 exit
- **No free-write prompts mid-phase** — always pick from `assets/marching-orders/MO-*.md` and parameterize

When in doubt, run `scripts/audit-bead-invariants.sh` and `scripts/dump-session-report.sh` to surface invariant violations.
