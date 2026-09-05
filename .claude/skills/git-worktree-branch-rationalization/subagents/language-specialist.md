---
name: language-specialist
description: Phase 5 (Comprehensive mode only) — language-aware re-fingerprint + verify-on-canonical for branches in languages with non-trivial fingerprinting (Rust traits, TypeScript generics, Python decorators, Go generics, C++ templates, SQL DDL). Boosts triage confidence with ast-grep / language-AST evidence. Augments — never silently overrides — the default triage row.
---

# Language Specialist

Spawned by the main agent for Comprehensive runs and for repos where the default `triage-batch.sh` heuristic underperforms. One specialist per non-trivial language present in the inventory; triage-worker output rows are *augmented*, not replaced.

Why this exists for branches (more than for stashes): a branch is a chain of commits, not a single diff. Same-name-different-signature is common across long-running branches — Rust trait impls, TypeScript generic constraints, Python decorator stacks, Go generic type parameters, C++ template specializations, SQL migration ordering. The default name-grep heuristic from `triage-batch.sh` will under-detect supersession in these cases, leading to false `superseded` verdicts (wrong drop) or false `divergent-refactor` verdicts (work assigned to harmonization that isn't actually divergent). Per Axiom 16: same-name on canonical is not always supersession; the language-aware check is what tells the two apart.

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{LANGUAGE}` — one of `rust`, `typescript`, `python`, `go`, `java`, `kotlin`, `swift`, `ruby`, `cpp`, `sql`, etc.
- `{BRANCH_RANGE}` — slice of `branches.tsv` rows whose `files_touched` are predominantly in `{LANGUAGE}` (or "all-{LANGUAGE}-branches")
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path
- `{CANONICAL}` — canonical branch from `project_profile.json`

## Outputs

- `<workspace>/triage/batch_specialist_<language>.tsv` — same schema as `batch_<id>.tsv` from `triage-worker` plus extra columns: `language_profile_version` (e.g., `rust-2021-edition`), `signature_match` (yes/no/partial), `evidence_source` (ast-grep | grep), `disagreement_with_default`, language-specific idiomatic-pattern findings populating `evidence_on_canonical`.
- **Side effects:** read-only inspection of bundle artifacts and canonical's checked-out state via `git`, `ast-grep`, `ripgrep`, Read tool. Never runs inside another worktree's index. Never mutates files. Confidence < 0.7 still forces `unknown` verdict despite evidence boost.
- **Decision contract:** AUGMENTS — never silently overrides — the default rubric. When specialist disagrees with default, BOTH verdicts go in the merged tsv via `triage-merger`; Phase 6 surfaces all disagreements to the user before freeze. Never replaces the default verdict on its own authority.

## Workflow

For each branch in the assigned range:

1. **Filter** the branch's bundle diff (`<bundle>/branches/<slug>/diff-vs-merge-base.diff`) to only hunks that touch `{LANGUAGE}` files (per the typical extensions list in `references/LANGUAGE-PROFILES.md`, or fall back to a built-in default for missing entries).

2. **Re-run ✦ FINGERPRINT (operator `✦`) with language-aware patterns.** Override the default name-only fingerprint with:

   | Language | Fingerprint targets |
   |----------|---------------------|
   | Rust | `fn`/`pub fn`/`async fn` declarations with full generics + lifetime params + return type; `impl Trait for Type`; `trait` definitions; `#[derive(...)]` macros; `macro_rules!` definitions; `pub use` re-exports |
   | TypeScript | `function`/`const`/`class` with full generic constraints; `interface`/`type` exports; `decorator` calls (`@Foo`); JSX component declarations; `enum` definitions |
   | Python | `def`/`async def` with full type annotations and decorator stacks; `class` definitions including base classes and metaclasses; `@decorator` chains; `__all__` exports |
   | Go | `func` with full generic type parameters; method-receiver type; interface declarations; `//go:generate` directives |
   | Java / Kotlin | method signatures including generic bounds; `@Annotation` stacks; sealed/data class declarations; companion-object members |
   | C / C++ | function declarations with full template parameters; `class`/`struct`/`union` with template specializations; macro definitions; `extern "C"` blocks |
   | SQL DDL | `CREATE TABLE`/`CREATE INDEX`/`ALTER TABLE` statements; migration ordering keys; `CREATE OR REPLACE FUNCTION` |

3. **Re-run ◐ VERIFY-ON-CANONICAL (operator `◐`) with language-aware tooling.** Use `ast-grep` where the language has a tree-sitter grammar; fall back to grep + regex only when ast-grep can't. Example for Rust:
   ```bash
   ast-grep run -l rust -p "fn ${SYM}($$$ARGS) -> $RET" --json \
       <files-on-canonical>
   ```
   Compare the captured `$$$ARGS` and `$RET` between the branch's diff and canonical. **Same-signature confirmation** boosts confidence toward `superseded`; **signature divergence** boosts confidence toward `divergent-refactor` (per Axiom 16's 30% threshold).

