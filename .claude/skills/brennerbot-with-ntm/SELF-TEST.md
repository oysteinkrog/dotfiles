# SELF-TEST.md — Trigger phrases + smoke test

## Trigger phrases

The skill should activate on phrasings like:

- "Investigate the design space for a bio-inspired alternative to nanochat"
- "Use brennerbot to figure out the best on-disk format for an append-only event log under 1KB events"
- "Run a multi-agent research session on `<question>` with hypothesis triage and adversarial debate"
- "Spin up a brennerbot swarm on this codebase to find the design weaknesses"
- "Resume the brennerbot session at `<workspace>` for another investigation pass"
- "Set up a Brenner-style hypothesis-and-evidence loop using ntm panes"
- "Triangulate a research question across cc + cod + gmi with adversarial debate"
- "What's the right architecture for X given constraints Y, Z? Use a multi-pane research swarm to figure it out"
- "Methodology drift check: how did our last brennerbot session diverge from canonical Brenner?"
- "Run a Brenner-style audit on this design doc with proposers, devil's advocates, and a synthesizer"
- "Apply the Brenner method (hypothesis triage, evidence packs, debate, distillation) to this question"
- "Frame this question for adversarial multi-agent investigation"
- "Use current NTM native BrennerBot pipelines to run an incident hypothesis loop"
- "Resume a Brenner-style NTM pipeline run and reconstruct what happened with causality/events"
- "I want the BrennerBot workflow, but using NTM's new pipeline/attention/causality features"

## Activation discipline

The skill **should** activate when:
- The user wants multi-agent research on a question with parallel hypothesis exploration
- The user asks for triangulated distillation across model families
- The user wants resumable research sessions with adversarial debate
- The user names "Brenner method" / "brennerbot" / "Brenner-style" explicitly

The skill **should NOT** activate when:
- The user wants single-agent research → use `/codebase-archaeology` or `/codebase-report` directly
- The user wants the brenner CLI itself → use `/brenner` (this skill is the methodology layer, not the CLI)
- The user wants just operator-loop tending of an existing swarm → use `/vibing-with-ntm`
- The user wants spawn-and-forget swarm work without methodology → use `/multi-agent-swarm-workflow`
- The user wants the ntm command catalog → use `/ntm`

## Smoke test (synthetic question)

This skill self-tests by mentally walking through the 10 phases on a tiny synthetic question:

> **Synthetic question:** "What is the best on-disk format for an append-only event log under 1KB events?"
> **Roster:** Squad (5 panes, cc:3 + cod:1 + gmi:1)
> **Mode:** corpus-distillation

### Phase 1 — Framing
- Apply ◊: paradox is that industry consensus is split between length-prefixed binary frames (Kafka) and JSONL (tooling-friendly), but a third class (CBOR-of-FlatBuffers + sparse offset index) benchmarks comparably to the first and tools comparably to the second. Why hasn't it taken over?
- Apply ✂: falsifier = "if a literature/codebase survey produces a verifiable benchmark where format X dominates format Y by ≥10× on the target workload, the question becomes 'use X'."
- Scope: append-only ≤1KB events, 10K-100K events/sec, 30-90 day retention. Out of scope: distributed coordination, encryption.
- Q-001 + H-000 (paradox) filed.

### Phase 2 — Bootstrap
- Verify current NTM surfaces: `ntm --robot-capabilities` includes `--robot-pipeline-run`, `--robot-attention`, `--robot-causality`; `ntm --robot-tools` reports usable orchestration dependencies.
- Spawn Squad: `ntm --robot-spawn=brennerbot-event-log --spawn-cc=3 --spawn-cod=1 --spawn-gmi=1 --spawn-wait`
- Dry-run executable pipeline: `ntm pipeline run .ntm/pipelines/brennerbot-squad.yaml --session brennerbot-event-log --var workspace_path=<workspace> --var session_id=brennerbot-event-log --var question_of_record_path=intake/question_of_record.md --var mode=corpus-distillation --dry-run`
- Pane 1 (cc): Proposer — productive-ignorance variant
- Panes 2 (cod), 3 (cc): Investigators
- Pane 4 (gmi): Devil's-Advocate
- Pane 5 (cc): Synthesizer + Adjudicator (rotating)
- Onboarding dispatched in parallel.

### Phase 3 — Hypothesis generation
- Proposer files candidate Hs:
  - H-001: "JSONL dominates for ≤1KB events because tooling cost dwarfs serialization cost."
  - H-002: "Length-prefixed binary frames dominate because the cost of parsing JSON at 100K events/sec exceeds the cost of binary-tooling friction."
  - H-003 (origin: third_alternative — INJECTED via MO-03c since H-001 vs H-002 is binary): "Both H-001 and H-002 assume the access pattern is fixed; under sparse-offset random reads, content-addressed CBOR-of-FlatBuffers with offset index dominates both."
- Triage merges duplicates, ranks. Slate: H-001, H-002, H-003.

