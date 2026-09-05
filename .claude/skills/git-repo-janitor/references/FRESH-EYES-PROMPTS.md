# Fresh-Eyes Prompts

The three review prompts (verbatim from the documentation-website-for-software-project skill — they're calibrated). Run in rotation across rounds.

---

## Prompt 1 — Direct review of the changes

> "Carefully read over all of the new file moves, deletes, .gitignore changes, and reference rewrites you (and your fellow agents) just made with 'fresh eyes' looking super carefully for any obvious bugs, errors, broken references, broken builds, missed cleanup. Carefully fix anything you uncover."

**What it catches:**
- Path-rewrite typos
- Missed references (the rewrite log says they were updated but they weren't)
- A move that left the destination file with the wrong content
- A delete that left dangling imports

---

## Prompt 2 — Random exploration with traceable intent

> "Sort of randomly explore the code files in this project, choosing files to deeply investigate and tracing whether any of them reference paths that may have been moved or deleted in this run. Once you understand the purpose of the file in the larger context, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious broken-reference bugs, silent test fixture losses, or build-system effects from the cleanup."

**What it catches:**
- References in less-grep'd files (e.g., `Makefile`, `.github/workflows/*.yml`, `.apr/workflows/*.yaml`)
- Build script breakage that didn't fail the per-commit gates because the build target wasn't exercised
- Test fixture losses where the test file isn't run by default

---

## Prompt 3 — Adversarial review of the cleanup itself

> "Turn your attention to reviewing the cleanup decisions made by your fellow agents and checking for any false-positive deletes (a deleted file may have been a referenced test fixture), bad moves (a moved file's new location may not be findable from a build script with hardcoded paths), or .gitignore additions that silently mask important files. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep."

**What it catches:**
- False-positive deletes that REFERENCE-GREP missed
- `.gitignore` shadowing that SHADOWING-AUDIT missed
- Cat-deferral mis-decisions (a category was deferred but actually safe to do; or vice versa)

---

## Termination rule

Two consecutive full rounds (all three prompts) produce only trivial findings (typo, wording polish) AND test + typecheck + lint + build + UBS all green.

For Comprehensive variant: ≥3 clean rounds, with multi-model triangulation on round 3.

---

## Between rounds

Run the project's full quality gate suite from `project_profile.json`:

```bash
<test_command>          # e.g., cargo test --workspace
<typecheck_command>     # e.g., cargo check --workspace
<lint_command>          # e.g., cargo clippy --workspace -- -D warnings
<build_command>         # e.g., cargo build --workspace --release
ubs .                   # if available
```

All must exit 0. Log each round + outcome to `fresh_eyes_log.md`.

---

## Stance variation

For Comprehensive variant, vary the stance across the three prompts within each round:

| Prompt | Round 1 stance | Round 2 stance | Round 3 stance |
|--------|----------------|----------------|----------------|
| 1 | Literal | Literal | Adversarial |
| 2 | Forensic | Skeptical | Skeptical |
| 3 | Adversarial | Adversarial | Forensic |

See `MODES-OF-REASONING.md` for stance definitions. Different stances surface different classes of bugs.
