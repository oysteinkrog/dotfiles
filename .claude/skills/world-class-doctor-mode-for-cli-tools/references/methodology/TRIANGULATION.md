# Multi-Model Triangulation

Used in Phase 4 (top-N specs + `mutate()` chokepoint + irreversible paths) and Phase 7 (each of the three calibrated review prompts).

Invoked via the `/multi-model-triangulation` skill. Each model receives the same prompt + same context; their outputs are compared.

---

## When to triangulate

Worth the 3× token cost:

- The `mutate()` chokepoint implementation (load-bearing for the entire skill).
- Any fixer that touches user data irreversibly (e.g., a DB schema migration).
- Any `--force` path.
- Any path that issues `Op::Rename` (the AGENTS.md no-delete pattern).
- The Phase 7 calibrated prompts.

NOT worth the cost:

- Style choices (variable naming, comment phrasing).
- Documentation prose.
- Test fixtures.
- Build/lint config.

---

## How to triangulate

```
1. The calling agent picks the question + the diff.
2. Invoke /multi-model-triangulation with:
   - the diff
   - the question (e.g., "Does this preserve byte-for-byte backup invariants under SIGKILL?")
   - the relevant context (links to MUTATE-CHOKEPOINT.md, the ops enum)
3. Each model returns a verdict and reasoning.
4. The calling agent compares:
   - Identical verdicts → consensus; record and proceed.
   - Different verdicts → divergence; investigate.
5. For each divergence:
   - Read each model's reasoning.
   - Check the actual code path.
   - File a bead if the divergence names a real bug.
   - Note in the triangulation report otherwise.
```

---

## Triangulation prompts (verbatim)

### `mutate()` chokepoint review

```
You are reviewing a critical chokepoint function `mutate(path, op) -> ActionResult`
that wraps every disk write performed by `<tool> doctor --fix`. Read the
implementation at: <link>.

Question: Does this implementation preserve the following invariants under
SIGKILL at any line of execution?

- Backup is verbatim (cmp-strict against the live file at the moment of backup).
- before_hash and after_hash are recorded only for completed mutations.
- actions.jsonl is append-only and fsync'd after each line.
- The per-path lock is released even on panic.
- Atomic writes: tempfile + rename, same FS as target.
- No torn writes visible to readers.

Your verdict: PRESERVES | DOES_NOT_PRESERVE.

If DOES_NOT_PRESERVE, name the line that breaks the invariant and the
specific failure scenario.
```

### Irreversible path review

```
You are reviewing a fixer for `fm-<id>` (a P0 failure mode). Read the
fixer at: <link>. Read the spec at: <link>.

Question: Is there any execution path that produces a state that cannot be
restored byte-for-byte by `<tool> doctor undo <run-id>`?

Specifically:
- Does the fixer touch bytes outside its declared diff range?
- Does the fixer rely on side effects that aren't recorded in actions.jsonl?
- Is there any `Op::DeletePath` or equivalent forbidden-by-AGENTS.md operation?
- Does the fixer use any source of nondeterminism (random IDs, timestamps in
  content) that would make undo non-byte-identical?

Your verdict: REVERSIBLE | NOT_REVERSIBLE.

If NOT_REVERSIBLE, name the path and the offending bytes.
```

### `--force` path review

```
You are reviewing the `--force` path of `<tool> doctor`. `--force` exists to
override exit-4 refusals in specific, documented cases. Read the implementation
at: <link>.

Question: Are there any safety invariants that `--force` bypasses?

Specifically:
- Does `--force` skip the backup write?
- Does `--force` skip the lock acquisition?
- Does `--force` allow writes outside `write_scopes`?
- Does `--force` skip the precondition check?
- Does `--force` activate without `--yes`?

Your verdict: SAFE | UNSAFE.

If UNSAFE, name the bypass and the specific scenario where it could
corrupt user data.
```

---

## Output format

Per-question, save to `<workspace>/triangulation_<phase>_<round>.md`:

```markdown
# Triangulation: phase=<phase> round=<round>

## Question 1: <Q>

| Model | Verdict | Reasoning excerpt |
|-------|---------|-------------------|
| Claude (this) | <verdict> | <one paragraph> |
| Codex | <verdict> | <one paragraph> |
| Gemini | <verdict> | <one paragraph> |

**Consensus:** YES | NO

**Disagreement (if any):** <description + bead-id if filed>

## Question 2: ...
```

---

## Cost discipline

Triangulation is reserved for high-stakes questions. Don't triangulate on:

- Documentation prose.
- Variable naming.
- Test fixture seed values.
- Style.
- Performance optimizations that don't affect safety.

If you find yourself triangulating on style, you've drifted. Stop and pull back to the high-stakes set.
