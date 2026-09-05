# Triage Rubric — How a Stash Earns Its Verdict

Every stash exits Phase 4 with exactly one verdict and an evidence string that backs it up. This document is the verdict-by-verdict rubric.

---

## Verdicts

| Verdict | Meaning | Default action |
|---------|---------|----------------|
| `superseded` | The stash's introduced symbols already exist on the primary branch with equivalent semantics | Phase 9 drop |
| `garbage` | The stash is a known-noise category (broken-by-other-agent / tree-reset / temp-pre-push / autostash with reflog) AND adds no novel surface | Phase 9 drop |
| `novel-and-accretive` | Fingerprint absent on primary, apply-check clean, content is a focused/defensive/test-only addition | Phase 6 apply |
| `partially-novel` | Apply-check finds rejects only on the superseded hunks; the novel hunks would still apply cleanly | Phase 7 split-apply |
| `novel-but-stale` | Fingerprint absent on primary BUT files referenced no longer exist OR apply-check fails on every hunk because the surrounding context drifted too far | Manual decision (default drop with note) |
| `unknown` | Triage couldn't classify with confidence ≥ 0.7 | Surface to user |

---

## Decision flow

```
For each stash n:

  1. FINGERPRINT extracts (functions, types, tests, fixture_strings, file_paths).

  2. If fingerprint is empty AND message matches a known-garbage pattern:
       → garbage, confidence 0.99
       → evidence: "message=<prefix>; empty fingerprint"

  3. APPLY-CHECK probe (`git apply --3way --check`):
       - exit 0       → apply_check = clean
       - exit nonzero → apply_check = reject (capture conflict files + line ranges)

  4. VERIFY-ON-MAIN:
       For each fingerprint symbol, search primary branch.
       Compute fingerprint_coverage = found / total.
       Compute file_existence_coverage = files_still_on_main / total_files.

  5. Classify:

     IF fingerprint_coverage >= 0.95 AND apply_check IN (clean, reject):
       → superseded, confidence 0.85 + 0.15*fingerprint_coverage
       → evidence: top 3 file:line citations
       → BUT first verify same_signature on the symbols — if a sample of
         3 introduced functions has different param lists on main, this
         is NOT supersession; flip to novel-but-stale or partially-novel.

     ELIF fingerprint_coverage <= 0.05 AND apply_check == clean:
       → novel-and-accretive, confidence 0.75 + 0.20*(1-fingerprint_coverage)
       → evidence: "no symbols found on main; apply-check clean"

     ELIF apply_check == reject AND any rejected hunks correspond to
          superseded symbols AND non-rejected hunks correspond to absent symbols:
       → partially-novel, confidence 0.70
       → evidence: per-hunk breakdown — which hunks superseded, which novel

     ELIF fingerprint_coverage <= 0.05 AND
          (file_existence_coverage <= 0.5 OR apply_check fails on every hunk):
       → novel-but-stale, confidence 0.70
       → evidence: "files X, Y removed from main; apply rejects all hunks"

     ELIF message matches garbage prefix AND fingerprint_coverage >= 0.5:
       → garbage (specifically: garbage-and-superseded), confidence 0.95
       → evidence: message + supersession proof

     ELSE:
       → unknown, confidence 0.60
       → flag for user review in Phase 5
```

---

## Garbage-prefix patterns

These message prefixes are presumptively garbage when they appear unmodified. Override only with strong novel-fingerprint evidence.

| Prefix regex | Meaning | Caveat |
|--------------|---------|--------|
| `^other-agent-broken` | Explicit label for known-broken state | Always garbage |
| `^temp-pre-push` | Paranoid save before a push | If push succeeded, content is on the remote — garbage |
| `^full-tree-reset-stash` | Stash created when an agent did `git stash; git reset --hard` | Almost always garbage — the user already abandoned this work |
| `^autostash` | Git's own auto-stash from `git pull --rebase` or `git rebase --autostash` | Recoverable from reflog; garbage in the stash list |
| `^pre-deadlock-fix` | Save before a destructive deadlock fix | Often the polished version landed — likely superseded |
| `^WIP on (no branch)` | Default `git stash` message on detached HEAD | Need fingerprint analysis; rarely garbage in itself |
| `^WIP on <deleted-branch>` | Stash from a branch that no longer exists | Often recoverable from `git reflog` for that branch — likely garbage in the stash list |
| `^stash@\{` | A doubly-stashed stash (rare) | Always inspect — usually a debugging artifact |

