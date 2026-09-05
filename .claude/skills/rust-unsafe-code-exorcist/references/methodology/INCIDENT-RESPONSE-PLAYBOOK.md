# INCIDENT-RESPONSE-PLAYBOOK.md — Soundness-Incident Workflow

When a soundness incident lands (CVE, miri finding from a user, production crash linked to UB, fuzz finding from an external party), the normal `audit-only` cadence is too slow. The skill's `harden-incident` mode is the response workflow.

This file is the per-incident playbook.

---

## 5-phase shape

```
1. CONTAIN    Stop the bleed. Bound the blast radius.
2. RECONSTRUCT  Reproduce on a controlled environment.
3. ROOT-CAUSE  First-principles trace. Why did it happen?
4. FIX-AND-REGRESS  Minimum-blast-radius fix + regression test.
5. EXPAND   After the incident closes, run a full audit-only to find adjacent risks.
```

Each phase has explicit go/no-go gates.

---

## Phase 1 — CONTAIN

**Goal.** Reduce active customer / user exposure.

**Actions (in order).**

1. **Pin the affected version.** Yank from crates.io if the affected version is shipping (`cargo yank --vers X.Y.Z`). Cite the security advisory ID in the yank reason.
2. **Publish a placeholder advisory.** GitHub Security Advisory Database / RustSec / CVE — even a stub with "investigation in progress" is better than silence.
3. **Notify known downstream consumers.** If the crate has a `users:` list or known major dependents, ping them — they need to know.
4. **Stop the active deploy.** If the affected version is in production at the user's company, prevent further rollouts until the fix lands.

**Time budget.** ~30 minutes. Speed > thoroughness.

**Output.** `<audit-dir>/incident-rca.md § Containment` with timestamped actions.

---

## Phase 2 — RECONSTRUCT

**Goal.** Reproduce the incident on a controlled environment.

**Actions.**

1. **Verify the report.** Run the reporter's test case on a fresh checkout of the affected version.
2. **Minimize.** Cut the test case down to the smallest reproducer (typically `cargo test --test repro_<incident_id>`). Use `cargo bisect-rustc` if the bug appears in some compiler versions but not others; use `cargo bisect-commit` to find the first project commit that introduced it.
3. **Pin the reproducer.** Add a regression test file at `tests/regression_<incident_id>.rs` that FAILS on the affected version.
4. **Capture environment.** `rustc --version --verbose`, `cargo --version`, target tuple, relevant feature flags — into `<audit-dir>/incident-rca.md § Reproduction environment`.

**Time budget.** ~1-3 hours, depending on how deterministic the bug is.

**Output.** `tests/regression_<incident_id>.rs` failing on the affected version + reproduction notes.

**Gate to Phase 3.** The regression test FAILS on the affected version AND PASSES on at least one historical commit (so we know it was once OK).

---

## Phase 3 — ROOT-CAUSE

**Goal.** First-principles answer to "why did this happen?"

**Actions.**

1. **Identify the unsoundness.** Which invariant was violated? Which `unsafe` block held the invariant? Was it the unsafe's own logic, or a caller violating the proof obligation?
2. **Trace the call graph.** Walk from the bug's symptom site back to the unsafe site, then forward from the unsafe site to all current callers. Are there other callers that could ALSO trigger this?
3. **Run the relevant operators.** Especially:
   - ⊙ Invariant-Locator (what was the invariant)
   - ⊕ Reachability-From-Safe (can a safe public API also reach this state)
   - ⚖ Send-Sync-Audit (if the bug is a data race)
   - 🔁 Async-Cancellation-Trace (if the bug is in an async path)
   - 🪟 FFI-Boundary-Contract (if FFI is involved)

4. **5 whys.** Don't stop at "the unsafe was wrong." Why did the unsafe pass review? Why did miri / fuzz / loom not catch it? Why did the caller violate the invariant?
5. **Find the meta-cause.** Was this a "missing test" issue? A "SAFETY comment was wrong" issue? A "macro-generated unsafe never reviewed" issue? The meta-cause informs the EXPAND phase.

**Output.** `<audit-dir>/incident-rca.md` with:
- Symptom description
- Reproducer
- Affected code (verbatim, with line numbers)
- Invariant violated (per operator ⊙)
- Why it wasn't caught
- 5-whys analysis
- Meta-cause

**Gate to Phase 4.** The RCA cites a specific invariant + a specific failure mode. "It was buggy" is not enough.

---

## Phase 4 — FIX-AND-REGRESS

**Goal.** Land the minimum-blast-radius fix + the regression test that pins the behavior.

**Actions.**

