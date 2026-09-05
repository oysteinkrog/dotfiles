# Confidence Scoring

**Source axiom:** Axiom 19. Every triage row carries a confidence score in [0, 1] derived from four dimensions; the lowest dimension caps the overall confidence. Verdicts with confidence < 0.7 always flip to `surface-to-user`.

The score is per-recommendation, not per-run. It tells the user (and the skill) where to focus review.

---

## The four dimensions

### 1. Evidence Quality (EQ) — 1 to 5

| Score | Meaning |
|-------|---------|
| 5 | File magic bytes + content fingerprint + filename rule + archetype rule all align |
| 4 | Content fingerprint + filename rule align; magic bytes confirm |
| 3 | Filename rule alone; content sniff matches expected pattern |
| 2 | Filename rule alone; content sniff is ambiguous |
| 1 | Filename rule alone; content sniff disagrees with expected pattern |

Examples:

- `storage.sqlite3` with `SQLite format 3\x00` magic bytes, in a Rust crate that doesn't track DBs as fixtures → EQ 5.
- `nohup.out` with first line "hello" looking like stdout → EQ 4.
- `scratch.py` matching `scratch-script` filename rule but content is a coherent helper module → EQ 1 (filename misleads).

### 2. Smell Specificity (SS) — 1 to 5

| Score | Meaning |
|-------|---------|
| 5 | One specific smell tag (e.g., only `sqlite-wal-shm`) |
| 4 | Two complementary tags (e.g., `progress-report` + `multi-llm-plan-cluster`) |
| 3 | Three+ tags but they all align toward one verdict |
| 2 | Three+ tags that produce conflicting verdicts (e.g., `planning-doc` + `secret-suspect` simultaneously) |
| 1 | Many tags, conflicting → no clear signal |

Higher specificity = more confident. Multiple aligned tags can boost confidence; conflicting tags lower it.

### 3. Reference-Graph Completeness (RGC) — 1 to 5

| Score | Meaning |
|-------|---------|
| 5 | REFERENCE-GREP ran across all expected file types (rs, toml, sh, py, md, json, yml, yaml, go, js, ts, html, Makefile, Dockerfile, vercel.json, netlify.toml, k8s yaml); zero inbound refs |
| 4 | Same scope; 1 inbound ref, in a comment / docstring (low-impact) |
| 3 | Some inbound refs but all are themselves candidates being deleted |
| 2 | 1 inbound ref in source code that needs rewriting |
| 1 | 2+ inbound refs in source code, in different file types; rewrite plan is risky |

Lower RGC = more risk that the move/delete will break something. Forces verdict to `surface-to-user`.

### 4. Reversibility (R) — 1 to 5

| Score | Meaning |
|-------|---------|
| 5 | `move` only — fully reversible via `git revert <move-commit>` |
| 4 | `gitignore-only` — easily reverted via `.gitignore` edit |
| 3 | `delete-and-gitignore` — reversible via `git revert` or bundle |
| 2 | `delete-no-gitignore` — reversible via bundle but lose recurrence rule |
| 1 | History rewrite (`git filter-repo`) — reversible only via mirror backup; affects every clone |

Action irreversibility lowers confidence. Filter-repo runs always score R=1.

---

## Combining dimensions

The overall confidence is the **minimum** of the four dimensions, normalized to [0, 1]:

```
confidence = min(EQ, SS, RGC, R) / 5.0
```

This is *deliberately conservative*: any single weak dimension caps the overall score. A row can't have high confidence if any single signal is questionable.

### Why "lowest caps"?

