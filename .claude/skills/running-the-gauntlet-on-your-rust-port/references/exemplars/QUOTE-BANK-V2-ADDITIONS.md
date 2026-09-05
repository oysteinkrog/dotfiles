# Quote Bank V2 — Additional Verbatim Source-Anchored Quotes

Companion file to [QUOTE-BANK.md](QUOTE-BANK.md). Same conventions: `[Q-NNN]` anchors, blockquoted verbatim text, `**Source:**` line, `**Operational use:**` line that names where the gauntlet applies the quote.

Sources (same as the original bank):
- **CC.md** = `/data/projects/frankensqlite/COMPREHENSIVE_BREAKDOWN_OF_FRANKENSQLITE_PERFORMANCE_AND_CONFORMANCE_ASSURANCE_PROCESS__CC.md`
- **CODEX.md** = `/data/projects/frankensqlite/COMPREHENSIVE_BREAKDOWN_OF_FRANKENSQLITE_PERFORMANCE_AND_CONFORMANCE_ASSURANCE_PROCESS__CODEX.md`

Numbering picks up at `[Q-201]` so this file never collides with the existing bank.

---

## §M — Mathematical reasoning (Q-201..Q-220)

These quotes name the *specific* mathematical claims FrankenSQLite makes and the places they show up in code. Mining them lets the gauntlet keep "every theorem has a file" honest in sibling ports.

### [Q-201] — CC.md §75 — Math toolkit has a file, not just a paper

> "Each row in that table is *not just citation*. It's a *concrete file location* in the codebase. An agent reading this catalog can grep for `Ville` or `BOCPD` or `Cahill` and find the implementation, the tests, the ledger entries, the bench numbers. The math isn't abstract; it's *traceable*."

**Source:** CC.md PART XVI §76 (lines 2681–2683)
**Operational use:** [`methodology/RUBRICS.md`](../methodology/RUBRICS.md) rubric 7 ("math is grep-able"); the [`subagents/eprocess-modeler.md`](../../subagents/eprocess-modeler.md) and [`subagents/invariant-catalog-builder.md`](../../subagents/invariant-catalog-builder.md) deliverables both require a file path next to every theorem cited.

### [Q-202] — CC.md §75 — Ville's inequality canonical citation

> "**Ville's inequality** (supermartingale max bound) | Ville 1939 | E-process Ville threshold rejection in `eprocess.rs`; lets H₀ be rejected anytime"

**Source:** CC.md PART XVI §75 (line 2646)
**Operational use:** [`patterns/70-E-PROCESSES.md`](../patterns/70-E-PROCESSES.md) anchors its anytime-validity claim here; the [`cookbook/e-process-rejection.md`](../cookbook/e-process-rejection.md) recipe quotes this row when explaining "why rejection without pre-committed N is sound".

### [Q-203] — CC.md §75 — Conformal prediction citation

> "**Conformal prediction** (distribution-free intervals) | Vovk-Gammerman-Shafer 2005 | Conformal bands on top of Beta posterior in `score_engine.rs`; Phase-9 verification gates"

**Source:** CC.md PART XVI §75 (line 2648)
**Operational use:** [`methodology/CONFORMAL-RATCHET.md`](../methodology/CONFORMAL-RATCHET.md) cites this as the foundation for the lower-bound-not-point-estimate ratchet rule.

### [Q-204] — CC.md §75 — BOCPD canonical citation

> "**Bayesian Online Change-Point Detection** | Adams-MacKay 2007 | `replay_harness.rs` regime detection; `drift_monitor.rs` BOCPD layer; README BOCPD section"

**Source:** CC.md PART XVI §75 (line 2649)
**Operational use:** [`patterns/80-BOCPD-REGIME-DETECTION.md`](../patterns/80-BOCPD-REGIME-DETECTION.md) and [`cookbook/bocpd-shift-detected.md`](../cookbook/bocpd-shift-detected.md) both anchor their math here.

### [Q-205] — CC.md §75 — Mauboussin process-vs-outcome citation

> "**Mauboussin's 'process vs outcome'** | Mauboussin 2012 | Implicit in the keep-gate philosophy: a good outcome with a bad process (no proof, no profile) is rejected; a bad outcome with a good process (correct hypothesis, no win) earns a ledger entry"

**Source:** CC.md PART XVI §75 (line 2677)
**Operational use:** [`methodology/KEEP-GATE-RULES.md`](../methodology/KEEP-GATE-RULES.md) lifts this verbatim as the philosophical justification for why ledger entries are written even when the outcome is "no kept change".

### [Q-206] — CC.md §11.1 — The 8 monitored invariants frame

> "MVCC INV-1..INV-7 monitoring; SsiFalsePositiveRate drift"

