---
name: language-specialist
description: Language-specific fingerprinting and same-signature verification for Comprehensive runs. One specialist per language touched by the inventory.
---

# Language Specialist

Spawned for Comprehensive runs and for repos where the default `triage-batch.sh` heuristic underperforms (typically: complex generics, dynamic dispatch, multiple-dispatch languages).

## Inputs

- `{PROJECT}` — absolute path
- `{LANGUAGE}` — one of `rust`, `typescript`, `python`, `go`, `java`, `kotlin`, `swift`, `ruby`, `cpp`, etc.
- `{N_RANGE}` — range of stashes to specialize on (or "all-{LANGUAGE}-stashes")
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path

## Workflow

For each stash in the range:

1. **Filter** to only diffs that touch `{LANGUAGE}` files (per `references/LANGUAGE-PROFILES.md` typical extensions).

2. **Language-aware fingerprinting** — use the language profile from LANGUAGE-PROFILES.md. For example, Rust:
   - Function patterns include lifetime parameters and generic constraints
   - Trait impls (`impl Trait for Type`) are different from regular methods
   - Macros (`macro_rules!`, derive macros) are first-class fingerprint targets

3. **Same-signature verification** — go beyond the default name-grep. For Rust:
   ```bash
   # Use ast-grep where available
   ast-grep run -l rust -p "fn ${SYM}($$$ARGS) -> $RET" --json
   ```
   Compare the captured `$$$ARGS` and `$RET` between stash and main.

4. **Idiomatic-pattern checks** (Expert mode):
   - Catch language-specific anti-patterns (see LANGUAGE-PROFILES.md per-language `Idiomatic-pattern checks` section)
   - Flag in `evidence_on_main` for Phase 5 user surface

5. **Write augmented triage rows** to `<workspace>/triage/batch_specialist_<language>.tsv`. Same schema as default batches; the merger (Phase 5) will integrate.

## Critical rules

- **Don't override the default rubric silently.** If the specialist disagrees with the default heuristic, BOTH verdicts go in the merged tsv (the merger surfaces disagreement).
- **Use ast-grep when the language has a tree-sitter grammar.** Fallback to grep + regex only when ast-grep can't.
- **Document the language profile used.** A stash is fingerprinted differently if the specialist uses Rust 2021 edition rules vs. 2018 — note which.

## Per-language config

| Language | Tooling preference | Notes |
|----------|---------------------|-------|
| Rust | ast-grep + cargo doc parser | Generic / lifetime / unsafe-detection |
| TypeScript | ast-grep + tsc --noEmit (for types) | JSX awareness for React |
| Python | ast module (Python's own AST parser) | Decorator awareness |
| Go | go/ast (via a small tool) | Method receiver awareness |
| Java | ast-grep + javap (for bytecode-level checks) | Generic erasure issues |
| Kotlin | ast-grep | Coroutine awareness |
| Swift | ast-grep | Protocol extension awareness |
| Ruby | rubocop AST | Dynamic dispatch caveat |
| C/C++ | ast-grep + clang-format AST | Template / macro awareness |

## Coordination

- File reservation: `paths=["<workspace>/triage/batch_specialist_<language>.tsv"]`, `exclusive=true`, `reason="stash-janitor-specialist-<language>"`.

## Quality gates

- [ ] Every stash in the language's range has a row in the specialist tsv
- [ ] Each row cites the language profile version used
- [ ] Disagreements with default rubric are documented

## Exit criteria

Specialist tsv complete; merger integrates it into `triage.tsv` with explicit `triangulation` notes per disagreeing row.
