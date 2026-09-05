# Backporting — Applying The Fix To Older Supported Versions

> **This file is advisory-only.** The user's mined release model is **forward-only**
> ([RELEASE-FORWARD-ONLY.md](RELEASE-FORWARD-ONLY.md), [REMEDIATION-PRINCIPLES.md
> §Principle 5](REMEDIATION-PRINCIPLES.md)) — the default response to a downstream
> "we're stuck on v1.3" request is "upgrade to v1.5; that's where the fix landed."
> The playbook below applies only when an OSS-with-paying-customers support policy
> explicitly mandates per-minor-version maintenance, or when a downstream user makes
> a compelling, time-bounded case for a backport (e.g., a security advisory window).
> If you're not in one of those cases, follow forward-only and skip this file.

When Phase 7 confirms UB in HEAD and bisection shows it was introduced in v1.0 (and HEAD is v1.5), all of v1.0..v1.5 have the bug. If v1.4 and v1.3 are still supported, the remediation must backport.

This file is the backport playbook.

---

## When backporting applies

| Situation | Backport? |
|---|---|
| You ship a `*-sys` or `*-core` crate with downstream users | Yes |
| You ship a `1.x` line and a `2.x` line | Yes — usually only most recent N minor versions of each major |
| You ship internally; everyone uses latest | No |
| You're an OSS maintainer following semver | Yes — per your support policy |

The standard Rust ecosystem expectation is: the most recent minor version of each major series, going back ~12 months.

---

## Backport candidate identification

After Phase 8 lands the HEAD remediation:

1. Run `git tag --merged HEAD --sort=-creatordate | head -20` to list recent versions.
2. For each version with `MAJOR < HEAD_MAJOR` or `MINOR < HEAD_MINOR - N` (N being your support policy):
   - Materialize a non-git archive snapshot under `<workspace>/phase5_experiment_results/backport_<EXP>_snapshots/`
   - Run the EXP-NNN reproducer against the snapshot
   - If UB reproduces → backport candidate
3. Group candidates by which can share a single backport commit (often v1.4 and v1.3 can share).

Output: `phase8_backport_candidates.md` with:
```markdown
| Version | UB confirmed? | Notes |
|---|---|---|
| v1.4.0 | YES | Identical pattern to HEAD; backport applies cleanly |
| v1.3.2 | YES | Pattern present but in different function; backport requires adaptation |
| v1.2.5 | NO | Pre-introduction; bisection landed at v1.3-rc1 |
```

---

## Backport commit hygiene

