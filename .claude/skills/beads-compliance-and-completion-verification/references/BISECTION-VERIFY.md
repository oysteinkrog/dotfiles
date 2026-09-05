# BISECTION-VERIFY.md — Localize a bead-score regression to a single commit

A bead that scored 880 last pass and 540 this pass has a story. Maybe its tests broke; maybe a sibling refactor invalidated its evidence; maybe a dependency upgrade silently regressed behavior. The author insists "I didn't touch that code." We don't litigate; we bisect.

`scripts/bisect-regression.sh` automates `git bisect` using `single-bead-audit.sh` as the test predicate. The output is the offending commit (with author, date, body, files changed) and a full bisect log under the audit dir.

---

## When to invoke

- A pass-over-pass diff (`scripts/diff-passes.sh`) shows a score drop ≥ 100 points on a single bead.
- A bead toggles from PASS → FALSE-CLOSED across two consecutive passes with no remediation in between.
- A `release-gate-keeper` NO-GO blocker cites a recently-regressed bead.
- A user explicitly asks "what broke `bd-foo`?".

---

## How it works

```
GOOD SHA (last pass with score ≥ threshold)        BAD SHA (current pass with score < threshold)
       ●---------------------------------------------●
                              |
                       git bisect mid
                              |
                              ▼
                    [worktree at mid SHA]
                              |
                  single-bead-audit.sh runs Phases 1-8
                              |
                  exit 0 → mark good      exit 2 → mark bad
                              |
                       git bisect step
                              |
                              ▼
              loop until single offending commit found
```

The bisect uses a **dedicated worktree** — never the project's main working tree. Other agents on the project keep working; the bisect runs in isolation under `/tmp/`. Cleanup is automatic via `trap EXIT`.

---

## Auto-detection of GOOD / BAD endpoints

`bisect-regression.sh` walks `passes/<UTC>/manifest.json` and reads `project_sha` (or `as_of_sha` for time-machine passes) — the SHA of the project at the time each pass ran.

- **GOOD** = the most recent pass where the bead's score was ≥ threshold.
- **BAD** = the most recent pass where it was < threshold.

If `project_sha` is missing from the manifest (older pass format), the user must pass `--good <sha> --bad <sha>` explicitly. Fix the gap by upgrading `bootstrap-audit.sh` to record `project_sha` going forward.

---

## Predicate cost

Each bisect step runs Phases 1-8 of `single-bead-audit.sh` — typically 30-90 seconds for a single bead in a project with a fast test suite. For 10 commits between GOOD and BAD, that's ~5 bisect steps and ~5 minutes total. For 1000 commits, ~10 steps and ~10 minutes.

For projects with slow tests, the predicate gets expensive. Mitigations:

- Pass `--mode triage` to skip Phase 4 test re-run; rely on Phase 5 + 6 alone. Less reliable but fast.
- Use `--bead-id <id> --skip-phases 4,6` (future flag — not yet implemented; documented for the rubric-tuning agent to consider).
- Pre-warm the cache: build the project once with `cargo build --release` against the BAD SHA before bisect starts.

---

## Output: `<audit-dir>/bisect/<bead-id>/`

```
bisect/
└── bd-billing-webhook/
    ├── bisect_log.txt           # full git-bisect log
    ├── predicate.log            # per-step single-bead-audit output
    └── run_<sha>/               # per-step audit pass dirs (for forensics)
        ├── manifest.json
        ├── REPORT.md
        └── beads/bd-billing-webhook/
            └── ...
```

---

## Worked example

```
$ ./scripts/bisect-regression.sh /data/projects/foo bd-billing-webhook
Bisecting bead bd-billing-webhook:
  good (score ≥ 700): 8a7bc4e9d1
  bad  (score <  700): 3f2c1ab498
Bisect worktree: /tmp/foo__bisect_bd-billing-webhook__1746547200
Bisecting: 6 commits between bounds
--- testing 7d4e8b1a... ---
GATE: PASSED (score=820)
--- testing 5c2f9b8e... ---
GATE: BLOCKED (score=540)
--- testing 9a3d6e7c... ---
GATE: BLOCKED (score=580)
…

=== Offending commit ===
commit 9a3d6e7c5b4a8d9e0f1c2b3a4d5e6f7
Author:    alice <alice@example.com>
AuthorDate: 2026-05-04T11:22:00Z
Commit:    bot <ci@example.com>
CommitDate: 2026-05-04T11:23:14Z

    refactor(stripe): unify webhook signature helpers (#412)

    Consolidates HMAC verification across stripe + paypal flows. No
    functional changes intended.

=== Files changed ===
 src/billing/webhook.ts | 18 ++++++++----------
 src/billing/utils.ts   |  2 ++
 2 files changed, 10 insertions(+), 10 deletions(-)

Bisect complete. Offending commit: 9a3d6e7c5b4a8d9e0f1c2b3a4d5e6f7
Full log: /data/projects/foo/beads_compliance_audit/bisect/bd-billing-webhook/bisect_log.txt
```

The "no functional changes intended" commit body is a tell — the refactor changed something. Now the team can read 10 lines of diff instead of 1000.

---

## False-positive guards

`bisect-regression.sh` marks a step as `skip` (not `bad`) if the predicate exits with a code other than 0 or 2 — typically a build failure or environment glitch. Skipped commits are excluded from the bisect; if too many skip, git-bisect aborts with "no candidate left." When that happens:

1. Inspect `predicate.log` for the cause.
2. If transient (network, flaky test), re-run.
3. If structural (build infra changed), use `--good` / `--bad` to narrow to a known-clean range.

---

## When NOT to bisect

- The bead's score didn't change (false alarm in `diff-passes.sh`).
- The change is from rubric tuning, not project regression. `convergence-check.py` flags `rubric_changed_since_prior_pass: true` — re-score under the new rubric before bisecting.
- The "regression" is a bead that was correctly false-closed previously (its score was inflated) — bisect would chase the wrong target.
- The bead is `closed` AND its `closed_at` is older than the GOOD SHA — the regression is in the audit infrastructure, not the project code.

---

## Operator pairing

`⊟ BISECT` (added in this expansion) is the operator for this section. It pairs with `⊿ DISCRIMINATE` (which kind of regression are we chasing — implementation, test, environment, audit?) — discriminate first, bisect second.