**Source:** CC.md PART XVI §75 row 2 (line 2647), expanded by §11.1
**Operational use:** [`subagents/invariant-catalog-builder.md`](../../subagents/invariant-catalog-builder.md) uses this as the template for sibling ports: every port needs its own enumerated INV-1..INV-N with one e-process apiece.

### [Q-207] — CC.md §76 — Math+code = traceability vs. either alone

> "Most engines have either the math (papers) *or* the code (implementations). FrankenSQLite has both, cross-linked."

**Source:** CC.md PART XVI §76 (line 2683)
**Operational use:** Mentioned in [`SKILL.md` § Philosophy](../../SKILL.md) and [`methodology/RUBRICS.md`](../methodology/RUBRICS.md) as the bar a Phase 16 certification bundle must clear.

### [Q-208] — CC.md §76 — Ten rows is valuable

> "**Generalization:** for sibling projects, build the equivalent catalog. Even ten rows is valuable. The discipline of 'every theorem has a file' is what turns a project from 'informed by recent research' into 'you can find any technique by searching for either its name or its file'."

**Source:** CC.md PART XVI §76 (lines 2685–2686)
**Operational use:** [`subagents/cookbook-author.md`](../../subagents/cookbook-author.md) includes a "math-catalog-author" sub-task that ships a 10-row table for every sibling adoption.

### [Q-209] — CC.md §11.3 — Arithmetic-mean e-value scope

> "Arithmetic mean of e-processes is itself an e-process under the global null *regardless of dependence between the individual invariants*."

**Source:** CC.md §11.3 (line 1011-ish, restated)
**Operational use:** Quoted in [`patterns/70-E-PROCESSES.md`](../patterns/70-E-PROCESSES.md) to justify why per-invariant calibration is *independent* of which invariants are correlated — the operator never has to argue about dependence.

### [Q-210] — CC.md §90.1 — Six MR pattern family enumeration

> "The skill catalogs six fundamental metamorphic relation patterns. The first one: ... 1. Equivalence (f(T(x)) = f(x)) / The transformation shouldn't change the output at all."

**Source:** CC.md PART XXIII §90.1 (lines 3186–3196)
**Operational use:** [`patterns/40-METAMORPHIC-TRANSFORMS.md`](../patterns/40-METAMORPHIC-TRANSFORMS.md) and [`subagents/metamorphic-author.md`](../../subagents/metamorphic-author.md) require every MR to declare which of the six patterns it instantiates.

### [Q-211] — CC.md §90.2 — Mutation testing as MR validator

> "VALIDATE → Mutation testing: does each MR actually catch planted bugs?"

**Source:** CC.md PART XXIII §90.2 (line 3205)
**Operational use:** [`cookbook/new-fault-class-discovered.md`](../cookbook/new-fault-class-discovered.md) cites this as the gate for accepting a new metamorphic relation into the suite.

### [Q-212] — CC.md §92 — Fourth-instance universal rule

> "When you think you found the deadlock and fixed the three instances you could see, **there is almost always a fourth**. This is the single most common failure mode across every concurrency debugging session in this repo's history."

**Source:** CC.md PART XXIII §92 (lines 3243–3244)
**Operational use:** Cited verbatim in [`methodology/ANTI-PATTERNS.md`](../methodology/ANTI-PATTERNS.md) and operationalized by [`subagents/red-team-attacker.md`](../../subagents/red-team-attacker.md), which must hunt the fourth instance before any deadlock bead is closed.

### [Q-213] — CC.md §92.1 — Static-pattern false-positive rule

> "When you think you found a concurrency bug via static pattern-matching, **verify the actual code paths before reporting it.** Grep-based audits produce pattern matches, not proofs."

**Source:** CC.md PART XXIII §92.1 (lines 3251–3252)
**Operational use:** [`subagents/red-team-attacker.md`](../../subagents/red-team-attacker.md) prompt includes this exact rule; [`methodology/ANTI-PATTERNS.md`](../methodology/ANTI-PATTERNS.md) lists "grep without code-path verification" as a rejection reason for triangulator findings.

### [Q-214] — CC.md §92.2 — Nine-class deadlock taxonomy

> "1. Classic mutex deadlock (AB-BA, self, reader-upgrade, condvar wakeup loop) / 2. Async / `.await` deadlocks (mutex held across await, channel cycle) / 3. Livelock / retry storms / broken condvar / 4. Database concurrency (SQLITE_BUSY, long transaction, writer fight) / 5. LD_PRELOAD / runtime-init reentrancy / 6. Data races / TOCTOU / 7. Multi-process / swarm races (advisory-lease race, missing reservation) / 8. Poisoning / partial state / 9. Memory ordering / lost wakeups"

**Source:** CC.md PART XXIII §92.2 (lines 3265–3275)
**Operational use:** [`patterns/65-CRASH-BOUNDARIES.md`](../patterns/65-CRASH-BOUNDARIES.md) and the [`subagents/soak-runner-loom.md`](../../subagents/soak-runner-loom.md) coverage matrix both require every deadlock-class test to declare which of the nine classes it covers.