Each backport branch should:
- Cherry-pick the HEAD remediation if it applies cleanly
- Otherwise, write a separate backport PR with the *minimal* fix (don't backport refactors)
- Include the regression test from the original EXP-NNN
- Update the version's CHANGELOG.md citing the original advisory ID

Branch naming: `backport/v1.4.x` for the 1.4 line, etc.

Commit message:
```
backport: fix <UB shape> reachable from <fn>

Backport of <HEAD-commit-hash>: <one-line>.

The HEAD remediation rewrites <module>; this backport applies the
minimal fix at <file:line> without the rewrite. Functional equivalence
verified by running the regression test (tests/regression/exp_007.rs)
under MIRIFLAGS="-Zmiri-tree-borrows".

Refs: <advisory-id> / <issue-link>
```

---

## Testing the backport

The backport must pass the same regression test as HEAD. Run Phase 3 dynamic sweep against the backport branch:

```bash
git switch backport/v1.4.x
MIRIFLAGS="-Zmiri-tree-borrows" cargo +nightly miri test --test regression_exp_007
```

If the test fails, the backport didn't fix the UB on this branch. Iterate.

For each backport branch, run the full MIRIFLAGS matrix. Sanitizers and loom are optional for backports (the minimal-fix policy says: prove the targeted UB is fixed, don't re-audit the branch).

---

## Multi-branch publication

Once all backports pass:

1. **Tag each backport** with a patch version: `v1.4.6`, `v1.3.5`, etc.
2. **Publish in semver order** — oldest first. This way downstream users on v1.3 can `cargo update` to v1.3.5 without being pushed to v1.4.
3. **Yank the unpatched versions** if the UB is CVSS ≥ 7.0:
   ```bash
   cargo yank --vers 1.4.5
   cargo yank --vers 1.4.4
   # ... down through the introducing version
   ```
4. **One advisory references all patched versions.** The RustSec template's `patched_versions` field is a list:
   ```toml
   patched_versions = [">= 1.5.3", ">= 1.4.6, < 1.5.0", ">= 1.3.5, < 1.4.0"]
   ```

---

## Common backport gotchas

### B-G1 — The bug existed but the API didn't

If `pub fn buggy_fn` was added in v1.4 and you're trying to backport to v1.3, there's nothing to backport. Document: "v1.3 does not expose buggy_fn; no action needed".

### B-G2 — The fix depends on a newer stable Rust feature

The HEAD remediation uses `AtomicU64::from_ptr` (stable in 1.84) but v1.3's MSRV is 1.65. Options:
- Bump v1.3's MSRV with a minor version (only OK per your policy)
- Backport a different remediation (operator `⊕ REWRITE` again — score the v1.3-compatible alternatives)
- Skip the backport; require users to upgrade to v1.4

### B-G3 — The fix conflicts with v1.x-only feature flags

If `feature = "legacy-mode"` only exists in v1.x, the backport must handle both code paths.

### B-G4 — Multiple unrelated changes in the HEAD commit

If the HEAD remediation was bundled with other changes (refactor + soundness fix), git cherry-pick brings the lot. Use `git cherry-pick -n <commit>` and then `git reset HEAD <unrelated-files>` to keep just the soundness fix.

### B-G5 — The HEAD CHANGELOG marks the change as "breaking"

A backport must not introduce a breaking change. If the fix is necessarily breaking (e.g., a public function had to be removed because it was inherently unsound), the backport may *yank without replacement*. Document explicitly.

---

## Backport priority order

When you have N backport branches, work on them in this order:

1. **Most recent first** — if v1.4.5 is what most users are on, fix it before older versions
2. **LTS branches before non-LTS** — if you mark certain versions as Long Term Support, those have priority
3. **Versions with active downstream users** — `crates.io/api/v1/crates/<crate>/owners` or similar to find who depends on you; reach out to the highest-traffic downstreams to coordinate

---

## Automation

`scripts/backport-runner.sh` (Phase 8 helper if installed) automates the per-branch check:

```bash
./scripts/backport-runner.sh <repo> EXP-007 v1.4.5 v1.3.4 v1.2.7
# For each version: archive snapshot, run reproducer, report PASS/FAIL/SKIP.
# If a version is NOT affected, skip; if affected, file as backport candidate.
```

---

## Backport bead structure

In Phase 9, each backport becomes a *sub-bead* of the parent remediation:

```
br-201 [remediation] Fix UB at btree.rs:412 (HEAD)
  br-202 [test] Add regression test
  br-203 [docs] Update SAFETY comment
  br-204 [backport] Apply fix to v1.4.x
    br-205 [test] Regression test passes on v1.4.x
  br-206 [backport] Apply fix to v1.3.x
    br-207 [test] Regression test passes on v1.3.x
  br-208 [disclosure] File RUSTSEC-YYYY-XXXX
```

Phase 9 polish ensures each backport bead has its own test + docs sub-beads.

---

## When NOT to backport

- The UB requires a usage pattern that didn't exist in the older version's API
- The UB is in a feature flag that wasn't shipped in the older version
- The fix is *substantively riskier* than the bug (e.g., a major refactor that you can't realistically test in a 7-day disclosure window)

In these cases, the disclosure advisory says: "Affected versions: 1.0..1.5. Mitigations: upgrade to 1.5.6 OR avoid <pattern>".

---

## Long-term cleanup

Backport branches accumulate. After your support policy's end-of-life for v1.3:

- Stop publishing v1.3.x patches
- Update CHANGELOG.md / SUPPORT.md to mark v1.3 EOL
- Archive the backport branches (`git tag archive/v1.3.x-eol` then delete branch)
- Update the runbook: future audits don't need to backport to v1.3

This is fully covered by [LIFECYCLE.md](LIFECYCLE.md).
