# Triage Rubric — How a Candidate Earns Its Verdict

Every candidate exits Phase 4 with exactly one verdict and an evidence string. This document is the verdict-by-verdict rubric.

---

## Verdicts

| Verdict | Meaning | Default Phase 6/7/8 action |
|---------|---------|----------------------------|
| `delete-and-gitignore` | Truly ephemeral; should never have been tracked AND will recur if not ignored | Phase 7 `git rm` + Phase 8 `.gitignore` add |
| `delete-no-gitignore` | One-off junk that won't recur (so no glob needed) | Phase 7 `git rm` only |
| `gitignore-only` | File is already removed from disk, OR pattern needs to land for prevention without untracking now | Phase 8 `.gitignore` add only |
| `move` | Worth keeping; needs a better home | Phase 6 `git mv` + reference rewrites |
| `keep-in-place` | Already correctly located; do nothing | (no commit) |
| `protected` | Archetype/protected-glob match — never touch | (no commit) |
| `surface-to-user` | Confidence < 0.7 OR ambiguous evidence | Phase 5 user decision |

The seventh verdict (`secret-leak`) only emerges from Phase 2.5 — it's not part of normal Phase 4 triage; it halts the run.

---

## Decision flow

```
For each candidate c:

  1. CHECK protected_globs (project_profile.json):
       If matches → verdict = protected, confidence = 1.0, evidence = "protected_globs:<pattern>"
       Skip to next.

  2. CHECK reference_graph[c]:
       n_refs = number of inbound references from non-candidate files
       If n_refs >= 1:
         If reference is in tests/, build script, hardcoded path constant:
           → verdict = keep-in-place (or move with rewrite plan)
         Else if all refs are also candidates being deleted:
           → ignore the inbound; treat as no refs
         Else:
           → verdict = surface-to-user, evidence = "refs=<files>"

  3. APPLY smell-tag rules (FILE-SMELLS.md):
       smell_strength = sum of confidence boosts from filename + content fingerprints

  4. Classify by smell + n_refs:

     IF smell_strength >= 0.95 AND n_refs == 0 AND smell in {sqlite-db, sqlite-wal-shm, nohup-leak, skill-output, dot-pre-skill-state, coverage-output, editor-backup, os-detritus}:
       → delete-and-gitignore, confidence = smell_strength
       → propose gitignore_pattern from the smell rule

     ELIF smell_strength >= 0.95 AND n_refs == 0 AND smell in {binary-elf, compiled-out, mailbox-format-patch, format-patch-blob}:
       → delete-no-gitignore, confidence = smell_strength
       → (one-off; pattern not generally useful)

     ELIF smell_strength >= 0.80 AND n_refs == 0 AND smell in {scratch-script, ad-hoc-test-fixture-stub, random-json-artifact, random-jsonl-artifact}:
       → delete-no-gitignore (or delete-and-gitignore if there's a clear future-recurrence pattern), confidence = smell_strength

     ELIF smell in {planning-doc, multi-llm-plan-cluster, audit-report, agent-output, txt-architecture-summary, runbook-or-recovery}:
       → move, confidence = smell_strength
       → propose dest from LOCATE-PROPER-HOME table below

     ELIF smell == progress-report (per-bead progress markdown):
       → move (to docs/progress/) AND propose gitignore-pattern (e.g., /progress_bd-*.md, /bd-*.md)
       → confidence = smell_strength

     ELIF smell == dual-format-asset:
       → For the unreferenced format: delete-no-gitignore
       → For the referenced format: keep-in-place
       → confidence = 0.95 if reference graph is unambiguous

     ELIF smell == 0-byte-stub AND n_refs == 0:
       → delete-no-gitignore, confidence = 0.85, evidence = "0-byte file with no inbound refs"

     ELSE:
       → surface-to-user, confidence = 0.5, evidence = "ambiguous: smell=<tags>, n_refs=<n>"
```

---

## LOCATE-PROPER-HOME table

This is the destination heuristic for the `move` verdict. It matches the categories used in the Apr-27 sessions.