---

## Same-signature verification

A symbol existing on main is NOT proof of supersession. The skill must verify *equivalent semantics* by sampling.

**Quick same-signature heuristic** (per language):

```
Rust:
  Stash:  pub fn lock_until(deadline: Instant) -> Result<()>
  Main:   pub fn lock_until(deadline: Instant) -> Result<()>
  → same_signature = true

  Stash:  pub fn lock_until(deadline: Instant) -> Result<()>
  Main:   pub fn lock_until(deadline: Instant, retries: u32) -> Result<()>
  → same_signature = false; param list extended; the stash version may
    actually be a regression — flag for user review

TypeScript:
  Compare:
    - parameter count
    - parameter types (best-effort, parsed from the fn signature)
    - return type
  Don't compare body — that would require parsing semantics

Python:
  Compare:
    - argument count + names
    - default values
    - decorators (if @overload, fingerprint it as multiple)

Go:
  Compare:
    - parameter list (types and order)
    - return list
```

**When same_signature is false on >30% of sampled symbols**, flip the verdict:

- If the stash's version is *more restrictive* (fewer params, narrower types): likely a regression — flag for user review.
- If the stash's version is *less restrictive* (more params, broader types): likely an earlier draft — confirm superseded.
- If signatures diverge on names alone: someone renamed; treat as superseded if the renamed symbol exists.

`scripts/triage-batch.sh` performs only a lightweight same-name heuristic. For this full same-signature check, use manual review or the `language-specialist` subagent with ast-grep where the language has a tree-sitter grammar.

---

## Confidence calibration

| Confidence | Meaning |
|-----------|---------|
| 0.95–1.00 | Multiple independent signals agree (fingerprint + apply-check + same-signature + message-prefix) |
| 0.85–0.94 | Two strong signals agree (e.g., fingerprint + apply-check) |
| 0.70–0.84 | One strong signal + one weak (e.g., fingerprint coverage 0.95 but signatures unverified) |
| 0.60–0.69 | Surface to user — borderline |
| <0.60 | Force `unknown`; do not auto-classify |

The Phase 5 user-facing decision table groups by verdict but sorts within each group by confidence ascending — the most ambiguous rows are most prominent for the user's eye.

---

## Per-hunk evidence (for `partially-novel`)

When a stash is `partially-novel`, Phase 5 needs per-hunk detail so the user can confirm the split. The canonical `triage.tsv` produced by `triage-batch.sh` / `merge-triage.sh` stays on the six-column schema (`n`, `verdict`, `confidence`, `evidence_on_main`, `apply_check`, `fingerprint_summary`). Put a compact hunk summary in `evidence_on_main`; Comprehensive/manual workers may also write a sidecar `hunk_breakdown` JSON artifact for Phase 7:

```json
{
  "hunks": [
    {"id": 1, "file": "src/parser.rs", "lines": "120-145", "verdict": "superseded", "evidence": "src/parser.rs:120 same fn body"},
    {"id": 2, "file": "src/parser.rs", "lines": "200-218", "verdict": "novel", "evidence": "no match on main"},
    {"id": 3, "file": "tests/parser_corpus.rs", "lines": "1-50", "verdict": "novel", "evidence": "file new on stash"}
  ]
}
```

Phase 7's split-apply uses the sidecar when it exists; otherwise it re-fingerprints per hunk before creating the split diff. In the example above, keep hunks 2 and 3 and drop hunk 1.

---

## Examples

### Example 1: `superseded` (asupersync session, stash@{0})

