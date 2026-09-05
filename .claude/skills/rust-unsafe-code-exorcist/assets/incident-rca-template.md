# Incident RCA — <INCIDENT-ID>

Copy to `<audit-dir>/incident-rca.md` at the start of a `harden-incident` run.
Per [INCIDENT-RESPONSE-PLAYBOOK.md](../references/methodology/INCIDENT-RESPONSE-PLAYBOOK.md).

---

## Metadata

- **Incident ID.** <CVE-2026-NNNN / GHSA-xxxx-xxxx-xxxx / internal tracker ID>
- **Severity.** <Critical | High | Medium | Low>
- **Reported.** <YYYY-MM-DD> by <reporter / source>
- **Affected versions.** <semver range>
- **Patched version.** <semver, once fix lands>

---

## 1. CONTAINMENT (Phase 1 actions)

| Action | Timestamp | Notes |
|--------|-----------|-------|
| Yanked vulnerable version from crates.io | <YYYY-MM-DD HH:MM UTC> | `cargo yank --vers X.Y.Z` ran by <user>. |
| Posted placeholder advisory | <YYYY-MM-DD HH:MM UTC> | RustSec advisory ID `<RUSTSEC-2026-NNNN>`. |
| Notified known downstream consumers | <YYYY-MM-DD HH:MM UTC> | <list of orgs/users, by GitHub handle>. |
| Stopped active deployment | <YYYY-MM-DD HH:MM UTC> | <details if applicable, or "n/a — not in our deployment">. |

---

## 2. REPRODUCTION (Phase 2)

**Reproducer.** `tests/regression_<incident-id>.rs`

```rust
//! Regression test for <INCIDENT-ID>.
//!
//! Symptom: <one-line>
//! Affected versions: <semver>

use mycrate::*;

#[test]
fn regression_<incident_id>() {
    let trigger = vec![/* ... */];
    let result = mycrate::affected_fn(&trigger);
    assert_eq!(result, Ok(expected));   // would fail on the buggy version
}
```

**Verified.** FAILS on commit `<pre-fix-hash>`; PASSES on commit `<post-fix-hash>` (once fix lands).

**Environment.**

- rustc: <version + verbose output>
- target: <triple>
- features: <enabled>
- OS: <platform>

**Minimization log.** <describe the path from the reporter's original repro to the minimal one>.

---

## 3. ROOT CAUSE (Phase 3)

### Affected code

```rust
// At <file>:<line>, version <X.Y.Z>:
<verbatim source of the affected block>
```

### Invariant violated

The unsafe block at <file>:<line> assumes:

- <INVARIANT-1>
- <INVARIANT-2>

### How the invariant was violated

- <Specific path the buggy code took: caller violated INVARIANT-1 by passing X;
   the unsafe block proceeded anyway because the precondition wasn't enforced>.

### Why we didn't catch it earlier

- **Tests.** <Why didn't the test suite catch this?>
- **miri.** <Why didn't miri catch this? — possibly because of strict-provenance not enabled, or the input class wasn't exercised>.
- **fuzz.** <Why didn't fuzz catch this? — possibly because there was no fuzz target on the relevant pub surface>.
- **Code review.** <Why didn't review catch this? — possibly because the SAFETY comment was stale / vague / missing>.

### 5 whys

1. <Why did the user hit the bug?> — <answer>
2. <Why did the bug exist?> — <answer>
3. <Why was the unsafe written this way?> — <answer>
4. <Why didn't the audit catch it?> — <answer>
5. <Why didn't our process catch it?> — <answer; this is the meta-cause>

### Meta-cause

<One-paragraph: was this a "missing test" issue? A "SAFETY comment stale" issue? A "macro-generated unsafe never reviewed" issue? The meta-cause informs the EXPAND phase.>

---

## 4. FIX (Phase 4)

### Approach

- (A | B | C) classification: <bucket>
- Plan: `audit/plans/site-<id>.md`
- Approach: <one-sentence>

### Active-checkout fix

- Branch / commit: `unsafe-exorcist-incident-<id>` or `<commit-sha>`
- PR: <URL>
- Status: <open | merged>

### Tests added

- `tests/regression_<incident-id>.rs` (failure-mode reproducer)
- `tests/equivalence_site_<id>.rs` (property-based equivalence test)
- (where applicable) loom / fuzz / kani harnesses

### Verification

- `cargo test`: <result>
- `cargo +nightly miri test` (default + strict-provenance + tree-borrows): <result>
- `cargo +nightly careful test`: <result>
- loom: <result, if applicable>
- cargo fuzz: <result, if widened pub surface>
- cargo mutants: <coverage %>
- cargo +nightly geiger: <delta>

---

## 5. RELEASE

- New version: vX.Y.Z+1
- Release date: <YYYY-MM-DD>
- Advisory resolved: <URL>
- CHANGELOG entry: <link to commit>
- Postmortem (public-facing): <URL>

---

## 6. EXPAND (Phase 5)

Following the incident's meta-cause, an EXPAND audit was scheduled:

- **Scope.** <Which areas of the codebase share the meta-cause's failure pattern?>
- **Mode.** `audit-only` against <crates>.
- **Outcome.** <Findings; new beads filed; etc.>

### Skill updates

- New `[E-NNN]` entry added to `EXEMPLAR-CATALOG.md`: <link>
- New `F-NNN` entry added to `COMMON-FAILURE-CASES.md`: <link>
- (If applicable) new operator card in `OPERATORS.md`: <link>

The audit's institutional memory has grown by this incident's lesson.

---

## Sign-off

- Incident closed: <YYYY-MM-DD>
- Closed by: <user>
- Post-incident review: <link to discussion/meeting>
- Follow-up beads: <list of beads that the EXPAND audit filed>
