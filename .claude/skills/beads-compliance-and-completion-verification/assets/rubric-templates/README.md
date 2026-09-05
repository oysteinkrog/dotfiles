# Rubric templates

Pre-tuned `rubric.md` variants. Copy one to `<audit-dir>/rubric.md` (replacing
the default copied by `bootstrap-audit.sh` from `assets/rubric-template.md`)
when the project's bead-type mix or quality bar differs from the defaults.

| Template | When to use |
|----------|-------------|
| `security-heavy.md` | Project has many `security`, `auth`, `crypto`, `webhook` beads. Bumps Phase 5 anti-theater + the security specialist's negative-test weight; lowers tolerance for `WAIVED` verdicts on auth tests. |
| `perf-heavy.md` | Latency-sensitive service. Boosts `test_depth` (statistical-significance benchmarks) and adds a `regression_pct` axis; per-perf-bead override demands ≥30 samples. |
| `infra-heavy.md` | Lots of migration / deploy / DDL beads. Raises `migration-safety-reviewer` weight; rollback drill is BLOCKING by default. |
| `docs-heavy.md` | Documentation-led project. Re-weights the docs dimension to 500/1000 (vs default 100); demands link-check + fidelity tests. |

After copying:

1. Compute its sha256: `sha256sum <audit-dir>/rubric.md`
2. Patch `manifest.json#rubric_sha256` with the new value (or re-run
   `bootstrap-audit.sh` which does this automatically)
3. The variants set `rubric_version` in their YAML frontmatter so
   `validate-rubric.py` will warn if you mix variant assertions with the
   default rubric's score bands.

**Convergence implication:** if you switch rubrics mid-project, the
prior pass's scores are not directly comparable to the new pass's scores.
`convergence-check.py` detects rubric_sha256 changes and emits
`rubric_changed_since_prior_pass: true` so the convergence verdict accounts
for it.