If EQ=5 (strong content evidence), SS=5 (one specific smell), RGC=5 (no inbound refs), but R=1 (we're recommending a `git filter-repo`), confidence = 0.2 → forces surface-to-user. That's correct: history rewrite is high-stakes regardless of other dimensions.

The opposite case: if EQ=2 (filename misleads), even with SS=5, RGC=5, R=4, confidence = 0.4 → forces surface-to-user. Correct again: weak content evidence means the rule may be false-positive.

---

## Output format

Each triage row in `triage.tsv` carries a confidence column:

```
id  verdict             confidence  evidence              proposed_dest  pattern  EQ  SS  RGC  R
000 delete-and-gitignore 0.97       smell=skill-output;refs=0  (none)        .skill-loop-progress.md  5  5  5  4
017 move                 0.92       smell=plan-doc;refs=4    docs/planning/ (none)  4  5  3  5
023 surface-to-user      0.40       smell=scratch;refs=1    (none)         (none)  2  4  2  3
```

The 4-dimension breakdown is exposed for transparency. A user reviewing low-confidence rows can see *which* dimension is weak and decide whether to override.

---

## Confidence register

`recommendation-confidence-register.md` summarizes:

```markdown
## Confidence register — repo-janitor-2026-05-08

### High confidence (≥0.85): 73 rows
- 23 delete-and-gitignore (sqlite-db, skill-output, nohup-leak)
- 16 move planning-doc → docs/planning/
- 27 move progress-report → docs/progress/
- 7 archetype-protected keep-in-place

### Medium confidence (0.7–0.84): 9 rows
- 8 move audit-report → docs/audits/ (RGC=3 — refs in self-referential markdown)
- 1 delete-no-gitignore (binary-elf at non-standard path)

### Low confidence (<0.7) → surface-to-user: 5 rows
- 3 scratch-script with 1 inbound ref each (RGC=2)
- 1 dual-format-asset where reference-grep was ambiguous
- 1 secret-suspect (.pub without .key) — Phase 2.5 surface

Total: 87 candidates triaged across 17 distinct smell rules
```

The user reviews the medium and low rows; the high rows usually pass with bulk confirmation.

---

## Calibration: when scores are wrong

If a high-confidence row turns out wrong (Phase 9 fresh-eyes catches a false-positive delete that was confidence 0.95), the calibration is off. The skill maintainer:

1. Captures the case in `WORKED-EXAMPLES.md`.
2. Investigates which dimension over-scored. Was it EQ=5 because the filename rule was too aggressive? RGC=5 because the grep missed a file type?
3. Updates the rubric: tighten EQ scoring rules; add file types to RGC's "expected scope" list.
4. Re-runs the smoke tests in SELF-TEST.md.

This is the feedback loop for the confidence rubric.

---

## Worked examples

### Example 1: clear delete

`storage.sqlite3-wal` (4096 bytes), sibling of `storage.sqlite3` (12 KB SQLite db).

- EQ: 5 (filename rule + magic-byte WAL signature `\x37\x7f\x06\x82` + size pattern)
- SS: 5 (one tag: `sqlite-wal-shm`)
- RGC: 5 (no inbound refs anywhere)
- R: 4 (delete-and-gitignore — reversible via bundle + revert)

Confidence = min(5, 5, 5, 4) / 5 = 0.80. **Verdict: `delete-and-gitignore`. ACT.**

### Example 2: ambiguous filename

`scratch.py` at root, 1.2 KB, content is `import json; def find_next_task(): ...`.

- EQ: 2 (filename rule says scratch but content is a coherent helper module)
- SS: 4 (`scratch-script` tag is the dominant signal)
- RGC: 2 (1 inbound ref: `tests/conftest.py:5: from scratch import helper_fn`)
- R: 3 (delete is reversible but loses the test helper)

Confidence = min(2, 4, 2, 3) / 5 = 0.40. **Verdict: `surface-to-user`. ASK.**

### Example 3: planning doc with rewrites

`COMPREHENSIVE_PLAN.md` (846 KB), referenced from 4 source files via path constants.

- EQ: 4 (filename rule + capitalized prefix pattern + content has heading "## Plan")
- SS: 5 (`planning-doc` tag dominant)
- RGC: 3 (4 inbound refs but all are simple path constants amenable to surgical Edit)
- R: 5 (move is fully reversible)

Confidence = min(4, 5, 3, 5) / 5 = 0.60. **Verdict: `surface-to-user` (just barely below 0.7).** Phase 5 user-confirms; if they say "go," the verdict promotes to `move`.

This is the right behavior: the agent isn't sure enough about the rewrites to auto-apply, so it asks. Once asked, the user provides the missing context.

### Example 4: high-stakes secret-leak escalation

`signing-cafef00d.key` (32 bytes, base64-decodable, pushed to public origin/main 8 days ago).

- EQ: 5 (filename + content fingerprint + size match exactly)
- SS: 5 (`secret-leak` tag)
- RGC: 5 (no inbound refs — it's freestanding)
- R: 1 (history rewrite via `git filter-repo` is high-stakes)

Confidence = min(5, 5, 5, 1) / 5 = 0.20. **Verdict: `secret-leak` → halt + escalate to `harden-secret-leak` mode.**

The low confidence forces the escalation gate. Even though three dimensions are perfect, the action is irreversible enough to require user verbatim auth.

---

## When to override the rubric

The user can always override a verdict. When they do, the override is captured in `user_overrides.tsv` with a reason. If the same kind of override happens repeatedly, surface as skill feedback in Phase 11 (`skill_feedback.md`).

For example, if 5 different runs all override `dual-format-asset` because the reference-grep is too narrow (doesn't include `<picture>` HTML elements), the calibration team adds `<picture>` to the RGC scope.

---

## What scoring doesn't do

- It doesn't tell you the *correct* verdict; the rubric does.
- It doesn't measure how *useful* a cleanup is; that's MEASUREMENT.md.
- It doesn't replace user review; it focuses user review.

The score is a triage signal, not a verdict.