### [Q-215] — CC.md §93 — Lean-formal one-frog rule

> "Work one frog at a time; no parallel frogs. / No theorem is 'done' before 7-check conformance parity passes. / No alignment claim without witness + regression + artifact hash. / Treat proof friction as evidence, not tactic debt. / Change one lever per iteration, then re-run proof + conformance."

**Source:** CC.md PART XXIII §93 (lines 3299–3303)
**Operational use:** [`subagents/iteration-coordinator.md`](../../subagents/iteration-coordinator.md) and [`methodology/CONVERGENCE.md`](../methodology/CONVERGENCE.md) both enforce the "one frog" rule when a round attempts to land >1 hypothesis simultaneously.

### [Q-216] — CC.md §11.2 — Per-invariant calibration is the honest tradeoff

> "Per-invariant calibration tunes the e-process growth rate so that *typical* runs of a healthy system don't spuriously trip the Ville threshold, while abnormal runs trip it quickly. Calibration is the honest tradeoff: too aggressive → false rejections; too lax → late detection."

**Source:** CC.md §11.2 (paraphrasing the calibration paragraph; verbatim portion: "Per-invariant calibration — the Honest Tradeoff")
**Operational use:** [`assets/eprocess-calibration-template.toml`](../../assets/eprocess-calibration-template.toml) bakes the tradeoff into a calibration manifest; [`cookbook/e-process-rejection.md`](../cookbook/e-process-rejection.md) routes recalibration through it.

### [Q-217] — CC.md §75 row 8 — Mazurkiewicz traces enable DPOR

> "**Mazurkiewicz traces** (concurrency equivalence classes) | Mazurkiewicz 1977 | asupersync `LabRuntime` + DPOR exploration; Phase-6 verification gate '3-transaction Mazurkiewicz trace exploration'"

**Source:** CC.md PART XVI §75 (line 2653)
**Operational use:** [`methodology/TRIANGULATION.md`](../methodology/TRIANGULATION.md) names DPOR-driven enumeration as one of the two acceptable triangulators for concurrency claims; [`subagents/soak-runner-loom.md`](../../subagents/soak-runner-loom.md) configures Loom equivalently.

### [Q-218] — CC.md §110 — DPOR practical reduction factor

> "DPOR's contribution: most interleavings are equivalent under the *Mazurkiewicz trace relation* (two independent operations can be swapped without changing observable behavior). DPOR enumerates only one representative per equivalence class. For typical concurrency tests, this reduces the exploration space by 4-6 orders of magnitude."

**Source:** CC.md PART XXVI §110 (lines 3713–3715)
**Operational use:** [`methodology/SOAK-PROTOCOL.md`](../methodology/SOAK-PROTOCOL.md) cites this as why a 24h DPOR run is meaningful — without DPOR, exhaustive enumeration of 3-transaction schedules is intractable.

### [Q-219] — CODEX.md §16.18 — SSI is conformance, not just performance

> "SSI and MVCC correctness are part of conformance, not just performance."

**Source:** CODEX.md §16.18 header (line 2438)
**Operational use:** [`methodology/THREE-PILLARS.md`](../THREE-PILLARS.md) cites this as the reason concurrency invariants land in the *conformance* pillar and not the *perf* pillar — even though concurrency is what perf usually measures.

### [Q-220] — CODEX.md §16.19 — E-processes need adversarial verification

> "E-Processes and DRO-Style Policies Need Adversarial Verification"

**Source:** CODEX.md §16.19 header (line 2466)
**Operational use:** [`subagents/red-team-attacker.md`](../../subagents/red-team-attacker.md) explicitly attacks the calibration of e-processes during Phase 11 fresh-eyes rounds; this quote justifies why the red-team pass is non-optional even when invariants are mathematically sound.

---

## §L — Ledger discipline expansions (Q-221..Q-235)

### [Q-221] — CC.md §21 — Ledger as collective memory of thinking

> "380 entries × 5 months = a corpus of *retired questions*. Re-running every benchmark from scratch is cheap. Re-running every *thinking attempt* from scratch is expensive. The ledger is the project's collective memory of the second."

**Source:** CC.md PART III §21 (lines 1298–1300)
**Operational use:** [`methodology/CASS-MINING.md`](../methodology/CASS-MINING.md) anchors the "60 days before perf work" rule here; [`subagents/cass-miner.md`](../../subagents/cass-miner.md) cites this when explaining why the mandate is non-optional.

### [Q-222] — CC.md §21 — Retry condition is the load-bearing bullet

> "That last bullet is the load-bearing one. The first six are bookkeeping; the seventh is *what makes the ledger useful in the future*."

