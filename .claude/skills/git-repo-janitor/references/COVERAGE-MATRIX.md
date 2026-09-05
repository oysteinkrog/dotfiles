# Coverage Matrix

**Source axiom:** Axiom 18. Every smell rule in [FILE-SMELLS.md](FILE-SMELLS.md) must produce a row in `coverage_matrix.md` for this run, marked `present | partial | missing | n/a`. A blank cell is a bug.

The matrix is the audit log of "what did the skill actually consider?" — not just "what did it find?"

---

## Why a coverage matrix matters

A 60-row triage.tsv lists what the skill *flagged*. It says nothing about what the skill *checked*. Without a matrix, you can't tell:

- Did the skill consider the `nohup-leak` rule on this run? (Yes; the rule was checked but no nohup.out exists → `n/a`.)
- Did the skill consider the `secret-suspect` rule on every candidate? (Yes; 87 candidates × secret-suspect rule = 87 cells; 0 hits → all `n/a`.)
- Did the skill skip any rule because of a bug or because it was deemed inapplicable?

The matrix surfaces all of these explicitly.

---

## Status values

| Value | Meaning |
|-------|---------|
| `present` | The smell rule fired on this run; ≥1 candidate was tagged with it |
| `partial` | The rule fired but the run handled it incompletely (e.g., 5 candidates tagged but only 3 reached a verdict; 2 are still `surface-to-user` pending user input) |
| `missing` | The rule was not exercised on this run, but the project's archetype suggests it should have been (e.g., a Python package that has no `*.pyc` candidates is suspicious; either the rule is broken or `__pycache__/` is already gitignored) |
| `n/a` | The rule was checked but doesn't apply here (e.g., a Rust crate has no `*.pyc` files because it has no Python; the rule is correctly inactive) |

A `missing` cell is a yellow flag that triggers Phase 9 fresh-eyes to investigate.

---

## Schema

`coverage_matrix.md` is a markdown table:

```markdown
## Smell-rule coverage — repo-janitor-2026-05-08 on `/data/projects/<repo>`

| Smell rule | Status | Hit count | Verdict distribution | Evidence | Notes |
|------------|--------|----------:|----------------------|----------|-------|
| sqlite-db | present | 3 | delete-and-gitignore: 3 | storage.sqlite3, dev.sqlite3-wal, dev.sqlite3-shm | Standard dev-DB pattern |
| sqlite-wal-shm | present | 2 | gitignore-tied: 2 | (sibling rows above) | Tied to sqlite-db parent verdict |
| nohup-leak | n/a | 0 | — | (no nohup.out at root) | OK |
| skill-output | present | 4 | delete-and-gitignore: 4 | .skill-loop-progress.md, ... | Apr-27 cleanup pattern |
| progress-report | present | 27 | move: 27 → docs/progress/ | progress*.md cluster | Frankensqlite pattern |
| planning-doc | present | 16 | move: 16 → docs/planning/ | COMPREHENSIVE_*.md cluster | Frankensqlite pattern |
| multi-llm-plan-cluster | present | 4 | move: 4 → docs/planning/ | PLAN_TO_*__GPT/OPUS/CODEX/GEMINI.md | Move all variants together |
| binary-elf | present | 2 | delete-no-gitignore: 2 | rust_out, test_ptr | Reproducible from cargo build |
| dual-format-asset | present | 1 | delete-no-gitignore: 1 (.png unreferenced) | illustration.png + illustration.webp | README references the .webp |
| coverage-output | n/a | 0 | — | (no coverage*.txt at root) | Project doesn't generate at root |
| editor-backup | n/a | 0 | — | (no *.bak at root) | OK |
| secret-suspect | partial | 1 | surface-to-user: 1 (signing-X.pub) | (Phase 2.5 user confirmed safe) | .pub without .key — public component, OK |
| numeric-or-shell-escape-name | n/a | 0 | — | (no numeric-named files) | Apr-27 ntm pattern absent |
| .br_recovery / .rch / agent-tooling-state | missing | 0 | — | (no .br_recovery/ but project uses beads_rust) | Investigate: should be present? |
...
```

The `missing` row above ("`.br_recovery/` not present but project uses beads_rust") is the kind of signal Phase 9 cares about: either the project's `.gitignore` already covers it (good) or the agent missed something (investigate).

---

## How to build the matrix