4. **Idiomatic-pattern checks (Expert mode).** Catch language-specific anti-patterns that would otherwise sneak in via a recovered keeper:
   - Rust: `unwrap()` in non-test code; `unsafe` blocks without SAFETY comments; missing `#[must_use]` on builder-pattern methods.
   - TypeScript: `any` introductions; `// @ts-ignore` or `// @ts-expect-error` without justification.
   - Python: bare `except:` clauses; mutable default arguments; `eval`/`exec` introductions.
   - Go: ignored errors via `_`; goroutine leaks (no `context.Context` parameter).
   - SQL: ALTER TABLE without `IF EXISTS` guards; missing indices on join columns.

   Flag in the row's `evidence_on_canonical` field for Phase 6 user surface — these are "should the recovered content land at all" signals, distinct from "is the content already on canonical."

5. **Write augmented rows** to `<workspace>/triage/batch_specialist_<language>.tsv` — same schema as `batch_<id>.tsv` from `triage-worker`, plus an extra column `language_profile_version` (e.g., `rust-2021-edition`, `typescript-5.4`, `python-3.12`).

## Critical rules

- **Don't silently override the default rubric.** If the specialist disagrees with the default heuristic, BOTH verdicts go in the merged tsv (the merger surfaces disagreement to the user in Phase 6). The specialist *augments* — never replaces.
- **Use ast-grep when the language has a tree-sitter grammar.** Fall back to grep + regex only when ast-grep can't or isn't installed; record which path was used in `evidence_source`.
- **Document the language profile used.** A branch is fingerprinted differently if the specialist uses Rust 2021 edition rules vs. 2018 — note which in `language_profile_version`.
- **Never bypass pre-commit hooks** (no commits in this phase, but stated for completeness).
- **Never use sed/awk on source files** (per AGENTS.md "No Script-Based Changes"). All inspection is read-only via git, ast-grep, ripgrep, or the Read tool.
- **Never disturb concurrent agents' working-tree state** in any worktree (per AGENTS.md "Note for Codex/GPT-5.5"). Specialist analysis runs against the bundle and against canonical's checked-out state — never inside another worktree's index.
- **Never delete files without express user permission** (per AGENTS.md RULE NUMBER 1).
- **Never run mass-delete primitives.**
- **Confidence < 0.7 still forces `unknown` verdict.** The specialist's evidence boost can raise confidence ABOVE 0.7 when justified by AST evidence; it cannot mask uncertainty.

## Per-language tooling preference

| Language | Preferred AST tool | Fallback | Notes |
|----------|-------------------|----------|-------|
| Rust | ast-grep | rg with regex | Generic / lifetime / unsafe-detection |
| TypeScript | ast-grep | rg + tsc --noEmit (for type-only checks) | JSX awareness for React |
| Python | Python's `ast` module (via small helper) | ast-grep | Decorator awareness |
| Go | `go/ast` (via small tool) | ast-grep | Method receiver awareness |
| Java / Kotlin | ast-grep | javap (for bytecode-level checks) | Generic erasure issues |
| Swift | ast-grep | rg | Protocol extension awareness |
| Ruby | rubocop AST | ast-grep | Dynamic dispatch caveat |
| C / C++ | ast-grep | clang-format AST | Template / macro awareness |
| SQL | rg with grammar-specific regex | manual inspection | Migration ordering matters |

If neither ast-grep nor the language's native AST tooling is available, downgrade to plain grep with `language_profile_version: degraded-grep-only` and lower confidence by 0.10.

## Coordination

- File reservation: `paths=["<workspace>/triage/batch_specialist_<language>.tsv"]`, `exclusive=true`, `reason="branch-rationalization-specialist-<language>"`, `ttl_seconds=3600`.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] Every branch in the assigned range has exactly one row in the specialist tsv
- [ ] Each row cites `language_profile_version`
- [ ] Disagreements with default rubric are documented in `disagreement_with_default` column
- [ ] Same-signature vs signature-divergence is recorded in `signature_match` (yes / no / partial)
- [ ] Idiomatic-pattern findings populate `evidence_on_canonical` with `file:line` citations on canonical (or "absent" if the pattern is novel to the branch)

## Exit criteria

Specialist tsv complete; `triage-merger` (Phase 6) integrates it into `triage.tsv` with explicit `triangulation_note` per disagreeing row, and surfaces all disagreements to the user before the Phase 6 freeze.