**Source:** CC.md PART III §21 (line 1297)
**Operational use:** [`patterns/185-RETRY-CONDITION-PREDICATE.md`](../patterns/185-RETRY-CONDITION-PREDICATE.md) and [`methodology/RETRY-CONDITION-VOCABULARY.md`](../methodology/RETRY-CONDITION-VOCABULARY.md) both cite this; it explains why the 8 canonical predicate forms are the only acceptable phrasings.

### [Q-223] — CC.md §21 — Correctness proof is a prerequisite for rejection

> "**Correctness proof before rejection** — *because perf rejection only counts if correctness was already verified*. A rejected idea that was also incorrect doesn't earn a ledger entry; it earns a bug fix."

**Source:** CC.md PART III §21 (lines 1291–1292)
**Operational use:** [`methodology/KEEP-GATE-RULES.md`](../methodology/KEEP-GATE-RULES.md) cites this to explain why behaviour-changing candidates route to bug-fix beads, not negative-ledger entries.

### [Q-224] — CC.md §20 — Honesty in harness, not reviewer

> "The pattern is: **the harness encodes the discipline so that no individual is responsible for being virtuous.** This is the only way a multi-agent project with rotating attention can sustain rigor over months."

**Source:** CC.md PART III §20 (lines 1281–1282)
**Operational use:** Cited in [`methodology/KERNEL.md`](../methodology/KERNEL.md) as axiom K-2 ("agents are not honest; harnesses are"); the [`subagents/hooks-installer.md`](../../subagents/hooks-installer.md) deliverables embody it.

### [Q-225] — CC.md §20 — concurrent_mode_default_guard.txt as proof file

> "**`concurrent_mode_default_guard.txt`** is dropped into every bench artifact lane *as proof* that the experiment ran with the project's defining feature enabled. The Feb-10-2026 incident (an agent silently disabled it) cannot recur silently because the proof file is part of the artifact contract."

**Source:** CC.md PART III §20 item 6 (line 1277)
**Operational use:** [`patterns/175-CONCURRENT-MODE-GUARD.md`](../patterns/175-CONCURRENT-MODE-GUARD.md) generalizes this to "every project has one defining feature whose default has a proof file in every artifact lane".

### [Q-226] — CC.md §20 — Pass-over-pass is a file

> "Pass-over-pass gate is a *file*. `.bench-history/*.latest.json` is committed. You can't bench on your machine, see a 30% drop, and quietly not commit — the next CI run reads the committed baseline."

**Source:** CC.md PART III §20 item 9 (line 1280)
**Operational use:** [`patterns/155-BENCH-HISTORY-RATCHET.md`](../patterns/155-BENCH-HISTORY-RATCHET.md) and [`patterns/165-PASS-OVER-PASS-GATE.md`](../patterns/165-PASS-OVER-PASS-GATE.md) both quote this verbatim as the rule that gives the gate teeth.

### [Q-227] — CODEX.md §10.1 — Ledger purpose canonical statement

> "The ledger's purpose is to retire optimization search-space permanently: a future agent reading the ledger does not have to re-execute the same dead-end experiment."

**Source:** CODEX.md §10.1 (paraphrased preface; verbatim portion: "Purpose" header content; line ~1425)
**Operational use:** Cited in [`assets/negative-ledger-seed.md`](../../assets/negative-ledger-seed.md) as the front-matter prose for new ports.

### [Q-228] — CODEX.md §10.4 — Git history confirms operational, not aspirational

> "Git History Confirms Ledger Discipline"

**Source:** CODEX.md §10.4 header (line 1501)
**Operational use:** [`methodology/RUBRICS.md`](../methodology/RUBRICS.md) rubric 5 ("ledger is operational not aspirational") requires the certification bundler to show ≥30 git commits citing a ledger entry by ID in the last 90 days.

### [Q-229] — CODEX.md §16.22 — Negative evidence anti-repeat system

> "Negative Evidence Is an Anti-Repeat System"

**Source:** CODEX.md §16.22 header (line 2551)
**Operational use:** Used as the title-level slogan in the [`cookbook/INDEX.md`](../cookbook/INDEX.md) preamble for new contributors learning why the ledger exists.

### [Q-230] — CC.md §3.7 — Sibling progress docs cross-citation

> "Sibling Progress Docs"

**Source:** CC.md §3.7 header (line 601)
**Operational use:** [`methodology/INTEGRATION-WITH-HELPER-SKILLS.md`](../methodology/INTEGRATION-WITH-HELPER-SKILLS.md) cites this when describing how a Phase 16 certification bundle from one sibling can short-circuit a Phase 0 intake for another.

### [Q-231] — CC.md §3.5 — Pre-Work Mandatory Procedure

> "Pre-Work Mandatory Procedure (per AGENTS.md)"

