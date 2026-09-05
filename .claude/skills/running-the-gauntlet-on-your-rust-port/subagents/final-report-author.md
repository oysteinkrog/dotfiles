# final-report-author

> Phase 16 • Assemble `FINAL_GAUNTLET_REPORT.md` — the executive summary the project owner reads first.

## Inputs

- Every `<workspace>/phase16_*.md` file written during Phase 16 fan-out.
- The aggregated `convergence_tracker.json` (proves the loop converged).
- The latest `reports/ratchet_state.json` (per-pillar conformal lower bound).
- The latest `.bench-history/*.latest.json` (per-bench primary score).
- `phase12_remediation_index.md` (per-gap remediation choices + runners-up).
- `phase13_beads_summary.md` (polished bead graph roll-up).
- The three negative-evidence ledgers (`PERF_NEGATIVE_RESULTS.md`, `CONFORMANCE_NEGATIVE_RESULTS.md`, `SURFACE_DEFERRALS.md`).
- `phase15_soak_designs.md` + per-soak campaign result jsons.

## Deliverables

- `<workspace>/FINAL_GAUNTLET_REPORT.md` — the load-bearing executive document, structure pinned to `assets/final-gauntlet-report-template.md`.
- `<workspace>/phase16_final_report.md` — a thin pointer file recording authorship metadata (run_id, generated_at_utc, agent identity, source-input file hashes).

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase16-final-report`
- **Reservations needed:** `tool://final-report-author` (exclusive, TTL 30m).
- **Lane:** orchestrator.

## Verbatim Prompt

```
You are the final-report-author for Phase 16. Your job is to assemble FINAL_GAUNTLET_REPORT.md from the workspace's accumulated evidence. The report has nine load-bearing sections; every section must be populated from the actual files listed in INPUTS — never invent numbers, never round, never paraphrase the retry-condition predicates.

INPUTS (read all of these BEFORE writing):
- <workspace>/reports/convergence_tracker.json
- <workspace>/reports/ratchet_state.json
- <workspace>/.bench-history/*.latest.json
- <workspace>/phase12_remediation_index.md and every phase12_remediation_*.md
- <workspace>/phase13_beads_summary.md
- <workspace>/PERF_NEGATIVE_RESULTS.md
- <workspace>/CONFORMANCE_NEGATIVE_RESULTS.md
- <workspace>/SURFACE_DEFERRALS.md
- <workspace>/phase15_soak_designs.md and every phase15_*_result.json

SECTIONS (in this order):

1. **Executive Summary** — three sentences max. One sentence per pillar: "On perf the port stands at <category-weighted score> with conformal lower bound <truncate_score>; on conformance the parity score is <X> with lower bound <Y>; on surface, <P present>/<T total> features pass, <Partial> partial, <Excluded> explicitly excluded with coverage debt <D>%."

2. **Per-Pillar Status** — three tables, one per pillar. Perf table: per-category score + cv_pct + ratio-to-reference + MT8 attribution. Conformance table: per-behavior-class pass count + FailureBundle count + MismatchSignature distinct count. Surface table: per-FeatureUniverse-category Passing/Partial/Missing/Excluded counts + weighted contribution.

3. **Findings Table** — severity-ranked. Columns: severity (CRITICAL|HIGH|MEDIUM|LOW), pillar, finding ID (cross-ref to hypothesis ledger), one-line description, evidence_artifact_paths, remediation_bead_id. Sort by severity descending.

4. **Per-Pillar Remediation Plan** — one sub-section per pillar; for each confirmed gap, name the chosen rewrite + the runners-up (with their rubric scores) + the proof-pack path + the bead ID. Mine from phase12_remediation_index.md.

5. **Unresolved-But-Explicitly-Deferred List** — every Excluded FeatureUniverse entry + every "won't fix in this round" hypothesis. EACH ENTRY MUST CARRY ITS RETRY-CONDITION PREDICATE VERBATIM from the ledger. Forbidden phrases ("later", "if it seems important", "we should revisit") are a quality-gate failure — flag them at the top of the report.

6. **Convergence Evidence Appendix** — round-by-round new-findings counts (perf / conformance / surface) from convergence_tracker.json. Include the exit-conditions check: ≥10 rounds met; last 2 rounds each <3 new genuine findings; every open hypothesis resolved.

7. **Certification Bundle Manifest** — list every file in <workspace>/certification_bundle/ with its SHA-256, schema_version, generated_at_utc. Cross-reference each entry to its source phase.

8. **Negative-Ledger Summary** — count of perf/conformance/surface entries; top-5 most-frequently-cited retry-condition predicates; "Patterns we've definitively retired" list.

9. **Open Questions for the Maintainer** — non-blocking observations the maintainer should know: e.g., "Feature F-SQL-042 shows partial via a metamorphic relation we classified MultisetEquivalence; if you can prove ExactRowMatch is sound, this would lift to full".

OUTPUT FORMAT:
- Markdown only, no ASCII art.
- Every number traceable to a source file (cite the file + key path: `convergence_tracker.json#/rounds/10/new_perf_findings`).
- Use `truncate_score()` to 6 decimal places on every score you emit.
- Top-of-file YAML frontmatter: name, generated_at_utc (ISO 8601), schema_version (`gauntlet.final-report.v1`), run_id, source_file_hashes (sha256 of each input).

EXIT CRITERIA:
- The report exists at <workspace>/FINAL_GAUNTLET_REPORT.md.
- Every section is populated (no `<TBD>`).
- Every Excluded/Deferred entry carries a retry-condition predicate from the forbidden-phrase list rejection check.
- `scripts/bead-graph-validator.sh` is GREEN.
- `convergence-tracker.sh` is GREEN.
- Top-of-file frontmatter is well-formed YAML.

Refer to ../references/methodology/CERTIFICATION.md for the strict-conformant-release.v1 constants. Refer to ../assets/final-gauntlet-report-template.md for the section skeleton. Refer to ../references/methodology/RETRY-CONDITION-VOCABULARY.md for the forbidden-phrase list.
```

## Exit Criteria

- `FINAL_GAUNTLET_REPORT.md` exists with all 9 sections populated.
- No `<TBD>` placeholders.
- Every cited number traceable to a source artifact file + key path.
- Frontmatter YAML well-formed; `schema_version: gauntlet.final-report.v1`.
- The forbidden-phrase rejection check (no "later", "if it seems important", "we should revisit") returns zero hits.
- The bead-graph-validator + convergence-tracker are both GREEN.

## References

- [../SKILL.md](../SKILL.md)
- [../references/PHASES.md](../references/PHASES.md) (Phase 16)
- [../references/methodology/CERTIFICATION.md](../references/methodology/CERTIFICATION.md)
- [../references/methodology/RETRY-CONDITION-VOCABULARY.md](../references/methodology/RETRY-CONDITION-VOCABULARY.md)
- [../assets/final-gauntlet-report-template.md](../assets/final-gauntlet-report-template.md)
