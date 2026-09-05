# fresh-eyes-reviewer-b

> Phase 14 • Second verbatim fresh-eyes review prompt (random-walk + AGENTS.md compliance).

## Inputs
- The current state of the workspace + target after `fresh-eyes-reviewer-a` completes.
- The target's `AGENTS.md` file.
- All best-practice guides referenced in AGENTS.md.

## Deliverables
- `<workspace>/phase14_fresh_eyes_b.md` with: explored files, traced execution flows, bugs/problems found, fixes applied (or beads opened), AGENTS.md compliance findings.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase14-fresh-eyes-b`
- **Reservations needed:** `tool://workspace-edit` (TTL 120m).
- **Lane:** cross-cutting.

## Verbatim Prompt

The following prompt is verbatim and MUST be applied literally:

> I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file.

**Procedure:**
1. Read `AGENTS.md` in full. Extract every rule, every referenced best-practice guide, every linting/test discipline. Build a checklist.
2. Pick 5–10 files at "random" — but bias toward files that:
   - Are high-impact (in the hot path, in the conformance gate, in the surface-coverage rollup).
   - Were touched recently (since Phase 9 baseline) but not by the agent doing this review.
   - Have many `pub` items (broad surface).
   - Have `unsafe` blocks.
3. For each picked file:
   - Read it in full.
   - Trace its imports and its importers (use `rg "use <crate>::<module>"` and inverse).
   - Understand the file's purpose in the larger workflow.
   - Apply the fresh-eyes lens (same checklist as fresh-eyes-reviewer-a, PLUS the AGENTS.md compliance checklist).
   - Fix what you find; open beads for what's out of scope.
4. After each fix, run the relevant tests AND `cargo clippy --workspace -- -D warnings` AND `cargo fmt --check`.

**AGENTS.md compliance checklist** (extract from the file; common rules across projects include):
- Negative-evidence ledger entries for every rejected perf candidate.
- `// SAFETY:` comments matching the actual invariant for every `unsafe`.
- Clippy lint group minimum (typically `clippy::pedantic` or project-specific).
- No `unwrap()` outside tests.
- No `panic!` outside `unreachable!` or explicitly-documented invariant violation.
- Structured logging via `tracing`, not `println!`/`eprintln!`.
- Cross-platform reproducibility: no `chrono::Utc::now()` in deterministic paths; use injected clocks.

**Output structure:**
```markdown
## AGENTS.md rules extracted (N)
| Rule | Source | Violations found |
|---|---|---|
| <rule> | AGENTS.md:LN | <count> |
| ... |

## Files explored (N)
| File | Imports traced | Importers traced | Purpose summary | Findings |
|---|---|---|---|---|

## Detailed findings + fixes
(same shape as fresh-eyes-reviewer-a)

## AGENTS.md compliance summary
| Rule | Files checked | Compliant | Fixed | Deferred |
```

**Discipline:**
- "Random" means deliberately diverse — do not just pick the files you happen to remember.
- Trace BOTH directions (imports AND importers) — sometimes a bug is upstream and only visible from the consumer's perspective.

## Exit Criteria
- 5–10 files explored with imports + importers traced.
- AGENTS.md rules extracted and applied as checklist.
- All in-scope fixes applied; `cargo clippy --workspace -- -D warnings` and `cargo fmt --check` green.
- `phase14_fresh_eyes_b.md` committed.

## References
- [PHASES.md § Phase 14](../references/PHASES.md)
- [methodology/OPERATORS.md § Fresh-Eyes](../references/methodology/OPERATORS.md)
- [exemplars/EXEMPLARS.md § fresh-eyes prompts](../references/exemplars/EXEMPLARS.md)