**Source:** CC.md §3.5 header (line 555)
**Operational use:** [`assets/agents-md-mandate-paragraph.md`](../../assets/agents-md-mandate-paragraph.md) is the verbatim insertion the [`subagents/ledger-seeder.md`](../../subagents/ledger-seeder.md) drops into a target port's AGENTS.md.

### [Q-232] — CODEX.md §16.34 — Negative ledger is empirical memory

> "The Negative Ledger Is an Empirical Memory System"

**Source:** CODEX.md §16.34 header (line 3081)
**Operational use:** Cross-linked from [`methodology/CASS-MINING.md`](../methodology/CASS-MINING.md) as the framing for why the cass index is the runtime view of the ledger.

### [Q-233] — CODEX.md §16.35 — Negative evidence changed strategy

> "Negative Evidence Changed the Optimization Strategy"

**Source:** CODEX.md §16.35 header (line 3124)
**Operational use:** Quoted in the [`final-gauntlet-report-template.md`](../../assets/final-gauntlet-report-template.md) as the prompt for the "ledger-changed-our-direction" narrative section.

### [Q-234] — CC.md §3.6 — Beads tracking minimal shape

> "Beads Issue Tracking — `.beads/issues.jsonl`"

**Source:** CC.md §3.6 header (line 583)
**Operational use:** [`subagents/bead-author.md`](../../subagents/bead-author.md) and [`subagents/bead-polisher.md`](../../subagents/bead-polisher.md) cite this as the canonical filename; [`assets/github-workflows/bead-graph-validator.yml`](../../assets/github-workflows/bead-graph-validator.yml) reads from this exact path.

### [Q-235] — CC.md §43 — Architectural defer is a valid retry predicate

> "reconsider only inside the broader DML mutation operator redesign"

**Source:** CC.md PART VII §43 (line 1921, identical to Q-023 but referenced from a different operational use)
**Operational use:** [`methodology/RETRY-CONDITION-VOCABULARY.md`](../methodology/RETRY-CONDITION-VOCABULARY.md) lists "architectural-defer" as one of the 8 canonical retry-condition predicate templates; this is the verbatim exemplar.

---

## §C — Convergence wisdom (Q-236..Q-245)

### [Q-236] — CC.md §77 — Optimization velocity is sustained, not bursty

> "**Optimization velocity is sustained, not bursty.** ~10 kept optimizations per month over five months. The compound effect is what closed the original gap, not any single heroic session."

**Source:** CC.md PART XVII §77 observation 4 (lines 2725–2726)
**Operational use:** [`methodology/CONVERGENCE.md`](../methodology/CONVERGENCE.md) cites this to set expectations: 10 rounds is the floor not the ceiling; one round ≠ done.

### [Q-237] — CC.md §77 — Biggest aggregate wins from architectural bugs

> "**The most impactful aggregate win was the cache-eviction architectural bug, not any single 100x optimization.** 7x MT throughput from one campaign — most of that came from one cache-key bug."

**Source:** CC.md PART XVII §77 observation 2 (lines 2723–2724)
**Operational use:** [`patterns/245-CACHE-KEY-EVICTION-AUDIT.md`](../patterns/245-CACHE-KEY-EVICTION-AUDIT.md) opens with this quote; the [`cookbook/embedding-cache-staleness.md`](../cookbook/embedding-cache-staleness.md) recipe is the generalization.

### [Q-238] — CC.md §77 — 100x-2000x wins are on cold paths

> "**The biggest individual wins are 100x-2000x — but on cold paths.** `notify_all` empty-fast-path at 129x, `PublishedPages::clear` empty at 2922x — these are AtomicBool-gate wins on data structures that are *usually empty* (most threads aren't waiting; most pages haven't been published)."

**Source:** CC.md PART XVII §77 observation 1 (line 2722)
**Operational use:** [`patterns/205-ATOMIC-BOOL-EMPTY-GATE.md`](../patterns/205-ATOMIC-BOOL-EMPTY-GATE.md) cites this as the *only* honest framing for empty-gate wins — magnitude is real, but the absolute time saved per call is small unless the call site is in an inner loop.

### [Q-239] — CC.md §78 — Cumulative compound effect doctrine

> "These numbers are the *output* of the discipline described in Parts I–XVI. None of them came from a single change. All of them came from *the system that names every change, measures every change, retires every rejected change, and ratchets every kept change forward*."

**Source:** CC.md PART XVII §78 (line 2738)
**Operational use:** Cited in the [`assets/final-gauntlet-report-template.md`](../../assets/final-gauntlet-report-template.md) as the closing line for the "Outcomes" section.

### [Q-240] — CC.md §72 — Index + detail split keeps context small

> "`MEMORY.md` is the *index*; each session file is a *detail page*. The index is loaded into every new Claude conversation; the detail page is reachable via `cass view` / `cass expand`. The discipline keeps the loaded context small while keeping the full archive durable."

