# Pattern 00 — KERNEL AXIOMS (K-1..K-12)

## What

The 12 universal axioms every pattern, gate, ledger entry, and operator in the gauntlet presupposes. If a downstream pattern contradicts one of these axioms, the axiom wins. Numbered K-1..K-12 with step-of-1 so the chain is grep-able (`grep -r "K-7" references/`). Full axiom text, operational glosses, and chain rules: [../methodology/KERNEL.md](../methodology/KERNEL.md).

## Why

A pattern library without a kernel is a folder of opinions. The 12 axioms compress every other reference file into one decision rule per gate: *"By K-N, this gate is invalid because …"* without the kernel, the agent re-derives the same correctness argument hundreds of times and gets it wrong somewhere.

> "If a phase, operator, gate, or ledger entry contradicts one of these axioms, the axiom wins." — [methodology/KERNEL.md](../methodology/KERNEL.md) header

## Where in FrankenSQLite

Mined from the entire `MINING-2-conformance-machinery.md` Summary table plus selected verbatim quotes anchored per axiom in [../methodology/KERNEL.md](../methodology/KERNEL.md). The 8-pillar Subject/Oracle/Comparator table at the bottom of MINING-2 is the spine of K-1; the rest are perimeter rules.

## Verbatim shape — the 12 axioms

| ID | Axiom (one-line) | Verbatim quote anchor | Operational gloss |
|---|---|---|---|
| **K-1** | Subject vs Oracle vs Comparator IS the engine | MINING-2 §Summary "Subject/Oracle/Comparator Across 8 Quality Concerns" | Every gate decomposes into a Subject (what we test), an Oracle (what we compare against), and a Comparator (how we decide equal). If you can't name all three, it's not a gate. |
| **K-2** | Honesty is encoded in the harness, not in the reviewer | MINING-2 §12 "An agent honest enough to write the gate is biased toward making it pass." | The reviewer cannot read 6,040 LOC of bench code on every PR. Discipline = files committed to git (`.bench-history/`, `concurrent_mode_default_guard.txt`, `truncate_score` callsite). |
| **K-3** | Negative evidence is a first-class output | CC.md lines 479–482 (MINING-1 §3) "This ledger records performance ideas that were measured and rejected." | Three durable ledgers (`perf-negative-results.md`, `conformance-negative-results.md`, `surface-deferrals.md`) committed to git; every entry carries a retry-condition predicate. |
| **K-4** | Both gates must move in the same run window | MINING-1 §1 "Both gates must move in the same run window. Same run = same git state, same `target/`, same machine, same minute." | Focused bench + broad bench JSON committed from the same compile, same host, same wall-clock minute. Pass-over-pass gate is a file precisely so "I forgot to commit" cannot happen. |
| **K-5** | `truncate_score` to 6 decimal places — cross-platform determinism | MINING-2 §11 "x86 vs ARM vs WASM differ at LSB; truncation ensures bytewise identical scores regardless of CPU." | Every release-boundary score `truncate_score`'d. Ratchet diff = bytewise across machines. Without it, Mac and Linux disagree at LSB and the ratchet flickers. |
| **K-6** | Anytime-valid sequential testing | MINING-2 §10 "Anytime-valid: check after every operation, reject when crosses `1/α`, **no Bonferroni correction needed**." | Three composed layers: Beta posterior per category × pass rate; distribution-free conformal band; e-process with Ville's inequality. Release uses LOWER bound. |
| **K-7** | Deterministic rendering = canonical comparison | MINING-2 §1 "String rendering uniform: `Vec<Vec<String>>` with NULL capitalized, integers base-10, floats via `Display`, text in single quotes, blob as `X'<hex>'`." | `normalize_value` capitalizes NULL, formats floats as `{f:.15}`, normalizes NaN/Inf/-Inf. Per-class: `render_resp_value`, `render_tensor_spec`. |
| **K-8** | Both-error = agreement; one-error-one-OK = hard failure | MINING-2 §1 "Both-error = agreement (message text irrelevant). One-error-one-OK = hard failure." | A divergence is a *behavior* divergence, not a *message* divergence. Forbids "agreement-by-error-message" anti-pattern. |
| **K-9** | Engine-Identity discriminator — never compare an oracle against itself | MINING-2 §3 `SUBJECT_IDENTITY_LABEL: &str = "frankensqlite"; REFERENCE_IDENTITY_LABEL: &str = "csqlite-oracle";` | Every artifact carries `Subject::<port>` and `Oracle::<reference>` strings; comparator asserts distinct. Preflight doctor verifies before any test runs. |
| **K-10** | `BEAD_ID` + `SCHEMA_VERSION` in every module + every artifact | MINING-2 §16 `LOG_SCHEMA_VERSION: &str = "1.0.0"; REQUIRED_EVENT_FIELDS: &[&str] = &["run_id","timestamp","phase","event_type"]` | Every harness module declares the bead it serves (`bd-1dp9.1.2`, `bd-3go.3`) and the schema version of its emitted artifact. Schema change ⇒ version bump. |
| **K-11** | Content-addressed artifact identity — `run_id` is provenance, not identity | MINING-2 §2 "Invariant: `artifact_id = SHA-256 of canonical JSON excluding run_id`. Two runs with identical semantic inputs produce the same artifact ID even with different `run_id`." | What was the test? = artifact id. When/where did we run it? = run id. Distinct runs that test the same thing produce the same artifact id. |
| **K-12** | Convergence is a CI gate, not an editorial verdict | SKILL.md § Convergence Rule "≥10 full iterations of Phases 5→10. Two consecutive clean rounds each producing <3 *new genuine* findings ... Every open hypothesis resolved." | Convergence is computed mechanically: round-over-round new-finding counts, deduplicated by MismatchSignature, exit-non-zero from `convergence-tracker.sh` until all three conditions hold. |