```
n: 0
ref: stash@{0}
message: wip-BACK-1742-mutex-lock-until
fingerprint: { functions: ["lock_until", "recover_lock"], types: [], tests: [] }
verify_on_main:
  - lock_until: src/mutex.rs:317 ✓ same signature
  - recover_lock: src/mutex.rs:412 ✓ same signature
apply_check: clean (would apply but redundantly)
verdict: superseded
confidence: 0.97
evidence: "src/mutex.rs:317,412 — both fns present with same signatures"
```

### Example 2: `garbage` (asupersync session, stash@{67})

```
n: 67
ref: stash@{67}
message: other-agent-broken
fingerprint: { ... } # not even computed
verdict: garbage
confidence: 0.99
evidence: "message=other-agent-broken; explicit garbage label"
```

### Example 3: `novel-and-accretive` (asupersync session, stash@{34})

```
n: 34
ref: stash@{34}
message: wip-BACK-1742-mysql-ok-packet-defensive
fingerprint:
  functions: [defensive_ok_packet_length_cap, parse_ok_packet_safe]
  types: []
  tests: [test_ok_packet_length_overflow_returns_err]
  fixture_strings: ["\\x07\\x00\\x00\\x01\\xff\\xff\\xff\\xff\\xff\\xff"]
verify_on_main:
  - defensive_ok_packet_length_cap: NOT FOUND on main
  - parse_ok_packet_safe: NOT FOUND on main
  - test_ok_packet_length_overflow_returns_err: NOT FOUND on main
  - fixture string: NOT FOUND on main
apply_check: clean
verdict: novel-and-accretive
confidence: 0.92
evidence: "no symbols on main; apply clean; defensive guard + test"
```

### Example 4: `partially-novel`

```
n: 47
ref: stash@{47}
message: wip-BACK-1801-parser-refactor-and-fuzz-corpus
fingerprint:
  functions: [Parser::parse_v2, Parser::parse_legacy_v1]
  types: [ParserError]
  tests: [test_parser_v2_basic, test_parser_v2_overflow]
  fixture_strings: [<200 fuzz corpus entries>]
verify_on_main:
  - Parser::parse_v2: src/parser.rs:120 ✓ same signature (landed via PR #234)
  - Parser::parse_legacy_v1: NOT FOUND
  - ParserError: src/parser.rs:88 ✓ same enum variants
  - test_parser_v2_basic: tests/parser_test.rs:42 ✓ same body
  - test_parser_v2_overflow: NOT FOUND
  - fuzz corpus: NOT FOUND
apply_check: reject (3 of 8 hunks reject; the parser refactor hunks)
verdict: partially-novel
confidence: 0.81
hunk_breakdown:
  hunks 1-3 (parser refactor): superseded
  hunk 4 (parse_legacy_v1 deletion): superseded
  hunk 5 (test_parser_v2_overflow): novel
  hunks 6-8 (fuzz corpus files): novel
evidence: "parser refactor superseded by PR #234; novel hunks: overflow test + 200-entry fuzz corpus"
```

### Example 5: `novel-but-stale`

```
n: 88
ref: stash@{88}
message: wip-old-cli-flag-handling
fingerprint:
  functions: [Cli::parse_legacy_flags]
  types: [LegacyFlagSet]
  files: [src/cli/legacy.rs, src/cli/mod.rs]
verify_on_main:
  - Cli::parse_legacy_flags: NOT FOUND
  - LegacyFlagSet: NOT FOUND
  - src/cli/legacy.rs: FILE NOT ON MAIN
file_existence_coverage: 0.5 (mod.rs exists; legacy.rs gone)
apply_check: fail (every hunk rejects; can't find context)
verdict: novel-but-stale
confidence: 0.85
evidence: "src/cli/legacy.rs no longer exists on main; clearly part of an
abandoned refactor branch. Apply impossible without rewriting against new
CLI architecture in src/cli/parse.rs."
```

---

## When the rubric is wrong

The rubric is statistical — every Phase 5 user-facing table is the human-in-the-loop check. If the user overrides a verdict:

- The override is captured in `user_overrides.tsv` with the user's stated reason
- The merged `triage.tsv` reflects the override
- If overrides change >5 verdicts, the merger re-asks for confirmation as a sanity check

If the same kind of override happens repeatedly across runs, surface it as skill feedback in Phase 11.