**Source:** CC.md PART XV §72 (lines 2613–2614)
**Operational use:** [`methodology/MEMORY-MD-CONVENTION.md`](../methodology/MEMORY-MD-CONVENTION.md) lifts this verbatim; [`methodology/COMPACTION-SURVIVAL.md`](../methodology/COMPACTION-SURVIVAL.md) describes the resume protocol that depends on it.

### [Q-241] — CC.md §74 — MEMORY.md bulk edits forbidden

> "The discipline that prevents conflicts: each session adds *one line* (linking to a new session_*.md file) and *occasionally* updates an existing line if a topic is superseded. Bulk edits to MEMORY.md are forbidden by convention. The bulk content lives in topic files."

**Source:** CC.md PART XV §74 (lines 2633–2634)
**Operational use:** [`methodology/MEMORY-MD-CONVENTION.md`](../methodology/MEMORY-MD-CONVENTION.md) encodes this as the "one line per session" rule.

### [Q-242] — CODEX.md §16.1 — Assurance flywheel definition

> "The Assurance Flywheel"

**Source:** CODEX.md §16.1 header (line 1919)
**Operational use:** [`methodology/CONVERGENCE.md`](../methodology/CONVERGENCE.md) frames Phases 5→10 explicitly as flywheel-turns; the [`subagents/iteration-coordinator.md`](../../subagents/iteration-coordinator.md) loops on this metaphor.

### [Q-243] — CODEX.md §16.11 — Ratchets make progress monotone

> "Confidence Gates and Ratchets Make Progress Monotone"

**Source:** CODEX.md §16.11 header (line 2235)
**Operational use:** [`methodology/CONFORMAL-RATCHET.md`](../methodology/CONFORMAL-RATCHET.md) cites this as the load-bearing claim of the lower-bound-only release rule.

### [Q-244] — CODEX.md §16.43 — Lower-bound, not vanity-score

> "Confidence Gates Are Lower-Bound Gates, Not Vanity Scores"

**Source:** CODEX.md §16.43 header (line 3462)
**Operational use:** Verbatim in [`methodology/CONFORMAL-RATCHET.md`](../methodology/CONFORMAL-RATCHET.md) and [`cookbook/ratchet-block.md`](../cookbook/ratchet-block.md); the bad-rejection mode "we beat the gate on point-estimate" is explicitly named here.

### [Q-245] — CODEX.md §16.21 — Beads encode proof obligations

> "Beads Encode Proof Obligations, Not Just Tasks"

**Source:** CODEX.md §16.21 header (line 2522)
**Operational use:** [`subagents/bead-author.md`](../../subagents/bead-author.md) and [`subagents/bead-polisher.md`](../../subagents/bead-polisher.md) cite this when explaining why every bead requires linked artifact paths.

---

## §S — Sibling adoption lessons (Q-246..Q-265)

### [Q-246] — CC.md §107 — Cross-sibling maturity matrix definition

> "This matrix is the *actionable diff* between FrankenSQLite's discipline and where each sibling stands. The columns to the right of 'Agent Mail' are the project-specific extensions; the columns up to 'bv' are the universal floor. Most siblings have the universal floor; few have the project-specific layers."

**Source:** CC.md PART XXIV §107 (lines 3635–3637)
**Operational use:** [`exemplars/SIBLING-PROJECTS-STATUS.md`](SIBLING-PROJECTS-STATUS.md) is keyed off this matrix; [`subagents/sibling-status-auditor.md`](../../subagents/sibling-status-auditor.md) regenerates the matrix at Phase 0 intake.

### [Q-247] — CC.md §108 — Skills first, modules second

> "For a new sibling project, the implication: **adopt the skills first, instantiate the modules second**. The modules emerge naturally from the skills' demands. The reverse order (build modules without the skill discipline) produces ad-hoc machinery that doesn't compose."