## Per-class instantiation

The 12 axioms are project-class-invariant. What changes per class is the *instantiation* of K-1's Subject/Oracle/Comparator triple — see [pattern:05-SUBJECT-ORACLE-COMPARATOR](05-SUBJECT-ORACLE-COMPARATOR.md). Every other axiom holds verbatim: K-5's `truncate_score` is the same six-decimal-place truncation whether the score is a SQL parity ratio, a Redis RESP roundtrip ratio, or a tensor ULP-distance ratio.

## Composition (compositional invariants from KERNEL.md)

- **K-1 + K-9** ⇒ A comparator that cannot name distinct Subject and Oracle identity strings is invalid. Composed in [pattern:05-SUBJECT-ORACLE-COMPARATOR](05-SUBJECT-ORACLE-COMPARATOR.md) and [pattern:15-ENGINE-IDENTITY](15-ENGINE-IDENTITY.md).
- **K-2 + K-4** ⇒ The pass-over-pass gate must be a committed file checked by CI, not a manual rerun. Composed in [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) and [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md).
- **K-3 + K-12** ⇒ Convergence cannot be declared while open hypotheses or unretired ledger entries exist. Composed in [pattern:180-NEGATIVE-LEDGER](180-NEGATIVE-LEDGER.md) and [pattern:185-RETRY-CONDITION-PREDICATE](185-RETRY-CONDITION-PREDICATE.md).
- **K-5 + K-6 + K-11** ⇒ Cross-machine ratchet diff = `truncate_score(conformal_lower_bound(...))` over canonical-JSON-hashed artifacts. Composed in [pattern:75-BAYESIAN-CONFORMAL-SCORE](75-BAYESIAN-CONFORMAL-SCORE.md) and [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md).
- **K-7 + K-8** ⇒ The 30-line `scenario()` template is the floor; canonical rendering + both-error-agreement is the API. Composed in [pattern:35-NORMALIZED-VALUE](35-NORMALIZED-VALUE.md).
- **K-10 + K-11** ⇒ Every artifact is content-addressable AND version-stamped; a future agent can replay exactly. Composed in [pattern:100-E2E-LOG-SCHEMA](100-E2E-LOG-SCHEMA.md) and [pattern:195-RUN-IDENTITY-STACK](195-RUN-IDENTITY-STACK.md).

When two axioms conflict in a specific case, defer to K-2 (honesty in the harness) and design a new gate.

## Pitfalls

- **"We follow the axioms in spirit."** No. The axioms reference specific files (`.bench-history/<bench>.latest.json`, `concurrent_mode_default_guard.txt`, `<reference>_version_contract.toml`). Spirit is not a file. If the file isn't on disk and committed, the axiom is unsatisfied.
- **Citing K-N without quoting the source.** The verbatim quote is what protects against drift. A bead that says "by K-4" without the source line is a bead that will lose the argument three months from now when an agent disputes the rule.
- **Adding a K-13 yourself.** The kernel is closed. New rules go into [methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md) or a new pattern file, with traceback to one of K-1..K-12. The kernel only expands on a deliberate revision (see KERNEL.md version marker `<!-- KERNEL_START v1.0 -->`).
- **Treating K-12 as advisory.** `scripts/convergence-tracker.sh` exits non-zero until convergence is reached. CI fails. Agents who say "I think we're converged" without the script's blessing are wrong by K-2.
- **Skipping K-9 because "obviously the oracle is different".** The oracle preflight doctor catches the embarrassing case where a refactor silently rewired both sides to the same executor. The string assertion takes 4 lines; skip it once and you'll spend a week chasing a 100%-pass-rate that means nothing.
