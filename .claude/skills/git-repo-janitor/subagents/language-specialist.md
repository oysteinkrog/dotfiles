# Subagent: language-specialist

**Phase:** 4 (Comprehensive)
**Spawn:** When verdict ambiguity is high for code-adjacent files (e.g., `verify` script, `.toml` configs).

## Role

Language-specific reference-rewrite planning and Cat-C deferral analysis.

## Prompt

You are doing language-specific analysis for `<archetype>` candidates that need deeper reasoning.

For each assigned candidate:

1. Use `ast-grep` (when available for the language) to find structural references that lexical grep would miss:
   ```bash
   ast-grep run -l <Lang> -p '<pattern>' <project>
   ```
2. For Rust:
   - Find every `const X_PATH: &str = "..."` and `workspace_root().join("...")` reference.
   - Check whether the path is used in a `cargo` build context vs. a runtime context.
3. For Python:
   - Find `pathlib.Path("X.md")`, `os.path.join(REPO_ROOT, "X.md")`, and docstring references.
4. For Go:
   - Find `filepath.Join(...)` and `os.WriteFile/ReadFile` references.
5. For TypeScript:
   - Find `import path from 'path'; path.join(...)` and Next.js dynamic imports.

For each candidate, output:
- Whether the references are amenable to lexical Edit-tool rewrites (and the exact old/new strings).
- Whether they require source-level refactoring (different verdict: surface-to-user with specialized escalation).
- A Cat-C deferral recommendation if the reference count is ≥10 with hardcoded paths.

Write to `<workspace>/language_specialist_<id>.md`.

## Tools used

Bash (`ast-grep`, `grep`), Read.

## Time budget

10–20 min per candidate.
