# SOURCE-CORPUS — Track A from `/operationalizing-expertise` Applied to This Skill

This skill applies the [operationalizing-expertise](../../../operationalizing-expertise/SKILL.md) Track A workflow:
**corpus → quote bank → triangulated kernel → operator library → validators.**

The deliverables for Track A already exist within this skill — this file documents WHERE they live, WHY the architecture matters, and HOW to extend the corpus when the methodology evolves.

---

## Why this matters

The FrankenSQLite bibles at `/data/projects/frankensqlite/COMPREHENSIVE_BREAKDOWN_OF_FRANKENSQLITE_PERFORMANCE_AND_CONFORMANCE_ASSURANCE_PROCESS__CC.md` (~5,065 lines, 32 `# PART` headings) + `..._CODEX.md` (~3,798 lines, 19 numbered sections) are ~8,800 lines drawn from:

- ~380 negative-ledger entries.
- ~5 months of FrankenSQLite session history (cass).
- 18 harness modules in `crates/fsqlite-harness/src/`.
- 6,040-line `comprehensive_bench.rs`.
- The full §75-76 mathematical toolkit (32 results from Ville 1939 through Mauboussin 2012).
- 11+ sibling-project adoption tables.
- 10 winning optimization patterns with verbatim proof numbers.
- 8 retry-condition predicate forms.
- 12 anti-patterns from the negative ledger + 5 anti-patterns from `/extreme-software-optimization` + 3 from `/testing-metamorphic`.

That's a lot of evidence. Without an operationalized structure, this skill becomes "vibes referring vaguely to a bible."

The Track A discipline turns it into:

- **Corpus** — the primary sources, addressable by section.
- **Quote bank** — stable anchors with tags for fast retrieval.
- **Triangulated kernel** — the consensus invariants (the 12 K-N axioms in `KERNEL.md`).
- **Operator library** — composable cognitive moves (the 19 glyphs in `OPERATORS.md`).
- **Validators** — executable checks (the scripts in `scripts/`).

---

## Mapping this skill to Track A deliverables

| Track A deliverable | Where it lives in this skill |
|---|---|
| `corpus/primary_sources/` | The two FrankenSQLite bibles (CC.md + CODEX.md) + the three mining extracts at `/data/tmp/gauntlet-skill-mining/MINING-1-vocab-operators.md`, `MINING-2-conformance-machinery.md`, `MINING-3-perf-surface-machinery.md`. |
| `corpus/quote_bank/quote_bank.md` | [exemplars/EXEMPLARS.md § Quote bank](../exemplars/EXEMPLARS.md) — verbatim quotes lifted from FrankenSQLite session history and the bibles, with stable anchor IDs. |
| `corpus/specs/triangulated_kernel.md` | [methodology/KERNEL.md](KERNEL.md) — the 12 K-N axioms (K-1 through K-12), marker-bounded as `<!-- KERNEL_START v1.0 --> ... <!-- KERNEL_END v1.0 -->` for deterministic extraction. |
| `corpus/specs/operator_library.md` | [methodology/OPERATORS.md](OPERATORS.md) — the 19 glyphs (★ ✦ ◐ ⬡ ⚠ ⊕ ⊙ ⊞ ⌘ ⟁ ⤴ 🔁 ⚖ 🪟 🗄 🧪 📐 🎚 🪞) with triggers + failure modes + prompt modules + quote-bank anchors. |
| `corpus/specs/session_kickoff*.md` | [methodology/KICKOFF-PROMPTS.md](KICKOFF-PROMPTS.md) (per-mode kickoff prompts) + [AGENT-PROMPTS.md](../AGENT-PROMPTS.md) (per-subagent prompts). |
| `scripts/validate-corpus.py` | `scripts/check-skills.sh` (verifies every referenced helper skill has either a fallback or is jsm-installable) + `scripts/extract-from-bibles.sh` (verifies the routed bible excerpt headers still exist and extract non-empty content). |
| `scripts/validate-operators.py` | (TODO: a polish-bar checker that asserts every glyph in OPERATORS.md has trigger + failure-mode + prompt-module + quote-bank-anchor + composes-with sections). |
| `scripts/validate-kernel.py` | Planned validator; today the marker-bounded block is checked by reading `KERNEL.md` directly plus `scripts/check-cross-links.py`. |