Phase 2.5 follows Phase 2 inventory. The coverage-mapper subagent (or Phase 4's first pass):

```bash
# Pseudocode
for rule in $(list_all_smell_rules):
    matching_candidates = candidates.tsv filter by smell_tags contains $rule
    if len(matching_candidates) == 0:
        if archetype_suggests_rule_should_apply($rule):
            status = "missing"   # yellow flag
        else:
            status = "n/a"
    elif all matching candidates have a verdict:
        status = "present"
    else:
        status = "partial"   # some are still surface-to-user

    write_row(rule, status, len(matching_candidates), verdict_distribution, evidence_summary, notes)
```

A draft script `scripts/generate-coverage-matrix.sh` produces the skeleton; the coverage-mapper subagent fills in the `Notes` column and decides `missing` vs `n/a` based on archetype.

---

## "Should this rule apply?" — archetype heuristics

The decision between `missing` and `n/a` depends on the archetype:

| Archetype | Rules expected to be `present` or explicit `n/a` (anything else is `missing`) |
|-----------|-------------------------------------------------------------------------------|
| `single-rust-crate` | sqlite-db (often `n/a`), binary-elf (often `present` or `n/a`), `*.rs.bk` (often `n/a`), criterion/ (often `n/a`), perf.data (often `n/a`) |
| `polyglot-monorepo` | All language-cache rules: `__pycache__`, `node_modules/leakage`, `target/leakage`. Each per-subtree |
| `claude-skill-repo` | skill-output, dot-pre-skill-state, planning-doc (often `present`) |
| `nextjs-saas` | `.next/`, `node_modules/leakage`, `*.tsbuildinfo`, `*.snap.new` |
| `python-package` | `__pycache__`, `*.pyc`, `.coverage`, `.pytest_cache/`, `.venv/leakage` |
| `go-cli` | `*.test`, `*.out`, ELF binary at root, `*.golangci.bck.*` |

For an archetype, the matrix should have explicit rows for every rule in the "expected" column. A blank cell or missing row triggers an investigation.

---

## What the matrix unlocks

1. **Phase 9 fresh-eyes** uses the matrix to decide what to investigate. A `missing` cell ("we expected to find sqlite-wal-shm but didn't") is a signal to dig deeper.

2. **Negative-decision recording** (Axiom 18 + the `⊠ NEGATIVE-DECISION` operator). When the user explicitly skips a category, the matrix records it: "skipped Cat C TOML moves because reference count >10 with hardcoded paths; surface for future runs."

3. **Cross-run drift detection** (`maintenance-review` mode). Compare `coverage_matrix.md` across two runs of the same repo. New `present` rows = drift; new `missing` rows = something previously caught is now silent (regression).

4. **Skill quality measurement** (MEASUREMENT.md). Across runs, what fraction of cells are `n/a` vs `present` vs `missing` vs `partial`? A high `partial` fraction indicates the skill needs better Phase 4 finish-rate.

5. **Auditability**. A reviewer can ask "did the skill consider rule X?" and the matrix has the row.

---

## Worked example: Cat-C deferral row

The frankensqlite Apr-27 cleanup deferred Cat-C (TOML contracts) because their reference count was >10 with hardcoded paths. The matrix row:

```markdown
| toml-contract-with-hardcoded-paths | present | 15 | DEFERRED-by-rule: 15 | corpus_manifest.toml, db300_*.toml, parity_taxonomy.toml, leapfrog_exit_criteria.toml, ... | DEFERRED per Cat-C rule: ≥10 refs with hardcoded path strings; user signed off on skip; will revisit when ready for the larger surgery |
```

A future run on the same repo would re-check the rule. If the project meanwhile refactored the references to be configurable, the same rule would produce verdict `move: 15 → docs/contracts/` instead.

---

## Negative-decision register

When the user override a verdict (e.g., "actually keep stash@{47} too"), the matrix's `Notes` column records it AND a separate `negative_decisions.md` file lists the user-visible exceptions:

```markdown
## Negative decisions — repo-janitor-2026-05-08 on `<repo>`

1. **Cat C deferral**: 15 TOML contracts NOT moved; refs too pervasive
2. **`signing-X.pub` kept at root**: Phase 2.5 surfaced; user confirmed safe (public component of an Ed25519 keypair)
3. **`tests/fixtures/sample.log` kept**: Triage flagged `coverage-output` smell but reference-grep found use as a parser test fixture
```

These are the things future maintainers will ask about. Recording them keeps the skill auditable.

---

## When the matrix is wrong

If a rule fires on a row that should be `n/a`, that's a false-positive: investigate the rule, narrow it. If a rule that should fire is `missing` and the file isn't present, that's correct. If a rule that should fire is `missing` and the file IS present (just escaped detection), that's a real bug in the smell catalogue.

The Phase 9 fresh-eyes round 3 (Adversarial stance) is supposed to catch the third case. Document any caught instance in `WORKED-EXAMPLES.md` for future runs.
