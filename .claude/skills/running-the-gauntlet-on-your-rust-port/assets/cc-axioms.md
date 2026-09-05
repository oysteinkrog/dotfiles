# CC Axioms (Paste-Ready)

The 12 K-N kernel axioms in compressed form, suitable for pasting into a project's AGENTS.md or the top of a contributor onboarding doc. Full text + verbatim source quotes in `references/methodology/KERNEL.md`.

<!-- CC_AXIOMS_START v1.0 -->

**K-1. Subject vs Oracle vs Comparator IS the engine.**
Every artifact decomposes into Subject, Oracle, and Comparator. If you can't name all three on demand, the gate is not a gate.

**K-2. Honesty is encoded in the harness, not in the reviewer.**
The committed gate file, the dropped proof file, the canonicalized score function — the discipline lives in code, not in PR-review attention.

**K-3. Negative evidence is a first-class output.**
A rejected optimization is not a non-event. The three ledgers (`PERF_NEGATIVE_RESULTS.md`, `CONFORMANCE_NEGATIVE_RESULTS.md`, `SURFACE_DEFERRALS.md`) are mandatorily grepped before every campaign.

**K-4. Both gates must move in the same run window.**
Focused gate + broad gate, same git state, same `target/`, same machine, same minute. Cherry-picking across runs is a rejection.

**K-5. `truncate_score` to 6 decimal places — cross-platform determinism.**
x86 / ARM / WASM differ at the LSB. Truncate every cross-boundary score so ratchet diffs are bytewise reproducible.

**K-6. Anytime-valid sequential testing (Bayesian + Conformal + E-process).**
Beta posterior per category × pass rate; distribution-free conformal lower bound for release decisions; e-process Ville-bounded rejection without Bonferroni correction.

**K-7. Deterministic rendering = canonical comparison.**
Two engines "agreeing" requires a comparator whose output is bytewise identical for semantically equal inputs. `Vec<Vec<String>>` with NULL capitalized, floats `{:.15}`, etc.

**K-8. Both-error = agreement; one-error-one-OK = hard failure.**
A divergence is a behavior divergence, not a message divergence. If both engines reject, the test passes regardless of which error string was emitted.

**K-9. Engine-Identity discriminator — never compare an oracle against itself.**
Every artifact carries `Subject::<port>` and `Oracle::<reference>`. The comparator asserts distinct. Self-comparison is the most insidious 100%-pass failure mode.

**K-10. BEAD_ID + SCHEMA_VERSION in every module + every artifact.**
Every harness module names the bead it serves and the schema version of its output. When the schema changes, the version bumps; downstream readers either upgrade or fail loudly.

**K-11. Content-addressed artifact identity — `run_id` is provenance, not identity.**
`artifact_id = SHA-256 of canonical JSON excluding run_id`. Two runs with the same semantic inputs produce the same artifact ID even with different timestamps / PIDs.

**K-12. Convergence is a CI gate, not an editorial verdict.**
`scripts/convergence-tracker.sh` declares convergence mechanically: ≥10 rounds, 2 consecutive clean rounds, every open hypothesis resolved. An agent does not "feel" converged.

<!-- CC_AXIOMS_END v1.0 -->

---

When conflicts arise between axioms in edge cases, defer to **K-2** (honesty in the harness) and design a new gate. See `references/methodology/KERNEL.md` § Compositional Invariants for how the axioms chain.