---

## Corpus

### Primary sources

- **FrankenSQLite bibles** — `/data/projects/frankensqlite/COMPREHENSIVE_BREAKDOWN_OF_FRANKENSQLITE_PERFORMANCE_AND_CONFORMANCE_ASSURANCE_PROCESS__CC.md` (the comprehensive primary; 32 current `# PART` headings) and `..._CODEX.md` (the secondary cross-check; 19 numbered sections).

- **Mining extracts** — three intermediate documents derived from the bibles, addressable by skill code:
  - [MINING-1-vocab-operators.md](/data/tmp/gauntlet-skill-mining/MINING-1-vocab-operators.md) — keep-gate vocabulary, retry-condition predicates, 10 winning optimization patterns, mathematical-toolkit catalog (32 entries), sibling-project adoption status, anti-patterns catalog.
  - [MINING-2-conformance-machinery.md](/data/tmp/gauntlet-skill-mining/MINING-2-conformance-machinery.md) — 30-line scenario template, Differential V2 envelope, EngineIdentity discriminator, metamorphic machinery, mismatch minimizer, three-tier equivalence, replay harness with BOCPD, fault VFS + crash-boundary protocol, e-processes, Bayesian + conformal score engine, adversarial search, oracle preflight doctor, fixture root contract, failure bundle, e2e log schema, first-failure explainer, oracle-parity surface, subject/oracle/comparator summary table.
  - [MINING-3-perf-surface-machinery.md](/data/tmp/gauntlet-skill-mining/MINING-3-perf-surface-machinery.md) — `comprehensive_bench.rs` skeleton + 6 timing constants + `measure_with_teardown` + 6 weighted categories + `release-perf` profile + JSON v3 report + `concurrent_mode_default_guard.txt`, focused narrow benches, MT8 attribution discipline, pass-over-pass gate, profile-first contract + 19-field proof-pack card, HotPathProfileSnapshot per-domain counter table, algebraically-redundant counter elimination, proof-pack baseline structure, robust regression detection (median + MAD), 10 winning patterns cross-ref, FeatureUniverse + invariant catalog, closure-wave pattern, verification-contract enforcement, run identity stack, universal floor + bootstrapping order.

- **Adjacent skills** — the gauntlet draws style and structure from [/saas-billing-patterns-for-stripe-and-paypal](../../../saas-billing-patterns-for-stripe-and-paypal/SKILL.md) (the per-mode KICKOFF-PROMPTS / VERIFICATION-FIRST / SKILL-FALLBACKS / HOOKS-INTEGRATION format) and from public skill-writing conventions (the SKILL.md frontmatter contract).

### Corpus integrity rules