1. **Draft the fix in the audit dir first.** Per the skill's normal Phase 5 workflow: full safe rewrite (if it's a (C) site that the incident reveals), or hardened SAFETY + lint (if it's a (A) site where the caller violated the proof obligation), or feature flag (if it's a (B) safety-vs-perf trade the audit reveals must shift).
2. **Property-based equivalence test.** Even for a single-incident fix, the test must cover the failure-mode inputs (per [10-POINTER-MIGRATIONS.md § Equivalence-proving patterns](../patterns/10-POINTER-MIGRATIONS.md)).
3. **Run the harness.** miri + careful + loom + fuzz + mutants + geiger. The fix must close the regression test AND keep all other tests green.
4. **Phase 7 fresh-eyes review.** The three verbatim prompts. The fix is small but high-stakes; don't skip.
5. **Active-checkout fix.** Per `harden-incident` mode, the fix lands in the project repo via the active checkout or an ordinary branch (per [WORKTREE-REFACTOR-PROTOCOL.md](WORKTREE-REFACTOR-PROTOCOL.md)); git worktrees are forbidden.
6. **Ship.** Cut a new release with the fix. Update the security advisory from "investigation" to "resolved in version X.Y.Z+1".

**Time budget.** ~half day to a day.

**Output.** Merged PR + new release + closed advisory + regression test pinned in `tests/regression_<incident_id>.rs`.

**Gate to Phase 5.** Advisory is closed; users have a fixed version available.

---

## Phase 5 — EXPAND

**Goal.** Use the incident's meta-cause to find adjacent risks.

**Actions.**

1. **Search for the same shape elsewhere.** If the incident was "FFI caller violated null-termination invariant," grep / ast-grep for every other `extern "C"` call and check whether each has the same proof obligation. If the incident was "unsafe impl Send on a raw-pointer field," audit every `unsafe impl Send`.
2. **Spawn a full audit-only run.** Now that the incident is contained, do the broad audit that wasn't urgent enough during the fire. Use the meta-cause to inform the audit's emphasis bundle.
3. **Update the skill itself.** If the incident revealed a pattern the exemplar catalog didn't have, add a new `[E-NNN]` entry to `EXEMPLAR-CATALOG.md`. If a new operator would have helped, propose one for `OPERATORS.md`. The skill's institutional memory grows.
4. **Postmortem.** Write a public-facing postmortem (template at `assets/incident-rca-template.md`). What happened, what we fixed, what we're doing differently. Users appreciate transparency.

**Time budget.** Days to weeks, depending on the size of the EXPAND audit.

**Output.** A full `audit-only` artifact + an updated skill + a postmortem.

---

## Per-incident artifacts

A `harden-incident` run produces, at minimum:

| Artifact | Path |
|----------|------|
| RCA | `<audit-dir>/incident-rca.md` |
| Regression test | `tests/regression_<incident_id>.rs` (in project repo) |
| Reproducer / minimization log | `<audit-dir>/incident-repro.md` |
| Fix commit / PR | `<commit SHA or GitHub URL>` |
| Updated SAFETY / lint | per `audit/plans/site-<id>.md` |
| Advisory | `<URL>` |
| Postmortem | `<github URL or blog post>` |
| Updated EXEMPLAR-CATALOG (if applicable) | `references/source/EXEMPLAR-CATALOG.md` |

The audit-summary line for the incident mode reads:

```
INCIDENT MODE: <incident-id>
Symptom:  <one-line>
Fix:      shipped in version <X.Y.Z+1>
Advisory: <URL> (resolved)
Adjacent risks found in expand audit: <count>
Skill updated: yes/no (new pattern <E-NNN> added)
```

---

## Anti-patterns

- **Fix without RCA.** A fix that "looks right" but doesn't trace the invariant violation might re-introduce the bug elsewhere.
- **Widening fix scope to cleanup adjacent code.** Resist. The incident fix is the incident fix. Adjacent cleanup goes in the EXPAND audit.
- **Skipping the regression test.** Without it, the fix can regress in a future refactor without anyone noticing.
- **Skipping the postmortem.** Users see "version X.Y.Z+1 fixes a security issue" — without a postmortem, they don't know what was at risk or whether they were exposed.
- **Folding the incident fix into an unrelated feature PR.** Per AGENTS.md no-batch principle. The fix is its own PR; the advisory references that PR by hash.

---

## Composability

The `harden-incident` mode COMPOSES with `audit-only`. After the incident closes, the orchestrator automatically transitions to a full `audit-only` (Phase 5 — EXPAND). The orchestrator's mode-transition prompt:

```
The incident at <incident-id> is now closed (fix shipped in <version>).
Transitioning to audit-only mode. The meta-cause from incident-rca.md will
inform the emphasis-bundle selection for the full audit.
```

This is the skill's institutional-learning loop in action.
