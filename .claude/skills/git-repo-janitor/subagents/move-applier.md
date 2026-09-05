# Subagent: move-applier

**Phase:** 6
**Spawn:** One per move category (sequential within category).

## Role

`git mv` + reference rewrites + gates + commit per category.

## Prompt

You are applying moves for category `<X>` in `<workspace>/move_plan.md`.

For each move (src → dst) in this category, in plan order:

1. Run `bash <skill-dir>/scripts/snapshot-tree.sh <project> phase6_<seq>` to capture working-tree state.
2. Re-run REFERENCE-GREP on `<src>` (`grep -rn` across `*.rs *.toml *.sh *.py *.md *.json *.yml *.yaml *.go *.js *.ts *.tsx *.html Makefile`). If drift since Phase 4, surface and ask.
3. `mkdir -p $(dirname <dst>)` if it doesn't exist.
4. `git mv <src> <dst>` (use `bash <skill-dir>/scripts/apply-move.sh` for the move plus pre-flight checks).
5. **REWRITE-REFERENCES** for each surfaced reference, via the **Edit tool** (one old/new pair at a time). Categories of rewrites:
   - Markdown link: `](./X.md)` → `](./docs/planning/X.md)` (or basename-only if README is in the same dir as the new path)
   - Code path constant: `const X_PATH: &str = "X.md";` → `const X_PATH: &str = "docs/planning/X.md";`
   - Shell var: `SPEC_PATH="X.md"` → `SPEC_PATH="docs/planning/X.md"`
   - YAML/TOML: `spec: X.md` → `spec: docs/planning/X.md`
   - Append `(file, line, old → new, ts)` to `<workspace>/reference_rewrite_log.tsv`
   - Skip refs marked `rewrite_eligibility=surface-only` — surface them and ask.

6. After all moves in this category:
   - Run `bash <skill-dir>/scripts/verify-references.sh <project> <src1> <src2> ...` — surface any survivors.
   - Run quality gates from `project_profile.json`:
     ```bash
     <test_command>
     <typecheck_command>
     <lint_command>
     <build_command>
     ```
     All must pass (or user-approved pre-existing failure).
   - `git add -A`
   - Compose commit message with `commit-message-author` subagent (or use `references/COMMIT-MESSAGE-CRAFT.md § Phase 6 template`).
   - Commit.
   - Append (id, action=move, sha, gates=passed) to `<workspace>/apply_log.tsv`.

If apply-check fails: do NOT force. Surface to user with full context per `references/INCIDENT-PLAYBOOK.md § A reference rewrite breaks the build`.

DO NOT use sed/awk/regex transforms for reference rewrites. Edit tool only.

## Output

- N commits on `repo-janitor-<DATE>` branch
- `<workspace>/apply_log.tsv` populated
- `<workspace>/reference_rewrite_log.tsv` populated

## Tools used

Bash, Read, Edit.

## Time budget

5–30 min per category.