- **Evidence-first.** Every rule in this skill's references/ cites a primary-source section (e.g., "CC.md §37" or "MINING-1 §1"). Adding a rule without a source citation is a contract violation.
- **Deterministic extraction.** The kernel block in KERNEL.md is bounded by `<!-- KERNEL_START v1.0 -->` / `<!-- KERNEL_END v1.0 -->` so a script can extract it without parsing the rest of the file.
- **Triangulation.** The kernel is **consensus-only** (12 axioms). Disputed points (e.g., "is closure-wave applicable to Numerical-Python class?") live in the pattern bundles' "Common mistakes" / "Patterns rejected" sections, NOT in the kernel.
- **Operator cards must include trigger + failure-mode + prompt-module + quote-bank-anchor + composes-with.** All 19 operators in OPERATORS.md follow this contract.
- **Validation gates required.** The [Polish Bar](../../SKILL.md#the-polish-bar-non-negotiable) is the gate; the keep-gate rules in [KEEP-GATE-RULES.md](KEEP-GATE-RULES.md) are the audit.
- **Provenance auditable.** Every pattern doc cites primary-source sections; bead IDs traceable via the FrankenSQLite session history.
- **Join-key contract.** Workspace artifacts use the same `<bundle>` id ([Phase N artifact paths from PHASES.md](../PHASES.md)) across phase artifacts; bead IDs link tasks to fixes to tests to runbooks.

---

## Quote Bank

The full quote bank lives in [exemplars/EXEMPLARS.md § Quote bank](../exemplars/EXEMPLARS.md). The format:

```
[QUOTE_ID] (§N) tags: [tag1, tag2] — quote text — anchor: <description>
```

Example entries (selected; full set in EXEMPLARS.md):

```
[Q-001] (CC.md §37) tags: [keep-gate, scratch-worktree]
"keep gate" — The numeric threshold an optimization must clear to be merged. Singular "the keep gate" usually means the comprehensive-bench primary score. Specific gates are *named*: "focused DML keep gate", "10K DELETE keep gate", "MT8 keep gate".
anchor: keep-gate-canonical-definition

[Q-002] (CC.md §37) tags: [within-noise, noise-band, cv_pct]
"within noise" — Improvement is ≤ the workload's cv_pct band (typically ±3-5%). Not a win — *technically also not a loss*, but not durable evidence.
anchor: within-noise-definition

[Q-007] (CC.md §37) tags: [scratch-worktree, ledger-discipline]
"scratch worktree" — A directory under `/data/tmp/frankensqlite-<feature>-<timestamp>` where the rejected candidate's code lives so it can be inspected later without polluting main. The path itself goes into the ledger entry.
anchor: scratch-worktree-pattern

[Q-010] (CC.md §37) tags: [behavior-preserving, oracle-tests]
"behavior-preserving" — The candidate doesn't change observable behavior (verified by oracle tests, selection counts, bench-level row equality). Required prerequisite for any rejection-by-perf — a behavior-changing candidate is a different question entirely.
anchor: behavior-preserving-prerequisite

[Q-015] (CC.md §37) tags: [MT8, attribution, profiling-anchor]
"MT8" / "MT 8t" — Multi-thread 8-thread benchmark — the canonical concurrency-stress workload. Used as a profiling anchor: "MT8 attribution" means the profiler ran under MT8 load, which exercises the MVCC plane realistically.
anchor: MT8-canonical-anchor

[Q-019] (MINING-1 §1) tags: [both-gates, same-run-window]
"both gates must move in the same run window" — The non-negotiable rule for keeping a perf change. Same run = same git state, same `target/`, same machine, same minute.
anchor: both-gates-same-window

[Q-031] (MINING-2 §1) tags: [oracle-comparator, both-error-agreement]
"Both-error = agreement (message text irrelevant). One-error-one-OK = hard failure."
anchor: both-error-agreement-rule

[Q-040] (MINING-3 §3) tags: [MT8-attribution, 0.1-percent-rule]
"Each frame ≥0.1% is a *candidate*. A frame at 0.05% is below the noise floor of the bench (cv_pct 3-5%); the micro-lever trap. A frame at 1% is rare and high-value. The 0.1-1% range is where productive optimization work happens."
anchor: micro-lever-trap

[Q-050] (MINING-2 §10) tags: [e-process, Ville, anytime-valid]
"Anytime-valid: check after every operation, reject when crosses 1/α, no Bonferroni correction needed."
anchor: ville-anytime-valid

[Q-067] (CC.md §63) tags: [MT8-citations, attribution-format]
"Closed 0.44% MT8 PublishedPages::clear residual" / "Closed 0.63% MT8 inclusive self-time" / "Closed 0.51% MT8 self-time symbol".
anchor: MT8-attribution-citation-format
```

Use these in:
- Bug reports (`> [Q-031]: "Both-error = agreement..."` is more authoritative than paraphrasing).
- Phase 14 fresh-eyes findings ("violates [Q-040] — frame at 0.07% is the micro-lever trap").
- Onboarding docs for new agents starting in the gauntlet.
- Ledger entries (cite the quote anchor in the rationale).

---

## Triangulated Kernel (marker-bounded)

The kernel lives in [methodology/KERNEL.md](KERNEL.md) between markers:

```
<!-- KERNEL_START v1.0 -->
[the 12 K-N axioms, paragraph form with quote anchors]
<!-- KERNEL_END v1.0 -->
```

The block is deliberately marker-bounded so agents can extract it with `sed`/`awk` when needed; no shipped `extract-kernel.sh` exists in this skill package.

The 12 axioms (compressed; full forms in KERNEL.md):

- **K-1**: Subject vs Oracle vs Comparator IS the engine.
- **K-2**: Honesty is encoded in the harness, not in the reviewer.
- **K-3**: Negative evidence is a first-class output.
- **K-4**: Both gates must move in the same run window.
- **K-5**: `truncate_score` to 6 decimal places — cross-platform determinism.
- **K-6**: Anytime-valid sequential testing (Bayesian + Conformal + E-process).
- **K-7**: Deterministic rendering = canonical comparison.
- **K-8**: Both-error = agreement; one-error-one-OK = hard failure.
- **K-9**: Engine-Identity discriminator — never compare an oracle against itself.
- **K-10**: BEAD_ID + SCHEMA_VERSION in every module + every artifact.
- **K-11**: Content-addressed artifact identity — `run_id` is provenance, not identity.
- **K-12**: Convergence is a CI gate, not an editorial verdict.

The kernel is **consensus-only**. Disputed points (e.g., "should rust-port testing require shuttle by default?") live in [taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md) per-class or [tooling/CONCURRENCY-TOOLCHAIN.md](../tooling/CONCURRENCY-TOOLCHAIN.md) as design choices, NOT in the kernel.

---

## Operator Library

The 19 glyphs live in [methodology/OPERATORS.md](OPERATORS.md). Each card:

```
## <glyph> <Name>

**Question:** "<one-line question>"

**Triggers:** <list>

**Failure modes:** <list>

**Prompt module:** <verbatim prompt agent emits>

**Quote-bank anchor:** <[Q-NNN] reference + verbatim quote>

**Composes with:** <other glyphs>
```

The 19 glyphs (compressed; full cards in OPERATORS.md):

| Glyph | Name | Question |
|---|---|---|
| ★ | Pin-Reference-Version | Does every artifact name the exact reference version? |
| ✦ | Enumerate-Surface | Is every pub/opcode/command accounted for with present/partial/missing/n/a/excluded? |
| ◐ | Wire-Oracle | Is there an in-process/subprocess bridge to the pinned reference with EngineIdentity? |
| ⬡ | Instrument-Hot-Path | Does this hot loop have a counter ≥0.1% self-time? |
| ⚠ | Escalate-To-Fresh-Repro | Does the FailureBundle have seed + schedule + platform fingerprint? |
| ⊕ | Isomorphic-Rewrite | What are 2+ behavior-preserving rewrites for this path? |
| ⊙ | Debounce-False-Positive | Is this TrueDivergence or one of the 5 known classes? |
| ⊞ | Soak | Has this run the soak duration (24h fuzz / multi-day miri / ...)? |
| ⌘ | Reduce / Minimize | Has the failure been delta-debugged to 1-minimal? |
| ⟁ | Triangulate-Profile | Do flamegraph + samply + dhat agree on attribution? |
| ⤴ | Attribute-To-MT8 | Does this kept win name a specific frame ≥0.1% self-time? |
| 🔁 | Pass-Over-Pass-Gate | Have both gates moved in the same run window? |
| ⚖ | Ratchet-Lower-Bound | Does the change raise the conformal LOWER bound? |
| 🪟 | Fresh-Eyes | Have the 3 calibrated prompts run? Two clean rounds? |
| 🗄 | Ledger-Retire | Does the entry name a concrete retry-condition predicate? |
| 🧪 | Experiment-Design | Does the gap have hypothesis-repro-signal-falsifiability? |
| 📐 | Conformal-Band | Does the release decision use distribution-free LOWER bound? |
| 🎚 | Raise-ULP-Tolerance | Has the ULP change been justified + scoped + snapshot'd? |
| 🪞 | Engine-Identity-Guard | Does every artifact have Subject + Oracle asserted-distinct? |

The library is deliberately overlapping — a single perf candidate typically deserves four or five glyphs applied in sequence.

### Extension instructions for adding new operators

When extending the library (e.g., a new project class requires a new cognitive move):

1. **Identify the gap.** A new operator is justified only when an existing glyph's triggers don't fire on the new situation.
2. **Pick a glyph.** Use a Unicode glyph that visually echoes the operation (★ for "pinning", ⬡ for "instrumentation"). Avoid letter-only names.
3. **Write the card** following the template above. Every field is mandatory; "TODO" sections are forbidden.
4. **Cite a quote-bank anchor.** Every operator must ground in a primary-source quote. If no quote exists, the operator is speculative; revisit after the primary source is updated.
5. **Update the composition cheat-sheet** at the end of OPERATORS.md showing how the new glyph composes with existing ones.
6. **Update [SKILL.md § Operator Library](../../SKILL.md)** with the new row in the operator table.

---

## Validators

The validation regime — Track A's "validation gates":

| Validator | Script | What it checks |
|---|---|---|
| Skill coverage | `scripts/check-skills.sh` | Every helper skill referenced in this skill is either installed OR has an inline fallback in [SKILL-FALLBACKS.md](SKILL-FALLBACKS.md). |
| Source coverage | planned validator | Every § of the FrankenSQLite bibles maps to at least one reference file in this skill. Until this ships, use `scripts/extract-from-bibles.sh` for the routed excerpts and a targeted citation audit for touched references. |
| Operator integrity | `scripts/validate-operators.py` (TODO) | Every glyph in OPERATORS.md has trigger + failure-mode + prompt-module + quote-bank-anchor + composes-with sections. |
| Quote bank integrity | `scripts/validate-quote-bank.py` (TODO) | Every quote has stable ID, primary-source anchor, ≥1 tag. |
| Kernel extraction | marker-bounded manual extraction | The marker-bounded kernel block extracts cleanly and contains all 12 K-N entries. |
| Convergence | `scripts/convergence-tracker.sh` | The ≥10 rounds / ≥2 clean / 0 open hypotheses gate is mechanically checked. |
| Bead graph | `scripts/bead-graph-validator.sh` | `br dep cycles` empty + every remediation bead has test+bench+doc deps. |
| Ledger discipline | `scripts/mine-ledger.sh` | Every closed entry has a retry-condition predicate matching one of the 8 forms. |
| Final report | `scripts/final-report-builder.sh` | All 16 phases have output; certification bundle is complete; top-line says CERTIFIED or names blocker. |

Failing any validator blocks the relevant Phase from closing (e.g., failing `bead-graph-validator.sh` blocks Phase 13 close).

### Syn-walkers

`scripts/syn-walkers/` is a Rust Cargo crate (clap-based binary `syn-walkers`) containing source-walker passes for predicates ast-grep can't express. Each walker lives at `src/walkers/<name>.rs`.

**Currently-shipped walkers** (4):

1. `src/walkers/public_api_diff.rs` — compares the subject's `pub fn` / `pub struct` / `pub trait impl` surface against the reference's `__all__` / public-API export list; emits per-symbol present/partial/missing rows.
2. `src/walkers/extern_c_signatures.rs` — verifies every `extern "C"` declaration's calling convention + signature matches the C header counterpart.
3. `src/walkers/no_mangle_symbols.rs` — enumerates `#[no_mangle]` symbols + their `extern "C"`-ness + visibility.
4. `src/walkers/pyfunction_coverage.rs` — for PyO3-bridged classes, verifies every Python-side `__all__` entry has a corresponding `#[pyfunction]` or `#[pymethods]` in the subject.

**Walkers adopters may want to add** (per project class — these are not shipped; they're the kinds of predicates syn-walkers is designed to support):

- An `engine_identity.rs` walker — finds every comparator entry and verifies `assert_ne!(EngineIdentity::Subject, EngineIdentity::Oracle)` (or equivalent) is present.
- A `bead_schema_version.rs` walker — verifies every harness module declares `BEAD_ID` const + emitted artifacts include `LOG_SCHEMA_VERSION`.
- A `truncate_score.rs` walker — verifies every score-emitting function calls `truncate_score(...)` at the boundary.
- A `counter_redundancy.rs` walker — finds counter writes on hot paths that are provably algebraically derivable from existing counters.

Add new walkers by dropping a new `src/walkers/<name>.rs` and registering it in `src/walkers/mod.rs` and the CLI dispatcher in `src/main.rs`.

### ast-grep YAMLs (6 files)

`scripts/ast-grep-surface-patterns/` contains per-project-class surface-detection patterns. Each file holds the rules for one class (`<class>.yml`); `common.yml` holds the cross-class basics that every per-class file `apply:` extends:

1. `common.yml` — cross-class Rust surface (`pub fn`, `pub struct`, `pub trait`, `impl ... for ...`, `#[no_mangle]`, `extern "C"`, `macro_export`).
2. `sql-class.yml` — SQL-class additions: `PRAGMA <name>`, `pragma_<name>!`, `Opcode::<name>`, `enum Opcode { ... }`.
3. `resp-class.yml` — RESP-class additions: `pub const COMMAND_<name>`, `#[command]`, `redis_module!`.
4. `numerical-class.yml` — Numerical-Python-class additions: `#[pyfunction]`, `pub fn <name>(...) -> PyResult`, `__all__` entries.
5. `ml-class.yml` — ML-System-class additions: `#[torch::op]`, `aten::<name>`, autograd-relevant signatures, PyTree comparator markers.
6. `http-class.yml` — HTTP-Protocol-class additions: `pub struct ... HandlerExt`, `#[get/post/put/delete]`, OpenAPI schema export markers.

The orchestrator uses these in Phase 1 RECON to enumerate per-class surface elements deterministically (vs. relying on the agent's grep). Invoke per-class:

```bash
ast-grep scan -r scripts/ast-grep-surface-patterns/common.yml --json <target>/src/
ast-grep scan -r scripts/ast-grep-surface-patterns/sql-class.yml --json <target>/src/
```

---

## How to extend the corpus

When the FrankenSQLite bible is revised, or a new sibling's session history reveals a generalizable pattern, follow this 5-step process:

### Step 1: Add the source quote to the quote bank

In [exemplars/EXEMPLARS.md § Quote bank](../exemplars/EXEMPLARS.md), append:

```
[Q-NNN] (<primary-source §N>) tags: [tag1, tag2]
"<verbatim quote text>"
anchor: <short-anchor-id>
```

The anchor ID is referenced by operators / patterns / ledger entries; once committed, it should not change (downstream agents may grep for it).

### Step 2: Determine the architectural placement

- If the quote teaches a NEW invariant → consider extending the kernel (Step 3).
- If the quote teaches a NEW cognitive move → consider extending the operator library (Step 4).
- If the quote teaches a NEW pattern → consider extending [remediation/REMEDIATION-PATTERNS.md](../remediation/REMEDIATION-PATTERNS.md).
- If the quote teaches a NEW anti-pattern → extend [methodology/ANTI-PATTERNS.md](ANTI-PATTERNS.md).
- If the quote teaches a NEW class-specific instantiation → extend [taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md).

### Step 3: Extend the kernel (rare — requires triangulation)

A new K-N axiom requires:

1. The quote is consensus across 3+ primary-source citations (not just one).
2. The axiom is NOT derivable from existing K-1..K-12.
3. The axiom appears repeatedly in the FrankenSQLite session history (≥10 hits across 60-day window).
4. PR review with multi-model triangulation (per [TRIANGULATION.md](TRIANGULATION.md)): structural finding → full agreement required.

If approved:
- Append to [KERNEL.md](KERNEL.md) between the markers as K-13, K-14, ...
- Update the compositional-invariants section showing how the new axiom chains with existing ones.
- Update [SKILL.md § Operator Library](../../SKILL.md) cross-reference table.
- Bump `KERNEL_START v1.0` → `v1.1`.

### Step 4: Extend the operator library

A new glyph requires:

1. Existing glyphs' triggers don't fire on the new situation (gap evidence).
2. The new glyph composes with ≥2 existing glyphs (not orthogonal).
3. ≥1 quote-bank anchor.

If approved:
- Append a card to [OPERATORS.md](OPERATORS.md) per the template.
- Update the composition cheat-sheet at the end of OPERATORS.md.
- Update [SKILL.md § Operator Library](../../SKILL.md) table.

### Step 5: Update validators

If the new extension introduces a new invariant that should be machine-checked:
- Add a new script to `scripts/`.
- Add the script to the [Polish Bar](../../SKILL.md#the-polish-bar-non-negotiable) checklist.
- Wire into the relevant CI gate (`scripts/final-report-builder.sh` or per-Phase exit-criteria check).

---

## Track A vs Track B vs Track C dispatch

From [/operationalizing-expertise](../../../operationalizing-expertise/SKILL.md):

- **Track A** — Operationalize a single methodology into corpus + quote bank + triangulated kernel + operator library + validators. **This skill is primarily Track A.** The methodology is the FrankenSQLite gauntlet; the corpus is the two bibles; the kernel is K-1..K-12; the operators are the 19 glyphs.

- **Track B** — Cross-methodology synthesis (e.g., synthesizing FrankenSQLite + saas-billing + flywheel into a unified meta-methodology). **Not applicable** to this skill; the gauntlet is single-methodology.

- **Track C** — Mining session history for hidden rituals (the rituals an experienced practitioner does without realizing they're doing them). **This skill has elements of Track C** for the rituals mining — the 60-day cass mining, the verbatim retry-condition predicates, the "fresh-eyes pass" ritual, the "scratch worktree" pattern. These weren't in the FrankenSQLite README; they were extracted from session history and committed to the kernel/operators as evergreen patterns.

The Track A/C blend means:
- The kernel + operators come from explicit methodology documentation (Track A).
- The rituals + vocabulary glossary + retry-condition forms come from session history (Track C).
- Both feed the same validators.

---

## See also

- [exemplars/EXEMPLARS.md](../exemplars/EXEMPLARS.md) — the full quote bank (this file points TO it; don't duplicate).
- [exemplars/FRANKENSQLITE-BIBLE.md](../exemplars/FRANKENSQLITE-BIBLE.md) — section-by-section routing into the two bibles.
- [methodology/KERNEL.md](KERNEL.md) — the 12 axioms.
- [methodology/OPERATORS.md](OPERATORS.md) — the 19 glyphs.
- [methodology/ANTI-PATTERNS.md](ANTI-PATTERNS.md) — the rejected-pattern catalog.
- [/operationalizing-expertise](../../../operationalizing-expertise/SKILL.md) — the upstream Track A workflow this skill applies.
- Public authoring conventions — the contract that gates extensions.
- [/flywheel](../../../flywheel/SKILL.md) — the generative-grammar discipline that informs Phase 10 idea-wizard.
