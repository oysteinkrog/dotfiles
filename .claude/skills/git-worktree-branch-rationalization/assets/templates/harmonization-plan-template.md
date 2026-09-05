# Harmonization Plan Template

Used by `harmonization-plan.sh` and the harmonization-planner subagent for Phase 7. See the script for the auto-generated version.

The harmonization plan is reviewed by the user BEFORE Phase 8 mutates anything. Every synthesis commit on the rationalization branch traces back to a row in this plan.

---

```markdown
# Harmonization Plan — {RUN_DATE}

**Project:** {PROJECT_PATH}
**Canonical:** {CANONICAL_BRANCH}
**Rationalization branch:** {RATIONALIZATION_BRANCH}

## Why this plan exists

{N_COLLIDING_FILES} file(s) are touched by ≥2 non-protected branches with verdict ∈
{novel-and-accretive, partially-novel, divergent-refactor, dirty-worktree-only}.
For each one, this plan proposes a best-of-all-worlds synthesis on top of canonical's
current structure rather than picking one variant and dropping the rest.

Synthesis commits land via the Edit tool (NEVER sed/awk; per AGENTS.md "No Script-Based
Changes"). Each synthesis commit's message cites the source branches and explains why
each hunk came from where.

If you disagree with any synthesis, reply with overrides per the "Next step" section.
The plan can be re-run after overrides without losing prior work.

---

## Variant matrix — `{FILE_1_PATH}`

**Canonical version key signatures:**

\```{lang}
{canonical key snippets — function signatures, important constants, etc.}
\```

**Contributing variants:**

| source | kind | identified intent | hunk summary | tests/fixtures |
|--------|------|-------------------|--------------|----------------|
| `{branch_A}` | branch (head: {sha}) | {intent} | {summary} | {tests/fixtures} |
| `{branch_B}` | branch (head: {sha}) | {intent} | {summary} | {tests/fixtures} |
| `{worktree_path}` | dirty worktree (staged + unstaged) | {intent} | {summary} | {tests/fixtures} |

**Intents identified:**
- defensive hardening (branch A) — `if input.is_empty() { return ...; }`
- length-cap (branch B) — `if input.len() > N { ... }`
- redaction-pattern (branch C) — `input.replace("password=", ...)`
- type-narrowing (worktree dirty) — `let s: &str = input;`

**Proposed synthesis (on top of canonical's current structure):**

\```{lang}
{the synthesized code, which composes all four intents — defensive null-check from A,
length-cap from B, redaction-pattern from C, type-narrowing from worktree — on top of
canonical's signature}
\```

**Why this synthesis beats any single variant:**

- Defensive null-check (from `{branch_A}`) catches an edge case the others miss.
- Length-cap (from `{branch_B}`) prevents unbounded allocations.
- Redaction-pattern (from `{branch_C}`) is the actual security feature.
- Type-narrowing (from `{worktree_path}`'s staged) clarifies intent for static analysis.

None of the variants individually satisfy all four intents. The synthesis composes
them in dependency order: type-narrowing → null-check → length-cap → redaction.

**Confidence:** {confidence_score} (0.0–1.0)
**Risks:** {identified risks — e.g., "if input is non-UTF8, the redaction pattern
needs careful handling"}

**Tests/fixtures to land alongside:**

- `{test_file_path}::{test_name}` from `{branch_X}` — exercises the redaction path
- `{fixture_file_path}` from `{branch_Y}` — sample input with embedded passwords
- (Tests are additive across variants; include all of them)

**Proposed commit message:**

\```
{prefix}({scope}): harmonize redact_secrets defensive checks across four sources

This commit synthesizes complementary defensive checks for redact_secrets that were
each developed in separate branches/worktrees but never landed together:

- Defensive null-check from `agent-redact-null-check` (sha {sha_A}):
  prevents allocation when input is empty.
- Length-cap from `feature/redact-length-cap` (sha {sha_B}):
  caps at 4096 chars to prevent unbounded growth.
- Redaction-pattern from `feature/redact-pattern` (sha {sha_C}):
  the actual security feature, replacing `password=...` patterns.
- Type-narrowing from worktree `{wt_path}` (staged content):
  clarifies intent for static analysis.

The composition order matters: type-narrowing first (no-op at runtime), then
null-check (early return), then length-cap (truncation), then redaction
(pattern replace). Each layer's test from the original branch is included.

Recovered via:
- harmonization plan: <workspace>/harmonization_plan.md
- source variants: <bundle>/branches/{slug_A}/, <bundle>/branches/{slug_B}/,
  <bundle>/branches/{slug_C}/, <bundle>/worktrees/{wt_sanitized}/
\```

---

## Variant matrix — `{FILE_2_PATH}`

(Repeat the structure above for each colliding file.)

---

## Files touched by exactly one branch (no harmonization needed)

These files have a clear single source. Phase 8 will straight-apply via the strategy
chosen in `triage.tsv` (cherry-pick / squash-merge / rebase-and-merge / split-commits).
No entry needed in this plan.

| file | source branch | strategy |
|------|---------------|----------|
| {path} | {branch} | {strategy} |
| ... | ... | ... |

---

## Branches with verdict `divergent-refactor` and no file collision

These branches took an intentionally incompatible direction but don't collide with
other non-protected branches on any file. Per the SKILL.md kernel (Axiom 1: Harmonize,
don't pick — but only when variants share files), no harmonization is attempted.
Default action: skip in Phase 8; user opt-in to delete in Phase 10.

| branch | reason | files touched | proposed action |
|--------|--------|---------------|-----------------|
| {name} | {one-paragraph reason} | {file count} | skip (default) / delete (opt-in) |
| ... | ... | ... | ... |

---

## Next step

Reply with one of:

- `approve` — proceed to Phase 8 with the syntheses as proposed.
- `revise <file>` — open the variant matrix for `<file>` for re-discussion (you'll
  see the matrix again with proposed alternatives).
- `pick <branch> for <file>` — drop the synthesis and use `<branch>`'s variant as-is
  for `<file>`.
- `drop <file>` — don't recover any variant for `<file>`; canonical's current
  version stands.
- `wait` / `stop` — abort the run; bundle and refs remain intact.

The skill will not proceed to Phase 8 until you approve.
```

---

## Authoring checklist for each variant matrix entry

- [ ] All contributing variants enumerated (don't miss a branch or worktree)
- [ ] Each variant's intent named explicitly (defensive / refactor / test / fixture / type-narrowing / error-handling / performance / naming)
- [ ] Proposed synthesis preserves the strongest example of each intent
- [ ] Synthesis composes intents in correct dependency order
- [ ] Confidence score honest (≤0.7 → flag for extra user attention)
- [ ] Risks called out
- [ ] Tests/fixtures from all variants enumerated
- [ ] Commit message drafted with full source citations

---

## When NOT to harmonize a variant matrix

- **Architectural disagreement.** If two variants represent fundamentally incompatible architectural choices (different state-machine designs, different storage layouts, different API contracts), flag as `divergent-refactor`, surface to user, do NOT auto-synthesize. Per HARMONIZATION.md.
- **Binary collision.** If both variants modify the same binary blob in different ways, defer to user; the variant matrix doesn't apply.
- **Test-only collision.** If two variants only collide on a test fixture file, both fixtures are usually additive; concatenate them rather than composing them.
- **Refactor-only collision.** If two variants both refactor the same file but neither adds new functionality, pick the strongest one and discard the other; the variant matrix collapses to a single-source row.