| Smell / pattern | Default destination | Notes |
|-----------------|--------------------|-------|
| `*PLAN*.md`, `*PROPOSED*.md`, `*ARCHITECTURE*.md`, `*SPEC*.md` | `docs/planning/` | The single most-common destination |
| `multi-llm-plan-cluster` (`*__GPT.md`, `*__OPUS.md`, etc.) | `docs/planning/` | Move all variants together |
| `progress.md`, `progress_bd-*.md`, `bd-*.md` | `docs/progress/` | Plus `.gitignore` add |
| `*BENCHMARK*.md`, `PERFORMANCE_*.md` | `docs/planning/` (or `docs/benchmarks/` if exists) | Often referenced from README |
| `*RECOVERY*.md`, `*RUNBOOK*.md`, `OPERATIONS.md` | `docs/operations/` (or `docs/`) | |
| `*REVIEW*.md`, `*AUDIT*.md`, `*FINDINGS*.md` | `docs/audits/` (or `docs/planning/` if no audits dir) | |
| `*REFERENCE*.md`, `*INDEX.md`, `*PATTERNS.md` | `docs/reference/` | |
| `*_ARCHITECTURE_SUMMARY.txt` | `docs/reference/` | |
| `*GUIDE*.md`, `project_idea_and_guide.md` | `docs/planning/` | |
| `UPGRADE_LOG.md`, `CHANGELOG_AGENT_FRIENDLY.md` | `docs/planning/` (or `docs/operations/`) | NOT `CHANGELOG.md` — that stays at root |
| `TOON_INTEGRATION_BRIEF.md`, `*_INTEGRATION_BRIEF.md` | `docs/planning/` | |
| `RESEARCH_FINDINGS.md`, `OPPORTUNITY_MATRIX.md` | `docs/planning/` | |
| `EXISTING_*_STRUCTURE*.md` | `docs/planning/` | |
| `*-policy*.md` | `docs/policies/` (or `docs/`) | |
| Visualization Python (`*viz*.py`, `*visual*.py`) | `scripts/visualization/` | When part of a build pipeline |
| Deploy scripts (`deploy*.sh`) | `scripts/` (or `scripts/deploy/`) | |
| Coverage scripts (`coverage.sh`) | Already under `scripts/` usually; keep | |
| Top-level `*.toml` configs referenced by code with hardcoded paths | **Skip move** unless user confirms the larger surgery | The frankensqlite cat-C lesson |

If **no existing destination dir** matches: create the proposed dir as part of the move plan; ask user to confirm it before Phase 6.

---

## Confidence calibration

| Confidence | Meaning |
|-----------|---------|
| 0.95–1.00 | Multiple independent signals agree (smell + filename + content fingerprint + 0 inbound refs + archetype rule) |
| 0.85–0.94 | Two strong signals agree (e.g., smell + 0 refs) |
| 0.70–0.84 | One strong signal + one weak (e.g., smell strength 0.85 but reference-grep had ambiguous matches) |
| 0.60–0.69 | Surface to user — borderline |
| <0.60 | Force `surface-to-user`; do not auto-classify |

The Phase 5 categorized plan groups by verdict but sorts within each group by **confidence ascending** — the most ambiguous rows are most prominent for the user's eye.

---

## Per-evidence sample-format

Every triage row's `evidence` column should be a compact string the user can scan:

```
smell=skill-output;refs=0                         → high-confidence delete
smell=plan-doc;refs=2:README.md,scripts/build.sh  → move; rewrite refs in 2 files
smell=secret-suspect;file=signing-X.key;size=32   → Phase 2.5 secret-leak halt
smell=binary-elf;file=test_ptr;refs=0             → delete (binary, no refs)
smell=dual-format-asset;dup-of=illustration.webp  → delete .png; .webp is referenced
smell=scratch-script;refs=1:tests/conftest.py     → SURFACE-TO-USER (might be real test helper)
smell=sqlite-wal-shm;sibling=storage.sqlite3      → tied to the sibling's verdict
smell=archetype-protected;rule=Cargo.toml         → keep-in-place
smell=0-byte-stub;file=wrangler_version.txt;size=0 → delete (0-byte stub)
```

---

## Worked examples

### Example 1: `delete-and-gitignore` — clear ephemeral

```
candidate: storage.sqlite3
size: 12288
smell: sqlite-db (1.0)
content_fingerprint: SQLite format 3 magic at offset 0
n_refs: 0
verdict: delete-and-gitignore
confidence: 0.97
gitignore_pattern: /storage*.sqlite3*
evidence: "smell=sqlite-db;refs=0;dev-runtime DB"
```

### Example 2: `move` — long-form planning doc

```
candidate: COMPREHENSIVE_PLAN_FOR_DUMMY.md
size: 846000
smell: planning-doc (0.95) + multi-llm-plan-cluster (0.5)
n_refs: 4 (crates/X-harness/src/bin/spec_audit.rs:19; tests/rfc2119_audit.rs:13; tests/spec_authority.rs:55; tests/bd_4eue.rs:55)
verdict: move
proposed_dest: docs/planning/COMPREHENSIVE_PLAN_FOR_DUMMY.md
confidence: 0.92
evidence: "smell=planning-doc;refs=4;all are path constants — surgical Edit-tool rewrite"
```