**Source:** CC.md PART XXV §108 (line 3672)
**Operational use:** [`methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md) and [`methodology/SKILL-FALLBACKS.md`](../methodology/SKILL-FALLBACKS.md) both lift this verbatim as the intake doctrine for a new sibling.

### [Q-248] — CC.md §108 — FrankenSQLite is a full demo of the skill stack

> "The single biggest insight from constructing this map: **FrankenSQLite has at least one module instantiating every entry in the skill catalog**. The project isn't using *some* of the skills; it's a *full demonstration suite* for the skill stack."

**Source:** CC.md PART XXV §108 (line 3670)
**Operational use:** [`exemplars/FRANKENSQLITE-BIBLE.md`](FRANKENSQLITE-BIBLE.md) cites this as the reason FrankenSQLite is the canonical worked example for every gauntlet rubric.

### [Q-249] — CC.md §99 — FrankenNumPy as most-mature sibling

> "FrankenNumPy is the closest sibling in discipline maturity. It's adopted *more* structural enforcement than FrankenSQLite in some areas (the codebase-hygiene `rg`-based gate is sharper)."

**Source:** CC.md PART XXIV §99 (lines 3528–3529)
**Operational use:** [`case-studies/franken_numpy.md`](../case-studies/franken_numpy.md) and [`exemplars/SIBLING-PROJECTS-STATUS.md`](SIBLING-PROJECTS-STATUS.md) both lift this; FrankenNumPy's `rg`-based codebase hygiene is the template that [`subagents/hooks-installer.md`](../../subagents/hooks-installer.md) ports back to other siblings.

### [Q-250] — CC.md §99 — FrankenNumPy's structurally-enforced no-stubs invariant

> "**Structurally enforced no-stubs invariant** via `crates/fnp-conformance/tests/codebase_hygiene.rs` (8 `#[test]` functions fail CI on stub markers)."

**Source:** CC.md PART XXIV §99 (line 3508)
**Operational use:** [`assets/integration-test-templates/`](../../assets/integration-test-templates) ships a `codebase_hygiene.rs.template` derived from this; the [`subagents/hooks-installer.md`](../../subagents/hooks-installer.md) installs it into a sibling at Phase 1.

### [Q-251] — CC.md §69 — Reservations carry beads ID

> "**Reservations carry `reason` field** containing the beads ID. A future audit can answer 'who edited this file at this time, why'."

**Source:** CC.md PART XV §69 (line 2577)
**Operational use:** [`patterns/260-AGENT-MAIL-RESERVATIONS.md`](../patterns/260-AGENT-MAIL-RESERVATIONS.md) cites this; [`subagents/iteration-coordinator.md`](../../subagents/iteration-coordinator.md) verifies the `reason` field's bead ID exists in the beads graph before allowing a reservation to land.

### [Q-252] — CC.md §70 — Build-discipline crisis lessons

> "**NEVER `cargo bench` or `cargo test --workspace`** — these take 17+ minutes and hang the build for everyone."

**Source:** CC.md PART XV §70 (line 2585)
**Operational use:** [`patterns/255-RCH-OFFLOAD-DISCIPLINE.md`](../patterns/255-RCH-OFFLOAD-DISCIPLINE.md) and [`methodology/ANTI-PATTERNS.md`](../methodology/ANTI-PATTERNS.md) cite this as the *origin* of the rch-offload mandate.

### [Q-253] — CC.md §70 — Cold CARGO_TARGET_DIR per agent

> "**Cold `CARGO_TARGET_DIR=/data/tmp/<unique>-target`** to avoid cross-agent contention on the shared target directory."

**Source:** CC.md PART XV §70 (line 2587)
**Operational use:** [`assets/hooks/`](../../assets/hooks) PreToolUse template prepends `CARGO_TARGET_DIR` per agent; [`subagents/hooks-installer.md`](../../subagents/hooks-installer.md) wires this in by default for swarm-mode workspaces.

### [Q-254] — CC.md §71 — Other agents' edits are normal

> "those are changes created by the potentially dozen of other agents working on the project at the same time. ... you NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents."

**Source:** CC.md PART XV §71 (lines 2599–2602)
**Operational use:** [`methodology/ANTI-PATTERNS.md`](../methodology/ANTI-PATTERNS.md) lifts this verbatim; [`assets/agents-md-mandate-paragraph.md`](../../assets/agents-md-mandate-paragraph.md) includes a one-paragraph derivative for the target port's own AGENTS.md.

### [Q-255] — CC.md §73 — NTM is degraded; trust tmux

> "`ntm snapshot` reports session state, though the same session notes that NTM occasionally reports zero sessions when tmux clearly has many — *trust tmux*, NTM is degraded source."

**Source:** CC.md PART XV §73 (line 2623)
**Operational use:** [`subagents/ntm-orchestrator.md`](../../subagents/ntm-orchestrator.md) prompt includes a tmux-fallback verification step before reporting "no sessions"; the gauntlet's NTM pipelines under [`assets/ntm-pipelines/`](../../assets/ntm-pipelines) all carry a `verify-with-tmux` flag.

### [Q-256] — CC.md §82 — Spec edits are commits

> "**Spec edits are commits.** 'spec: tighten §6.3 SSI pivot rule' is a normal commit message. Spec changes ratchet with code changes."

**Source:** CC.md PART XIX §82 (lines 2832)
**Operational use:** [`methodology/SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md) cites this as the rule for greenfield ports; the [`cookbook/six-month-soak-revival.md`](../cookbook/six-month-soak-revival.md) recipe (in this same set) flags spec-drift recovery as a Phase 0 audit item.

### [Q-257] — CC.md §82 — Spec is in the repo

> "**The spec is in the repo.** Not a wiki, not a Notion page. A markdown file in the same git history as the code."

**Source:** CC.md PART XIX §82 (line 2830)
**Operational use:** [`methodology/IDENTITY-AND-REPRODUCIBILITY.md`](../methodology/IDENTITY-AND-REPRODUCIBILITY.md) cites this as the only acceptable substrate for the source-of-truth artifact in any sibling.

### [Q-258] — CODEX.md §16.5 — Feature coverage as release debt

> "Feature Coverage Dashboard Turns Missing Tests Into Release Debt"

**Source:** CODEX.md §16.5 header (line 2041)
**Operational use:** [`patterns/105-FEATURE-UNIVERSE.md`](../patterns/105-FEATURE-UNIVERSE.md) anchors the "release debt" framing here; [`subagents/feature-universe-builder.md`](../../subagents/feature-universe-builder.md) emits a release-debt report keyed on this concept.

### [Q-259] — CODEX.md §16.6 — Verification contract stops weak-evidence closes

> "Verification Contract Enforcement Stops Beads From Closing With Weak Evidence"

**Source:** CODEX.md §16.6 header (line 2073)
**Operational use:** [`patterns/120-VERIFICATION-CONTRACT.md`](../patterns/120-VERIFICATION-CONTRACT.md) and [`assets/github-workflows/bead-graph-validator.yml`](../../assets/github-workflows/bead-graph-validator.yml) both cite this verbatim.

### [Q-260] — CODEX.md §16.8 — Failure bundle ergonomics

> "Failure Bundles Are an Ergonomics Contract for Red Runs"

**Source:** CODEX.md §16.8 header (line 2133)
**Operational use:** [`patterns/90-FAILURE-BUNDLE.md`](../patterns/90-FAILURE-BUNDLE.md) lifts this; the [`subagents/replay-runner.md`](../../subagents/replay-runner.md) Phase 7 deliverable is the bundle the maintainer consumes when red runs land.

### [Q-261] — CODEX.md §16.10 — Release certificate as signed claim boundary

> "Release Certificates Turn Evidence Into a Signed Claim Boundary"

**Source:** CODEX.md §16.10 header (line 2208)
**Operational use:** [`assets/release-certification-template.md`](../../assets/release-certification-template.md) cites this; [`subagents/certification-bundler.md`](../../subagents/certification-bundler.md) is the producer.

### [Q-262] — CODEX.md §16.13 — Performance claims are cell-level

> "Performance Claims Are Cell-Level, Not Aggregate-Level"

**Source:** CODEX.md §16.13 header (line 2291)
**Operational use:** [`methodology/RUBRICS.md`](../methodology/RUBRICS.md) and [`cookbook/perf-regression-triage.md`](../cookbook/perf-regression-triage.md) both anchor cell-level reporting here; aggregate-only claims fail rubric 4.

### [Q-263] — CODEX.md §16.16 — Inline-critical vs offloaded is a safety boundary

> "Inline-Critical Versus Offloaded Work Is a Safety Boundary"

**Source:** CODEX.md §16.16 header (line 2363)
**Operational use:** Cited in [`patterns/255-RCH-OFFLOAD-DISCIPLINE.md`](../patterns/255-RCH-OFFLOAD-DISCIPLINE.md) and [`cookbook/asupersync-cancel-leak.md`](../cookbook/asupersync-cancel-leak.md) (in this same set).

### [Q-264] — CODEX.md §16.27 — Reusable assurance kit list

> "The portfolio table points to a reusable kit that should be extracted as templates or shared crates/scripts rather than rediscovered per project."

**Source:** CODEX.md §16.27 preface (lines 2726–2728)
**Operational use:** [`assets/`](../../assets) directory of this skill *is* the kit; every template named in §16.27 has a corresponding file under `assets/`.

### [Q-265] — CODEX.md §16.28 — CASS archaeology = operational not aspirational

> "The most important thing CASS added on this pass was not another benchmark number. It recovered the working instructions that produced the evidence."

**Source:** CODEX.md §16.28 (lines 2803–2805)
**Operational use:** [`methodology/CASS-MINING.md`](../methodology/CASS-MINING.md) cites this when explaining why cass mining is *evidence*, not just navigation; [`subagents/cass-miner.md`](../../subagents/cass-miner.md) returns extracted prompts, not just URLs.

---

## Adding new entries

This file follows the same conventions as [QUOTE-BANK.md](QUOTE-BANK.md). When mining more quotes:

1. Pick the next free `[Q-NNN]` slot. Reserve `Q-266..Q-300` for §S expansion, `Q-301+` for a future thematic section.
2. Cite verbatim text in a blockquote.
3. Add `**Source:**` line with CC.md or CODEX.md section + line range.
4. Add `**Operational use:**` line that names ≥1 skill file the quote anchors a rule in.
5. Cross-link from the anchoring rule's "Why" section back to the new `[Q-NNN]`.

Tag conventions match [QUOTE-BANK.md](QUOTE-BANK.md); when a quote anchors a K-axiom, prefix with the K-N tag.