### Phase 4 — Investigation
- Round 1: Investigator-1 fills EV-pack-H-001 (3 supports, 1 attempted falsifier — not fired).
- Round 1: Investigator-2 fills EV-pack-H-002 (3 supports, 1 refute — Kafka benchmarks at scale show 50% throughput drop in JSONL workloads).
- Round 1: Investigator-3 (rotating onto H-003) fills EV-pack-H-003 (2 supports — fugu-style "discount" via FlatBuffers, 1 attempted falsifier — couldn't find a benchmark dominating, so falsifier didn't fire).
- Devil's-Advocate (gmi) attacks H-001 strongest: critique C-001 severity:moderate ("JSONL workloads at 100K/sec hit GC pressure that binary frames don't"). Files counter-EV-007 from a Kafka benchmark.
- `convergence-check.sh --phase=4`: 1 EV refute on H-001, 1 EV refute potential on H-002 (the Kafka benchmark refutes JSONL claim) → kill_rate 1, add_rate 0 → CONVERGED.

### Phase 5 — Cross-examination
- Pair: H-001 vs H-002. Champion-cc argues H-001; Champion-cod argues H-002. After 3 rounds, gmi Adjudicator rules: H-002 confirmed (Kafka benchmark cited as falsifier-firing on H-001); H-001 refuted by EV-007.
- Pair: H-002 vs H-003. cc champions H-002, gmi champions H-003. After 3 rounds, cod Adjudicator rules: H-003 maintained but with confidence:medium (evidence promising but no decisive benchmark). H-002 maintained at confirmed.
- Result: H-002 confirmed; H-001 refuted; H-003 deferred (needs more evidence).

### Phase 6 — Synthesis
- by_cc.md: distillation emphasizing the binary-frame hypothesis confirmed; lists invariants (parsing-cost dominance for high-throughput append).
- by_cod.md: distillation emphasizing the "third alternative deferred but interesting" reading.
- by_gmi.md: distillation emphasizing the workload-dependence claim and challenging confirmed-vs-deferred boundary.
- Meta-synthesizer (a different family from dominant) reconciles. disagreement_register.md: D-001 (cc vs cod on whether deferred third alternative deserves Phase 4 reopen), D-002 (cc vs gmi on whether "workload-dependent" undermines the verdict), D-003 (cod vs gmi on whether Phase 5 adjudication of H-003 was premature).

### Phase 7 — Fresh-eyes audit
- All 5 panes run the trio. Round 1 surfaces 3 critical findings (one scale-check error in an assumption, one citation pointing to wrong line range, one missed third-alternative variant).
- Fix and re-run trio. Round 2: only typo-level findings.
- Round 3: clean. Two consecutive trivial trio-rounds → CONVERGED.
- `ubs` clean on `deliverables/scripts/` (only one helper script there).

### Phase 8 — Freeze
- `RESUME.md` written; `ntm --robot-causality=brennerbot-event-log --causality-project=<workspace>` captured; `ntm checkpoint save`; `git commit`; push.

### Phase 9 — Handback
- 1-page HANDBACK.md: "TL;DR: H-002 (binary frames) confirmed for the workload class. H-003 (CBOR + offset index) deferred — promising but no decisive benchmark. Open thread: a Phase 4 reopen targeting H-003 with synthetic benchmark."

### Phase 10 — Drift check
- Fresh general-purpose Agent reads session-logs, applies DRIFT-RUBRIC.md.
- Verdict: convergent (all 15 operators applied; phase order normal; bead invariants clean).
- One lesson: ⟂ Object-Transpose was applied unevenly (Investigator-1 used full corpus surface instead of a proxy; Investigator-2 picked a proxy first). Lesson: update MO-04a-investigate.md to make the proxy-cost-savings × signal-clarity scoring more explicit.

### Smoke test verdict

The skill walks through 10 phases on a tiny question with no dead-ends. Every operator card fires; every marching-order template lands; every script has a callsite. **Smoke test passes.**

---

## Mental dry-run completeness check

| Phase | Marching order(s) used | Beads written | Mail thread | Script | Pass? |
|-------|------------------------|---------------|-------------|--------|-------|
| 1 | MO-01 | Q-001, H-000 | (none) | bootstrap-session.sh | ✓ |
| 2 | MO-02 (×5 panes) | (none) | RS-... main session + onboard-pN ×5 | ntm pipeline dry-run + robot capabilities/tools | ✓ |
| 3 | MO-03a, MO-03b, MO-03c | H-001..H-003 | per-H ×3 | audit-bead-invariants.sh | ✓ |
| 4 | MO-04a (×3 H), MO-04b (×1 H) | EV-001..007, C-001 | per-H + INVEST-coord | convergence-check.sh, render-evidence-pack.sh | ✓ |
| 5 | MO-05a (×2 pairs), MO-05b (×2) | DEBATE-001..002, H state changes | per-debate ×2 + ADJUDICATE | (none) | ✓ |
| 6 | MO-06a (×3 families), MO-06b | D-cc-001, D-cod-001, D-gmi-001, D-meta-001 | META-DISTILL | disagreement-register-lint.sh | ✓ |
| 7 | MO-07a (×5 panes × 3 trio-rounds) | AF-001..AF-NNN | AUDIT-pN ×5 | convergence-check.sh, ubs | ✓ |
| 8 | MO-08 | (none new) | (none) | dump-session-report.sh, resume-session.sh --dry-run, ntm causality | ✓ |
| 9 | MO-09 | (none) | (none) | (none) | ✓ |
| 10 | MO-10 (fresh general-purpose Agent) | (none) | DRIFT optional | drift-check.sh | ✓ |

All phases land. All operators fire. All scripts have callsites.