### Example 3: `surface-to-user` — scratch script with one ref

```
candidate: scratch.py
size: 1200
smell: scratch-script (0.7)
n_refs: 1 (tests/conftest.py:5: `from scratch import helper_fn`)
verdict: surface-to-user
confidence: 0.55
evidence: "smell=scratch;refs=1:tests/conftest.py — possible test helper, NOT auto-deletable"
```

### Example 4: `gitignore-only` — wal/shm sibling already removed

```
candidate: storage.sqlite3-wal
size: 4096
smell: sqlite-wal-shm (1.0)
n_refs: 0
sibling_status: storage.sqlite3 verdict=delete-and-gitignore
verdict: delete-and-gitignore (tied to sibling)
gitignore_pattern: /storage*.sqlite3*  (covers both)
confidence: 1.0
```

### Example 5: `keep-in-place` — verify script

```
candidate: verify (no extension)
size: 487
smell: ad-hoc-test-fixture-stub (0.5)
content: shell script
n_refs: 3 (tests/ext_conformance.rs:4; README.md:116; README.md:556)
verdict: keep-in-place
confidence: 0.95
evidence: "smell=script;refs=3:tests+README;archetype-pattern: top-level verify entrypoint"
```

### Example 6: `protected` — Cargo.toml

```
candidate: Cargo.toml
size: 2400
smell: (none — but protected_globs contains it)
n_refs: many (every crates/* member)
verdict: protected
confidence: 1.0
evidence: "protected_globs:Cargo.toml"
```

### Example 7: secret-leak (Phase 2.5)

```
candidate: signing-77c6e768.key
size: 32
smell: secret-suspect (filename) + secret-leak (content: 32-byte non-printable)
n_refs: 0 (no reference; key was force-added)
provenance: introduced in 6de5816 "feat: Enhance file reservations..."
                pushed to origin: yes (in commit history of origin/main)
                exposure window: ~30 days
verdict: secret-leak (Phase 2.5 halt)
action: switch to INCIDENT-PLAYBOOK.md § Secret Leak
```

### Example 8: `move` — multi-LLM plan cluster

```
candidates (4):
  PLAN_TO_PORT_DUMMY__GPT.md
  PLAN_TO_PORT_DUMMY__OPUS.md
  PLAN_TO_PORT_DUMMY__GEMINI.md
  PLAN_TO_PORT_DUMMY__CODEX.md
shared smell: multi-llm-plan-cluster (0.95) + planning-doc (0.95)
n_refs: 1 (PLAN_TO_PORT_DUMMY__GPT.md is referenced from README.md:120 "Data source")
verdict: move (all 4)
proposed_dest: docs/planning/
confidence: 0.93
evidence: "smell=multi-llm-cluster;ref=README.md → __GPT variant; rewrite all 4 refs together"
```

---

## When the rubric is wrong

The rubric is statistical — every Phase 5 user-facing table is the human-in-the-loop check. If the user overrides a verdict:

- The override is captured in `user_overrides.tsv` with the user's stated reason
- The merged `triage.tsv` reflects the override
- If overrides change >5 verdicts, the merger re-asks for confirmation as a sanity check

If the same kind of override happens repeatedly across runs, surface it as skill feedback in Phase 11.

---

## A note on the "Cat C deferral" pattern

In the Apr-27 frankensqlite cleanup, 15 TOML contract files were technically eligible for `move` (they were long-lived config docs at the project root). But `REFERENCE-GREP` revealed they were referenced by hardcoded path constants in 20+ Rust source files — moving them would have required a much larger refactor.

**Codified rule:** When a candidate's reference graph has `≥10` source-code references AND those references use hardcoded path strings (not configurable paths), the verdict flips from `move` to `surface-to-user` with a recommendation to **defer the move** until the user wants to do the larger surgery. The plan output explicitly labels the category as deferred:

> ### C. MOVE to `docs/contracts/` — DEFERRED
> These TOML files are load-bearing config referenced by 20+ Rust files via
> hardcoded path strings. Moving requires updating those refs; recommend
> skipping unless user wants the larger surgery. **Default: leave at root.**

This is a feature, not a bug. A janitorial pass should make the obviously-junky things go away cleanly, not introduce build breakages chasing a nicer tree layout. The user can always come back later and tackle Cat C as a focused refactor.
